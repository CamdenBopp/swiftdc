import Ccapstone
import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private func packedExpectations() throws -> [(String, String)] {
    try String(contentsOfFile: "Fixtures/Sample/packedarithmetic.s", encoding: .utf8)
        .split(separator: "\n").filter { $0.hasPrefix("// EXPECT ") }.map {
            let parts = $0.split(separator: " ")
            return (String(parts[2]), String(parts[3]))
        }
}

private let packedFixture = "Fixtures/Sample/libPackedArithmetic.dylib"

private func packedFunctions(_ filter: String?) async throws -> [DisassembledFunction] {
    try await withStableDependencies {
        try await Disassembler().disassemble(path: packedFixture, functionFilter: filter)
    }
}

@Test func packedArithmeticDoesNotCarryBetweenIndependentLanesIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: packedFixture) else { return }
    let functions = try await packedFunctions("PackedProbe")
    let expected = try packedExpectations()
    try #require(expected.count == 54)
    try #require(functions.count == expected.count)
    for (name, value) in expected {
        let matches = functions.filter { $0.displayName.hasPrefix("PackedProbe.\(name)(") }
        let function = try #require(matches.count == 1 ? matches.first : nil)
        let state = ValueTracer().finalState(of: function.instructions)
        if value == "?" {
            #expect(state["x0"] == nil || state["x0"] == .unknown, Comment(rawValue: name))
        } else if let integer = UInt64(value) {
            #expect(state["x0"] == .immediate(integer), Comment(rawValue: name))
        } else {
            #expect(state["x0"] != nil && state["x0"] != .unknown, Comment(rawValue: name))
        }
    }
}

@Test func packedArithmeticIsDeclinedInWholeAndFilteredRenderersIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: packedFixture) else { return }
    let expected = try packedExpectations()
    for filter: String? in [nil, "PackedProbe"] {
        let functions = try await packedFunctions(filter)
        let selected = functions.filter { $0.displayName.hasPrefix("PackedProbe.") }
        try #require(selected.count == expected.count)
        for (name, value) in expected {
            let matches = selected.filter { $0.displayName.hasPrefix("PackedProbe.\(name)(") }
            let function = try #require(matches.count == 1 ? matches.first : nil)
            for output in [function.renderPseudo(), function.renderStructured()] {
                let returns = output.split(separator: "\n").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }.filter { $0.hasPrefix("return ") }
                if value == "known" {
                    #expect(returns.count == 1 && returns[0] != "return ?", Comment(rawValue: output))
                } else {
                    #expect(returns == ["return \(value)"], Comment(rawValue: output))
                }
            }
        }
    }
}

@Test func scalarSemanticTableDoesNotInterpretPackedMultiply() throws {
    // clang-assembled mul v0.8b,v1.8b,v2.8b and mul x0,x1,x2.
    let words: [UInt32] = [0x0e229c20, 0x9b027c20]
    let engine = try #require(CapstoneEngine())
    let decoded = engine.disassemble(words.withUnsafeBytes { Data($0) }, address: 0x1000)
    try #require(decoded.count == 2)
    let packed = try #require(decoded[0].detail)
    let scalar = try #require(decoded[1].detail)
    #expect(packed.id == AARCH64_INS_MUL)
    #expect(packed.operands[0].vectorArrangement == AARCH64LAYOUT_VL_8B)
    #expect(InstructionSemantics.effect(of: packed) == nil)
    #expect(InstructionSemantics.effect(of: scalar) != nil)
}

@Test func packedGuardsPreserveScalarStackAndFloatingForms() throws {
    let engine = try #require(CapstoneEngine())
    func decode(_ words: [UInt32]) throws -> [Instruction] {
        let decoded = engine.disassemble(words.withUnsafeBytes { Data($0) }, address: 0x1000)
        try #require(decoded.count == words.count)
        return decoded.map { Instruction(address: $0.address, text: $0.text, detail: $0.detail) }
    }
    // Actual AND-immediate permits SP as a scalar destination.
    let stack = try decode([0xd28005e5, 0x927cecbf])
    #expect(InstructionSemantics.effect(of: try #require(stack[1].detail)) != nil)
    #expect(ValueTracer().finalState(of: stack)["sp"] == .immediate(32))
    // Two scalar FMOV immediates, FADD, FNEG at H/S/D widths. Packed .2s
    // may also decode at width64, so these controls pin the arrangement too.
    for words: [UInt32] in [
        [0x1ee01001, 0x1ee01002, 0x1ee22820, 0x1ee14000],
        [0x1e201001, 0x1e201002, 0x1e222820, 0x1e214000],
        [0x1e601001, 0x1e601002, 0x1e622820, 0x1e614000],
    ] {
        let instructions = try decode(words)
        #expect(instructions[2].detail?.operands[0].vectorArrangement == AARCH64LAYOUT_INVALID)
        #expect(instructions[3].detail?.operands[0].vectorArrangement == AARCH64LAYOUT_INVALID)
        let add = ValueTracer().finalState(of: Array(instructions.prefix(3)))["v0"]
        let neg = ValueTracer().finalState(of: instructions)["v0"]
        #expect(add != nil && add != .unknown)
        #expect(neg != nil && neg != .unknown)
    }
    // A scalar Advanced-SIMD integer D operation is one64-bit lane and may
    // use ordinary word arithmetic. It is not the packed ADD/SUB form.
    let prefix: [UInt32] = [0x1e601001, 0x1e601002]
    for (op, expected): (UInt32, UInt64) in [(0x5ee28420, 0x8000000000000000), (0x7ee28420, 0)] {
        let instructions = try decode(prefix + [op])
        #expect(instructions[2].detail?.operands[0].vectorArrangement == AARCH64LAYOUT_INVALID)
        #expect(ValueTracer().finalState(of: instructions)["v0"] == .immediate(expected))
    }
}

/// The fixture run on this machine: 255 + 1 wraps in every byte, with no
/// carry into the next lane.
@Test func packedAdditionWrapsPerLaneNativelyIfPresent() throws {
    #if arch(arm64)
    guard FileManager.default.fileExists(atPath: packedFixture) else { return }
    let handle = try #require(dlopen(packedFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let pointer = try #require(dlsym(handle, "$s11PackedProbe5add8Bs6UInt64VyF"))
    #expect(unsafeBitCast(pointer, to: (@convention(c) () -> UInt64).self)() == 0)
    #endif
}

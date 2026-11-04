import Ccapstone
import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private func moviDetail(
    _ arrangement: AArch64Layout_VectorLayout, immediate: Int64,
    shift: aarch64_shifter = AARCH64_SFT_INVALID, amount: UInt32 = 0,
    destination: PhysReg = PhysReg(kind: .vector, number: 0, widthBits: 128), lane: Int? = nil
) -> StructuredInsn {
    StructuredInsn(id: AARCH64_INS_MOVI, conditionCode: AArch64CC_Invalid,
        updatesFlags: false, writeback: false, postIndex: false, operands: [
            StructuredOperandInfo(operand: .register(destination), shift: (AARCH64_SFT_INVALID, 0),
                extender: AARCH64_EXT_INVALID, vectorIndex: lane, vectorArrangement: arrangement),
            StructuredOperandInfo(operand: .immediate(immediate), shift: (shift, amount), extender: AARCH64_EXT_INVALID),
        ])
}

private func moviState(_ detail: StructuredInsn) -> AbstractValue? {
    ValueTracer().finalState(of: [Instruction(address: 0x1000, text: "movi", detail: detail)])["v0"]
}

@Test func moviDecoderRetainsArrangementAndShiftIndependently() throws {
    let words: [UInt32] = [0x4f00c400, 0x4f00c420, 0x6f00e420, 0x4f00e400, 0x0f00e400]
    let data = words.withUnsafeBytes { Data($0) }
    let engine = try #require(CapstoneEngine())
    let instructions = engine.disassemble(data, address: 0x1000)
    #expect(instructions.count == words.count)
    let expected = [AARCH64LAYOUT_VL_4S, AARCH64LAYOUT_VL_4S, AARCH64LAYOUT_VL_2D,
                    AARCH64LAYOUT_VL_16B, AARCH64LAYOUT_VL_8B]
    for (instruction, layout) in zip(instructions, expected) {
        #expect(instruction.detail?.operands.first?.vectorArrangement == layout)
    }
    let zero = try #require(instructions.first?.detail)
    #expect(zero.operands[1].operand.immediateValue == 0)
    #expect(zero.operands[1].shift.type == AARCH64_SFT_MSL)
    #expect(zero.operands[1].shift.amount == 8)
    #expect(moviState(zero)
        == .aggregate([.immediate(0xff000000ff), .immediate(0xff000000ff)]))
}

@Test func moviModifiedImmediatesExpandWithinEachElement() {
    let cases: [(AArch64Layout_VectorLayout, Int64, aarch64_shifter, UInt32, UInt64)] = [
        (AARCH64LAYOUT_VL_4S, 0, AARCH64_SFT_MSL, 8, 0xff000000ff),
        (AARCH64LAYOUT_VL_4S, 0, AARCH64_SFT_MSL, 16, 0xffff0000ffff),
        (AARCH64LAYOUT_VL_4S, 1, AARCH64_SFT_MSL, 8, 0x1ff000001ff),
        (AARCH64LAYOUT_VL_4S, 1, AARCH64_SFT_MSL, 16, 0x1ffff0001ffff),
        (AARCH64LAYOUT_VL_16B, 7, AARCH64_SFT_INVALID, 0, 0x0707070707070707),
        (AARCH64LAYOUT_VL_8H, 7, AARCH64_SFT_LSL, 8, 0x0700070007000700),
        (AARCH64LAYOUT_VL_4S, 7, AARCH64_SFT_LSL, 24, 0x0700000007000000),
        (AARCH64LAYOUT_VL_2D, Int64(bitPattern: 0xff0000ff0000ffff), AARCH64_SFT_INVALID, 0, 0xff0000ff0000ffff),
    ]
    for (layout, immediate, shift, amount, word) in cases {
        #expect(moviState(moviDetail(layout, immediate: immediate, shift: shift, amount: amount))
            == .aggregate([.immediate(word), .immediate(word)]))
    }
    // Every legal byte immediate and LSL choice, with the expected word built
    // independently from an explicit little-endian byte array.
    for elementBytes in [1, 2, 4] {
        let layout = elementBytes == 1 ? AARCH64LAYOUT_VL_16B
            : elementBytes == 2 ? AARCH64LAYOUT_VL_8H : AARCH64LAYOUT_VL_4S
        for position in 0..<elementBytes {
            for byte: UInt64 in [0, 1, 0x7f, 0x80, 0xff] {
                var bytes = Array(repeating: UInt8(0), count: 8)
                for index in stride(from: position, to: 8, by: elementBytes) { bytes[index] = UInt8(byte) }
                let word = bytes.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << UInt64($1.offset * 8) }
                #expect(moviState(moviDetail(layout, immediate: Int64(byte),
                    shift: AARCH64_SFT_LSL, amount: UInt32(position * 8)))
                    == .aggregate([.immediate(word), .immediate(word)]))
            }
        }
    }
}

@Test func moviHalfWidthLayoutsKeepTheirKnownLowWord() {
    for layout in [AARCH64LAYOUT_VL_8B, AARCH64LAYOUT_VL_4H, AARCH64LAYOUT_VL_2S] {
        let bytes = layout == AARCH64LAYOUT_VL_8B ? 1 : layout == AARCH64LAYOUT_VL_4H ? 2 : 4
        var word: UInt64 = 0
        for bit in stride(from: 0, to: 64, by: bytes * 8) { word |= 7 << UInt64(bit) }
        #expect(moviState(moviDetail(layout, immediate: 7)) == .immediate(word))
    }
    #expect(moviState(moviDetail(AARCH64LAYOUT_VL_D, immediate: -1,
        destination: PhysReg(kind: .vector, number: 0, widthBits: 64))) == .immediate(.max))
    // Legacy synthetic zero instructions lack the arrangement, but no modifier
    // may turn that compatibility case into a false all-zero value.
    #expect(moviState(moviDetail(AARCH64LAYOUT_INVALID, immediate: 0))
        == .aggregate([.immediate(0), .immediate(0)]))
}

@Test func moviDeclinesUnprovenLayoutsAndMalformedModifiers() {
    let cases = [
        moviDetail(AARCH64LAYOUT_INVALID, immediate: 7),
        moviDetail(AARCH64LAYOUT_INVALID, immediate: 0, shift: AARCH64_SFT_MSL, amount: 8),
        moviDetail(AARCH64LAYOUT_VL_4S, immediate: 0, shift: AARCH64_SFT_MSL, amount: 0),
        moviDetail(AARCH64LAYOUT_VL_4S, immediate: 0, shift: AARCH64_SFT_MSL, amount: 24),
        moviDetail(AARCH64LAYOUT_VL_8H, immediate: 0, shift: AARCH64_SFT_MSL, amount: 8),
        moviDetail(AARCH64LAYOUT_VL_4S, immediate: 7, shift: AARCH64_SFT_LSL, amount: 7),
        moviDetail(AARCH64LAYOUT_VL_4S, immediate: 7, shift: AARCH64_SFT_LSL, amount: 32),
        moviDetail(AARCH64LAYOUT_VL_16B, immediate: 7, shift: AARCH64_SFT_LSL, amount: 8),
        moviDetail(AARCH64LAYOUT_VL_4S, immediate: 256),
        moviDetail(AARCH64LAYOUT_VL_4S, immediate: -1),
        moviDetail(AARCH64LAYOUT_VL_2D, immediate: 7),
        moviDetail(AARCH64LAYOUT_VL_2D, immediate: 0, shift: AARCH64_SFT_LSL, amount: 8),
        moviDetail(AARCH64LAYOUT_VL_4S, immediate: 0, lane: 0),
        moviDetail(AARCH64LAYOUT_VL_4S, immediate: 0,
            destination: PhysReg(kind: .vector, number: 0, widthBits: 64)),
        moviDetail(AARCH64LAYOUT_VL_4S, immediate: 0,
            destination: PhysReg(kind: .gpr, number: 0, widthBits: 64)),
    ]
    for detail in cases { #expect(ValueTracer.moviValue(detail) == nil) }
}

@Test func moviMachineFixtureRecoversEveryWordInWholeAndFilteredModesIfPresent() async throws {
    let path = "Fixtures/Sample/libVectorImmediates.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let expected: [(String, UInt64)] = try String(contentsOfFile: "Fixtures/Sample/vectorimmediates.s", encoding: .utf8)
        .split(separator: "\n").filter { $0.hasPrefix("// EXPECT ") }.map {
            let parts = $0.split(separator: " ")
            return (String(parts[2]), try #require(UInt64(parts[3], radix: 16)))
        }
    #expect(expected.count == 19)
    let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    for filter: String? in [nil, "MoviProbe"] {
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: filter)
        }
        for (name, word) in expected {
            let function = try #require(functions.first { $0.displayName.hasPrefix("MoviProbe.\(name)(") })
            let analysis = ValueTracer().analyze(function)
            let exit = try #require(function.instructions.last { $0.controlFlow == .return })
            #expect(analysis.exitValues[exit.address] == .immediate(word))
            let text = function.renderStructured()
            #expect(!text.contains("return ?"), Comment(rawValue: text))
            #expect(text.contains("return \(word)") || text.contains("return 0x\(String(word, radix: 16))"),
                    Comment(rawValue: text))
            // The machine agrees with the EXPECT line.
            let symbol = function.symbol.hasPrefix("_") ? String(function.symbol.dropFirst()) : function.symbol
            let pointer = try #require(dlsym(handle, symbol))
            #expect(unsafeBitCast(pointer, to: (@convention(c) () -> UInt64).self)() == word)
        }
    }
}

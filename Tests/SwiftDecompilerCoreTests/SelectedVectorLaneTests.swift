import Ccapstone
import Foundation
import Testing
#if os(macOS)
import Darwin
#endif
@testable import SwiftDecompilerCore

private let selectedPackedVector = AbstractValue.select(condition: .argument(0),
    whenTrue: .aggregate([.immediate(7), .immediate(19)]),
    whenFalse: .aggregate([.immediate(11), .immediate(23)]))
private let selectedLowLane = AbstractValue.select(condition: .argument(0),
    whenTrue: .immediate(7), whenFalse: .immediate(11))

@Test func selectedVectorScalarViewsProjectOnlyTheRequestedLane() {
    #expect(ValueTracer.scalarView(selectedPackedVector, bits: 64) == selectedLowLane)
    #expect(ValueTracer.scalarView(selectedPackedVector, bits: 128) == selectedPackedVector)
    let wide = AbstractValue.select(condition: .argument(0),
        whenTrue: .aggregate([.immediate(0x1_0000_0007), .immediate(19)]),
        whenFalse: .aggregate([.immediate(0x2_0000_000b), .immediate(23)]))
    for bits in [8, 16, 32] {
        #expect(ValueTracer.scalarView(wide, bits: bits) == selectedLowLane)
    }
    // A select of ordinary scalar values keeps its existing meaning.
    #expect(ValueTracer.scalarView(selectedLowLane, bits: 64) == selectedLowLane)
}

@Test func selectedVectorProjectionDeclinesOpaqueArmsAndFoldsEqualLanes() {
    let mixed = AbstractValue.select(condition: .argument(0),
        whenTrue: .aggregate([.immediate(7), .immediate(19)]), whenFalse: .loaded(0x4000))
    #expect(ValueTracer.scalarView(mixed, bits: 64) == .unknown)
    let loaded = AbstractValue.select(condition: .argument(0),
        whenTrue: .aggregate([.loaded(0x4000), .loaded(0x4008)]),
        whenFalse: .aggregate([.loaded(0x5000), .loaded(0x5008)]))
    #expect(ValueTracer.scalarView(loaded, bits: 32) == .unknown)
    #expect(ValueTracer.scalarView(loaded, bits: 64) == .select(condition: .argument(0),
        whenTrue: .loaded(0x4000), whenFalse: .loaded(0x5000)))
    let equalLow = AbstractValue.select(condition: .unknown,
        whenTrue: .aggregate([.immediate(7), .immediate(19)]),
        whenFalse: .aggregate([.immediate(7), .immediate(23)]))
    #expect(ValueTracer.scalarView(equalLow, bits: 64) == .immediate(7))
    let differentLow = AbstractValue.select(condition: .unknown,
        whenTrue: .aggregate([.immediate(7), .immediate(19)]),
        whenFalse: .aggregate([.immediate(11), .immediate(23)]))
    #expect(ValueTracer.scalarView(differentLow, bits: 64) == .unknown)
}

@Test func nestedSelectedVectorProjectionRetainsItsConditions() throws {
    let nested = AbstractValue.select(condition: .argument(1), whenTrue: selectedPackedVector,
        whenFalse: .aggregate([.immediate(31), .immediate(37)]))
    let low = ValueTracer.scalarView(nested, bits: 64)
    for a: UInt64 in [0, 1, .max] {
        for b: UInt64 in [0, 1, .max] {
            let expected: UInt64 = b == 0 ? 31 : a == 0 ? 11 : 7
            #expect(try ProbeValue.abstractValue(low).evaluateInteger(arguments: [a, b]) == expected)
        }
    }
}

private func selectedVectorDetail(_ id: aarch64_insn, _ operands: [StructuredOperand]) -> StructuredInsn {
    StructuredInsn(id: id, conditionCode: AArch64CC_Invalid, updatesFlags: false,
        writeback: false, postIndex: false, operands: operands.map {
            StructuredOperandInfo(operand: $0, shift: (AARCH64_SFT_INVALID, 0), extender: AARCH64_EXT_INVALID)
        })
}

/// Real transfer and memory paths, with a known join value seeded at entry.
/// The optional Q reload must not throw away the low word just because the
/// ordinary call invalidated the high word.
private func selectedVectorRoundTrip(
    _ value: AbstractValue = selectedPackedVector, lane: Int = 0,
    calls: Int = 0, indirect: Bool = false, storeBits: Int = 128, reloadVector: Bool = false,
    register: Int = 8, overwriteLowWord: Bool = false
) -> AbstractValue? {
    let sp = PhysReg(kind: .stackPointer, number: 31, widthBits: 64)
    let vector = PhysReg(kind: .vector, number: register, widthBits: storeBits)
    let temporary = PhysReg(kind: .vector, number: 9, widthBits: 128)
    let x0 = PhysReg(kind: .gpr, number: 0, widthBits: 64)
    var instructions: [Instruction] = []
    func append(_ text: String, _ id: aarch64_insn, _ operands: [StructuredOperand]) {
        instructions.append(Instruction(address: 0x1000 + UInt64(instructions.count * 4), text: text,
            detail: selectedVectorDetail(id, operands)))
    }
    for _ in 0..<calls {
        instructions.append(Instruction(address: 0x1000 + UInt64(instructions.count * 4),
            text: indirect ? "blr x16" : "bl 0x2000", controlFlow: .call,
            branchTarget: indirect ? nil : 0x2000))
    }
    append("str vector, [sp]", AARCH64_INS_STR,
        [.register(vector), .memory(base: sp, index: nil, displacement: 0)])
    if overwriteLowWord {
        let w10 = PhysReg(kind: .gpr, number: 10, widthBits: 32)
        append("str w10, [sp]", AARCH64_INS_STR,
            [.register(w10), .memory(base: sp, index: nil, displacement: 0)])
    }
    let offset: Int64
    if reloadVector {
        append("ldr q9, [sp]", AARCH64_INS_LDR,
            [.register(temporary), .memory(base: sp, index: nil, displacement: 0)])
        append("str q9, [sp, #32]", AARCH64_INS_STR,
            [.register(temporary), .memory(base: sp, index: nil, displacement: 32)])
        offset = 32
    } else { offset = 0 }
    append("ldr x0, [sp, #lane]", AARCH64_INS_LDR,
        [.register(x0), .memory(base: sp, index: nil, displacement: offset + Int64(lane * 8))])
    let exit = UInt64(0x1000 + instructions.count * 4)
    instructions.append(Instruction(address: exit, text: "ret", controlFlow: .return))
    let function = DisassembledFunction(symbol: "_selectedVectorRoundTrip", demangledName: nil,
        startAddress: 0x1000, instructions: instructions, source: .symbol)
    return ValueTracer().analyze(function, entry: .swiftValueInstance(
        seededRegisters: ["v\(register)": value, "x10": .immediate(99)])).exitValues[exit]
}

@Test func selectedVectorsSpillScalarAndWholeViewsWithoutInventingTuples() throws {
    for bits in [64, 128] {
        let low = try #require(selectedVectorRoundTrip(storeBits: bits))
        #expect(low == selectedLowLane)
        for input: UInt64 in [0, 1, .max] {
            #expect(try ProbeValue.abstractValue(low).evaluateInteger(arguments: [input]) == (input == 0 ? 11 : 7))
        }
    }
    let high = try #require(selectedVectorRoundTrip(lane: 1))
    for input: UInt64 in [0, 1, .max] {
        #expect(try ProbeValue.abstractValue(high).evaluateInteger(arguments: [input]) == (input == 0 ? 23 : 19))
    }
    #expect(selectedVectorRoundTrip(selectedLowLane) == selectedLowLane)
}

@Test func selectedCalleeSavedLowLanesSurviveCallsAndPartialVectorReloads() throws {
    for calls in [1, 2] {
        for indirect in [false, true] {
            for reload in [false, true] {
                for register in [8, 15] {
                    #expect(selectedVectorRoundTrip(calls: calls, indirect: indirect,
                        reloadVector: reload, register: register) == selectedLowLane)
                    #expect(selectedVectorRoundTrip(lane: 1, calls: calls, indirect: indirect,
                        reloadVector: reload, register: register) == nil)
                }
            }
        }
    }
    // Caller-saved vectors lose stale lanes. v0 can hold the fresh result;
    // other caller-saved registers have no corresponding return-value role.
    #expect(selectedVectorRoundTrip(calls: 1, reloadVector: true, register: 0) == .callResult(0x1000))
    for register in [7, 16, 31] {
        #expect(selectedVectorRoundTrip(calls: 1, reloadVector: true, register: register) == nil)
    }
    // An opaque branch cannot be split.
    let mixed = AbstractValue.select(condition: .argument(0),
        whenTrue: .aggregate([.immediate(7), .immediate(19)]), whenFalse: .loaded(0x4000))
    #expect(selectedVectorRoundTrip(mixed) == nil)
    #expect(selectedVectorRoundTrip(.aggregate([.immediate(7), .unknown]), reloadVector: true) == .immediate(7))
    #expect(selectedVectorRoundTrip(.aggregate([.unknown, .immediate(23)]), lane: 1,
        reloadVector: true) == .immediate(23))
    #expect(selectedVectorRoundTrip(.aggregate([.unknown, .unknown]), reloadVector: true) == nil)
}

@Test func selectedVectorPartialReloadNeverPromotesAFourByteStoreToAWholeLane() {
    let original = AbstractValue.aggregate([.immediate(7), .immediate(23)])
    // The partial write destroys the old eight-byte snapshot. A Q reload and
    // spill must not turn the known four bytes into a known eight-byte value.
    #expect(selectedVectorRoundTrip(original, reloadVector: true, overwriteLowWord: true) == nil)
    #expect(selectedVectorRoundTrip(original, lane: 1, reloadVector: true, overwriteLowWord: true)
        == .immediate(23))
}

private let selectedVectorFixture = "Fixtures/Sample/libSelectedVectorLanes.dylib"

/// The real decoder and CFG produce the join rather than consume seeded state.
@Test func selectedVectorMachineFixtureRecoversLanesInWholeAndFilteredModesIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: selectedVectorFixture) else { return }
    let path = selectedVectorFixture
    for filter: String? in [nil, "VectorJoin"] {
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: filter)
        }
        for name in ["low", "high", "noCall", "scalar", "scalarSpill"] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("VectorJoin.\(name)(") })
            let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
            let exit = try #require(function.instructions.last { $0.controlFlow == .return })
            for text in [function.renderStructured(), function.renderPseudo()] {
                if name == "high" {
                    #expect(analysis.exitValues[exit.address] == nil)
                    #expect(text.contains("return ?"), Comment(rawValue: text))
                } else {
                    let value = try #require(analysis.exitValues[exit.address])
                    for input: UInt64 in [0, 1, 7, 11, 1 << 63, .max] {
                        #expect(try ProbeValue.abstractValue(value).evaluateInteger(arguments: [input])
                            == (input == 0 ? 11 : 7))
                    }
                    #expect(!text.contains("return ?"), Comment(rawValue: text))
                    #expect(text.contains("arg0") && text.contains("11") && text.contains("7"), Comment(rawValue: text))
                    #expect(!text.contains("(7, 7)") && !text.contains("(11, 11)"), Comment(rawValue: text))
                }
            }
        }
    }
}

#if os(macOS) && arch(arm64)
@Test func selectedVectorMachineFixtureMatchesItsNativeOracleIfPresent() throws {
    guard FileManager.default.fileExists(atPath: selectedVectorFixture) else { return }
    let path = selectedVectorFixture
    let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    for (name, length) in [("low", 3), ("high", 4), ("noCall", 6), ("scalar", 6), ("scalarSpill", 11)] {
        let pointer = try #require(dlsym(handle, "$s10VectorJoin\(length)\(name)yS2iF"))
        let native = unsafeBitCast(pointer, to: (@convention(thin) (Int) -> Int).self)
        for input in [0, 1, 7, 11, Int.min, Int.max] {
            #expect(native(input) == (name == "high" ? 19 : input == 0 ? 11 : 7))
        }
    }
}
#endif

@Test func selectedVectorWordsKeepTheirFloatingMeaningInReturnsArgumentsAndArithmeticIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: selectedVectorFixture) else { return }
    for filter: String? in [nil, "VectorJoin"] {
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: selectedVectorFixture, functionFilter: filter)
        }
        for name in ["float", "float32", "float16", "floatSum", "floatCall", "floatBodyCall"] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("VectorJoin.\(name)(") })
            for output in [function.renderStructured(), function.renderPseudo()] {
                #expect(output.contains("1.0") && output.contains("2.0"), Comment(rawValue: output))
                #expect(!output.contains("0x3ff0") && !output.contains("0x4000")
                    && !output.contains("0x3f80") && !output.contains("0x3c00"), Comment(rawValue: output))
                #expect(!output.contains("return ?"), Comment(rawValue: output))
                let selected = "((arg0 == 0) ? 2.0 : 1.0)"
                let expected = name == "floatSum" ? "return (\(selected) + \(selected))"
                    : name == "floatCall" ? "return VectorJoin.takeDouble(\(selected))"
                    : name == "floatBodyCall" ? "return selectedVectorBits(\(selected))"
                    : "return \(selected)"
                #expect(output.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == expected },
                        Comment(rawValue: output))
            }
        }
    }
}

#if os(macOS) && arch(arm64)
@Test func selectedVectorFloatingFixtureMatchesItsNativeOracleIfPresent() throws {
    guard FileManager.default.fileExists(atPath: selectedVectorFixture) else { return }
    let handle = try #require(dlopen(selectedVectorFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    for input in [0, 1, 7, 11, Int.min, Int.max] {
        let expected: Double = input == 0 ? 2 : 1
        for name in ["float", "floatSum", "floatCall"] {
            let pointer = try #require(dlsym(handle, "$s10VectorJoin\(name.count)\(name)ySdSiF"))
            let native = unsafeBitCast(pointer, to: (@convention(c) (Int) -> Double).self)
            #expect(native(input) == (name == "floatSum" ? expected * 2 : expected))
        }
        let single = try #require(dlsym(handle, "$s10VectorJoin7float32ySfSiF"))
        #expect(unsafeBitCast(single, to: (@convention(c) (Int) -> Float).self)(input) == Float(expected))
        let half = try #require(dlsym(handle, "selectedVectorHalfAsDouble"))
        #expect(unsafeBitCast(half, to: (@convention(c) (Int) -> Double).self)(input) == expected)
        let bits = try #require(dlsym(handle, "$s10VectorJoin13floatBodyCallys6UInt64VSiF"))
        #expect(unsafeBitCast(bits, to: (@convention(c) (Int) -> UInt64).self)(input) == expected.bitPattern)
    }
}
#endif

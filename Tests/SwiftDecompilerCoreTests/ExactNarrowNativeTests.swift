import Ccapstone
import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let loadBitsFixtures = [
    "Fixtures/Sample/libLoadBits.Onone.dylib",
    "Fixtures/Sample/libLoadBits.dylib",
    "Fixtures/Sample/libLoadBits.Osize.dylib",
]

private struct LoadBitsCase {
    let method: String
    let cName: String
    let load: aarch64_insn
    let explicitExtension: Bool
    let extensionMask: Int64?

    static let cases: [Self] = [
        .init(method: "plain", cName: "loadbits_plain", load: AARCH64_INS_LDR, explicitExtension: true, extensionMask: nil),
        .init(method: "masked", cName: "loadbits_masked", load: AARCH64_INS_LDR, explicitExtension: true,
              extensionMask: 0x0000_FFFF_FFFF_FFFF),
        .init(method: "roundTrip", cName: "loadbits_round_trip", load: AARCH64_INS_LDRSW, explicitExtension: false, extensionMask: nil),
        .init(method: "roundTripUnscaled", cName: "loadbits_round_trip_unscaled", load: AARCH64_INS_LDURSW, explicitExtension: false, extensionMask: nil),
    ]
}

@Test func narrowFloatingReadPreservesNativeTypedFieldBitsIfPresent() async throws {
    for fixture in loadBitsFixtures {
        try await verifyTypedFieldReads(in: fixture)
    }
}

private func verifyTypedFieldReads(in loadBitsFixture: String) async throws {
    let fixtureComment = Comment(rawValue: loadBitsFixture)
    guard FileManager.default.fileExists(atPath: loadBitsFixture) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, "Build \(loadBitsFixture) before testing.")
        return
    }
    let handle = try #require(dlopen(loadBitsFixture, RTLD_NOW | RTLD_LOCAL | RTLD_FIRST), fixtureComment)
    defer { dlclose(handle) }
    typealias Transfer = @convention(c) (UInt32) -> UInt32
    let patterns: [UInt32] = [0x8000_0000, 0x3F90_0001, 0xFFC0_1234, 0x8123_4567]
    for row in LoadBitsCase.cases {
        let comment = Comment(rawValue: "\(loadBitsFixture): \(row.method)")
        let symbol = try #require(dlsym(handle, row.cName), comment)
        let native = unsafeBitCast(symbol, to: Transfer.self)
        for input in patterns {
            #expect(native(input) == input, comment)
        }
    }

    let machO = try BinaryLoader.load(path: loadBitsFixture)
    let maps = try FieldMapBuilder.build(in: machO)
    let fields = try #require(maps["LoadBits.FloatBox"], fixtureComment)
    try #require(fields.lookup(offset: 0, bytes: 4) == .success(.whole(name: "f", typeMangledName: "Sf")), fixtureComment)
    let array = await withStableDependencies { await Disassembler().disassemble(machO: machO) }
    let stream = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: machO, transform: { $0 })
    }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: loadBitsFixture, functionFilter: "LoadBits.FloatBox.")
    }
    let w8 = PhysReg(kind: .gpr, number: 8, widthBits: 32)
    let x8 = PhysReg(kind: .gpr, number: 8, widthBits: 64)
    let x20 = PhysReg(kind: .gpr, number: 20, widthBits: 64)
    let s0 = PhysReg(kind: .vector, number: 0, widthBits: 32)
    for (mode, functions) in [("array", array), ("stream", stream), ("filtered", filtered)] {
        for row in LoadBitsCase.cases {
            let comment = Comment(rawValue: "\(loadBitsFixture) \(mode): \(row.method)")
            let function = try #require(functions.first {
                $0.displayName.hasPrefix("LoadBits.FloatBox.\(row.method)(")
            }, comment)
            let moveIndex = 1 + (row.explicitExtension ? 1 : 0) + (row.extensionMask == nil ? 0 : 1)
            try #require(function.instructions.count == moveIndex + 2, comment)
            let load = try #require(function.instructions[0].detail, comment)
            try #require(load.id == row.load && load.operands.count == 2 && !load.writeback && !load.postIndex, comment)
            try #require(load.operands[0].operand.register == (row.explicitExtension ? w8 : x8), comment)
            guard case .memory(let base, nil, 0) = load.operands[1].operand else {
                Issue.record(Comment(rawValue: "\(loadBitsFixture) \(mode): \(row.method) must load the direct offset-zero receiver"))
                continue
            }
            try #require(base == x20, comment)
            if row.explicitExtension {
                let extend = try #require(function.instructions[1].detail, comment)
                try #require(extend.id == AARCH64_INS_SXTW && extend.operands.count == 2, comment)
                try #require(extend.operands.compactMap { $0.operand.register } == [x8, w8], comment)
            }
            if let expectedMask = row.extensionMask {
                let mask = try #require(function.instructions[moveIndex - 1].detail, comment)
                try #require(mask.id == AARCH64_INS_AND && mask.operands.count == 3, comment)
                try #require(mask.operands.prefix(2).compactMap { $0.operand.register } == [x8, x8], comment)
                try #require(mask.operands[2].operand.immediateValue == expectedMask, comment)
            }
            let move = try #require(function.instructions[moveIndex].detail, comment)
            try #require(move.id == AARCH64_INS_FMOV && move.operands.count == 2, comment)
            try #require(move.operands.compactMap { $0.operand.register } == [s0, w8], comment)
            let tail = function.instructions[moveIndex + 1]
            try #require(tail.detail?.id == AARCH64_INS_RET && tail.controlFlow == .return, comment)
            for view in [function.renderPseudo(), function.renderStructured()] {
                let returns = view.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("return ") }
                #expect(returns == ["return self.f"], comment)
            }
        }
    }
}

/// Evaluate the raw word in machine arithmetic independently of the tracer's
/// sign-extension representation. An unsupported operation is not a match.
private func evaluateLoadBitsExit(_ value: AbstractValue, argument: UInt64) -> UInt64? {
    switch value {
    case .argument(0): return argument
    case .immediate(let word): return word
    case .binary(let op, let lhs, let rhs):
        guard let left = evaluateLoadBitsExit(lhs, argument: argument),
              let right = evaluateLoadBitsExit(rhs, argument: argument)
        else { return nil }
        switch op {
        case .bitAnd: return left & right
        case .shiftLeft where right < 64: return left << right
        case .arithmeticShiftRight where right < 64: return UInt64(bitPattern: Int64(bitPattern: left) >> right)
        default: return nil
        }
    default: return nil
    }
}

@Test func widerIntegerReadPreservesNativeSignedByteBitsIfPresent() async throws {
    for fixture in loadBitsFixtures {
        try await verifyRawWordReads(in: fixture)
    }
}

private func verifyRawWordReads(in loadBitsFixture: String) async throws {
    let fixtureComment = Comment(rawValue: loadBitsFixture)
    guard FileManager.default.fileExists(atPath: loadBitsFixture) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, "Build \(loadBitsFixture) before testing.")
        return
    }
    let handle = try #require(dlopen(loadBitsFixture, RTLD_NOW | RTLD_LOCAL | RTLD_FIRST), fixtureComment)
    defer { dlclose(handle) }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: loadBitsFixture, functionFilter: "loadbits_")
    }
    let x0 = PhysReg(kind: .gpr, number: 0, widthBits: 64)
    let x8 = PhysReg(kind: .gpr, number: 8, widthBits: 64)
    let w0 = PhysReg(kind: .gpr, number: 0, widthBits: 32)
    let w8 = PhysReg(kind: .gpr, number: 8, widthBits: 32)
    typealias DecodedOperandSpec = (id: aarch64_insn, registers: [PhysReg], immediate: Int64?)

    func verify(_ name: String, prefix: [DecodedOperandSpec], vectors: [(UInt64, UInt32)],
                native: (UInt64) -> UInt32) throws {
        let comment = Comment(rawValue: "\(loadBitsFixture): \(name)")
        let function = try #require(functions.first { $0.symbol == "_" + name }, comment)
        let expected = prefix + [(AARCH64_INS_MOV, [w0, w8], nil)]
        try #require(function.instructions.count == expected.count + 1, comment)
        for (instruction, spec) in zip(function.instructions, expected) {
            let detail = try #require(instruction.detail, comment)
            try #require(detail.id == spec.id, comment)
            try #require(detail.operands.count == spec.registers.count + (spec.immediate == nil ? 0 : 1), comment)
            try #require(detail.operands.prefix(spec.registers.count).compactMap { $0.operand.register } == spec.registers,
                         comment)
            if let immediate = spec.immediate {
                try #require(detail.operands.last?.operand.immediateValue == immediate, comment)
            }
        }
        let tail = try #require(function.instructions.last, comment)
        try #require(tail.detail?.id == AARCH64_INS_RET && tail.controlFlow == .return, comment)
        let trace = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
        let exit = try #require(trace.exitValues[tail.address], comment)
        for (input, expected) in vectors {
            let actual = native(input)
            let vector = Comment(rawValue: "\(loadBitsFixture): \(name) input 0x\(String(input, radix: 16))")
            #expect(actual == expected, vector)
            #expect(evaluateLoadBitsExit(exit, argument: input) == UInt64(actual), vector)
        }
    }

    let byteSymbol = try #require(dlsym(handle, "loadbits_byte_to_word"), fixtureComment)
    let byteToWord = unsafeBitCast(byteSymbol, to: (@convention(c) (UInt32) -> UInt32).self)
    try verify("loadbits_byte_to_word", prefix: [(AARCH64_INS_SXTB, [x8, w0], nil)],
               vectors: [(0x1234_5680, 0xFFFF_FF80), (0xFEDC_BA25, 0x25), (0xABCD_00FF, 0xFFFF_FFFF)]) {
        byteToWord(UInt32($0))
    }

    typealias WideInput = @convention(c) (UInt64) -> UInt32
    let shiftSymbol = try #require(dlsym(handle, "loadbits_unequal_shifts"), fixtureComment)
    let unequalShifts = unsafeBitCast(shiftSymbol, to: WideInput.self)
    try verify("loadbits_unequal_shifts",
               prefix: [(AARCH64_INS_LSL, [x8, x0], 31), (AARCH64_INS_ASR, [x8, x8], 32)],
               vectors: [(0x1234_5680, 0x091A_2B40), (0x1_ABCD_00FF, 0xD5E6_807F)], native: unequalShifts)

    let maskSymbol = try #require(dlsym(handle, "loadbits_mask_clears_low_bit"), fixtureComment)
    let clearsLowBit = unsafeBitCast(maskSymbol, to: WideInput.self)
    try verify("loadbits_mask_clears_low_bit",
               prefix: [(AARCH64_INS_SXTW, [x8, w0], nil), (AARCH64_INS_AND, [x8, x8], -2)],
               vectors: [(0x1234_5681, 0x1234_5680), (0x8000_0001, 0x8000_0000), (0xFFFF_FFFF, 0xFFFF_FFFE)],
               native: clearsLowBit)
}

import Ccapstone
import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let fpWideRawFixture = "Fixtures/Sample/libFPWideRaw.dylib"

private func evaluateFPWideExit(_ value: AbstractValue, input: UInt64) -> UInt64? {
    switch value {
    case .argument(0):
        return input
    case .binary(.bitAnd, .argument(0), .immediate(let mask)):
        return input & mask
    default:
        return nil
    }
}

@Test func widenedFloatingMovesTrackOnlyTheNativeRawSourceBitsIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fpWideRawFixture) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, "Build \(fpWideRawFixture) before testing.")
        return
    }
    let handle = try #require(dlopen(fpWideRawFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    typealias RawBits = @convention(c) (UInt64) -> UInt64
    let wordSymbol = try #require(dlsym(handle, "fpwide_word"))
    let halfSymbol = try #require(dlsym(handle, "fpwide_half"))
    let word = unsafeBitCast(wordSymbol, to: RawBits.self)
    let half = unsafeBitCast(halfSymbol, to: RawBits.self)
    let vectors: [(input: UInt64, word: UInt64, half: UInt64)] = [
        (0xFEDC_BA98_8000_0000, 0x8000_0000, 0x0000),
        (0x0123_4567_FFC0_1234, 0xFFC0_1234, 0x1234),
        (0xFFFF_FFFF_3F90_8000, 0x3F90_8000, 0x8000),
        (0xABCD_1122_0000_FC01, 0x0000_FC01, 0xFC01),
    ]
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: fpWideRawFixture, functionFilter: "fpwide_")
    }
    let w0 = PhysReg(kind: .gpr, number: 0, widthBits: 32)
    let x0 = PhysReg(kind: .gpr, number: 0, widthBits: 64)
    let d0 = PhysReg(kind: .vector, number: 0, widthBits: 64)
    let cases: [(method: String, bits: Int, mask: UInt64, native: RawBits)] = [
        ("_fpwide_word", 32, 0xFFFF_FFFF, word),
        ("_fpwide_half", 16, 0xFFFF, half),
    ]
    try #require(functions.count == cases.count)
    try #require(Set(functions.map(\.symbol)) == Set(cases.map(\.method)))
    for row in cases {
        let comment = Comment(rawValue: row.method)
        let function = try #require(functions.first { $0.symbol == row.method }, comment)
        try #require(function.instructions.count == 3, comment)
        let first = try #require(function.instructions[0].detail, comment)
        let second = try #require(function.instructions[1].detail, comment)
        let narrow = PhysReg(kind: .vector, number: 0, widthBits: row.bits)
        try #require(first.id == AARCH64_INS_FMOV && first.operands.count == 2, comment)
        try #require(first.operands[0].operand.register == narrow && first.operands[1].operand.register == w0, comment)
        try #require(second.id == AARCH64_INS_FMOV && second.operands.count == 2, comment)
        try #require(second.operands[0].operand.register == x0 && second.operands[1].operand.register == d0, comment)
        let tail = function.instructions[2]
        try #require(tail.controlFlow == .return && tail.detail?.id == AARCH64_INS_RET, comment)

        // This is a raw tracer test with the native oracle's independently
        // verified x0 input. The assembly has no declared Swift signature.
        let result = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
        let exit = try #require(result.exitValues[tail.address], comment)
        #expect(exit == .binary(.bitAnd, .argument(0), .immediate(row.mask)), comment)
        for vector in vectors {
            let native = row.native(vector.input)
            #expect(native == (row.bits == 32 ? vector.word : vector.half), comment)
            #expect(evaluateFPWideExit(exit, input: vector.input) == native, comment)
        }
    }
}

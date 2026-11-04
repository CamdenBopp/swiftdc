import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A float's bits read into a general register are an integer. `fmov x8, d0`
/// carried the Double through unchanged, so `floatbits.swift` (-O) rendered
/// `Int(a)`'s finiteness guard as `(arg0 & 0x7fffffffffffffff) >
/// 1.7976931348623157e+308`, a float compare that is false on NaN where the
/// binary traps, and `a.bitPattern > 100` as `(arg0 <=ᵁ 100)`, which reads as
/// a compare of the Double.
@Test func aFloatsBitsMovedToAnIntegerRegisterRenderAsItsBitPatternIfPresent() async throws {
    let path = "Fixtures/Sample/libFloatBits.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FloatBits.\(name)(") }).renderStructured()
    }
    let guardText = try render("truncatingConversion")
    #expect(guardText.contains("if ((arg0.bitPattern & 0x7fffffffffffffff) > 0x7fefffffffffffff) {"))
    #expect(!guardText.contains("e+308"))
    #expect(try render("lowByte").contains("(((arg0.bitPattern & 255) != 7) ? 2 : 1)"))
    #expect(try render("bitsAbove").contains("((arg0.bitPattern <=ᵁ 100) ? 8 : 7)"))
    #expect(try render("exponentField").contains("(((arg0.bitPattern >>ᵁ 52) != 1023) ? 10 : 9)"))
    #expect(try render("floatLowByte").contains("(((arg0.bitPattern & 255) != 7) ? 12 : 11)"))
    // No operator between the bits and the compare: rendered `(arg0 != nan)`.
    #expect(try render("bitsEqualPayload").contains("((arg0.bitPattern != 0x7ff8000000000001) ? 18 : 17)"))
}

/// The tracer's half: `fmov x0, d1` is the bit pattern of d1 at its own
/// width, an immediate stays the immediate, and moving a bit pattern back
/// into a float register of that width is the float again.
@Test func anFmovBetweenRegisterFilesReinterpretsTheBits() throws {
    let engine = try #require(CapstoneEngine())
    func trace(_ words: [UInt32]) -> (value: AbstractValue?, float: AbstractValue?) {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let body = engine.disassemble(Data(bytes), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, annotation: nil,
                        controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: "f", demangledName: nil, startAddress: 0x1000,
                                            instructions: body, source: .symbol)
        let result = ValueTracer().analyze(function, entry: nil)
        return (result.exitValues[body.last!.address], result.exitFloatValues[body.last!.address])
    }
    let double = AbstractValue.unary(.toFloat(bits: 64), .immediate(5))
    // mov w8, #5; scvtf d1, w8; fmov x0, d1; ret
    #expect(trace([0x528000a8, 0x1e620101, 0x9e660020, 0xd65f03c0]).value
        == .unary(.bitPattern(bits: 64), double))
    // mov w8, #5; scvtf d1, w8; fmov x9, d1; fmov d0, x9; ret
    #expect(trace([0x528000a8, 0x1e620101, 0x9e660029, 0x9e670120, 0xd65f03c0]).float == double)
    // mov w8, #5; scvtf s1, w8; fmov w0, s1; ret
    #expect(trace([0x528000a8, 0x1e220101, 0x1e260020, 0xd65f03c0]).value
        == .unary(.bitPattern(bits: 32), .unary(.toFloat(bits: 32), .immediate(5))))
    // mov x9, #0x4059000000000000; fmov d2, x9; fmov x0, d2; ret: the same bits
    #expect(trace([0xd2e80b29, 0x9e670122, 0x9e660040, 0xd65f03c0]).value == .immediate(0x4059000000000000))
}

/// A Float's bits are 32. `fmov w0, s0` is `a.bitPattern`; `fmov x0, d0`
/// reads all of d0, whose upper half the Float does not define, and declines.
/// Before the bit pattern was modelled the first read `(arg0 & 0xffffffff)`
/// and the second `arg0`, the Float itself (`floatbitswidth.s`).
@Test func aFloatsBitsReadAtAnotherWidthDeclineIfPresent() async throws {
    let path = "Fixtures/Sample/libFloatBitsWidth.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FloatBitsWidth.\(name)(") }).renderStructured()
    }
    #expect(try render("word").contains("return arg0.bitPattern\n"))
    #expect(try render("whole").contains("return ?\n"))
}

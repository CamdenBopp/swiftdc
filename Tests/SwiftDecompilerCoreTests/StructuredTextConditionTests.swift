import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A raw function (no value tracer, so no baked `cond:`): its branch
/// conditions come from the structurer's text path.
private func textPathFunction(_ words: [UInt32], undetailed: Set<Int> = []) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "_textPath", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.enumerated().map { index, insn in
            Instruction(address: insn.address, text: insn.text, controlFlow: insn.controlFlow,
                        branchTarget: insn.branchTarget, detail: undetailed.contains(index) ? nil : insn.detail)
        }, source: .symbol)
}

/// The text path names a definition's source registers, which read as their
/// values at the test. `and w8, w0, #0xff; add w0, w0, #1; cmp w8, #7`
/// rendered `(w0 & 0xff) == 7`, one more than the value tested, and
/// `mov x20, x1; bl f; cbz x20` rendered `x1 == 0` with x1 clobbered
/// (StringArity.takeOptString).
@Test func aTextConditionDeclinesASourceWrittenBeforeTheTest() throws {
    // ...; b.eq +12; mov w0, #1; ret; mov w0, #2; ret
    let tail: [UInt32] = [0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]
    let kept = try textPathFunction([0x12001c08, 0x71001d1f, 0x54000060] + tail).renderStructured()
    #expect(kept.contains("(w0 & 0xff) == 7"), Comment(rawValue: kept))
    let written = try textPathFunction([0x12001c08, 0x11000400, 0x71001d1f, 0x54000060] + tail).renderStructured()
    #expect(!written.contains("w0 & 0xff"), Comment(rawValue: written))
    #expect(written.contains("w8 == 7"), Comment(rawValue: written))
    // Without Capstone detail an instruction between may write anything.
    let unknown = try textPathFunction([0x12001c08, 0x11000501, 0x71001d1f, 0x54000060] + tail, undetailed: [1]).renderStructured()
    #expect(unknown.contains("w8 == 7"), Comment(rawValue: unknown))

    // mov x20, x1; [bl +24;] cbz x20, +12; mov w0, #1; ret; mov w0, #2; ret[; ret]
    let copied = try textPathFunction([0xaa0103f4, 0xb4000074] + tail).renderStructured()
    #expect(copied.contains("x1 == 0") || copied.contains("!x1"), Comment(rawValue: copied))
    let called = try textPathFunction([0xaa0103f4, 0x94000006, 0xb4000074] + tail + [0xd65f03c0]).renderStructured()
    #expect(!called.contains("x1 == 0") && !called.contains("!x1"), Comment(rawValue: called))
    #expect(called.contains("x20 == 0"), Comment(rawValue: called))
}

/// The tested register's last write need not be its first operand: `ldp
/// x9, x8, [sp]` loads x8, and `ldr x9, [x8], #8` moves it. Walking past
/// either found `mov x8, x1` and rendered `x1 == 7` (RetainRegister.enroll
/// read the pointer an `ldp` had loaded from).
@Test func aTextConditionStopsAtAnyWriteOfTheTestedRegister() throws {
    let tail: [UInt32] = [0xf1001d1f, 0x54000060, 0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]
    let copied = try textPathFunction([0xaa0103e8] + tail).renderStructured()
    #expect(copied.contains("x1 == 7"), Comment(rawValue: copied))
    for write: UInt32 in [0xa94023e9, 0xf8408509] {   // ldp x9, x8, [sp]; ldr x9, [x8], #8
        let text = try textPathFunction([0xaa0103e8, write] + tail).renderStructured()
        #expect(!text.contains("x1 == 7"), Comment(rawValue: text))
        #expect(text.contains("x8 == 7"), Comment(rawValue: text))
    }
    // Without detail the instruction between may load x8. An immediate has
    // no source for the survival check to catch: `mov x8, #5` read `5 == 7`.
    let constant = try textPathFunction([0xd28000a8] + tail).renderStructured()
    #expect(constant.contains("if (0)") || constant.contains("5 == 7"), Comment(rawValue: constant))
    let unknown = try textPathFunction([0xd28000a8, 0xd503201f] + tail, undetailed: [1]).renderStructured()  // nop
    #expect(unknown.contains("x8 == 7"), Comment(rawValue: unknown))
}

/// `ubfx d, s, #lsb, #width` is `(s >> lsb) & (2^width - 1)`. Read as a
/// copy of s, the Go float test `ubfx x13, x12, #23, #8; cmp x13, #0xff`
/// (exponent all ones) rendered `x12 != 0xff`. `sbfx` sign-extends its
/// field, which no operator spells, so its register stays.
@Test func aTextConditionReadsABitfieldExtractAsItsField() throws {
    let tail: [UInt32] = [0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]
    func render(_ extract: UInt32, _ compare: UInt32) throws -> String {
        try textPathFunction([extract, compare, 0x54000061] + tail).renderStructured()
    }
    let cmpW8 = UInt32(0x71001d1f), cmpX8 = UInt32(0xf1001d1f), cmpX8ff = UInt32(0xf103fd1f)
    let unsigned = try render(0x53031c08, cmpW8)         // ubfx w8, w0, #3, #5; cmp w8, #7
    #expect(unsigned.contains("((w0 >>ᵁ 3) & 0x1f) != 7"), Comment(rawValue: unsigned))
    let low = try render(0x53000c08, cmpW8)              // ubfx w8, w0, #0, #4
    #expect(low.contains("(w0 & 0xf) != 7"), Comment(rawValue: low))
    let exponent = try render(0xd3577828, cmpX8ff)       // ubfx x8, x1, #23, #8; cmp x8, #0xff
    #expect(exponent.contains("((x1 >>ᵁ 23) & 0xff) != 0xff"), Comment(rawValue: exponent))
    let signed = try render(0x93442c08, cmpX8)           // sbfx x8, x0, #4, #8
    #expect(signed.contains("x8 != 7"), Comment(rawValue: signed))
    #expect(!signed.contains("x0"), Comment(rawValue: signed))
}

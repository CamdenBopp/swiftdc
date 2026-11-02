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

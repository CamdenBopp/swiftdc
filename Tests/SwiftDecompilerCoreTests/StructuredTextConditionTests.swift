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

/// A logical and an arithmetic right shift differ on a negative value:
/// both printed `(x0 >> 3)`. Each now names its kind, as the tracer's
/// expressions do.
@Test func aTextConditionNamesItsShiftsKind() throws {
    let tail: [UInt32] = [0xf1001d1f, 0x54000061, 0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]
    let logical = try textPathFunction([0xd343fc08] + tail).renderStructured()     // lsr x8, x0, #3
    #expect(logical.contains("(x0 >>ᵁ 3) != 7"), Comment(rawValue: logical))
    let arithmetic = try textPathFunction([0x9343fc08] + tail).renderStructured()  // asr x8, x0, #3
    #expect(arithmetic.contains("(x0 >>ˢ 3) != 7"), Comment(rawValue: arithmetic))
}

/// An operand's printed shift or extend is part of its value. Dropped,
/// `cmp x0, #0x1, lsl #12` read `x0 == 1` (it compares with 4096) and
/// `cmp x21, x8, lsr #1` read `x21 >=ᵁ x8` (RetainRegister.enroll).
/// An extend or a rotate, which no operator here spells, declines.
@Test func aTextConditionKeepsAnOperandsShift() throws {
    let tail: [UInt32] = [0x54000060, 0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]  // b.eq +12; ...
    func render(_ words: [UInt32]) throws -> String { try textPathFunction(words + tail).renderStructured() }
    let cases: [([UInt32], String)] = [
        ([0xeb41041f], "x0 == (x1 >>ᵁ 1)"),                  // cmp x0, x1, lsr #1
        ([0xf140041f], "x0 == 0x1000"),                      // cmp x0, #1, lsl #12
        ([0xab81081f], "x0 == -((x1 >>ˢ 2))"),               // cmn x0, x1, asr #2
        ([0xea010c1f], "(x0 & (x1 << 3)) == 0"),             // tst x0, x1, lsl #3
        ([0x0a010808, 0x71001d1f], "(w0 & (w1 << 2)) == 7"), // and w8, w0, w1, lsl #2; cmp w8, #7
        ([0xeb21401f], "if (?)"),                            // cmp x0, w1, uxtw
        ([0x0ac10808, 0x71001d1f], "w8 == 7"),               // and w8, w0, w1, ror #2; cmp w8, #7
    ]
    for (words, expected) in cases {
        let text = try render(words)
        #expect(text.contains(expected), Comment(rawValue: text))
    }
}

/// A definition that overwrites its own source leaves the result, not the
/// source, in that register at the test: `lsr x8, x8, #3; cmp x8, #1`
/// rendered `(x8 >>ᵁ 3) == 1`, shifting the result again.
@Test func aTextConditionDeclinesADefinitionOfItsOwnSource() throws {
    let tail: [UInt32] = [0xf100051f, 0x54000060, 0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]
    let other = try textPathFunction([0xd343fc08] + tail).renderStructured()   // lsr x8, x0, #3
    #expect(other.contains("(x0 >>ᵁ 3) == 1"), Comment(rawValue: other))
    let own = try textPathFunction([0xd343fd08] + tail).renderStructured()     // lsr x8, x8, #3
    #expect(!own.contains(">>"), Comment(rawValue: own))
    #expect(own.contains("x8 == 1"), Comment(rawValue: own))
    // and w8, w8, #0xff; cmp w8, #1: masking the result again changes nothing.
    let mask = try textPathFunction([0x12001d08, 0x7100051f] + tail.dropFirst()).renderStructured()
    #expect(mask.contains("(w8 & 0xff) == 1"), Comment(rawValue: mask))
}

/// The text path renders a definition from InstructionSemantics, the
/// table the value tracer evaluates, so the two cannot disagree on what an
/// instruction computes. A multiply, an exclusive or, a complement and an
/// extend each named only the tested register before; a register shift
/// amount is taken mod the width, as the hardware does. A division or a
/// sign extension into a wider result, which no operator here spells,
/// keeps the tested register.
@Test func aTextConditionRendersTheSharedSemantics() throws {
    let tail: [UInt32] = [0x54000060, 0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]   // b.eq +12; ...
    let cmpX8 = UInt32(0xf1001d1f), cmpW8 = UInt32(0x71001d1f)
    let cases: [(UInt32, UInt32, String)] = [
        (0x9b017c08, cmpX8, "(x0 * x1) == 7"),              // mul x8, x0, x1
        (0xca010008, cmpX8, "(x0 ^ x1) == 7"),              // eor x8, x0, x1
        (0xaa2003e8, cmpX8, "~x0 == 7"),                    // mvn x8, x0
        (0xaa210008, cmpX8, "(x0 | ~x1) == 7"),             // orn x8, x0, x1
        (0x53001c08, cmpW8, "(w0 & 0xff) == 7"),            // uxtb w8, w0
        (0x9ac12408, cmpX8, "(x0 >>ᵁ (x1 & 0x3f)) == 7"),   // lsr x8, x0, x1
        (0x9ac10808, cmpX8, "x8 == 7"),                     // udiv x8, x0, x1
        (0x93407c08, cmpX8, "x8 == 7"),                     // sxtw x8, w0
    ]
    for (definition, compare, expected) in cases {
        let text = try textPathFunction([definition, compare] + tail).renderStructured()
        #expect(text.contains(expected), Comment(rawValue: text))
    }
}

/// `tst` and `ands` set N and Z from the masked value and clear C and V. A
/// carry condition after one is constant: `tst w0, #0xff; b.hs` is never
/// taken, and rendered `(w0 & 0xff) >=ᵁ 0`, always true. `b.mi` printed
/// `(w0 & 0xff) < 0 // 0`. Found by Tools/semantics/conditions.py.
@Test func aTextConditionReadsTestFlagsAsTheirSign() throws {
    let tail: [UInt32] = [0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]
    func render(_ test: UInt32, _ condition: UInt32) throws -> String {
        try textPathFunction([test, 0x54000060 | condition] + tail).renderStructured()
    }
    let tst = UInt32(0x72001c1f), ands = UInt32(0x72001c08)   // tst w0, #0xff; ands w8, w0, #0xff
    let cases: [(UInt32, UInt32, String)] = [
        (tst, 0x0, "(w0 & 0xff) == 0"),
        (tst, 0x4, "(w0 & 0xff) < 0"),     // b.mi
        (tst, 0x5, "(w0 & 0xff) >= 0"),    // b.pl
        (tst, 0xc, "(w0 & 0xff) > 0"),     // b.gt
        (tst, 0x2, "if (?)"),              // b.hs: never taken
        (tst, 0x9, "if (?)"),              // b.ls: always taken
        (ands, 0x3, "if (?)"),             // b.lo
    ]
    for (test, condition, expected) in cases {
        let text = try render(test, condition)
        #expect(text.contains(expected), Comment(rawValue: text))
        #expect(!text.contains("//"), Comment(rawValue: text))
    }
}

/// `cmn a, b` sets the flags from `a + b`. Equality and an order against a
/// nonzero immediate read as a comparison with `-b`; the others do not:
/// `cmn w0, #0; b.hs` is never taken (adding 0 never carries) but rendered
/// `w0 >=ᵁ -0`, and `cmn w0, w1; b.ge` with w1 = 0x80000000 disagrees with
/// `w0 >= -w1`. Found by Tools/semantics/conditions.py.
@Test func aTextConditionReadsAnAdditionsOrderOnlyAgainstAnImmediate() throws {
    let tail: [UInt32] = [0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]
    func render(_ test: UInt32, _ condition: UInt32) throws -> String {
        try textPathFunction([test, 0x54000060 | condition] + tail).renderStructured()
    }
    let register = UInt32(0x2b01001f), zero = UInt32(0x3100001f), seven = UInt32(0x31001c1f)
    let cases: [(UInt32, UInt32, String)] = [
        (register, 0x0, "w0 == -w1"),
        (register, 0xa, "if (?)"),          // b.ge
        (register, 0x2, "if (?)"),          // b.hs
        (zero, 0x2, "if (?)"),              // b.hs
        (zero, 0xa, "w0 >= -0"),            // b.ge
        (seven, 0x2, "w0 >=\u{1D41} -7"),   // b.hs
        (seven, 0xb, "w0 < -7"),            // b.lt
    ]
    for (test, condition, expected) in cases {
        let text = try render(test, condition)
        #expect(text.contains(expected), Comment(rawValue: text))
    }
}

/// A definition of the other width is not the value a compare tests: `eor
/// x8, x0, x1; cmp w8, #7` compares the low word of the 64-bit result,
/// `orr w8, w1, #…; cmp x8, #0; b.gt` the zero-extended word, which is
/// positive where the 32-bit expression is negative, and `mov w8, #-1; cmp
/// x8, x9` compares 0xffffffff, not the `-1` it rendered. A value proven in
/// [0, 2^31) is the same at both widths against an immediate, and a bit
/// test below 32 reads the same bit of either. Found by
/// Tools/semantics/conditions.py.
@Test func aTextConditionKeepsARegisterDefinedAtAnotherWidth() throws {
    let tail: [UInt32] = [0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]
    let cases: [([UInt32], String)] = [
        ([0xca010008, 0x71001d1f, 0x54000060], "w8 == 7"),          // eor x8, x0, x1; cmp w8, #7; b.eq
        ([0x320e8828, 0xf100011f, 0x5400006c], "x8 > 0"),           // orr w8, w1, #0x1c001c; cmp x8, #0; b.gt
        ([0x0a010008, 0x6b02011f, 0x54000060], "(w0 & w1) == w2"),  // and w8, w0, w1; cmp w8, w2; b.eq
        ([0x12800008, 0xeb09011f, 0x54000062], "x8 >=\u{1D41} x9"),   // mov w8, #-1; cmp x8, x9; b.hs
        ([0xd37efc28, 0x7100051f, 0x54000060], "(x1 >>\u{1D41} 62) == 1"),  // lsr x8, x1, #62; cmp w8, #1
        ([0x12800008, 0xf100051f, 0x5400006b], "x8 < 1"),           // mov w8, #-1; cmp x8, #1; b.lt
        ([0xd37efc28, 0x6b02011f, 0x5400006b], "w8 < w2"),          // lsr x8, x1, #62; cmp w8, w2; b.lt
        ([0xd37f3808, 0x7110011f, 0x54000068], "((x0 & 0x7fff) << 1) >\u{1D41} 0x400"),  // ubfiz x8, x0, #1, #15; cmp w8, #0x400; b.hi
        ([0xd37f7808, 0x7110011f, 0x5400006c], "w8 > 0x400"),       // ubfiz x8, x0, #1, #31: bit 31 may be set
        ([0xd37efc28, 0x6b02011f, 0x54000060], "(x1 >>\u{1D41} 62) == w2"),  // …; b.eq
        ([0x529b0009, 0xeb09011f, 0x54000060], "x8 == 0xd800"),     // mov w9, #0xd800; cmp x8, x9
        ([0x529b0008, 0xeb09011f, 0x5400006a], "0xd800 >= x9"),     // mov w8, #0xd800; cmp x8, x9; b.ge
        ([0xd37efc29, 0x6b09011f, 0x54000068], "w8 >\u{1D41} (x1 >>\u{1D41} 62)"),  // lsr x9, x1, #62; cmp w8, w9; b.hi
        ([0xca010008, 0x36180068], "bit 3 of (x0 ^ x1) clear"),     // eor x8, x0, x1; tbz w8, #3
        ([0xca010008, 0x34000068], "w8 == 0"),                      // eor x8, x0, x1; cbz w8
    ]
    for (words, expected) in cases {
        let text = try textPathFunction(words + tail).renderStructured()
        #expect(text.contains(expected), Comment(rawValue: text))
    }
}

/// A 32-bit operand that folds to a constant keeps its register: the
/// number has no width to read it at. `eor w8, wzr, #0x801f801f; cmp w8,
/// #0; b.lt` is taken, the word being negative, and rendered `0x801f801f <
/// 0`. A number in [-2^31, 2^31) reads the same at either width and stays
/// (`mov w9, #0xd800; cmp w8, w9`, a UTF-16 surrogate check). Found by
/// Tools/semantics/conditions.py.
@Test func aTextConditionKeepsAFoldedWordConstantsRegister() throws {
    let tail: [UInt32] = [0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]
    let text = try textPathFunction([0x520197e8, 0x7100011f, 0x5400006b] + tail).renderStructured()
    #expect(text.contains("w8 < 0"), Comment(rawValue: text))
    #expect(!text.contains("0x801f801f"), Comment(rawValue: text))
    let surrogate = try textPathFunction([0x529b0009, 0x6b09011f, 0x54000063] + tail).renderStructured()
    #expect(surrogate.contains("w8 <\u{1D41} 0xd800"), Comment(rawValue: surrogate))
}

/// A word test of a 64-bit copy of a call's result reads that result when
/// its declared type is a word or narrower: `mov x26, x0; cmp w26, #1`
/// after `swift_getEnumCaseMultiPayload` (`unsigned`, Enum.h:155) is a test
/// of the case index. A result of unknown or wider type keeps the register,
/// whose low word need not be the value (58 such tests in one framework
/// read `w26 != 1` until this).
@Test func aTextConditionReadsAWordResultsSavedCopy() throws {
    let tail: [UInt32] = [0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]
    // bl +0x100; mov x26, x0; cmp w26, #1; b.ne +12; ...
    func render(_ callee: String) throws -> String {
        let function = try textPathFunction([0x94000040, 0xaa0003fa, 0x7100075f, 0x54000061] + tail)
        let instructions = function.instructions.enumerated().map { index, insn in
            index == 0 ? Instruction(address: insn.address, text: insn.text, controlFlow: insn.controlFlow,
                                     branchTarget: insn.branchTarget, detail: insn.detail, callee: .kept(callee))
                : insn
        }
        return DisassembledFunction(symbol: function.symbol, demangledName: nil, startAddress: function.startAddress,
                                    instructions: instructions, source: .symbol).renderStructured()
    }
    let cases: [(String, String)] = [
        ("swift_getEnumCaseMultiPayload", "if (swift_getEnumCaseMultiPayload() != 1)"),
        ("getEnumTag value witness for M.E", "if (getEnumTag value witness for M.E() != 1)"),
        ("M.tag() -> Swift.UInt8", "if (M.tag() != 1)"),
        ("M.count() -> Swift.Int", "if (w26 != 1)"),
        ("sub_2000", "if (w26 != 1)"),
    ]
    for (callee, expected) in cases {
        let text = try render(callee)
        #expect(text.contains(expected), Comment(rawValue: text))
    }
}

/// In an ObjC method the text path names x2–x7 as the arguments they
/// arrive as, but only where no path from entry can have written them:
/// `add x2, x9, #1; cmp x2, #0` rendered `arg0 == 0`, and so did a test of
/// x2 in a block after a call, which clobbers it.
@Test func aTextConditionNamesAnArgumentOnlyWhereItArrived() throws {
    let engine = try #require(CapstoneEngine())
    func condition(_ words: [UInt32], block: Int) throws -> String {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        let function = DisassembledFunction(symbol: "_m", demangledName: nil, startAddress: 0x1000,
            instructions: decoded.map { Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                                                    branchTarget: $0.branchTarget, detail: $0.detail) }, source: .symbol)
        let blocks = function.basicBlocks()
        return ControlFlowStructure(blocks: blocks, objectiveCArguments: true).condition(of: blocks[block]).text
    }
    let test: [UInt32] = [0xf100005f, 0x54000040, 0xd65f03c0, 0xd65f03c0]   // cmp x2, #0; b.eq +8; ret; ret
    #expect(try condition(test, block: 0) == "arg0 == 0")
    #expect(try condition([0x91000522] + test, block: 0) == "x2 == 0")              // add x2, x9, #1
    #expect(try condition([0x94000040, 0x14000001] + test, block: 1) == "x2 == 0")  // bl +0x100; b +4
    #expect(try condition([0x91000523, 0x14000001] + test, block: 1) == "arg0 == 0") // add x3, …: x2 untouched
}

/// A signed order of 32-bit operands compares their sign-extended values,
/// and a w register's sign is bit 31 of its low half. `cmp w9, w8; b.lt`
/// with w8 = -100000 read `… < 0xfffe7960` over zero-extended operands,
/// taking the wrong branch for every non-negative sum, and `tbnz w0, #31`
/// read `arg0 < 0`, the sign of an undefined high half (`signed32.c`, ABI
/// review item 3).
@Test func aSigned32BitComparisonSignExtendsItsOperandsIfPresent() async throws {
    let path = "Fixtures/Sample/libSigned32.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }).renderStructured()
    }
    let cmp = try text("_s_cmp")
    #expect(cmp.contains("<< 32) >>ˢ 32) < -100000)"), Comment(rawValue: cmp))
    let neg = try text("_s_neg")
    #expect(neg.contains("if (((arg0 << 32) >>ˢ 32) < 0)"), Comment(rawValue: neg))
}

import Testing
@testable import SwiftDecompilerCore

/// The structurer treats x21 as the Swift error register only when a function
/// genuinely threads swifterror: it **clears** x21 before a throwing call *and*
/// **tests** it against zero after, to catch the throw. Requiring both — not the
/// clear alone — is what fixed two measured misfires where an incidental x21
/// zeroing suppressed a recovered-but-declined value to a bare `return`
/// (Objective-C `isEqual:`; Combine Publisher constructors). See the init in
/// `Structurer.swift`.
///
/// These unit-test the two discriminators directly, which is fast and portable;
/// the end-to-end direction is covered by `ObjCValuelessReturnTests` (real
/// system ObjC) and, host-gated, by the Combine check below.

private func block(_ texts: [String]) -> [BasicBlock] {
    let instructions = texts.enumerated().map { index, text in
        Instruction(address: UInt64(index * 4), text: text)
    }
    return [BasicBlock(startAddress: 0, instructions: instructions, successors: [])]
}

// MARK: - clears

@Test func detectsClearingTheSwiftErrorRegister() {
    #expect(ControlFlowStructure.clearsSwiftErrorRegister(block(["mov x21, #0"])))
    #expect(ControlFlowStructure.clearsSwiftErrorRegister(block(["mov w21, #0"])))
    #expect(ControlFlowStructure.clearsSwiftErrorRegister(block(["mov x21, xzr"])))
}

@Test func doesNotMistakeOtherMovesForClearingX21() {
    // Moving a value INTO x21, or zeroing a different register, is not a clear.
    #expect(!ControlFlowStructure.clearsSwiftErrorRegister(block(["mov x21, x0"])))
    #expect(!ControlFlowStructure.clearsSwiftErrorRegister(block(["mov x20, #0"])))
    #expect(!ControlFlowStructure.clearsSwiftErrorRegister(block(["mov w2, #0x21"])))  // imm, not reg
}

// MARK: - tests against zero

@Test func detectsTestingTheSwiftErrorRegisterAgainstZero() {
    #expect(ControlFlowStructure.testsSwiftErrorRegister(block(["cbz x21, 0x100"])))
    #expect(ControlFlowStructure.testsSwiftErrorRegister(block(["cbnz x21, 0x100"])))
    #expect(ControlFlowStructure.testsSwiftErrorRegister(block(["cmp x21, #0"])))
    #expect(ControlFlowStructure.testsSwiftErrorRegister(block(["subs x21, x21, xzr"])))
}

@Test func aTestAgainstARegisterIsNotASwiftErrorTest() {
    // The exact ObjC `isEqual:` shape: x21 compared to another register, not to
    // zero — comparing objects, not checking for a thrown error. This is the case
    // that must NOT qualify, or the ObjC misfire returns.
    #expect(!ControlFlowStructure.testsSwiftErrorRegister(block(["cmp x21, x0"])))
    #expect(!ControlFlowStructure.testsSwiftErrorRegister(block(["cbz x20, 0x100"])))
    #expect(!ControlFlowStructure.testsSwiftErrorRegister(block(["cmp x0, #0"])))
}

// MARK: - the combined discriminator, by shape

@Test func swifterrorRequiresBothAClearAndAZeroTest() {
    // Genuine swifterror: clears then tests against zero.
    let genuine = block(["mov x21, #0", "bl _throwingCallee", "cbnz x21, 0x100"])
    #expect(ControlFlowStructure.clearsSwiftErrorRegister(genuine)
        && ControlFlowStructure.testsSwiftErrorRegister(genuine))

    // Bool/pointer scratch: clears x21 but never tests it against zero. The Swift
    // Publisher-constructor misfire.
    let scratch = block(["mov x21, x0", "mov w21, #0", "mov x0, x21", "ret"])
    #expect(ControlFlowStructure.clearsSwiftErrorRegister(scratch)
        && !ControlFlowStructure.testsSwiftErrorRegister(scratch))

    // ObjC isEqual:: clears x21, tests it against a register (not zero).
    let objcIsEqual = block(["mov x21, x0", "mov w21, #0", "cmp x21, x0", "ret"])
    #expect(ControlFlowStructure.clearsSwiftErrorRegister(objcIsEqual)
        && !ControlFlowStructure.testsSwiftErrorRegister(objcIsEqual))
}

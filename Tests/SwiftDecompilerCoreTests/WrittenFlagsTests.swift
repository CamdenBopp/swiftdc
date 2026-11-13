import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A compare that writes its own operand (`subs w19, w19, #2; b.hi`) tests
/// the value before it, while the register holds the value after it at the
/// branch. Rendered by the register's name, `w19 >ᵁ 2` was one step off and
/// `subs x9, x9, #1; b.ne` read `x9 != 1`, a loop testing a register it never
/// changes (`writtenflags.c`). Equality reads as the result against 0; an
/// order declines.
@Test(arguments: ["Fixtures/Sample/libWrittenFlags.dylib", "Fixtures/Sample/libWrittenFlags.O1.dylib"])
func aCompareThatWritesItsOperandIsReadByItsResultIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    let down = try structured("_down2")
    #expect(!down.contains("w19 >") && down.contains("if (?)"), Comment(rawValue: down))
    let sum = try structured("_sum")
    #expect(sum.contains("while (x9 != 0)"), Comment(rawValue: sum))
    #expect(!sum.contains("!= 1)") && !sum.contains("!= 0x10)") && !sum.contains("!= -4)"), Comment(rawValue: sum))
}

@Test func aRegisterIsMentionedOnlyAsAWholeWord() {
    #expect(ControlFlowStructure.mentionsRegister("x19", in: "w19 > 2"))
    #expect(ControlFlowStructure.mentionsRegister("x19", in: "(x19 + 1)"))
    #expect(!ControlFlowStructure.mentionsRegister("x19", in: "x190 > 2"))
    #expect(!ControlFlowStructure.mentionsRegister("x1", in: "x19 > 2"))
    #expect(!ControlFlowStructure.mentionsRegister("x19", in: "arg0"))
}

/// A register another instruction rewrites between the compare and the
/// branch means its new value at the branch: `cmp w21, w19; add w21, w21,
/// #3; b.lt` read `w21 < w19`, three off, and `cmp w19, #1; lsr w19, w19,
/// #1` read a test of the shifted value. Such a condition declines.
@Test(arguments: ["Fixtures/Sample/libWrittenFlags.dylib", "Fixtures/Sample/libWrittenFlags.O1.dylib"])
func aCompareWhoseOperandIsRewrittenBeforeTheBranchDeclinesIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    let steps = try structured("_two_steps")
    #expect(!steps.contains("w21 < w19") && steps.contains("if (?)"), Comment(rawValue: steps))
    let bits = try structured("_each_bit")
    #expect(!bits.contains("w19 <ᵁ") && !bits.contains("w19 >=ᵁ") && !bits.contains("w19 != 1)") && !bits.contains("w19 == 1)"),
            Comment(rawValue: bits))
}

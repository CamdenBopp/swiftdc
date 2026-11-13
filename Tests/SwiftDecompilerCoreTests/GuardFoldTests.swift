import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A branch to a trap is folded away as the compiler's own overflow check
/// only when its trap edge is the overflow of the arithmetic that set the
/// flags. Any other branch to a trap is the program's `precondition` and
/// stays. Each of the four `pre…` functions lost its trap: `precondition(a
/// < b); return a &- b` rendered `return (arg0 - arg1)` (`guardfold.swift`,
/// -O).
@Test func aPreconditionIsNotFoldedAsAnOverflowCheckIfPresent() async throws {
    let path = "Fixtures/Sample/libGuardFold.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("GF.\(name)(") }, "no \(name)").renderStructured()
    }
    // `subs; b.hs trap`: carry set after a subtract is "no borrow".
    let less = try structured("preLess")
    #expect(less.contains("if (arg0 >= arg1) {\n        trap()"), Comment(rawValue: less))
    // `adds; b.vc trap`: the trap edge is "did not overflow".
    let overflowed = try structured("preOverflowed")
    #expect(overflowed.contains("trap()"), Comment(rawValue: overflowed))
    // `fcmp; b.vs trap`: V after a float compare is "unordered".
    let nan = try structured("preNotNaN")
    #expect(nan.contains("trap()"), Comment(rawValue: nan))
    // `subs; csel; cmp; b.hs trap`: the compare owns the flags.
    let after = try structured("preAfterSubtract")
    #expect(after.contains(">=ᵁ arg2) {\n        trap()"), Comment(rawValue: after))
    // The compiler's checks still fold: `adds; b.vs`, `adds; b.hs`, `subs; b.lo`.
    for name in ["checkedAdd", "checkedAddUnsigned", "checkedSubtractUnsigned"] {
        let text = try structured(name)
        #expect(!text.contains("trap()") && !text.contains("if ("), Comment(rawValue: text))
    }
}

/// The trap edge decides, not the branch's own condition: with the trap as
/// the fall-through, `adds; b.vc ok; brk` traps on overflow and folds, and
/// `adds; b.vs ok; brk` traps when the add did not overflow and stays.
@Test func theTrapEdgeOfAGuardDecidesWhetherItFolds() throws {
    func structured(_ words: [UInt32]) throws -> String {
        let engine = try #require(CapstoneEngine())
        let instructions = engine.disassemble(words.withUnsafeBytes { Data($0) }, address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        try #require(instructions.count == words.count)
        return DisassembledFunction(symbol: "_guard", demangledName: "M.guarded(Swift.Int, Swift.Int) -> Swift.Int",
                                    startAddress: 0x1000, instructions: instructions, source: .symbol)
            .renderStructured()
    }
    //   adds x0, x0, x1 ; b.vc +8 ; brk #1 ; ret
    let folds = try structured([0xab010000, 0x54000047, 0xd4200020, 0xd65f03c0])
    #expect(!folds.contains("trap()"), Comment(rawValue: folds))
    //   adds x0, x0, x1 ; b.vs +8 ; brk #1 ; ret
    let stays = try structured([0xab010000, 0x54000046, 0xd4200020, 0xd65f03c0])
    #expect(stays.contains("trap()"), Comment(rawValue: stays))
    // The flags are the last writer's. Here an earlier `subs` would match
    // the trap edge (`lo`), but the `cmp` after it owns the flags:
    //   subs x8, x0, x1 ; cmp x8, x2 ; b.hs +8 ; brk #1 ; mov x0, x8 ; ret
    let compared = try structured([0xeb010008, 0xeb02011f, 0x54000042, 0xd4200020, 0xaa0803e0, 0xd65f03c0])
    #expect(compared.contains("trap()"), Comment(rawValue: compared))
    // Signed overflow is a checked operation's even when its sum is
    // discarded (seen in libSwiftCompilerPluginMessageHandling):
    //   add x8, x0, #1 ; cmn x8, #1 ; b.vc +8 ; brk #1 ; mov x0, x8 ; ret
    let discarded = try structured([0x91000408, 0xb100051f, 0x54000047, 0xd4200020, 0xaa0803e0, 0xd65f03c0])
    #expect(!discarded.contains("trap()"), Comment(rawValue: discarded))
}

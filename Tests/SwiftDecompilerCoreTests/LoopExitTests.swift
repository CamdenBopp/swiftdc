import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An exit from an inner loop that leaves the outer loop too
/// (`loopexit.swift`, -O). The inner loop's exit is where the structurer
/// stops, so the text after the inner loop is the rest of the outer loop's
/// body, and a `break` ran it: `stopAll` read `if (ext(?) == 6) { break }`
/// into `sink(-i)` and the outer test, where the code returns. Such an exit
/// is spelled out: the tail it reaches, or a goto to the code after both.
@Test func anExitLeavingTwoLoopsIsNotABreakIfPresent() async throws {
    let path = "Fixtures/Sample/libLoopExit.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func exitLine(_ name: String) throws -> String {
        let text = try #require(functions.first { $0.displayName.hasPrefix(name) }, "no \(name)").renderStructured()
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let test = try #require(lines.firstIndex { $0.hasPrefix("if (LoopExit.ext(?) == 6)") }, Comment(rawValue: text))
        return lines[test + 1]
    }
    #expect(try exitLine("LoopExit.stopAll") == "return")
    #expect(try exitLine("LoopExit.leaveBoth") == "return")
    let outer = try exitLine("LoopExit.breakOuter")
    #expect(outer.hasPrefix("goto loc_"), Comment(rawValue: outer))
    let text = try #require(functions.first { $0.displayName.hasPrefix("LoopExit.breakOuter") }).renderStructured()
    let label = String(outer.dropFirst("goto ".count)) + ":"
    let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    let at = try #require(lines.firstIndex(of: label), Comment(rawValue: text))
    #expect(lines[at + 1] == "LoopExit.sink(100)", Comment(rawValue: text))
}

/// A loop body never falls through to where its emission stops: off the
/// end of a body the loop runs again. `threeDeep`'s outer latch, emitted
/// inside the middle loop, read `if (x21 != x19) { goto loc_690 }` into
/// `sink(-j)`, where the code returns.
@Test func aLoopBodyDoesNotFallThroughToItsStopIfPresent() async throws {
    let path = "Fixtures/Sample/libLoopExit.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.displayName.hasPrefix("LoopExit.threeDeep") }).renderStructured()
    let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    let back = try #require(lines.firstIndex { $0.hasPrefix("goto loc_") && $0.hasSuffix("// loop") }, Comment(rawValue: text))
    #expect(lines[back + 1] == "}", Comment(rawValue: text))
    #expect(lines[back + 2] == "return", Comment(rawValue: text))
}

/// The loop's single exit needs no added transfer: every edge to it is
/// already its exit statement. Added anyway, `stopAll` read a dead `return`
/// between its inner loop and the label that follows it.
@Test func aLoopsSingleExitGetsNoDeadTransferIfPresent() async throws {
    let path = "Fixtures/Sample/libLoopExit.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.displayName.hasPrefix("LoopExit.stopAll") }).renderStructured()
    let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    for index in lines.indices.dropLast(2) where lines[index] == "}" {
        #expect(!(lines[index + 1] == "return" && lines[index + 2].hasPrefix("loc_")), Comment(rawValue: text))
    }
}

/// An arm ends in a transfer when its last line is one, or when it ends in
/// an `if`/`else` whose arms both do; an `if` without `else`, a loop and an
/// empty arm can fall through.
@Test func anArmEndsInATransferThroughNestedIfElse() {
    #expect(ControlFlowStructure.endsInTransfer(["    goto loc_10"]))
    #expect(!ControlFlowStructure.endsInTransfer([]))
    #expect(!ControlFlowStructure.endsInTransfer(["    f()"]))
    #expect(ControlFlowStructure.endsInTransfer([
        "    if (a) {", "        continue", "    } else {", "        goto loc_10", "    }",
    ]))
    #expect(!ControlFlowStructure.endsInTransfer([
        "    if (a) {", "        continue", "    } else {", "        f()", "    }",
    ]))
    #expect(!ControlFlowStructure.endsInTransfer(["    if (a) {", "        continue", "    }"]))
    #expect(!ControlFlowStructure.endsInTransfer(["    while (true) {", "        break", "    }"]))
}

/// A loop body's added transfer is never dead. `deadexit.s`'s loops end
/// their bodies in an if/else that leaves on both arms, and each gained a
/// `return` after it that nothing reaches (as stripped swift-syntax's
/// `sub_8ec8` did).
@Test func noTransferFollowsAnIfElseThatLeavesOnBothArmsIfPresent() async throws {
    let path = "Fixtures/Sample/libDeadExit.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.displayName == "_twoExits" }).renderStructured()
    let returns = text.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces) == "return" }
    #expect(returns.count == 2, Comment(rawValue: text))
}

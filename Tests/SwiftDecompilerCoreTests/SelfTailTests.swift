import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A `br` resolved to an address inside its own function is a tail call,
/// not a jump (`selftail.swift`, -O). `countdown` tail-calls itself
/// through self's vtable; as a branch target the resolution became an edge
/// back to the entry, and the structured view a `while` loop around the
/// call whose condition never changes. Resolved without an edge, the
/// `br` is still a tail call, so it returns what the callee returns.
@Test func aTailCallResolvedIntoItsOwnFunctionIsNoLoopIfPresent() async throws {
    let path = "Fixtures/Sample/libSelfTail.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "countdown")
    }
    let function = try #require(functions.first { $0.displayName.hasPrefix("SelfTail.Counter.countdown") })
    let text = function.renderStructured()
    #expect(!text.contains("while"), Comment(rawValue: text))
    #expect(text.contains("self.countdown((arg0 - 1))"), Comment(rawValue: text))
    // The tail call forwards its result: x0 at the `br` is the argument,
    // and what the callee returns is what countdown returns.
    #expect(text.contains("return self.countdown((arg0 - 1))"), Comment(rawValue: text))
    let branch = try #require(function.instructions.first { $0.text.hasPrefix("br") })
    #expect(branch.branchTarget == nil && branch.callee?.hasPrefix("SelfTail.Counter.countdown") == true)
}

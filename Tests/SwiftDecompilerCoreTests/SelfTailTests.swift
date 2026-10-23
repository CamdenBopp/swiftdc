import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A `br` resolved to an address inside its own function is a tail call,
/// not a jump (`selftail.swift`, -O). `countdown` tail-calls itself
/// through self's vtable; as a branch target the resolution became an edge
/// back to the entry, and the structured view a `while` loop around the
/// call whose condition never changes.
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
    let branch = try #require(function.instructions.first { $0.text.hasPrefix("br") })
    #expect(branch.branchTarget == nil && branch.callee?.hasPrefix("SelfTail.Counter.countdown") == true)
}

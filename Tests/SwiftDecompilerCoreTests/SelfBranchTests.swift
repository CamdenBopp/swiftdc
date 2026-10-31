import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A `b` to a function's own entry is a loop's edge, which the CFG already
/// draws. Its callee made it a call as well: `error_exit_controls.s`'s
/// `entryBackEdge` ("The entry block is also a loop target") rendered
/// `ExitProof.entryBackEdge(arg0)` inside its loop, and Go's stack-growth
/// prologue rendered `while (sp <=ᵁ x16) { runtime.morestack_noctxt();
/// main.main() }`.
@Test func aBranchToTheOwnEntryIsNoCallIfPresent() async throws {
    let path = "Fixtures/Sample/libErrorExitControls.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "entryBackEdge")
    }
    let function = try #require(functions.first { $0.symbol.contains("entryBackEdge") })
    let branch = try #require(function.instructions.first { $0.controlFlow == .branch && $0.branchTarget == function.startAddress })
    #expect(branch.callee == nil)
    let body = function.renderStructured().split(separator: "\n").dropFirst()
    #expect(body.contains { $0.contains("while") }, "\(function.renderStructured())")
    #expect(!body.contains { $0.contains("entryBackEdge(") }, "\(function.renderStructured())")
}

@Test func goStackGrowthIsALoopWithoutACallIfPresent() async throws {
    let path = "Fixtures/Sample/goProgram.stripped"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "main.main")
    }
    let main = try #require(functions.first { $0.symbol == "_main.main" })
    let rendered = main.renderStructured()
    let body = rendered.split(separator: "\n").dropFirst()
    #expect(body.contains { $0.contains("runtime.morestack_noctxt()") }, "\(rendered)")
    #expect(!body.contains { $0.contains("main.main(") }, "\(rendered)")
}

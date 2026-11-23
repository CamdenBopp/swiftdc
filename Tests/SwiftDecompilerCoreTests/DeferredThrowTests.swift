import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A throw that joins the normal path before the `ret` was printed at the
/// end of its own path, ahead of the block the two share. That block was
/// taken for the epilogue alone. With a `defer` it holds the deferred work,
/// which then read as skipped by the throw and followed by a plain return:
/// `defer { ledger.entries = 99 }; if x == 3 { throw … }` rendered
/// `throw ?`, then `arg0.entries = 99`, then `return`. deferthrow.swift
/// states each function's true behaviour.
private func views(_ name: String) async throws -> [String]? {
    let path = "Fixtures/Sample/libDeferThrow.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let function = try #require(functions.first { $0.displayName.hasPrefix("DeferThrow.\(name)(") })
    return [function.renderStructured(), function.renderPseudo()]
}

/// Lines of `text` in order, trimmed.
private func lines(_ text: String) -> [String] {
    text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
}

@Test(arguments: [("storeThenExit", "arg0.entries = 99"), ("callThenExit", "DeferThrow.record(7)")])
func aThrowIsNotPrintedAheadOfWorkItSharesIfPresent(name: String, work: String) async throws {
    guard let views = try await views(name) else { return }
    for text in views {
        let lines = lines(text)
        // The work is there once, after the error is made, and nothing
        // says the function throws or returns before or around it.
        let workAt = try #require(lines.firstIndex(of: work), Comment(rawValue: text))
        #expect(lines.filter { $0 == work }.count == 1, Comment(rawValue: text))
        let hook = try #require(lines.firstIndex { $0.hasPrefix("swift_willThrow(") }, Comment(rawValue: text))
        #expect(hook < workAt, Comment(rawValue: text))
        #expect(!lines.contains { $0.hasPrefix("throw") }, Comment(rawValue: text))
        #expect(!lines.contains("return"), Comment(rawValue: text))
        // The exit is both outcomes' and is spelled so.
        #expect(lines[(workAt + 1)...].first == DisassembledFunction.unresolvedSwiftExitStatement, Comment(rawValue: text))
    }
}

/// The control: a shared block that is the epilogue alone still ends its
/// throwing path in the throw, and returns after it.
@Test func aThrowIntoABareEpilogueIsStillPrintedOnItsPathIfPresent() async throws {
    guard let views = try await views("plainExit") else { return }
    let structured = lines(views[0])
    let hook = try #require(structured.firstIndex { $0.hasPrefix("swift_willThrow(") }, Comment(rawValue: views[0]))
    #expect(structured[hook + 1] == "throw ?", Comment(rawValue: views[0]))
    #expect(structured.contains("return"), Comment(rawValue: views[0]))
    #expect(!structured.contains(DisassembledFunction.unresolvedSwiftExitStatement), Comment(rawValue: views[0]))
}

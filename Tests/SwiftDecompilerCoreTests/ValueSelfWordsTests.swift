import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A small integer struct's non-mutating method takes its self's words in
/// the general registers after its formals (`valueselfwords.swift`, -O):
/// `g(_ k:)` has k in x0 and s in x1. Seeded only with no formals, every
/// such method with one read `return ?`.
@Test func aStructsSelfWordsFollowItsFormalsIfPresent() async throws {
    let path = "Fixtures/Sample/libValueSelfWords.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("return (self.s - arg0)"), Comment(rawValue: text))
    #expect(text.contains("return (arg1 + (self.s * arg0))"), Comment(rawValue: text))
    #expect(text.contains("return (self.q - arg0)"), Comment(rawValue: text))
    // A float formal is in its own bank: self.s is still x0.
    let scaled = try await withStableDependencies { try await LabReport.report(path: path, function: "One.scaled") }
    #expect(scaled.contains("seeds: x0=self[0] v0=arg0"), Comment(rawValue: scaled))
}

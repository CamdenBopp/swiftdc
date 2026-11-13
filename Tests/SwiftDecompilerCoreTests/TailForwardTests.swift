import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A function ending in a branch to a callee that returns its result: the
/// tail-return rule took only callees with a Swift argument list and
/// non-generic callers, so `countLit() { "hello".count }` (`b
/// String.count.getter`) and `dynType<T>(_:)` (`b swift_getDynamicType`)
/// rendered the call with no `return` (`tailforward.swift`, -O).
@Test func aTailBranchToAGetterOrRuntimeEntryReturnsItIfPresent() async throws {
    let path = "Fixtures/Sample/libTailForward.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix(name) }, "no \(name)").renderStructured()
    }
    let count = try structured("TailForward.countLit(")
    #expect(count.contains("return Swift.String.count.getter(\"hello\")"), Comment(rawValue: count))
    let dyn = try structured("TailForward.dynType<")
    #expect(dyn.contains("return swift_getDynamicType("), Comment(rawValue: dyn))
}

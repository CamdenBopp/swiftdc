import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A throw of an error that already exists ends in a throw of that value.
/// `throw e` is `mov x21, x0; bl swift_willThrow; …; ret` with x21 still
/// `e`, and only a fresh `swift_allocError` box was recognised, so it
/// rendered `machine_return() /* unresolved Swift success/error exit */`
/// (`throwvalue.swift`, -Onone and -O).
@Test func aThrownErrorParameterIsThrownIfPresent() async throws {
    for level in ["Onone", "O"] {
        let path = "Fixtures/Sample/libThrowValue.\(level).dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        func structured(_ name: String) throws -> String {
            try #require(functions.first { $0.displayName.hasPrefix("TV.\(name)(") }, "\(level) \(name)")
                .renderStructured()
        }
        let plain = try structured("rethrowIt")
        #expect(plain.contains("throw arg0") && !plain.contains("machine_return"), "\(level): \(plain)")
        // On one path; the other still returns.
        let guarded = try structured("failIfZero")
        #expect(guarded.contains("throw arg1") && guarded.contains("return arg0"), "\(level): \(guarded)")
        // A rethrow of a callee's error shares its `ret` with the normal
        // return, and x21 is known on neither: no throw is claimed for it.
        let passed = try structured("passOn")
        // A fresh `swift_allocError` box is not a source value: `throw ?`.
        let boxed = try structured("risky")
        #expect(boxed.contains("throw ?") && !boxed.contains("throw r") && !boxed.contains("throw swift_allocError"),
                "\(level): \(boxed)")
        let statements = passed.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(!statements.contains { $0.hasPrefix("throw ") }, "\(level): \(passed)")
    }
}

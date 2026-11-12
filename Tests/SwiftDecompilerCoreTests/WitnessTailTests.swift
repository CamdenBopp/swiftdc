import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A protocol witness that tail-calls its conforming member forwards the
/// member's result: `ldr x0, [x20]; b V.count`. The tail-return rule read
/// only an ordinary `Module.Type.member` caller, which a witness's name is
/// not, so it rendered `V.count(self: ?)` with no `return`
/// (`witnesstail.swift`, -O). A witness is read by its requirement.
@Test func aWitnessTailCallReturnsTheMembersResultIfPresent() async throws {
    let path = "Fixtures/Sample/libWitnessTail.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let witness = try #require(functions.first { $0.displayName.hasPrefix("protocol witness for WitnessTail.Counted.count()") })
    let text = witness.renderStructured()
    #expect(text.contains("return WitnessTail.V.count("), Comment(rawValue: text))
    #expect(Disassembler.witnessRequirement(
        "protocol witness for M.P.f() -> Swift.Int in conformance M.V : M.P in M") == "M.P.f() -> Swift.Int")
    #expect(Disassembler.witnessRequirement("M.V.f() -> Swift.Int") == nil)
}

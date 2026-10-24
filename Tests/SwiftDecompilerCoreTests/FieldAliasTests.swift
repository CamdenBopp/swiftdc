import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A register loaded from or stored to a field of self was known to equal
/// that field until the next store to a field, but a call may write the
/// field too: `field_aliases.swift` (-O) `let old = a; bumpA(); b = old`
/// rendered `bumpA(); self.b = self.a`, the incremented a, and
/// `let old = a; bumpA(); return old` rendered `return self.a`, the same
/// text as `bumpA(); return a`, which is right only there.
@Test func aFieldAliasDoesNotSurviveACallThatMayWriteItIfPresent() async throws {
    let path = "Fixtures/Sample/libFieldAliases.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    func pseudo(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FieldAliases.Box.\(name)(") }).renderPseudo()
    }
    for name in ["stale", "storeTwice"] {
        let text = try pseudo(name)
        #expect(text.contains("self.b = ") && !text.contains("self.b = self.a"), "\(name): \(text)")
    }
    let staleReturn = try pseudo("staleReturn")
    #expect(!staleReturn.contains("return self.a"), "\(staleReturn)")
    // A load after the call is the field's current value.
    let fresh = try pseudo("fresh")
    #expect(fresh.contains("return self.a\n"), "\(fresh)")
}

/// Only a retain or an access marker leaves every field alone. A release
/// can run a deinit, which may write a field of anything it reaches, and an
/// in-image function that merely shares a runtime name proves nothing.
@Test func onlyRetainsAndAccessMarkersWriteNoFields() {
    for callee in ["swift_retain", "_swift_bridgeObjectRetain", "objc_retain", "objc_retain_x19", "swift_beginAccess",
                   "swift_endAccess"] {
        #expect(ValueTracer.CallFacts(callee: callee).writesNoFields, "\(callee)")
    }
    for callee in ["swift_release", "objc_release", "swift_bridgeObjectRelease", "Box.bumpA()", "memcpy"] {
        #expect(!ValueTracer.CallFacts(callee: callee).writesNoFields, "\(callee)")
    }
    #expect(!ValueTracer.CallFacts(callee: "swift_retain", knownArityApplies: false).writesNoFields)
}

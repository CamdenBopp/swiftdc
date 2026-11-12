import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A closure's printed signature lists its formals only; what it captured
/// follows as more arguments. The forwarder for `{ y in y &+ k }` passes k
/// in x1 and rendered `closure #1 (arg0)` (`closurecapture.swift`, -Onone).
/// A closure's call is laid out from what its body reads.
@Test func aClosuresCapturesAreArgumentsIfPresent() async throws {
    let path = "Fixtures/Sample/libClosureCapture.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let forwarder = try #require(functions.first { $0.displayName.hasPrefix("partial apply forwarder for closure #1") })
    let text = forwarder.renderStructured()
    #expect(text.contains("closure #1 (arg0, ?)"), Comment(rawValue: text))
}

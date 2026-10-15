import Foundation
import Testing
@testable import SwiftDecompilerCore

private func pseudo(_ name: String, in path: String) async throws -> String? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: name)
    }
    return try #require(functions.first { $0.displayName.hasPrefix(name) }).renderPseudo()
}

/// A runtime entry point of known C arity shows exactly its parameters.
/// `swift_errorRelease` whose object was unknown read `swift_errorRelease()`,
/// a call that takes nothing.
@Test func aKnownArityCallKeepsItsUnknownParametersIfPresent() async throws {
    guard let text = try await pseudo("SwiftErrorProbe.tryHidden(", in: "Fixtures/Sample/libSwiftErrorProbe.dylib")
    else { return }
    #expect(text.contains("swift_errorRelease(?)"), Comment(rawValue: text))
    #expect(!text.contains("swift_errorRelease()"), Comment(rawValue: text))
}

/// And no more than its parameters: `memset` read stale x3 and x4 as two
/// more arguments.
@Test func aKnownArityCallDropsRegistersPastItsParametersIfPresent() async throws {
    guard let text = try await pseudo("ABISource.ABIFiveWords.init(", in: "Fixtures/Sample/libABISource.dylib")
    else { return }
    #expect(text.contains("memset(local_38, 0, 40)"), Comment(rawValue: text))
    #expect(!text.contains("memset(local_38, 0, 40,"), Comment(rawValue: text))
}

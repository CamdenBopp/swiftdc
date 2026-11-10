import Testing
import Foundation
import Demangling
@testable import SwiftDecompilerCore

// MARK: - The fixture

private func functions(_ path: String) async throws -> [DisassembledFunction]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    return try await withStableDependencies { try await Disassembler().disassemble(path: path) }
}

/// The body of the one specialization of `base` whose name holds `marker`.
private func body(_ functions: [DisassembledFunction], _ base: String, _ marker: String = "") throws -> String {
    let matches = functions.filter {
        $0.displayName.contains("specialization <") && $0.displayName.contains("of DroppedArgs.\(base)")
            && (marker.isEmpty || $0.displayName.contains(marker))
    }
    #expect(matches.count == 1, "\(base) \(marker): \(matches.map(\.displayName))")
    return try #require(matches.first).renderStructured()
}

private func caller(_ functions: [DisassembledFunction], _ name: String) throws -> String {
    try #require(functions.first { $0.displayName.hasPrefix("DroppedArgs.\(name)(") }).renderStructured()
}

/// -O and -Osize define the same specializations with the same signatures.
private let optimizedBuilds = ["Fixtures/Sample/libDroppedArgs.dylib", "Fixtures/Sample/libDroppedArgs.Osize.dylib"]

/// A closure-propagated clause prints an unclosed `[`, and the signature was
/// left in the call: `… P.apply<A>(A.Type, Swift.Int, (Swift.Int) -> Swift.Int)
/// -> Swift.Int(arg0, arg0)`.
@Test(arguments: optimizedBuilds)
func aClosurePropagatedCallHasNoSignatureInItIfPresent(path: String) async throws {
    guard let functions = try await functions(path) else { return }
    let text = try caller(functions, "useApply")
    #expect(text.contains("of DroppedArgs.apply<A>(arg0, arg0)"), Comment(rawValue: text))
}

import Foundation
import Testing
@testable import SwiftDecompilerCore

private func structured(_ path: String) async throws -> [String: String] {
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    return Dictionary(functions.map { ($0.displayName, $0.renderStructured()) }, uniquingKeysWith: { a, _ in a })
}

/// `[[arg - 8] + k]` called with the same argument where the witness takes
/// its metadata is that argument's value witness k (`valueWitnessCall`).
/// The same loads with another argument passed as the metadata, or a load
/// at `-16`, prove nothing and stay unresolved.
@Test func aValueWitnessThroughArgumentMetadataIsNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libValueWitnessArgs.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let text = try await structured(path)
    #expect(text["_vwDestroy"]?.contains("destroy value witness for arg1(arg0, arg1)") == true, "\(text["_vwDestroy"] ?? "")")
    for name in ["_vwOtherMetadata", "_vwNotTheTable"] {
        #expect(text[name]?.contains("value witness") == false, "\(name)")
        #expect(text[name]?.contains("unresolved call") == true, "\(name)")
    }
}

/// A stripped generic function the optimizer never specialized receives
/// its metadata as an argument: `assignCopy` destroys `a`, and
/// `duplicate` copies `x` into a temporary and takes it into `box`.
@Test func aStrippedGenericFunctionsValueWitnessesAreNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libArgumentWitness.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let all = try await structured(path).values.joined(separator: "\n")
    // Named for an operation, still not an address: unresolved dispatch.
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let graph = CallGraph(functions: functions)
    #expect(graph.unresolvedCallSites == 3 && graph.externalCallSites == 1)
    #expect(all.contains("destroy value witness for arg2(arg0, arg2)"))
    #expect(all.contains("initializeWithCopy value witness for arg2(?, arg0, arg2)"))
    #expect(all.contains("initializeWithTake value witness for arg2(arg1, ?, arg2)"))
}

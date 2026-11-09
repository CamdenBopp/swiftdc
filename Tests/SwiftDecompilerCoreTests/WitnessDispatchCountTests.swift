import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A call named for a value witness of a type the binary does not fix
/// (`destroy value witness for A`) has no address: any type's witness may
/// run. The call graph counted it as an import called through its GOT
/// slot, so `xrefs --unreferenced` disclosed no indirect dispatch for
/// three calls that may reach this image's functions.
@Test func aWitnessCallCountsAsUnresolvedNotExternalIfPresent() async throws {
    let path = "Fixtures/Sample/libArgumentWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let calls = functions.flatMap(\.instructions).filter { $0.controlFlow == .call && $0.branchTarget == nil }
    #expect(calls.filter(\.facts.isWitnessDispatch).compactMap(\.callee).sorted() == [
        "destroy value witness for A", "initializeWithCopy value witness for A", "initializeWithTake value witness for A",
    ])
    #expect(calls.filter(\.facts.isWitnessDispatch).allSatisfy { $0.callee?.contains(" value witness for ") == true })
    // `__chkstk_darwin` through its GOT slot is the one import.
    #expect(calls.filter { !$0.facts.isWitnessDispatch }.map(\.callee) == ["__chkstk_darwin"])
    for graph in [CallGraph(functions: functions), CallGraph(functions: functions.map(CallGraph.sites(of:)))] {
        #expect(graph.unresolvedCallSites == 3)
        #expect(graph.externalCallSites == 1)
    }
}

import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A call through self's own vtable slot reaches the named implementation
/// only when self is exactly that class: `DispatchDerived` overrides
/// `DispatchBase.hook`, and `DispatchBase.run`'s `self.hook()` runs the
/// override for a derived instance. It rendered as a static call,
/// `DispatchBase.hook()`, and the call graph recorded run → hook as a proven
/// edge. It now renders `self.hook()` and its edge is marked self dispatch.
private let fixture = "Fixtures/Sample/libCodegen.opt.dylib"

@Test func aSelfDispatchRendersThroughSelfIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: "DispatchBase.run")
    }
    let text = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(text.contains("self.hook()"), "\(text)")
    #expect(!text.contains("DispatchBase.hook("), "\(text)")
}

@Test func aSelfDispatchEdgeIsNotProvenIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture)
    }
    let graph = CallGraph(functions: functions)
    let run = try #require(functions.first { $0.displayName.hasPrefix("Codegen.DispatchBase.run") })
    let edges = graph.callees(of: run.startAddress)
    let hook = try #require(edges.first { graph.name(of: $0.callee).hasPrefix("Codegen.DispatchBase.hook") })
    #expect(hook.isSelfDispatch)
    // A direct call stays proven, so the flag is not set everywhere.
    #expect(graph.edges.contains { !$0.isSelfDispatch })
}

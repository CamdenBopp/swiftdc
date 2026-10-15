import Foundation
import Testing
@testable import SwiftDecompilerCore

private func loopEntryFunction(_ name: String) async throws -> DisassembledFunction? {
    let path = "Fixtures/Sample/libLoopEntry.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: name)
    }
    return try #require(functions.first { $0.displayName.hasPrefix("LoopEntry.\(name)(") })
}

@Test func initializesNamedLoopVariablesWithTheirProvenNonzeroEntriesIfPresent() async throws {
    guard let function = try await loopEntryFunction("nonzeroStart") else { return }
    let body = function.renderStructured()
    #expect(body.contains("var i = 3"))
    #expect(body.contains("var sum = 17"))
    let start = try #require(body.range(of: "var i = 3"))
    let loop = try #require(body.range(of: "while (i < arg0)"))
    #expect(start.lowerBound < loop.lowerBound)
    #expect(body.components(separatedBy: "var i = 3").count == 2)
}

@Test func sequentialLoopBindingsHaveDistinctAccumulatorNamesIfPresent() async throws {
    guard let function = try await loopEntryFunction("sequentialSums") else { return }
    let body = function.renderStructured()
    for text in ["var i = 3", "var sum = 17", "var j = 7", "var acc = 41", "acc += j"] {
        #expect(body.contains(text), "\(body)")
    }
}

@Test func nestedLoopInitializationRemainsInsideTheOuterLoopIfPresent() async throws {
    guard let function = try await loopEntryFunction("nestedCounters") else { return }
    let lines = function.renderStructured().split(separator: "\n").map(String.init)
    #expect(lines.contains("    var i = 3"))
    #expect(lines.contains("        var j = 7"))
    let outer = try #require(lines.firstIndex { $0.contains("while (i < arg0)") })
    let innerInit = try #require(lines.firstIndex { $0.contains("var j = 7") })
    let innerLoop = try #require(lines.firstIndex { $0.contains("while (j < arg0)") })
    #expect(outer < innerInit && innerInit < innerLoop)
}

@Test func anUnprovenLoopEntryDoesNotInventAnInitializerIfPresent() async throws {
    guard let function = try await loopEntryFunction("unknownStart") else { return }
    let body = function.renderStructured()
    #expect(!body.contains("var i ="))
    #expect(!body.contains("while (i <"))
}

@Test func loopEntryFactsAreAvailableToIndependentProbeValidatorsIfPresent() async throws {
    guard let function = try await loopEntryFunction("nonzeroStart") else { return }
    let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
    let bindings = analysis.loopInitializations.values.flatMap { $0 }
    #expect(bindings.count == 2)
    #expect(bindings.contains { $0.name == "i" && $0.value == 3 && $0.stackOffset != nil })
    #expect(bindings.contains { $0.name == "sum" && $0.value == 17 && $0.stackOffset != nil })
    let recorder = ProbeRecorder()
    Probe.recording(recorder) { Probe.observe(analysis, of: function) }
    let events = recorder.records.filter { $0.event == .loopInitialization }
    #expect(events.count == 2)
    #expect(events.contains { $0["name"] == .name("i") && $0["value"] == .uint(3) })
    #expect(events.contains { $0["name"] == .name("sum") && $0["value"] == .uint(17) })
}

@Test func aNonrotatedLoopKeepsItsCounterStepBeforeContinuingIfPresent() async throws {
    guard let function = try await loopEntryFunction("multipleExits") else { return }
    let body = function.renderStructured()
    #expect(body.contains("while (true)"))
    #expect(body.contains("var i = 3"))
    #expect(body.contains("if (i != 7)"))
    #expect(!body.contains("if (x8 != 7)"))
    let update = try #require(body.range(of: "i += 1"))
    let transfer = try #require(body.range(of: "continue"))
    #expect(update.lowerBound < transfer.lowerBound)
    #expect(body.components(separatedBy: "i += 1").count == 2)
}

/// A loop-body pass that hits its bound holds states that never settled; it
/// must name nothing for that loop. With a budget of one visit per block,
/// one of `nestedCounters`' two loops hits the bound and used to keep its
/// induction claims; the other loop settles and keeps its own.
@Test func aCappedLoopBodyPassClaimsNothingForItsLoopIfPresent() async throws {
    guard let function = try await loopEntryFunction("nestedCounters") else { return }
    var tracer = ValueTracer()
    tracer.loopBodyIterationsPerBlock = 1
    let recorder = ProbeRecorder(filter: ProbeFilter(events: [ProbeEvent.tracerLoopBodyCap.id]))
    let analysis = Probe.recording(recorder) {
        tracer.analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
    }
    let capped = Set(recorder.records.compactMap(\.address))
    try #require(capped.count == 1)
    let blocks = function.basicBlocks()
    let cappedBranches = Set(blocks.filter { capped.contains($0.startAddress) }.compactMap { $0.instructions.last?.address })
    try #require(cappedBranches.count == 1)
    for branch in cappedBranches {
        #expect(analysis.loopUpdates[branch] == nil)
        #expect(analysis.loopInitializations[branch] == nil)
    }
    #expect(analysis.loopUpdates.count == 1)
    #expect(analysis.loopInitializations.values.flatMap { $0 }.count == 1)
}

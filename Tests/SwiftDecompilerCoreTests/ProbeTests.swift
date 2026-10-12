import Foundation
import Testing
@testable import SwiftDecompilerCore
import Synchronization

private extension ProbeEvent {
    static let testDecision = ProbeEvent("test.decision", .abi, .decision, "A test event.")
    static let testDecline = ProbeEvent("test.decline", .values, .decline, "A test decline.")
}

@Test func aProbeWithoutARecorderBuildsNothing() {
    nonisolated(unsafe) var built = 0
    func fields() -> KeyValuePairs<String, ProbeValue> { built += 1; return ["n": .int(1)] }
    Probe.record(.testDecision, at: 0x10, fields())
    #expect(built == 0, "the payload autoclosure ran with no recorder installed")
}

@Test func aRecorderCapturesCountsAndAttributesToTheFunction() {
    let recorder = ProbeRecorder()
    Probe.recording(recorder) {
        Probe.inFunction(0x1000, "f") {
            Probe.record(.testDecision, at: 0x1004, ["callee": .name("g"), "count": .int(2)])
            Probe.record(.testDecline, at: 0x1008, ["reason": .label("clobbered")])
        }
        Probe.count(.testDecline, by: 3)
    }
    let records = recorder.records
    #expect(records.map(\.event.id) == ["test.decision", "test.decline"])
    #expect(records.map(\.sequence) == [1, 2])
    #expect(records[0].function == ProbeFunction(start: 0x1000, name: "f"))
    #expect(records[0]["count"] == .int(2))
    #expect(recorder.count(of: .testDecline) == 4)
    // Outside `recording`, nothing more arrives.
    Probe.record(.testDecision)
    #expect(recorder.count(of: .testDecision) == 1)
}

@Test func aFilterNarrowsTheTraceButNotTheCounts() {
    let recorder = ProbeRecorder(filter: ProbeFilter(categories: [.decline], function: "keep"))
    Probe.recording(recorder) {
        Probe.inFunction(0x1000, "keepMe") {
            Probe.record(.testDecision)
            Probe.record(.testDecline)
        }
        Probe.inFunction(0x2000, "other") { Probe.record(.testDecline) }
    }
    #expect(recorder.records.map { $0.function?.name } == ["keepMe"])
    #expect(recorder.count(of: .testDecline) == 2)
    #expect(recorder.count(of: .testDecision) == 1)
}

@Test func aValidatorSeesEveryRecordAndCollectsViolations() {
    let recorder = ProbeRecorder(filter: ProbeFilter(events: []), validators: [{ record in
        record["count"] == .int(3) ? "count 3 at \(record.address.map { String($0, radix: 16) } ?? "-")" : nil
    }])
    Probe.recording(recorder) {
        Probe.record(.testDecision, at: 0x20, ["count": .int(3)])
        Probe.record(.testDecision, at: 0x24, ["count": .int(4)])
    }
    #expect(recorder.records.isEmpty, "the filter admits nothing to the trace")
    #expect(recorder.violations == ["count 3 at 20"])
}

@Test func jsonLinesRedactBinaryNamesUnlessAllowed() {
    let lines = Mutex<[String]>([])
    let recorder = ProbeRecorder(output: .jsonLines { line in lines.withLock { $0.append(line) } }, includeNames: false)
    Probe.recording(recorder) {
        Probe.inFunction(0x1000, "Secret.function") {
            Probe.record(.testDecision, at: 0x1004, ["callee": .name("Secret.callee"), "why": .label("a \"quote\"")])
        }
    }
    let line = lines.withLock { $0 }.joined()
    #expect(!line.contains("Secret"), Comment(rawValue: line))
    #expect(line.contains("\"why\":\"a \\\"quote\\\"\""), Comment(rawValue: line))
    #expect(line.contains("\"address\":\"0x1004\""), Comment(rawValue: line))
    let parsed = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    #expect(parsed?["event"] as? String == "test.decision")
    let summary = try? JSONSerialization.jsonObject(with: Data(recorder.summaryLine().utf8)) as? [String: Any]
    #expect(summary?["schema"] as? String == ProbeRecorder.schema)
}

/// Instruments observe; they never decide. Every render of every fixture with
/// a recorder installed (every event admitted, validators running) must be
/// byte-identical to the render without one. The recorder must also have
/// seen events, or the comparison proves nothing.
@Test func probeRecordingDoesNotChangeOutputIfPresent() async throws {
    let fixtures = [
        "Fixtures/Sample/libReconstruction.opt.dylib", "Fixtures/Sample/libAsyncFns.opt.dylib",
        "Fixtures/Sample/libSample.dylib", "Fixtures/Sample/libCallReads.O0.dylib",
    ]
    for path in fixtures where FileManager.default.fileExists(atPath: path) {
        func render() async throws -> String {
            let functions = try await Disassembler(preset: .default).disassemble(path: path)
            return functions.map { $0.renderStructured() + "\n" + $0.renderPseudo() }.joined(separator: "\n")
        }
        let plain = try await withStableDependencies { try await render() }
        let recorder = ProbeRecorder(validators: [{ _ in nil }])
        let probed = try await withStableDependencies { try await Probe.recording(recorder) { try await render() } }
        #expect(plain == probed, "\(path)")
        #expect(recorder.records.count > 3, "\(path): the recorder saw \(recorder.records.count) events")
        #expect(recorder.count(of: .argumentLayout) > 0, "\(path)")
    }
}

/// Validators are the oracle hook: the tracer's write check must stay silent
/// on every fixture (a write the tracer does not model leaves a stale value
/// that can render as a confident argument), and so must the iteration
/// bounds, whose states are not a fixpoint.
@Test func theTracerModelsEveryWriteOnTheFixturesIfPresent() async throws {
    let fixtures = [
        "Fixtures/Sample/libReconstruction.opt.dylib", "Fixtures/Sample/libReconstruction.osize.dylib",
        "Fixtures/Sample/libAsyncFns.opt.dylib", "Fixtures/Sample/libSample.dylib",
        "Fixtures/Sample/sample.release", "Fixtures/Sample/libCallReads.O1.dylib",
    ]
    for path in fixtures where FileManager.default.fileExists(atPath: path) {
        let recorder = ProbeRecorder(filter: ProbeFilter(events: [
            ProbeEvent.tracerUnmodelledWrite.id, ProbeEvent.tracerFixpointCap.id, ProbeEvent.tracerLoopBodyCap.id,
        ]))
        let functions = try await withStableDependencies {
            try await Probe.recording(recorder) { try await Disassembler(preset: .default).disassemble(path: path) }
        }
        #expect(!functions.isEmpty)
        let found = recorder.records.map { "\($0.event.id) \($0.function?.name ?? "") @\($0.address.map { String($0, radix: 16) } ?? "-") \($0.fields.map { "\($0.key)=\($0.value)" })" }
        #expect(found.isEmpty, "\(path):\n\(found.prefix(10).joined(separator: "\n"))")
    }
}

/// A register the tracer knows nothing about is sometimes `.unknown` and
/// sometimes absent. Comparing block states literally saw a loop's x9 flip
/// between the two, so the worklist never emptied: an app's grid sampler (20
/// blocks) hit the bound, and the snapshot pass replayed an unconverged,
/// optimistic state. `Sampler.disk` is that shape.
@Test func theTracerConvergesWhereUnknownAndAbsentAlternateIfPresent() async throws {
    let path = "Fixtures/Sample/libGridSampler.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let recorder = ProbeRecorder(filter: ProbeFilter(events: [ProbeEvent.tracerFixpointCap.id]))
    let functions = try await withStableDependencies {
        try await Probe.recording(recorder) {
            try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "Sampler.disk")
        }
    }
    #expect(!functions.isEmpty)
    #expect(recorder.records.isEmpty, "\(recorder.records.map { $0.function?.name ?? "" })")
}

/// Past its bound the tracer's states are not a fixpoint, and it must claim
/// nothing rather than replay them. Forced with a bound of zero per block.
@Test func aTracerPastItsBoundClaimsNothingIfPresent() async throws {
    let path = "Fixtures/Sample/libGridSampler.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "Sampler.disk")
    }
    let disk = try #require(functions.first { $0.basicBlocks().count > 16 })
    let unbounded = ValueTracer().analyze(disk, entry: .swiftFunction(scalarArguments: [:]))
    #expect(!unbounded.callSites.isEmpty, "the comparison needs a function with recorded calls")
    var tracer = ValueTracer()
    tracer.iterationsPerBlock = 0
    let recorder = ProbeRecorder()
    let bounded = Probe.recording(recorder) { tracer.analyze(disk, entry: .swiftFunction(scalarArguments: [:])) }
    #expect(recorder.count(of: .tracerFixpointCap) == 1)
    #expect(bounded.callSites.isEmpty && bounded.exitValues.isEmpty, "\(bounded.callSites.count) call sites claimed past the bound")
}

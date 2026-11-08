import Foundation
import Testing
import SwiftDecompilerCore

private func value(_ kind: String, _ fields: [String: ProbeValue] = [:]) -> ProbeValue {
    .object(fields.merging(["kind": .label(kind)]) { _, new in new })
}
private func literal(_ bits: UInt64) -> ProbeValue { value("immediate", ["bits": .uint(bits)]) }
private func binary(_ op: String, _ a: UInt64, _ b: UInt64) -> ProbeValue {
    value("binary", ["operator": .label(op), "lhs": literal(a), "rhs": literal(b)])
}
private func wrapped(_ node: ProbeValue) -> ProbeValue {
    .object(["schema": .label("swiftdc-value/1"), "expression": node])
}
private func claim(_ recorder: ProbeRecorder, function: UInt64 = 0x1000, address: UInt64 = 0x1008,
                   node: ProbeValue, event: ProbeEvent = .returnValue) {
    Probe.recording(recorder) {
        Probe.inFunction(function, "sample") {
            Probe.record(event, at: address, ["register": .label("x0"), "value": wrapped(node), "x0": wrapped(node)])
        }
    }
}

@Test func integerOracleEvaluatesSignedUnsignedAndARMEdges() throws {
    let cases: [(String, UInt64, UInt64, UInt64)] = [
        ("unsigned-less", .max, 1, 0), ("less", .max, 1, 1), ("add", .max, 1, 0),
        ("divide", 1 << 63, .max, 1 << 63), ("remainder", 1 << 63, .max, 0),
        ("divide", 7, 0, 0), ("remainder", 7, 0, 7),
        ("multiply-high", .max, 2, .max), ("unsigned-multiply-high", .max, .max, .max - 1),
        ("arithmetic-shift-right", 1 << 63, 63, .max), ("shift-right", 1 << 63, 63, 1)
    ]
    for (op, a, b, expected) in cases { #expect(try wrapped(binary(op, a, b)).evaluateInteger() == expected) }
    #expect(throws: ProbeScoreError.self) { try wrapped(binary("shift-left", 1, 64)).evaluateInteger() }
}
@Test func integerOracleSelectEvaluatesOnlyChosenArm() throws {
    let select = value("select", ["condition": literal(1), "whenTrue": literal(7), "whenFalse": value("call-result")])
    #expect(try wrapped(select).evaluateInteger() == 7)
}
@Test func scoreSeparatesAgreementCoverageUnknownAndMissing() throws {
    let score = try ProbeScore([.init(.max, in: 0x1000), .init(18, in: 0x2000),
                                .init(3, in: 0x3000), .init(4, in: 0x4000)])
    let recorder = score.recorder
    claim(recorder, node: literal(.max))
    claim(recorder, function: 0x2000, node: literal(7))
    claim(recorder, function: 0x3000, node: value("unknown"))
    let report = try score.report()
    #expect(report.counts == ["verified": 1, "refuted": 1, "not-evaluated": 1, "missing": 1])
    #expect(report.agreement == 0.5); #expect(report.coverage == 0.5); #expect(report.exitCode == 1)
}
@Test func scoreRequiresOneAnalysisAndUnambiguousExit() throws {
    let score = try ProbeScore([.init(7, in: 0x1000)])
    claim(score.recorder, node: literal(7)); claim(score.recorder, node: literal(7))
    #expect(try score.report().evaluated == 0)
    let multi = try ProbeScore([.init(7, in: 0x1000), .init(7, in: 0x1000, at: 0x1008)])
    claim(multi.recorder, node: literal(7)); claim(multi.recorder, address: 0x1010, node: literal(8))
    #expect(try multi.report().results.map(\.outcome) == [.notEvaluated, .verified])
}
@Test func presentButDeclinedReturnCountsAsUnknownRatherThanMissing() throws {
    let score = try ProbeScore([.init(7, in: 0x1000)])
    Probe.recording(score.recorder) {
        Probe.inFunction(0x1000, "declined") {
            Probe.record(.returnOutcome, at: 0x1008, ["status": .label("unknown")])
        }
    }
    #expect(try score.report().counts["not-evaluated"] == 1)
    #expect(try score.report().counts["missing"] == 0)
}
@Test func scoreRejectsEmptyCasesInvalidWidthsAndWrongImage() throws {
    #expect(throws: ProbeScoreError.self) { try ProbeScore([]) }
    #expect(throws: ProbeScoreError.self) { try ProbeScore([.init(7, in: 1, bits: 0)]) }
    let score = try ProbeScore(oracle: ReturnOracle([.init(7, in: 1)], binaryUUID: "A"))
    Probe.recording(score.recorder) { Probe.record(.imageIdentity, ["uuid": .label("B")]) }
    #expect(throws: ProbeScoreError.self) { try score.report() }
}
@Test func scoreNativeSamplesNeedNoExitOrValidatorBoilerplate() async throws {
    let cases = ReturnExpectation.samples(in: 0x1000, inputs: [0, .max, 7]) { $0 &+ 1 }
    let score = try await ProbeScore.recording(cases) {
        Probe.inFunction(0x1000, "increment") {
            Probe.record(.returnValue, at: 0x1008, ["register": .label("x0"),
                "value": wrapped(value("binary", ["operator": .label("add"),
                    "lhs": value("argument", ["index": .int(0)]), "rhs": literal(1)]))])
        }
    }
    #expect(score.evaluated == 3); #expect(score.agreement == 1)
}
@Test func scoreManifestDefaultsAndBitPatternsRoundTrip() throws {
    let json = #"{"schema":"swiftdc-oracle/1","cases":[{"function":"0x1000","expected":-1}]}"#
    let oracle = try JSONDecoder().decode(ReturnOracle.self, from: Data(json.utf8))
    #expect(oracle.cases[0].expected == .max); #expect(oracle.cases[0].bits == 64)
    #expect(oracle.cases[0].arguments.isEmpty); #expect(oracle.cases[0].address == nil)
    let roundTrip = try JSONDecoder().decode(ReturnOracle.self, from: JSONEncoder().encode(oracle))
    #expect(roundTrip.cases[0].expected == .max)
}
@Test func scoreAcceptsTypedSwiftIntSamplesWithoutBitPatternConversions() throws {
    let cases = ReturnExpectation.samples(in: 0x1000, inputs: [-1, 0, Int.min, Int.max]) { $0 &+ 1 }
    let score = try ProbeScore(cases)
    claim(score.recorder, node: value("binary", ["operator": .label("add"),
        "lhs": value("argument", ["index": .int(0)]), "rhs": literal(1)]))
    #expect(try score.report().evaluated == 4)
    #expect(try score.report().agreement == 1)
    #expect(ReturnExpectation(signed: -1, in: 0x1000).expected == .max)
}
@Test func scoreReadsCompletedTraceAndRejectsTruncation() throws {
    let recorder = ProbeRecorder()
    claim(recorder, node: literal(.max))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let line = try #require(recorder.records.first).jsonLine()
    try (line + "\n" + recorder.summaryLine() + "\n").write(to: url, atomically: true, encoding: .utf8)
    let score = try ProbeScore([.init(.max, in: 0x1000)])
    try score.readTrace(at: url)
    #expect(try score.report().agreement == 1)
    try (line + "\n").write(to: url, atomically: true, encoding: .utf8)
    #expect(throws: ProbeScoreError.self) { try ProbeScore([.init(.max, in: 0x1000)]).readTrace(at: url) }
}
@Test func typedProbeSinkStreamsOutsideMutexAndMutesItsOwnEvents() {
    let recorder = ProbeRecorder(output: .records { _ in Probe.record(.returnValue) })
    claim(recorder, node: literal(7))
    #expect(recorder.counts[ProbeEvent.returnValue.id] == 1)
    #expect(recorder.records.isEmpty)
}

@Test func scoreCLIExitStatusesMatchTheReportedOutcomes() throws {
    let executable = URL(fileURLWithPath: ".build/debug/swiftdc").standardizedFileURL
    guard FileManager.default.isExecutableFile(atPath: executable.path) else { return }
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let manifest = scratch.appendingPathComponent("oracle.json"), trace = scratch.appendingPathComponent("trace.jsonl")
    try JSONEncoder().encode(ReturnOracle([.init(7, in: 0x1000)])).write(to: manifest)
    let scenarios: [(ProbeValue, Bool, Bool, Int32)] = [
        (literal(7), false, true, 0), (literal(8), false, true, 1), (literal(8), true, true, 1),
        (value("unknown"), false, true, 3), (value("unknown"), true, true, 0), (literal(7), false, false, 2)
    ]
    for (node, allow, complete, expected) in scenarios {
        let recorder = ProbeRecorder(); claim(recorder, node: node)
        let lines = recorder.records.map { $0.jsonLine() } + (complete ? [recorder.summaryLine()] : [])
        try (lines.joined(separator: "\n") + "\n").write(to: trace, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["score", trace.path, "--trace", "--oracle", manifest.path] + (allow ? ["--allow-incomplete"] : [])
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus == expected, "complete=\(complete), allow=\(allow), expected=\(expected)")
    }
}

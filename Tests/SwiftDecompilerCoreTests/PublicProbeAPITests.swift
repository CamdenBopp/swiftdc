import Foundation
import Synchronization
import Testing
import SwiftDecompilerCore

@Test func publicProbeValuesKeepExactBitsAndRedactNestedNames() throws {
    let recorder = ProbeRecorder()
    Probe.recording(recorder) {
        Probe.inFunction(0x1000, "Secret.function") {
            Probe.record(.returnValue, at: 0x1004, [
                "value": .abstractValue(.binary(.unsignedLess, .immediate(UInt64.max), .argument(0))),
                "nested": .object(["items": .array([.name("Secret.type"), .uint(UInt64.max)])]),
            ])
        }
    }
    let record = try #require(recorder.records.first)
    let redacted = record.jsonLine(includeNames: false)
    #expect(!redacted.contains("Secret"))
    #expect(redacted.contains("0xffffffffffffffff"))
    let json = try #require(JSONSerialization.jsonObject(with: Data(redacted.utf8)) as? [String: Any])
    let fields = try #require(json["fields"] as? [String: Any])
    let value = try #require(fields["value"] as? [String: Any])
    let expression = try #require(value["expression"] as? [String: Any])
    #expect(value["schema"] as? String == "swiftdc-value/1")
    #expect(expression["operator"] as? String == "unsigned-less")
}

@Test func probeAssessmentsSeparateUnsupportedFromVerifiedAndAllowRecorderReads() throws {
    let holder = Mutex<ProbeRecorder?>(nil)
    let recorder = ProbeRecorder(filter: ProbeFilter(events: []), assessmentValidators: [{ record in
        // This used to deadlock when user callbacks ran under the recorder lock.
        #expect(holder.withLock { $0?.count(of: .returnValue) } != nil)
        Probe.record(.renderedFunction, ["view": .label("oracle-trial")])
        let outcome: ProbeAssessment.Outcome = record["case"] == .int(0) ? .verified
            : record["case"] == .int(1) ? .refuted : .notEvaluated
        return ProbeAssessment(oracle: "native-fixture", outcome: outcome)
    }])
    holder.withLock { $0 = recorder }
    Probe.recording(recorder) {
        for n in 0..<3 { Probe.record(.returnValue, ["case": .int(n)]) }
    }
    #expect(recorder.records.isEmpty)
    #expect(recorder.count(of: .renderedFunction) == 0)
    #expect(recorder.assessments.map { $0.assessment.outcome } == [.verified, .refuted, .notEvaluated])
    let json = try #require(JSONSerialization.jsonObject(with: Data(recorder.summaryLine().utf8)) as? [String: Any])
    let summary = try #require(json["summary"] as? [String: Any])
    #expect(summary["assessments"] as? [String: Int] == ["verified": 1, "refuted": 1, "not-evaluated": 1])
}

@Test func aSummaryOnlyProbeDoesNotBuildSnapshotPayloads() {
    var built = 0
    func fields() -> KeyValuePairs<String, ProbeValue> {
        built += 1
        return ["value": .abstractValue(.immediate(7))]
    }
    let recorder = ProbeRecorder(output: .summaryOnly)
    Probe.recording(recorder) { Probe.record(.returnValue, fields()) }
    #expect(built == 0)
    #expect(recorder.count(of: .returnValue) == 1)
}

@Test func aStructuredFlatFallbackCountsOnlyOneCommittedRender() throws {
    let function = DisassembledFunction(symbol: "fixture", demangledName: nil, startAddress: 0x1000,
        instructions: [Instruction(address: 0x1000, text: "ret", annotation: "return 7", controlFlow: .return, exit: .normal("7"))], source: .address)
    let recorder = ProbeRecorder()
    let text = Probe.recording(recorder) { function.renderStructured() }
    #expect(text.contains("return 7"))
    let renders = recorder.records.filter { $0.event == .renderedFunction }
    #expect(renders.count == 1)
    #expect(renders.first?["view"] == .label("structured"))
    #expect(renders.first?["returns"] == .int(1))
}

import Testing
import SwiftDecompilerCore

/// Return addresses identify exits inside one analysis, not the image that
/// produced a record. The scorer cannot combine independently loaded images.
@Test func scoringDeclinesMultipleImageAnalysesForEveryExitContract() throws {
    for mode: ProbeScore.Mode in [.recoveredReturn, .rawRegister] {
        for explicitExit in [false, true] {
            for multipleExits in [false, true] {
                for repeatedUUID in [false, true] {
                    let score = try ProbeScore([.init(7, in: 0x1000,
                        at: explicitExit ? 0x1008 : nil)], mode: mode)
                    Probe.recording(score.recorder) {
                        Probe.record(.imageIdentity, ["uuid": .label("A")])
                        Probe.record(.imageIdentity, ["uuid": .label(repeatedUUID ? "A" : "B")])
                        Probe.inFunction(0x1000, "imageReturn") {
                            let event: ProbeEvent = mode == .rawRegister ? .exitRegisters : .returnValue
                            Probe.record(event, at: 0x1008, ["register": .label("x0"),
                                "value": .abstractValue(.immediate(7)), "x0": .abstractValue(.immediate(7)),
                                "path": .abstractValue(.immediate(1))])
                            if multipleExits {
                                Probe.record(event, at: 0x1010, ["register": .label("x0"),
                                    "value": .abstractValue(.immediate(8)), "x0": .abstractValue(.immediate(8)),
                                    "path": .abstractValue(.immediate(0))])
                            }
                        }
                    }
                    let report = try score.report()
                    #expect(report.results.map(\.outcome) == [.notEvaluated],
                        "mode=\(mode), explicit=\(explicitExit), multiple=\(multipleExits), sameUUID=\(repeatedUUID)")
                    #expect(report.evaluated == 0)
                    #expect(report.exitCode == 3)
                }
            }
        }
    }
}

@Test func scoringSingleImageAndLegacyImageFreeFactsRemainEvaluable() throws {
    for mode: ProbeScore.Mode in [.recoveredReturn, .rawRegister] {
        for includeImage in [false, true] {
            let score = try ProbeScore([.init(7, in: 0x1000)], mode: mode)
            Probe.recording(score.recorder) {
                if includeImage { Probe.record(.imageIdentity, ["uuid": .label("A")]) }
                Probe.inFunction(0x1000, "imageReturn") {
                    Probe.record(mode == .rawRegister ? .exitRegisters : .returnValue, at: 0x1008,
                        ["register": .label("x0"), "value": .abstractValue(.immediate(7)),
                         "x0": .abstractValue(.immediate(7))])
                }
            }
            #expect(try score.report().results.map(\.outcome) == [.verified])
        }
    }
}

@Test func scoringUUIDBoundManifestRejectsRepeatedImageAnalysis() throws {
    for mode: ProbeScore.Mode in [.recoveredReturn, .rawRegister] {
        let score = try ProbeScore(oracle: ReturnOracle([.init(7, in: 0x1000)], binaryUUID: "A"), mode: mode)
        Probe.recording(score.recorder) {
            Probe.record(.imageIdentity, ["uuid": .label("A")])
            Probe.record(.imageIdentity, ["uuid": .label("A")])
        }
        #expect(throws: ProbeScoreError.self) { try score.report() }
    }
}

import Foundation
import Testing
import SwiftDecompilerCore

private func guardedExit(_ score: ProbeScore, address: UInt64, value: AbstractValue,
                         path: AbstractValue, status: String = "recovered") {
    Probe.recording(score.recorder) {
        Probe.inFunction(0x1000, "twoReturns") {
            if status == "recovered" {
                Probe.record(.returnValue, at: address, ["register": .label("x0"),
                    "value": .abstractValue(value), "path": .abstractValue(path)])
            } else {
                Probe.record(.returnOutcome, at: address, ["status": .label(status), "path": .abstractValue(path)])
            }
        }
    }
}

@Test func scoreSelectsReturnPathsFromInputsRatherThanExpectedValues() throws {
    let score = try ProbeScore([.init(7, in: 0x1000, arguments: [0]),
                                .init(8, in: 0x1000, arguments: [1]),
                                .init(8, in: 0x1000, arguments: [0])])
    guardedExit(score, address: 0x1008, value: .immediate(7),
                path: .binary(.equal, .argument(0), .immediate(0)))
    guardedExit(score, address: 0x1010, value: .immediate(8),
                path: .binary(.notEqual, .argument(0), .immediate(0)))
    #expect(try score.report().results.map(\.outcome) == [.verified, .verified, .refuted])
}

@Test func scoreIgnoresDeclinedReturnsOnlyOnProvenUntakenPaths() throws {
    let score = try ProbeScore([.init(7, in: 0x1000, arguments: [0]), .init(8, in: 0x1000, arguments: [1])])
    guardedExit(score, address: 0x1008, value: .immediate(7),
                path: .binary(.equal, .argument(0), .immediate(0)))
    guardedExit(score, address: 0x1010, value: .unknown,
                path: .binary(.notEqual, .argument(0), .immediate(0)), status: "partial")
    #expect(try score.report().results.map(\.outcome) == [.verified, .notEvaluated])
}

@Test func ambiguousUnknownUnmatchedAndDuplicateReturnPathsDecline() throws {
    for otherPath: AbstractValue in [.immediate(1), .unknown, .immediate(0)] {
        let score = try ProbeScore([.init(7, in: 0x1000)])
        guardedExit(score, address: 0x1008, value: .immediate(7), path: otherPath == .immediate(0) ? .immediate(0) : .immediate(1))
        guardedExit(score, address: 0x1010, value: .immediate(8), path: otherPath)
        #expect(try score.report().results.map(\.outcome) == [.notEvaluated])
    }
    let duplicate = try ProbeScore([.init(7, in: 0x1000)])
    guardedExit(duplicate, address: 0x1008, value: .immediate(7), path: .immediate(1))
    for _ in 0..<2 { guardedExit(duplicate, address: 0x1010, value: .immediate(8), path: .immediate(0)) }
    #expect(try duplicate.report().results.map(\.outcome) == [.notEvaluated])
}

@Test func oneGuardedExitAndExplicitExitKeepTheirDistinctContracts() throws {
    let score = try ProbeScore([.init(7, in: 0x1000), .init(7, in: 0x1000, at: 0x1008)])
    guardedExit(score, address: 0x1008, value: .immediate(7), path: .immediate(0))
    #expect(try score.report().results.map(\.outcome) == [.notEvaluated, .verified])
}

@Test func returnPathsDoNotCombineDifferentImageAnalyses() throws {
    let score = try ProbeScore([.init(7, in: 0x1000)])
    Probe.recording(score.recorder) {
        Probe.record(.imageIdentity, ["uuid": .label("A")])
        Probe.record(.imageIdentity, ["uuid": .label("B")])
    }
    guardedExit(score, address: 0x1008, value: .immediate(7), path: .immediate(1))
    guardedExit(score, address: 0x1010, value: .immediate(8), path: .immediate(0))
    #expect(try score.report().results.map(\.outcome) == [.notEvaluated])
}

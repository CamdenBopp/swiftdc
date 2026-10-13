import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func researchInputsKeepEdgesAndReplayTheirSeed() {
    let first = ResearchFixtures.inputs(seed: 1)
    #expect(first == ResearchFixtures.inputs(seed: 1))
    #expect(first != ResearchFixtures.inputs(seed: 2))
    #expect(Array(first.prefix(ResearchFixtures.edges.count)) == ResearchFixtures.edges)
    #expect(Set(first).count == first.count)
    #expect(first.count == ResearchFixtures.edges.count + 16)
    #expect(ResearchFixtures.inputs(randomCount: 0) == ResearchFixtures.edges)
}
@Test func researchOracleRejectsEmptyOrUntrustedSignaturesBeforeExecuting() {
    #expect(throws: ProbeScoreError.self) { try ResearchFixtures.oracle(path: "missing", module: "OtherModule", inputs: [0]) }
    #expect(throws: ProbeScoreError.self) { try ResearchFixtures.oracle(path: "missing", module: "ResearchOnone", inputs: []) }
}
@Test func nativeResearchCorpusAgreesAtEveryOptimizationLevelIfPresent() async throws {
    let inputs = ResearchFixtures.inputs(seed: 7)
    let required: Set<String> = ["increment", "mixedBits", "lowWord", "wordAdd", "unsignedByte", "wordArithmeticShift", "signedLowerBound", "signedRange",
                                 "signExtendByte", "signExtendHalf", "signExtendWord", "wordSelect", "wordNot", "shiftedNot", "orNot",
                                 "signedWordProduct", "unsignedWordProduct", "signedWordAccumulate", "unsignedWordSubtract", "rotateBits", "rotateWord"]
    for module in ResearchFixtures.modules {
        let path = "Fixtures/Sample/lib\(module).dylib"
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let oracle = try ResearchFixtures.oracle(path: path, module: module, inputs: inputs)
        #expect(oracle.cases.count == inputs.count * ResearchFixtures.names.count)
        #expect(Set(oracle.cases.compactMap(\.id)).count == oracle.cases.count)
        let score = try ProbeScore(oracle: oracle)
        try await withStableDependencies {
            let machO = try BinaryLoader.loadMachO(path: path)
            await Probe.recording(score.recorder) {
                let _: [Void] = await Disassembler().disassembleStreaming(machO: machO) { _ = $0.renderStructured() }
            }
        }
        let report = try score.report()
        #expect(report.counts["refuted"] == 0, "\(module): \(report.results.filter { $0.outcome == .refuted })")
        let requiredHere = module == "ResearchOnone" ? required : required.union(["signedHigh", "unsignedHigh"])
        for name in requiredHere {
            let cases = report.results.filter { $0.expectation.id?.hasPrefix(name + "/") == true }
            #expect(cases.count == inputs.count)
            #expect(cases.allSatisfy { $0.outcome == .verified }, "\(module).\(name) lost native oracle coverage")
        }
        if module == "ResearchOnone" {
            for name in ["signedHigh", "unsignedHigh"] {
                let cases = report.results.filter { $0.expectation.id?.hasPrefix(name + "/") == true }
                #expect(cases.count == inputs.count)
                #expect(cases.allSatisfy { $0.outcome == .notEvaluated }, "unproven tuple projection must decline")
            }
        }
    }
}

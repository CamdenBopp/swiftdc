import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func depthLimitedSourceReturnsAreNotVerifiedAsCompleteIfPresent() async throws {
    let path = "Fixtures/Sample/libResearchOptimized.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let oracle = try ResearchFixtures.oracle(path: path, module: "ResearchOptimized", inputs: [7])
    var expectation = try #require(oracle.cases.first { $0.id == "boundedLoop/0x7" })
    let recorder = ProbeRecorder()
    let functions = try await withStableDependencies {
        try await Probe.recording(recorder) {
            try await Disassembler().disassemble(path: path, functionFilter: "boundedLoop")
        }
    }
    let function = try #require(functions.first)
    let ret = try #require(function.instructions.first { $0.controlFlow == .return })
    expectation.address = ret.address
    let score = try ProbeScore([expectation])
    let raw = try ProbeScore([expectation], mode: .rawRegister)
    for record in recorder.records { score.observe(record); raw.observe(record) }
    #expect(try raw.report().results.map(\.outcome) == [.verified])
    #expect(try score.report().results.map(\.outcome) == [.notEvaluated])
    #expect(recorder.records.contains {
        $0.event.id == "render.return-outcome" && $0.address == ret.address && $0["status"] == .label("partial")
    })
    #expect(!recorder.records.contains { $0.event.id == "render.return-value" && $0.address == ret.address })
    #expect(function.renderStructured().contains("? - 1"))
    let zeroRet = try #require(function.instructions.last { $0.controlFlow == .return })
    #expect(recorder.records.contains {
        $0.event.id == "render.return-outcome" && $0.address == zeroRet.address && $0["status"] == .label("recovered")
    })
}

@Test func aTernaryOperatorIsNotAnUnknownReturnPlaceholderIfPresent() async throws {
    let path = "Fixtures/Sample/libResearchOnone.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let recorder = ProbeRecorder()
    let functions = try await withStableDependencies {
        try await Probe.recording(recorder) {
            try await Disassembler().disassemble(path: path, functionFilter: "signedRange")
        }
    }
    let function = try #require(functions.first { $0.displayName.hasPrefix("ResearchOnone.signedRange(") })
    #expect(function.renderStructured().contains("? 71 : 61"))
    #expect(recorder.records.contains { $0.event.id == "render.return-value" })
    #expect(!recorder.records.contains { $0["status"] == .label("partial") })
}

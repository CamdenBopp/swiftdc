import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func anUnrecoveredPureResultRendersAnUnknownReturnIfPresent() async throws {
    let path = "Fixtures/Sample/libResearchOptimized.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    for preset in DemanglePreset.allCases {
        let recorder = ProbeRecorder()
        let functions = try await withStableDependencies {
            try await Probe.recording(recorder) {
                try await Disassembler(preset: preset).disassemble(path: path, functionFilter: "wordSelect")
            }
        }
        let function = try #require(functions.first { $0.symbol.contains("wordSelect") })
        #expect(function.renderPseudo().contains("return ?"))
        #expect(function.renderStructured().contains("return ?"))
        let outcomes = recorder.records.filter { $0.event == .returnOutcome }
        #expect(outcomes.count == 1)
        #expect(outcomes.first?["status"] == .label("unknown"))
        #expect(recorder.count(of: .returnValue) == 0)
    }
}

@Test func anUnsupportedExistentialResultHasAnUnknownOutcomeIfPresent() async throws {
    let path = "Fixtures/Sample/libIndirect.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let recorder = ProbeRecorder()
    let functions = try await withStableDependencies {
        try await Probe.recording(recorder) {
            try await Disassembler().disassemble(path: path, functionFilter: "asAny")
        }
    }
    let function = try #require(functions.first { $0.symbol.contains("asAny") })
    #expect(function.renderPseudo().contains("return ?"))
    #expect(function.renderStructured().contains("return ?"))
    let outcomes = recorder.records.filter { $0.event == .returnOutcome }
    #expect(outcomes.count == 1)
    #expect(outcomes.first?["status"] == .label("unknown"))
    #expect(recorder.count(of: .returnValue) == 0)
}

@Test func theFlatFallbackUsesOnlyAProvenValueReturnContract() {
    let ret = Instruction(address: 0x1000, text: "ret", controlFlow: .return)
    let value = DisassembledFunction(symbol: "value", demangledName: "value()", startAddress: 0x1000,
        instructions: [ret], source: .symbol, semanticName: "M.value() -> Swift.Int")
    #expect(value.renderPseudo().contains("return ?"))
    #expect(value.renderStructured().contains("return ?"))
    for signature in [nil, "M.void() -> ()", "M.never() -> Swift.Never", "M.asyncValue() async -> Swift.Int"] {
        let function = DisassembledFunction(symbol: "control", demangledName: signature, startAddress: 0x1000,
            instructions: [ret], source: .symbol)
        #expect(!function.renderPseudo().contains("return ?"))
        #expect(!function.renderStructured().contains("return ?"))
    }
}

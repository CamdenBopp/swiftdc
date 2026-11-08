import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func displayPresetsKeepImportedCallArgumentsAndReturnFactsIfPresent() async throws {
    let path = "Fixtures/Sample/libImportedClassProbe.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    for preset in DemanglePreset.allCases {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: preset).disassemble(path: path)
        }
        for name in ["withObject", "withOptionalObject"] {
            let function = try #require(functions.first { $0.symbol.contains(name) })
            let call = try #require(function.instructions.first { $0.controlFlow == .call || $0.controlFlow == .branch })
            #expect(call.callArguments?.count == 1, "\(preset): \(function.renderPseudo())")
            #expect(call.callArguments?.first?.contains("arg0") == true)
            #expect(!function.renderPseudo().contains("note()"))
        }
    }
}
@Test func everyDisplayPresetKeepsTheNativeIntegerCoverageIfPresent() async throws {
    let path = "Fixtures/Sample/libResearchOptimized.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let oracle = try ResearchFixtures.oracle(path: path, module: "ResearchOptimized", inputs: ResearchFixtures.edges)
    var expected: [ProbeScoreReport.Outcome]?
    for preset in DemanglePreset.allCases {
        let score = try ProbeScore(oracle: oracle)
        try await withStableDependencies {
            let machO = try BinaryLoader.loadMachO(path: path)
            await Probe.recording(score.recorder) {
                let _: [Void] = await Disassembler(preset: preset).disassembleStreaming(machO: machO) { _ = $0.renderStructured() }
            }
        }
        let report = try score.report()
        #expect(report.counts["refuted"] == 0)
        let outcomes = report.results.map(\.outcome)
        if let expected { #expect(outcomes == expected, "\(preset) changed semantic coverage") }
        else { expected = outcomes; #expect(report.evaluated > 0) }
    }
}

@Test func displayedNamesCanHideTypesWithoutDiscardingSemanticIdentity() {
    let function = DisassembledFunction(symbol: "$s1M1fyS2iF", demangledName: "f(_:)", startAddress: 0x1000,
        instructions: [], source: .symbol, semanticName: "M.f(Swift.Int) throws -> Swift.Int")
    #expect(function.displayName == "f(_:)")
    #expect(function.replacingInstructions([]).semanticName == function.semanticName)
    #expect(function.attachingSwitchTargets([:]).semanticName == function.semanticName)
    #expect(Disassembler.swiftScalarArgumentRegisters(of: function) == ["x0": 0])
    #expect(TypeInference.argumentTypes(of: function)[0]?.isSignedInteger == true)
    #expect(DisassembledFunction.signatureReturnsValue(displayName: function.analysisDisplayName, objcSignature: nil))
}
@Test func presetsStillUseTheirOwnHeadingsAndCalleeSpellingsIfPresent() async throws {
    let path = "Fixtures/Sample/libImportedClassProbe.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    for preset in DemanglePreset.allCases {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: preset).disassemble(path: path, functionFilter: "withObject")
        }
        let function = try #require(functions.first { $0.symbol.contains("withObject") })
        #expect(function.semanticName?.contains("__C.NSObject") == true)
        if preset == .simplified {
            #expect(function.displayName == "withObject(_:_:)")
            #expect(function.renderPseudo().contains("note(arg0)"))
            #expect(!function.renderPseudo().contains("ImportedClassProbe.note"))
        } else if preset == .interface {
            #expect(!function.displayName.contains("__C."))
        } else {
            #expect(function.displayName.contains("__C.NSObject"))
        }
    }
}

@Test func functionFiltersMatchTheChosenPresentationSpellingIfPresent() async throws {
    let path = "Fixtures/Sample/libImportedClassProbe.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    for preset in [DemanglePreset.simplified, .interface] {
        try await withStableDependencies {
            let disassembler = Disassembler(preset: preset)
            let all = try await disassembler.disassemble(path: path)
            let original = try #require(all.first { $0.symbol.contains("withOptionalObject") })
            let filtered = try await disassembler.disassemble(path: path, functionFilter: original.displayName)
            #expect(filtered.contains { $0.startAddress == original.startAddress })
        }
    }
}

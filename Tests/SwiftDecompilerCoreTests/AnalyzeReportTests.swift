import Testing
import Foundation
@testable import SwiftDecompilerCore

/// Content assertions for the default, flagship `analyze` report. It was only
/// ever checked for not-crashing on corrupt input — never for what it renders,
/// so a silent regression in the combined declarations + disassembly output
/// would have gone unnoticed. Driven by the committed fixtures (build them with
/// `Fixtures/Sample/build.sh`); absent, these skip like the other gated tests.
struct AnalyzeReportTests {
    private let reconstruction = "Fixtures/Sample/libReconstruction.dylib"
    private let sample = "Fixtures/Sample/sample.release"

    @Test func textReportSectionsAndContentIfPresent() async throws {
        guard FileManager.default.fileExists(atPath: reconstruction) else { return }
        let report = try await withStableDependencies {
            try await AnalysisReport(preset: .default).generate(path: reconstruction)
        }

        // The section skeleton, in order: declarations before disassembly.
        let declarations = try #require(report.range(of: "SWIFT DECLARATIONS"))
        let disassembly = try #require(report.range(of: "DISASSEMBLY"))
        #expect(declarations.lowerBound < disassembly.lowerBound)

        // Declarations section carries reconstructed types with typed fields.
        #expect(report.contains("struct Reconstruction.IntPair"))
        #expect(report.contains("var a: Swift.Int"))

        // Disassembly is grouped by owning type, under a demangled-signature
        // header, and carries swiftdc's return-value reconstruction — the
        // semantic annotation a flat disassembler does not produce.
        #expect(report.contains("// ──── Reconstruction ────"))
        #expect(report.contains("Reconstruction.isEqual(Swift.Int, Swift.Int) -> Swift.Bool:"))
        #expect(report.contains("return (arg0 == arg1)"))
    }

    @Test func objcSectionRendersForAMixedBinaryIfPresent() async throws {
        guard FileManager.default.fileExists(atPath: sample) else { return }
        let report = try await withStableDependencies {
            try await AnalysisReport(preset: .default).generate(path: sample)
        }
        #expect(report.contains("OBJECTIVE-C"))
    }

    @Test func jsonReportIsValidAndPopulatedIfPresent() async throws {
        guard FileManager.default.fileExists(atPath: reconstruction) else { return }
        let jsonText = try await withStableDependencies {
            try await AnalysisReport(preset: .default).generateJSON(path: reconstruction)
        }

        let data = try #require(jsonText.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let declarations = try #require(object["declarations"] as? [Any])
        let functions = try #require(object["functions"] as? [Any])
        #expect(!declarations.isEmpty, "JSON report has no declaration blocks")
        #expect(!functions.isEmpty, "JSON report recovered no functions")
        #expect(jsonText.contains("Reconstruction.IntPair"))
    }
}

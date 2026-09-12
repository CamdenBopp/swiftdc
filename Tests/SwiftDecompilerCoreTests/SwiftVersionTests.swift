import Testing
import Foundation
@testable import SwiftDecompilerCore

// MARK: - Pure decision (no fixture needed)

/// The linker's swift-tool record and the objc stable-ABI bits are both exact;
/// the tool record wins (it can carry a patch level) and the objc bits are
/// evidence.
@Test func classifiesAnExactVersionFromEvidence() {
    let fromObjc = SwiftVersionDetector.classify(
        swiftSections: ["__swift5_fieldmd", "__swift5_types"],
        objcStable: (6, 4), objcLegacyMarker: "v4.2", buildToolSwift: nil,
        platform: "macOS", minOS: "27.0.0", sdk: "27.0.0"
    )
    #expect(fromObjc.confidence == .exact)
    #expect(fromObjc.producingVersion == "6.4")
    #expect(fromObjc.summary == "Swift 6.4")
    #expect(fromObjc.evidence.contains { $0.contains("objc image-info stable-ABI") })
    // The SDK is context, never the claim.
    #expect(fromObjc.context.contains { $0.contains("not proof") && $0.contains("SDK 27.0.0") })

    let fromTool = SwiftVersionDetector.classify(
        swiftSections: ["__swift5_types"],
        objcStable: (6, 4), objcLegacyMarker: nil, buildToolSwift: "6.0.0",
        platform: nil, minOS: nil, sdk: nil
    )
    #expect(fromTool.confidence == .exact)
    #expect(fromTool.producingVersion == "6.0.0")
    #expect(fromTool.versionSource == "LC_BUILD_VERSION swift tool")
}

/// Only `__swift5_*` sections, no version-bearing bits: prove the generation,
/// decline the minor version.
@Test func declinesToABIGenerationWhenNoVersionRecorded() {
    let report = SwiftVersionDetector.classify(
        swiftSections: ["__swift5_types", "__swift5_fieldmd"],
        objcStable: nil, objcLegacyMarker: nil, buildToolSwift: nil,
        platform: nil, minOS: nil, sdk: nil
    )
    #expect(report.confidence == .abiGeneration)
    #expect(report.producingVersion == nil)
    #expect(report.abiGeneration == "Swift 5 stable ABI")
    #expect(report.hasSwiftMetadata)
}

/// No Swift evidence at all reads differently from a coarse-but-present result
/// — the empty-result rule: "not Swift" must not be spelled like "Swift, version
/// unknown".
@Test func declinesToNoneWithoutAnyEvidence() {
    let report = SwiftVersionDetector.classify(
        swiftSections: [], objcStable: nil, objcLegacyMarker: nil, buildToolSwift: nil,
        platform: "macOS", minOS: "15.0.0", sdk: "15.0.0"
    )
    #expect(report.confidence == .none)
    #expect(report.producingVersion == nil)
    #expect(report.summary.contains("No Swift evidence"))
    // Still reports build context, since that much IS known.
    #expect(!report.context.isEmpty)
}

// MARK: - Real payload (runs only when the fixture is built)

/// A release build stamps its producing compiler into the objc image-info
/// stable-ABI bits, so detection lands on an exact version. Asserted
/// structurally (major ≥ 5, `X.Y`) rather than a hard-coded number, since the
/// fixture is rebuilt by whatever Swift is installed.
@Test func detectsExactSwiftVersionIfPresent() throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let report = SwiftVersionDetector.detect(machO)

    #expect(report.confidence == .exact)
    #expect(report.hasSwiftMetadata)
    #expect(report.swiftSections.contains("__swift5_types"))
    let version = try #require(report.producingVersion)
    let parts = version.split(separator: ".").compactMap { Int($0) }
    #expect(parts.count >= 2)
    #expect((parts.first ?? 0) >= 5, "stable ABI is Swift 5+, got \(version)")
    #expect(report.evidence.contains { $0.contains("objc image-info") || $0.contains("LC_BUILD_VERSION") })
}

/// The evidence lives in reflection sections and the objc image-info, none of
/// which `strip` removes — so a stripped binary still names its Swift version.
/// This is the same strip-proof property the rest of the tool leans on.
@Test func detectionSurvivesStrippingIfPresent() throws {
    let path = "Fixtures/Sample/sample.stripped"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let report = SwiftVersionDetector.detect(machO)

    #expect(report.confidence == .exact)
    let version = try #require(report.producingVersion)
    #expect((version.split(separator: ".").first.flatMap { Int($0) } ?? 0) >= 5)
}

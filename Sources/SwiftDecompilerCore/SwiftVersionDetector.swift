import Foundation
import MachOKit
import MachOObjCSection

/// Evidence-backed detection of the Swift toolchain that produced a Mach-O.
///
/// The project rule is to decline rather than guess, so a version is reported
/// only where the binary carries proof, and the three outcomes are spelled
/// differently on purpose:
///
///   - `.exact`         a specific compiler version is recorded. Two provable
///                      sources: the `__objc_imageinfo` stable-ABI version bits
///                      (bits 16–31 of the flags word carry the producing
///                      compiler's major.minor — a Swift 6.4 build stamps
///                      `0x0604….`), and an `LC_BUILD_VERSION` entry whose tool
///                      is `TOOL_SWIFT` (the linker recording the compiler
///                      version; present in some builds, absent in many release
///                      binaries).
///   - `.abiGeneration` only the ABI generation is provable — the presence of
///                      `__swift5_*` reflection metadata, or the legacy objc
///                      image-info Swift marker (bits 8–15, used by pre-stable
///                      Swift 1–4.x). The exact minor version is not recoverable.
///   - `.none`          no Swift evidence at all: probably not a Swift binary,
///                      or one stripped of every trace.
///
/// This deliberately does NOT infer a Swift version from the SDK/platform in
/// `LC_BUILD_VERSION`. The SDK a binary was built against is not the compiler
/// that built it, so it is reported as context, never as the claim.
public struct SwiftVersionReport: Sendable {
    public enum Confidence: String, Sendable {
        case exact
        case abiGeneration
        case none
    }

    public let confidence: Confidence
    /// One-line human claim (`Swift 6.4`, or a decline).
    public let summary: String
    /// Facts that prove the claim.
    public let evidence: [String]
    /// Related build facts that are NOT proof of the Swift version.
    public let context: [String]

    // Structured detail (also drives `--json`).
    public let producingVersion: String?   // e.g. "6.4"
    public let versionSource: String?      // where `producingVersion` came from
    public let abiGeneration: String?      // e.g. "Swift 5 (stable ABI)"
    public let hasSwiftMetadata: Bool
    public let swiftSections: [String]
    public let buildToolSwift: String?     // "6.0.0" from LC_BUILD_VERSION, if any
    public let platform: String?
    public let minOS: String?
    public let sdk: String?
}

public enum SwiftVersionDetector {
    /// The lowest major the stable-ABI bits can legitimately carry. The stable
    /// Swift ABI landed in Swift 5, so a value below 5 (typically 0) means the
    /// field is unset rather than a real version, and we fall back.
    static let stableABIFloor = 5
    static let stableABICeiling = 99

    public static func detect(_ machO: MachOFile) -> SwiftVersionReport {
        // 1. Swift reflection sections (`__swift5_types`, `__swift5_fieldmd`, …),
        //    present since the Swift 5 stable ABI. Survive `strip`.
        let swiftSections = machO.sections
            .map(\.sectionName)
            .filter { $0.hasPrefix("__swift5") }
            .sorted()

        // 2. objc image-info Swift bits.
        var objcStable: (Int, Int)?
        var objcLegacy: String?
        if let flags = machO.objc.imageInfo?.flags {
            let stable = flags.swiftStableVersion
            // Plain comparison, not `(floor...ceiling).contains`: a ClosedRange
            // traps if the bounds ever invert, and these are hand-maintained.
            if stable.major >= stableABIFloor && stable.major <= stableABICeiling {
                objcStable = (stable.major, stable.minor)
            }
            objcLegacy = flags.swiftUnstableVersion?.description
        }

        // 3. LC_BUILD_VERSION: the swift tool record (strongest single fact when
        //    present), plus platform/SDK for context only.
        var buildToolSwift: String?
        var platform: String?
        var minOS: String?
        var sdk: String?
        for case let .buildVersion(build) in machO.loadCommands {
            platform = friendlyPlatform("\(build.platform)")
            minOS = "\(build.minos)"
            sdk = "\(build.sdk)"
            for tool in build.tools(in: machO) where tool.tool == .swift {
                buildToolSwift = "\(tool.version)"
            }
            break
        }

        return classify(
            swiftSections: swiftSections,
            objcStable: objcStable,
            objcLegacyMarker: objcLegacy,
            buildToolSwift: buildToolSwift,
            platform: platform, minOS: minOS, sdk: sdk
        )
    }

    /// MachOKit prints the raw `PLATFORM_MACOS`-style name; this is context text,
    /// so give it the spelling a reader expects. Unknown platforms keep the raw
    /// name minus the prefix rather than being dropped.
    private static func friendlyPlatform(_ raw: String) -> String {
        let known = [
            "PLATFORM_MACOS": "macOS", "PLATFORM_IOS": "iOS", "PLATFORM_TVOS": "tvOS",
            "PLATFORM_WATCHOS": "watchOS", "PLATFORM_VISIONOS": "visionOS",
            "PLATFORM_MACCATALYST": "Mac Catalyst",
            "PLATFORM_IOSSIMULATOR": "iOS Simulator", "PLATFORM_TVOSSIMULATOR": "tvOS Simulator",
            "PLATFORM_WATCHOSSIMULATOR": "watchOS Simulator", "PLATFORM_VISIONOSSIMULATOR": "visionOS Simulator",
        ]
        if let friendly = known[raw] { return friendly }
        return raw.hasPrefix("PLATFORM_") ? String(raw.dropFirst("PLATFORM_".count)) : raw
    }

    /// The pure decision, split out from Mach-O parsing so both the claim
    /// ladder and the decline path are unit-testable without a fixture.
    /// `objcStable` is the `__objc_imageinfo` stable-ABI (major, minor), already
    /// range-checked by the caller; `objcLegacyMarker` is the pre-stable nibble.
    static func classify(
        swiftSections: [String],
        objcStable: (Int, Int)?,
        objcLegacyMarker: String?,
        buildToolSwift: String?,
        platform: String?, minOS: String?, sdk: String?
    ) -> SwiftVersionReport {
        let hasSwiftMetadata = !swiftSections.isEmpty

        var evidence: [String] = []
        if let buildToolSwift {
            evidence.append("LC_BUILD_VERSION swift tool record → \(buildToolSwift)")
        }
        if let objcStable {
            evidence.append("objc image-info stable-ABI version bits → \(objcStable.0).\(objcStable.1)")
        }
        if hasSwiftMetadata {
            let shown = swiftSections.prefix(6).joined(separator: ", ")
            let more = swiftSections.count > 6 ? ", …" : ""
            evidence.append("__swift5 reflection metadata present (\(swiftSections.count) sections): \(shown)\(more)")
        }

        var context: [String] = []
        if let platform {
            let os = [minOS.map { "min OS \($0)" }, sdk.map { "SDK \($0)" }]
                .compactMap { $0 }.joined(separator: ", ")
            context.append("build environment (not proof of the Swift version): \(platform)\(os.isEmpty ? "" : ", \(os)")")
        }

        // Prefer the linker's record (it can carry a patch level), then the objc
        // stable-ABI bits. Both are exact; a coarse fall-through only when neither
        // is present.
        if let buildToolSwift {
            return SwiftVersionReport(
                confidence: .exact, summary: "Swift \(buildToolSwift)",
                evidence: evidence, context: context,
                producingVersion: buildToolSwift, versionSource: "LC_BUILD_VERSION swift tool",
                abiGeneration: hasSwiftMetadata ? "Swift 5 (stable ABI)" : nil,
                hasSwiftMetadata: hasSwiftMetadata, swiftSections: swiftSections,
                buildToolSwift: buildToolSwift, platform: platform, minOS: minOS, sdk: sdk
            )
        }
        if let objcStable {
            let version = "\(objcStable.0).\(objcStable.1)"
            return SwiftVersionReport(
                confidence: .exact, summary: "Swift \(version)",
                evidence: evidence, context: context,
                producingVersion: version, versionSource: "objc image-info stable-ABI bits",
                abiGeneration: "Swift 5 (stable ABI)",
                hasSwiftMetadata: hasSwiftMetadata, swiftSections: swiftSections,
                buildToolSwift: nil, platform: platform, minOS: minOS, sdk: sdk
            )
        }
        if hasSwiftMetadata || objcLegacyMarker != nil {
            let generation = hasSwiftMetadata
                ? "Swift 5 stable ABI"
                : "pre-stable Swift (objc marker \(objcLegacyMarker ?? "?"))"
            if !hasSwiftMetadata, let objcLegacyMarker {
                evidence.append("objc image-info legacy Swift marker → \(objcLegacyMarker)")
            }
            return SwiftVersionReport(
                confidence: .abiGeneration,
                summary: "Swift binary; exact version not recorded (\(generation))",
                evidence: evidence, context: context,
                producingVersion: nil, versionSource: nil, abiGeneration: generation,
                hasSwiftMetadata: hasSwiftMetadata, swiftSections: swiftSections,
                buildToolSwift: nil, platform: platform, minOS: minOS, sdk: sdk
            )
        }
        return SwiftVersionReport(
            confidence: .none,
            summary: "No Swift evidence found (likely not built by the Swift compiler)",
            evidence: [], context: context,
            producingVersion: nil, versionSource: nil, abiGeneration: nil,
            hasSwiftMetadata: false, swiftSections: [],
            buildToolSwift: nil, platform: platform, minOS: minOS, sdk: sdk
        )
    }
}

public extension SwiftVersionReport {
    /// Human-readable, greppable rendering.
    var text: String {
        var lines = [summary, "  confidence: \(confidence.rawValue)"]
        if !evidence.isEmpty {
            lines.append("  evidence:")
            lines.append(contentsOf: evidence.map { "    - \($0)" })
        }
        if !context.isEmpty {
            lines.append(contentsOf: context.map { "  \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    /// Structured JSON, composable with `jq` and diffable across builds.
    func jsonString() -> String {
        var object: [String: Any] = [
            "confidence": confidence.rawValue,
            "summary": summary,
            "evidence": evidence,
            "context": context,
            "hasSwiftMetadata": hasSwiftMetadata,
            "swiftSections": swiftSections,
        ]
        object["producingVersion"] = producingVersion
        object["versionSource"] = versionSource
        object["abiGeneration"] = abiGeneration
        object["buildToolSwift"] = buildToolSwift
        object["platform"] = platform
        object["minOS"] = minOS
        object["sdk"] = sdk
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

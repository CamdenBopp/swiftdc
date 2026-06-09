import Foundation
import MachOKit
import MachOSwiftSection
import SwiftDump
import Semantic

/// Demangling presets, mapped onto SwiftDump's `DemangleOptions` so callers
/// (e.g. the CLI) don't need to import the demangler directly.
public enum DemanglePreset: String, CaseIterable, Sendable {
    case `default`
    case simplified
    case interface

    var options: DemangleOptions {
        switch self {
        case .default: return .default
        case .simplified: return .simplified
        case .interface: return .interface
        }
    }
}

/// Reconstructs approximate Swift source declarations from the `__swift5_*`
/// metadata in a Mach-O binary, using MachOSwiftSection + SwiftDump.
public struct SwiftDeclarationDumper: Sendable {
    /// Which metadata sections to reconstruct.
    public enum Section: String, CaseIterable, Sendable {
        case types
        case protocols
        case conformances
        case associatedTypes
    }

    public var preset: DemanglePreset

    public init(preset: DemanglePreset = .default) {
        self.preset = preset
    }

    /// Reconstruct declarations for the requested sections, returning formatted
    /// Swift-like source text. Per-entry failures are skipped (binaries vary).
    public func dump(
        _ machO: MachOFile,
        sections: Set<Section> = Set(Section.allCases)
    ) async -> String {
        let configuration = DumperConfiguration.demangleOptions(preset.options)
        var blocks: [String] = []

        if sections.contains(.types), let types = try? machO.swift.types {
            for type in types {
                if let text = await dumpType(type, configuration, in: machO) {
                    blocks.append(text)
                }
            }
        }

        if sections.contains(.protocols), let protocols = try? machO.swift.protocols {
            for proto in protocols {
                if let text = await safeDump({ try await proto.dump(using: configuration, in: machO) }) {
                    blocks.append(text)
                }
            }
        }

        if sections.contains(.conformances), let conformances = try? machO.swift.protocolConformances {
            for conformance in conformances {
                if let text = await safeDump({ try await conformance.dump(using: configuration, in: machO) }) {
                    blocks.append(text)
                }
            }
        }

        if sections.contains(.associatedTypes), let assocs = try? machO.swift.associatedTypes {
            for assoc in assocs {
                if let text = await safeDump({ try await assoc.dump(using: configuration, in: machO) }) {
                    blocks.append(text)
                }
            }
        }

        return blocks.joined(separator: "\n\n")
    }

    private func dumpType(
        _ type: TypeContextWrapper,
        _ configuration: DumperConfiguration,
        in machO: MachOFile
    ) async -> String? {
        switch type {
        case .enum(let value):
            return await safeDump { try await value.dump(using: configuration, in: machO) }
        case .struct(let value):
            return await safeDump { try await value.dump(using: configuration, in: machO) }
        case .class(let value):
            return await safeDump { try await value.dump(using: configuration, in: machO) }
        }
    }

    private func safeDump(_ work: () async throws -> SemanticString) async -> String? {
        do {
            return try await work().string
        } catch {
            return nil
        }
    }
}

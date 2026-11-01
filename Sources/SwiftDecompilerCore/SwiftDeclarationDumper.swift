import Foundation
import MachOKit
import MachOSwiftSection
import SwiftDump
// 0.12.0 split the render configuration out of SwiftDump into its own module,
// which SwiftDump depends on but does not re-export. It still vends a
// `DeclarationRenderConfiguration` typealias for source compatibility; we use the new name.
import SwiftDeclarationRendering
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
    /// Swift-like source text. An entry that fails to render is named, with
    /// the error, in a comment where its declaration would be: skipping it
    /// read as a binary without that type (`OpenAICompatibleModel`, exported
    /// by GenerativeAgents, was missing from `dump` without a word).
    public func dump(
        _ machO: MachOFile,
        sections: Set<Section> = Set(Section.allCases)
    ) async -> String {
        // Every type prints through ExtendedExistentials, so a constrained
        // existential reads `any Source<String>`, not the toolchain printer's
        // `symbolic existential type (non-unique) 0x0 <Swift.String>`.
        // A builder resolver loses one thing the options resolver gets: the
        // renderer adds `.removeReferenceStoragePrefix` to options when it
        // prints a stored field's type, after the `weak` keyword, and passes
        // a builder through unchanged (`weak var target: weak Optional<…>`).
        // Reference storage occurs only in stored-field types, so it is
        // always on here.
        // Only the types section: the conformance renderer, like the field
        // renderer, adjusts an options resolver and passes a builder through,
        // and lost its extension spelling (`Swift.ClosedRange<>.Index`).
        let configuration = DeclarationRenderConfiguration.demangleOptions(preset.options)
        let options = preset.options.union(.removeReferenceStoragePrefix)
        let typesConfiguration = DeclarationRenderConfiguration(demangleResolver: .builder { node in
            try ExtendedExistentials.resolve(node).printSemantic(using: options)
        })
        var blocks: [String] = []

        if sections.contains(.types), let types = try? machO.swift.types {
            for type in types {
                switch await dumpType(type, typesConfiguration, in: machO) {
                case .success(let text):
                    blocks.append(text)
                case .failure(let error):
                    blocks.append("// \(Self.kind(of: type)) \(Self.displayName(of: type, in: machO)): not rendered: \(error)")
                }
            }
        }

        if sections.contains(.protocols), let protocols = try? machO.swift.protocols {
            for proto in protocols {
                blocks.append(await render("protocol \(proto.name)") { try await proto.dump(using: configuration, in: machO) })
            }
        }

        if sections.contains(.conformances), let conformances = try? machO.swift.protocolConformances {
            for conformance in conformances {
                blocks.append(await render("protocol conformance") { try await conformance.dump(using: configuration, in: machO) })
            }
        }

        if sections.contains(.associatedTypes), let assocs = try? machO.swift.associatedTypes {
            for assoc in assocs {
                blocks.append(await render("associated type witnesses") { try await assoc.dump(using: configuration, in: machO) })
            }
        }

        return blocks.joined(separator: "\n\n")
    }

    private func dumpType(
        _ type: TypeContextWrapper,
        _ configuration: DeclarationRenderConfiguration,
        in machO: MachOFile
    ) async -> Result<String, any Swift.Error> {
        do {
            switch type {
            case .enum(let value): return .success(try await value.dump(using: configuration, in: machO).string)
            case .struct(let value): return .success(try await value.dump(using: configuration, in: machO).string)
            case .class(let value): return .success(try await value.dump(using: configuration, in: machO).string)
            }
        } catch {
            return .failure(error)
        }
    }

    static func kind(of type: TypeContextWrapper) -> String {
        switch type {
        case .enum: return "enum"
        case .struct: return "struct"
        case .class: return "class"
        }
    }

    /// The qualified name when every parent is a module or type, else the
    /// descriptor's own name, else `?`.
    static func displayName(of type: TypeContextWrapper, in machO: MachOFile) -> String {
        if let qualified = FieldMapBuilder.qualifiedName(of: type, in: machO) { return qualified }
        let name: String?
        switch type {
        case .enum(let model): name = try? model.descriptor.name(in: machO)
        case .struct(let model): name = try? model.descriptor.name(in: machO)
        case .class(let model): name = try? model.descriptor.name(in: machO)
        }
        return name ?? "?"
    }

    /// The rendered entry, or a comment naming it and why it was not
    /// rendered.
    private func render(_ what: String, _ work: () async throws -> SemanticString) async -> String {
        do {
            return try await work().string
        } catch {
            return "// \(what): not rendered: \(error)"
        }
    }
}

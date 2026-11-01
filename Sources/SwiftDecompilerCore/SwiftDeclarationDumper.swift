import Foundation
import MachOKit
import MachOSwiftSection
import SwiftDump
// 0.12.0 split the render configuration out of SwiftDump into its own module,
// which SwiftDump depends on but does not re-export. It still vends a
// `DeclarationRenderConfiguration` typealias for source compatibility; we use the new name.
import SwiftDeclarationRendering
import Semantic
import Demangling

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
            let descriptorSymbols = Self.descriptorSymbols(in: machO)
            for type in types {
                switch await dumpType(type, typesConfiguration, in: machO) {
                case .success(let text):
                    blocks.append(Self.placingLocalType(text, type, symbols: descriptorSymbols, in: machO))
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

    /// A type declared inside a function sits under an anonymous context.
    /// An optimized build records no name for that context, and the
    /// renderer then skips it: `PrecedenceGroupBody`, local to LLDB's
    /// `ASTGenVisitor.generate(precedenceGroupDecl:)`, printed as
    /// `swiftASTGen.ASTGenVisitor.PrecedenceGroupBody`, a member type of
    /// `ASTGenVisitor`, which it is not (468 types in the corpus).
    ///
    /// The type's own descriptor symbol names its function
    /// (`PrecedenceGroupBody #1 in …generate(…)`), and replaces the printed
    /// name when the image has one. Otherwise the context is marked where it
    /// was dropped, as the Swift runtime prints one:
    /// `ASTGenVisitor.(unknown context at $855dc90).PrecedenceGroupBody`.
    static func placingLocalType(
        _ text: String, _ type: TypeContextWrapper, symbols: [UInt64: String], in machO: MachOFile
    ) -> String {
        // The named types between this one and each anonymous ancestor,
        // innermost first; only types can be declared in a function.
        var chain: [String] = []
        var anonymous: [(address: UInt64, below: [String])] = []
        guard let own = displayName(of: type, in: machO).split(separator: ".").last.map(String.init) else { return text }
        chain.append(own)
        var next: SymbolOrElement<ContextWrapper>?
        switch type {
        case .enum(let m): next = try? m.parent(in: machO)
        case .struct(let m): next = try? m.parent(in: machO)
        case .class(let m): next = try? m.parent(in: machO)
        }
        var hops = 0
        while let link = next, hops < 64 {
            hops += 1
            guard case .element(let wrapper) = link else { break }
            switch wrapper {
            case .anonymous(let context):
                anonymous.append((machO.address(forOffset: context.descriptor.offset), chain))
            case .type(let parentType):
                let name: String?
                switch parentType {
                case .enum(let m): name = try? m.descriptor.name(in: machO)
                case .struct(let m): name = try? m.descriptor.name(in: machO)
                case .class(let m): name = try? m.descriptor.name(in: machO)
                }
                guard let name else { return text }
                chain.append(name)
            default:
                break
            }
            next = try? wrapper.parent(in: machO)
        }
        guard !anonymous.isEmpty else { return text }
        var lines = text.components(separatedBy: "\n")
        guard var header = lines.first,
              let keyword = header.firstMatch(of: #/^(?:[a-z@]+ )*?(?:struct|class|enum|actor) /#)
        else { return text }
        // Each anonymous context sits just above the `below` names, which
        // print last in the name, joined by dots.
        func span(_ below: [String]) -> Range<String.Index>? {
            let suffix = "." + below.reversed().joined(separator: ".")
            var from = keyword.range.upperBound
            while let found = header.range(of: suffix, range: from ..< header.endIndex) {
                let after = found.upperBound
                if after == header.endIndex || " <:{".contains(header[after]) { return found }
                from = found.upperBound
            }
            return nil
        }
        let address = machO.address(forOffset: Self.descriptorOffset(of: type))
        if let symbol = symbols[address], let full = Self.demangledDescriptorName(symbol),
           let last = span([own]) {
            header.replaceSubrange(keyword.range.upperBound ..< last.upperBound, with: full)
        } else {
            // Outermost first, so an earlier insertion does not move a later span.
            for context in anonymous.reversed() {
                guard let found = span(context.below) else { return text }
                header.insert(contentsOf: ".(unknown context at $\(String(context.address, radix: 16)))", at: found.lowerBound)
            }
        }
        lines[0] = header
        return lines.joined(separator: "\n")
    }

    static func descriptorOffset(of type: TypeContextWrapper) -> Int {
        switch type {
        case .enum(let m): return m.descriptor.offset
        case .struct(let m): return m.descriptor.offset
        case .class(let m): return m.descriptor.offset
        }
    }

    /// Nominal type descriptor symbols (`$s…Mn`) by address, from the symbol
    /// table of a file. A cache image's symbol table may live in another
    /// subcache and cannot be read (`CacheSymbols`), so it has none.
    static func descriptorSymbols(in machO: MachOFile) -> [UInt64: String] {
        guard !machO.isLoadedFromDyldCache else { return [:] }
        var result: [UInt64: String] = [:]
        for symbol in machO.symbols where symbol.name.hasSuffix("Mn") && symbol.name.hasPrefix("_$s") {
            if let address = Disassembler.sectionAddress(of: symbol), result[address] == nil {
                result[address] = symbol.name
            }
        }
        return result
    }

    /// `PrecedenceGroupBody #1 in …` from `_$s…Mn`, or nil.
    static func demangledDescriptorName(_ symbol: String) -> String? {
        guard let node = try? demangleAsNode(String(symbol.dropFirst())) else { return nil }
        let printed = node.print(using: .default)
        let prefix = "nominal type descriptor for "
        guard printed.hasPrefix(prefix) else { return nil }
        return String(printed.dropFirst(prefix.count))
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

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

        if sections.contains(.types), let recorded = UnrecordedTypes.ownRecords(in: machO) {
            let types = recorded + UnrecordedTypes.types(in: machO, recorded: recorded)
            let descriptorSymbols = Self.descriptorSymbols(in: machO)
            for type in types {
                switch await dumpType(type, typesConfiguration, in: machO) {
                case .success(let text):
                    let placed = Self.placingLocalType(text, type, symbols: descriptorSymbols, in: machO)
                    blocks.append(UnnamedStorage.comment(of: type, in: machO).map { UnnamedStorage.placing($0, in: placed) } ?? placed)
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
            let foreign = ForeignRequirementNames(machO, options: preset.options)
            for conformance in conformances {
                let text = await render("protocol conformance") { try await conformance.dump(using: configuration, in: machO) }
                blocks.append(foreign?.naming(in: text, conformance) ?? text)
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
        guard let (own, anonymous) = anonymousAncestors(of: type, in: machO) else { return text }
        var lines = text.components(separatedBy: "\n")
        guard var header = lines.first,
              let keyword = header.firstMatch(of: #/^(?:[a-z@]+ )*?(?:struct|class|enum|actor) /#)
        else { return text }
        guard let address = machO.imageAddress(ofOffset: Self.descriptorOffset(of: type)) else { return text }
        guard !anonymous.isEmpty else {
            // A private type IRGen did not wrap in an anonymous context (one
            // that is usable from inline, `getAddrOfParentContextDescriptor`)
            // has no discriminator in its metadata: Swift's own SIL module
            // prints `SIL.AccessPathWalker`, and a second file's private
            // `AccessPathWalker` would print the same. Its descriptor symbol
            // keeps it, `SIL.(AccessPathWalker in _FFCB…)`, and is used when
            // it names the printed type with only the discriminators added.
            guard let symbol = symbols[address], let full = Self.demangledDescriptorName(symbol),
                  full.contains(" in _"),
                  let last = nameSpan(of: [own], in: header, from: keyword.range.upperBound),
                  full.replacing(#/\((\w+) in _\w+\)/#, with: { String($0.1) })
                      == header[keyword.range.upperBound ..< last.upperBound]
            else { return text }
            header.replaceSubrange(keyword.range.upperBound ..< last.upperBound, with: full)
            lines[0] = header
            return lines.joined(separator: "\n")
        }
        // A local type in a private function prints with its private
        // discriminator, `.(unknown context at _H).(PlaneInfo in _H)`.
        func privateSpan() -> Range<String.Index>? {
            guard let open = header.range(of: ".(\(own) in _", range: keyword.range.upperBound ..< header.endIndex),
                  let close = header[open.upperBound...].firstIndex(of: ")")
            else { return nil }
            return open.lowerBound ..< header.index(after: close)
        }
        guard let unwrapped = withoutPositionName(header, contexts: anonymous, from: keyword.range.upperBound)
        else { return text }
        header = unwrapped
        if let symbol = symbols[address], let full = Self.demangledDescriptorName(symbol),
           let last = nameSpan(of: [own], in: header, from: keyword.range.upperBound) ?? privateSpan() {
            header.replaceSubrange(keyword.range.upperBound ..< last.upperBound, with: full)
        } else if !markingUnknownContexts(anonymous, in: &header, from: keyword.range.upperBound) {
            return text
        }
        lines[0] = header
        return lines.joined(separator: "\n")
    }

    /// A type's own name and each anonymous context above it: its address,
    /// and the named types between it and this type, innermost first (only
    /// types can be declared in a function). Nil when a name cannot be read.
    static func anonymousAncestors(
        of type: TypeContextWrapper, in machO: MachOFile
    ) -> (own: String, contexts: [(address: UInt64, below: [String])])? {
        guard let own = displayName(of: type, in: machO).split(separator: ".").last.map(String.init) else { return nil }
        var chain = [own]
        var anonymous: [(address: UInt64, below: [String])] = []
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
                guard let address = machO.imageAddress(ofOffset: context.descriptor.offset) else { return nil }
                anonymous.append((address, chain))
            case .type(let parentType):
                let name: String?
                switch parentType {
                case .enum(let m): name = try? m.descriptor.name(in: machO)
                case .struct(let m): name = try? m.descriptor.name(in: machO)
                case .class(let m): name = try? m.descriptor.name(in: machO)
                }
                guard let name else { return nil }
                chain.append(name)
            default:
                break
            }
            next = try? wrapper.parent(in: machO)
        }
        return (own, anonymous)
    }

    /// MachOSwiftSection 0.23 and later name a local type whose function it
    /// cannot name by the address of the anonymous context wrapping it,
    /// spelled as a private declaration name: `LocalTypes.Outer.(Local in
    /// $1dbc)`. That reads as a private member of `Outer`, and it drops the
    /// function's own context, which two local types of one function share.
    /// The position name is the one of the type directly under the innermost
    /// anonymous context: a type nested in a local type prints as
    /// `M.CostCache.(WorkItem in $3990c).State`. When its address is that
    /// context's, the bare name is put back, so `markingUnknownContexts` can
    /// mark every context as the runtime spells it. Nil when the name carries
    /// another address: the evidence disagrees. The text is returned as it
    /// is when it has no position name for that type, or no context.
    static func withoutPositionName(
        _ text: String, contexts: [(address: UInt64, below: [String])], from start: String.Index
    ) -> String? {
        guard let innermost = contexts.first, let placed = innermost.below.last,
              let open = text.range(of: ".(\(placed) in $", range: start ..< text.endIndex)
        else { return text }
        guard let close = text[open.upperBound...].firstIndex(of: ")"),
              text[open.upperBound ..< close] == String(innermost.address, radix: 16)
        else { return nil }
        var unwrapped = text
        unwrapped.replaceSubrange(open.lowerBound ... close, with: ".\(placed)")
        return unwrapped
    }

    /// MachOSwiftSection 0.23 and later name a local type by the function or
    /// closure that declares it when the binary records one: `Result #1 in
    /// AppIntentsIndex.MetadataIndex.properties(forIdentifiers:)`. Such a name
    /// drops no context when the type directly under each anonymous context
    /// is a local declaration on the name's context spine (each node's first
    /// child), not one that only appears in a signature.
    static func namesEveryAnonymousContext(_ node: Node, contexts: [(address: UInt64, below: [String])]) -> Bool {
        guard !contexts.isEmpty else { return false }
        var local: Set<String> = []
        var current: Node? = node
        var hops = 0
        while let spine = current, hops < 64 {
            hops += 1
            let children = Array(spine.children)
            if children.count >= 2, children[1].kind == .localDeclName,
               let name = Array(children[1].children).last?.text {
                local.insert(name)
            }
            current = children.first
        }
        return contexts.allSatisfy { context in context.below.last.map(local.contains) ?? false }
    }

    /// Where the `below` names print last in a name, joined by dots, as a
    /// whole component (followed by the end, a space, `<`, `:` or `{`).
    static func nameSpan(of below: [String], in text: String, from start: String.Index) -> Range<String.Index>? {
        let suffix = "." + below.reversed().joined(separator: ".")
        var from = start
        while let found = text.range(of: suffix, range: from ..< text.endIndex) {
            let after = found.upperBound
            if after == text.endIndex || " <:{".contains(text[after]) { return found }
            from = found.upperBound
        }
        return nil
    }

    /// Marks each dropped anonymous context where it belongs in `text`, as
    /// the Swift runtime prints one. False, leaving `text` as it was, when a
    /// place is not found.
    static func markingUnknownContexts(
        _ contexts: [(address: UInt64, below: [String])], in text: inout String, from start: String.Index
    ) -> Bool {
        var marked = text
        let offset = text.distance(from: text.startIndex, to: start)
        // Outermost first, so an earlier insertion does not move a later span.
        for context in contexts.reversed() {
            guard let found = nameSpan(of: context.below, in: marked, from: marked.index(marked.startIndex, offsetBy: offset))
            else { return false }
            marked.insert(contentsOf: ".(unknown context at $\(String(context.address, radix: 16)))", at: found.lowerBound)
        }
        text = marked
        return true
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

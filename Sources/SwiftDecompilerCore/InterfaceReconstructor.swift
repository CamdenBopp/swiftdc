import Foundation
import MachOKit
// `indexer` and `printer` are SPI. Safe while MachOSwiftSection is exact-pinned;
// re-check them at each bump.
@_spi(Support) import SwiftInterface
@_spi(Support) import SwiftIndexing
@_spi(Support) import SwiftPrinting
import MachOSwiftSection

/// Reconstructs a Swift *interface* — `.swiftinterface`-style source — from a
/// Mach-O's Swift metadata, via MachOSwiftSection's `SwiftInterfaceBuilder`.
///
/// Higher fidelity than ``SwiftDeclarationDumper``: real Swift syntax with
/// generics, extensions, and conformances organized the way source is, rather
/// than a flat per-declaration listing. Works on standalone files and on
/// dyld-shared-cache images.
public struct InterfaceReconstructor: Sendable {
    public struct Options: Sendable {
        /// Include types imported from C in the generated interface.
        public var showCImportedTypes: Bool
        /// Emit `// offset` comments for stored properties.
        public var fieldOffsets: Bool
        /// Emit each member's binary address as a comment.
        public var memberAddresses: Bool
        /// Emit vtable-offset comments for class methods / computed properties.
        public var vtableOffsets: Bool
        /// Emit a memory-layout comment for each type.
        public var typeLayout: Bool
        /// Emit a memory-layout comment for each enum (payload/spare-bit info).
        public var enumLayout: Bool
        /// Order members by binary layout offset instead of grouping by category.
        public var sortByOffset: Bool
        /// Parse opaque (`some P`) return types. Experimental — may error on
        /// complex return types (hence off by default).
        public var parseOpaqueReturnTypes: Bool

        public init(
            showCImportedTypes: Bool = false,
            fieldOffsets: Bool = false,
            memberAddresses: Bool = false,
            vtableOffsets: Bool = false,
            typeLayout: Bool = false,
            enumLayout: Bool = false,
            sortByOffset: Bool = false,
            parseOpaqueReturnTypes: Bool = false
        ) {
            self.showCImportedTypes = showCImportedTypes
            self.fieldOffsets = fieldOffsets
            self.memberAddresses = memberAddresses
            self.vtableOffsets = vtableOffsets
            self.typeLayout = typeLayout
            self.enumLayout = enumLayout
            self.sortByOffset = sortByOffset
            self.parseOpaqueReturnTypes = parseOpaqueReturnTypes
        }
    }

    public var options: Options

    public init(options: Options = .init()) {
        self.options = options
    }

    /// Build and render the Swift interface for `machO` as plain text.
    public func reconstruct(_ machO: MachOFile) async throws -> String {
        let configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(showCImportedTypes: options.showCImportedTypes),
            printConfiguration: .init(
                printFieldOffset: options.fieldOffsets,
                printMemberAddress: options.memberAddresses,
                printVTableOffset: options.vtableOffsets,
                memberSortOrder: options.sortByOffset ? .byOffset : .byCategory,
                printTypeLayout: options.typeLayout,
                printEnumLayout: options.enumLayout
            )
        )
        let builder = try SwiftInterfaceBuilder(configuration: configuration, in: machO)
        if options.parseOpaqueReturnTypes {
            builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machO))
        }
        try await builder.prepare()
        var text = try await builder.printRoot().string
        // The builder indexes `__swift5_types` itself, so a record that
        // reaches into another image (`UnrecordedTypes.ownRecords`) prints
        // as a declaration here. Take out exactly what it printed.
        if let extent = ImageExtent(cacheImage: machO) {
            for definition in builder.indexer.rootTypeDefinitions.values
            where !extent.contains(cacheOffset: definition.typeContextDescriptorWrapper.contextDescriptor.offset) {
                text = Self.removing(try await builder.printer.printTypeDefinition(definition).string, from: text)
            }
        }
        text += Self.unrenderedTypesNote(text, in: machO, showsCImportedTypes: options.showCImportedTypes)
        // Nothing but imports from an image with no Swift section: there is
        // no module here, and the import block read as a valid empty one
        // (`interface` on a C dylib). Empty lets the caller say so, as `dump`
        // does. A module of free functions has no Swift section either, but
        // its declarations print.
        let declares = text.split(separator: "\n").contains { line in
            !line.allSatisfy(\.isWhitespace) && !line.hasPrefix("import ")
        }
        if !declares, !machO.sections.contains(where: { $0.sectionName.hasPrefix("__swift5_") }) { return "" }
        // The printer's address is the symbol it attributed a member to,
        // which for a stripped witness is a data slot; see MemberAddressAudit.
        return options.memberAddresses ? MemberAddressAudit(machO).audit(text).text : text
    }

    /// A closing comment naming each type the image records in
    /// `__swift5_types` that the printed interface neither declares nor
    /// extends, or an empty string. The builder drops a type it cannot read
    /// without a word: with its type references damaged, an image's
    /// interface printed `func top(_: S.Point)` alone, and Point, Box and
    /// Shape vanished, where `dump` names each. Nothing here proves why a
    /// type is missing, so the note says only that it is. A C-imported type
    /// is left out unless shown.
    static func unrenderedTypesNote(_ text: String, in machO: MachOFile, showsCImportedTypes: Bool = false) -> String {
        guard let recorded = UnrecordedTypes.ownRecords(in: machO) else { return "" }
        let missing = recorded.compactMap { type -> String? in
            let name: String?
            switch type {
            case .enum(let model): name = try? model.descriptor.name(in: machO)
            case .struct(let model): name = try? model.descriptor.name(in: machO)
            case .class(let model): name = try? model.descriptor.name(in: machO)
            }
            guard let name, !name.isEmpty else { return nil }
            let display = SwiftDeclarationDumper.displayName(of: type, in: machO)
            if !showsCImportedTypes, display.hasPrefix("__C.") { return nil }
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let present = text.range(of: #"\b(struct|class|enum|actor) "# + escaped + #"\b"#,
                                     options: .regularExpression) != nil
                || text.range(of: #"\bextension (\S+\.)?"# + escaped + #"\b"#, options: .regularExpression) != nil
            return present ? nil : "\(SwiftDeclarationDumper.kind(of: type)) \(display)"
        }
        guard !missing.isEmpty else { return "" }
        return "\n// Recorded in this image's __swift5_types but not declared above:\n"
            + missing.map { "//   \($0)\n" }.joined()
    }

    /// `text` without `block`, a whole run of lines of it.
    static func removing(_ block: String, from text: String) -> String {
        guard !block.isEmpty, let range = text.range(of: "\n" + block + "\n") else { return text }
        return text.replacingCharacters(in: range, with: "\n")
    }
}

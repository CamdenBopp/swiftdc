import Foundation
import MachOKit
import SwiftInterface

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
        return try await builder.printRoot().string
    }
}

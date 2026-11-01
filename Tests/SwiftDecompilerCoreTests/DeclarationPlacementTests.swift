import Testing
import Foundation
import Demangling
import MachOSwiftSection
@testable import SwiftDecompilerCore

/// Where `dump` places a type, and how it prints a field's type, checked
/// against what the binary itself says (`localtypes.swift`).
struct DeclarationPlacementTests {
    private func types(_ name: String) async throws -> String? {
        let path = "Fixtures/Sample/\(name)"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let machO = try BinaryLoader.load(path: path)
        return await withStableDependencies { await SwiftDeclarationDumper().dump(machO, sections: [.types]) }
    }

    /// A function-local type printed as a member of the enclosing type
    /// (`LocalTypes.Outer.Local`). With the type's descriptor symbol it is
    /// named by its function, as `swift-demangle` names that symbol.
    @Test func aLocalTypeIsNamedByItsFunctionIfPresent() async throws {
        guard let text = try await types("libLocalTypes.dylib") else { return }
        #expect(text.contains("struct Local #1 in LocalTypes.Outer.make() -> Any {"), Comment(rawValue: text))
        #expect(text.contains("struct FreeLocal #1 in LocalTypes.freeMake() -> Any {"), Comment(rawValue: text))
        #expect(!text.contains("struct LocalTypes.Outer.Local"), Comment(rawValue: text))
    }

    /// Stripped, nothing names the function, and the anonymous context is
    /// marked where it was dropped, as the Swift runtime prints one.
    @Test func aStrippedLocalTypeKeepsItsUnknownContextIfPresent() async throws {
        guard let text = try await types("libLocalTypes.stripped.dylib") else { return }
        let local = text.split(separator: "\n").first { $0.hasSuffix(".Local {") }.map(String.init) ?? ""
        #expect(local.hasPrefix("struct LocalTypes.Outer.(unknown context at $"), "\(local)")
        #expect(!text.contains("struct LocalTypes.Outer.Local"), Comment(rawValue: text))
        #expect(!text.contains("struct LocalTypes.FreeLocal"), Comment(rawValue: text))
    }

    /// A constrained existential field printed `symbolic existential type
    /// (non-unique) 0x0 <Swift.String>`: no protocol, no meaning.
    @Test func aConstrainedExistentialFieldNamesItsProtocolIfPresent() async throws {
        guard let text = try await types("libLocalTypes.stripped.dylib") else { return }
        #expect(text.contains("var source: Swift.Optional<any LocalTypes.Source<Self.LocalTypes.Source.Element == Swift.String>>"), Comment(rawValue: text))
        #expect(!text.contains("symbolic existential"), Comment(rawValue: text))
        let machO = try BinaryLoader.load(path: "Fixtures/Sample/libLocalTypes.stripped.dylib")
        let maps = try await withStableDependencies { try FieldMapBuilder.build(in: machO) }
        let holder = try #require(maps["LocalTypes.Holder"])
        #expect(holder.fieldTypeNames["pair"] == "Swift.Optional<any LocalTypes.Source<Self.LocalTypes.Source.Element == Swift.Int>>")
    }

    /// A shape whose type names a parameter the arguments do not supply is
    /// not printed as a type.
    @Test func anUnresolvableShapeDeclines() {
        let parameter = Node.create(kind: .type, child: Node.create(kind: .dependentGenericParamType, children: [
            Node.create(kind: .index, index: 0), Node.create(kind: .index, index: 1),
        ]))
        let shape = Node.create(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, child: parameter)
        let arguments = Node.create(kind: .typeList, child: Node.create(kind: .type, child: Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Swift"), Node.create(kind: .identifier, text: "Int"),
        ])))
        let field = Node.create(kind: .type, child: Node.create(kind: .symbolicExtendedExistentialType, children: [shape, arguments]))
        #expect(throws: ExtendedExistentials.Unresolved.self) { try ExtendedExistentials.resolve(field) }
        // A parameter at depth 1 is no generalization parameter.
        let deeper = Node.create(kind: .type, child: Node.create(kind: .symbolicExtendedExistentialType, children: [
            Node.create(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, child: Node.create(kind: .type, child: Node.create(kind: .dependentGenericParamType, children: [
                Node.create(kind: .index, index: 1), Node.create(kind: .index, index: 0),
            ]))),
            arguments,
        ]))
        #expect(throws: ExtendedExistentials.Unresolved.self) { try ExtendedExistentials.resolve(deeper) }
        // Index 0 is supplied: it resolves to the argument.
        let resolvable = Node.create(kind: .type, child: Node.create(kind: .symbolicExtendedExistentialType, children: [
            Node.create(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, child: Node.create(kind: .type, child: Node.create(kind: .dependentGenericParamType, children: [
                Node.create(kind: .index, index: 0), Node.create(kind: .index, index: 0),
            ]))),
            arguments,
        ]))
        #expect((try? ExtendedExistentials.resolve(resolvable))?.print(using: .default) == "Swift.Int")
    }

    /// A type no `__swift5_types` record lists, reachable only from its
    /// field descriptor and another type's field, was missing from `dump`.
    @Test func aTypeNoRecordListsIsDeclaredIfPresent() async throws {
        guard let text = try await types("libUnrecordedType.dylib") else { return }
        #expect(text.contains("struct UnrecordedType.Inner {\n    var a: Swift.Int\n    var b: Swift.Int"), Comment(rawValue: text))
        #expect(text.contains("struct UnrecordedType.Holder {"), Comment(rawValue: text))
    }

    /// `layout` and field naming read the same types: `Inner`, which no
    /// record lists, has its two fields.
    @Test func aTypeNoRecordListsIsLaidOutIfPresent() async throws {
        let path = "Fixtures/Sample/libUnrecordedType.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let machO = try BinaryLoader.load(path: path)
        let maps = try await withStableDependencies { try FieldMapBuilder.build(in: machO) }
        let inner = try #require(maps["UnrecordedType.Inner"])
        #expect(inner.fields.map(\.name) == ["a", "b"])
        #expect(inner.instanceSize == 16)
    }

    /// The reader the walk uses returns the file's bytes, at every offset
    /// and width, against a plain read of the file.
    @Test func theFieldDescriptorReaderReadsTheFileIfPresent() throws {
        let path = "Fixtures/Sample/libUnrecordedType.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let machO = try BinaryLoader.load(path: path)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        let section = try #require(machO.sections.first { $0.sectionName == "__swift5_fieldmd" })
        var mismatches = 0
        for offset in section.offset ..< section.offset + section.size - 4 {
            let byte = bytes[offset]
            let word = bytes[offset ..< offset + 4].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            if UnrecordedTypes.read(offset, as: UInt8.self, in: machO) != byte { mismatches += 1 }
            if UnrecordedTypes.read(offset, as: UInt32.self, in: machO) != word { mismatches += 1 }
            if UnrecordedTypes.read(offset, as: UInt16.self, in: machO) != UInt16(truncatingIfNeeded: word) { mismatches += 1 }
        }
        #expect(mismatches == 0)
    }

    /// A type the renderer fails on was skipped, which read as a binary
    /// without it: GenerativeAgents' `OpenAICompatibleModel` (its argument
    /// type is a cross-image reference the reader does not follow).
    @Test func aTypeThatFailsToRenderIsNamedIfAvailable() async throws {
        let path = "/System/Library/PrivateFrameworks/GenerativeAgents.framework/Versions/A/GenerativeAgents"
        guard let machO = try? BinaryLoader.loadFromDyldCache(cachePath: nil, selector: .path(path)) else { return }
        // The metadata, not the output, says whether the type is there.
        let names = ((try? machO.swift.types) ?? []).map { SwiftDeclarationDumper.displayName(of: $0, in: machO) }
        guard names.contains("GenerativeAgents.OpenAICompatibleModel") else { return }
        let text = await withStableDependencies { await SwiftDeclarationDumper().dump(machO, sections: [.types]) }
        #expect(text.contains("// struct GenerativeAgents.OpenAICompatibleModel: not rendered: ")
            || text.contains("struct GenerativeAgents.OpenAICompatibleModel {"), Comment(rawValue: String(text.prefix(2000))))
    }
}

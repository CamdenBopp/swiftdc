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

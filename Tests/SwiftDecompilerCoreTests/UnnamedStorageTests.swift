import Testing
import Foundation
import MachOKit
@testable import SwiftDecompilerCore

/// A descriptor counts cases and fields; only field records name them.
/// `dump` and `layout` say so rather than print a type with nothing in it
/// (`interfacefacts.swift`).
struct UnnamedStorageTests {
    private func dump(_ name: String) async throws -> String? {
        let path = "Fixtures/Sample/\(name)"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let machO = try BinaryLoader.load(path: path)
        return await withStableDependencies { await SwiftDeclarationDumper().dump(machO, sections: [.types]) }
    }

    private func comments(_ name: String) async throws -> [String: String]? {
        let path = "Fixtures/Sample/\(name)"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let machO = try BinaryLoader.load(path: path)
        let found = await withStableDependencies { UnnamedStorage.comments(in: machO) }
        return Dictionary(found.map { ($0.type, $0.comment) }, uniquingKeysWith: { first, _ in first })
    }

    /// `@objc` enums have no records in an ordinary build, and a type with
    /// records, or with nothing to name, is left alone.
    @Test func anObjCEnumCountsItsCasesIfPresent() async throws {
        guard let comments = try await comments("libInterfaceFacts.dylib") else { return }
        #expect(comments == ["InterfaceFacts.ObjCEnum": "2 cases: the binary has no field records, so no names"])
        guard let text = try await dump("libInterfaceFacts.dylib") else { return }
        #expect(text.contains("enum InterfaceFacts.ObjCEnum {\n    // 2 cases: the binary has no field records, so no names\n"), Comment(rawValue: text))
    }

    /// Without reflection metadata the same holds for every type, payload
    /// cases and stored fields included; an enum without cases says nothing.
    @Test func noReflectionMetadataCountsEverythingIfPresent() async throws {
        guard let comments = try await comments("libInterfaceFacts.noreflection.dylib") else { return }
        #expect(comments["InterfaceFacts.Payloaded"] == "3 cases (2 with a payload): the binary has no field records, so no names")
        #expect(comments["InterfaceFacts.Stored"] == "2 stored fields: the binary has no field records, so no names")
        #expect(comments["InterfaceFacts.StoredClass"] == "1 stored field: the binary has no field records, so no names")
        #expect(comments["InterfaceFacts.Caseless"] == nil)
    }

    /// A body the dump left empty keeps its braces around the comment.
    @Test func aCommentOpensAnEmptyBody() {
        #expect(UnnamedStorage.placing("n", in: "enum E {}") == "enum E {\n    // n\n}")
        #expect(UnnamedStorage.placing("n", in: "enum E {\n    /* Allocator */\n}") == "enum E {\n    // n\n\n    /* Allocator */\n}")
    }
}

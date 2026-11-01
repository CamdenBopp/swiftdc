import Testing
import Foundation
import Demangling
import MachOSwiftSection
@testable import SwiftDecompilerCore

/// Where `dump` places a type, and how it prints a field's type, checked
/// against what the binary itself says.
struct DeclarationPlacementTests {
    private func types(_ name: String) async throws -> String? {
        let path = "Fixtures/Sample/\(name)"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let machO = try BinaryLoader.load(path: path)
        return await withStableDependencies { await SwiftDeclarationDumper().dump(machO, sections: [.types]) }
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

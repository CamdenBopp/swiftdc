import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A getter that takes arguments.
struct DispatchThunkArgumentTests {
    private func function(_ path: String, _ name: String) async throws -> DisassembledFunction? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        return try #require(functions.first { $0.displayName.contains(name) })
    }

    /// A subscript's getter takes its index: `g[i]` read
    /// `Grid.subscript.getter(self: arg0)`.
    @Test func aSubscriptGetterTakesItsIndexIfPresent() async throws {
        guard let read = try await function("Fixtures/Sample/libSubscriptGetter.dylib", "SubscriptGetter.read") else { return }
        let pseudo = read.renderPseudo()
        #expect(pseudo.contains("SubscriptGetter.Grid.subscript.getter(self: arg0, arg1)"), Comment(rawValue: pseudo))
        #expect(!Disassembler.getterTakesNoArguments(
            "SubscriptGetter.Grid.subscript.getter : (Swift.Int) -> Swift.Int", classTypeIndex: ClassTypeIndex()))
    }
}

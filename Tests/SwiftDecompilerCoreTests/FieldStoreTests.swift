import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A field loaded, overwritten, then tested by its old value
/// (`fieldstore.swift`, -O): `ldr x0, [x20, #0x10]; str xzr, [x20, #0x10];
/// cbz x0`. Named by the field at the test, the condition read the new value:
/// `self.v = 0` then `if (self.v != 0)`, never true. Across a store or a call
/// the loaded register is not named by its field.
@Test func aFieldOverwrittenBeforeItsTestIsNotNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libFieldStore.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    let take = try structured("FieldStore.Cell.take() -> ()")
    #expect(take.contains("self.v = 0"), Comment(rawValue: take))
    #expect(!take.contains("if (self.v != 0)"), Comment(rawValue: take))
    // A call between the load and the test may change the field too.
    let peek = try structured("FieldStore.Cell.peek() -> ()")
    #expect(!peek.contains("if (self.v != 0)"), Comment(rawValue: peek))
    let release = try structured("FieldStore.Chain.deinit")
    #expect(release.contains("self.next = 0"), Comment(rawValue: release))
    #expect(!release.contains("if (self.next != 0)"), Comment(rawValue: release))
    // Nothing between the load and the test: still named by its field.
    let forward = try structured("FieldStore.Chain.forward() -> ()")
    #expect(forward.contains("if (self.next != 0)"), Comment(rawValue: forward))
}

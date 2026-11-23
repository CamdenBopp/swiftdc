import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `interface` on an image with no Swift section printed an import block,
/// a plausible empty module, where `dump` said no Swift metadata was found.
/// Nothing to reconstruct is now an empty result, which the CLI reports. A
/// Swift module keeps its interface, including one of free functions only,
/// which has no Swift section either (`libCallArity`).
@Test func anImageWithNoSwiftHasNoInterfaceIfPresent() async throws {
    let c = "Fixtures/Sample/libVariadicCalls.dylib"
    let swift = "Fixtures/Sample/libSample.dylib"
    guard FileManager.default.fileExists(atPath: c), FileManager.default.fileExists(atPath: swift) else { return }
    let cImage = try BinaryLoader.load(path: c)
    let none = try await withStableDependencies { try await InterfaceReconstructor().reconstruct(cImage) }
    #expect(none.isEmpty, Comment(rawValue: none))
    let swiftImage = try BinaryLoader.load(path: swift)
    let some = try await withStableDependencies { try await InterfaceReconstructor().reconstruct(swiftImage) }
    #expect(some.contains("import Swift"), Comment(rawValue: String(some.prefix(200))))
    let functionsOnly = "Fixtures/Sample/libCallArity.dylib"
    if FileManager.default.fileExists(atPath: functionsOnly) {
        let image = try BinaryLoader.load(path: functionsOnly)
        let text = try await withStableDependencies { try await InterfaceReconstructor().reconstruct(image) }
        #expect(text.contains("func one(_: Swift.Int) -> Swift.Int"), Comment(rawValue: text))
    }
}

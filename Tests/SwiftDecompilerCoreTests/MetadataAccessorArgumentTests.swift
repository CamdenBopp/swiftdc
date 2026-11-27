import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A type metadata accessor of another image takes the request in x0 and,
/// only for a generic type, metadata after it. Its name does not say which.
/// `foreignMake(_: Int, _: Int, _: Int)` reaches the accessor of a class
/// that is not generic with its own formals still in x1 and x2, and
/// rendered `type metadata accessor for MetaAccessorKit.MAKlass(0, arg1,
/// arg2)`. metaaccessorclient.swift states each function's value.
private let accessorImage = "Fixtures/Sample/libMetaAccessorClient.dylib"

private func accessorViews(_ name: String) async throws -> [String]? {
    guard FileManager.default.fileExists(atPath: accessorImage) else { return nil }
    let image = try BinaryLoader.load(path: accessorImage)
    let listing = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: accessorImage)
    }
    let filtered = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: accessorImage, functionFilter: name)
    }
    let streamed = await withStableDependencies {
        await Disassembler(preset: .default).disassembleStreaming(machO: image, transform: { $0 })
    }
    return try [listing, filtered, streamed].flatMap { functions -> [String] in
        let function = try #require(functions.first { $0.displayName.contains("MetaAccessorClient.\(name)(") })
        return [function.renderStructured(), function.renderPseudo()]
    }
}

@Test func anImportedMetadataAccessorShowsItsRequestAndAnUnknownTailIfPresent() async throws {
    guard let views = try await accessorViews("foreignMake") else { return }
    for text in views {
        #expect(text.contains("type metadata accessor for MetaAccessorKit.MAKlass(0, …)"), "\(text)")
        #expect(!text.contains("arg1") && !text.contains("arg2"), "\(text)")
        // The object's one field still takes the first formal.
        #expect(text.contains("= arg0"), "\(text)")
    }
}

/// An accessor in the image is read from its body, which takes nothing.
@Test func anAccessorOfThisImageKeepsWhatItsBodyReadsIfPresent() async throws {
    guard let views = try await accessorViews("localMake") else { return }
    for text in views {
        #expect(text.contains("type metadata accessor for MetaAccessorClient.MALocal()"), "\(text)")
    }
}

/// With nothing known past the request the list ends there, as trailing
/// unknowns are trimmed everywhere: no tail is claimed or dropped.
@Test func anImportedAccessorWithNothingAfterItsRequestShowsNoTailIfPresent() async throws {
    guard let views = try await accessorViews("foreignOnly") else { return }
    for text in views {
        #expect(text.contains("type metadata accessor for MetaAccessorKit.MAKlass(0)"), "\(text)")
    }
}

import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let frameMayFixture = "Fixtures/Sample/libFrameMay.dylib"

@Test func lostFramePointerPreservationHasIndependentNativeOraclesIfPresent() throws {
    guard FileManager.default.fileExists(atPath: frameMayFixture) else { return }
    let library = try #require(dlopen(frameMayFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Entry = @convention(c) () -> Int64
    for (name, expected): (String, Int64) in [
        ("directCell", 99), ("sameCall", 99), ("shadowSave", 99), ("keepProven", 7), ("keepUnproved", 7),
    ] {
        let symbol = "$s8FrameMay\(name.count)\(name)SiyF"
        let entry = unsafeBitCast(try #require(dlsym(library, symbol)), to: Entry.self)
        #expect(entry() == expected, Comment(rawValue: name))
    }
}

@Test func losingFramePointerPreservationKeepsPossibleFrameReachInEveryPipelineIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: frameMayFixture) else { return }
    let image = try BinaryLoader.load(path: frameMayFixture)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: frameMayFixture) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: frameMayFixture, functionFilter: "FrameMay.")
    }
    let streamed = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    for group in [listing, array, filtered, streamed, Array(each.values)] {
        for name in ["directCell", "sameCall", "shadowSave"] {
            let function = try #require(group.first { $0.displayName.hasPrefix("FrameMay.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains("return ?"), Comment(rawValue: text))
                #expect(!text.contains("return 7"), Comment(rawValue: text))
            }
        }
        for name in ["keepProven", "keepUnproved"] {
            let positive = try #require(group.first { $0.displayName.hasPrefix("FrameMay.\(name)(") })
            for text in [positive.renderPseudo(), positive.renderStructured()] {
                #expect(text.contains("return 7"), Comment(rawValue: text))
            }
        }
    }
}

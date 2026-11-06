import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let frameLayoutAliasFixture = "Fixtures/Sample/libFrameLayoutAlias.dylib"

@Test func frameLayoutAliasHasAnIndependentNativeOracleIfPresent() throws {
    guard FileManager.default.fileExists(atPath: frameLayoutAliasFixture) else { return }
    let library = try #require(dlopen(frameLayoutAliasFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Oracle = @convention(c) () -> Int64
    func call(_ name: String) throws -> Int64 {
        let address = try #require(dlsym(library, name))
        return unsafeBitCast(address, to: Oracle.self)()
    }
    #expect(try call("$s16FrameLayoutAlias12forwardAliasSiyF") == 11)
    #expect(try call("$s16FrameLayoutAlias8noEscapeSiyF") == 7)
}

/// Two addresses can refer to words of one local. The later interior address
/// cannot stop the earlier pointer's write range at that word and retain 7.
@Test func anInteriorFrameAddressDoesNotProveAnObjectBoundaryIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: frameLayoutAliasFixture) else { return }
    let full = try await withStableDependencies {
        try await Disassembler().disassemble(path: frameLayoutAliasFixture)
    }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: frameLayoutAliasFixture, functionFilter: "FrameLayoutAlias.")
    }
    let streamed = try await withStableDependencies {
        let image = try BinaryLoader.load(path: frameLayoutAliasFixture)
        return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    for functions in [full, filtered, streamed] {
        let changed = try #require(functions.first { $0.displayName.hasPrefix("FrameLayoutAlias.forwardAlias(") })
        let kept = try #require(functions.first { $0.displayName.hasPrefix("FrameLayoutAlias.noEscape(") })
        for structured in [false, true] {
            let text = structured ? changed.renderStructured() : changed.renderPseudo()
            #expect(text.contains("return 11"), Comment(rawValue: text))
            #expect(!text.contains("return 7"), Comment(rawValue: text))
            let control = structured ? kept.renderStructured() : kept.renderPseudo()
            #expect(control.contains("return 7"), Comment(rawValue: control))
        }
        // With no callee body available, the raw-address fallback still
        // declines. A later interior address must never make it return7.
        let unproven = ValueTracer().analyze(changed)
        let exit = try #require(changed.instructions.last?.address)
        #expect((unproven.exitValues[exit] ?? .unknown) == .unknown)
    }
    for structured in [false, true] {
        func views(_ functions: [DisassembledFunction]) -> [String: String] {
            Dictionary(uniqueKeysWithValues: functions.filter { $0.displayName.hasPrefix("FrameLayoutAlias.") }
                .map { ($0.symbol, structured ? $0.renderStructured() : $0.renderPseudo()) })
        }
        #expect(views(filtered) == views(full))
        #expect(views(streamed) == views(full))
    }
}

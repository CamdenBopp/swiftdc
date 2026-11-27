import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A module-level function has no `self`, generic or not. Its printed name
/// carries its own generic parameters, `M.name<A where A: M.P>(…)`, which
/// hid that it is `M.name`: `weighPair` keeps one of its formals in x20
/// across `gWeigh` and rendered `gWeigh<…>(self: arg0, local_30, arg2)`.
/// freegenericclient.swift states each function's value.
private let freeGenericImage = "Fixtures/Sample/libFreeGenericClient.dylib"

private func freeGenericViews(_ name: String) async throws -> [String]? {
    guard FileManager.default.fileExists(atPath: freeGenericImage) else { return nil }
    let image = try BinaryLoader.load(path: freeGenericImage)
    let listing = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: freeGenericImage)
    }
    let filtered = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: freeGenericImage, functionFilter: name)
    }
    let streamed = await withStableDependencies {
        await Disassembler(preset: .default).disassembleStreaming(machO: image, transform: { $0 })
    }
    return try [listing, filtered, streamed].flatMap { functions -> [String] in
        let function = try #require(functions.first { $0.displayName.contains("FreeGenericClient.\(name)(") })
        return [function.renderStructured(), function.renderPseudo()]
    }
}

@Test func aGenericFreeFunctionHasNoSelfIfPresent() async throws {
    guard let views = try await freeGenericViews("weighPair") else { return }
    for text in views {
        #expect(text.contains("FreeGenericKit.gWeigh<A where A: FreeGenericKit.FGWeighted>(local_"), "\(text)")
        #expect(!text.contains("self:"), "\(text)")
    }
}

/// A generic method of a class is no free function: its receiver is in x20.
@Test func aGenericMethodKeepsItsReceiverIfPresent() async throws {
    guard let views = try await freeGenericViews("viaMethod") else { return }
    for text in views {
        #expect(text.contains("FreeGenericKit.FGBox.pick<A>(self: arg0, "), "\(text)")
    }
}

/// Only a clause the name ends in is the function's own.
@Test func onlyATrailingGenericClauseIsRemoved() {
    func stripped(_ name: String) -> String { String(Disassembler.withoutTrailingGenericClause(name[...])) }
    #expect(stripped("M.f<A>") == "M.f")
    #expect(stripped("M.f<A where A: M.P>") == "M.f")
    #expect(stripped("M.f<A, B where A: M.P<B>>") == "M.f")
    // The `>` of an arrow inside the clause closes nothing.
    #expect(stripped("M.f<A where A == (Swift.Int) -> Swift.Int>") == "M.f")
    // A type's clause in the middle stays, and so the name is no `M.name`.
    #expect(stripped("M.Box<A>.get") == "M.Box<A>.get")
    #expect(stripped("M.Box<A>.get<B>") == "M.Box<A>.get")
    #expect(stripped("M.f") == "M.f")
    // Unbalanced: returned as it is.
    #expect(stripped("M.f>") == "M.f>")
}

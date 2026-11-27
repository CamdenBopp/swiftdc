import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A member an extension adds, called with `self` in x20, takes its formals
/// from x0 and nothing of `self` after them. `viaExistential` calls
/// `EMShape.scaled(_: Int)` on an opened existential and rendered
/// `scaled(self: …, arg2, ?, ?, <the projected address>)`: the hidden
/// metadata and witness table, and a temporary still in x3.
/// extensionmemberclient.swift states each function's value.
private let extensionMemberImage = "Fixtures/Sample/libExtensionMemberClient.dylib"

private func extensionMemberViews(_ name: String) async throws -> [String]? {
    guard FileManager.default.fileExists(atPath: extensionMemberImage) else { return nil }
    let image = try BinaryLoader.load(path: extensionMemberImage)
    let listing = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: extensionMemberImage)
    }
    let filtered = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: extensionMemberImage, functionFilter: name)
    }
    let streamed = await withStableDependencies {
        await Disassembler(preset: .default).disassembleStreaming(machO: image, transform: { $0 })
    }
    return try [listing, filtered, streamed].flatMap { functions -> [String] in
        let function = try #require(functions.first { $0.displayName.contains("ExtensionMemberClient.\(name)(") })
        return [function.renderStructured(), function.renderPseudo()]
    }
}

@Test func anExtensionMemberCalledOnAnExistentialTakesItsFormalsOnlyIfPresent() async throws {
    guard let views = try await extensionMemberViews("viaExistential") else { return }
    for text in views {
        #expect(text.contains("EMShape.scaled(self: __swift_project_boxed_opaque_existential_1(local_"), "\(text)")
        #expect(text.contains(", ?), arg2)\n"), "\(text)")
    }
}

/// A value type's member takes `self` in the registers after its formals,
/// and x20 is not its receiver. An Int is one word, so the call takes its
/// formal and that word: `emPlus(arg2, arg0, arg2)` named a third register,
/// the formal's source still in x2.
@Test func anExtensionMemberOfAnIntegerTakesItsFormalsAndOneWordIfPresent() async throws {
    guard let views = try await extensionMemberViews("viaInt") else { return }
    for text in views {
        #expect(text.contains("Swift.Int.emPlus(arg2, arg0) + arg1)"), "\(text)")
        #expect(!text.contains("self:"), "\(text)")
    }
}

/// A formal in a floating-point register comes from that bank: the
/// Double is in d0, whatever the integer registers hold. It read
/// `tilted(self: …, ?, ?, <the projected address>)`.
@Test func anExtensionMemberTakesAFloatFormalFromItsOwnRegisterIfPresent() async throws {
    guard let views = try await extensionMemberViews("viaDouble") else { return }
    for text in views {
        #expect(text.contains("EMShape.tilted(self: __swift_project_boxed_opaque_existential_1(local_"), "\(text)")
        #expect(text.contains(", ?), arg2)\n"), "\(text)")
    }
}

/// A struct formal is neither kind of scalar: the call is left as found.
@Test func anExtensionMemberWithAStructFormalIsLeftAsFoundIfPresent() async throws {
    guard let views = try await extensionMemberViews("viaStruct") else { return }
    for text in views {
        #expect(text.contains("ExtensionMemberKit.EMBig.init(a:b:c:d:)(arg2, 1, 2, 3))"), "\(text)")
    }
}

/// The rule is for a member an extension adds. A protocol witness thunk
/// called with `self` in x20 is left as found, its hidden metadata and
/// witness table shown: trimming it to its formals is not proven here.
@Test func aWitnessThunkIsNotTrimmedToItsFormalsIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let all = functions.map { $0.renderStructured() }.joined(separator: "\n")
    let call = try #require(all.split(separator: "\n").first {
        $0.contains("protocol witness for sample.Shape.describe(self: ")
    })
    #expect(call.contains("), 0x"), "\(call)")
}

/// Only a fixed-width integer's one word is known from its name.
@Test func onlyAFixedWidthIntegerReceiverHasAKnownWordCount() {
    for name in ["Swift.Int", "Swift.UInt8", "Swift.Int64", "Swift.Bool"] {
        #expect(Disassembler.extensionReceiverWords(name) == 1, "\(name)")
    }
    for name in ["Swift.String", "Swift.UnsafeRawBufferPointer", "Swift.Double", "M.Pair", "Swift.Array<Swift.Int>", ""] {
        #expect(Disassembler.extensionReceiverWords(name) == nil, "\(name)")
    }
}

/// A two-word receiver is not cut to one word past its formal: its call is
/// left as another layout decided it.
@Test func anExtensionMemberOfATwoWordValueIsNotBoundToOneWordIfPresent() async throws {
    guard let views = try await extensionMemberViews("viaBuffer") else { return }
    for text in views {
        #expect(text.contains("Swift.UnsafeRawBufferPointer.emCount(…)"), "\(text)")
    }
}

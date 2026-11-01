import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `__swift_instantiateConcreteTypeFromMangledNameV2` is a private helper
/// IRGen emits into every image, so a stripped binary leaves it unnamed and
/// its calls read `sub_100008a20(0x1010f3150, 0x100dac540)` (GoodLinks). Its
/// body has one fixed shape, which names it; a function that differs in its
/// callee or its branch is not it (`mangledhelper.s`).
@Test func theMangledNameMetadataHelperIsNamedByItsBodyIfPresent() async throws {
    let path = "Fixtures/Sample/libMangledHelper.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func function(at address: UInt64) throws -> DisassembledFunction {
        try #require(functions.first { $0.startAddress == address })
    }
    let entry = try #require(functions.first { $0.displayName == "_entry" })
    let calls = entry.instructions.compactMap(\.branchTarget)
    try #require(calls.count == 3)
    let genuine = try function(at: calls[0])
    #expect(genuine.displayName == Disassembler.mangledNameMetadataHelperName)
    #expect(genuine.source == .helperShape)
    #expect(genuine.render().contains("[recognized by its body: a helper IRGen emits]"))
    for lookalike in [calls[1], calls[2]] {
        let function = try function(at: lookalike)
        #expect(function.displayName.hasPrefix("sub_"), "\(function.displayName)")
    }
    #expect(entry.renderPseudo().contains("__swift_instantiateConcreteTypeFromMangledNameV2("))

    // The streaming whole-image path (`disasm --pseudo`) and a filtered run
    // name it too.
    let machO = try BinaryLoader.load(path: path)
    let streamed = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: machO) { $0.displayName }
    }
    #expect(streamed.contains(Disassembler.mangledNameMetadataHelperName))
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "instantiateConcrete")
    }
    #expect(filtered.map(\.displayName) == [Disassembler.mangledNameMetadataHelperName])
}

/// The helper is a C function, so its x20 is no `self`: stripped, a call
/// with x20 freshly written read `__swift_instantiateConcreteTypeFromMangledNameV2(self: arg0, …)`.
@Test func theRecognizedHelperTakesNoSelfIfPresent() async throws {
    let path = "Fixtures/Sample/libReconstruction.opt.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(text.contains("__swift_instantiateConcreteTypeFromMangledNameV2(0x"))
    #expect(!text.contains("__swift_instantiateConcreteTypeFromMangledNameV2(self:"))
    let machO = try BinaryLoader.load(path: path)
    let streamed = await withStableDependencies {
        await Disassembler().disassembleStreamingRender(machO: machO) { $0.renderPseudo() }
    }.joined(separator: "\n")
    #expect(streamed.contains("__swift_instantiateConcreteTypeFromMangledNameV2(0x"))
    #expect(!streamed.contains("__swift_instantiateConcreteTypeFromMangledNameV2(self:"))
}

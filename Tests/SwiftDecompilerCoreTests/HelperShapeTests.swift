import Foundation
import Testing
import Demangling
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
    #expect(text.contains("swift_allocObject(type metadata for "))
    #expect(!text.contains("__swift_instantiateConcreteTypeFromMangledNameV2(self:"))
    let machO = try BinaryLoader.load(path: path)
    let streamed = await withStableDependencies {
        await Disassembler().disassembleStreamingRender(machO: machO) { $0.renderPseudo() }
    }.joined(separator: "\n")
    #expect(streamed.contains("swift_allocObject(type metadata for "))
    #expect(!streamed.contains("__swift_instantiateConcreteTypeFromMangledNameV2(self:"))
}

/// Each pair the helper takes spells its type: decoded, it is the type the
/// pair's own `…MR` symbol ("mangled name ref for type metadata for T")
/// names, for all of `mangledtypes.swift`'s pairs, generic, sugared,
/// nested, tuple, function and Foundation types among them. Stripped, the
/// calls render those types (`swift_allocObject(type metadata for …)`).
@Test func aMangledNamePairDecodesToItsSymbolsTypeIfPresent() async throws {
    let path = "Fixtures/Sample/libMangledTypes.dylib"
    let stripped = "Fixtures/Sample/libMangledTypes.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path), FileManager.default.fileExists(atPath: stripped) else { return }
    let machO = try BinaryLoader.load(path: path)
    let prefix = "mangled name ref for type metadata for "
    var checked = 0
    for symbol in machO.symbols where symbol.name.hasPrefix("_$s") && symbol.name.hasSuffix("MR") {
        guard let address = Disassembler.sectionAddress(of: symbol),
              let printed = demangledPrinted(String(symbol.name.dropFirst()))
        else { continue }
        try #require(printed.hasPrefix(prefix), "\(printed)")
        #expect(MangledNamePair.typeName(at: address, in: machO) == String(printed.dropFirst(prefix.count)),
                "\(symbol.name)")
        // Four bytes in, the length word is read as an offset: whatever it
        // leads to is not a name of the pair's length.
        #expect(MangledNamePair.typeName(at: address + 4, in: machO) == nil, "\(symbol.name) + 4")
        checked += 1
    }
    #expect(checked >= 12)
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: stripped) }
    let text = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(text.contains("swift_allocObject(type metadata for Swift._ContiguousArrayStorage<"), Comment(rawValue: text))
}

private func demangledPrinted(_ symbol: String) -> String? {
    guard let node = try? demangleAsNode(symbol) else { return nil }
    return node.print(using: .default)
}

/// Each helper shape is checked against the symbols it was taken from: in
/// every arm64 fixture that names its helpers, the recogniser, shown no
/// labels, names a function only where the symbol there is that helper,
/// and every shape names at least one.
@Test func everyHelperShapeNamesOnlyItsHelperIfPresent() throws {
    let directory = "Fixtures/Sample"
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    let disassembler = Disassembler()
    var namedHelpers = Set<String>()
    // libMangledHelper labels its helper `genuine`, by design.
    for entry in entries.sorted() where entry.hasSuffix(".dylib") && !entry.contains("stripped")
        && !entry.hasPrefix("libMangledHelper") {
        guard let machO = try? BinaryLoader.load(path: "\(directory)/\(entry)"), machO.header.cpuType == .arm64 else { continue }
        var symbols: [UInt64: Set<String>] = [:]
        for symbol in machO.symbols {
            if let address = Disassembler.sectionAddress(of: symbol) { symbols[address, default: []].insert(symbol.name) }
        }
        let boundaries = Set(disassembler.functionStarts(of: machO)).union(symbols.keys).sorted()
        for (address, name) in disassembler.recognizedHelperNames(in: machO, boundaries: boundaries, labels: [:]) {
            #expect(symbols[address]?.contains("_" + name) == true, "\(entry) 0x\(String(address, radix: 16)): \(name) vs \(symbols[address] ?? [])")
            namedHelpers.insert(name)
        }
    }
    #expect(namedHelpers == Disassembler.helperShapeNames, "\(Disassembler.helperShapeNames.subtracting(namedHelpers))")
}

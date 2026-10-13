import Foundation
import Testing
import Demangling
@testable import SwiftDecompilerCore

@Test func nominalTreesKeepClassesSeparateFromImportedValueTypes() throws {
    var evidence = NominalTypeEvidence()
    for symbol in ["$s18ImportedClassProbe10withObjectyS2i_So8NSObjectCtF",
                   "$s18ImportedClassProbe9withPointyS2i_So7CGPointVtF"] {
        evidence.collect(from: try demangleAsNode(symbol), options: .default)
    }
    let index = ClassTypeIndex().adding(evidence)
    #expect(index.isClass("__C.NSObject"))
    #expect(!index.isClass("__C.CGPoint"))
    #expect(index.referenceOptionalInner("Swift.Optional<__C.NSObject>") == "__C.NSObject")
    // Conflicting metadata wins conservatively over a nominal class node.
    let disputed = ClassTypeIndex(qualifiedNonClassNames: ["__C.NSObject"]).adding(evidence)
    #expect(!disputed.isClass("__C.NSObject"))
    let shadowed = ClassTypeIndex(classNames: ["Ref"], qualifiedClassNames: ["M.Ref"])
        .adding(NominalTypeEvidence(values: ["External.Ref"]))
    #expect(!shadowed.isClass("Ref"))
    #expect(shadowed.isClass("M.Ref"))
    #expect(!shadowed.isClass("External.Ref"))
}

@Test func aPlainKnownClassSeedsLikeItsOptional() {
    let index = ClassTypeIndex(qualifiedClassNames: ["M.Ref"])
    for type in ["M.Ref", "Swift.Optional<M.Ref>"] {
        let function = DisassembledFunction(symbol: "$s1M1f", demangledName: "M.f(Swift.Int, \(type)) -> Swift.Int",
            startAddress: 0x1000, instructions: [], source: .symbol)
        #expect(Disassembler.swiftScalarArgumentRegisters(of: function, classTypeIndex: index) == ["x0": 0, "x1": 1])
    }
}

@Test func aGenericValueContainingAClassIsStillAValue() throws {
    var evidence = NominalTypeEvidence()
    for symbol in ["$s1M1fyyAA3BoxCySiGF", "$s1M1gyyAA4WrapVyAA3RefCGF"] {
        evidence.collect(from: try demangleAsNode(symbol), options: .default)
    }
    let index = ClassTypeIndex().adding(evidence)
    #expect(index.isClass("M.Box<Swift.Int>"))
    #expect(index.isClass("M.Ref"))
    #expect(!index.isClass("M.Wrap<M.Ref>"))
    #expect(index.referenceOptionalInner("Swift.Optional<M.Wrap<M.Ref>>") == nil)
}

@Test func importedClassParametersRecoverWithoutAClassSymbolIfPresent() async throws {
    let path = "Fixtures/Sample/libImportedClassProbe.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    #expect(!machO.symbols.contains { $0.name == "_OBJC_CLASS_$_NSObject" })
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "ImportedClassProbe")
    }
    let streamed = try await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: machO) { $0 }
    }
    for name in ["withObject", "withOptionalObject"] {
        let function = try #require(functions.first { $0.displayName.hasPrefix("ImportedClassProbe.\(name)(") })
        let text = function.renderPseudo()
        #expect(text.contains("note(arg0") || text.contains("note((arg0"), Comment(rawValue: text))
        #expect(!text.contains("note(?)"), Comment(rawValue: text))
        let streaming = try #require(streamed.first { $0.startAddress == function.startAddress })
        #expect(streaming.renderPseudo() == text)
    }
    let point = try #require(functions.first { $0.displayName.hasPrefix("ImportedClassProbe.withPoint(") })
    #expect(point.renderPseudo().contains("note(?)"))
}

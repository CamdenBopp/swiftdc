import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A struct or enum of a library-evolution image is not read out of
/// registers: a resilient type is passed by address whatever its fields.
/// `afterPoint(_ p: Point, _ n: Int) { n &* 5 }` rendered `return (arg0.y +
/// (arg0.y << 2))`, and a caller passing the address of a temporary
/// rendered `afterColor(arg0, (arg0 + 1))` (`resilient.swift`, -O
/// -enable-library-evolution).
@Test func aResilientValueIsNotReadFromRegistersIfPresent() async throws {
    let path = "Fixtures/Sample/libResilient.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("RS.\(name)(") }, "no \(name)").renderStructured()
    }
    for name in ["afterPoint", "afterVec", "afterMixed", "afterColor", "afterOnly", "firstAfterOnly", "readPoint"] {
        let text = try structured(name)
        // Nothing is claimed about the value: no field of the pointer in
        // x0, and no formal read from a register the type did not take.
        #expect(text.contains("return ?") && !text.contains("arg"), Comment(rawValue: text))
    }
    let caller = try structured("callColor")
    #expect(caller.contains("RS.afterColor(?, ?)"), Comment(rawValue: caller))
    // A method's `self` is a pointer in x20 either way, and its formals
    // start at x0: these were right and stay right.
    #expect(try structured("Point.scaled").contains("return (arg0 * 11)"))
    #expect(try structured("Point.shifted").contains("return (self.x + arg0)"))
    #expect(try structured("Mixed.scaled").contains("return (arg0 * 19)"))
    // A getter's receiver is an address in x20. Tracked, it shows; not
    // traceable (`resilient_tail.s`), it is unknown, not absent, and not
    // the struct's words in x0 and x1 (`self: (?, ?)`).
    #expect(try structured("totalOfFirst").contains("RS.Point.total.getter(self: (arg0 + 32))"))
    let untraced = try #require(functions.first { $0.displayName == "_untraced_total" }).renderStructured()
    #expect(untraced.contains("RS.Point.total.getter(self: ?)"), Comment(rawValue: untraced))
    // Not resilient, in the same image: a `@frozen` enum has no case
    // descriptors and is its tag in x0, and an internal struct's
    // descriptor is not exported, so it is still its fields.
    #expect(try structured("afterFixed").contains("return (arg1 + 21)"))
    #expect(try structured("innerSum").contains("return (arg1 + arg0.q)"))
}

/// Each register-lowering question declines for a possibly resilient type,
/// and answers for the same layout when the flag is off: the shapes are
/// ones that would otherwise lower.
@Test func everyRegisterLoweringDeclinesAPossiblyResilientTypeIfPresent() throws {
    let path = "Fixtures/Sample/libResilient.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    // All three kinds are in this image: `enum case for RS.Color.red`, the
    // dispatch thunk of `Shape.area()`, and `Point.x`'s stored component.
    #expect(LibraryEvolutionEvidence.kinds(in: machO) == [.enumCase, .dispatchThunk, .storedPropertyDescriptor])
    let maps = try FieldMapBuilder.build(in: machO)
    let point = try #require(maps["RS.Point"]), vec = try #require(maps["RS.Vec"])
    let mixed = try #require(maps["RS.Mixed"])
    #expect(point.mayBeResilient && vec.mayBeResilient && mixed.mayBeResilient)
    #expect(point.wordIntegerFieldOffsetsInRegisters == nil)
    #expect(point.mixedScalarFieldBanksInRegisters == nil)
    #expect(vec.homogeneousFloatFieldOffsets == nil)
    #expect(mixed.mixedScalarFieldBanksInRegisters == nil)
    #expect(SwiftLowering.aggregateRegisters(of: "RS.Point", fieldMaps: maps) == nil)
    // Its layout in memory is unchanged: a value returned through x8 still
    // has its fields at the map's offsets.
    #expect(Disassembler.completeValueLayout(of: "RS.Point", fieldMaps: maps, classTypeIndex: ClassTypeIndex()) != nil)

    func loadable(_ map: FieldMap) -> FieldMap { var map = map; map.mayBeResilient = false; return map }
    #expect(loadable(point).wordIntegerFieldOffsetsInRegisters == [0, 8])
    #expect(loadable(vec).homogeneousFloatFieldOffsets == [0, 8])
    #expect(loadable(mixed).mixedScalarFieldBanksInRegisters?.map(\.isFloat) == [false, true])
    #expect(SwiftLowering.aggregateRegisters(of: "RS.Point", fieldMaps: maps.mapValues(loadable)) ?? (0, 0) == (2, 0))

    // A resilient enum is not claimed to take one register, or none; a tag
    // read from memory still has its case name.
    #expect(LibraryEvolutionEvidence.resilientEnums(in: machO) == ["RS.Color", "RS.Only"])
    let enums = EnumCaseIndex.build(in: machO)
    #expect(enums.isResilient("RS.Color") && enums.isResilient("RS.Only") && !enums.isResilient("RS.Fixed"))
    #expect(enums.caseName(ofEnum: "RS.Color", tag: 2) == "blue")
    #expect(SwiftLowering.of("RS.Color", enumCaseIndex: enums) == .unknown)
    #expect(SwiftLowering.of("RS.Only", enumCaseIndex: enums) == .unknown)
    #expect(SwiftLowering.of("RS.Fixed", enumCaseIndex: enums) == .oneInteger)

    // Only an exported struct may be resilient.
    let exported = LibraryEvolutionEvidence.exportedTypes(in: machO)
    #expect(exported.contains("RS.Point") && !exported.contains("RS.Inner"))
    #expect(try #require(maps["RS.Inner"]).mayBeResilient == false)
    #expect(maps["RS.Inner"]?.wordIntegerFieldOffsetsInRegisters == [0, 8])
}

/// Only what a resilient build alone emits is evidence. A plain module
/// has property descriptors too (the trivial zero word, or a computed
/// component for `public private(set) var`), and none is evidence.
@Test func aPlainImageShowsNoLibraryEvolutionEvidenceIfPresent() throws {
    #expect(LibraryEvolutionEvidence.isStoredComponent(0x0180_0000))   // struct field, offset 0
    #expect(LibraryEvolutionEvidence.isStoredComponent(0x0380_0010))   // class field, offset 0x10
    #expect(!LibraryEvolutionEvidence.isStoredComponent(0))            // trivial descriptor
    #expect(!LibraryEvolutionEvidence.isStoredComponent(0x0240_0000))  // computed component
    // `throwinggetter.swift`: a public struct with a public stored property,
    // compiled without library evolution.
    let path = "Fixtures/Sample/libThrowingGetter.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    #expect(!LibraryEvolutionEvidence.isPresent(in: machO))
    #expect(try FieldMapBuilder.build(in: machO)["TG.S"]?.mayBeResilient == false)
    // `droppedargs.swift`, plain, imports a standard-library dispatch thunk
    // (`dispatch thunk of Swift.BinaryInteger._lowWord.getter`): an import
    // says nothing about this image.
    let importing = "Fixtures/Sample/libDroppedArgs.dylib"
    guard FileManager.default.fileExists(atPath: importing) else { return }
    #expect(LibraryEvolutionEvidence.kinds(in: try BinaryLoader.load(path: importing)).isEmpty)
}

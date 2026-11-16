import Testing
import Foundation
@testable import SwiftDecompilerCore

/// The demangled-name parse is positional, and the positions differ between
/// methods and property accessors. Getting it wrong picks the *property* as the
/// type.
@Test func parsesSelfTypeFromDemangledName() {
    // Method: Module.Type.method
    #expect(Disassembler.selfTypeFromDemangledName("st.Box.get() -> Swift.Int") == "Box")
    // Property accessor: Module.Type.property.accessor — one level deeper.
    #expect(Disassembler.selfTypeFromDemangledName("lay.Dog.breed.getter : Swift.String") == "Dog")
    #expect(Disassembler.selfTypeFromDemangledName("lay.Dog.breed.setter : Swift.String") == "Dog")
    #expect(Disassembler.selfTypeFromDemangledName("lay.Dog.breed.modify : Swift.String") == "Dog")
    // Nested type.
    #expect(Disassembler.selfTypeFromDemangledName("m.Outer.Inner.go() -> ()") == "Inner")
    // A function-typed parameter's arrow is not the signature's: cut there,
    // the qualified parameter before it split into `apply(_: M` and `Other`.
    #expect(Disassembler.selfTypeFromDemangledName(
        "m.Holder.apply(_: m.Other, _: (Swift.Int) -> ()) -> ()") == "Holder")
}

/// x20 is not an instance in any of these. Naming `self.field` in them would
/// attach a nominal type's field layout to a pointer that is not that type.
@Test func refusesNonInstanceDemangledNames() {
    // A static entry point: x20 holds the metatype. This one was a real bug —
    // `swift_allocObject(self, 32, 7)` on an allocating init.
    #expect(Disassembler.selfTypeFromDemangledName("st.Box.__allocating_init() -> st.Box") == nil)
    #expect(Disassembler.selfTypeFromDemangledName("static st.Box.build() -> st.Box") == nil)
    #expect(Disassembler.selfTypeFromDemangledName("static lay.Cfg.shared.getter : lay.Cfg") == nil)
    // Not code with a receiver at all.
    #expect(Disassembler.selfTypeFromDemangledName("method descriptor for st.Box.get() -> Swift.Int") == nil)
    #expect(Disassembler.selfTypeFromDemangledName("variable initialization expression of lay.Dog.breed : Swift.String") == nil)
    #expect(Disassembler.selfTypeFromDemangledName("dispatch thunk of st.Box.get() -> Swift.Int") == nil)
    // A witness thunk's self is the conforming type, which this parse would not
    // find — so it must decline rather than answer with the protocol.
    #expect(Disassembler.selfTypeFromDemangledName("protocol witness for sample.Shape.describe() -> Swift.String in conformance sample.Circle") == nil)
    // A free function: the parse yields the module, which has no field map.
    #expect(Disassembler.selfTypeFromDemangledName("sample.run() -> ()") == "sample")
    #expect(Disassembler.selfTypeFromDemangledName("main") == nil)
    #expect(Disassembler.selfTypeFromDemangledName(nil) == nil)
}

/// An argument label must not trip the non-instance markers: the signature is
/// cut before they are checked.
@Test func signatureDoesNotTripNonInstanceMarkers() {
    // `(for:)` contains "for" — but not " for " once the signature is removed.
    #expect(Disassembler.selfTypeFromDemangledName("m.Cache.value(for: Swift.String) -> Swift.Int") == "Cache")
    // A return type mentioning a type must not be mined.
    #expect(Disassembler.selfTypeFromDemangledName("m.Factory.make() -> m.Widget") == "Factory")
}

/// The vtable index is authoritative when it has an entry — it is the only
/// source carrying `isInstance`. Consulting the symbol first is what produced
/// `swift_allocObject(self, …)` on a static allocating init.
@Test func vtableIndexOverridesTheSymbol() {
    let fieldMaps: [String: FieldMap] = [
        "Animal": FieldMap(typeName: "Animal", layout: .init(fields: [], size: 32, stride: 32, alignment: 8, extraInhabitantCount: 0)),
    ]
    let function = DisassembledFunction(
        symbol: "_$s6sample6AnimalC4nameACSS_tcfC",
        demangledName: "sample.Animal.init(name: Swift.String) -> sample.Animal",
        startAddress: 0x1000, instructions: [], source: .symbol
    )

    // Index says this address is a non-instance slot: refuse, despite the name
    // parsing cleanly to a type that does have a field map.
    let staticIndex = SelfTypeIndex(bindings: [
        0x1000: SelfBinding(selfTypeName: "Animal", kind: "init", isInstance: false,
                            source: .vtableSlot(type: "Animal", slot: 6)),
    ])
    #expect(Disassembler.selfType(of: function, selfIndex: staticIndex, fieldMaps: fieldMaps) == nil)

    // Index says instance: accept.
    let instanceIndex = SelfTypeIndex(bindings: [
        0x1000: SelfBinding(selfTypeName: "Animal", kind: "method", isInstance: true,
                            source: .vtableSlot(type: "Animal", slot: 0)),
    ])
    #expect(Disassembler.selfType(of: function, selfIndex: instanceIndex, fieldMaps: fieldMaps) == "Animal")

    // No index entry at all: fall back to the symbol. This is what covers
    // structs, whose methods are statically dispatched and have no vtable.
    let structFunction = DisassembledFunction(
        symbol: "_$s2st3CfgV4instSiyF", demangledName: "st.Cfg.inst() -> Swift.Int",
        startAddress: 0x2000, instructions: [], source: .symbol
    )
    let cfgMaps: [String: FieldMap] = [
        "Cfg": FieldMap(typeName: "Cfg", layout: .init(fields: [], size: 16, stride: 16, alignment: 8, extraInhabitantCount: 0)),
    ]
    // A qualified symbol cannot borrow a simple-only map from a different
    // module's Cfg. An exact descriptor key restores the known receiver.
    // (From the pre-merge stash 983aa25.)
    #expect(Disassembler.selfType(of: structFunction, selfIndex: SelfTypeIndex(bindings: [:]), fieldMaps: cfgMaps) == nil)
    #expect(Disassembler.selfType(
        of: structFunction, selfIndex: SelfTypeIndex(bindings: [:]),
        fieldMaps: cfgMaps.merging(["st.Cfg": cfgMaps["Cfg"]!]) { _, exact in exact }
    ) == "Cfg")
}

/// A class with no stored property has no field map, and a final method no
/// vtable slot, so `final class Node: NSObject`'s `join` seeded no self:
/// `enroll(?)` for `enroll(self)`. A symbol-named type the class index
/// proves a class takes self in x20 all the same; a struct of that name, a
/// class only by simple name, or a free function (its module) does not.
@Test func aSymbolNamedClassWithNoLayoutStillHasSelf() {
    let join = DisassembledFunction(
        symbol: "_$s14RetainRegister4NodeC4joinyS2iF",
        demangledName: "RetainRegister.Node.join(Swift.Int) -> Swift.Int",
        startAddress: 0x1000, instructions: [], source: .symbol)
    let none = SelfTypeIndex(bindings: [:])
    let classes = ClassTypeIndex(qualifiedClassNames: ["RetainRegister.Node"])
    #expect(Disassembler.selfType(of: join, selfIndex: none, fieldMaps: [:], classTypeIndex: classes) == "Node")
    #expect(Disassembler.selfType(of: join, selfIndex: none, fieldMaps: [:]) == nil)
    #expect(Disassembler.selfType(of: join, selfIndex: none, fieldMaps: [:],
                                  classTypeIndex: ClassTypeIndex(classNames: ["Node"])) == nil)
    let free = DisassembledFunction(
        symbol: "_$s14RetainRegister4codeSiyF", demangledName: "RetainRegister.code() -> Swift.Int",
        startAddress: 0x2000, instructions: [], source: .symbol)
    #expect(Disassembler.selfType(of: free, selfIndex: none, fieldMaps: [:],
                                  classTypeIndex: ClassTypeIndex(qualifiedClassNames: ["RetainRegister"])) == nil)
    // A name metadata gives a stripped body has no signature, so it cannot
    // say `static`: declined.
    let stripped = DisassembledFunction(
        symbol: "sub_1000", demangledName: "RetainRegister.Node.method",
        startAddress: 0x3000, instructions: [], source: .symbol)
    #expect(Disassembler.selfType(of: stripped, selfIndex: none, fieldMaps: [:], classTypeIndex: classes) == nil)
    // Each half alone: a metadata name with a signature on a stripped body,
    // and a Swift symbol whose name carries none.
    let strippedSigned = DisassembledFunction(
        symbol: "sub_4000", demangledName: "RetainRegister.Node.join(Swift.Int) -> Swift.Int",
        startAddress: 0x4000, instructions: [], source: .symbol)
    #expect(Disassembler.selfType(of: strippedSigned, selfIndex: none, fieldMaps: [:], classTypeIndex: classes) == nil)
    let unsigned = DisassembledFunction(
        symbol: "_$s14RetainRegister4NodeC4joinyS2iF", demangledName: "RetainRegister.Node.method",
        startAddress: 0x5000, instructions: [], source: .symbol)
    #expect(Disassembler.selfType(of: unsigned, selfIndex: none, fieldMaps: [:], classTypeIndex: classes) == nil)
    // A destructor has no signature but is never static.
    let deinitializer = DisassembledFunction(
        symbol: "_$s14RetainRegister4NodeCfD", demangledName: "RetainRegister.Node.__deallocating_deinit",
        startAddress: 0x6000, instructions: [], source: .symbol)
    #expect(Disassembler.selfType(of: deinitializer, selfIndex: none, fieldMaps: [:], classTypeIndex: classes) == "Node")
    // The destroying deinit (`fd`) takes self in x20 as well: `add x0, x20,
    // #0x10` addresses its first stored property at -Onone.
    let destroyer = DisassembledFunction(
        symbol: "_$s14RetainRegister4NodeCfd", demangledName: "RetainRegister.Node.deinit",
        startAddress: 0x7000, instructions: [], source: .symbol)
    #expect(Disassembler.selfType(of: destroyer, selfIndex: none, fieldMaps: [:], classTypeIndex: classes) == "Node")
    // The vtable index's "not an instance" still wins.
    let staticIndex = SelfTypeIndex(bindings: [
        0x1000: SelfBinding(selfTypeName: "Node", kind: "method", isInstance: false,
                            source: .vtableSlot(type: "Node", slot: 0)),
    ])
    #expect(Disassembler.selfType(of: join, selfIndex: staticIndex, fieldMaps: [:], classTypeIndex: classes) == nil)
}

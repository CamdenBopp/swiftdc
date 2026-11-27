import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A value-witness table's eight functions are in every table; getEnumTag,
/// destructiveProjectEnumData and destructiveInjectEnumTag follow at +0x58
/// only in an enum's (`EnumValueWitnessTable`, swift/include/swift/ABI/
/// Metadata.h). A call through one of those words is an enum witness only
/// when the table is an enum's, so its name needs the metadata's nominal
/// kind as well as the metadata passed back: a symbol whose mangling says
/// enum, or an accessor an enum descriptor of the image points at.
private let enumOnlyWitnesses = ["getEnumTag value witness for ", "destructiveProjectEnumData value witness for ",
                                 "destructiveInjectEnumTag value witness for "]

private func views(_ path: String) async throws -> [String: [String]]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    return Dictionary(functions.map { ($0.displayName, [$0.renderStructured(), $0.renderPseudo()]) },
                      uniquingKeysWith: { a, _ in a })
}

/// The mangling's nominal kind, for the two entities a call can load a
/// table through: `…ON` and `…OMa` are an enum's, `…V…` a struct's, `…C…`
/// a class's. The entity must be the one asked for, and anything else that
/// mentions an enum (its descriptor) is no metadata.
@Test func onlyAnEnumsMetadataSymbolsAreEnumEvidence() {
    for symbol in ["_$ss17FloatingPointSignON", "$ss17FloatingPointSignON", "_$sSiSgN"] {
        #expect(Disassembler.namesEnumMetadata(symbol, accessor: false), "\(symbol)")
        #expect(!Disassembler.namesEnumMetadata(symbol, accessor: true), "\(symbol)")
    }
    for symbol in ["_$ss17FloatingPointSignOMa", "_$sSqMa", "_$s12RemoteErrors0A5ErrorOMa", "_$s11EnumSlotKit6SignalOMa"] {
        #expect(Disassembler.namesEnumMetadata(symbol, accessor: true), "\(symbol)")
        #expect(!Disassembler.namesEnumMetadata(symbol, accessor: false), "\(symbol)")
    }
    for symbol in ["_$sSiN", "_$sSSN", "_$sSiMa", "_$ss23_ContiguousArrayStorageCMa", "_$s11EnumSlotKit5PlainVMa",
                   "_$s11EnumSlotKit4NodeCMa", "_$ss17FloatingPointSignOMn", "_puts", "_$s", ""] {
        #expect(!Disassembler.namesEnumMetadata(symbol, accessor: false), "\(symbol)")
        #expect(!Disassembler.namesEnumMetadata(symbol, accessor: true), "\(symbol)")
    }
}

/// enum_slot_evidence.s: metadata the loader binds, and metadata an
/// imported accessor returns, each passed back as the call's last operand.
/// Swift.FloatingPointSign is an enum and keeps all three names.
@Test func anEnumsOwnSlotsKeepTheirNamesIfPresent() async throws {
    guard let text = try await views("Fixtures/Sample/libEnumSlotEvidence.dylib") else { return }
    let expected = [
        "_esBoundEnumTag": "getEnumTag value witness for Swift.FloatingPointSign(",
        "_esAccessorEnumTag": "getEnumTag value witness for Swift.FloatingPointSign(",
        "_esAccessorEnumProject": "destructiveProjectEnumData value witness for Swift.FloatingPointSign(",
        "_esAccessorEnumInject": "destructiveInjectEnumTag value witness for Swift.FloatingPointSign(",
    ]
    for (name, call) in expected.sorted(by: { $0.key < $1.key }) {
        for view in try #require(text[name], "\(name)") {
            #expect(view.contains(call), Comment(rawValue: "\(name)\n\(view)"))
            #expect(!view.contains("unresolved call"), Comment(rawValue: "\(name)\n\(view)"))
        }
    }
}

/// The same loads and the same operand through a struct's or a class's
/// metadata: the word past the table is not a witness, so the call is to
/// an unknown function. Passing the metadata back does not make
/// `getEnumTag value witness for Swift.Int`.
@Test func theWordPastAStructsOrClasssTableIsNoEnumWitnessIfPresent() async throws {
    guard let text = try await views("Fixtures/Sample/libEnumSlotEvidence.dylib") else { return }
    for name in ["_esBoundStructTag", "_esBoundStructProject", "_esAccessorStructTag", "_esAccessorClassTag",
                 "_esAccessorClassInject"] {
        for view in try #require(text[name], "\(name)") {
            #expect(!view.contains(" value witness for "), Comment(rawValue: "\(name)\n\(view)"))
            #expect(view.contains("unresolved call"), Comment(rawValue: "\(name)\n\(view)"))
        }
    }
    // The common slots are in every table: the struct's destroy is named.
    for view in try #require(text["_esBoundStructDestroy"]) {
        #expect(view.contains("destroy value witness for Swift.Int("), Comment(rawValue: view))
    }
}

/// An enum's metadata symbol bound into a slot the program can rewrite
/// (`__DATA,__data`) proves nothing about what the slot holds at the call.
@Test func anEnumBoundIntoAWritableSlotIsNoEvidenceIfPresent() async throws {
    guard let text = try await views("Fixtures/Sample/libEnumSlotEvidence.dylib") else { return }
    for view in try #require(text["_esWritableSlotEnumTag"]) {
        #expect(!view.contains(" value witness for "), Comment(rawValue: view))
        #expect(view.contains("unresolved call"), Comment(rawValue: view))
    }
}

/// The compiler's own enum witness calls, on a resilient enum of another
/// module (resilienttypederror.swift at -O and -Osize: `RemoteError.failed`
/// is injected before the throw). Its metadata comes from the import
/// `$s12RemoteErrors0A5ErrorOMa`, an enum's accessor.
@Test(arguments: ["libResilientTypedError.dylib", "libResilientTypedError.Osize.dylib"])
func aResilientEnumsInjectedTagKeepsItsNameIfPresent(image: String) async throws {
    guard let text = try await views("Fixtures/Sample/\(image)") else { return }
    let all = text.values.map { $0[0] }.joined(separator: "\n")
    #expect(all.contains("destructiveInjectEnumTag value witness for RemoteErrors.RemoteError("), Comment(rawValue: all))
}

/// enumslotclient.swift. `classify` switches over a resilient `Signal`,
/// which the compiler does through getEnumTag and
/// destructiveProjectEnumData on the metadata `type metadata accessor for
/// EnumSlotKit.Signal` returns; those names stay. The source's own calls of
/// the word at +0x58 go through Signal's table, where it is getEnumTag,
/// and through Plain's (a struct), Node's (a class) and a class-constrained
/// parameter's, where it is no witness. So every enum-only name in the
/// image is Signal's, at both levels and in both views.
///
/// At -O the helper is inlined and each caller holds the loads. At -Onone
/// the loads are calls to `UnsafeRawPointer.load` inside the helper, whose
/// call is unresolved for every type, and `level` calls
/// destructiveInjectEnumTag (at -O that call is a tail `br`).
@Test(arguments: ["libEnumSlotClient.dylib", "libEnumSlotClient.Onone.dylib"])
func onlyTheEnumInAClientKeepsEnumWitnessNamesIfPresent(image: String) async throws {
    guard let text = try await views("Fixtures/Sample/\(image)") else { return }
    let optimized = !image.contains("Onone")
    func function(_ name: String) throws -> [String] {
        let key = try #require(text.keys.sorted().first { $0.hasPrefix("EnumSlotClient.\(name)") }, "\(name)")
        return try #require(text[key])
    }
    for (name, rendered) in text.sorted(by: { $0.key < $1.key }) {
        for view in rendered {
            for witness in enumOnlyWitnesses {
                for piece in view.components(separatedBy: witness).dropFirst() {
                    #expect(piece.hasPrefix("EnumSlotKit.Signal("), Comment(rawValue: "\(name)\n\(view)"))
                }
            }
        }
    }
    for view in try function("classify(") {
        #expect(view.contains("getEnumTag value witness for EnumSlotKit.Signal("), Comment(rawValue: view))
        #expect(view.contains("destructiveProjectEnumData value witness for EnumSlotKit.Signal("), Comment(rawValue: view))
    }
    if optimized {
        for view in try function("enumSlot(") {
            #expect(view.contains("getEnumTag value witness for EnumSlotKit.Signal(arg0)"), Comment(rawValue: view))
        }
        for name in ["structSlot(", "nodeSlot(", "classSlot<"] {
            for view in try function(name) {
                #expect(view.contains("unresolved call"), Comment(rawValue: "\(name)\n\(view)"))
                #expect(!view.contains(" value witness for "), Comment(rawValue: "\(name)\n\(view)"))
            }
        }
    } else {
        for view in try function("level(") {
            #expect(view.contains("destructiveInjectEnumTag value witness for EnumSlotKit.Signal("), Comment(rawValue: view))
        }
        for view in try function("callWordPastCommonTable(") {
            #expect(view.contains("unresolved call"), Comment(rawValue: view))
        }
    }
}

/// An enum descriptor's accessor pointer is the image's own evidence, with
/// or without symbols (resilient.swift: Color and Only are enums, Point a
/// struct).
@Test func aLocalEnumsAccessorIsFoundFromItsDescriptorIfPresent() async throws {
    let path = "Fixtures/Sample/libResilient.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func accessor(_ type: String) throws -> UInt64 {
        try #require(functions.first { $0.displayName == "type metadata accessor for RS.\(type)" }, "\(type)").startAddress
    }
    let enums = MetadataSymbolizer.enumAccessorAddresses(in: try BinaryLoader.load(path: path))
    #expect(try enums.contains(accessor("Color")))
    #expect(try enums.contains(accessor("Only")))
    #expect(try !enums.contains(accessor("Point")))
}

/// `bl accessor; mov x1, x0; ldur x8, [x0, #-8]; ldr x8, [x8, #slot]; blr
/// x8` against libResilient's own accessors: the call returns the metadata,
/// which is passed back as the last operand of getEnumTag (value, T).
/// Through Color's accessor (an enum descriptor's) the word at +0x58 is
/// getEnumTag; through Point's (a struct's) it is not a witness. +0x8 is
/// destroy in both.
@Test func aLocalAccessorNamesEnumSlotsOnlyForAnEnumIfPresent() async throws {
    let path = "Fixtures/Sample/libResilient.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    try await withStableDependencies {
        let listed = try await Disassembler().disassemble(path: path)
        let image = try BinaryLoader.load(path: path)
        let engine = try #require(CapstoneEngine())
        let start: UInt64 = 0x0100_0000
        func render(type: String, slot: UInt32) throws -> String {
            let callee = "type metadata accessor for RS.\(type)"
            let target = try #require(listed.first { $0.displayName == callee }, "\(type)").startAddress
            let resolver = Disassembler.ReferenceResolver(names: [target: callee], stringRanges: [],
                machO: image, demangleSymbol: { _ in nil })
            let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [target],
                objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:],
                selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(), enumCaseIndex: EnumCaseIndex(),
                payloadEnumIndex: PayloadEnumCaseIndex(), classTypeIndex: ClassTypeIndex(),
                classParameterFields: ClassParameterFieldIndex(), asyncIndex: .empty, asyncChainSlots: [:])
            // The accessor lies below `start`: a backward `bl` from +8.
            let delta = UInt32(truncatingIfNeeded: (Int64(target) - Int64(start + 8)) / 4) & 0x03ff_ffff
            let words: [UInt32] = [
                0xa9bf_7bfd,                    // stp x29, x30, [sp, #-16]!
                0x9100_03fd,                    // mov x29, sp
                0x9400_0000 | delta,            // bl accessor
                0xaa00_03e1,                    // mov x1, x0
                0xf85f_8008,                    // ldur x8, [x0, #-8]
                0xf940_0108 | ((slot / 8) << 10), // ldr x8, [x8, #slot]
                0xd63f_0100,                    // blr x8
                0xa8c1_7bfd,                    // ldp x29, x30, [sp], #16
                0xd65f_03c0,                    // ret
            ]
            let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
            let instructions = engine.disassemble(bytes, address: start).map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail,
                    callee: .kept($0.branchTarget == target ? callee : nil))
            }
            #expect(instructions.count == words.count && instructions[2].branchTarget == target)
            let function = DisassembledFunction(symbol: "_slotProbe", demangledName: nil,
                startAddress: start, instructions: instructions, source: .symbol)
            return Disassembler().analyzeFunction(function, context: context).renderStructured()
        }
        let enumTag = try render(type: "Color", slot: 0x58)
        #expect(enumTag.contains("getEnumTag value witness for RS.Color("), Comment(rawValue: enumTag))
        let structWord = try render(type: "Point", slot: 0x58)
        #expect(!structWord.contains(" value witness for "), Comment(rawValue: structWord))
        for type in ["Color", "Point"] {
            let destroy = try render(type: type, slot: 0x8)
            #expect(destroy.contains("destroy value witness for RS.\(type)("), Comment(rawValue: destroy))
        }
    }
}

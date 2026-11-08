import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A class parameter of a free function is one pointer, and `FieldMap` has the
/// offsets behind it: `h.v + 1` reads `(arg0.v + 1)`, and everything that is
/// not provably that object at that offset and width stays `?`.

private func structured(_ path: String) async throws -> [(name: String, text: String)]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    return functions.map { ($0.displayName, $0.renderStructured()) }
}

/// The body of `Module.name(…)` or `Module.name<A>(…)`.
private func body(_ rendered: [(name: String, text: String)], _ name: String) throws -> String {
    try #require(rendered.first { $0.name.hasPrefix("\(name)(") || $0.name.hasPrefix("\(name)<") }, "\(name) missing").text
}

@Test func aClassParametersFieldNamesAtEveryOptimizationLevelIfPresent() async throws {
    for path in ["Fixtures/Sample/libClassParamSmall.dylib", "Fixtures/Sample/libClassParamSmall.opt.dylib",
                 "Fixtures/Sample/libClassParamSmall.size.dylib"] {
        guard let rendered = try await structured(path) else { continue }
        let text = try body(rendered, "ClassParamSmall.readHolder")
        #expect(text.contains("return (arg0.v + 1)"), Comment(rawValue: "\(path)\n\(text)"))
    }
}

@Test func aLoadNamesAFieldOnlyAtItsOwnWidthIfPresent() async throws {
    for path in ["Fixtures/Sample/libClassParam.dylib", "Fixtures/Sample/libClassParam.opt.dylib"] {
        guard let rendered = try await structured(path) else { continue }
        for (name, expected) in [
            ("readHolder", "(arg0.v + 1)"), ("afterString", "(arg1.v + 2)"), ("readWithGeneric", "(arg0.v + 8)"),
            ("twoReads", "(arg0.v + arg1.v)"), ("branchOnField", "(arg0.v > 3)"), ("readOwn", "(arg0.b + 11)"),
            ("readShared", "(arg0.a + 9)"), ("readDup", "(arg0.a + 10)"), ("readOtherDup", "(arg0.z + 17)"),
            ("readFlag", "arg0.flag"), ("readSmall", "arg0.small"), ("readTiny", "arg0.tiny"),
            ("readHalf", "arg0.half"), ("readFloat", "arg0.f"), ("readDouble", "arg0.d"),
            ("readNext", "arg0.next"),
        ] {
            let text = try body(rendered, "ClassParam.\(name)")
            #expect(text.contains(expected), Comment(rawValue: "\(path)\n\(text)"))
        }
        // A sign-extending load keeps the extension: the register is not the
        // field's bits alone.
        let wide = try body(rendered, "ClassParam.readSmallWide")
        #expect(wide.contains("((arg0.small << 32) >>ˢ 32)"), Comment(rawValue: wide))
        // Two words of a wide field, one word of a two-word value, a byte of
        // an Int: each is part of a field, not the field.
        for name in ["readString", "readOptionalInt", "readPairFirst"] {
            let text = try body(rendered, "ClassParam.\(name)")
            #expect(!text.contains("arg0."), Comment(rawValue: "\(path)\n\(text)"))
        }
        let low = try body(rendered, "ClassParam.lowByte")
        #expect(!low.contains("return arg0.big"), Comment(rawValue: low))
    }
    guard let rendered = try await structured("Fixtures/Sample/libClassParam.opt.dylib") else { return }
    let low = try body(rendered, "ClassParam.lowByte")
    #expect(low.contains("return ?"), Comment(rawValue: low))
    let pair = try body(rendered, "ClassParam.quietPair")
    #expect(pair.contains("(arg0.w * arg0.v)"), Comment(rawValue: pair))
}

@Test func aValueReadFromAClassParametersFieldIsASnapshotIfPresent() async throws {
    for path in ["Fixtures/Sample/libClassParam.dylib", "Fixtures/Sample/libClassParam.opt.dylib"] {
        guard let rendered = try await structured(path) else { continue }
        for name in ["snapshotAcrossStore", "snapshotAcrossAliasStore", "snapshotAcrossCall", "loopBump"] {
            let text = try body(rendered, "ClassParam.\(name)")
            #expect(text.contains("return ?"), Comment(rawValue: "\(path)\n\(text)"))
        }
        let current = try body(rendered, "ClassParam.increment")
        #expect(current.contains("return arg0.v"), Comment(rawValue: "\(path)\n\(current)"))
    }
}

@Test func onlyAFreeFunctionsBareClassParameterNamesAFieldIfPresent() async throws {
    for path in ["Fixtures/Sample/libClassParam.dylib", "Fixtures/Sample/libClassParam.opt.dylib",
                 "Fixtures/Sample/libClassParam.size.dylib"] {
        guard let rendered = try await structured(path) else { continue }
        for name in ["optionalParam", "inoutRead", "readBoxHead", "readBoxTail", "readBoxGeneric", "readInherited"] {
            let text = try body(rendered, "ClassParam.\(name)")
            #expect(!text.contains("arg0."), Comment(rawValue: "\(path)\n\(text)"))
        }
        // Everything that is no free function keeps what it rendered.
        for function in rendered where function.name.contains("take(")
            || function.name.contains("Namespace.read(") || function.name.contains("closure #")
            || function.name.contains("asyncRead(") {
            #expect(!function.text.contains("arg0.v"), Comment(rawValue: "\(path)\n\(function.text)"))
        }
    }
}

@Test func aClassLaidOutElsewhereNamesNoFieldIfPresent() async throws {
    if let kit = try await structured("Fixtures/Sample/libClassParamKit.dylib") {
        let text = try body(kit, "ClassParamKit.readKit")
        #expect(text.contains("return ?"), Comment(rawValue: text))
    }
    guard let client = try await structured("Fixtures/Sample/libClassParamClient.dylib") else { return }
    for name in ["readOver", "readForeignTwin"] {
        let text = try body(client, "ClassParamClient.\(name)")
        #expect(text.contains("return ?"), Comment(rawValue: text))
    }
    let own = try body(client, "ClassParamClient.readOwnTwin")
    #expect(own.contains("(arg0.other + 3)"), Comment(rawValue: own))
    let pair = try body(client, "ClassParamClient.readOwnPair")
    #expect(pair.contains("(arg0.mine + 6)"), Comment(rawValue: pair))
}

// MARK: - The tracer, on exact instructions

private let ret: UInt32 = 0xD65F_03C0
private let field = AbstractValue.argumentField(argument: 0, offset: 0x10)

/// What x0 holds at the last instruction, a `ret`, with x0 and x1 the first
/// two arguments.
private func exit(_ words: [UInt32], fields: [Int: [Int: Int]] = [0: [0x10: 8]]) throws -> AbstractValue? {
    let engine = try #require(CapstoneEngine())
    let bytes = (words + [ret]).flatMap { word in (0 ..< 4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    let function = DisassembledFunction(
        symbol: "probe", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map { insn in
            Instruction(address: insn.address, text: insn.text, annotation: nil, controlFlow: insn.controlFlow,
                        branchTarget: insn.controlFlow == .call ? nil : insn.branchTarget, detail: insn.detail)
        }, source: .address)
    var tracer = ValueTracer()
    tracer.argumentObjectFields = fields
    return tracer.analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
        .exitValues[0x1000 + UInt64(words.count) * 4]
}

@Test func aFieldLoadMustMatchTheFieldExactly() throws {
    #expect(try exit([0xF940_0800]) == field)                                // ldr x0, [x0, #0x10]
    #expect(try exit([0x3940_4000]) == nil)                                  // ldrb w0: one byte of it
    #expect(try exit([0xB940_1000]) == nil)                                  // ldr w0: half of it
    #expect(try exit([0xB940_1000], fields: [0: [0x10: 4]]) == field)        // ldr w0 of a four-byte field, unmasked
    #expect(try exit([0x3940_4000], fields: [0: [0x10: 1]]) == field)        // ldrb w0 of a one-byte field
    let extended = try exit([0xB980_1000], fields: [0: [0x10: 4]])           // ldrsw x0
    #expect(extended != nil && extended != field)
    // ldr x8, [x0], #0x10 and ldr x0, [x0, x1]: neither is a constant offset
    // from the object, even where one would land on a field.
    #expect(try exit([0xF840_0408, 0xAA08_03E0], fields: [0: [0: 8]]) == nil)
    #expect(try exit([0xF861_6800], fields: [0: [0: 8]]) == nil)
    #expect(try exit([0xF940_0820]) == nil)                                  // ldr x0, [x1, #0x10]: not a class argument
    #expect(try exit([0xF940_0820], fields: [1: [0x10: 8]]) == .argumentField(argument: 1, offset: 0x10))
    #expect(try exit([0x9100_2008, 0xF940_0500]) == field)                   // add x8, x0, #8; ldr x0, [x8, #8]
}

@Test func eachRegisterOfAPairLoadIsItsOwnFieldLoad() throws {
    // ldp x0, x1, [x0, #0x10]; mov x0, x1: the base is the destination, and
    // the second word must still be read from the argument.
    let pair: [UInt32] = [0xA941_0400, 0xAA01_03E0]
    #expect(try exit(pair, fields: [0: [0x10: 8, 0x18: 8]]) == .argumentField(argument: 0, offset: 0x18))
    #expect(try exit(pair) == nil)
    #expect(try exit([0xA941_0400], fields: [0: [0x10: 8, 0x18: 8]]) == field)
}

@Test func aParameterOverwrittenInTheBodyReadsNoField() throws {
    #expect(try exit([0xAA01_03E0, 0xF940_0800]) == nil)                     // mov x0, x1; ldr x0, [x0, #0x10]
    // L: ldr x8, [x0, #0x10]; mov x0, x8; cbnz x8, L: x0 is the argument
    // only on the first pass.
    #expect(try exit([0xF940_0808, 0xAA08_03E0, 0xB5FF_FFC8]) == nil)
}

@Test func anyWriteOutsideTheFrameEndsAFieldSnapshot() throws {
    let load: UInt32 = 0xF940_0808, result: UInt32 = 0xAA08_03E0             // ldr x8, [x0, #0x10]; mov x0, x8
    let enter: UInt32 = 0xD100_43FF, leave: UInt32 = 0x9100_43FF             // sub sp / add sp, #0x10
    #expect(try exit([load, result]) == field)
    #expect(try exit([load, 0xF900_003F, result]) == nil)                    // str xzr, [x1]: may be the same object
    #expect(try exit([load, 0xF829_802A, result]) == nil)                    // swp x9, x10, [x1]
    #expect(try exit([load, 0xC89F_FC29, result]) == nil)                    // stlr x9, [x1]
    #expect(try exit([enter, load, 0xF900_03FF, result, leave]) == field)    // str xzr, [sp]: the frame is no object
    // A spill keeps the field's name only until the same write.
    let spill: UInt32 = 0xF900_03E8, reload: UInt32 = 0xF940_03E0            // str x8, [sp]; ldr x0, [sp]
    #expect(try exit([enter, load, spill, reload, leave]) == field)
    #expect(try exit([enter, load, spill, 0xF900_003F, reload, leave]) == nil)
    // ldr x19, [x0, #0x10]; bl; mov x0, x19: an unknown call may write it.
    #expect(try exit([0xF940_0813, 0x9400_0010, 0xAA13_03E0]) == nil)
}

@Test func aStoredRegisterHoldsTheFieldsNewValueOnlyAtItsWidth() throws {
    let load: UInt32 = 0xF940_0808, bump: UInt32 = 0x9100_0508, result: UInt32 = 0xAA08_03E0
    #expect(try exit([load, bump, 0xF900_0808, result]) == field)            // str x8, [x0, #0x10]
    #expect(try exit([load, bump, 0xB900_1008, result]) == nil)              // str w8: part of the field
    #expect(try exit([0xD280_0028, 0xF900_0808, result]) == .immediate(1))   // a constant stays a constant
    #expect(try exit([0xF900_0801, 0xAA01_03E0]) == .argument(1))            // an argument stays the argument
}

// MARK: - What goes in the index

private let holderMap = FieldMap(typeName: "Holder", instanceSize: 24,
                                 fields: [(offset: 0x10, bytes: 8, name: "v", typeEncoding: "Si")])

@Test func theIndexAnswersOnlyForTheExactQualifiedClass() {
    let classes = ClassTypeIndex(classNames: ["Holder"], qualifiedClassNames: ["F.Holder"])
    let maps = ["Holder": holderMap, "F.Holder": holderMap]
    let index = ClassParameterFieldIndex(fieldMaps: maps, classTypeIndex: classes)
    #expect(index.fieldMap(ofParameterType: "F.Holder") != nil)
    for other in ["Holder", "G.Holder", "inout F.Holder", "Swift.Optional<F.Holder>", "F.Holder.Type"] {
        #expect(index.fieldMap(ofParameterType: other) == nil, Comment(rawValue: other))
    }
}

@Test func theQualifiedKeyAloneDecidesASharedSimpleName() {
    let maps = ["Holder": holderMap, "F.Holder": holderMap]
    // The simple name is also a value type's: `adding` took it out.
    let shared = ClassTypeIndex(classNames: [], qualifiedClassNames: ["F.Holder"])
    #expect(ClassParameterFieldIndex(fieldMaps: maps, classTypeIndex: shared)
        .fieldMap(ofParameterType: "F.Holder") != nil)
    // The simple key was dropped as a collision.
    let classes = ClassTypeIndex(classNames: ["Holder"], qualifiedClassNames: ["F.Holder"])
    #expect(ClassParameterFieldIndex(fieldMaps: ["F.Holder": holderMap], classTypeIndex: classes)
        .fieldMap(ofParameterType: "F.Holder") != nil)
}

@Test func theIndexDeclinesADoubtfulClass() {
    let maps = ["Holder": holderMap, "F.Holder": holderMap]
    let classes = ClassTypeIndex(classNames: ["Holder"], qualifiedClassNames: ["F.Holder"])
    // No proof it is a class at all.
    let struct_ = ClassTypeIndex(classNames: ["Holder"], qualifiedNonClassNames: ["F.Holder"])
    #expect(ClassParameterFieldIndex(fieldMaps: maps, classTypeIndex: struct_)
        .fieldMap(ofParameterType: "F.Holder") == nil)
    #expect(ClassParameterFieldIndex(fieldMaps: maps, classTypeIndex: classes, runtimeLaidOut: ["F.Holder"])
        .fieldMap(ofParameterType: "F.Holder") == nil)
}

@Test func onlyAFreeFunctionsSignatureGivesClassArgumentMaps() {
    let classes = ClassTypeIndex(classNames: ["Holder"], qualifiedClassNames: ["F.Holder"])
    let index = ClassParameterFieldIndex(fieldMaps: ["Holder": holderMap, "F.Holder": holderMap], classTypeIndex: classes)
    func arguments(_ name: String) -> [Int] {
        let function = DisassembledFunction(symbol: "$s1F", demangledName: name, startAddress: 0x1000,
                                            instructions: [], source: .address)
        return Disassembler.classArgumentFieldMaps(of: function, scalarArguments: ["x0": 0, "x1": 1], index: index)
            .keys.sorted()
    }
    #expect(arguments("F.read(F.Holder) -> Swift.Int") == [0])
    #expect(arguments("F.read(Swift.Int, F.Holder) -> Swift.Int") == [1])
    #expect(arguments("F.read<A>(F.Holder, A) -> Swift.Int") == [0])
    #expect(arguments("F.read(__owned F.Holder) -> Swift.Int") == [0])
    #expect(arguments("F.Outer.read(F.Holder) -> Swift.Int").isEmpty)
    #expect(arguments("static F.Outer.read(F.Holder) -> Swift.Int").isEmpty)
    #expect(arguments("closure #1 (F.Holder) -> Swift.Int in F.make() -> ()").isEmpty)
    #expect(arguments("function signature specialization <Arg[0] = Dead> of F.read(F.Holder) -> Swift.Int").isEmpty)
    #expect(arguments("F.read(F.Holder) async -> Swift.Int").isEmpty)
}

@Test func onlyAFieldOneRegisterHoldsHasALoadWidth() {
    let map = FieldMap(typeName: "W", instanceSize: 0x38, fields: [
        (offset: 0x10, bytes: 1, name: "flag", typeEncoding: "Sb"),
        (offset: 0x18, bytes: 8, name: "big", typeEncoding: "Si"),
        (offset: 0x20, bytes: 16, name: "s", typeEncoding: "SS"),
        (offset: 0x30, bytes: 8, name: "next", typeEncoding: "Si"),
    ])
    #expect(Disassembler.wholeWordFieldWidths(of: map) == [0x10: 1, 0x18: 8, 0x30: 8])
}

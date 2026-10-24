import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func decodesObjCIvarStorageLayouts() {
    #expect(ObjCTypeLayoutDecoder.layout(of: "@\"NSString\"") == .init(size: 8, alignment: 8))
    #expect(ObjCTypeLayoutDecoder.layout(of: "q") == .init(size: 8, alignment: 8))
    #expect(ObjCTypeLayoutDecoder.layout(of: "[3i]") == .init(size: 12, alignment: 4))
    #expect(
        ObjCTypeLayoutDecoder.layout(of: "{CGRect={CGPoint=dd}{CGSize=dd}}")
            == .init(size: 32, alignment: 8)
    )
    #expect(ObjCTypeLayoutDecoder.layout(of: "(Value=iq)") == .init(size: 8, alignment: 8))
    #expect(ObjCTypeLayoutDecoder.layout(of: "?") == nil)
}

/// A pointer to an empty struct inside a struct left the empty struct's
/// `}` unconsumed, so it closed the outer struct early: `{S=^{Opaque=}q}`
/// measured 8 bytes, not 16, and an ivar of that type claimed half its
/// bytes.
@Test func decodesAPointerToAnEmptyStructInsideAStruct() {
    #expect(ObjCTypeLayoutDecoder.layout(of: "{S=^{Opaque=}q}") == .init(size: 16, alignment: 8))
    #expect(ObjCTypeLayoutDecoder.layout(of: "{S=^{Opaque=}c^{Other=}}") == .init(size: 24, alignment: 8))
    #expect(ObjCTypeLayoutDecoder.layout(of: "^{Opaque=}") == .init(size: 8, alignment: 8))
    #expect(ObjCTypeLayoutDecoder.layout(of: "{Opaque=}") == nil)
}

/// `l` and `L` measured 8 bytes, where the runtime's NSGetSizeAndAlignment
/// treats them as 32 bits on 64-bit platforms (LP64's `long` encodes as
/// `q`), so an `l` ivar claimed four bytes of the next one.
@Test func decodesLAsThirtyTwoBits() {
    #expect(ObjCTypeLayoutDecoder.layout(of: "l") == .init(size: 4, alignment: 4))
    #expect(ObjCTypeLayoutDecoder.layout(of: "L") == .init(size: 4, alignment: 4))
    #expect(ObjCTypeLayoutDecoder.layout(of: "{T=lL}") == .init(size: 8, alignment: 4))
    #expect(ObjCTypeLayoutDecoder.layout(of: "q") == .init(size: 8, alignment: 8))
}

/// A size, count or width in a corrupt encoding can overflow `Int`. Each of
/// these trapped (arithmetic overflow) in one decoder step; now the whole
/// encoding has no layout, including a pointer whose pointee overflowed.
@Test func declinesObjCTypeLayoutsWhoseSizeOverflows() {
    let nines = String(repeating: "9", count: 25)
    for encoding in [
        "[\(nines)c]",                    // the count's digits
        "b9223372036854775807",            // a bitfield's rounding up to bytes
        "[4611686018427387904q]",          // count times element size
        "j[4611686018427387904c]",         // a complex type's two halves
        "{x=[9223372036854775806c]q}",     // aligning the next field
        "{x=[9223372036854775807c]c}",     // adding the next field
        "^[\(nines)c]",                   // a pointer to any of them
    ] {
        #expect(ObjCTypeLayoutDecoder.layout(of: encoding) == nil, "\(encoding)")
    }
    // The largest size that does not overflow still decodes.
    #expect(ObjCTypeLayoutDecoder.layout(of: "[9223372036854775807c]") == .init(size: .max, alignment: 1))
}

/// Each nesting level is a recursive call. A corrupt encoding nested 2,000
/// deep overflowed the stack (EXC_BAD_ACCESS); past the bound it declines.
@Test func declinesObjCTypeLayoutsNestedPastTheBound() {
    let bound = ObjCTypeLayoutDecoder.maximumNestingDepth
    func pointers(_ levels: Int) -> String { String(repeating: "^", count: levels - 1) + "c" }
    func arrays(_ levels: Int) -> String {
        String(repeating: "[1", count: levels - 1) + "c" + String(repeating: "]", count: levels - 1)
    }
    #expect(ObjCTypeLayoutDecoder.layout(of: pointers(bound)) == .init(size: 8, alignment: 8))
    #expect(ObjCTypeLayoutDecoder.layout(of: arrays(bound)) == .init(size: 1, alignment: 1))
    #expect(ObjCTypeLayoutDecoder.layout(of: pointers(bound + 1)) == nil)
    #expect(ObjCTypeLayoutDecoder.layout(of: arrays(bound + 1)) == nil)
    #expect(ObjCTypeLayoutDecoder.layout(of: pointers(2_000)) == nil)
    #expect(ObjCTypeLayoutDecoder.layout(of: arrays(2_000)) == nil)
}

/// An ivar whose decoded size is near `Int.max` lies past the instance; the
/// bound check `offset + bytes <= instanceSize` itself overflowed (trap).
@Test func dropsAnIvarFieldLargerThanTheInstance() {
    let map = FieldMap(
        typeName: "Corrupt", instanceSize: 16,
        fields: [(offset: 8, bytes: .max, name: "_huge", typeEncoding: "[9223372036854775807c]"),
                 (offset: 0, bytes: 8, name: "isa", typeEncoding: "#")]
    )
    #expect(map.fields.map(\.name) == ["isa"])
}

/// End to end, from the file: `disasm` on a copy of the fixture whose ivar
/// type string (`SDNonselfCaller._target`, the last string in
/// `__objc_methtype`) is overwritten in place. Its `ivar_t` still points into
/// `__objc_methtype`, so the preflight accepts the file; a payload longer
/// than the original runs over `__cstring` and `__unwind_info` into the
/// segment's zero padding. Every payload trapped or overflowed the stack.
@Test func corruptIvarTypeEncodingsDeclineTheirFieldIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCNonselfOutgoing.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let original = try Data(contentsOf: URL(fileURLWithPath: path))
    let target = Data(#"@"SDNonselfTarget""#.utf8) + Data([0])
    guard let found = original.range(of: target),
          original.range(of: target, in: found.upperBound..<original.endIndex) == nil
    else { Issue.record("fixture no longer holds one `_target` ivar type string"); return }

    func ivarFieldNames(_ url: URL) throws -> [String]? {
        let index = ObjCMetadataIndex.build(in: try BinaryLoader.load(path: url.path))
        return index.fieldMaps["SDNonselfCaller"]?.fields.map(\.name)
    }
    #expect(try ivarFieldNames(URL(fileURLWithPath: path)) == ["_target"])

    let payloads = [
        "[" + String(repeating: "9", count: 25) + "c]",
        "[4611686018427387904q]",
        "[9223372036854775807c]",
        String(repeating: "^", count: 2_000) + "c",
    ]
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-ivar-type-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for (number, payload) in payloads.enumerated() {
        let bytes = Data(payload.utf8) + Data([0])
        let start = found.lowerBound
        // Only the original string, the two small sections after it and
        // zero padding are overwritten.
        let end = start + bytes.count, padding = start + 0x100
        guard end <= original.count, end <= padding || original[padding..<end].allSatisfy({ $0 == 0 })
        else { Issue.record("fixture layout changed: no zero padding after `_target`'s type"); return }
        var corrupt = original
        corrupt.replaceSubrange(start..<(start + bytes.count), with: bytes)
        let url = directory.appendingPathComponent("corrupt-\(number).dylib")
        try corrupt.write(to: url)

        let functions = try await withStableDependencies {
            try await Disassembler(preset: .simplified).disassemble(path: url.path)
        }
        #expect(!functions.isEmpty, "\(payload.prefix(40))")
        #expect(try ivarFieldNames(url)?.contains("_target") != true, "\(payload.prefix(40))")
    }
}

/// Objective-C method records carry their IMPs, so names and signatures survive
/// nlist stripping independently of Swift metadata and LC_FUNCTION_STARTS.
@Test func objcMethodBindingsSurviveStripping() throws {
    let release = "Fixtures/Sample/libSample.dylib"
    let stripped = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: release),
          FileManager.default.fileExists(atPath: stripped)
    else { return }

    let full = ObjCMetadataIndex.build(in: try BinaryLoader.load(path: release))
    let bare = ObjCMetadataIndex.build(in: try BinaryLoader.load(path: stripped))
    #expect(full.count > 0)

    let fullMethods = Dictionary(
        full.all.map { ($0.binding.displayName, $0.address) },
        uniquingKeysWith: { first, _ in first }
    )
    let bareMethods = Dictionary(
        bare.all.map { ($0.binding.displayName, $0.address) },
        uniquingKeysWith: { first, _ in first }
    )
    #expect(bareMethods["-[SDWidget ping]"] == fullMethods["-[SDWidget ping]"])
    if fullMethods["-[SDObjCCounter incrementBy:]"] != nil {
        #expect(bareMethods["-[SDObjCCounter incrementBy:]"] == fullMethods["-[SDObjCCounter incrementBy:]"])
    }
}

/// A filtered disassembly must be able to find an ObjC selector when the raw
/// implementation symbol is gone, and direct ivar loads/stores must use the
/// runtime's absolute ivar offsets.
@Test func recoversStrippedObjCMethodBodyAndIvars() async throws {
    let path = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path,
            functionFilter: "incrementBy"
        )
    }
    guard let method = functions.first(where: { $0.objcMethod?.selector == "incrementBy:" }) else {
        // Older pre-built fixtures did not yet include sample_objc.m.
        return
    }
    #expect(method.source == .objcMetadata)
    #expect(method.displayName == "-[SDObjCCounter incrementBy:]")
    #expect(method.objcMethod?.signature == "- (long long)incrementBy:(long long)arg0;")
    let notes = method.instructions.compactMap(\.annotation)
    #expect(notes.contains("self->_count"))
    #expect(notes.contains("self->_count += arg0"))
    #expect(method.renderPseudo().contains("self->_count += arg0"))
    #expect(method.renderPseudo().contains("return self->_count"))
}

/// ObjC metadata proves x0=self and x2=arg0 at entry. Both values should flow
/// through register moves into a recovered message expression.
@Test func tracksObjCReceiverArgumentsAndIvarValues() async throws {
    let path = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path,
            functionFilter: "greetingWithPrefix"
        )
    }
    guard let method = functions.first(where: { $0.objcMethod?.selector == "greetingWithPrefix:" }) else {
        return
    }
    #expect(method.renderPseudo().contains("return [arg0 stringByAppendingString:self->_name]"))
}

@Test func preservesObjCCategoryOwnership() async throws {
    let path = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path,
            functionFilter: "sd_stringByAddingBang"
        )
    }
    guard let method = functions.first(where: { $0.objcMethod?.selector == "sd_stringByAddingBang" }) else {
        return
    }
    #expect(method.objcMethod?.className == "NSString")
    #expect(method.objcMethod?.categoryName == "SDSampleExtras")
    #expect(method.displayName == "-[NSString(SDSampleExtras) sd_stringByAddingBang]")
    #expect(method.renderPseudo().contains("return [self stringByAppendingString:@\"!\"]"))
}

/// Stage 2 retains values through arithmetic, runtime property helpers, subword
/// ivar accesses, initializer super-calls, and return registers.
@Test func recoversSourceLikeObjCStatements() async throws {
    let path = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path,
            functionFilter: "SDObjCCounter"
        )
    }

    func pseudo(_ selector: String) -> String {
        expandingResultBindingsForAssertions(functions.first(where: { $0.objcMethod?.selector == selector })?.renderPseudo() ?? "")
    }

    let initializer = pseudo("initWithName:count:")
    #expect(initializer.contains("self = [super init]"))
    #expect(initializer.contains("self->_name = [arg0 copy]"))
    #expect(initializer.contains("self->_count = arg1"))
    #expect(initializer.contains("self->_enabled = YES"))
    #expect(initializer.contains("return self"))
    let structuredInitializer = functions
        .first(where: { $0.objcMethod?.selector == "initWithName:count:" })?
        .renderStructured() ?? ""
    #expect(structuredInitializer.contains("if (self != 0)"))
    #expect(!structuredInitializer.contains("if (sp"))
    #expect(pseudo("name").contains("return self->_name"))
    #expect(pseudo("setName:").contains("self->_name = [arg0 copy]"))
    #expect(pseudo("isEnabled").contains("return self->_enabled"))
    #expect(pseudo("setEnabled:").contains("self->_enabled = arg0"))
    #expect(pseudo(".cxx_destruct").contains("self->_name = nil"))
    #expect(pseudo("formattedCount").contains(
        "return [NSString stringWithFormat:@\"%ld\", self->_count]"
    ))
    #expect(pseudo("seventhValueA:b:c:d:e:f:g:").contains("return arg6"))
    #expect(pseudo("initWithA:b:c:d:e:f:g:").contains("self->_count = arg6"))
    #expect(pseudo("counterWithA:b:c:d:e:f:g:").contains(
        "return [[self alloc] initWithA:arg0 b:arg1 c:arg2 d:arg3 e:arg4 f:arg5 g:arg6]"
    ))

    // ARC runtime helpers are exact lowerings of a source send, so rendering
    // each one back composes into the original expression.
    //
    // The composed form is the load-bearing case, and the lowering is the
    // reverse of what it looks like: `[self alloc]` (a Class receiver, as in
    // +counterWithA: above) lowers to a bare objc_alloc(self), while
    // `[[self class] alloc]` (an INSTANCE receiver) lowers to
    // objc_alloc(objc_opt_class(self)). Collapsing the composed form to
    // `[self alloc]` therefore drops a real `class` call — and on an instance
    // receiver prints something that is not valid ObjC at all, since `alloc` is
    // a class method. These three methods are instance methods for that reason;
    // a class-method fixture cannot reach this path.
    #expect(pseudo("sd_bareClassAlloc").contains("return [[self class] alloc]"))
    #expect(!pseudo("sd_bareClassAlloc").contains("return [self alloc]"))
    #expect(pseudo("sd_classAllocInit").contains("return [[[self class] alloc] init]"))
    #expect(pseudo("sd_isSameKindAs:").contains("[arg0 isKindOfClass:[self class]]"))

    let json = functions.jsonString()
    #expect(json.contains("\"statement\" : \"return self->_name\""))
}

@Test func structuresObjCControlFlowWithSourceNames() async throws {
    let path = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path,
            functionFilter: "incrementIfEnabled"
        )
    }
    guard let method = functions.first(where: { $0.objcMethod?.selector == "incrementIfEnabled:" })
    else { return }
    let structured = method.renderStructured()
    #expect(structured.contains("if (self->_enabled)"))
    #expect(structured.contains("self->_count += arg0"))
    #expect(structured.contains("return self->_count"))

    let argumentFunctions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path,
            functionFilter: "incrementIfPositive"
        )
    }
    guard let argumentMethod = argumentFunctions.first(where: {
        $0.objcMethod?.selector == "incrementIfPositive:"
    }) else { return }
    let argumentStructured = argumentMethod.renderStructured()
    #expect(argumentStructured.contains("arg0"))
    #expect(!argumentStructured.contains("x2"))
}

/// How a Swift value of a demangled type travels: in no register, one
/// integer register, one floating-point register, several registers, or
/// not provably in registers at all.
///
/// One classification for every consumer that asks the question. Entry
/// seeding, call layout, the register a result is read from and whether a
/// callee returns through x8 each kept their own type list, and the lists
/// disagreed: the x8 check took any type spelling ` -> ` as a closure in
/// registers, so a tuple of three closures (six words) and
/// `Dictionary<Int, Int>.Iterator` (40 bytes) read as direct results
/// while the result-register check declined both. Facts here follow
/// swift/docs/ABI/TypeLayout.rst and the calling convention's rule that a
/// value of at most four words is returned in registers
/// (docs/ABI/CallingConvention.rst, "Physical Conventions").
enum SwiftLowering: Equatable, Sendable {
    /// No value: `()`, `Never`, a one-case enum.
    case zeroSized
    /// One integer register: an integer, Bool, pointer, reference, `any
    /// Error`, a one-pointer collection, a no-payload enum of two or more
    /// cases, an Optional of a pointer or reference.
    case oneInteger
    /// One floating-point register.
    case oneFloat
    /// In registers, more than one or of a layout not modelled further: a
    /// String's two words, an Optional scalar's payload and tag, a closure's
    /// function and context, a buffer pointer, a metatype.
    case direct
    /// Not proven to travel in registers: a struct, payload enum, tuple,
    /// generic parameter, existential or anything unlisted.
    case unknown

    /// Whether the value travels in registers, so a result never uses x8.
    var isDirect: Bool { self != .unknown }

    static func of(
        _ type: String, enumCaseIndex: EnumCaseIndex = EnumCaseIndex(),
        classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> SwiftLowering {
        let type = type.trimmingCharacters(in: .whitespaces)
        // A resilient enum is passed by address, whatever its cases.
        if enumCaseIndex.isResilient(type) { return .unknown }
        if ["()", "Swift.Void", "Swift.Never"].contains(type) || enumCaseIndex.isSingleCaseEnum(type) {
            return .zeroSized
        }
        if floats.contains(type) { return .oneFloat }
        if let payload = Disassembler.optionalPayload(type) {
            // A pointer or reference optional is nil as 0 in one register; any
            // other payload adds a tag or uses an extra inhabitant, which this
            // does not model, so it is direct only when the payload is.
            if Disassembler.isSingleRegisterPointer(payload) || classTypeIndex.isClass(payload)
                || payload == "Swift.AnyObject" {
                return .oneInteger
            }
            return of(payload, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex).isDirect
                ? .direct : .unknown
        }
        // A variadic parameter (`Any...`) is passed as its Array.
        if type.hasSuffix("..."), type.count > 3 { return .oneInteger }
        if integers.contains(type) || Disassembler.isSingleRegisterPointer(type)
            || onePointerGenerics.contains(where: { isWhole(type, generic: $0) })
            || enumCaseIndex.isNoPayloadEnum(type) || classTypeIndex.isClass(type) {
            return .oneInteger
        }
        // An `Any` existential metatype is its metadata pointer alone: `Any`
        // has no protocol, so no witness table follows it (`_typeName(_:
        // qualified:)`). Any other `.Type` may be thin (no register) or carry
        // witness tables.
        if type == "Any.Type" || type == "Swift.Any.Type" { return .oneInteger }
        // `AnyObject` is a layout constraint, not a protocol with witnesses:
        // its existential metatype is the class's metadata pointer alone
        // (measured: `pick(_:_:_:)` selects between x1 and x2, `pass(_:_:)`
        // takes its Int in x1).
        if type == "AnyObject.Type" || type == "Swift.AnyObject.Type" { return .oneInteger }
        if multiWord.contains(type) || multiWordGenerics.contains(where: { isWhole(type, generic: $0) })
            || type.hasSuffix(".Protocol") || isFunctionType(type) {
            return .direct
        }
        // Any other metatype is a metadata pointer (or nothing, when thin)
        // and, when existential, one witness table for each protocol that
        // has one. Five words leave the registers.
        if type.hasSuffix(".Type") {
            return metatypeWordBound(type) <= maxDirectResultWords ? .direct : .unknown
        }
        return .unknown
    }

    /// The standard library's frozen fixed-width integers and `Bool`: one
    /// general register each, passed by value wherever they are `self`.
    static let fixedWidthIntegers: Set<String> = [
        "Swift.Bool", "Swift.Int", "Swift.UInt", "Swift.Int8", "Swift.UInt8", "Swift.Int16", "Swift.UInt16",
        "Swift.Int32", "Swift.UInt32", "Swift.Int64", "Swift.UInt64",
    ]

    /// A result of more words than this is returned through x8.
    private static let maxDirectResultWords = 4
    /// Composition members that are never a protocol with a witness table:
    /// the `AnyObject` layout constraint and the `Sendable` marker.
    private static let witnesslessMembers: Set<String> = ["Swift.AnyObject", "Swift.Sendable"]

    /// The most words the metatype spelled `type` (`….Type`) can take: its
    /// metadata pointer and one witness table for each member of the
    /// composition it names (IRGen's `convertExistentialMetatypeType`).
    ///
    /// An existential metatype prints as its members joined by ` & ` with
    /// the suffix on the last one (`M.P & M.Q.Type`, `any M.P & M.Q<…>.Type`),
    /// and the name does not say which members are protocols with witness
    /// tables: a superclass, an `@objc` protocol and a marker protocol of
    /// another module take none and are counted as one each. A concrete
    /// metatype (`M.S.Type`, `M.G<M.P & M.Q>.Type`) has one member and is
    /// one word or none.
    private static func metatypeWordBound(_ type: String) -> Int {
        var members: [Substring] = []
        var depth = 0
        var start = type.startIndex
        var index = type.startIndex
        while index < type.endIndex {
            let character = type[index]
            if depth == 0, type[index...].hasPrefix(" & ") {
                members.append(type[start..<index])
                index = type.index(index, offsetBy: 3)
                start = index
                continue
            }
            switch character {
            case "(", "<", "[": depth += 1
            // The `>` of an arrow closes nothing.
            case ">" where index > type.startIndex && type[type.index(before: index)] == "-": break
            case ")", ">", "]": depth -= 1
            default: break
            }
            index = type.index(after: index)
        }
        members.append(type[start...])
        // The suffix belongs to the whole composition, and a metatype of a
        // metatype (`M.P & M.Q.Type.Type`) has the same words.
        var last = members.removeLast()
        while last.hasSuffix(".Type") { last = last.dropLast(".Type".count) }
        members.append(last)
        return 1 + members.filter { !witnesslessMembers.contains(String($0)) }.count
    }

    private static let floats: Set<String> = [
        "Swift.Double", "Swift.Float", "Swift.Float16", "Swift.Float32", "Swift.Float64",
        "Swift.CGFloat", "CoreGraphics.CGFloat",
    ]
    private static let integers: Set<String> = [
        "Swift.Bool", "Swift.Int", "Swift.UInt", "Swift.Int8", "Swift.UInt8", "Swift.Int16", "Swift.UInt16",
        "Swift.Int32", "Swift.UInt32", "Swift.Int64", "Swift.UInt64", "Swift.AnyObject",
        // `any Error` is one pointer to its box (SwiftError).
        "Swift.Error",
        // `_rawBits: UInt64` (stdlib/public/core/StringIndex.swift).
        "Swift.String.Index",
        // `case equal, less` (StringComparison.swift).
        "Swift._StringComparisonResult",
        // The compiler's own scalars (`_stdlib_isOSVersionAtLeast…` returns
        // `Builtin.Int1`).
        "Builtin.Int1", "Builtin.Int8", "Builtin.Int16", "Builtin.Int32", "Builtin.Int64", "Builtin.Word",
        "Builtin.RawPointer", "Builtin.NativeObject", "Builtin.BridgeObject", "Builtin.UnknownObject",
    ]
    /// One storage (or bridge) pointer: Array's, ContiguousArray's,
    /// Dictionary's and Set's native value, and the array buffers'.
    private static let onePointerGenerics = [
        "Swift.Array", "Swift.ContiguousArray", "Swift.Dictionary", "Swift.Set",
        "Swift._ArrayBuffer", "Swift._ContiguousArrayBuffer",
    ]
    /// Two to four words.
    private static let multiWord: Set<String> = [
        "Swift.String", "Swift._StringGuts", "Swift.Substring", "Swift.Character", "Swift.Unicode.Scalar", "Swift.StaticString",
        "Swift.AnyKeyPath",
    ]
    private static let multiWordGenerics = [
        "Swift.UnsafeBufferPointer", "Swift.UnsafeMutableBufferPointer", "Swift.Unmanaged",
    ]

    /// Whether `type` is `generic<…>` itself, not a type nested in it:
    /// `Swift.Dictionary<Swift.Int, Swift.Int>.Iterator` is 40 bytes, and a
    /// prefix test read it as the dictionary's one pointer.
    private static func isWhole(_ type: String, generic: String) -> Bool {
        guard type.hasPrefix(generic + "<"), type.hasSuffix(">") else { return false }
        var depth = 0
        var previous: Character?
        for (offset, character) in type.dropFirst(generic.count).enumerated() {
            defer { previous = character }
            if character == "<" { depth += 1 }
            // A function-valued element still belongs to the collection:
            // `Array<(Int) -> Int>` is one pointer. The arrow's `>` closes
            // neither this generic nor one nested inside it.
            if character == ">", previous != "-" {
                depth -= 1
                if depth == 0 { return offset == type.count - generic.count - 1 }
            }
        }
        return false
    }

    /// Whether `type` is a function type as a whole, `(…) -> …` with
    /// attributes, not a tuple or generic that contains one: `((Int) -> Int,
    /// (Int) -> Int, (Int) -> Int)` is six words.
    private static func isFunctionType(_ type: String) -> Bool {
        var rest = Substring(type)
        while rest.hasPrefix("@") {
            guard let space = rest.firstIndex(of: " ") else { return false }
            rest = rest[rest.index(after: space)...]
        }
        guard rest.first == "(" else { return false }
        var depth = 0
        for index in rest.indices {
            // The `>` of an arrow closes nothing.
            if rest[index] == ">", index > rest.startIndex, rest[rest.index(before: index)] == "-" { continue }
            switch rest[index] {
            case "(", "<", "[": depth += 1
            case ")", ">", "]":
                depth -= 1
                if depth == 0 {
                    let tail = rest[rest.index(after: index)...]
                    return tail.hasPrefix(" -> ") || tail.hasPrefix(" throws") || tail.hasPrefix(" async")
                }
            default: break
            }
        }
        return false
    }
}

extension SwiftLowering {
    /// The registers a struct this image lays out in full takes as a direct
    /// argument: how many x and how many v registers, or one x register (its
    /// address) when it is passed indirectly. Nil when any field's
    /// representation is not proven.
    ///
    /// Measured against `swiftc -O -emit-ir` (docs/ABI-INVARIANTS.md, the
    /// struct-lowering oracle): IRGen explodes the struct into its scalar
    /// fields at their byte offsets, nested structs flattened and empty
    /// ones dropped, and the Swift calling convention then merges integer
    /// scalars that are neighbours in offset order and share an 8-byte chunk
    /// into one register (`{Int32, Int32}` is one i64, `{Bool, Bool}` one
    /// i16) while every float or double keeps its own (`{Float, Float}` is
    /// two floats, `{Float, Int32}` a float and an i32). A float between two
    /// integers of one chunk keeps them apart: `{Int16, Float16, Int16}` is
    /// i16, half, i16, three registers, where `{Int16, Int16, Float16}` is
    /// i32, half (clang `SwiftAggLowering::finish` merges `Entries[i - 1]`
    /// with `Entries[i]` only, and never a floating-point entry). More than
    /// four registers in all go indirect (`{Int ×5}`, `{Float ×4, Int}`).
    static func aggregateRegisters(
        of type: String, fieldMaps: [String: FieldMap],
        enumCaseIndex: EnumCaseIndex = EnumCaseIndex(), classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> (integers: Int, floats: Int)? {
        guard let footprint = aggregateRegisterFootprint(
            of: type, fieldMaps: fieldMaps, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex)
        else { return nil }
        if footprint.integers + footprint.floats > 4 { return (1, 0) }
        return footprint
    }

    /// A complete direct value, never the pointer used to transport an
    /// indirect formal. The latter does not prove an ordinary value receiver.
    static func directAggregateRegisters(
        of type: String, fieldMaps: [String: FieldMap],
        enumCaseIndex: EnumCaseIndex = EnumCaseIndex(), classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> (integers: Int, floats: Int)? {
        guard let footprint = aggregateRegisterFootprint(
            of: type, fieldMaps: fieldMaps, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex),
              footprint.integers + footprint.floats <= 4
        else { return nil }
        return footprint
    }

    private static func aggregateRegisterFootprint(
        of type: String, fieldMaps: [String: FieldMap],
        enumCaseIndex: EnumCaseIndex, classTypeIndex: ClassTypeIndex
    ) -> (integers: Int, floats: Int)? {
        // An explicit Void parameter is still a source argument, but the
        // empty tuple has no payload in either register bank. Keep its opaque
        // slot while placing later arguments; dropping the slot would change
        // their source indices. This does not classify tuples containing Void.
        if type == "()" || type == "Swift.Void" { return (0, 0) }
        // An empty struct is laid out, complete, in zero bytes: no register.
        if !classTypeIndex.isClass(type), let map = fieldMaps[type], map.instanceSize == 0,
           map.trustLimitReason == nil, map.fields.isEmpty {
            return (0, 0)
        }
        var pieces: [ScalarPiece] = []
        guard collectScalars(of: type, at: 0, fieldMaps: fieldMaps, enumCaseIndex: enumCaseIndex,
                             classTypeIndex: classTypeIndex, depth: 0, pieces: &pieces)
        else { return nil }
        var integers = 0, floats = 0
        var previous: ScalarPiece?
        for piece in pieces.sorted(by: { $0.begin < $1.begin }) {
            // Two scalars at the same bytes are not one struct's fields: the
            // layout contradicts itself, and neither reading is counted.
            if let previous, piece.begin < previous.end { return nil }
            // An integer joins the register of the piece just before it when
            // that piece is an integer ending in the chunk this one starts in.
            let joinsPrevious = previous.map { !$0.isFloat && ($0.end - 1) / 8 == piece.begin / 8 } ?? false
            if piece.isFloat {
                floats += 1
            } else if !joinsPrevious {
                integers += 1
            }
            previous = piece
        }
        return (integers, floats)
    }

    /// One scalar a struct lowers to, at its bytes `begin ..< end` from the
    /// start of the outermost value. An integer piece lies within one 8-byte
    /// chunk; padding is no piece.
    private struct ScalarPiece {
        let begin: Int
        let end: Int
        let isFloat: Bool
    }

    private static func collectScalars(
        of type: String, at base: Int, fieldMaps: [String: FieldMap],
        enumCaseIndex: EnumCaseIndex, classTypeIndex: ClassTypeIndex, depth: Int,
        pieces: inout [ScalarPiece]
    ) -> Bool {
        guard depth < 8,
              let map = Disassembler.completeValueLayout(of: type, fieldMaps: fieldMaps, classTypeIndex: classTypeIndex),
              // A possibly resilient type is passed by address, whatever its
              // fields; its layout in memory is still the map's.
              !map.mayBeResilient
        else { return false }
        for field in map.fields {
            let offset = base + field.offset
            guard let fieldType = map.fieldTypeNames[field.name] else { return false }
            switch of(fieldType, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex) {
            case .oneInteger:
                // An integer field never straddles a chunk: it is aligned to
                // its size.
                guard field.bytes <= 8, offset % 8 + field.bytes <= 8 else { return false }
                pieces.append(ScalarPiece(begin: offset, end: offset + field.bytes, isFloat: false))
            case .oneFloat:
                pieces.append(ScalarPiece(begin: offset, end: offset + field.bytes, isFloat: true))
            case .zeroSized:
                continue
            default:
                if Disassembler.twoWordStringTypes.contains(fieldType), field.bytes == 16 {
                    // Two whole words, each its own chunk.
                    guard offset % 8 == 0 else { return false }
                    pieces.append(ScalarPiece(begin: offset, end: offset + 8, isFloat: false))
                    pieces.append(ScalarPiece(begin: offset + 8, end: offset + 16, isFloat: false))
                } else if let payload = Disassembler.optionalScalarPayload(ofParameterType: fieldType) {
                    // Its payload's bytes, a Double's included, then a tag
                    // byte: integer data both, so a payload narrower than a
                    // word shares its register with the tag.
                    guard offset % 8 + payload.bytes <= 8 else { return false }
                    let tag = offset + payload.bytes
                    pieces.append(ScalarPiece(begin: offset, end: tag, isFloat: false))
                    pieces.append(ScalarPiece(begin: tag, end: tag + 1, isFloat: false))
                } else if !collectScalars(of: fieldType, at: offset, fieldMaps: fieldMaps,
                                          enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex,
                                          depth: depth + 1, pieces: &pieces) {
                    return false
                }
            }
        }
        return true
    }
}

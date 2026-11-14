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
            || type.hasSuffix(".Type") || type.hasSuffix(".Protocol") || isFunctionType(type) {
            return .direct
        }
        return .unknown
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
    /// ones dropped, and the Swift calling convention then merges the
    /// integer data in each 8-byte chunk into one register (`{Int32, Int32}`
    /// is one i64, `{Bool, Bool}` one i16) while every float or double keeps
    /// its own (`{Float, Float}` is two floats, `{Float, Int32}` a float and
    /// an i32). More than four registers in all go indirect (`{Int ×5}`,
    /// `{Float ×4, Int}`).
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
        var integerChunks = Set<Int>()
        var floats = 0
        guard collectScalars(of: type, at: 0, fieldMaps: fieldMaps, enumCaseIndex: enumCaseIndex,
                             classTypeIndex: classTypeIndex, depth: 0,
                             integerChunks: &integerChunks, floats: &floats)
        else { return nil }
        return (integerChunks.count, floats)
    }

    private static func collectScalars(
        of type: String, at base: Int, fieldMaps: [String: FieldMap],
        enumCaseIndex: EnumCaseIndex, classTypeIndex: ClassTypeIndex, depth: Int,
        integerChunks: inout Set<Int>, floats: inout Int
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
                integerChunks.insert(offset / 8)
            case .oneFloat:
                floats += 1
            case .zeroSized:
                continue
            default:
                if Disassembler.twoWordStringTypes.contains(fieldType), field.bytes == 16 {
                    integerChunks.formUnion([offset / 8, offset / 8 + 1])
                } else if let payload = Disassembler.optionalScalarPayload(ofParameterType: fieldType) {
                    // Its payload's bytes, a Double's included, then a tag byte.
                    integerChunks.insert(offset / 8)
                    integerChunks.insert((offset + payload.bytes) / 8)
                } else if !collectScalars(of: fieldType, at: offset, fieldMaps: fieldMaps,
                                          enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex,
                                          depth: depth + 1, integerChunks: &integerChunks, floats: &floats) {
                    return false
                }
            }
        }
        return true
    }
}

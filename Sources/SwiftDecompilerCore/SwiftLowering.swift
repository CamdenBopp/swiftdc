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
        if integers.contains(type) || Disassembler.isSingleRegisterPointer(type)
            || onePointerGenerics.contains(where: { isWhole(type, generic: $0) })
            || enumCaseIndex.isNoPayloadEnum(type) || classTypeIndex.isClass(type) {
            return .oneInteger
        }
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
        "Swift.String", "Swift.Substring", "Swift.Character", "Swift.Unicode.Scalar", "Swift.StaticString",
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
        for (offset, character) in type.dropFirst(generic.count).enumerated() {
            if character == "<" { depth += 1 }
            if character == ">" {
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

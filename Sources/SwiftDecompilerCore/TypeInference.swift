import Foundation

/// Phase-1 type recovery: derive a `ValueType` for a value from the two
/// lowest-uncertainty evidence sources — the ABI signature (typed parameters)
/// and the value's own structure — computed once in analysis, not re-parsed at
/// each render site. See `docs/research/phase1-type-lattice.md`.
///
/// Deliberately conservative: absent evidence yields `.unknown`, and integer
/// **signedness** is set only from a typed parameter (or a sign-encoding
/// operator), never inferred from "a register holds an integer".
public enum TypeInference {
    /// The recovered type of each source-parameter index, keyed like
    /// `.argument(index)`. The single typed source that replaces the scattered
    /// render-site signature parsers for the purpose of comparison signedness.
    public static func argumentTypes(
        of function: DisassembledFunction, classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> [Int: ValueType] {
        guard function.objcMethod == nil, let name = function.demangledName,
              Disassembler.isSwiftMangled(function.symbol),
              let arrow = name.range(of: " -> ", options: .backwards)
        else { return [:] }
        let signature = name[..<arrow.lowerBound]
        guard let paramsRange = DisassembledFunction.outermostArgumentListRange(of: String(signature))
        else { return [:] }
        var types: [Int: ValueType] = [:]
        for (index, parameter) in DisassembledFunction
            .splitTopLevelArguments(signature[paramsRange]).enumerated() {
            types[index] = classify(parameterType(parameter), classTypeIndex: classTypeIndex)
        }
        return types
    }

    /// The declared type name of a demangled parameter (`label: Type` → `Type`).
    private static func parameterType(_ parameter: String) -> String {
        var type = parameter
        if let colon = type.range(of: ": ", options: .backwards) {
            type = String(type[colon.upperBound...])
        }
        return type.trimmingCharacters(in: .whitespaces)
    }

    private static let signedInts: [String: Int] = [
        "Swift.Int": 64, "Swift.Int64": 64, "Swift.Int32": 32,
        "Swift.Int16": 16, "Swift.Int8": 8,
    ]
    private static let unsignedInts: [String: Int] = [
        "Swift.UInt": 64, "Swift.UInt64": 64, "Swift.UInt32": 32,
        "Swift.UInt16": 16, "Swift.UInt8": 8,
    ]
    private static let floats: [String: Int] = [
        "Swift.Double": 64, "Swift.Float64": 64, "Swift.CGFloat": 64,
        "CoreGraphics.CGFloat": 64, "Swift.Float": 32, "Swift.Float32": 32, "Swift.Float16": 16,
    ]

    /// Classify a Swift type name into the lattice. Unknown for anything not on
    /// the concrete-scalar list — an honest bottom, not a guess.
    static func classify(
        _ type: String, classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> ValueType {
        if let w = signedInts[type] { return .signedInteger(w) }
        if let w = unsignedInts[type] { return .unsignedInteger(w) }
        if let w = floats[type] { return .floating(w) }
        if type == "Swift.Bool" { return .boolean }
        if type == "Swift.OpaquePointer" || type == "Swift.UnsafeRawPointer"
            || type == "Swift.UnsafeMutableRawPointer"
            || type.hasPrefix("Swift.UnsafePointer<")
            || type.hasPrefix("Swift.UnsafeMutablePointer<") { return .pointer }
        // A reference (class) optional is a single-register nilable value; typing
        // it `.optional` is what lets its `== 0`/`!= 0` render as `== nil`/`!= nil`.
        if classTypeIndex.referenceOptionalInner(type) != nil {
            return ValueType(category: .optional, width: 64, signedness: .unknownSign)
        }
        return .unknown
    }

    /// The structural type of a value, consulting the seeded argument types. Used
    /// to decide whether an unsigned machine comparison over a value is a signed
    /// range check, an unsigned `UInt` comparison, or must stay low-level.
    ///
    /// Signedness is propagated only where an operator encodes it (`-x` is
    /// signed; a compare is boolean). A bare immediate is `integer` with
    /// **unknown** signedness — its bit pattern alone proves nothing.
    static func typeOf(_ value: AbstractValue, arguments: [Int: ValueType]) -> ValueType {
        switch value {
        case .argument(let index):
            return arguments[index] ?? .unknown
        case .immediate:
            return ValueType(category: .integer, width: nil, signedness: .unknownSign)
        case .binary(let op, let lhs, let rhs):
            if op.isComparison { return .boolean }
            switch op {
            case .add, .subtract, .multiply, .divide, .remainder:
                // Arithmetic preserves the signedness the non-constant operands
                // agree on: a constant is signedness-NEUTRAL (`signedValue + 1`
                // stays signed), so it imposes no facet and is not met in. Width
                // is dropped. Two genuinely-conflicting operands (signed - unsigned)
                // still resolve down to unknownSign.
                let operandTypes = [lhs, rhs].compactMap { operand -> ValueType? in
                    if case .immediate = operand { return nil }
                    return typeOf(operand, arguments: arguments)
                }
                guard let first = operandTypes.first else {
                    return ValueType(category: .integer, width: nil, signedness: .unknownSign)
                }
                let merged = operandTypes.dropFirst().reduce(first, ValueType.meet)
                return ValueType(category: merged.category == .integer ? .integer : merged.category,
                                 width: nil, signedness: merged.signedness)
            case .bitAnd:
                // A low-bits mask (`& 0xff`) is a width TRUNCATION, not a sign
                // change: a zero-extended byte of an unsigned value is unsigned at
                // the narrower width. A signed value through the mask is no longer
                // provably signed (its byte reads unsigned), so it degrades to
                // unknown — honest, not a fabricated signedness.
                if case .immediate(let mask) = rhs,
                   [0xff, 0xffff, 0xffff_ffff].contains(mask) {
                    let width = mask == 0xff ? 8 : (mask == 0xffff ? 16 : 32)
                    return typeOf(lhs, arguments: arguments).isUnsignedInteger
                        ? .unsignedInteger(width)
                        : ValueType(category: .integer, width: width, signedness: .unknownSign)
                }
                return ValueType(category: .integer, width: nil, signedness: .unknownSign)
            case .bitOr, .bitXor, .shiftLeft, .shiftRight, .arithmeticShiftRight:
                return ValueType(category: .integer, width: nil, signedness: .unknownSign)
            default:
                return .unknown
            }
        case .unary(let op, let operand):
            switch op {
            case .negate: // `-x` is signed
                let t = typeOf(operand, arguments: arguments)
                return .signedInteger(t.width)
            case .bitwiseNot:
                return ValueType(category: .integer, width: nil, signedness: .unknownSign)
            case .squareRoot, .absoluteValue:
                return .floating(nil)
            }
        default:
            return .unknown
        }
    }
}

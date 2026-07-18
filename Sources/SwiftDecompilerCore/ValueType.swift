import Foundation

/// A small, conservative type recovered for a value. The *representation* half of the Phase-1 type
/// lattice (see `docs/research/phase1-type-lattice.md`). Every fact is optional and every conflict
/// resolves *down* to unknown — the lattice bottom is "we know nothing", and no operation ever
/// invents a fact. It exists so semantic facts (notably integer **signedness**, whose loss is the
/// U1 defect) travel with values instead of being re-derived from function signatures at render time.
///
/// Phase 1 populates this from two low-uncertainty evidence sources only — the ABI signature (typed
/// parameters) and signedness-encoding instructions (the comparison condition code) — and computes it
/// structurally via `typeOf`. A fully flowing mid-body type-state (Phase 2) will reuse `meet`
/// unchanged. Deliberately NOT a Swift type: it records only what machine code + metadata justify.
public struct ValueType: Equatable, Sendable {
    /// The coarse semantic category. `.unknown` is a real state, not an error.
    public enum Category: Equatable, Sendable {
        case integer
        case boolean
        case floatingPoint
        case pointer
        case enumeration
        case optional
        case unknown
    }

    /// Signedness is meaningful only for `.integer`. `.unknownSign` is the honest default — an ARM64
    /// register holding an integer-shaped value does NOT reveal Swift's source-level signedness.
    public enum Signedness: Equatable, Sendable {
        case signed
        case unsigned
        case unknownSign
    }

    public var category: Category
    /// Bit width (8/16/32/64) when known; nil = unknown.
    public var width: Int?
    public var signedness: Signedness

    public init(category: Category, width: Int? = nil, signedness: Signedness = .unknownSign) {
        self.category = category
        self.width = width
        self.signedness = signedness
    }

    /// The lattice bottom — nothing known.
    public static let unknown = ValueType(category: .unknown, width: nil, signedness: .unknownSign)

    // Convenience constructors for the facts the ABI hands us.
    public static func signedInteger(_ width: Int?) -> ValueType {
        ValueType(category: .integer, width: width, signedness: .signed)
    }
    public static func unsignedInteger(_ width: Int?) -> ValueType {
        ValueType(category: .integer, width: width, signedness: .unsigned)
    }
    public static let boolean = ValueType(category: .boolean, width: 1, signedness: .unknownSign)
    public static func floating(_ width: Int?) -> ValueType {
        ValueType(category: .floatingPoint, width: width, signedness: .unknownSign)
    }
    public static let pointer = ValueType(category: .pointer, width: 64, signedness: .unsigned)

    /// Whether this is definitely a signed integer (the fact that lets an unsigned machine comparison
    /// over it be recovered as the `0 <= x && x < N` range idiom).
    public var isSignedInteger: Bool { category == .integer && signedness == .signed }
    /// Whether this is definitely an unsigned integer (so an unsigned machine comparison of it reads
    /// as a plain `<`, which is correct for `UInt`).
    public var isUnsignedInteger: Bool { category == .integer && signedness == .unsigned }

    /// The join used at CFG merges and to combine evidence: keep only facts BOTH sides support.
    /// Category disagreement → `.unknown`; width disagreement → nil; signedness disagreement →
    /// `.unknownSign`. Monotone (never adds a fact), commutative, associative, idempotent.
    public static func meet(_ a: ValueType, _ b: ValueType) -> ValueType {
        ValueType(
            category: a.category == b.category ? a.category : .unknown,
            width: a.width == b.width ? a.width : nil,
            signedness: a.signedness == b.signedness ? a.signedness : .unknownSign
        )
    }
}

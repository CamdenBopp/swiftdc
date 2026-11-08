/// Folds the compiler's lowering of division and remainder by a constant back
/// to `x / D` and `x % D`.
///
/// LLVM turns `x / D` into a multiply-high by a magic reciprocal plus shifts,
/// in shapes that vary with D and signedness (from `swiftc -O` at Xcode 26):
///
///     x / 7     smulh; asr #1; add q, q', hi lsr #63
///     x / 3     smulh; add q, hi, hi lsr #63            (no post-shift)
///     x / 15    smulh; add hi, hi, x; asr #3; add …     (add-back, sign from hi + x)
///     x / -7    smulh; asr #1; add …                    (negative divisor)
///     UInt / 7  umulh; sub t, x, hi; add hi, hi, t lsr #1; lsr #2
///     UInt/1000 lsr x, #3; umulh; lsr #4                (pre-shift)
///     x % 7     … ; sub t, q, q lsl #3; add x, x, t     (x - 7q via shifts)
///
/// The fold has two halves. Evaluation finds the divisor: the tree is run on
/// concrete inputs, D is read off by bisection, and the tree must agree with
/// real division on boundary probes (multiples of D and their neighbours, both
/// signs, the extremes), which a partial sequence (the signed `asr` before its
/// sign correction, which floors) fails. Then the proof: `MagicConstants`
/// regenerates LLVM's own constants for D, and the tree must be, structurally,
/// the sequence LLVM emits with them, whose derivation is exact for every
/// 64-bit input. A probe-passing tree that is not that sequence stays as built.
/// A remainder is proven by linear arithmetic over `x` and the quotient.
enum MagicDivision {
    static func fold(
        _ op: AbstractBinaryOperator, _ lhs: AbstractValue, _ rhs: AbstractValue
    ) -> AbstractValue? {
        switch op {
        case .add, .subtract, .shiftRight, .arithmeticShiftRight: break
        default: return nil
        }
        let tree = AbstractValue.binary(op, lhs, rhs)
        return quotient(tree) ?? remainder(tree)
    }

    // MARK: - Quotient

    private static func quotient(_ tree: AbstractValue) -> AbstractValue? {
        var signed = false, unsigned = false
        multiplyHighKinds(tree, signed: &signed, unsigned: &unsigned)
        // No multiply-high: not this idiom (a bare `x >> 3` stays a shift).
        // Both kinds: some other computation; decline.
        guard signed != unsigned else { return nil }
        var atoms: [AbstractValue] = []
        collectAtoms(tree, into: &atoms)
        guard atoms.count == 1 else { return nil }
        let x = atoms[0]
        let q: (UInt64) -> UInt64? = { evaluate(tree, bindings: [(x, $0)]) }
        guard let divisor = signed ? signedDivisor(q) : unsignedDivisor(q),
              isLLVMLowering(tree, of: x, divisor: divisor, signed: signed)
        else { return nil }
        return .binary(signed ? .divide : .unsignedDivide, x, .immediate(divisor))
    }

    /// |D| is the smallest positive x whose quotient is non-zero, and that
    /// quotient's sign is D's. Found by bisection, then verified, so a tree
    /// that is not monotone in x simply fails the verification.
    private static func signedDivisor(_ q: (UInt64) -> UInt64?) -> UInt64? {
        guard let top = q(UInt64(Int64.max)).map({ Int64(bitPattern: $0) }), top != 0 else { return nil }
        var lo: Int64 = 1, hi: Int64 = .max
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            guard let value = q(UInt64(mid)) else { return nil }
            if value == 0 { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 1 else { return nil }
        let divisor = top < 0 ? -lo : lo
        for x in signedProbes(magnitude: lo) {
            guard let got = q(UInt64(bitPattern: x)), Int64(bitPattern: got) == x / divisor else { return nil }
        }
        return UInt64(bitPattern: divisor)
    }

    private static func unsignedDivisor(_ q: (UInt64) -> UInt64?) -> UInt64? {
        guard let top = q(.max), top != 0 else { return nil }
        var lo: UInt64 = 1, hi: UInt64 = .max
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            guard let value = q(mid) else { return nil }
            if value == 0 { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 1 else { return nil }
        for x in unsignedProbes(divisor: lo) {
            guard let got = q(x), got == x / lo else { return nil }
        }
        return lo
    }

    // MARK: - Proof

    /// Whether `tree` is the sequence LLVM emits for `x / divisor`
    /// (`TargetLowering::BuildSDIV` / `BuildUDIV`), up to the order of a
    /// commutative operation's operands. The sign correction may read the
    /// shifted or the unshifted quotient: an arithmetic shift keeps the sign
    /// bit, so both are the same bit.
    private static func isLLVMLowering(
        _ tree: AbstractValue, of x: AbstractValue, divisor: UInt64, signed: Bool
    ) -> Bool {
        func binary(_ op: AbstractBinaryOperator, _ a: AbstractValue, _ b: AbstractValue) -> AbstractValue {
            .binary(op, a, b)
        }
        func shift(_ op: AbstractBinaryOperator, _ value: AbstractValue, _ amount: Int) -> AbstractValue {
            amount > 0 ? binary(op, value, .immediate(UInt64(amount))) : value
        }
        var candidates: [AbstractValue] = []
        if signed {
            guard let c = MagicConstants.signed(Int64(bitPattern: divisor)) else { return false }
            let d = Int64(bitPattern: divisor), m = Int64(bitPattern: c.magic)
            let high = binary(.multiplyHigh, x, .immediate(c.magic))
            let adjusted = d > 0 && m < 0 ? binary(.add, high, x)
                : d < 0 && m > 0 ? binary(.subtract, high, x)
                : high
            let quotient = shift(.arithmeticShiftRight, adjusted, c.shift)
            candidates = [quotient, adjusted].map {
                binary(.add, quotient, binary(.shiftRight, $0, .immediate(63)))
            }
        } else {
            guard let c = MagicConstants.unsigned(divisor) else { return false }
            let high = binary(.unsignedMultiplyHigh, shift(.shiftRight, x, c.preShift), .immediate(c.magic))
            let body = c.isAdd
                ? binary(.add, binary(.shiftRight, binary(.subtract, x, high), .immediate(1)), high)
                : high
            candidates = [shift(.shiftRight, body, c.postShift)]
        }
        return candidates.contains { sameModuloCommutation($0, tree) }
    }

    private static func sameModuloCommutation(_ a: AbstractValue, _ b: AbstractValue) -> Bool {
        guard case .binary(let opA, let lhsA, let rhsA) = a,
              case .binary(let opB, let lhsB, let rhsB) = b, opA == opB
        else { return a == b }
        if sameModuloCommutation(lhsA, lhsB), sameModuloCommutation(rhsA, rhsB) { return true }
        switch opA {
        case .add, .multiply, .multiplyHigh, .unsignedMultiplyHigh, .bitAnd, .bitOr, .bitXor:
            return sameModuloCommutation(lhsA, rhsB) && sameModuloCommutation(rhsA, lhsB)
        default:
            return false
        }
    }

    // MARK: - Remainder

    /// `x - D * (x / D)`, however the multiply is spelled (`msub`, or shifts
    /// and adds), is `x % D`. The quotient has already folded to `x / D` by the
    /// time the remainder's last instruction is traced, so the tree is reduced
    /// to `a*x + b*q + c` with the quotient as its own unknown `q`, exactly, in
    /// wrapping arithmetic, and must come out as `x - D*q`: true for every `x`
    /// and `q`, so true at `q = x / D` whatever the division's signedness.
    private static func remainder(_ tree: AbstractValue) -> AbstractValue? {
        guard case .binary(let op, _, _) = tree, op == .add || op == .subtract else { return nil }
        var atoms: [AbstractValue] = []
        collectAtoms(tree, into: &atoms)
        guard atoms.count == 2 else { return nil }
        for (index, atom) in atoms.enumerated() {
            guard case .binary(let division, let x, .immediate(let divisor)) = atom,
                  division == .divide || division == .unsignedDivide,
                  x == atoms[1 - index]
            else { continue }
            guard let form = linearForm(tree, x: x, q: atom),
                  form == LinearForm(x: 1, q: 0 &- divisor, constant: 0)
            else { return nil }
            return .binary(division == .divide ? .remainder : .unsignedRemainder, x, .immediate(divisor))
        }
        return nil
    }

    /// `x * x + q * q + constant`, coefficients mod 2^64.
    private struct LinearForm: Equatable {
        var x: UInt64, q: UInt64, constant: UInt64
    }

    /// The exact linear form of a tree built from `x`, `q`, constants, `+`,
    /// `-`, multiplication by a constant and left shift by a constant; nil for
    /// anything nonlinear.
    private static func linearForm(_ value: AbstractValue, x: AbstractValue, q: AbstractValue) -> LinearForm? {
        if value == x { return LinearForm(x: 1, q: 0, constant: 0) }
        if value == q { return LinearForm(x: 0, q: 1, constant: 0) }
        func scaled(_ form: LinearForm, _ k: UInt64) -> LinearForm {
            LinearForm(x: form.x &* k, q: form.q &* k, constant: form.constant &* k)
        }
        switch value {
        case .immediate(let constant):
            return LinearForm(x: 0, q: 0, constant: constant)
        case .binary(.add, let lhs, let rhs), .binary(.subtract, let lhs, let rhs):
            guard let a = linearForm(lhs, x: x, q: q), let b = linearForm(rhs, x: x, q: q) else { return nil }
            if case .binary(.add, _, _) = value {
                return LinearForm(x: a.x &+ b.x, q: a.q &+ b.q, constant: a.constant &+ b.constant)
            }
            return LinearForm(x: a.x &- b.x, q: a.q &- b.q, constant: a.constant &- b.constant)
        case .binary(.multiply, let lhs, .immediate(let k)), .binary(.multiply, .immediate(let k), let lhs):
            return linearForm(lhs, x: x, q: q).map { scaled($0, k) }
        case .binary(.shiftLeft, let lhs, .immediate(let amount)) where amount < 64:
            return linearForm(lhs, x: x, q: q).map { scaled($0, 1 << amount) }
        default:
            return nil
        }
    }

    // MARK: - Concrete evaluation

    private static func isEvaluable(_ op: AbstractBinaryOperator) -> Bool {
        switch op {
        case .add, .subtract, .multiply, .bitAnd, .bitOr, .bitXor,
             .shiftLeft, .shiftRight, .arithmeticShiftRight,
             .multiplyHigh, .unsignedMultiplyHigh:
            return true
        default:
            return false
        }
    }

    private static func multiplyHighKinds(_ value: AbstractValue, signed: inout Bool, unsigned: inout Bool) {
        guard case .binary(let op, let lhs, let rhs) = value, isEvaluable(op) else { return }
        if op == .multiplyHigh { signed = true }
        if op == .unsignedMultiplyHigh { unsigned = true }
        multiplyHighKinds(lhs, signed: &signed, unsigned: &unsigned)
        multiplyHighKinds(rhs, signed: &signed, unsigned: &unsigned)
    }

    /// The distinct leaves the evaluator cannot compute: the unknowns.
    private static func collectAtoms(_ value: AbstractValue, into atoms: inout [AbstractValue]) {
        switch value {
        case .immediate:
            return
        case .binary(let op, let lhs, let rhs) where isEvaluable(op):
            collectAtoms(lhs, into: &atoms)
            collectAtoms(rhs, into: &atoms)
        default:
            if !atoms.contains(value) { atoms.append(value) }
        }
    }

    private static func evaluate(_ value: AbstractValue, bindings: [(AbstractValue, UInt64)]) -> UInt64? {
        switch value {
        case .immediate(let constant):
            return constant
        case .binary(let op, let lhs, let rhs) where isEvaluable(op):
            guard let a = evaluate(lhs, bindings: bindings),
                  let b = evaluate(rhs, bindings: bindings)
            else { return nil }
            switch op {
            case .add: return a &+ b
            case .subtract: return a &- b
            case .multiply: return a &* b
            case .bitAnd: return a & b
            case .bitOr: return a | b
            case .bitXor: return a ^ b
            case .shiftLeft: return b < 64 ? a << b : nil
            case .shiftRight: return b < 64 ? a >> b : nil
            case .arithmeticShiftRight:
                return b < 64 ? UInt64(bitPattern: Int64(bitPattern: a) >> Int64(b)) : nil
            case .multiplyHigh:
                return UInt64(bitPattern: Int64(bitPattern: a).multipliedFullWidth(by: Int64(bitPattern: b)).high)
            case .unsignedMultiplyHigh:
                return a.multipliedFullWidth(by: b).high
            default:
                return nil
            }
        default:
            return bindings.first { $0.0 == value }?.1
        }
    }

    // MARK: - Verification inputs

    /// Deterministic spread over every magnitude: an LCG, each draw also
    /// shifted right by a draw-dependent amount so small values appear too.
    private static let spread: [UInt64] = {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var values: [UInt64] = []
        for _ in 0 ..< 48 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            values.append(state)
            values.append(state >> (state & 63))
        }
        return values
    }()

    private static let multiples: [UInt64] = [1, 2, 3, 10, 1000, 1 << 20, 1 << 40]

    private static func signedProbes(magnitude d: Int64) -> [Int64] {
        var probes: [Int64] = [0, 1, -1, 2, -2, .max, .min, .max - 1, .min + 1]
        for k in multiples {
            let (base, overflow) = d.multipliedReportingOverflow(by: Int64(k))
            guard !overflow else { continue }
            probes += [base &- 1, base, base &+ 1, 0 &- base &- 1, 0 &- base, 0 &- base &+ 1]
        }
        let top = Int64.max / d * d
        probes += [top &- 1, top, 0 &- top, 0 &- top &+ 1]
        probes += spread.map { Int64(bitPattern: $0) }
        return probes
    }

    private static func unsignedProbes(divisor d: UInt64) -> [UInt64] {
        var probes: [UInt64] = [0, 1, 2, .max, .max - 1, 1 << 63, (1 << 63) - 1]
        for k in multiples {
            let (base, overflow) = d.multipliedReportingOverflow(by: k)
            guard !overflow else { continue }
            probes += [base &- 1, base, base &+ 1]
        }
        let top = UInt64.max / d * d
        probes += [top &- 1, top]
        probes += spread
        return probes
    }
}

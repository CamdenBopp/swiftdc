// Branches to a trap on the overflow or carry flag that are NOT the
// compiler's own overflow check, beside ones that are. A checked `a + b`
// lowers to `adds; b.vs trap` (signed) or `adds; b.hs trap` (unsigned),
// and `a - b` to `subs; b.vs trap` or `subs; b.lo trap`: the trap edge is
// the overflow edge and the flags are the arithmetic's own. Each function
// below names its lowering and when it traps.
//
// `subs; b.hs trap`: traps iff a >= b, the precondition, not an overflow.
@inline(never) public func preLess(_ a: UInt, _ b: UInt) -> UInt {
    precondition(a < b)
    return a &- b
}

// `adds; b.vc trap`: traps iff the add did NOT overflow.
@inline(never) public func preOverflowed(_ a: Int, _ b: Int) -> Int {
    let (r, o) = a.addingReportingOverflow(b)
    precondition(o)
    return r
}

// `fcmp d0, d0; b.vs trap`: V after a float compare is "unordered".
// Traps iff x is NaN.
@inline(never) public func preNotNaN(_ x: Double, _ k: Int) -> Int {
    precondition(!x.isNaN)
    return k &+ 1
}

// `subs; csel …, lo; cmp x8, x2; b.hs trap`: the flags are the compare's,
// not the subtraction's. Traps iff k >= n, where k is a - b or 0.
@inline(never) public func preAfterSubtract(_ a: UInt, _ b: UInt, _ n: UInt) -> UInt {
    let (d, o) = a.subtractingReportingOverflow(b)
    let k = o ? 0 : d
    precondition(k < n)
    return k
}

// The real checks, which fold: `adds; b.vs`, `adds; b.hs`, `subs; b.lo`.
@inline(never) public func checkedAdd(_ a: Int, _ b: Int) -> Int { a + b }
@inline(never) public func checkedAddUnsigned(_ a: UInt, _ b: UInt) -> UInt { a + b }
@inline(never) public func checkedSubtractUnsigned(_ a: UInt, _ b: UInt) -> UInt { a - b }

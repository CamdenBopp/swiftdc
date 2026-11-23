// Subset tests lowered to `bics` (-O).
//
// `bics d, n, m` computes n & ~m and sets N and Z from it, with C and V
// clear. A subset test needs only Z, so the destination is the zero
// register. Each function's true behaviour is its source.

public struct Access: OptionSet, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

@inline(never) public func consume(_ x: Int) { print(x) }

// `bics xzr, x1, x0; cset w0, eq`: true iff every bit of need is in have.
@inline(never) public func allows(_ have: Access, _ need: Access) -> Bool { have.contains(need) }

// `bics xzr, x0, x1; csel`: 11 iff a has a bit b lacks.
@inline(never) public func extraBits(_ a: UInt64, _ b: UInt64) -> Int { (a & ~b) != 0 ? 11 : 22 }

// `bics wzr, w0, w1; cset w0, eq`: the 32-bit form.
@inline(never) public func covered(_ a: UInt32, _ b: UInt32) -> Bool { (a & ~b) == 0 }

// `bics xzr, x1, x0; cinc`: consume(1) iff need is not a subset of have.
@inline(never) public func route(_ have: Access, _ need: Access) {
    if !have.isSuperset(of: need) { consume(1) } else { consume(2) }
}

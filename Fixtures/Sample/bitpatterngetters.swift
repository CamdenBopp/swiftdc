// At -Onone `Float.bitPattern` and `Double.bitPattern` are calls to the
// standard library's getters. Each takes its `self` in v0 and nothing in
// the integer registers, which still hold the caller's own formals or an
// earlier call's result.
//
// floatBits(p, k, m) = 1097 + 3 * bits(p.a) + 5 * bits(p.b) + 7 * k + 11 * m
// doubleBits(d, k) = bits(d) &+ k
// intHash(x, k) = x.hashValue &+ k
public struct TwoF {
    public var a: Float
    public var b: Float
    public init(a: Float, b: Float) { self.a = a; self.b = b }
}

@inline(never) public func floatBits(_ p: TwoF, _ k: Int, _ m: Int) -> Int {
    1097 &+ 3 &* Int(p.a.bitPattern) &+ 5 &* Int(p.b.bitPattern) &+ 7 &* k &+ 11 &* m
}

@inline(never) public func doubleBits(_ d: Double, _ k: Int) -> Int {
    Int(truncatingIfNeeded: d.bitPattern) &+ k
}

// The control: an integer receiver is in x0, the one register this call's
// arguments are read from. intHash(x, k) = x.hashValue &+ k
@inline(never) public func intHash(_ x: Int, _ k: Int) -> Int {
    x.hashValue &+ k
}

// A static getter of a float type has no `self` at all.
// staticBits(k) = bits(Float.pi) &+ k
@inline(never) public func staticBits(_ k: Int) -> Int {
    Int(Float.pi.bitPattern) &+ k
}

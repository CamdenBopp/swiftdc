// A small integer struct's non-mutating method takes its self's words in
// the general registers after its formals: `g(_ k:)` gets k in x0 and s in
// x1. Seeded only for a method with no formals, any method with one read
// `return ?` for `sub x0, x1, x0`.
//
// True behaviour: One.g(k) is s - k; One.h(a, b) is a * s + b;
// Two.r(k) is q - k (p in x1, q in x2); One.scaled(d) truncates d * s,
// with d in d0 and s in x0, the general bank's first register.
public struct One {
    public var s: Int
    public init(s: Int) { self.s = s }
    @inline(never) public func g(_ k: Int) -> Int { s &- k }
    @inline(never) public func h(_ a: Int, _ b: Int) -> Int { a &* s &+ b }
    @inline(never) public func scaled(_ d: Double) -> Int { Int(d * Double(s)) }
}

public struct Two {
    public var p: Int
    public var q: Int
    public init(p: Int, q: Int) { self.p = p; self.q = q }
    @inline(never) public func r(_ k: Int) -> Int { q &- k }
}

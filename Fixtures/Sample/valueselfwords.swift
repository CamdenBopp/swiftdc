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

// A struct of Doubles takes its self in the v registers after the float
// formals: `Point(x: 3.5, y: 4.25).length()` is `fmov d0, #3.5; fmov d1,
// #4.25; b length`, and `Point(x: 1.5, y: 2.5).scaled(7.0)` passes 7.0 in
// d0 and self in d1 and d2. Both read with no self at all. A payload enum
// and a struct mixing an Int and a Double also lost their self: the enum's
// words are not known here, and the mixed struct's field order across the
// two banks is not either, so each self is `?`.
public struct Point {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    @inline(never) public func length() -> Double { (x * x + y * y).squareRoot() }
    @inline(never) public func scaled(_ k: Double) -> Double { x * k + y }
}
public struct Mixed {
    public var a: Int
    public var f: Double
    public init(a: Int, f: Double) { self.a = a; self.f = f }
    @inline(never) public func mix(_ k: Int) -> Double { Double(a &+ k) * f }
}
public enum Shape {
    case none
    case pair(Int, Int)
    @inline(never) public func tag(_ k: Int) -> Int {
        switch self { case .none: return k; case .pair(let a, let b): return a &* b &+ k }
    }
}
@inline(never) public func callLength() -> Double { Point(x: 3.5, y: 4.25).length() }
@inline(never) public func callScaled() -> Double { Point(x: 1.5, y: 2.5).scaled(7.0) }
@inline(never) public func callMix() -> Double { Mixed(a: 11, f: 0.5).mix(13) }
@inline(never) public func callTag() -> Int { Shape.pair(301, 302).tag(303) }

// Noncopyable argument-layout probe. True behaviour per function.
@inline(never) public func sink(_ x: Int) { print(x) }
public final class Res { public var n = 0; public init() {} }

public struct Pair: ~Copyable {
    public var a: Int, b: Int
    public init(a: Int, b: Int) { self.a = a; self.b = b }
    deinit { sink(a) }               // deinit: sink(a)
}
public struct Big: ~Copyable {       // 5 words: passed indirectly
    public var a: Int, b: Int, c: Int, d: Int, e: Int
    public init(_ x: Int) { a = x; b = x; c = x; d = x; e = x }
    deinit { sink(e) }               // deinit: sink(e)
}
public struct Handle: ~Copyable {    // class field: deinit bumps r.n
    public let r: Res
    public init(_ r: Res) { self.r = r }
    deinit { r.n &+= 1 }
}
// returns k (x2) &* 3 ; p is x0,x1
@inline(never) public func afterPair(_ p: borrowing Pair, _ k: Int) -> Int { k &* 3 }
// returns k &* 5 ; big is an address in x0, k is x1
@inline(never) public func afterBig(_ big: borrowing Big, _ k: Int) -> Int { k &* 5 }
// returns k &* 5 ; big is an address in x0 (owned), k is x1; deinit runs sink(e)
@inline(never) public func afterBigConsumed(_ big: consuming Big, _ k: Int) -> Int { k &* 7 }
// returns big.c &+ k
@inline(never) public func bigField(_ big: borrowing Big, _ k: Int) -> Int { big.c &+ k }
// returns k &+ 1; inout big is address x0, k is x1
@inline(never) public func afterInoutBig(_ big: inout Big, _ k: Int) -> Int { big.a = k; return k &+ 1 }
// caller: afterPair(Pair(a: x, b: y), 11) -> 33 ; then deinit sink(x)
@inline(never) public func callPair(_ x: Int, _ y: Int) -> Int { let p = Pair(a: x, b: y); return afterPair(p, 11) }
// caller: afterBig(Big(x), 13) -> 65 ; then deinit sink(x)
@inline(never) public func callBig(_ x: Int) -> Int { let b = Big(x); return afterBig(b, 13) }
// returns h.r.n ; h is x0 (the Res object)
@inline(never) public func handleN(_ h: borrowing Handle) -> Int { h.r.n }
// consuming forwarding: returns k after consuming h (deinit increments h.r.n)
@inline(never) public func dropHandle(_ h: consuming Handle, _ k: Int) -> Int { _ = consume h; return k }
extension Pair {
    // consuming method with arg: returns a &+ b &+ k ; self is x0,x1 (not x20), k is x2? (self last: k x0, self x1,x2)
    public consuming func sum(_ k: Int) -> Int { a &+ b &+ k }
    // borrowing method: returns k &* 2
    public borrowing func twice(_ k: Int) -> Int { k &* 2 }
    // mutating: self in x20; sets b = k
    public mutating func setB(_ k: Int) { b = k }
}
extension Big {
    // borrowing method on indirect self: self address in x20; returns self.d &+ k
    public borrowing func plusD(_ k: Int) -> Int { d &+ k }
    // consuming method on indirect self: returns e &- k; deinit runs
    public consuming func minusE(_ k: Int) -> Int { e &- k }
}

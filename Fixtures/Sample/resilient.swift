// A module compiled with library evolution. Its public structs and enums
// are resilient: address-only at every function boundary, inside the
// module too, so each is passed as ONE pointer whatever its fields.
//
// IR: `afterPoint(ptr %0, i64 %1)`, `afterColor(ptr %0, i64 %1)`,
// `afterOne(ptr %0, i64 %1)`: the Int is always in x1.
public struct Point {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

public enum Color { case red, green, blue }

// One case: zero-sized when loadable, still a pointer when resilient.
public enum Only { case one }

// True behaviour: n * 5. Read with `p` exploded into x0 and x1 it showed
// `arg0.y * 5`.
@inline(never) public func afterPoint(_ p: Point, _ n: Int) -> Int { n &* 5 }

// True behaviour: n + 7. Read with the enum as a tag in x0 the Int was
// taken from x1 correctly but `c` named a pointer as a case.
@inline(never) public func afterColor(_ c: Color, _ n: Int) -> Int { n &+ 7 }

// True behaviour: n - 3. With the one-case enum taking no register the
// Int was read from x0, which holds the enum's address.
@inline(never) public func afterOnly(_ o: Only, _ n: Int) -> Int { n &- 3 }

// Reads through the pointer: p.y + n.
@inline(never) public func readPoint(_ p: Point, _ n: Int) -> Int { p.y &+ n }

// Two Doubles: an HFA in d0, d1 when loadable. True behaviour: n * 9.
public struct Vec {
    public var dx: Double
    public var dy: Double
    public init(dx: Double, dy: Double) { self.dx = dx; self.dy = dy }
}
@inline(never) public func afterVec(_ v: Vec, _ n: Int) -> Int { n &* 9 }

// Mixed banks: x0 and d0 when loadable. True behaviour: n * 13.
public struct Mixed {
    public var i: Int
    public var d: Double
    public init(i: Int, d: Double) { self.i = i; self.d = d }
}
@inline(never) public func afterMixed(_ m: Mixed, _ n: Int) -> Int { n &* 13 }

extension Point {
    // `self` is a pointer in x20, the Int in x0. True behaviour: n * 11.
    @inline(never) public func scaled(_ n: Int) -> Int { n &* 11 }
    // True behaviour: self.x + n, read through x20.
    @inline(never) public func shifted(_ n: Int) -> Int { x &+ n }
}
extension Vec {
    // True behaviour: n * 17.
    @inline(never) public func scaled(_ n: Int) -> Int { n &* 17 }
}
extension Mixed {
    // True behaviour: n * 19.
    @inline(never) public func scaled(_ n: Int) -> Int { n &* 19 }
}

// A caller: passes the ADDRESS of a temporary holding `.blue`.
@inline(never) public func callColor(_ n: Int) -> Int { afterColor(.blue, n &+ 1) }

// A public protocol: a resilient module calls its requirements through
// exported dispatch thunks (`Tj`), which a plain module does not emit.
public protocol Shape { func area() -> Int }

// Not resilient, in the same module. A `@frozen` enum has no `enum case
// for …` descriptors and travels as its tag: `afterFixed(i8 %0, i64 %1)`.
// True behaviour: n + 21.
@frozen public enum Fixed { case a, b }
@inline(never) public func afterFixed(_ f: Fixed, _ n: Int) -> Int { n &+ 21 }

// An internal struct is never resilient: `innerSum(i64 %0, i64 %1, i64
// %2)`. Its descriptor is not exported. True behaviour: s.q + n.
struct Inner { var p: Int; var q: Int }
@inline(never) func innerSum(_ s: Inner, _ n: Int) -> Int { s.q &+ n }
@inline(never) public func callInner(_ n: Int) -> Int { innerSum(Inner(p: n, q: n &+ 1), n) }

// `firstAfterOnly(ptr %0, i64 %1, i64 %2)`. True behaviour: a + 30, a in
// x1. With the one-case enum taking no register, x1 was seeded as `b` and
// this read `arg2 + 30`.
@inline(never) public func firstAfterOnly(_ o: Only, _ a: Int, _ b: Int) -> Int { a &+ 30 }

extension Point {
    // A getter of a resilient struct: self by address in x20, nothing else.
    @inline(never) public var total: Int { x &+ y }
}
// Calls of that getter. The receiver is an address the caller computes;
// where it is not tracked the call still has a receiver: `total.getter(self:
// ?)`, never `total.getter()`.
@inline(never) public func totalOfFirst(_ ps: [Point]) -> Int { ps[0].total }
@inline(never) public func totalOf(_ p: Point) -> Int { p.total &+ 1 }
public final class Holder {
    public var p: Point
    public init(p: Point) { self.p = p }
    @inline(never) public func total() -> Int { p.total }
}

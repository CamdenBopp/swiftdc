// A register that holds a field of self across a call (-O). After
// `ldr x19, [x20, #0x10]`, or a store of x19 there, the tracer knows x19
// equals self.a, but only until something writes self.a again, and a call
// may: bumpA increments it. stale's `str x19, [x20, #0x18]` after the call
// rendered `self.b = self.a`, which reads as the incremented a, and
// staleReturn returned `self.a`.
//
// True behaviour: stale sets b to a's value before bumpA; storeTwice sets
// a = x, bumps a, then sets b = x; staleReturn bumps a and returns its old
// value; fresh bumps a and returns the new one (a load after the call).
public final class Box {
    public var a = 0
    public var b = 0
    @inline(never) public func bumpA() { a &+= 1 }
    @inline(never) public func stale() { let old = a; bumpA(); b = old }
    @inline(never) public func storeTwice(_ x: Int) { a = x; bumpA(); b = x }
    @inline(never) public func staleReturn() -> Int { let old = a; bumpA(); return old }
    @inline(never) public func fresh() -> Int { bumpA(); return a }
}

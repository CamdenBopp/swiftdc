// Value-type methods: the formal parameters come from x0, and then, unless
// the method is mutating (`self` by address in x20), `self`'s words.
// True behaviour: `newline` calls `append("\n")`; `appendBoxed` calls
// `append(_:)` with one String argument loaded through a pointer;
// `mix` calls `Hasher._combine(_:)` with one argument; `use` calls the
// non-mutating `Meter.scaled(k)` with k in x0 and self's one word, v, in x1;
// `appendTwo` calls `append(_:)` twice, one argument each.
@inline(never) public func newline(_ s: inout String) { s.append("\n") }
@inline(never) public func appendBoxed(_ s: inout String, _ box: UnsafePointer<String>) { s.append(box.pointee) }
@inline(never) public func mix(_ h: inout Hasher, _ v: UInt) { h.combine(v) }
public struct Meter {
    public var v: Int
    public init(v: Int) { self.v = v }
    @inline(never) public func scaled(_ k: Int) -> Int { v &* k }
}
@inline(never) public func use(_ v: Int, _ k: Int) -> Int { Meter(v: v).scaled(k) }
// Internal, so `strip -x` leaves it unnamed: an unnamed function's entry
// proves no register, and the tracer records no snapshot for its second
// call (libValueMethod.stripped.dylib).
// After the first append, which returns nothing, no register is known.
@inline(never) func appendTwo(_ s: inout String, _ a: String, _ b: String) {
    s.append(a)
    s.append(b)
}
@inline(never) public func appendBoth(_ s: inout String, _ a: String, _ b: String) {
    appendTwo(&s, a, b)
}

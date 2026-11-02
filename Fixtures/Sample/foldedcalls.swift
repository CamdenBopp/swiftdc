// Direct calls into an address the linker folded several functions onto.
//
// At -O, these lower to identical bodies that `ld` folds onto shared
// addresses under every symbol:
//
// - `Box.plus(x)` (x0 = x, x1 = self.a: a one-word struct self comes after
//   the formals) and the function-signature specialization of `pairPlus`,
//   which drops the dead `p.1` (x0 = p.0, x1 = y), are both
//   `add x0, x1, x0; ret`.
// - `pairPlus` itself (x0 = p.0, d0 = p.1, x1 = y) and `addTwo(a, b)`
//   (x0 = a, x1 = b) are both a tail call to that body.
//
// Each caller tail-calls the `add` body. That address is one of two
// functions, and nothing in the binary says which, so a call to it must
// take neither name nor either signature's argument layout. The true calls:
// `callPair()` is `pairPlus((3, 2.5), 4)`, which returns 7; `callAdd(_:)`
// is `addTwo(x, 5)`; `callBox(_:)` is `b.plus(6)`. The body reads x0 and
// x1, so `(3, 4)`, `(x, 5)` and `(6, b.a)` are what reaches it.

@inline(never) public func pairPlus(_ p: (Int, Double), _ y: Int) -> Int { p.0 &+ y }
@inline(never) public func addTwo(_ a: Int, _ b: Int) -> Int { a &+ b }

public struct Box {
    public var a: Int
    @inline(never) public func plus(_ x: Int) -> Int { a &+ x }
}

@inline(never) public func callPair() -> Int { pairPlus((3, 2.5), 4) }
@inline(never) public func callAdd(_ x: Int) -> Int { addTwo(x, 5) }
@inline(never) public func callBox(_ b: Box) -> Int { b.plus(6) }

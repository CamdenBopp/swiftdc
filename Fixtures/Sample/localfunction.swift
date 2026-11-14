// Local functions. One takes its captures after its formals, exactly as a
// closure does: `mix #1 (Int) -> Int in outer(_:_:)` is lowered to
// `(i64 k, i64 a, i64 b)`. Its printed name shows only `(Int)`.
//
// `$defer #1 () -> ()` is a local function too: no formals, only captures.
@inline(never) func sink(_ x: Int) {}
@inline(never) func external(_ x: Int) -> Int { x &* 3 }

// True behaviour: `mix(k)` computes k * a + b: three registers reach it.
@inline(never) public func outer(_ a: Int, _ b: Int, _ k: Int) -> Int {
    @inline(never) func mix(_ k: Int) -> Int { k &* a &+ b }
    return mix(k) &+ mix(k &+ 1)
}

// True behaviour: the defer body takes no formal; it captures nothing
// that needs a register here (it calls `sink(9)`), so its call has no
// argument. x0 at the call is `external`'s result.
@inline(never) public func deferred(_ x: Int) -> Int {
    defer { sink(9) }
    return external(x)
}

// The defer body captures `x`: one register, which is the capture.
@inline(never) public func deferredCapture(_ x: Int) -> Int {
    defer { sink(x) }
    return external(x &+ 1)
}

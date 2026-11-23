// A tail branch into a body that keeps x0 but may not return (-O, stripped).
//
// Each helper returns its first argument untouched, so its body never
// writes x0. Two of them can trap first and one can loop forever. A
// wrapper that tail-calls one is a single `b`. The helpers are internal:
// stripped, their bodies have no name, and the wrapper's branch is all
// that says they run. Each function's true behaviour is its source.

// `cbz x0, trap; ret`: traps when x is 0.
@inline(never) func nonZero(_ x: Int) -> Int { precondition(x != 0); return x }
// `cmp x1, #4; b.lt trap; ret`: traps when y < 4.
@inline(never) func aboveThree(_ x: Int, _ y: Int) -> Int { precondition(y > 3); return x }
// `cmp x0, #9; b.ne done; b .`: never returns when x is 9.
@inline(never) func unlessNine(_ x: Int) -> Int { if x == 9 { while true {} }; return x }
// A lone `ret`: the control. (The unused parameter keeps the wrapper
// from being folded onto it.)
@inline(never) func same(_ x: Int, _ unused: Int) -> Int { x }

@inline(never) public func wrapNonZero(_ x: Int) -> Int { nonZero(x) }
@inline(never) public func wrapAboveThree(_ x: Int, _ y: Int) -> Int { aboveThree(x, y) }
@inline(never) public func wrapUnlessNine(_ x: Int) -> Int { unlessNine(x) }
@inline(never) public func wrapSame(_ x: Int) -> Int { same(x, 4) }

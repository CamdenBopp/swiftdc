// Callers of a function whose result is `Never` (-Onone, -O, -Osize).
//
// `stop` and `halt` have no success value: each throws for a negative x
// and traps otherwise. A `try_apply` of one has an unreachable normal
// destination, so its caller runs on only along the error edge, and no
// register after the call is a result. Each function's true behaviour is
// its source.

public struct Stopped: Error { public init() {} }
public struct Halted: Error {
    public var code: Int
    public init(code: Int) { self.code = code }
}

// Throws for a negative x in x21, traps otherwise. x0 comes back as scratch.
@inline(never) public func stop(_ x: Int) throws -> Never {
    if x < 0 { throw Stopped() }
    fatalError()
}

// Throws for a negative x, traps otherwise. `Halted` is one Int, so its
// typed error comes back in x0 with x21 set: x0 after the call is the
// error's `code`.
@inline(never) public func halt(_ x: Int) throws(Halted) -> Never {
    if x < 0 { throw Halted(code: x) }
    fatalError()
}

// The opposite Never: `throws(Never)` cannot throw, and the result is an
// Int in x0. Returns x * 3.
@inline(never) public func ordinary(_ x: Int) throws(Never) -> Int { x &* 3 }

// Returns 1 for a negative x (the catch), traps otherwise.
@inline(never) public func caught(_ x: Int) -> Int {
    do { try stop(x) } catch { return 1 }
}

// Throws what `stop(x + 1)` throws, or traps. It never returns an Int.
@inline(never) public func relay(_ x: Int) throws -> Int {
    let next = x &+ 1
    try stop(next)
}

// Returns `code + 1` of the error `halt` threw, which is x + 1, for a
// negative x, and traps otherwise. The value read after the call is the
// error payload, not a result of `halt`.
@inline(never) public func haltCode(_ x: Int) -> Int {
    do throws(Halted) { try halt(x) } catch { return error.code &+ 1 }
}

// The control: returns `ordinary(x) + 1`, which is x * 3 + 1.
@inline(never) public func useOrdinary(_ x: Int) -> Int { ordinary(x) &+ 1 }

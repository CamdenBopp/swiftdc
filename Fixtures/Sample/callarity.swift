// Fixture for call-site arguments laid out from the callee's signature.
// Built by `build.sh` into `libCallArity.dylib` (-Onone) and
// `libCallArity.opt.dylib` (-O). Each caller leaves a register live that is
// not an argument of the callee it calls.

@inline(never) public func one(_ a: Int) -> Int { a &* 3 }
@inline(never) public func none() -> Int { 42 }
@inline(never) public func mixed(_ a: Int, _ d: Double, _ b: Int) -> Double { Double(a &+ b) * d }
@inline(never) public func gen<T>(_ a: Int, _ t: T) -> Int { a }

// x1 still holds `b` at the call: `one` takes one argument.
public func callOne(_ a: Int, _ b: Int) -> Int { one(a) &+ b }
// x0 holds `one`'s result at the call: `none` takes no argument.
public func callNone(_ a: Int) -> Int { _ = one(a); return none() }
// The Double travels in d0, so `b` is the second integer register.
public func callMixed(_ a: Int, _ b: Int) -> Double { mixed(a, 2.5, b) }
// A generic callee is outside the first slice: unchanged.
public func callGen(_ a: Int, _ b: Int) -> Int { gen(a, b) }

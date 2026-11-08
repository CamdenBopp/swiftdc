// Scalar views of a zeroed vector register. Swift materialises a floating
// zero with `movi v0.2d, #0` (all 128 bits); a Double argument or return
// is d0, the register's low eight-byte lane.
// True behaviour: `laneZeroCall` passes 0.0 and `laneZeroReturn` returns 0.0.

@inline(never) public func laneTakes(_ d: Double) -> Double { d + 1 }

// `movi v0.2d, #0; bl laneTakes`: the argument is d0 = 0.0.
public func laneZeroCall() -> Double { laneTakes(0) }

// `movi v0.2d, #0; ret`: the return is d0 = 0.0.
public func laneZeroReturn() -> Double { 0 }

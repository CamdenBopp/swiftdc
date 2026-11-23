// LEVELS: O Osize
// A register counter with a constant start (countUp, -O): named and stepped.
// EXPECT structured O countUp :: var i = -3
// EXPECT structured O countUp :: i += 3
// FORBID structured * countUp :: x19 <ᵁ 0x3e5
@inline(never) public func sink(_ x: Int) { print(x) }
public func countUp() { var i = 0; while i < 1000 { sink(i); i += 3 } }

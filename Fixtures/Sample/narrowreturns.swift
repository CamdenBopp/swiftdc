// Computed results of narrow integer types (-O). The caller reads only the
// type's low bits, at its signedness, so `add16(0xffff)` is 0x47, not the
// 0x10047 left in w0: `add w0, w0, #0x48; ret`. True results: add16 =
// (x + 72) mod 2^16; add8 = Int8(truncatingIfNeeded: x + 100); mul32 =
// Int32(truncatingIfNeeded: x * y); shl16 = (x << 3) mod 2^16. `widen`
// returns Int: its `and x0, x8, #0xffff` is the source's own conversion.
@inline(never) public func takeInt(_ x: Int) -> Int { x &* 3 }
public func add16(_ x: UInt16) -> UInt16 { x &+ 72 }
public func add8(_ x: Int8) -> Int8 { x &+ 100 }
public func mul32(_ x: Int32, _ y: Int32) -> Int32 { x &* y }
public func widen(_ x: UInt16) -> Int { Int(x &+ 72) }
public func shl16(_ x: UInt16) -> UInt16 { x << 3 }

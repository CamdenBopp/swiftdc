// Integer-to-float conversions (-O). True behaviour: u2d returns k's bits
// as a UInt converted to Double (1.8e19 for k = -1); s32 returns c as a
// Double (-1.0 for c = -1); u32 returns u as a Double.
@inline(never) public func u2d(_ k: Int) -> Double { Double(UInt(bitPattern: k)) }
@inline(never) public func s32(_ c: Int32) -> Double { Double(c) }
@inline(never) public func u32(_ u: UInt32) -> Double { Double(u) }

// A pure scalar result whose lowering the value tracer does not model:
// -O counts bits with the vector `cnt` and `addv`. Keep unknown-return
// coverage separate from the modelled REV, CLZ and RBIT.
@inline(never) public func bitCount(_ x: UInt64) -> Int {
    x.nonzeroBitCount
}

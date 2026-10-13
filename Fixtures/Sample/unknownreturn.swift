// A pure scalar result whose CLZ lowering is intentionally not modelled by
// the value tracer. Keep unknown-return coverage separate from supported REV.
@inline(never) public func leadingZeros(_ x: UInt64) -> Int {
    x.leadingZeroBitCount
}

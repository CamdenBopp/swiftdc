// A throwing function whose error path and normal path share the `ret`
// (-O). True behaviour: plainThrow throws E(code: x) when x < 0, and
// returns x * 3 otherwise; swift_willThrow returns nothing, so x0 on the
// throwing path is no result.
public struct E: Error { public var code: Int }
@inline(never) public func plainThrow(_ x: Int) throws -> Int {
    if x < 0 { throw E(code: x) }
    return x &* 3
}

// Compile inside TypedErrorProbe alongside the original provider.
@frozen public struct FourValue {
    public let a, b, c, d: UInt64

    public init(_ value: UInt64) {
        a = value
        b = value &+ 1
        c = value &+ 2
        d = value &+ 3
    }
}

@inline(never)
public func probeFour(_ mode: Int) throws(TinyFailure) -> FourValue {
    if mode == 0 { throw .gamma }
    return FourValue(9013)
}

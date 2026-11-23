public enum TinyFailure: Error {
    case alpha, beta, gamma
}

public struct BigValue {
    public let a, b, c, d, e: UInt64

    public init(_ value: UInt64) {
        a = value
        b = value &+ 1
        c = value &+ 2
        d = value &+ 3
        e = value &+ 4
    }
}

@inline(never)
public func probeDirect(_ mode: Int) throws(TinyFailure) -> (Double, UInt64) {
    if mode == 0 { throw .gamma }
    return (2.75, 7003)
}

@inline(never)
public func probeIndirect(_ mode: Int) throws(TinyFailure) -> BigValue {
    if mode == 0 { throw .gamma }
    if mode < 0 { throw .beta }
    return BigValue(8007)
}

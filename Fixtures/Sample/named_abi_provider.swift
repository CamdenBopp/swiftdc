// These SDK spellings name foreign Swift ABIs, not the system declarations.
public enum NamedABIFailure: Error { case negative }

@_silgen_name("getpid")
@inline(never) public func providerPID(_ value: Double) throws -> Double {
    if value < 0 { throw NamedABIFailure.negative }
    return value + 0.5
}
@_silgen_name("sqrt")
@inline(never) public func providerSqrt(_ value: Int64) throws -> Int64 {
    if value < 0 { throw NamedABIFailure.negative }
    return value &+ 37
}
@_silgen_name("free")
@inline(never) public func providerFree(_ value: Int64) throws -> Int64 {
    if value < 0 { throw NamedABIFailure.negative }
    return value &+ 41
}
@_silgen_name("CGRectInset")
@inline(never) public func providerRect(_ value: Int64) throws -> Int64 {
    if value < 0 { throw NamedABIFailure.negative }
    return value &+ 43
}
@_silgen_name("printf")
@inline(never) public func providerFormat(_ value: Double, _ weight: Int64) throws -> Int64 {
    if value < 0 { throw NamedABIFailure.negative }
    return (Int64(value) &* 3) &+ weight
}

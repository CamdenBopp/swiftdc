// A plain spelling and an SDK C spelling both name Swift error-ABI entries.
// Their caller lives in another image, so no local body summary can supply
// the error-register effect. A name alone proves neither entry is C.
public enum PlainErrorFailure: Error { case negative }

@_silgen_name("plain_error_raise")
@inline(never) public func raisePlainError(_ value: Int) throws -> Int {
    if value < 0 { throw PlainErrorFailure.negative }
    return value &+ 37
}

@_silgen_name("getpid")
@inline(never) public func raiseCatalogNamedError(_ value: Int) throws -> Int {
    if value < 0 { throw PlainErrorFailure.negative }
    return value &+ 37
}

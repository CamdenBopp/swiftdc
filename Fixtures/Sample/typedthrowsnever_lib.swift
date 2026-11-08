// The library half of the throws(Never) fixture, built at -O. `transform`
// takes its error type as a generic parameter, `throws(E)`. The
// always-emit-into-client wrappers below call it with three bindings of E,
// so the -O build specializes it for each and serializes the
// specializations; a client that uses a wrapper emits both the wrapper and
// the `generic specialization <serialized, …>` it calls (the client half is
// typedthrowsnever.swift, built at -Onone). This is the lowering behind the
// standard library's `Unicode.Scalar.withUTF8CodeUnits` specializations in
// sample.debug.
//
// Every specialization prints the unspecialized signature, `throws(A)`;
// only its substitution list says what A is.
//
// - `neverThrows` binds E to `Swift.Never`. No value of Never exists, so
//   that specialization cannot throw: its one exit returns `body(x) &+ 1`.
// - `typedThrows` binds E to `ProbeError`, a real error type. Its
//   specialization throws what the closure throws and must stay throwing.
// - `untypedThrows` binds E to `any Swift.Error`. It must stay throwing too.
//
// The closure arrives as a parameter, so a specialization calls it through
// `blr` and cannot see what it does to x21. At -Onone the client spills x21,
// tests it after the call and reloads it before `ret`.
public enum ProbeError: Error { case bad, worse }

@inlinable @inline(never)
public func transform<E: Error>(_ x: Int, _ body: (Int) throws(E) -> Int) throws(E) -> Int {
    let y = try body(x)
    return y &+ 1
}

@_alwaysEmitIntoClient
public func neverThrows(_ x: Int, _ body: (Int) -> Int) -> Int {
    transform(x, body)
}

@_alwaysEmitIntoClient
public func typedThrows(_ x: Int, _ body: (Int) throws(ProbeError) -> Int) throws(ProbeError) -> Int {
    try transform(x, body)
}

@_alwaysEmitIntoClient
public func untypedThrows(_ x: Int, _ body: (Int) throws -> Int) throws -> Int {
    try transform(x, body)
}

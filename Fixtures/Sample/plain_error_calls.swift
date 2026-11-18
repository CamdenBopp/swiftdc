// Both declarations use Swift's error ABI despite the raw symbol spelling.
// getpid binds to our separate provider, never to the system C function.
@_silgen_name("plain_error_raise")
func importedPlainError(_ value: Int) throws -> Int
@_silgen_name("getpid")
func importedCatalogNamedError(_ value: Int) throws -> Int

@inline(never) public func catchPlainProbe(_ value: Int) -> Int {
    do { return try importedPlainError(value) &+ 100 }
    catch { return -8 }
}

@inline(never) public func catchCatalogProbe(_ value: Int) -> Int {
    // A different result operation keeps the optimizer from merging the two
    // callers into an indirect function-pointer body and hiding this case.
    do { return try importedCatalogNamedError(value) &* 3 }
    catch { return -11 }
}

// These entries propagate errors rather than catch them. Their shared return
// must not be classified as normal solely because the imported name looks C.
@inline(never) public func forwardPlainProbe(_ value: Int) throws -> Int {
    try importedPlainError(value) &+ 17
}

@inline(never) public func forwardCatalogProbe(_ value: Int) throws -> Int {
    try importedCatalogNamedError(value) &* 7
}

// Real Swift heap objects make the assembly callers exercise the platform's
// swift_bridgeObjectRetain, rather than a same-named test replacement.
// Each caller constructs one token. The retained cases balance every strong
// reference; the immediate-return control transfers its reference to the test.
nonisolated(unsafe) private var made = 0
nonisolated(unsafe) private var destroyed = 0

private final class ResultIdentityToken {
    let value: Int
    init(_ value: Int) { self.value = value }
    deinit { destroyed += 1 }
}

@_cdecl("result_identity_make")
public func makeIdentityToken() -> UnsafeMutableRawPointer {
    made += 1
    return Unmanaged.passRetained(ResultIdentityToken(made + 6)).toOpaque()
}

@_cdecl("result_identity_sink")
public func readIdentityToken(_ pointer: UnsafeMutableRawPointer) -> Int {
    Unmanaged<ResultIdentityToken>.fromOpaque(pointer).takeUnretainedValue().value
}

@_cdecl("result_identity_destroy")
public func destroyIdentityToken(_ pointer: UnsafeMutableRawPointer) {
    Unmanaged<ResultIdentityToken>.fromOpaque(pointer).release()
}

@_cdecl("result_identity_count")
public func identityConstructionCount() -> Int { made }

@_cdecl("result_identity_destroyed")
public func identityDestructionCount() -> Int { destroyed }

@_cdecl("result_identity_reset")
public func resetIdentityCounts() { made = 0; destroyed = 0 }

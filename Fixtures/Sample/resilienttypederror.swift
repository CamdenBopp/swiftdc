// A resilient typed error adds an indirect SIL result before the formals.
import RemoteErrors
@inline(never) func remote<T>(_ type: T.Type, _ value: T, _ n: Int) throws(RemoteError) -> T {
    if n < 0 { throw .failed(n) }
    print(n)
    return value
}
public func useRemote(_ n: Int, _ value: Double) -> Double {
    do { return try remote(Double.self, value, n) } catch { return -1 }
}

// C ABI oracle: a nonnegative n returns value; a negative n returns -1.
@_cdecl("resilient_typed_error_probe")
public func nativeProbe(_ n: Int, _ value: Double) -> Double {
    useRemote(n, value)
}

// No dropped formal: the typed error alone must not veto substitution.
@inline(never) func keepValue<T>(_ value: T, _ n: Int) throws(RemoteError) -> T {
    if n < 0 { throw .failed(n &+ 1) }
    print(n &+ 1000)
    return value
}
public func useKeptValue(_ n: Int, _ value: Double) -> Double {
    do { return try keepValue(value, n) } catch { return -2 }
}
@_cdecl("resilient_typed_error_keep_probe")
public func nativeKeptProbe(_ n: Int, _ value: Double) -> Double {
    useKeptValue(n, value)
}

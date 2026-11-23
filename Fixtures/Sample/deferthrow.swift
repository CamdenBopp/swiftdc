// A throw that shares its exit block with the return (-O).
//
// A `defer` runs on every exit. At -O the throwing path and the normal
// path join before the deferred work, and one `ret` serves both: the
// work happens on the throwing path too, before the error leaves. Each
// function's true behaviour is its source.

public struct Refused: Error { public var code: Int }
public final class Ledger {
    public var entries: Int = 0
    public var last: Int = 0
    public init() {}
}
@inline(never) public func record(_ x: Int) { print(x) }

// Throwing path: allocate the error, then entries = 99, then throw.
// Normal path: last = x, then entries = 99, then return.
@inline(never) public func storeThenExit(_ ledger: Ledger, _ x: Int) throws {
    defer { ledger.entries = 99 }
    if x == 3 { throw Refused(code: 3) }
    ledger.last = x
}

// The same with a call for the deferred work: record(7) runs on both paths.
@inline(never) public func callThenExit(_ ledger: Ledger, _ x: Int) throws {
    defer { record(7) }
    if x == 3 { throw Refused(code: 3) }
    ledger.last = x
}

// The control: nothing is deferred, so the shared block is the epilogue
// alone and the throwing path ends in its throw.
@inline(never) public func plainExit(_ ledger: Ledger, _ x: Int) throws {
    if x == 3 { throw Refused(code: 3) }
    ledger.last = x
}

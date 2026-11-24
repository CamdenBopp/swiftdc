// A caller that catches a typed error from a synchronous callee. A
// `throws(E)` function whose result and error are both direct returns the
// error in the result's integer registers, with x21 nonzero as the flag
// (swift/lib/IRGen/GenCall.cpp, combineResultAndTypedErrorType). After the
// call the caller tests x21 (`cbz`/`cbnz x21`): on the nonzero edge x0 is
// the error and the callee produced no result. Where the result or the
// error is indirect, x0 on that edge is undefined. Either way it is never
// the callee's result.
//
// Each path hands what it has to a function that is not inlined: the
// result on the normal path, the error in the catch. Both edges are then
// real branches that read x0, at -O as at -Onone, and each shows its value
// as a call's argument (the two paths share one `ret`, whose x0 is
// neither's alone). Every body has its own constants, so no two functions
// share code.

public struct Fault: Error {
    public var code: Int
    public init(code: Int) { self.code = code }
}

public enum Kind: UInt8, Error { case low = 1, mid = 2, high = 3 }

// n >= 0: returns n + 11. n < 0: throws Fault(code: 3n), the code in x0.
@inline(never) public func pick(_ n: Int) throws(Fault) -> Int {
    if n < 0 { throw Fault(code: n &* 3) }
    return n &+ 11
}

// fault.code ^ 0x55
@inline(never) public func report(_ fault: Fault) -> Int { fault.code ^ 0x55 }

// 5v
@inline(never) public func keep(_ v: Int) -> Int { v &* 5 }

// n >= 0: keep(n + 11). n < 0: report(Fault(code: 3n)) = 3n ^ 0x55.
// The argument of `report` is the error, not what `pick` returned.
public func caught(_ n: Int) -> Int {
    do { return try keep(pick(n)) } catch { return report(error) }
}

// n < 100: returns n + 23. Otherwise throws .high, the tag byte 3 in x0.
@inline(never) public func grade(_ n: Int) throws(Kind) -> Int {
    if n >= 100 { throw .high }
    return n &+ 23
}

// kind.rawValue + 300
@inline(never) public func tally(_ kind: Kind) -> Int { Int(kind.rawValue) &+ 300 }

// v - 9
@inline(never) public func hold(_ v: Int) -> Int { v &- 9 }

// n < 100: hold(n + 23). Otherwise tally(.high) = 303.
public func caughtKind(_ n: Int) -> Int {
    do { return try hold(grade(n)) } catch { return tally(error) }
}

// The result is in d0 and the error in x0: no register holds both.
// n >= 0: returns d * 2.5 + n. n < 0: throws Fault(code: n - 17).
@inline(never) public func scale(_ d: Double, _ n: Int) throws(Fault) -> Double {
    if n < 0 { throw Fault(code: n &- 17) }
    return d * 2.5 + Double(n)
}

// fault.code ^ 0x33
@inline(never) public func weigh(_ fault: Fault) -> Int { fault.code ^ 0x33 }

// n >= 0: (d * 2.5 + n) * 1.5. n < 0: Double(weigh(Fault(code: n - 17))).
public func caughtScale(_ d: Double, _ n: Int) -> Double {
    do { return try scale(d, n) * 1.5 } catch { return Double(weigh(error)) }
}

// Control, a callee with no result: x0 after it is the error or nothing.
public nonisolated(unsafe) var ledger = 0

// n >= 0: ledger += n. n < 0: throws Fault(code: n - 4).
@inline(never) public func note(_ n: Int) throws(Fault) {
    if n < 0 { throw Fault(code: n &- 4) }
    ledger &+= n
}

// fault.code ^ 0x71
@inline(never) public func audit(_ fault: Fault) -> Int { fault.code ^ 0x71 }

// n >= 0: n + 21 (and ledger += n). n < 0: audit(Fault(code: n - 4)).
public func caughtNote(_ n: Int) -> Int {
    do { try note(n); return n &+ 21 } catch { return audit(error) }
}

// Control, untyped throws: the error is the box in x21, and x0 on the
// error edge is whatever the callee left.
public struct Loose: Error { public var code: Int }

// n >= 0: returns n + 37. n < 0: throws Loose(code: n).
@inline(never) public func loose(_ n: Int) throws -> Int {
    if n < 0 { throw Loose(code: n) }
    return n &+ 37
}

// 41 for a Loose, 43 for anything else
@inline(never) public func describe(_ error: any Error) -> Int { error is Loose ? 41 : 43 }

// 7v
@inline(never) public func carry(_ v: Int) -> Int { v &* 7 }

// n >= 0: carry(n + 37). n < 0: describe(the error) = 41.
public func caughtLoose(_ n: Int) -> Int {
    do { return try carry(loose(n)) } catch { return describe(error) }
}

// Control, throws(Never): a function that cannot throw. There is no error
// edge and the result keeps its name. 13n + 1
@inline(never) public func sure(_ n: Int) throws(Never) -> Int { n &* 13 &+ 1 }

// v ^ 0x19
@inline(never) public func mark(_ v: Int) -> Int { v ^ 0x19 }

// mark(13n + 1)
public func useSure(_ n: Int) -> Int { mark(sure(n)) }

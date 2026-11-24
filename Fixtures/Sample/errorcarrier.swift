// Where a typed error travels. A function that throws a typed error
// returns with x21 non-zero. The error itself is in the result's registers
// only when the result and the error are both returned directly: the tag
// of a no-payload enum then takes the first integer register, x0. A result
// returned through memory moves the error to a buffer the caller passes,
// and x0 at the throw is undefined.
//
// The functions here are the direct side, each compiled as written. The
// indirect side with x0 poisoned is authored in errorcarrier.s, against the
// types declared here.

public enum Fault: Error { case low, mid, high }

// Four words: returned in x0 to x3.
public struct Quad {
    public let a, b, c, d: Int

    public init(_ value: Int) {
        a = value
        b = value &+ 1
        c = value &+ 2
        d = value &+ 3
    }
}

// Five words: one more than the registers a result may take, so it is
// returned through x8.
public struct Quint {
    public let a, b, c, d, e: Int

    public init(_ value: Int) {
        a = value
        b = value &+ 1
        c = value &+ 2
        d = value &+ 3
        e = value &+ 4
    }
}

// Direct result, direct error: throws .high (tag 2 in x0) iff mode == 0,
// else returns mode + 5.
@inline(never)
public func scalar(_ mode: Int) throws(Fault) -> Int {
    if mode == 0 { throw .high }
    return mode &+ 5
}

// A tuple in v0 and x0: throws .high (tag 2 in x0) iff mode == 0, else
// returns (2.5, mode).
@inline(never)
public func pair(_ mode: Int) throws(Fault) -> (Double, Int) {
    if mode == 0 { throw .high }
    return (2.5, mode)
}

// Labels name a tuple's elements and change nothing about where they
// travel: throws .high (tag 2 in x0) iff mode == 0, else returns
// (count: mode + 9, scale: 1.5) in x0 and v0.
@inline(never)
public func labelled(_ mode: Int) throws(Fault) -> (count: Int, scale: Double) {
    if mode == 0 { throw .high }
    return (count: mode &+ 9, scale: 1.5)
}

// A four-word struct in x0 to x3: throws .high (tag 2 in x0) iff
// mode == 0, else returns Quad(mode).
@inline(never)
public func quad(_ mode: Int) throws(Fault) -> Quad {
    if mode == 0 { throw .high }
    return Quad(mode)
}

// The compiler's own indirect throw: .high is stored through the error
// buffer iff mode == 0, and x0 is left as it was. Otherwise Quint(mode) is
// written through x8.
@inline(never)
public func quint(_ mode: Int) throws(Fault) -> Quint {
    if mode == 0 { throw .high }
    return Quint(mode)
}

// An async function hands its error to its caller's resume function:
// throws .high iff mode == 0, else returns mode + 5.
@inline(never)
public func later(_ mode: Int) async throws(Fault) -> Int {
    if mode == 0 { throw .high }
    return mode &+ 5
}

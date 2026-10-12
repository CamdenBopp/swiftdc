// A throw that falls into the normal epilogue. At -O the throwing path joins
// the return at one `ret`, with x21 the error on one path and the caller's
// zero on the other: `if (r0 < 0) { swift_willThrow(…) }; return r0` read as
// a function that always returns.
public enum MergedError: Error { case bad }

@inline(never) public func sink(_ x: Int) -> Int { x &+ 3 }

@inline(never) public func untypedCall(_ x: Int) throws -> Int {
    let y = sink(x)
    if y < 0 { throw MergedError.bad }
    return y
}

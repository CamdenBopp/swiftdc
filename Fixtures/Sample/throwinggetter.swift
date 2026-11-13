// Throwing getters whose storage type is a function type. The demangler
// prints an accessor as `name.getter : Type` and never shows `throws`, so
// `S.subscript.getter : (Swift.Int, Swift.Int) -> Swift.Int` looks like a
// non-throwing function signature. True behaviour: each caller arms x21
// with zero, calls the getter, and branches on x21 (`cbnz x21`): the catch
// path returns the negative constant, the normal path the value.
public struct Refused: Error { public init() {} }

@inline(never) func checked(_ x: Int) throws -> Int {
    if x < 0 { throw Refused() }
    return x &* 2
}

public struct S {
    public var base: Int
    @inline(never) public init(base: Int) { self.base = base }
    public var fn: (Int) -> Int {
        @inline(never) get throws { let b = try checked(base); return { $0 &+ b } }
    }
    public static subscript(i: Int) -> Int {
        @inline(never) get throws { try checked(i) }
    }
    public subscript(a: Int, b: Int) -> Int {
        @inline(never) get throws { try checked(a &+ b &+ base) }
    }
}

public func fnProp(_ s: S) -> Int {
    do { return try s.fn(4) } catch { return -5 }
}

public func staticSub(_ x: Int) -> Int {
    do { return try S[x] } catch { return -6 }
}

public func sub2(_ s: S, _ x: Int) -> Int {
    do { return try s[x, 2] &+ 100 } catch { return -8 }
}

// Throws of an error that already exists. Every `throw` stores the error
// in x21 and calls `swift_willThrow` with it; the function then returns
// with x21 still holding it, which is how its caller sees the throw.
// Only a fresh `swift_allocError` box was recognised, so each function
// here ended in an unresolved exit. True behaviour is in each comment.
public struct Refusal: Error { public var code: Int; public init(code: Int) { self.code = code } }

// throw e
@inline(never) public func rethrowIt(_ e: any Error) throws -> Int { throw e }

// if k == 0 { throw e }; return k
@inline(never) public func failIfZero(_ k: Int, _ e: any Error) throws -> Int {
    if k == 0 { throw e }
    return k
}

public final class Holder {
    public var stored: any Error
    public init(stored: any Error) { self.stored = stored }
    // throw self.stored
    @inline(never) public func raise() throws { throw stored }
}

@inline(never) func risky(_ k: Int) throws -> Int {
    if k < 0 { throw Refusal(code: k) }
    return k &* 2
}

// do { return try risky(k) } catch { throw error }: the caught error,
// thrown on.
@inline(never) public func passOn(_ k: Int) throws -> Int {
    do { return try risky(k) } catch { throw error }
}

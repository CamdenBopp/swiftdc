public final class K { public var v = 1; public init() {} }
// True: returns k.v + 1; `sending` does not change the ABI.
public func sendK(_ k: sending K) -> Int { k.v &+ 1 }
// True: returns x + 3.
public func optActor(_ x: Int, _ o: (any Actor)?) -> Int { x &+ 3 }
// True: returns x + 3.
public func anyActor(_ x: Int, _ o: any Actor) -> Int { x &+ 3 }
// True: returns x + 2 after calling f (an @isolated(any) closure).
public func isoAnyClosure(_ x: Int, _ f: @isolated(any) @Sendable () async -> Void) async -> Int { await f(); return x &+ 2 }

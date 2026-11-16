public final class K { public var v = 1; public init() {} }
public actor A4 { public var v = 1; public init() {} }
// True: returns k.v + 1.
public func plainK(_ k: K) -> Int { k.v &+ 1 }
// True: returns a.v + 1, caller already isolated to a.
public func isoA(_ a: isolated A4) -> Int { a.v &+ 1 }
// True: returns x + 3.
public func optAny(_ x: Int, _ o: (any AnyObject)?) -> Int { x &+ 3 }
// True: returns x + 3; isolation param unused.
public func isoAny(_ x: Int, _ i: isolated (any Actor)?) async -> Int { x &+ 3 }
// True: returns x + 3.
public func nonIsoAny(_ x: Int, _ i: (any Actor)?) async -> Int { x &+ 3 }

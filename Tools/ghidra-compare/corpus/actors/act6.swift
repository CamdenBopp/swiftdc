// Each returns x + 3 after nothing; async entry convention probes.
public func a1(_ x: Int, _ o: (any Actor)?) async -> Int { x &+ 3 }
public func a2(_ x: Int, _ o: any Actor) async -> Int { x &+ 3 }
public func a3(_ x: Int, _ o: AnyObject?) async -> Int { x &+ 3 }
public func a4(_ x: Int, _ o: Int) async -> Int { x &+ 3 }
public func a5(_ x: Int, _ o: any Sendable) async -> Int { x &+ 3 }

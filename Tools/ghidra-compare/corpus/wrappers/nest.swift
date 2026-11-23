public struct In { public var lo: Int; public var hi: Int }
public struct Out { public var inner: In; public var k: Int }
// true: returns c.hi - c.lo (x1 - x0)
public func flat(_ c: In) -> Int { c.hi &- c.lo }
// true: returns o.inner.hi - o.k (x1 - x2); Out is passed as three words x0,x1,x2
public func nested(_ o: Out) -> Int { o.inner.hi &- o.k }

// Parameters before an Int that are not one-register scalars, built -O.
// Each Int is in the register after the earlier parameters' words: a
// String takes x0 and x1, an Int? its payload x0 and tag x1, an inout one
// address, a StaticString three words, and an Array one storage pointer.
// True behaviour: each returns its Int parameter times its own constant
// (distinct, so the linker folds none of them together).
public func afterString(_ s: String, _ i: Int) -> Int { i &* 3 }
public func afterOptional(_ o: Int?, _ i: Int) -> Int { i &* 5 }
public func afterInout(_ x: inout Int, _ i: Int) -> Int { i &* 7 }
public func afterStaticString(_ s: StaticString, _ i: Int) -> Int { i &* 9 }
public func afterArray(_ xs: [Int], _ i: Int) -> Int { i &* 11 }
public func afterDictionary(_ d: [Int: Int], _ i: Int) -> Int { i &* 13 }
public func afterSet(_ s: Set<Int>, _ i: Int) -> Int { i &* 17 }

// A non-mutating method of a one-word struct takes its formal y in x0 and
// self's word in x1; callK's z is still in x2 from its own entry, no
// argument of k. True behaviour: callK returns a * 31 + y + z.
public struct W { public var a: Int; public init(a: Int) { self.a = a }
    @inline(never) public func k(_ y: Int) -> Int { a &* 31 &+ y } }
@inline(never) public func callK(_ a: Int, _ y: Int, _ z: Int) -> Int { W(a: a).k(y) &+ z }

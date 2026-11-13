import G
// area of makeShape(n): n*n via opaque witness
public func useOpaque(_ n: Int) -> Int { makeShape(n).area() }
// count of makeColl(n): 2
public func useColl(_ n: Int) -> Int { makeColl(n).count }
// existential open: area of any Shape
public func openIt(_ s: any Shape) -> Int { s.area() }
// generic call with conditional conformance: Pair<Int>(3,4) == Pair(3,4) -> true
public func pairEq(_ a: Int) -> Bool { Pair(a: a, b: 4) == Pair(a: 3, b: 4) }
// opaque parameter: area of x
public func someParam(_ x: some Shape) -> Int { x.area() }
// passes a pack across a module boundary: 3
public func usePack() -> Int { packCount(1, "a", 2.0) }
// generic subscript call: store[k, as: Int.self]
public func useSub(_ s: Store, _ k: String) -> Int? { s[k, as: Int.self] }

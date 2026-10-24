// Calls to generic specializations (-O). The demangler prints a
// specialization as the unspecialized declaration, `generic specialization
// <Swift.Double> of Specializations.bump<A where A: Swift.Numeric>(A) -> A`,
// and an `A` says nothing about where the argument travels: the Double
// specialization takes it in d0. Read from the printed `(A)`, the call took
// x0 positionally: `useDouble(d, n)` rendered `bump(arg1)`, passing n, and
// `returnDouble(d)` rendered `bump()`.
//
// True behaviour: useDouble calls bump<Double>(d) and stores the result,
// then stores n; useInt returns bump<Int>(n); returnDouble returns
// bump<Double>(d); count returns firstCount<[Int]>(a), whose parameter is a
// collection and whose result is its `Element`.
nonisolated(unsafe) public var dsink = 0.0
nonisolated(unsafe) public var isink = 0

@inline(never) public func bump<T: Numeric>(_ x: T) -> T { x + x }

@inline(never) public func firstCount<C: Collection>(_ c: C) -> C.Element? { c.first }

public func useDouble(_ d: Double, _ n: Int) { dsink = bump(d); isink = n }
public func useInt(_ n: Int) -> Int { bump(n) }
public func returnDouble(_ d: Double) -> Double { bump(d) }
public func count(_ a: [Int]) -> Int? { firstCount(a) }

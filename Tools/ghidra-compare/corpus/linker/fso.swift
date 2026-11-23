// Function-signature-optimization fixture (-O). True behaviour:
//  deadFirst(unused, x, y) = x*5 + y. FSO may drop `unused` (Arg[0] = Dead),
//   so in the specialized body x arrives in x0 and y in x1.
//  exploded(p: Pair, k) = p.b * k : FSO may explode Pair and drop the dead p.a.
//  constProp(x, k) with k always 7 -> constant propagated, x in x0.
struct Pair { var a: Int; var b: Int; var c: Int }
@inline(never) func deadFirst(_ unused: Int, _ x: Int, _ y: Int) -> Int { x &* 5 &+ y }
public func callDead(_ a: Int, _ b: Int) -> Int { deadFirst(a &* 2, a, b) &+ deadFirst(b, b, a) }
@inline(never) func exploded(_ p: Pair, _ k: Int) -> Int { p.b &* k &+ p.c }
public func callExploded(_ a: Int, _ b: Int, _ c: Int) -> Int { exploded(Pair(a: a, b: b, c: c), 9) &+ exploded(Pair(a: c, b: a, c: b), 11) }
@inline(never) func constProp(_ x: Int, _ k: Int) -> Int { x &* k &- 3 }
public func callConst(_ a: Int) -> Int { constProp(a, 7) &+ constProp(a &+ 1, 7) }

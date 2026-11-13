// Swift optimizer transforms fixture (-O, -enable-merge-functions).
// True behaviour:
//  sumAll<T: Numeric>(xs) sums; specialized for Int and Double ($s...Tf / Tg5 names).
//  applyTwice(f, x) = f(f(x)); called with a constant closure {$0 * 3} -> closure
//   specialization / capture propagation gives a specialized applyTwice.
//  mergeA/mergeB differ only in a constant -> may become a Tm merged body.
@inline(never) public func sumAll<T: Numeric>(_ xs: [T]) -> T {
  var s: T = 0
  for x in xs { s += x }
  return s
}
public func useInt(_ xs: [Int]) -> Int { sumAll(xs) }
public func useDouble(_ xs: [Double]) -> Double { sumAll(xs) }

@inline(never) func applyTwice(_ f: (Int) -> Int, _ x: Int) -> Int { f(f(x)) }
public func tripleTwice(_ x: Int) -> Int { applyTwice({ $0 * 3 }, x) }
public func addTwice(_ x: Int, _ k: Int) -> Int { applyTwice({ $0 + k }, x) }

public final class Box { public var a = 0; public var b = 0; public var c = 0; public init() {} }
@inline(never) public func mergeA(_ b: Box, _ v: Int) -> Int { b.a = v &* 17; b.c = v; return b.a &+ b.b &+ 1001 }
@inline(never) public func mergeB(_ b: Box, _ v: Int) -> Int { b.a = v &* 19; b.c = v; return b.a &+ b.b &+ 2002 }

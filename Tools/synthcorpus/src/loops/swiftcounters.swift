// LEVELS: O Osize Onone
// Counters seeded by a call or a field load, two counters stepping
// differently, and a counter read after the loop.
// TRUE behaviour:
//   fromCall():     var i = seed(); while i < 50 { sink(i); i += 1 }
//   fromField(b):   var i = b.lo; while i < b.hi { sink(i); i += 2 }
//   twoSteps(n):    var i = 0, j = n; while i < j { sink(j &- i); i &+= 3; j &-= 1 }
//   firstSquare(n): var i = 0; while i &* i < n { i &+= 1 }; return i
// twoSteps -O/-Osize: `cmp x20, x21; add x20, x20, #3; b.lt`. The flags
// read x20 before the add; raw `x20` at the branch is three past it.
// FORBID structured O,Osize twoSteps :: if (x20 < x21)
// firstSquare: `add x8, x8, #1; mul x9, x8, x8; cmp x9, x0; b.lt`. An empty
// body under that test hides the step and reads as an infinite loop.
// FORBID structured O,Osize firstSquare :: re:while \([^\n]*\) \{\n\s*\}
// fromCall steps x19 before `cmp x19, #0x32; b.ne`; fromField steps x20
// (`cmn x20, #2; add x20, x20, #2; b.vc header`, the guard is the back edge).
// FORBID structured O,Osize fromCall :: re:^(?![\s\S]*\b(x19|i) (=|\+=) )[\s\S]*if \(x19 != 0x32\)
// FORBID structured O,Osize fromField :: re:^(?![\s\S]*\b(x20|i) (=|\+=) )[\s\S]*while \(x20 < x8\)
// EXPECT structured * fromCall :: seed()
// EXPECT structured * fromField :: sink(
// EXPECT structured * twoSteps :: sink(
@inline(never) public func sink(_ x: Int) { print(x) }
@inline(never) public func seed() -> Int { Int.random(in: 0..<10) }
public final class Bounds { public var lo = 0; public var hi = 0; public init() {} }

public func fromCall() { var i = seed(); while i < 50 { sink(i); i += 1 } }
public func fromField(_ b: Bounds) { var i = b.lo; while i < b.hi { sink(i); i += 2 } }
public func twoSteps(_ n: Int) {
    var i = 0, j = n
    while i < j { sink(j &- i); i &+= 3; j &-= 1 }
}
public func firstSquare(_ n: Int) -> Int { var i = 0; while i &* i < n { i &+= 1 }; return i }

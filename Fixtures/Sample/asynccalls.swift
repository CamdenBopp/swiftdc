// Calls to async functions (-O). An async callee takes its context in x22
// and its formal parameters as a synchronous one does, from x0 and d0, or
// from x1 when x0 carries an indirect result. True behaviour: callBump
// calls bumpG() with no argument; callDbl passes d in d0 to dbl; callTwo
// passes a and b in x0 and x1 to twoArgs; callBig passes x to bigRes,
// whose 5-word result comes back through x0.
public struct Big5 { public var a, b, c, d, e: Int }
@inline(never) public func bumpG() async -> Int { 41 }
@inline(never) public func dbl(_ d: Double) async -> Double { d * 2 }
@inline(never) public func twoArgs(_ a: Int, _ b: Int) async -> Int { a &* 7 &+ b }
@inline(never) public func bigRes(_ x: Int) async -> Big5 { Big5(a: x, b: x &+ 1, c: 3, d: 4, e: 5) }
@inline(never) public func callBump() async -> Int { await bumpG() &+ 1 }
@inline(never) public func callDbl(_ d: Double) async -> Double { await dbl(d) + 1 }
@inline(never) public func callTwo(_ a: Int, _ b: Int) async -> Int { await twoArgs(a, b) &+ 3 }
@inline(never) public func callBig(_ x: Int) async -> Int { await bigRes(x).b }

// Struct, SIMD and closure parameters at -O. A struct's fields go to the
// register banks one by one (`Mix { Int, Double, Int }` takes x0, d0, x1),
// so the callee's name does not say which registers a call fills:
// `callMix(k)` passes k in x0, 1.5 in d0, 7 in x1 and 2.0 in d1, and must
// not render `fMix(arg0, 7)`, the 7 as the Double. `callPt(a, k)` passes
// a and 3.0 in d0, d1 and k in x0, not `fPt(arg1)`. `callSIMD(k)` passes
// the vector in q0 and k in x0, not `fSIMD(arg0)`. `callLead(k, a)` passes
// k in x0 before the Pt, which can still be shown.
public struct Mix { public var i: Int; public var d: Double; public var j: Int }
public struct Pt { public var x: Double; public var y: Double }
@inline(never) public func fMix(_ m: Mix, _ s: Double) -> Int { m.i &+ m.j &+ Int(m.d * s) }
@inline(never) public func fPt(_ p: Pt, _ k: Int) -> Double { p.x * Double(k) + p.y }
@inline(never) public func fClosure(_ f: (Int) -> Int, _ k: Int) -> Int { f(k) &+ 1 }
@inline(never) public func fSIMD(_ v: SIMD4<Float>, _ k: Int) -> Float { v[0] * Float(k) }
public func callMix(_ k: Int) -> Int { fMix(Mix(i: k, d: 1.5, j: 7), 2.0) }
public func callPt(_ a: Double, _ k: Int) -> Double { fPt(Pt(x: a, y: 3.0), k) }
public func callClosure(_ k: Int) -> Int { fClosure({ $0 &* 3 }, k) }
public func callSIMD(_ k: Int) -> Float { fSIMD(SIMD4<Float>(1, 2, 3, 4), k) }
@inline(never) public func fLead(_ k: Int, _ p: Pt) -> Double { p.x * Double(k) }
public func callLead(_ k: Int, _ a: Double) -> Double { fLead(k, Pt(x: a, y: 1.0)) }
// A value type's method takes its formals first and `self` after them
// (`self`'s Doubles in d after the Mix's): `p.scaled(Mix(i: k, d: 0.5, j: 2))`
// passes k in x0, 0.5 in d0, 2 in x1, then p's x and y in d1, d2.
extension Pt { @inline(never) public func scaled(_ m: Mix) -> Double { x * Double(m.i) + y * m.d } }
public func callScaled(_ p: Pt, _ k: Int) -> Double { p.scaled(Mix(i: k, d: 0.5, j: 2)) }
// `self` in an integer register after the formal's: `W(v: 9).take(Mix(i:
// k, d: 0.5, j: 3))` passes k in x0, 0.5 in d0, 3 in x1 and self's 9 in
// x2. Where the Mix ends is not known, so the 9 is not shown as an argument.
public struct W { public var v: Int }
extension W { @inline(never) public func take(_ m: Mix) -> Int { v &+ m.i &* m.j } }
public func callTake(_ k: Int) -> Int { W(v: 9).take(Mix(i: k, d: 0.5, j: 3)) }
// An Array, a Dictionary and a variadic parameter are one word each (a
// buffer reference), so the parameters after them are placed:
// `fArr(xs, k)` passes xs in x0 and k in x1, `fVar(1, 2, k: k)` passes
// the array of 1 and 2 in x0 and k in x1, `fDict(d, k)` d in x0, k in x1.
@inline(never) public func fArr(_ xs: [Int], _ k: Int) -> Int { xs.count &+ k }
@inline(never) public func fVar(_ xs: Int..., k: Int) -> Int { xs.count &* k }
@inline(never) public func fDict(_ d: [String: Int], _ k: Int) -> Int { d.count &- k }
public func callArr(_ xs: [Int], _ k: Int) -> Int { fArr(xs, k) }
public func callVar(_ k: Int) -> Int { fVar(1, 2, k: k) }
public func callDict(_ d: [String: Int], _ k: Int) -> Int { fDict(d, k) }
// A receiver of both banks: `md.f(3)` passes 3 in x0, then self's Int in
// x1 and its Double in d0. Part of `self` is no argument: rendered f(3).
public struct MD { public var i: Int; public var d: Double }
extension MD { @inline(never) public func f(_ k: Int) -> Int { k &+ i &+ Int(d) } }
public func callMD(_ i: Int) -> Int { MD(i: i &* 5, d: 2.5).f(3) }

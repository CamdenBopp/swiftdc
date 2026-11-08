// A struct's `self` passed after a method's formals, and as a getter's only
// words (-O). True behaviour: useConst(k) is `Pair(a: 3, b: 4).scaled(k) + 1`
// (k in x0, self's words 3 and 4 in x1 and x2), and useConstTotal(x) is
// `Pair(a: x, b: 4).total + 1` (self's words x and 4 in x0 and x1, the
// getter takes nothing else).
public struct Pair {
    public var a: Int
    public var b: Int
    @inline(never) public func scaled(_ k: Int) -> Int { a * k + b }
    public var total: Int { @inline(never) get { a &+ b &* 3 } }
}
@inline(never) public func useConst(_ k: Int) -> Int { Pair(a: 3, b: 4).scaled(k) &+ 1 }
@inline(never) public func useConstTotal(_ x: Int) -> Int { Pair(a: x, b: 4).total &+ 1 }

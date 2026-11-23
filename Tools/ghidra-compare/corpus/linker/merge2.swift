// Tm merge fixture. True behaviour: each kN(x) builds [x, x+1, CONST] and
// returns sumUp(array) where CONST is 100/200/300; the bodies differ only in
// CONST, so swift's merge-functions may make kN thunks over one Tm body
// with CONST as an extra argument (x1 or later).
@inline(never) public func sumUp(_ a: [Int]) -> Int { a.reduce(0, &+) }
public final class K { public var v: Int = 0; public init() {} }
@inline(never) public func k1(_ o: K, _ x: Int) -> Int { o.v = x; let a = [x, x &+ 1, 100, o.v]; return sumUp(a) &+ a.count }
@inline(never) public func k2(_ o: K, _ x: Int) -> Int { o.v = x; let a = [x, x &+ 1, 200, o.v]; return sumUp(a) &+ a.count }
@inline(never) public func k3(_ o: K, _ x: Int) -> Int { o.v = x; let a = [x, x &+ 1, 300, o.v]; return sumUp(a) &+ a.count }

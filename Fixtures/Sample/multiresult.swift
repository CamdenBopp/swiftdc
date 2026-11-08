// Calls whose results span registers, -O. Pair returns in x0 and x1, Mix
// in x0 and d0, PE as a payload in x0 and a tag in w1; the callers use one
// part. True behaviour: pairA is mkPair(x + 4).a + 2, mixI is
// mkMix(x + 17).i + 4, mixD is mkMix(x + 19).d + 2.5, peOn passes the
// payload n to takeInt; intCall (one register) is takeInt(x + 3) + 1.
public struct Pair { public var a: Int; public var b: Int }
public struct Mix { public var i: Int; public var d: Double }
public enum PE { case num(Int), none }
@inline(never) public func mkPair(_ x: Int) -> Pair { Pair(a: x &* 3, b: x &+ 5) }
@inline(never) public func mkMix(_ x: Int) -> Mix { Mix(i: x &* 7, d: Double(x) * 0.5) }
@inline(never) public func mkPE(_ x: Int) -> PE { x > 0 ? .num(x &* 11) : .none }
@inline(never) public func takeInt(_ x: Int) -> Int { x &* 13 }
@inline(never) public func pairA(_ x: Int) -> Int { mkPair(x &+ 4).a &+ 2 }
@inline(never) public func mixI(_ x: Int) -> Int { mkMix(x &+ 17).i &+ 4 }
@inline(never) public func mixD(_ x: Int) -> Double { mkMix(x &+ 19).d + 2.5 }
@inline(never) public func peOn(_ x: Int) -> Int { if case .num(let n) = mkPE(x &+ 1) { return takeInt(n) }; return 0 }
@inline(never) public func intCall(_ x: Int) -> Int { takeInt(x &+ 3) &+ 1 }

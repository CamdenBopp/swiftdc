// A protocol with a method its extension adds. Called on an existential,
// the method takes its formal in x0, Self's metadata in x1, the witness
// table in x2 and `self`, by address, in x20.
//
// EMShape.scaled(k) = area &* k.  EMBig.area = a &+ b &+ c &+ d.
// emMake(a, b) = EMBig(a: a, b: b, c: 1, d: 2) as any EMShape.
public protocol EMShape { var area: Int { get } }

extension EMShape {
    @inline(never) public func scaled(_ k: Int) -> Int { area &* k }
}

public struct EMBig: EMShape {
    public var a: Int, b: Int, c: Int, d: Int
    public init(a: Int, b: Int, c: Int, d: Int) { self.a = a; self.b = b; self.c = c; self.d = d }
    public var area: Int { a &+ b &+ c &+ d }
}

@inline(never) public func emMake(_ a: Int, _ b: Int) -> any EMShape {
    EMBig(a: a, b: b, c: 1, d: 2)
}

// Two more members extensions add. tilted takes a Double, in d0.
// emPlus extends a standard library value type: its `self` is one word
// after the formal, in x1, and x20 is not its receiver.
// EMShape.tilted(f) = area &+ Int(f).  Int.emPlus(k) = self &+ k &* 3.
extension EMShape {
    @inline(never) public func tilted(_ f: Double) -> Int { area &+ Int(f) }
}

extension Int {
    @inline(never) public func emPlus(_ k: Int) -> Int { self &+ k &* 3 }
}

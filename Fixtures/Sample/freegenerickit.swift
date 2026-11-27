// Module-level generic functions: neither has a `self`.
// gSize(k, v) = k &+ the size of A.
// gWeigh(v, k) = v.weight &* k.
public protocol FGWeighted { var weight: Int { get } }

@inline(never) public func gSize<A>(_ k: Int, _ v: A) -> Int {
    k &+ MemoryLayout<A>.size
}

@inline(never) public func gWeigh<A: FGWeighted>(_ v: A, _ k: Int) -> Int {
    v.weight &* k
}

// A generic method of a class does have a `self`: the control.
// FGBox.pick(k, w) = n &+ k &+ the size of B.
public final class FGBox {
    public var n: Int
    public init(n: Int) { self.n = n }
    @inline(never) public func pick<B>(_ k: Int, _ w: B) -> Int {
        n &+ k &+ MemoryLayout<B>.size
    }
}

// Compiler-made helpers that ARE the statement. An address-only value
// (here a struct holding `Any` and a weak reference, and an existential)
// is copied or assigned through an outlined helper or the existential
// assign helper, called as (source, destination, …). Hidden as runtime
// noise, each function below rendered with no store at all.
public final class K { public var v = 0; public init() {} }
public protocol Shape { func area() -> Int }
public struct AO {
    public var x: Any
    public weak var w: K?
    public var n: Int
}

public final class H {
    public var ao: AO
    public init(ao: AO) { self.ao = ao }
    // True behaviour: self.ao = a (`outlined assign with copy of AO`).
    @inline(never) public func setAO(_ a: AO) { ao = a }
}

// True behaviour: dst = src, then return dst.n.
@inline(never) public func assignAO(_ dst: inout AO, _ src: AO) -> Int { dst = src; return dst.n }

// True behaviour: a = b (`__swift_assign_boxed_opaque_existential_1`).
@inline(never) public func assignShape(_ a: inout any Shape, _ b: any Shape) { a = b }

// A copy into a fresh buffer: `outlined init with copy of AO`, the result.
@inline(never) public func copyAO(_ a: AO) -> AO { a }

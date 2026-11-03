// Calls to unspecialized generic functions (-O; specialization disabled).
// A generic value is passed by address; the type's metadata (and witness
// tables) follow the formals. True behaviour: useGen calls gen(n, w) with n
// in x0 and &w in x1 (metadata in x2); useSplit calls split(w, n), whose
// tuple result (A, Int) takes its buffer in x0, so &w is x1 and n x2;
// useIdentity calls identity(w), whose `-> A` result goes through x8.
public struct W { public var v: Int; public init(v: Int) { self.v = v } }
@inline(never) @_semantics("optimize.sil.specialize.generic.never")
public func gen<A>(_ n: Int, _ x: A) -> Int { n &* 3 }
@inline(never) @_semantics("optimize.sil.specialize.generic.never")
public func split<A>(_ x: A, _ n: Int) -> (A, Int) { (x, n &+ 1) }
@inline(never) @_semantics("optimize.sil.specialize.generic.never")
public func identity<A>(_ x: A) -> A { x }
public func useGen(_ w: W, _ n: Int) -> Int { gen(n, w) }
public func useSplit(_ w: W, _ n: Int) -> Int { split(w, n).1 }
public func useIdentity(_ w: W) -> Int { identity(w).v }

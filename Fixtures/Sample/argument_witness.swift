// Value-witness calls through metadata a function receives as an argument.
// Each generic function is internal and never specialized, so `strip -x`
// leaves it unnamed and its metadata is only an incoming register: the
// witness is `[[T - 8] + k]` and the call passes the same T as its last
// metadata argument.
//
// assignCopy: `a = b` is assignWithCopy (slot 3, `+0x18`) with
// (dest, src, T). release: dropping `x` is destroy (slot 1, `+0x8`) with
// (x, T). duplicate: copying `x` into a fresh buffer is initializeWithCopy
// (slot 2, `+0x10`) with (dest, src, T).

@_semantics("optimize.sil.specialize.generic.never") @inline(never)
func assignCopy<T>(_ a: inout T, _ b: T) { a = b }

@_semantics("optimize.sil.specialize.generic.never") @inline(never)
func release<T>(_ x: consuming T) { _ = consume x }

@_semantics("optimize.sil.specialize.generic.never") @inline(never)
func duplicate<T>(_ x: T, into box: UnsafeMutablePointer<T>) { box.initialize(to: x) }

public func useAssign(_ a: inout String, _ b: String) { assignCopy(&a, b) }
public func useRelease(_ x: [Int]) { release(x) }
public func useDuplicate(_ x: String, _ box: UnsafeMutablePointer<String>) { duplicate(x, into: box) }

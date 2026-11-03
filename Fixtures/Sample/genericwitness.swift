// Unspecialized generic functions (-O, specialization disabled). A value of
// a type parameter arrives as its address; after the formals come the type
// parameters' metadata, one register each in order, then witness tables.
// `pick<T>(Int, T, T) -> T` is (sret x8, k x0, a x1, b x2, T x3) and copies
// a or b through T's initializeWithCopy, slot 2 of [T - 8]:
// `initializeWithCopy value witness for A(&result, k > 0 ? a : b)`.
// `first<T, U>(T, U) -> T` gets T in x2 and U in x3 and copies a T: its
// witness is A's, not B's. `dup<T>(T) -> (T, T)` returns a tuple with a
// generic element, whose buffers come first (x0, x1; the T in x2), so its
// registers are not seeded.
@_semantics("optimize.sil.specialize.generic.never")
@inline(never) public func pick<T>(_ k: Int, _ a: T, _ b: T) -> T { k > 0 ? a : b }
@_semantics("optimize.sil.specialize.generic.never")
@inline(never) public func first<T, U>(_ t: T, _ u: U) -> T { t }
@_semantics("optimize.sil.specialize.generic.never")
@inline(never) public func dup<T>(_ x: T) -> (T, T) { (x, x) }
// A generic function with only scalar formals (an Int and a pointer): T's
// metadata is in x2, and returning the pointee copies it through T's
// initializeWithCopy: `initializeWithCopy value witness for A(&result, arg1)`.
@_semantics("optimize.sil.specialize.generic.never")
@inline(never) public func load<T>(_ k: Int, _ p: UnsafePointer<T>) -> T { p[k] }
// `wrap` stores Optional's tag through T's storeEnumTagSinglePayload.
@_semantics("optimize.sil.specialize.generic.never")
@inline(never) public func wrap<T>(_ k: Int, _ p: UnsafePointer<T>) -> T? { k > 0 ? p.pointee : nil }

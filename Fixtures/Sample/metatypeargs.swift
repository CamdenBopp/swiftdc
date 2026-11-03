// Metatype parameters (-O). A generic parameter's metatype is its metadata
// pointer and a class's metatype is thick, one word each, so the parameters
// after them are placed: `describe(Int.self, k)` passes Int's metadata in
// x0 and k in x1 (then the metadata again, as T's generic argument);
// `classMeta(Base.self, k)` passes Base's metadata in x0 and k in x1. A
// struct's metatype is thin and takes no register: not placed.
public class Base { public init() {} }
@_semantics("optimize.sil.specialize.generic.never")
@inline(never) public func describe<T>(_ t: T.Type, _ k: Int) -> Int { k &* MemoryLayout<T>.size }
@inline(never) public func classMeta(_ c: Base.Type, _ k: Int) -> Int { k &+ (c == Base.self ? 1 : 2) }
public func callDescribe(_ k: Int) -> Int { describe(Int.self, k) }
public func callClassMeta(_ k: Int) -> Int { classMeta(Base.self, k) }
// A generic method of a value type: its formals (T's metatype, k), then
// `self`'s word, then T's metadata. Only the formals are its arguments.
public struct Box { public var v: Int; public init(v: Int) { self.v = v } }
extension Box {
    @_semantics("optimize.sil.specialize.generic.never")
    @inline(never) public func put<T>(_ t: T.Type, _ k: Int) -> Int { v &+ k &+ MemoryLayout<T>.size }
}
public func callPut(_ b: Box, _ k: Int) -> Int { b.put(Int.self, k) }

public protocol P { func f() -> Int }
public protocol Q {}
public protocol Src<Out> { associatedtype Out; func next() -> Out }
public protocol Pair2<A, B> { associatedtype A; associatedtype B }
public class Base { public init() {} }
// metatype of existential vs existential metatype
public func m1(_ t: any P.Type) -> Int { 1 }     // existential metatype: any type conforming to P
public func m2(_ t: (any P).Type) -> Int { 2 }   // the metatype of the existential box type itself
// constrained existential of a user protocol with primary assoc
public func pa(_ s: any Src<Int>) -> Int { s.next() }
public func pa2(_ s: any Pair2<Int, String>) -> Int { 0 }
// pack with conformance requirement
public func allEq<each T: Equatable>(_ a: repeat each T, b: repeat each T) -> Bool {
  for (x, y) in repeat (each a, each b) { if x != y { return false } }
  return true
}
// two packs, same shape
public func zipCount<each T, each U>(_ t: repeat each T, u: repeat each U) -> Int where (repeat (each T, each U)): Any { 0 }
// superclass and AnyObject constraints
public func sup<T: Base>(_ x: T) -> T { x }
public func obj<T: AnyObject>(_ x: T) -> T { x }
// constrained extension members
public struct Wrap<T> { public var v: T; public init(_ v: T) { self.v = v } }
extension Wrap where T == Int { public func double() -> Int { v * 2 } }
extension Wrap where T: P { public func call() -> Int { v.f() } }
extension Wrap: P where T: P & Q { public func f() -> Int { v.f() } }
// generic class with superclass generic
public class GB<T> { public var x: T; public init(_ x: T) { self.x = x } }
public final class GD: GB<Int> { public override init(_ x: Int) { super.init(x) } }
// recursive generic class constraint
public protocol Cmp { associatedtype Me: Cmp where Me.Me == Me }
// opaque with composition
public func opq() -> some P & Q { W() }
public struct W: P, Q { public init() {}; public func f() -> Int { 9 } }
// existential with class composition and metatype
public func cm(_ t: (Base & P).Type) -> Int { 3 }
// throwing generic with typed throws
public enum E: Error { case bad }
public func tthrow<T>(_ x: T) throws(E) -> T { throw .bad }
// generic subscript with static
public struct S2 { public init() {}; public static subscript<T>(_ t: T.Type) -> Int { 4 } ; public subscript(i: Int, j j: Int) -> Int { i + j } }
// pack-typed stored property in class
public final class PB<each T> { public var vals: (repeat each T); public init(_ v: repeat each T) { vals = (repeat each v) } }
// variadic generic param in existential position
public func anyPack<each T>(_ v: repeat each T) -> [Any] { var r: [Any] = []; for x in repeat each v { r.append(x) }; return r }

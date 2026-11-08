// A formal built from a type parameter can be a metadata source: IRGen's
// PolymorphicConvention then derives that parameter from the formal and
// does not pass its metadata (-O). `keep<T, U>(_ b: Box<T>, _ u: U)` takes
// b in x0, u's address in x1 and U's metadata in x2: T's comes from b's
// isa, so x2 is U's, the second parameter's, not the first's.
public final class Box<T> {
    public var item: T
    public init(_ item: T) { self.item = item }
}

public struct Pod<T> {
    public var item: T
    public init(_ item: T) { self.item = item }
}

// Each body has its own shape, so LLVM merges none of them.
@inline(never) func mark(_ n: Int) { print(n) }

// Baseline: nothing is a source, A in x2, B in x3.
@inline(never) public func plain<T, U>(_ t: T, _ u: U) -> U { mark(0); return u }

// A class built from a parameter.
@inline(never) public func keep<T, U>(_ b: Box<T>, _ u: U) -> U { mark(0); mark(1); return u }

// The parameter nested in a class's argument.
@inline(never) public func nested<T, U>(_ b: Box<[T]>, _ u: U) -> U { mark(0); mark(1); mark(2); return u }

// A class's metatype.
@inline(never) public func classType<T, U>(_ b: Box<T>.Type, _ u: U) -> U { mark(0); mark(1); mark(2); mark(3); return u }

// A struct's metatype.
@inline(never) public func structType<T, U>(_ b: Pod<T>.Type, _ u: U) -> U { mark(0); mark(1); mark(2); mark(3); mark(4); return u }

// An array's metatype.
@inline(never) public func arrayType<T, U>(_ b: [T].Type, _ u: U) -> U { mark(0); mark(1); mark(2); mark(3); mark(4); mark(5); return u }

// A class inside an Optional, an inout class and an array: not sources
// (the convention looks at the parameter's own type, and an inout is an
// address), so T's metadata is passed.
@inline(never) public func optional<T, U>(_ b: Box<T>?, _ u: U) -> U { mark(0); mark(1); mark(2); mark(3); mark(4); mark(5); mark(6); return u }
@inline(never) public func inoutBox<T, U>(_ b: inout Box<T>, _ u: U) -> U { mark(0); mark(1); mark(2); mark(3); mark(4); mark(5); mark(6); mark(7); return u }
@inline(never) public func array<T, U>(_ b: [T], _ u: U) -> U { mark(0); mark(1); mark(2); mark(3); mark(4); mark(5); mark(6); mark(7); mark(8); return u }

// A parameter whose superclass is built from another parameter.
@inline(never) public func bound<T: Box<V>, V, U>(_ t: T, _ u: U) -> U { mark(0); mark(1); mark(2); mark(3); mark(4); mark(5); mark(6); mark(7); mark(8); mark(9); return u }

// A class in a tuple: SIL explodes the tuple, so its element is a parameter
// of its own and a source.
@inline(never) public func tupled<T, U>(_ p: (Box<T>, Int), _ u: U) -> U { for i in 0 ..< 11 { mark(i) }; return u }

// `__owned` changes who releases b, not that it is a source.
@inline(never) public func owned<T, U>(_ b: __owned Box<T>, _ u: U) -> U { for i in 0 ..< 12 { mark(i) }; mark(99); return u }

// A closure taking a Box is no source: nothing reaches its metadata.
@inline(never) public func closure<T, U>(_ f: (Box<T>) -> Void, _ u: U) -> U { for i in 0 ..< 13 { mark(i) }; mark(98); mark(97); return u }

@inline(never) public func escaping<T, U>(_ f: @escaping (Box<T>) -> Void, _ u: U) -> U { for i in 0 ..< 13 { mark(i) }; mark(87); mark(86); mark(85); mark(84); return u }

// A non-generic superclass fulfills nothing: A's metadata is passed.
open class Base {
    public init() {}
}
@inline(never) public func plainBound<T: Base, U>(_ t: T, _ u: U) -> U { for i in 0 ..< 14 { mark(i) }; mark(96); mark(95); mark(94); return u }

// A parameter made equal to a member type stays canonical and keeps its
// metadata argument. One made equal to another parameter or a concrete type
// is not canonical and takes none (enumerateGenericSignatureRequirements).
public protocol Holder {
    associatedtype Item
}
@inline(never) public func sameMember<T: Holder, U, V>(_ t: T, _ u: U, _ v: V) -> V where U == T.Item { for i in 0 ..< 15 { mark(i) }; mark(93); return v }
@inline(never) public func sameParam<T, U, V>(_ t: T, _ u: U, _ v: V) -> V where U == T { for i in 0 ..< 16 { mark(i) }; mark(92); mark(91); return v }
@inline(never) public func sameConcrete<T, U>(_ t: T, _ u: U) -> U where T == Int { for i in 0 ..< 17 { mark(i) }; mark(90); mark(89); mark(88); return u }

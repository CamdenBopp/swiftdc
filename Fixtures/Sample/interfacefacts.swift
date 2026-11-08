// What `interface` says about a declaration against what the binary proves.
// Built -O, -Onone, and -O without reflection metadata.
import Foundation

// Constrained existentials, through every route a type reaches the printer:
// field, payload, superclass, witness, conformance requirement, signature.
public protocol One<A> { associatedtype A }
public protocol Two<X, Y> { associatedtype X; associatedtype Y }
public protocol Marker {}
public protocol MaybeCopied: ~Copyable {}
public class Box<T> {}
public class BoxedSequence: Box<any Sequence<Int>> {}
public struct Existentials {
    public var one: any One<Int>
    public var two: any Two<Int, String>
    public var optional: (any One<Int>)?
    public var array: [any One<Int>]
    public var composed: any One<Int> & Marker
    public var nested: any One<any Two<Int, String>>
    public init(one: any One<Int>, two: any Two<Int, String>, composed: any One<Int> & Marker, nested: any One<any Two<Int, String>>) {
        self.one = one; self.two = two; optional = nil; array = []; self.composed = composed; self.nested = nested
    }
}
public struct GenericExistential<T> { public var sequence: any Sequence<T>; public init(sequence: any Sequence<T>) { self.sequence = sequence } }
public final class ClassExistential { public var mutable: any One<Int>; let constant: any One<String>; public init(mutable: any One<Int>, constant: any One<String>) { self.mutable = mutable; self.constant = constant } }
public enum PayloadExistential { case one(any One<Int>), labelled(x: any Two<Int, String>, y: Int), none }
public struct Inverses: ~Copyable { public var bare: any ~Copyable; public var composed: any MaybeCopied & ~Copyable; public var copied: any MaybeCopied }
public struct WitnessExistential: One { public typealias A = any One<Int> }
extension Box: Marker where T == any One<Int> {}
public func takesTwo(_ x: any Two<Int, String>) -> any Two<String, Int> { fatalError() }
public func takesInverse(_ x: borrowing any ~Copyable) {}

// A member name is all these have: none of them declared the attribute.
public struct NotBuilder { public static func buildBlock(_ a: Int...) -> Int { 0 } }
public struct NotWrapper<V> { public var wrappedValue: V; public init(wrappedValue: V) { self.wrappedValue = wrappedValue }; public var projectedValue: Int { 1 } }
public struct NotDynamicMember { public subscript(dynamicMember m: String) -> Int { 1 } }
public struct NotDynamicCall { public func dynamicallyCall(withArguments a: [Int]) -> Int { 1 } }
public struct HandWritten { public var _a: NotWrapper<Int>; public var a: Int { get { _a.wrappedValue } set { _a.wrappedValue = newValue } } }
@propertyWrapper public struct RealWrapper<V> { public var wrappedValue: V; public var projectedValue: Int { 1 }; public init(wrappedValue: V) { self.wrappedValue = wrappedValue } }
public struct Wrapped { @RealWrapper public var a: Int = 1; public var c = 2; public init() {} }

// `@objc` thunks exist for some members of a name and not others.
public class ObjCMembers: NSObject {
    public init(t: Int) {}
    @objc public override init() {}
    @objc public func same(_ x: Int) {}
    public func same(_ x: String) {}
    @objc public var marked = 1
    public var plain = 2
}

// Enums and fields no record names, in the copy without reflection metadata;
// an `@objc` enum has no records in any copy.
@objc public enum ObjCEnum: Int { case a, b }
public enum Payloaded { case a, b(Int), c(String) }
public struct Stored { public var a = 1; public var b = "" ; public init() {} }
public final class StoredClass { public var a = 1; public init() {} }
public enum Caseless {}

// A global's storage: `__DATA,__data` is a `var`, `__const` a `let`, and
// zero-fill storage, which a lazily initialized global has, says neither.
public var globalVar = 1
public let globalLet = 2
public var globalArrayVar = [1]
public let globalArrayLet = [1]
public let globalLazyLet = Int.random(in: 0...3)
public var globalLazyVar = Int.random(in: 0...3)
var internalVar = 3
public func touchInternalVar() { internalVar += 1 }

// Offsets under a superclass another module may grow.
open class ResilientChild: JSONDecoder { public var extra = 1; open func added() {} }
open class FixedParent { public var a = 1; open func added() {}; public init() {} }

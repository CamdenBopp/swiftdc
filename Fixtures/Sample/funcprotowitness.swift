// A generic function receives its type parameters' metadata and then one
// witness table per conformance requirement, after its formal arguments
// (swift/docs/ABI/CallingConvention.rst, polymorphic parameters; -O,
// library evolution). `feed<T: Sink>(_ s: T, _ v: Int)` takes s's address
// in x0, v in x1, T's metadata in x2 and T's Sink table in x3, so `ldr x8,
// [x3, #8]; blr x8` is Sink's requirement 0 on T: `Sink.put(_:) witness
// for A`.
import Foundation

public protocol Sink {
    func put(_ v: Int)
    var level: Int { get }
    static var unit: Int { get }
}

public protocol Tap {
    func tap()
}

@inline(never) public func feed<T: Sink>(_ s: T, _ v: Int) -> Int {
    s.put(v)
    return s.level
}

// Two parameters: both metadata (x2, x3), then T's table (x4) and U's (x5).
@inline(never) public func pair<T: Sink, U: Sink>(_ a: T, _ b: U) {
    a.put(1)
    b.put(2)
}

// Two requirements on one parameter, in signature order: Sink's table, then
// Tap's.
@inline(never) public func both<T: Sink & Tap>(_ a: T) {
    a.tap()
    a.put(3)
}

// A bare parameter's metatype is inexact (it may be a subclass's), so IRGen
// takes no metadata from it: T's metadata is still passed (x1), and its
// table after it (x2).
@inline(never) public func unitOf<T: Sink>(_ t: T.Type) -> Int {
    t.unit
}

// The signature orders Sink before Swift.Hashable: Sink's table is the
// first (x2), whatever Hashable's needs.
@inline(never) public func hashed<T: Hashable & Sink>(_ s: T) -> Int {
    s.put(4)
    return s.hashValue
}

// An @objc protocol takes no table, and has no Swift descriptor here, so
// nothing proves where the tables after it are: Ping comes first in the
// signature, and Sink's table, in x2, is not named.
@objc public protocol Ping {
    func ping()
}

@inline(never) public func mixed<T: Ping & Sink>(_ a: T) {
    a.put(5)
}

// A class instance built from a type parameter is a metadata source: Box<T>
// carries T's metadata and table, so feedBox takes no separate ones.
public final class Box<T: Sink> {
    public var item: T
    public init(_ item: T) { self.item = item }
}

@inline(never) public func feedBox<T: Sink>(_ box: Box<T>) {
    box.item.put(6)
}

// A superclass requirement makes a class-bound parameter its own metadata
// source.
open class Base {
    public init() {}
}

@inline(never) public func based<T: Base & Sink>(_ t: T) {
    t.put(7)
}

// Ping takes no table, so Tap's is in x3, where the count above puts
// Sink's: a call through it must not be named after Sink.
@inline(never) public func mixedTap<T: Ping & Sink & Tap>(_ a: T) {
    a.tap()
}

// A layout requirement takes no table: Sink's is the only one (x2).
@inline(never) public func anyObject<T: AnyObject & Sink>(_ t: T) {
    t.put(8)
}

// A conformance of an associated type takes a table too (x3, after
// Holder's), but it is not for a parameter, so it is not named for one.
public protocol Holder {
    associatedtype Item
    var item: Item { get }
}

@inline(never) public func deep<H: Holder>(_ h: H) where H.Item: Sink {
    h.item.put(9)
}

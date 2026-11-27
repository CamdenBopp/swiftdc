// Generics, protocols and existentials: the opaque half (-Onone, -O, -Osize).
//
// This module is compiled on its own, without cross-module optimization, so
// no generic function here can be specialised by a client and no existential
// built here can be devirtualised by one. A generic function takes its type
// parameters' metadata after its formals, in declaration order, then one
// witness table per conformance requirement, in requirement order. Each
// function's true behaviour is its source; every implementation has its own
// weights, so a result names the implementation, the requirement and the
// values.

// MARK: protocols

// Witness table: [0] conformance descriptor, [1] r0, [2] r1, [3] r2,
// [4] the r3 getter. The slot is the requirement.
public protocol Shape4 {
    func r0(_ k: Int) -> Int
    func r1(_ k: Int) -> Int
    func r2(_ k: Int) -> Int
    var r3: Int { get }
}

extension Shape4 {
    // The default for the r2 requirement: only `Dflt` takes it.
    // r0(k) * 2 + r1(k) + 77.
    public func r2(_ k: Int) -> Int { r0(k) &* 2 &+ r1(k) &+ 77 }
    // Not a requirement: a generic function over Self, never a slot.
    // r1(k) * 5 + r3 + 606.
    @inline(never) public func ext(_ k: Int) -> Int { r1(k) &* 5 &+ r3 &+ 606 }
}

// [1] the static tagBase getter, [2] the tag getter.
public protocol Tagged {
    static var tagBase: Int { get }
    var tag: Int { get }
}

// [1] the nameCode getter, [2] named.
public protocol Named {
    var nameCode: Int { get }
    func named(_ k: Int) -> Int
}

// An associated type with a conformance: [1] the Item: Shape4 associated
// conformance, [2] the Item associated type, [3] the item getter, [4] weight.
public protocol Container {
    associatedtype Item: Shape4
    var item: Item { get }
    func weight() -> Int
}

// Class-constrained: an existential of it is two words (object, table).
// [1] bump, [2] the total getter, [3] scale.
public protocol Counter: AnyObject {
    func bump(_ k: Int) -> Int
    var total: Int { get }
    func scale(_ k: Int) -> Int
}

// MARK: implementations

// Two words: fits an existential's inline buffer.
public struct Small: Shape4, Tagged {
    public var p: Int
    public var q: Int
    public init(p: Int, q: Int) { self.p = p; self.q = q }
    @inline(never) public func r0(_ k: Int) -> Int { p &* 3 &+ q &* 5 &+ k &* 7 &+ 1000 }
    @inline(never) public func r1(_ k: Int) -> Int { p &* 11 &+ q &* 13 &+ k &* 17 &+ 2000 }
    @inline(never) public func r2(_ k: Int) -> Int { p &* 19 &+ q &* 23 &+ k &* 29 &+ 3000 }
    public var r3: Int { p &* 31 &+ q &* 37 &+ 4000 }
    public static var tagBase: Int { 50000 }
    public var tag: Int { p &* 41 &+ q &* 43 &+ 5000 }
}

// Four words: boxed in an existential.
public struct Large: Shape4, Tagged, Named {
    public var p: Int
    public var q: Int
    public var r: Int
    public var s: Int
    public init(p: Int, q: Int, r: Int, s: Int) { self.p = p; self.q = q; self.r = r; self.s = s }
    @inline(never) public func r0(_ k: Int) -> Int { p &* 2 &+ q &* 3 &+ r &* 5 &+ s &* 7 &+ k &* 11 &+ 10000 }
    @inline(never) public func r1(_ k: Int) -> Int { p &* 13 &+ q &* 17 &+ r &* 19 &+ s &* 23 &+ k &* 29 &+ 20000 }
    @inline(never) public func r2(_ k: Int) -> Int { p &* 31 &+ q &* 37 &+ r &* 41 &+ s &* 43 &+ k &* 47 &+ 30000 }
    public var r3: Int { p &* 53 &+ q &* 59 &+ r &* 61 &+ s &* 67 &+ 40000 }
    public static var tagBase: Int { 60000 }
    public var tag: Int { p &* 71 &+ q &* 73 &+ r &* 79 &+ s &* 83 &+ 6000 }
    public var nameCode: Int { p &* 89 &+ q &* 97 &+ r &* 101 &+ s &* 103 &+ 7000 }
    @inline(never) public func named(_ k: Int) -> Int { p &* 107 &+ q &* 109 &+ r &* 113 &+ s &* 127 &+ k &* 131 &+ 8000 }
}

// A class: one retained word in an existential's buffer.
public final class Klass: Shape4, Tagged, Named {
    public let p: Int
    public let q: Int
    public init(p: Int, q: Int) { self.p = p; self.q = q }
    @inline(never) public func r0(_ k: Int) -> Int { p &* 137 &+ q &* 139 &+ k &* 149 &+ 100000 }
    @inline(never) public func r1(_ k: Int) -> Int { p &* 151 &+ q &* 157 &+ k &* 163 &+ 200000 }
    @inline(never) public func r2(_ k: Int) -> Int { p &* 167 &+ q &* 173 &+ k &* 179 &+ 300000 }
    public var r3: Int { p &* 181 &+ q &* 191 &+ 400000 }
    public static var tagBase: Int { 70000 }
    public var tag: Int { p &* 193 &+ q &* 197 &+ 9000 }
    public var nameCode: Int { p &* 199 &+ q &* 211 &+ 11000 }
    @inline(never) public func named(_ k: Int) -> Int { p &* 223 &+ q &* 227 &+ k &* 229 &+ 12000 }
}

// Takes the default r2.
public struct Dflt: Shape4 {
    public var p: Int
    public init(p: Int) { self.p = p }
    @inline(never) public func r0(_ k: Int) -> Int { p &* 233 &+ k &* 239 &+ 500000 }
    @inline(never) public func r1(_ k: Int) -> Int { p &* 241 &+ k &* 251 &+ 600000 }
    public var r3: Int { p &* 257 &+ 700000 }
}

// A struct holding a class reference: its copy and destroy value witnesses
// retain and release.
public struct Ref: Shape4 {
    public var obj: Klass
    public var n: Int
    public init(obj: Klass, n: Int) { self.obj = obj; self.n = n }
    @inline(never) public func r0(_ k: Int) -> Int { obj.p &* 263 &+ obj.q &* 269 &+ n &* 271 &+ k &* 277 &+ 800000 }
    @inline(never) public func r1(_ k: Int) -> Int { obj.p &* 281 &+ obj.q &* 283 &+ n &* 293 &+ k &* 307 &+ 900000 }
    @inline(never) public func r2(_ k: Int) -> Int { obj.p &* 311 &+ obj.q &* 313 &+ n &* 317 &+ k &* 331 &+ 1000000 }
    public var r3: Int { obj.p &* 337 &+ obj.q &* 347 &+ n &* 349 &+ 1100000 }
}

public struct Crate: Container {
    public var item: Small
    public var w: Int
    public init(item: Small, w: Int) { self.item = item; self.w = w }
    @inline(never) public func weight() -> Int { w &* 353 &+ item.p &* 359 &+ 1200000 }
}

public final class Tally: Counter {
    public var total: Int
    public let step: Int
    public init(total: Int, step: Int) { self.total = total; self.step = step }
    // total += k * step; returns the new total.
    @inline(never) public func bump(_ k: Int) -> Int { total = total &+ k &* step; return total }
    @inline(never) public func scale(_ k: Int) -> Int { total &* 367 &+ step &* 373 &+ k &* 379 &+ 1300000 }
}

// MARK: generic functions, never specialised by a client

// x0 = n, x1 = &x, x2 = T. n * 3 + size(T) * 7 + 13.
@inline(never) public func gSize<T>(_ n: Int, _ x: T) -> Int {
    n &* 3 &+ MemoryLayout<T>.size &* 7 &+ 13
}

// x0 = n, x1 = &x, x2 = &y, x3 = T, x4 = U.
// n * 5 + size(T) * 100 + alignment(U) * 10000 + 17: size from T's value
// witnesses, alignment from U's, so swapped metadata changes the result.
@inline(never) public func gTwo<T, U>(_ n: Int, _ x: T, _ y: U) -> Int {
    n &* 5 &+ MemoryLayout<T>.size &* 100 &+ MemoryLayout<U>.alignment &* 10000 &+ 17
}

// x8 = result, x0 = &x, x1 = T. Copies x out (initializeWithCopy).
@inline(never) public func gId<T>(_ x: T) -> T { x }

// x8 = result, x0 = sel, x1 = &x, x2 = &y, x3 = T. x for an even sel, else y.
@inline(never) public func gPick<T>(_ sel: Int, _ x: T, _ y: T) -> T {
    sel & 1 == 0 ? x : y
}

// x0 = &x, x1 = k, x2 = T, x3 = T: Shape4. Each calls one slot.
@inline(never) public func gR0<T: Shape4>(_ x: T, _ k: Int) -> Int { x.r0(k) &+ 41 }
@inline(never) public func gR1<T: Shape4>(_ x: T, _ k: Int) -> Int { x.r1(k) &+ 43 }
@inline(never) public func gR2<T: Shape4>(_ x: T, _ k: Int) -> Int { x.r2(k) &+ 47 }
@inline(never) public func gR3<T: Shape4>(_ x: T, _ k: Int) -> Int { x.r3 &+ k &* 53 }

// x0 = &x, x1 = &y, x2 = k, x3 = T, x4 = U, x5 = T: Shape4, x6 = U: Shape4.
// x.r1(k) * 3 + y.r3 + 19.
@inline(never) public func gTwoC<T: Shape4, U: Shape4>(_ x: T, _ y: U, _ k: Int) -> Int {
    x.r1(k) &* 3 &+ y.r3 &+ 19
}

// x0 = &x, x1 = &y, x2 = k, x3 = T, x4 = U, x5 = U: Shape4 (T has none).
// y.r0(k) + size(T) * 1000003.
@inline(never) public func gMixed<T, U: Shape4>(_ x: T, _ y: U, _ k: Int) -> Int {
    y.r0(k) &+ MemoryLayout<T>.size &* 1000003
}

// x0 = &c, x1 = k, x2 = C, x3 = C: Container. Item's metadata and its
// Shape4 table come from the runtime (associated type and conformance).
// c.item.r1(k) * 3 + c.weight().
@inline(never) public func gAssoc<C: Container>(_ c: C, _ k: Int) -> Int {
    c.item.r1(k) &* 3 &+ c.weight()
}

// x0 = x (the object itself), x1 = k, x2 = T, x3 = T: Counter.
// bump(k) * 3 + total + scale(k) * 7, in that order (bump stores).
@inline(never) public func gClassBound<T: Counter>(_ x: T, _ k: Int) -> Int {
    let bumped = x.bump(k)
    return bumped &* 3 &+ x.total &+ x.scale(k) &* 7
}

public final class Holder<T> {
    public let first: T
    public let second: T
    public init(_ a: T, _ b: T) { first = a; second = b }
}

// Two copies of x into a class instance (initializeWithCopy twice), then
// first.r0(k) + second.r1(k) * 3, then the instance is destroyed.
@inline(never) public func gHold<T: Shape4>(_ x: T, _ k: Int) -> Int {
    let h = Holder(x, x)
    return h.first.r0(k) &+ h.second.r1(k) &* 3
}

// x0 = &a, x1 = &b, x2 = T. Exchanges through a temporary (take witnesses).
@inline(never) public func gSwap<T>(_ a: inout T, _ b: inout T) {
    let t = a
    a = b
    b = t
}

// x0 = &dst, x1 = &src, x2 = T. assignWithCopy.
@inline(never) public func gAssign<T>(_ dst: inout T, _ src: T) { dst = src }

// MARK: generic types

public struct GBox<T: Shape4> {
    public var v: T
    public var bias: Int
    public init(v: T, bias: Int) { self.v = v; self.bias = bias }
    // v.r1(k) + bias * 3. bias is at a field offset read from the metadata.
    @inline(never) public func apply(_ k: Int) -> Int { v.r1(k) &+ bias &* 3 }
}

open class GNode<T: Shape4> {
    public var v: T
    public var n: Int
    public init(v: T, n: Int) { self.v = v; self.n = n }
    // v.r2(k) + n * 5. Called through the vtable.
    open func visit(_ k: Int) -> Int { v.r2(k) &+ n &* 5 }
    // v.r0(k) + n * 7.
    open func probe(_ k: Int) -> Int { v.r0(k) &+ n &* 7 }
}

// MARK: existentials

// which & 7: 0 Small(a, b), 1 Large(a, b, c, c + 1), 2 Klass(a, b),
// 3 Dflt(a), otherwise Ref(Klass(a, b), c).
@inline(never) public func eMake(_ which: Int, _ a: Int, _ b: Int, _ c: Int) -> any Shape4 {
    switch which & 7 {
    case 0: return Small(p: a, q: b)
    case 1: return Large(p: a, q: b, r: c, s: c &+ 1)
    case 2: return Klass(p: a, q: b)
    case 3: return Dflt(p: a)
    default: return Ref(obj: Klass(p: a, q: b), n: c)
    }
}

// Opens s and calls slot 2. s.r1(k) + 23.
@inline(never) public func eR1(_ s: any Shape4, _ k: Int) -> Int { s.r1(k) &+ 23 }

// which & 1: 0 Small(a, b), 1 Klass(a, b).
@inline(never) public func eMake2(_ which: Int, _ a: Int, _ b: Int) -> any Shape4 & Tagged {
    which & 1 == 0 ? Small(p: a, q: b) : Klass(p: a, q: b)
}

// which & 1: 0 Large(a, b, c, c + 2), 1 Klass(a, b).
@inline(never) public func eMake3(_ which: Int, _ a: Int, _ b: Int, _ c: Int) -> any Named & Shape4 & Tagged {
    which & 1 == 0 ? Large(p: a, q: b, r: c, s: c &+ 2) : Klass(p: a, q: b)
}

// Two tables after the metadata. s.r0(k) * 3 + s.tag.
@inline(never) public func eComp2(_ s: any Shape4 & Tagged, _ k: Int) -> Int { s.r0(k) &* 3 &+ s.tag }

// Three tables after the metadata. s.named(k) + s.r3 * 3 + s.tag * 5.
@inline(never) public func eComp3(_ s: any Named & Shape4 & Tagged, _ k: Int) -> Int {
    s.named(k) &+ s.r3 &* 3 &+ s.tag &* 5
}

// which & 3: 0 the Int a, 1 Small(a, b), 2 Klass(a, b), 3 Large(a, b, a, b).
@inline(never) public func eMakeAny(_ which: Int, _ a: Int, _ b: Int) -> Any {
    switch which & 3 {
    case 0: return a
    case 1: return Small(p: a, q: b)
    case 2: return Klass(p: a, q: b)
    default: return Large(p: a, q: b, r: a, s: b)
    }
}

// An Int: i * 3 + 1. A Small: r3 + 2. A Klass: 3. Anything else: 4.
@inline(never) public func eAny(_ x: Any) -> Int {
    if let i = x as? Int { return i &* 3 &+ 1 }
    if let s = x as? Small { return s.r3 &+ 2 }
    if x is Klass { return 3 }
    return 4
}

// which & 1: 0 Klass(a, b), 1 Tally(total: a, step: b).
@inline(never) public func eMakeObj(_ which: Int, _ a: Int, _ b: Int) -> AnyObject {
    which & 1 == 0 ? Klass(p: a, q: b) : Tally(total: a, step: b)
}

// A Klass: r3 + 5. A Tally: total * 3 + 6. Anything else: 7.
@inline(never) public func eObj(_ x: AnyObject) -> Int {
    if let k = x as? Klass { return k.r3 &+ 5 }
    if let t = x as? Tally { return t.total &* 3 &+ 6 }
    return 7
}

// which & 3: 0 Small, 1 Large, otherwise Klass. Two words: metatype, table.
@inline(never) public func eMeta(_ which: Int) -> any Tagged.Type {
    switch which & 3 {
    case 0: return Small.self
    case 1: return Large.self
    default: return Klass.self
    }
}

// Calls the static slot. t.tagBase + 29.
@inline(never) public func eMetaBase(_ t: any Tagged.Type) -> Int { t.tagBase &+ 29 }

// Tally(total: a, step: b) as its class-constrained existential.
@inline(never) public func eCounter(_ a: Int, _ b: Int) -> any Counter { Tally(total: a, step: b) }

// c.bump(k) + c.scale(k) * 3 + 59.
@inline(never) public func eCount(_ c: any Counter, _ k: Int) -> Int {
    let bumped = c.bump(k)
    return bumped &+ c.scale(k) &* 3 &+ 59
}

// The underlying type is Large(a, b, a + b, a - b), hidden from clients.
@inline(never) public func makeOpaque(_ a: Int, _ b: Int) -> some Shape4 {
    Large(p: a, q: b, r: a &+ b, s: a &- b)
}

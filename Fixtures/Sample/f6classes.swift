// F6: classes, stored properties and method dispatch, in pure Swift.
//
// Every function under test is `(Int, Int, Int) -> Int`, `@inline(never)`,
// and public, so a driver can call it by its mangled name with three
// integers in x0, x1, x2 and read x0. All arithmetic wraps (`&+`, `&*`),
// so no vector traps. Each comment names the machine shape the function is
// meant to produce and its true result in terms of a, b, c.
//
// The hierarchy is `open`, so the module cannot assume it sees every
// subclass and a call through a `Base` reference stays a vtable load.

// MARK: - The three-deep hierarchy

open class Base {
    public var p: Int          // offset 16
    public var q: Int          // offset 24
    public required init(p: Int, q: Int) { self.p = p; self.q = q }
    // Slot order follows declaration order: alpha, beta, gamma, delta,
    // epsilon, zeta, poke, combo, theta, iota, then the class methods.
    open func alpha(_ x: Int) -> Int { x &+ p &+ 11 }
    open func beta(_ x: Int) -> Int { x &* 2 &+ q &+ 13 }
    @inline(never) open func gamma() -> Int { p &* 17 &+ q }
    open func delta(_ x: Int, _ y: Int) -> Int { x &* 19 &- y &* 23 &+ p }
    open func epsilon(_ x: Int) -> Int { x ^ 0x29 }
    @inline(never) open func zeta(_ x: Int) -> Int { x &+ q &* 31 }
    // Base changes p; Mid (and so Leaf) changes q instead.
    @inline(never) open func poke(_ d: Int) { p = p &+ d }
    // Calls three methods on self: two through the vtable, one direct.
    @inline(never) open func combo(_ x: Int) -> Int { alpha(x) &* 1093 &+ beta(x) &+ fixed(x) }
    // Ignores its argument here; Leaf's override reads it.
    open func theta(_ x: Int) -> Int { p &+ 1319 }
    // Reads no field here; Leaf's override reads p.
    open func iota(_ x: Int) -> Int { x ^ 1327 }
    @inline(never) public final func fixed(_ x: Int) -> Int { x &* 37 &+ p }
    @inline(never) open class func cls(_ x: Int) -> Int { x &+ 41 }
    @inline(never) public static func stat(_ x: Int) -> Int { x &* 43 }
}

open class Mid: Base {
    public var r: Int          // offset 32
    public required init(p: Int, q: Int) { r = p &* 3 &+ q; super.init(p: p, q: q) }
    open override func alpha(_ x: Int) -> Int { x &+ p &+ 101 }
    open override func delta(_ x: Int, _ y: Int) -> Int { x &* 103 &- y &* 107 &+ q }
    // super.zeta is Base.zeta, a direct call.
    @inline(never) open override func zeta(_ x: Int) -> Int { super.zeta(x) &+ 113 }
    @inline(never) open override func poke(_ d: Int) { q = q &- d }
    open func eta(_ x: Int) -> Int { x &+ r &* 109 }
    @inline(never) open override class func cls(_ x: Int) -> Int { x &+ 127 }
}

open class Leaf: Mid {
    public var s: Int32        // offset 40
    public required init(p: Int, q: Int) { s = Int32(truncatingIfNeeded: p &- q); super.init(p: p, q: q) }
    open override func alpha(_ x: Int) -> Int { x &- p &+ 211 }
    // Mid does not override gamma, so super.gamma is Base.gamma, called
    // directly: not Leaf.gamma (that would recurse) and not a vtable load.
    @inline(never) open override func gamma() -> Int { super.gamma() &* 223 &+ r }
    open override func eta(_ x: Int) -> Int { x &* 227 &+ r &+ Int(s) }
    open override func theta(_ x: Int) -> Int { x &* 1321 &+ p }
    open override func iota(_ x: Int) -> Int { x ^ p }
    // super.cls is Mid.cls.
    @inline(never) open override class func cls(_ x: Int) -> Int { super.cls(x) &* 229 }
}

// kind & 3: 0 is Base, 1 is Mid, 2 and 3 are Leaf.
@inline(never) public func make(_ kind: Int, _ p: Int, _ q: Int) -> Base {
    switch kind & 3 {
    case 0: return Base(p: p, q: q)
    case 1: return Mid(p: p, q: q)
    default: return Leaf(p: p, q: q)
    }
}

// kind & 1: 0 is Mid, 1 is Leaf.
@inline(never) public func makeMid(_ kind: Int, _ p: Int, _ q: Int) -> Mid {
    kind & 1 == 0 ? Mid(p: p, q: q) : Leaf(p: p, q: q)
}

@inline(never) public func makeLeaf(_ p: Int, _ q: Int) -> Leaf { Leaf(p: p, q: q) }

// kind & 3: 0 is Base.self, 1 is Mid.self, 2 and 3 are Leaf.self.
@inline(never) public func pickType(_ kind: Int) -> Base.Type {
    switch kind & 3 {
    case 0: return Base.self
    case 1: return Mid.self
    default: return Leaf.self
    }
}

// Vtable slot 0 through a Base reference. o = make(a, b, c).
// Base: (c+7) + b + 11.  Mid: (c+7) + b + 101.  Leaf: (c+7) - b + 211.
@inline(never) public func vtAlpha(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = make(a, b, c)
    return o.alpha(c &+ 7)
}

// Slot 1, overridden nowhere: every kind gives (a^b)*2 + c + 13.
@inline(never) public func vtBeta(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = make(a, b, c)
    return o.beta(a ^ b)
}

// Slot 2, no arguments. Base and Mid: b*17 + c. Leaf: (b*17 + c)*223 + (b*3 + c).
// The result is then weighted: gamma*47 + a.
@inline(never) public func vtGamma(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = make(a, b, c)
    return o.gamma() &* 47 &+ a
}

// Slot 3, two arguments with unequal weights, so a swap shows.
// o = make(a, 5, 9). Base: b*19 - c*23 + 5. Mid and Leaf: b*103 - c*107 + 9.
@inline(never) public func vtDelta(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = make(a, 5, 9)
    return o.delta(b, c)
}

// Slot 4, overridden nowhere, reads no field: (b + c*53) ^ 0x29, for every kind.
@inline(never) public func vtEpsilon(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = make(a, b, c)
    return o.epsilon(b &+ c &* 53)
}

// Slot 5. Base: a + c*31. Mid and Leaf: a + c*31 + 113 (the override calls super).
@inline(never) public func vtZeta(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = make(a, b, c)
    return o.zeta(a)
}

// All six slots on one object, each result with its own weight, so a
// call named as the neighbouring slot changes the sum.
// o = make(a, b, c); alpha(1)*3 + beta(2)*5 + gamma()*7 + delta(3, 4)*11
// + epsilon(5)*13 + zeta(6)*17.
@inline(never) public func vtAll(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = make(a, b, c)
    var t = o.alpha(1) &* 3
    t = t &+ o.beta(2) &* 5
    t = t &+ o.gamma() &* 7
    t = t &+ o.delta(3, 4) &* 11
    t = t &+ o.epsilon(5) &* 13
    t = t &+ o.zeta(6) &* 17
    return t
}

// A slot Base does not have, through a Mid reference. m = makeMid(a, b, c),
// r = b*3 + c. Mid: a + r*109. Leaf: a*227 + r + Int32(b - c).
@inline(never) public func vtEta(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let m = makeMid(a, b, c)
    return m.eta(a)
}

// A method that dispatches on self. o = make(a, b, 59).
// alpha(c)*1093 + beta(c) + fixed(c), with alpha per kind as in vtAlpha
// (p = b), beta(c) = c*2 + 59 + 13, fixed(c) = c*37 + b.
@inline(never) public func vtCombo(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = make(a, b, 59)
    return o.combo(c)
}

// A slot whose Base implementation ignores its argument and whose Leaf
// override reads it: the argument is passed whatever Base.theta's body
// does. o = make(a, b, c). Base and Mid: b + 1319. Leaf: c*1321 + b.
// Result: theta(c)*1361 + a.
@inline(never) public func vtTheta(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = make(a, b, c)
    return o.theta(c) &* 1361 &+ a
}

// A slot whose Base implementation reads nothing of self and whose Leaf
// override reads p: self is passed whatever Base.iota's body does.
// o = make(a, b, c). Base and Mid: c ^ 1327. Leaf: c ^ b.
// Result: iota(c) + a*1367.
@inline(never) public func vtIota(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = make(a, b, c)
    return o.iota(c) &+ a &* 1367
}

// MARK: - Direct calls

final class Fin {
    var k: Int
    init(k: Int) { self.k = k }
    @inline(never) func run(_ x: Int) -> Int { x &* 1123 &+ k }
}

@inline(never) func makeFin(_ k: Int) -> Fin { Fin(k: k) }

// Control: a final class's method is a direct call. (b ^ c)*1123 + a.
@inline(never) public func finalClassCall(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let f = makeFin(a)
    return f.run(b ^ c)
}

// A final method of an open class through a Base reference of any kind:
// direct call to Base.fixed, never a slot. c*37 + b, then + a*61.
@inline(never) public func finalMethodCall(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = make(a, b, c)
    return o.fixed(c) &+ a &* 61
}

// Leaf.gamma on a known Leaf: its super call reaches Base.gamma.
// l = makeLeaf(a, b): (a*17 + b)*223 + (a*3 + b), then + c*67.
@inline(never) public func superGamma(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let l = makeLeaf(a, b)
    return l.gamma() &+ c &* 67
}

// Static and class methods named statically: three direct calls.
// Base.stat(a) = a*43; Mid.cls(b) = b + 127; Leaf.cls(c) = (c + 127)*229.
// Result: stat*71 + mid*73 + leaf.
@inline(never) public func staticDirect(_ a: Int, _ b: Int, _ c: Int) -> Int {
    Base.stat(a) &* 71 &+ Mid.cls(b) &* 73 &+ Leaf.cls(c)
}

// A class method through a metatype value: a slot of the metaclass.
// t = pickType(a). Base: b + 41. Mid: b + 127. Leaf: (b + 127)*229.
// Result: cls(b)*79 + c.
@inline(never) public func classMethodMeta(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let t = pickType(a)
    return t.cls(b) &* 79 &+ c
}

// MARK: - Initializers

enum Oops: Error {
    case zero
    case big(Int)
}

final class Rec {
    let a: Int      // 16
    let b: Int32    // 24
    let c: Int16    // 28
    var d: Int      // 32
    // Designated: a = a + 1, b = Int32(b*3), c = Int16(c ^ 0x55), d = a - c.
    @inline(never) init(a: Int, b: Int, c: Int) {
        self.a = a &+ 1
        self.b = Int32(truncatingIfNeeded: b &* 3)
        self.c = Int16(truncatingIfNeeded: c ^ 0x55)
        self.d = a &- c
    }
    // Convenience: delegates with (sum, sum + 1, sum + 2), then d = d*1097.
    @inline(never) convenience init(sum: Int) {
        self.init(a: sum, b: sum &+ 1, c: sum &+ 2)
        d = d &* 1097
    }
    // Failable: nil when x < 0, else a = x, b = 7, c = 9, d = x*1103.
    @inline(never) init?(positive x: Int) {
        if x < 0 { return nil }
        a = x; b = 7; c = 9; d = x &* 1103
    }
    // Throwing: .zero when x == 0, .big(x) when x > 1000, else
    // a = x, b = 3, c = 5, d = x ^ 1109.
    @inline(never) init(checked x: Int) throws {
        if x == 0 { throw Oops.zero }
        if x > 1000 { throw Oops.big(x) }
        a = x; b = 3; c = 5; d = x ^ 1109
    }
    // a*2 + b*3 + c*5 + d*7, each field at its own width.
    @inline(never) func sum() -> Int { a &* 2 &+ Int(b) &* 3 &+ Int(c) &* 5 &+ d &* 7 }
}

// A designated initializer's stores, read back at each width.
// (a+1)*2 + Int32(b*3)*3 + Int16(c ^ 0x55)*5 + (a - c)*7.
@inline(never) public func initDesignated(_ a: Int, _ b: Int, _ c: Int) -> Int {
    Rec(a: a, b: b, c: c).sum()
}

// A convenience initializer delegating to the designated one.
// s = a ^ b: Rec(a: s, b: s+1, c: s+2) with d = (s - (s+2))*1097 = -2194.
// Result: sum() + c.
@inline(never) public func initConvenience(_ a: Int, _ b: Int, _ c: Int) -> Int {
    Rec(sum: a ^ b).sum() &+ c
}

// A failable initializer: nil in x0 when a < 0.
// a < 0: b*1117 - 1. Otherwise: a*2 + 21 + 45 + a*1103*7, plus c.
@inline(never) public func initFailable(_ a: Int, _ b: Int, _ c: Int) -> Int {
    guard let r = Rec(positive: a) else { return b &* 1117 &- 1 }
    return r.sum() &+ c
}

// A throwing initializer, caught: the error comes back in x21.
// a == 0: -1129 + b. a > 1000: a*1151 + c. Else: a*2 + 9 + 25 + (a ^ 1109)*7.
@inline(never) public func initThrowing(_ a: Int, _ b: Int, _ c: Int) -> Int {
    do {
        return try Rec(checked: a).sum()
    } catch Oops.zero {
        return b &- 1129
    } catch Oops.big(let v) {
        return v &* 1151 &+ c
    } catch {
        return -1
    }
}

// A required initializer through a metatype value: the allocating
// initializer is a vtable slot. t = pickType(a); o = t.init(p: b, q: c).
// Result: o.alpha(a)*83 + o.gamma().
@inline(never) public func initRequired(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let t = pickType(a)
    let o = t.init(p: b, q: c)
    return o.alpha(a) &* 83 &+ o.gamma()
}

// MARK: - deinit

public var deinitLog = 0

final class Tracker {
    let w: Int
    init(w: Int) { self.w = w }
    deinit { deinitLog = deinitLog &* 7 &+ w }
}

class TrackBase {
    let w: Int
    init(w: Int) { self.w = w }
    deinit { deinitLog = deinitLog &* 5 &+ w }
}

final class TrackSub: TrackBase {
    deinit { deinitLog = deinitLog &* 3 &+ w &+ 1 }
}

@inline(never) func makeTracker(_ w: Int) -> Tracker { Tracker(w: w) }
@inline(never) func makeTrackBase(_ kind: Int, _ w: Int) -> TrackBase {
    kind & 1 == 0 ? TrackBase(w: w) : TrackSub(w: w)
}
@inline(never) func touch(_ t: AnyObject) -> Int { 89 }

// A deinit's store to a global, seen after the last release.
// log = a; make and drop Tracker(b): log = a*7 + b. Result: log*97 + c + 89.
@inline(never) public func deinitOnce(_ a: Int, _ b: Int, _ c: Int) -> Int {
    deinitLog = a
    var k = 0
    do {
        let t = makeTracker(b)
        k = touch(t)
    }
    return deinitLog &* 97 &+ c &+ k
}

// A subclass deinit runs before its superclass's. log = c.
// a even (TrackBase): log = c*5 + b.
// a odd (TrackSub): log = (c*3 + b + 1)*5 + b.
// Result: log + 89*101.
@inline(never) public func deinitChain(_ a: Int, _ b: Int, _ c: Int) -> Int {
    deinitLog = c
    var k = 0
    do {
        let t = makeTrackBase(a, b)
        k = touch(t)
    }
    return deinitLog &+ k &* 101
}

// MARK: - Stored properties of each width

final class Widths {
    var i8: Int8 = 0       // 16
    var u8: UInt8 = 0      // 17
    var i16: Int16 = 0     // 18
    var u16: UInt16 = 0    // 20
    var i32: Int32 = 0     // 24
    var u32: UInt32 = 0    // 28
    var i64: Int64 = 0     // 32
    var u64: UInt64 = 0    // 40
    var flag: Bool = false // 48
    @inline(never) func store(_ a: Int, _ b: Int, _ c: Int) {
        i8 = Int8(truncatingIfNeeded: a)
        u8 = UInt8(truncatingIfNeeded: b)
        i16 = Int16(truncatingIfNeeded: c)
        u16 = UInt16(truncatingIfNeeded: a >> 8)
        i32 = Int32(truncatingIfNeeded: b)
        u32 = UInt32(truncatingIfNeeded: c)
        i64 = Int64(a ^ b)
        u64 = UInt64(bitPattern: Int64(c &* 3))
        flag = a & 1 == 1
    }
}

@inline(never) func makeWidths(_ a: Int, _ b: Int, _ c: Int) -> Widths {
    let w = Widths()
    w.store(a, b, c)
    return w
}

// Loads of every scalar width at known offsets, signed ones sign-extended
// (ldrsb, ldrsh, ldrsw) and unsigned ones zero-extended. w = makeWidths(a, b, c):
// Int8(a)*3 + UInt8(b)*5 + Int16(c)*7 + UInt16(a >> 8)*11 + Int32(b)*13
// + UInt32(c)*17 + (a ^ b)*19 + (c*3)*23 + (a odd ? 29 : 0).
@inline(never) public func widthsRead(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let w = makeWidths(a, b, c)
    var t = Int(w.i8) &* 3
    t = t &+ Int(w.u8) &* 5
    t = t &+ Int(w.i16) &* 7
    t = t &+ Int(w.u16) &* 11
    t = t &+ Int(w.i32) &* 13
    t = t &+ Int(w.u32) &* 17
    t = t &+ Int(w.i64) &* 19
    t = t &+ Int(truncatingIfNeeded: w.u64) &* 23
    t = t &+ (w.flag ? 29 : 0)
    return t
}

// Stores of each width into an object the function did not create.
// w = makeWidths(0, 0, 0); then i8 = Int8(a + 1), u16 = UInt16(b + 2),
// i32 = Int32(c + 3), u64 = a ^ c, flag = b < 0.
// Result: i8*31 + u16*37 + i32*41 + u64*43 + (flag ? 47 : 0), read back
// through sumSome.
@inline(never) func sumSome(_ w: Widths) -> Int {
    var t = Int(w.i8) &* 31
    t = t &+ Int(w.u16) &* 37
    t = t &+ Int(w.i32) &* 41
    t = t &+ Int(truncatingIfNeeded: w.u64) &* 43
    t = t &+ (w.flag ? 47 : 0)
    return t
}

@inline(never) public func widthsWrite(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let w = makeWidths(0, 0, 0)
    w.i8 = Int8(truncatingIfNeeded: a &+ 1)
    w.u16 = UInt16(truncatingIfNeeded: b &+ 2)
    w.i32 = Int32(truncatingIfNeeded: c &+ 3)
    w.u64 = UInt64(bitPattern: Int64(a ^ c))
    w.flag = b < 0
    return sumSome(w)
}

// Fields a subclass adds sit after its superclass's. l = makeLeaf(a, b):
// p*1129 + q*1151 + r*1153 + Int(s)*1163 + c, with p = a, q = b,
// r = a*3 + b, s = Int32(a - b).
@inline(never) public func subclassFields(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let l = makeLeaf(a, b)
    return l.p &* 1129 &+ l.q &* 1151 &+ l.r &* 1153 &+ Int(l.s) &* 1163 &+ c
}

// MARK: - Observers, lazy, computed

final class Watched {
    var log = 0
    var v: Int = 0 {
        willSet { log = log &* 3 &+ newValue }
        didSet { log = log &* 5 &+ oldValue }
    }
    init(v: Int) { self.v = v }   // no observer in init
}

@inline(never) func makeWatched(_ v: Int) -> Watched { Watched(v: v) }

// willSet and didSet around each store. w.v starts at a, log at 0.
// After v = b: log = (0*3 + b)*5 + a. After v = c: log = (log*3 + c)*5 + b.
// Result: log*7 + v, with v = c.
@inline(never) public func observers(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let w = makeWatched(a)
    w.v = b
    w.v = c
    return w.log &* 7 &+ w.v
}

final class Lazy {
    var seed: Int
    var hits = 0
    lazy var big: Int = {
        hits = hits &+ 1
        return seed &* 59 &+ 3
    }()
    init(seed: Int) { self.seed = seed }
}

@inline(never) func makeLazy(_ seed: Int) -> Lazy { Lazy(seed: seed) }

// A lazy property is computed once: the second read does not see the new
// seed. x = a*59 + 3; seed = b; y = x. Result: x*3 + y*5 + hits*7 + c
// with hits = 1, so (a*59 + 3)*8 + 7 + c.
@inline(never) public func lazyProp(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let l = makeLazy(a)
    let x = l.big
    l.seed = b
    let y = l.big
    return x &* 3 &+ y &* 5 &+ l.hits &* 7 &+ c
}

class Comp {
    var raw: Int
    init(raw: Int) { self.raw = raw }
    var doubled: Int {
        @inline(never) get { raw &* 2 &+ 61 }
        @inline(never) set { raw = newValue &- 67 }
    }
}

@inline(never) func makeComp(_ raw: Int) -> Comp { Comp(raw: raw) }

// A computed property: a getter call, a setter call, a getter call.
// x = a*2 + 61; set b: raw = b - 67; y = (b - 67)*2 + 61.
// Result: x*1171 + y*1181 + c.
@inline(never) public func computedProp(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = makeComp(a)
    let x = o.doubled
    o.doubled = b
    let y = o.doubled
    return x &* 1171 &+ y &* 1181 &+ c
}

// MARK: - weak and unowned

final class Target {
    var val: Int
    init(val: Int) { self.val = val }
}

final class Holder {
    var strong: Target?
    weak var w: Target?
    init(val: Int) {
        let t = Target(val: val)
        strong = t
        w = t
    }
}

@inline(never) func makeHolder(_ val: Int) -> Holder { Holder(val: val) }
// Target alive: val*73. Gone: -79.
@inline(never) func weakRead(_ h: Holder) -> Int {
    if let t = h.w { return t.val &* 73 }
    return -79
}

// A weak load (swift_weakLoadStrong) before and after the last strong
// reference goes. r1 = a*73. b odd: strong = nil, r2 = -79; else r2 = a*73.
// Result: r1*3 + r2 + c.
@inline(never) public func weakProp(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let h = makeHolder(a)
    let r1 = weakRead(h)
    if b & 1 == 1 { h.strong = nil }
    let r2 = weakRead(h)
    return r1 &* 3 &+ r2 &+ c
}

final class Owner {
    var keep: Target
    unowned var back: Target
    var tail: Int
    init(val: Int, tail: Int) {
        let t = Target(val: val)
        keep = t
        back = t
        self.tail = tail
    }
}

@inline(never) func makeOwner(_ val: Int, _ tail: Int) -> Owner { Owner(val: val, tail: tail) }

// An unowned reference read (swift_unownedRetainStrong) and the field
// after it. o = makeOwner(a, b): back.val*1187 + tail*1193 + c = a*1187 + b*1193 + c.
@inline(never) public func unownedProp(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = makeOwner(a, b)
    return o.back.val &* 1187 &+ o.tail &* 1193 &+ c
}

// MARK: - Struct and Optional fields

struct Pair {
    var lo: Int32
    var hi: Int64
}

final class Bag {
    var pair: Pair      // lo 16, hi 24
    var maybe: Int?     // 32, tag byte 40
    var small: Int32?   // 44, tag byte 48
    var tail: Int       // 56
    init(pair: Pair, maybe: Int?, small: Int32?, tail: Int) {
        self.pair = pair; self.maybe = maybe; self.small = small; self.tail = tail
    }
}

// pair = (Int32(a), b); maybe = c odd ? c : nil; small = a < 0 ? nil : Int32(b);
// tail = a ^ c.
@inline(never) func makeBag(_ a: Int, _ b: Int, _ c: Int) -> Bag {
    Bag(pair: Pair(lo: Int32(truncatingIfNeeded: a), hi: Int64(b)),
        maybe: c & 1 == 1 ? c : nil,
        small: a < 0 ? nil : Int32(truncatingIfNeeded: b),
        tail: a ^ c)
}

// A struct field, two Optionals with out-of-line tag bytes, and the field
// after them. g = makeBag(a, b, c):
// Int32(a)*83 + b*89 + (maybe ?? -97)*101 + Int(small ?? -103)*107 + (a ^ c)*109.
@inline(never) public func structOptionalFields(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let g = makeBag(a, b, c)
    var t = Int(g.pair.lo) &* 83
    t = t &+ Int(g.pair.hi) &* 89
    t = t &+ (g.maybe ?? -97) &* 101
    t = t &+ Int(g.small ?? -103) &* 107
    t = t &+ g.tail &* 109
    return t
}

// MARK: - A field across a call

final class Cell {
    var v: Int   // 16
    var w: Int   // 24
    init(v: Int, w: Int) { self.v = v; self.w = w }
    @inline(never) func bump(_ d: Int) { v = v &+ d }
    @inline(never) func peek(_ d: Int) -> Int { w ^ d }
    @inline(never) func bumpIfOdd(_ d: Int) { if d & 1 == 1 { v = v &* 3 } }
    @inline(never) func bumpW(_ d: Int) { w = w &- d }
    // Reads its own field, calls a method that writes it, reads it again:
    // v*1409 + (v + d)*1423. The two reads print as the same `self.v`
    // unless the render tells them apart.
    @inline(never) func selfAcross(_ d: Int) -> Int {
        let x = v
        bump(d)
        let y = v
        return x &* 1409 &+ y &* 1423
    }
}

@inline(never) func makeCell(_ v: Int, _ w: Int) -> Cell { Cell(v: v, w: w) }
@inline(never) func same(_ c: Cell) -> Cell { c }

// Read, a call that writes the field, read again. x = a; bump(c); y = a + c.
// Result: x*1009 + y*1013 + b. A render that reuses x for y gives a*2022 + b.
@inline(never) public func staleBump(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = makeCell(a, b)
    let x = o.v
    o.bump(c)
    let y = o.v
    return x &* 1009 &+ y &* 1013 &+ o.w
}

// Control: the call between the reads writes nothing. x = y = a; k = b ^ c.
// Result: a*1019 + a*1021 + (b ^ c)*1031.
@inline(never) public func stalePeek(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = makeCell(a, b)
    let x = o.v
    let k = o.peek(c)
    let y = o.v
    return x &* 1019 &+ y &* 1021 &+ k &* 1031
}

// The call writes the field on one path only. x = a; y = c odd ? a*3 : a.
// Result: x*1033 + y*1039 + b.
@inline(never) public func staleCond(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = makeCell(a, b)
    let x = o.v
    o.bumpIfOdd(c)
    let y = o.v
    return x &* 1033 &+ y &* 1039 &+ o.w
}

// The call writes the neighbouring field: v is the same before and after,
// w is not. v1 = v2 = a; w1 = b; w2 = b - c.
// Result: v1*1049 + w1*1051 + v2*1061 + w2*1063.
@inline(never) public func staleOther(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = makeCell(a, b)
    let v1 = o.v
    let w1 = o.w
    o.bumpW(c)
    let v2 = o.v
    let w2 = o.w
    return v1 &* 1049 &+ w1 &* 1051 &+ v2 &* 1061 &+ w2 &* 1063
}

// The writer is reached through the vtable, so which field it writes
// depends on the dynamic class. o = make(a, b, 131); poke(c).
// Base: p2 = b + c, q2 = 131. Mid and Leaf: p2 = b, q2 = 131 - c.
// Result: p1*1069 + q1*1087 + p2*1091 + q2*1097 with p1 = b, q1 = 131.
@inline(never) public func staleVirtual(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = make(a, b, 131)
    let p1 = o.p
    let q1 = o.q
    o.poke(c)
    let p2 = o.p
    let q2 = o.q
    return p1 &* 1069 &+ q1 &* 1087 &+ p2 &* 1091 &+ q2 &* 1097
}

// The same read-call-read on a parameter: o.v*1373 + (o.v + d)*1381.
@inline(never) func readAcross(_ o: Cell, _ d: Int) -> Int {
    let x = o.v
    o.bump(d)
    let y = o.v
    return x &* 1373 &+ y &* 1381
}

// The object is a parameter of the function that reads across the call.
// o = makeCell(a, b): readAcross(o, c) + o.w*1399 = a*1373 + (a + c)*1381 + b*1399.
@inline(never) public func staleParam(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = makeCell(a, b)
    return readAcross(o, c) &+ o.w &* 1399
}

// The object is self in the method that reads across the call.
// o = makeCell(a, b): o.selfAcross(c) + o.w*1427 = a*1409 + (a + c)*1423 + b*1427.
@inline(never) public func staleSelf(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = makeCell(a, b)
    return o.selfAcross(c) &+ o.w &* 1427
}

// MARK: - Aliases

// Two references to one object: a store through one is read through the
// other. o = makeCell(a, b); d = same(o); o.v = c. Result: d.v*1103 + o.w = c*1103 + b.
@inline(never) public func aliasSame(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = makeCell(a, b)
    let d = same(o)
    o.v = c
    return d.v &* 1103 &+ o.w
}

// x.v = k; y.v = k + 1; then x.v is reloaded: k + 1 when x and y are one
// object, k when they are two. Result: x.v*1109 + y.v.
@inline(never) func pokeBoth(_ x: Cell, _ y: Cell, _ k: Int) -> Int {
    x.v = k
    y.v = k &+ 1
    return x.v &* 1109 &+ y.v
}

// a even: one object twice: (c + 1)*1109 + (c + 1), plus b*1117.
// a odd: two objects: c*1109 + (c + 1), plus b*1117.
@inline(never) public func aliasMaybe(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let c1 = makeCell(a, b)
    let c2 = a & 1 == 0 ? c1 : makeCell(b, a)
    return pokeBoth(c1, c2, c) &+ c1.w &* 1117
}

// Control: two objects that cannot alias. c1 = (a, b), c2 = (b, c).
// c1.v = c2.w + 1171 = c + 1171; c2.bump(c1.v): c2.v = b + c + 1171.
// Result: c1.v*1181 + c2.v*1187 + c1.w.
@inline(never) public func twoObjects(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let c1 = makeCell(a, b)
    let c2 = makeCell(b, c)
    c1.v = c2.w &+ 1171
    c2.bump(c1.v)
    return c1.v &* 1181 &+ c2.v &* 1187 &+ c1.w
}

// MARK: - A class cluster behind a protocol

public protocol Shape {
    var sides: Int { get }
    func area(_ k: Int) -> Int
    func name() -> Int
}

final class Tri: Shape {
    var n: Int
    init(n: Int) { self.n = n }
    var sides: Int { 3 }
    func area(_ k: Int) -> Int { n &* k &+ 1201 }
    func name() -> Int { 1213 }
}

final class Sq: Shape {
    var n: Int
    init(n: Int) { self.n = n }
    var sides: Int { 4 }
    func area(_ k: Int) -> Int { n &* n &+ k &* 1217 }
    func name() -> Int { 1223 }
}

final class Hex: Shape {
    var n: Int
    var extra: Int
    init(n: Int) { self.n = n; self.extra = n ^ 1229 }
    var sides: Int { 6 }
    func area(_ k: Int) -> Int { extra &- k &* 1231 }
    func name() -> Int { 1237 }
}

// kind & 3: 0 is Tri, 1 is Sq, 2 and 3 are Hex.
@inline(never) public func makeShape(_ kind: Int, _ n: Int) -> any Shape {
    switch kind & 3 {
    case 0: return Tri(n: n)
    case 1: return Sq(n: n)
    default: return Hex(n: n)
    }
}

// Three witness-table calls on an existential. s = makeShape(a, b).
// Result: area(c)*1249 + sides*1259 + name().
// Tri: (b*c + 1201)*1249 + 3*1259 + 1213.
// Sq: (b*b + c*1217)*1249 + 4*1259 + 1223.
// Hex: ((b ^ 1229) - c*1231)*1249 + 6*1259 + 1237.
@inline(never) public func protoCluster(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let s = makeShape(a, b)
    return s.area(c) &* 1249 &+ s.sides &* 1259 &+ s.name()
}

public protocol Node: AnyObject {
    var weight: Int { get set }
    func eval(_ x: Int) -> Int
}

final class AddNode: Node {
    var weight: Int
    init(weight: Int) { self.weight = weight }
    func eval(_ x: Int) -> Int { x &+ weight &* 1277 }
}

final class MulNode: Node {
    var pad = 1279
    var weight: Int      // at 24 here, at 16 in AddNode
    init(weight: Int) { self.weight = weight }
    func eval(_ x: Int) -> Int { x &* weight &+ pad }
}

@inline(never) public func makeNode(_ kind: Int, _ w: Int) -> any Node {
    kind & 1 == 0 ? AddNode(weight: w) : MulNode(weight: w)
}

// A class-bound existential: a setter, a getter and a method through the
// witness table. n = makeNode(a, b); n.weight = n.weight + 1283 (a getter
// then a setter); r = n.eval(c).
// AddNode: r = c + (b + 1283)*1277. MulNode: r = c*(b + 1283) + 1279.
// Result: r*1289 + n.weight.
@inline(never) public func protoClassBound(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let n = makeNode(a, b)
    n.weight = n.weight &+ 1283
    return n.eval(c) &* 1289 &+ n.weight
}

// MARK: - A generic class and a subclass that fixes its parameter

open class Slot<T> {
    public var item: T
    public var count: Int
    public init(item: T, count: Int) { self.item = item; self.count = count }
    open func take() -> T { item }
    open func score(_ x: Int) -> Int { x &+ count &* 1291 }
}

open class IntSlot: Slot<Int> {
    open override func take() -> Int { item &* 1297 }
    open override func score(_ x: Int) -> Int { x &- count &* 1301 }
}

// kind & 1: 0 is Slot<Int>, 1 is IntSlot.
@inline(never) public func makeSlot(_ kind: Int, _ v: Int, _ n: Int) -> Slot<Int> {
    kind & 1 == 0 ? Slot<Int>(item: v, count: n) : IntSlot(item: v, count: n)
}

// Vtable calls on a generic class through its specialised base. The
// generic take() returns indirectly (x8) even for Int. s = makeSlot(a, b, c).
// Slot<Int>: take = b, score(a) = a + c*1291.
// IntSlot: take = b*1297, score(a) = a - c*1301.
// Result: take*1303 + score.
@inline(never) public func genericTake(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let s = makeSlot(a, b, c)
    return s.take() &* 1303 &+ s.score(a)
}

// A generic function over the class, kept unspecialised: count is read
// through the field offset the metadata carries, and score is a slot.
@_semantics("optimize.sil.specialize.generic.never")
@inline(never) public func readSlot<T>(_ s: Slot<T>, _ x: Int) -> Int {
    s.count &* 1307 &+ s.score(x)
}

// s = makeSlot(a, b, c). Slot<Int>: c*1307 + b + c*1291.
// IntSlot: c*1307 + b - c*1301.
@inline(never) public func genericUnspecialized(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let s = makeSlot(a, b, c)
    return readSlot(s, b)
}

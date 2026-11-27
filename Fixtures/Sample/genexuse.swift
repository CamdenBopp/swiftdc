// Generics, protocols and existentials: the callers (-Onone, -O, -Osize).
//
// Every test takes three Ints and returns one. It builds its values, does
// one generic or dynamic operation through GenExLib (a separate module, so
// nothing is specialised or devirtualised across it) or through a local
// generic, and returns an integer whose weights name the implementation,
// the requirement and every value. Each has a C entry `ge_<name>` for the
// native driver. The true behaviour is the source; the weights of the
// library's implementations are in genexlib.swift.

import GenExLib

// MARK: local implementations

public struct LPoint: Shape4 {
    public var x: Int
    public var y: Int
    @inline(never) public func r0(_ k: Int) -> Int { x &* 401 &+ y &* 409 &+ k &* 419 &+ 2000000 }
    @inline(never) public func r1(_ k: Int) -> Int { x &* 421 &+ y &* 431 &+ k &* 433 &+ 2100000 }
    @inline(never) public func r2(_ k: Int) -> Int { x &* 439 &+ y &* 443 &+ k &* 449 &+ 2200000 }
    public var r3: Int { x &* 457 &+ y &* 461 &+ 2300000 }
}

// Not specialised even in this module: metadata and table are arguments.
// x.r2(k) * 3 + x.r3.
@_semantics("optimize.sil.specialize.generic.never")
@inline(never) func lNever<T: Shape4>(_ x: T, _ k: Int) -> Int { x.r2(k) &* 3 &+ x.r3 }

// Specialised by the optimizer at -O and -Osize. x.r0(k) * 7 + x.r1(k).
@inline(never) func lSpec<T: Shape4>(_ x: T, _ k: Int) -> Int { x.r0(k) &* 7 &+ x.r1(k) }

// Two parameters, specialised. x.r3 + y.tag * 3 + U.tagBase * 5 + k.
@inline(never) func lSpecTwo<T: Shape4, U: Tagged>(_ x: T, _ y: U, _ k: Int) -> Int {
    x.r3 &+ y.tag &* 3 &+ U.tagBase &* 5 &+ k
}

// An associated type, unspecialised. c.item.r3 + c.weight() * 3.
@_semantics("optimize.sil.specialize.generic.never")
@inline(never) func lAssoc<C: Container>(_ c: C, _ k: Int) -> Int { c.item.r3 &+ c.weight() &* 3 &+ k }

struct LWrap<T: Shape4> {
    var inner: T
    var m: Int
    // inner.r1(k) + m * 463.
    @inline(never) func run(_ k: Int) -> Int { inner.r1(k) &+ m &* 463 }
}

final class LCell<T: Shape4> {
    let inner: T
    let m: Int
    init(inner: T, m: Int) { self.inner = inner; self.m = m }
    // inner.r2(k) + m * 467.
    @inline(never) func run(_ k: Int) -> Int { inner.r2(k) &+ m &* 467 }
}

// The underlying type is LPoint(x: a, y: b), known in this module.
@inline(never) func lOpaque(_ a: Int, _ b: Int) -> some Shape4 { LPoint(x: a, y: b) }

// An existential stored in a class, after another field.
final class Shelf {
    var pad: Int
    var slot: any Shape4
    init(pad: Int, slot: any Shape4) { self.pad = pad; self.slot = slot }
}

// s.slot.r1(k) + s.pad * 3: the container starts at the field's offset.
@inline(never) func useShelf(_ s: Shelf, _ k: Int) -> Int { s.slot.r1(k) &+ s.pad &* 3 }

// MARK: controls (must render exactly)

// a * 3 + b * 5 + c * 7 + 9.
@_cdecl("ge_ctlArith") @inline(never) public func ctlArith(_ a: Int, _ b: Int, _ c: Int) -> Int {
    a &* 3 &+ b &* 5 &+ c &* 7 &+ 9
}

// A direct call of a concrete method: Small(a, b).r1(c) + 31.
@_cdecl("ge_ctlDirect") @inline(never) public func ctlDirect(_ a: Int, _ b: Int, _ c: Int) -> Int {
    Small(p: a, q: b).r1(c) &+ 31
}

// A direct call of a final class's method: Klass(a, b).r2(c) + 37.
@_cdecl("ge_ctlClass") @inline(never) public func ctlClass(_ a: Int, _ b: Int, _ c: Int) -> Int {
    Klass(p: a, q: b).r2(c) &+ 37
}

// A direct call of a local concrete method: LPoint(a, b).r0(c) + 61.
@_cdecl("ge_ctlLocal") @inline(never) public func ctlLocal(_ a: Int, _ b: Int, _ c: Int) -> Int {
    LPoint(x: a, y: b).r0(c) &+ 61
}

// MARK: unspecialised generic calls across the module

// gSize(n: x0, &x: x1, T = Int: x2). a * 3 + 8 * 7 + 13 + b * 1009 + c * 1013.
@_cdecl("ge_genSizeInt") @inline(never) public func genSizeInt(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gSize(a, b) &+ b &* 1009 &+ c &* 1013
}

// T = Large (32 bytes). a * 3 + 32 * 7 + 13 + b * 1019 + c * 1021.
@_cdecl("ge_genSizeLarge") @inline(never) public func genSizeLarge(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gSize(a, Large(p: b, q: c, r: a, s: b)) &+ b &* 1019 &+ c &* 1021
}

// gTwo(n, &x, &y, T = Small, U = UInt8): a * 5 + 16 * 100 + 1 * 10000 + 17
// + b * 1031 + c * 1033.
@_cdecl("ge_genTwo") @inline(never) public func genTwo(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gTwo(a, Small(p: b, q: c), UInt8(truncatingIfNeeded: c)) &+ b &* 1031 &+ c &* 1033
}

// The same with the types exchanged: a * 5 + 1 * 100 + 8 * 10000 + 17
// + b * 1039 + c * 1049.
@_cdecl("ge_genTwoSwapped") @inline(never) public func genTwoSwapped(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gTwo(a, UInt8(truncatingIfNeeded: b), Small(p: b, q: c)) &+ b &* 1039 &+ c &* 1049
}

// gId(result: x8, &x: x0, T: x1). (a + b * 3) * 5 + c.
@_cdecl("ge_genIdInt") @inline(never) public func genIdInt(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gId(a &+ b &* 3) &* 5 &+ c
}

// A four-word value through gId: a * 2 + b * 3 + c * 5 + (a + c) * 7 + 1051.
@_cdecl("ge_genIdLarge") @inline(never) public func genIdLarge(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let l = gId(Large(p: a, q: b, r: c, s: a &+ c))
    return l.p &* 2 &+ l.q &* 3 &+ l.r &* 5 &+ l.s &* 7 &+ 1051
}

// gPick(result: x8, sel: x0, &x: x1, &y: x2, T: x3). a even: Small(b, c),
// else Small(c, b). p * 1061 + q * 1063 + a.
@_cdecl("ge_genPick") @inline(never) public func genPick(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let s = gPick(a, Small(p: b, q: c), Small(p: c, q: b))
    return s.p &* 1061 &+ s.q &* 1063 &+ a
}

// One requirement each, through gR0...gR3 (&x: x0, k: x1, T: x2, table: x3).
// Small(a, b).r0(c) + 41 + 1069.
@_cdecl("ge_genSlot0") @inline(never) public func genSlot0(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gR0(Small(p: a, q: b), c) &+ 1069
}

// Small(a, b).r1(c) + 43 + 1087.
@_cdecl("ge_genSlot1") @inline(never) public func genSlot1(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gR1(Small(p: a, q: b), c) &+ 1087
}

// Small(a, b).r2(c) + 47 + 1091.
@_cdecl("ge_genSlot2") @inline(never) public func genSlot2(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gR2(Small(p: a, q: b), c) &+ 1091
}

// Small(a, b).r3 + c * 53 + 1093.
@_cdecl("ge_genSlot3") @inline(never) public func genSlot3(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gR3(Small(p: a, q: b), c) &+ 1093
}

// Large(a, b, c, 7).r2(a) + 47.
@_cdecl("ge_genSlotLarge") @inline(never) public func genSlotLarge(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gR2(Large(p: a, q: b, r: c, s: 7), a)
}

// A class as T: x0 is the address of a word holding the object.
// Klass(a, b).r1(c) + 43.
@_cdecl("ge_genSlotClass") @inline(never) public func genSlotClass(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gR1(Klass(p: a, q: b), c)
}

// The default implementation behind slot 3: Dflt(a).r0(b) * 2 + Dflt(a).r1(b)
// + 77 + 47 + c * 1097.
@_cdecl("ge_genDefault") @inline(never) public func genDefault(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gR2(Dflt(p: a), b) &+ c &* 1097
}

// gTwoC(&x: x0, &y: x1, k: x2, T: x3, U: x4, T table: x5, U table: x6).
// Small(a, b).r1(c) * 3 + Large(b, c, a, 3).r3 + 19.
@_cdecl("ge_genTwoC") @inline(never) public func genTwoC(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gTwoC(Small(p: a, q: b), Large(p: b, q: c, r: a, s: 3), c)
}

// gMixed(&x, &y, k, T, U, U table). Small(b, c).r0(a) + 32 * 1000003.
@_cdecl("ge_genMixed") @inline(never) public func genMixed(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gMixed(Large(p: a, q: a, r: a, s: a), Small(p: b, q: c), a)
}

// gAssoc(&c: x0, k: x1, C: x2, C table: x3).
// Small(a, b).r1(a + c) * 3 + Crate.weight (c * 353 + a * 359 + 1200000).
@_cdecl("ge_genAssoc") @inline(never) public func genAssoc(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gAssoc(Crate(item: Small(p: a, q: b), w: c), a &+ c)
}

// A class-constrained parameter: the object itself is x0.
// t = a + c * b; t * 3 + t + (t * 367 + b * 373 + c * 379 + 1300000) * 7.
@_cdecl("ge_genClassBound") @inline(never) public func genClassBound(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gClassBound(Tally(total: a, step: b), c)
}

// Non-trivial value witnesses: Ref(Klass(a, b), c) copied twice and
// destroyed. r0(a + b) + r1(a + b) * 3.
@_cdecl("ge_genHoldRef") @inline(never) public func genHoldRef(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gHold(Ref(obj: Klass(p: a, q: b), n: c), a &+ b)
}

// The same with trivial witnesses: Small(a, b).r0(c) + Small(a, b).r1(c) * 3.
@_cdecl("ge_genHoldSmall") @inline(never) public func genHoldSmall(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gHold(Small(p: a, q: b), c)
}

// gSwap(&a: x0, &b: x1, T: x2) exchanges two Refs.
// Ref(Klass(b, c), a).r0(1) * 3 + Ref(Klass(a, b), c).r1(2).
@_cdecl("ge_genSwap") @inline(never) public func genSwap(_ a: Int, _ b: Int, _ c: Int) -> Int {
    var x = Ref(obj: Klass(p: a, q: b), n: c)
    var y = Ref(obj: Klass(p: b, q: c), n: a)
    gSwap(&x, &y)
    return x.r0(1) &* 3 &+ y.r1(2)
}

// gAssign(&dst: x0, &src: x1, T: x2). Ref(Klass(c, a), b).r2(a).
@_cdecl("ge_genAssign") @inline(never) public func genAssign(_ a: Int, _ b: Int, _ c: Int) -> Int {
    var x = Ref(obj: Klass(p: a, q: b), n: c)
    gAssign(&x, Ref(obj: Klass(p: c, q: a), n: b))
    return x.r2(a)
}

// A protocol extension method on a concrete value: ext(k: x0, Self: x1,
// Self table: x2, self: x20). Small(a, b).r1(c) * 5 + Small(a, b).r3 + 606.
@_cdecl("ge_genExt") @inline(never) public func genExt(_ a: Int, _ b: Int, _ c: Int) -> Int {
    Small(p: a, q: b).ext(c)
}

// MARK: generics inside this module

// Unspecialised at every level. LPoint(a, b).r2(c) * 3 + LPoint(a, b).r3.
@_cdecl("ge_localNever") @inline(never) public func localNever(_ a: Int, _ b: Int, _ c: Int) -> Int {
    lNever(LPoint(x: a, y: b), c)
}

// The same generic with an imported type: metadata and table come from
// the other image. Small(a, b).r2(c) * 3 + Small(a, b).r3 + 1103.
@_cdecl("ge_localNeverLib") @inline(never) public func localNeverLib(_ a: Int, _ b: Int, _ c: Int) -> Int {
    lNever(Small(p: a, q: b), c) &+ 1103
}

// Specialised when optimized. LPoint(a, b).r0(c) * 7 + LPoint(a, b).r1(c).
@_cdecl("ge_localSpec") @inline(never) public func localSpec(_ a: Int, _ b: Int, _ c: Int) -> Int {
    lSpec(LPoint(x: a, y: b), c)
}

// Small(a, b).r3 + Large(b, c, a, 5).tag * 3 + 60000 * 5 + c.
@_cdecl("ge_localSpecTwo") @inline(never) public func localSpecTwo(_ a: Int, _ b: Int, _ c: Int) -> Int {
    lSpecTwo(Small(p: a, q: b), Large(p: b, q: c, r: a, s: 5), c)
}

// Small(a, b).r3 + Crate.weight (c * 353 + a * 359 + 1200000) * 3 + b.
@_cdecl("ge_localAssoc") @inline(never) public func localAssoc(_ a: Int, _ b: Int, _ c: Int) -> Int {
    lAssoc(Crate(item: Small(p: a, q: b), w: c), b)
}

// MARK: generic types

// GBox<Small>.apply: Small(a, b).r1(a + 1) + c * 3.
@_cdecl("ge_gboxApply") @inline(never) public func gboxApply(_ a: Int, _ b: Int, _ c: Int) -> Int {
    GBox(v: Small(p: a, q: b), bias: c).apply(a &+ 1)
}

// GBox<Large>.apply: bias is past four words. Large(a, b, c, 9).r1(c) + b * 3.
@_cdecl("ge_gboxApplyLarge") @inline(never) public func gboxApplyLarge(_ a: Int, _ b: Int, _ c: Int) -> Int {
    GBox(v: Large(p: a, q: b, r: c, s: 9), bias: b).apply(c)
}

// The first vtable entry of GNode<Small>: Small(a, b).r2(b + 2) + c * 5.
@_cdecl("ge_gnodeVisit") @inline(never) public func gnodeVisit(_ a: Int, _ b: Int, _ c: Int) -> Int {
    GNode(v: Small(p: a, q: b), n: c).visit(b &+ 2)
}

// The second: Small(a, b).r0(c) + (a + b) * 7.
@_cdecl("ge_gnodeProbe") @inline(never) public func gnodeProbe(_ a: Int, _ b: Int, _ c: Int) -> Int {
    GNode(v: Small(p: a, q: b), n: a &+ b).probe(c)
}

// A local generic struct's method: LPoint(a, b).r1(a) + c * 463.
@_cdecl("ge_lwrapRun") @inline(never) public func lwrapRun(_ a: Int, _ b: Int, _ c: Int) -> Int {
    LWrap(inner: LPoint(x: a, y: b), m: c).run(a)
}

// A local generic class's method: LPoint(b, c).r2(a) + a * 467.
@_cdecl("ge_lcellRun") @inline(never) public func lcellRun(_ a: Int, _ b: Int, _ c: Int) -> Int {
    LCell(inner: LPoint(x: b, y: c), m: a).run(a)
}

// MARK: existentials opened here

// eMake(0, ...) is Small(a, b) in the inline buffer. One slot each.
// Small(a, b).r0(c) + 1109.
@_cdecl("ge_exSlot0") @inline(never) public func exSlot0(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eMake(0, a, b, c).r0(c) &+ 1109
}

// Small(a, b).r1(c) + 1117.
@_cdecl("ge_exSlot1") @inline(never) public func exSlot1(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eMake(0, a, b, c).r1(c) &+ 1117
}

// Small(a, b).r2(c) + 1123.
@_cdecl("ge_exSlot2") @inline(never) public func exSlot2(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eMake(0, a, b, c).r2(c) &+ 1123
}

// Small(a, b).r3 + c * 1129.
@_cdecl("ge_exSlot3") @inline(never) public func exSlot3(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eMake(0, a, b, c).r3 &+ c &* 1129
}

// A boxed payload: Large(a, b, c, c + 1).r1(a).
@_cdecl("ge_exLarge") @inline(never) public func exLarge(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eMake(1, a, b, c).r1(a)
}

// A class payload: Klass(a, b).r2(c).
@_cdecl("ge_exClass") @inline(never) public func exClass(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eMake(2, a, b, c).r2(c)
}

// The default witness: Dflt(a).r0(b) * 2 + Dflt(a).r1(b) + 77 + c.
@_cdecl("ge_exDefault") @inline(never) public func exDefault(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eMake(3, a, b, c).r2(b) &+ c
}

// A payload with a reference: Ref(Klass(a, b), c).r3.
@_cdecl("ge_exRef") @inline(never) public func exRef(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eMake(4, a, b, c).r3
}

// The implementation is chosen by a & 7 at run time: eMake(a, b, c, a + b).r0(c).
@_cdecl("ge_exDynamic") @inline(never) public func exDynamic(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eMake(a, b, c, a &+ b).r0(c)
}

// The extension method on an opened existential: the payload address is
// x20, the opened metadata x1, the table x2.
// Large(a, b, c, c + 1).r1(b) * 5 + Large(...).r3 + 606.
@_cdecl("ge_exExt") @inline(never) public func exExt(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eMake(1, a, b, c).ext(b)
}

// MARK: existentials built here

// A five-word container, payload inline. Small(a, b).r1(c) + 23.
@_cdecl("ge_exPassSmall") @inline(never) public func exPassSmall(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eR1(Small(p: a, q: b), c)
}

// The payload goes to a box. Large(a, b, c, 11).r1(a) + 23.
@_cdecl("ge_exPassLarge") @inline(never) public func exPassLarge(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eR1(Large(p: a, q: b, r: c, s: 11), a)
}

// Klass(a, b).r1(c) + 23.
@_cdecl("ge_exPassClass") @inline(never) public func exPassClass(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eR1(Klass(p: a, q: b), c)
}

// A local type and its local table. LPoint(a, b).r1(c) + 23.
@_cdecl("ge_exPassLocal") @inline(never) public func exPassLocal(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eR1(LPoint(x: a, y: b), c)
}

// Stored in a class, overwritten, then read: Small(b, a).r1(c) + c * 3.
@_cdecl("ge_exStore") @inline(never) public func exStore(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let s = Shelf(pad: c, slot: eMake(1, a, b, c))
    s.slot = eMake(0, b, a, c)
    return useShelf(s, c)
}

// Three containers in an array, 40 bytes apart:
// Small(a, b).r0(c) + Large(b, c, a, a + 1).r0(c) * 3 + Klass(c, a).r0(c) * 5.
@_cdecl("ge_exArray") @inline(never) public func exArray(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let xs: [any Shape4] = [eMake(0, a, b, c), eMake(1, b, c, a), eMake(2, c, a, b)]
    return xs[0].r0(c) &+ xs[1].r0(c) &* 3 &+ xs[2].r0(c) &* 5
}

// MARK: compositions

// Two tables. Small(a, b).r0(c) * 3 + Small(a, b).tag.
@_cdecl("ge_comp2Pass") @inline(never) public func comp2Pass(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eComp2(Small(p: a, q: b), c)
}

// s is Small(b, c) for an even a, else Klass(b, c).
// s.r1(c) * 3 + s.tag * 7 + its type's tagBase.
@_cdecl("ge_comp2Open") @inline(never) public func comp2Open(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let s = eMake2(a, b, c)
    return s.r1(c) &* 3 &+ s.tag &* 7 &+ type(of: s).tagBase
}

// Three tables, in the order Named, Shape4, Tagged.
// l = Large(a, b, c, 13): l.named(a) + l.r3 * 3 + l.tag * 5.
@_cdecl("ge_comp3Pass") @inline(never) public func comp3Pass(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eComp3(Large(p: a, q: b, r: c, s: 13), a)
}

// s is Large(a, b, c, c + 2) for an even c, else Klass(a, b).
// s.nameCode + s.r2(a) * 3 + s.tag * 5.
@_cdecl("ge_comp3Open") @inline(never) public func comp3Open(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let s = eMake3(c, a, b, c)
    return s.nameCode &+ s.r2(a) &* 3 &+ s.tag &* 5
}

// MARK: Any and AnyObject

// An Int in an Any (four words: buffer and metadata).
// (a + b) * 3 + 1 + c * 1151.
@_cdecl("ge_anyPassInt") @inline(never) public func anyPassInt(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eAny(a &+ b) &+ c &* 1151
}

// A Small in an Any. Small(a, b).r3 + 2 + c * 1153.
@_cdecl("ge_anyPassSmall") @inline(never) public func anyPassSmall(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eAny(Small(p: a, q: b)) &+ c &* 1153
}

// a & 3 picks the payload: the Int b: b * 3 + 1163. Small(b, c): r0(a).
// Klass(b, c): a + 1171. Large(b, c, b, c): r3.
@_cdecl("ge_anyOpen") @inline(never) public func anyOpen(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let x = eMakeAny(a, b, c)
    if let i = x as? Int { return i &* 3 &+ 1163 }
    if let s = x as? Small { return s.r0(a) }
    if x is Klass { return a &+ 1171 }
    return (x as! Large).r3
}

// Klass(a, b).r3 + 5 + c * 1181.
@_cdecl("ge_anyObjPass") @inline(never) public func anyObjPass(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eObj(Klass(p: a, q: b)) &+ c &* 1181
}

// a even: Klass(b, c): p * 1187 + q * 1193. Odd: a Tally: b + c + 1201.
@_cdecl("ge_anyObjOpen") @inline(never) public func anyObjOpen(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = eMakeObj(a, b, c)
    if let k = o as? Klass { return k.p &* 1187 &+ k.q &* 1193 }
    if o is Tally { return b &+ c &+ 1201 }
    return 1213
}

// MARK: casts

// s = eMake(a, b, c, a). Small(b, c): p * 1217 + q * 1223. Large(b, c, a,
// a + 1): s * 1229 + r. Klass: 1231 + c. Otherwise s.r0(c).
@_cdecl("ge_castConcrete") @inline(never) public func castConcrete(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let s = eMake(a, b, c, a)
    if let x = s as? Small { return x.p &* 1217 &+ x.q &* 1223 }
    if let l = s as? Large { return l.s &* 1229 &+ l.r }
    if s is Klass { return 1231 &+ c }
    return s.r0(c)
}

// A forced cast that always succeeds: Large(a, b, c, c + 1).
// s * 1237 + p * 1249 + q * 1259 + r.
@_cdecl("ge_castForced") @inline(never) public func castForced(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let l = eMake(1, a, b, c) as! Large
    return l.s &* 1237 &+ l.p &* 1249 &+ l.q &* 1259 &+ l.r
}

// One existential to another. eMake(a, b, c, b): Small, Large and Klass
// are Tagged: tag + 1277. Dflt and Ref are not: r3.
@_cdecl("ge_castExToEx") @inline(never) public func castExToEx(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let s = eMake(a, b, c, b)
    if let t = s as? any Tagged { return t.tag &+ 1277 }
    return s.r3
}

// a & 7 == 0: b * 1279 + c. Otherwise b + c * 1283.
@_cdecl("ge_castIs") @inline(never) public func castIs(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eMake(a, b, c, c) is Small ? b &* 1279 &+ c : b &+ c &* 1283
}

// MARK: metatypes

// The dynamic type of an existential, compared with metadata.
// a & 7 == 0: b + 1289. 1: c + 1291. Otherwise b + c + 1297.
@_cdecl("ge_metaTypeOf") @inline(never) public func metaTypeOf(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let t: any Shape4.Type = type(of: eMake(a, b, c, a))
    if t == Small.self { return b &+ 1289 }
    if t == Large.self { return c &+ 1291 }
    return b &+ c &+ 1297
}

// A static requirement through an existential metatype (metatype, table).
// (50000, 60000 or 70000 by a & 3) * 3 + b + c * 1301.
@_cdecl("ge_metaStatic") @inline(never) public func metaStatic(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eMeta(a).tagBase &* 3 &+ b &+ c &* 1301
}

// An existential metatype built here. a even: 50000, else 70000.
// + 29 + b * 1303 + c * 1307.
@_cdecl("ge_metaPass") @inline(never) public func metaPass(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let t: any Tagged.Type = a & 1 == 0 ? Small.self : Klass.self
    return eMetaBase(t) &+ b &* 1303 &+ c &* 1307
}

// type(of:) on an Any. a & 3 == 0 (an Int): b + 1319. 1 (Small): c + 1321.
// Otherwise b * c + 1327.
@_cdecl("ge_metaAny") @inline(never) public func metaAny(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let t: Any.Type = type(of: eMakeAny(a, b, c))
    if t == Int.self { return b &+ 1319 }
    if t == Small.self { return c &+ 1321 }
    return b &* c &+ 1327
}

// MARK: opaque result types

// The underlying type is the library's secret.
// Large(a, b, a + b, a - b).r2(c) + 1361.
@_cdecl("ge_opaqueLib") @inline(never) public func opaqueLib(_ a: Int, _ b: Int, _ c: Int) -> Int {
    makeOpaque(a, b).r2(c) &+ 1361
}

// The underlying type is known here. LPoint(a, b).r1(c) + 1367.
@_cdecl("ge_opaqueLocal") @inline(never) public func opaqueLocal(_ a: Int, _ b: Int, _ c: Int) -> Int {
    lOpaque(a, b).r1(c) &+ 1367
}

// MARK: class-constrained existentials

// Two words: the object and the table.
// t = a + c * b; t * 3 + t + (t * 367 + b * 373 + c * 379 + 1300000).
@_cdecl("ge_counterOpen") @inline(never) public func counterOpen(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let k = eCounter(a, b)
    let bumped = k.bump(c)
    return bumped &* 3 &+ k.total &+ k.scale(c)
}

// t = a + c * b; t + (t * 367 + b * 373 + c * 379 + 1300000) * 3 + 59.
@_cdecl("ge_counterPass") @inline(never) public func counterPass(_ a: Int, _ b: Int, _ c: Int) -> Int {
    eCount(Tally(total: a, step: b), c)
}

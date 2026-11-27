// Enums and Optionals at the machine level (-Onone, -O, -Osize).
//
// Each shape has a maker `mkX(a, b)` that picks the case from `a & 3` and
// puts `b` in the payload, and a weigher `wtX` that switches over the value
// and returns a different weighted integer per case, combined with the
// payload. A wrong case name, a wrong tag comparison or a wrong payload
// read changes the weigher's result. The `ef_X` entry is wtX(mkX(a, b)).
//
// Every constant is distinct so no two bodies fold.

public final class Box {
    public let v: Int                       // +0x10
    @inline(never) init(_ v: Int) { self.v = v }
}
public final class Crate {
    public let pad: Int                     // +0x10
    public let w: Int                       // +0x18
    @inline(never) init(_ w: Int) { self.pad = 0x5a5a; self.w = w }
}

// MARK: no-payload enums

// One byte, tag 0 or 1.
public enum E2 { case lo, hi }
// w0 = bit 1 of a. (Bit 0 would fold onto Flagged.on's getter at -O.)
@inline(never) public func mkE2(_ a: Int, _ b: Int) -> E2 { (a & 2) == 0 ? .lo : .hi }
// e in w0 (one bit matters), k in x1. lo: k*3+101. hi: k*5+202.
@inline(never) public func wtE2(_ e: E2, _ k: Int) -> Int {
    switch e {
    case .lo: return k &* 3 &+ 101
    case .hi: return k &* 5 &+ 202
    }
}
@_cdecl("ef_E2") public func efE2(_ a: Int, _ b: Int) -> Int { wtE2(mkE2(a, b), b) }

// One byte, tags 0, 1, 2.
public enum E3 { case x, y, z }
// a&3 == 0: x (0). == 1: y (1). else z (2).
@inline(never) public func mkE3(_ a: Int, _ b: Int) -> E3 {
    switch a & 3 {
    case 0: return .x
    case 1: return .y
    default: return .z
    }
}
// x: k*7+301. y: k*11+302. z: k*13+303.
@inline(never) public func wtE3(_ e: E3, _ k: Int) -> Int {
    switch e {
    case .x: return k &* 7 &+ 301
    case .y: return k &* 11 &+ 302
    case .z: return k &* 13 &+ 303
    }
}
@_cdecl("ef_E3") public func efE3(_ a: Int, _ b: Int) -> Int { wtE3(mkE3(a, b), b) }

// E255?: one byte, nil is 255. The low byte of a is the tag; 255 gives nil.
@inline(never) public func mkO255(_ a: Int, _ b: Int) -> E255? { E255(rawValue: UInt8(truncatingIfNeeded: a)) }
// nil: k*2+9000. c0: k*3+1. c1: k*5+2. c127: k*7+3. c128: k*11+4.
// c254: k*13+5. any other case: k*17+6.
@inline(never) public func wtO255(_ e: E255?, _ k: Int) -> Int {
    switch e {
    case nil: return k &* 2 &+ 9000
    case .c0: return k &* 3 &+ 1
    case .c1: return k &* 5 &+ 2
    case .c127: return k &* 7 &+ 3
    case .c128: return k &* 11 &+ 4
    case .c254: return k &* 13 &+ 5
    default: return k &* 17 &+ 6
    }
}
@_cdecl("ef_O255") public func efO255(_ a: Int, _ b: Int) -> Int { wtO255(mkO255(a, b), b) }

// E256?: every byte value is a case, so nil is a second byte: tag byte 1.
// The low 16 bits of a are the tag; 256 and above give nil.
@inline(never) public func mkO256(_ a: Int, _ b: Int) -> E256? { E256(rawValue: UInt16(truncatingIfNeeded: a)) }
// nil: k*2+9100. c0: k*3+21. c1: k*5+22. c127: k*7+23. c128: k*11+24.
// c255: k*13+25. any other case: k*17+26.
@inline(never) public func wtO256(_ e: E256?, _ k: Int) -> Int {
    switch e {
    case nil: return k &* 2 &+ 9100
    case .c0: return k &* 3 &+ 21
    case .c1: return k &* 5 &+ 22
    case .c127: return k &* 7 &+ 23
    case .c128: return k &* 11 &+ 24
    case .c255: return k &* 13 &+ 25
    default: return k &* 17 &+ 26
    }
}
@_cdecl("ef_O256") public func efO256(_ a: Int, _ b: Int) -> Int { wtO256(mkO256(a, b), b) }

// E257?: a 16-bit tag, nil is 257. 257 and above give nil.
@inline(never) public func mkO257(_ a: Int, _ b: Int) -> E257? { E257(rawValue: UInt16(truncatingIfNeeded: a)) }
// nil: k*2+9200. c0: k*3+31. c1: k*5+32. c255: k*7+33. c256: k*11+34.
// any other case: k*17+36.
@inline(never) public func wtO257(_ e: E257?, _ k: Int) -> Int {
    switch e {
    case nil: return k &* 2 &+ 9200
    case .c0: return k &* 3 &+ 31
    case .c1: return k &* 5 &+ 32
    case .c255: return k &* 7 &+ 33
    case .c256: return k &* 11 &+ 34
    default: return k &* 17 &+ 36
    }
}
@_cdecl("ef_O257") public func efO257(_ a: Int, _ b: Int) -> Int { wtO257(mkO257(a, b), b) }

// MARK: single-payload enums

// Int has no spare pattern: payload in x0, a one-bit tag in w1. The empty
// cases have tag 1 and their index (a: 0, b: 1) in x0.
public enum SPInt { case v(Int), a, b }
// a&3 == 0: v(b). 1: a. 2: b. 3: v(b+7).
@inline(never) public func mkSPInt(_ a: Int, _ b: Int) -> SPInt {
    switch a & 3 {
    case 0: return .v(b)
    case 1: return .a
    case 2: return .b
    default: return .v(b &+ 7)
    }
}
// v(x): x*3+1000. a: 2001. b: 3002.
@inline(never) public func wtSPInt(_ e: SPInt) -> Int {
    switch e {
    case .v(let x): return x &* 3 &+ 1000
    case .a: return 2001
    case .b: return 3002
    }
}
@_cdecl("ef_SPInt") public func efSPInt(_ a: Int, _ b: Int) -> Int { wtSPInt(mkSPInt(a, b)) }

// Bool's byte has spare values from 2: v(false) 0, v(true) 1, a 2, b 3, c 4.
public enum SPBool { case v(Bool), a, b, c }
// a&3 == 0: v(b is odd). 1: a. 2: b. 3: c.
@inline(never) public func mkSPBool(_ a: Int, _ b: Int) -> SPBool {
    switch a & 3 {
    case 0: return .v((b & 1) != 0)
    case 1: return .a
    case 2: return .b
    default: return .c
    }
}
// v(true): 41. v(false): 43. a: 47. b: 53. c: 59.
@inline(never) public func wtSPBool(_ e: SPBool) -> Int {
    switch e {
    case .v(let t): return t ? 41 : 43
    case .a: return 47
    case .b: return 53
    case .c: return 59
    }
}
@_cdecl("ef_SPBool") public func efSPBool(_ a: Int, _ b: Int) -> Int { wtSPBool(mkSPBool(a, b)) }

// A class reference: one register. a is the pointer value 0, b is 1.
public enum SPClass { case v(Box), a, b }
// a&3 == 0: v(Box(b)). 1: a. 2: b. 3: v(Box(b+9)).
@inline(never) public func mkSPClass(_ a: Int, _ b: Int) -> SPClass {
    switch a & 3 {
    case 0: return .v(Box(b))
    case 1: return .a
    case 2: return .b
    default: return .v(Box(b &+ 9))
    }
}
// v(o): o.v*7+1100. a: 2203. b: 3305.
@inline(never) public func wtSPClass(_ e: SPClass) -> Int {
    switch e {
    case .v(let o): return o.v &* 7 &+ 1100
    case .a: return 2203
    case .b: return 3305
    }
}
@_cdecl("ef_SPClass") public func efSPClass(_ a: Int, _ b: Int) -> Int { wtSPClass(mkSPClass(a, b)) }

// A raw pointer's only spare pattern is null: a is x0 == 0 with tag 0, and
// b needs the tag bit in w1 (tag 1, x0 == 0).
public enum SPPtr { case v(UnsafeRawPointer), a, b }
// a&3 == 0: v(b | 0x1000). 1: a. 2: b. 3: v(b | 0x2000).
@inline(never) public func mkSPPtr(_ a: Int, _ b: Int) -> SPPtr {
    switch a & 3 {
    case 0: return .v(unsafeBitCast(b | 0x1000, to: UnsafeRawPointer.self))
    case 1: return .a
    case 2: return .b
    default: return .v(unsafeBitCast(b | 0x2000, to: UnsafeRawPointer.self))
    }
}
// v(p): p*3+1. a: 4409. b: 5511.
@inline(never) public func wtSPPtr(_ e: SPPtr) -> Int {
    switch e {
    case .v(let p): return Int(bitPattern: p) &* 3 &+ 1
    case .a: return 4409
    case .b: return 5511
    }
}
@_cdecl("ef_SPPtr") public func efSPPtr(_ a: Int, _ b: Int) -> Int { wtSPPtr(mkSPPtr(a, b)) }

// String's spare patterns are in its second word (x1): a is x1 == 0, b is
// x1 == 1, and x0 is zero for both.
public enum SPString { case v(String), a, b }
// a&3 == 0: v(decimal text of b & 0xfff). 1: a. 2: b. 3: v("q").
@inline(never) public func mkSPString(_ a: Int, _ b: Int) -> SPString {
    switch a & 3 {
    case 0: return .v(String(b & 0xfff))
    case 1: return .a
    case 2: return .b
    default: return .v("q")
    }
}
// v(s): (UTF-8 length of s)*11+600. a: 6601. b: 7703.
@inline(never) public func wtSPString(_ e: SPString) -> Int {
    switch e {
    case .v(let s): return s.utf8.count &* 11 &+ 600
    case .a: return 6601
    case .b: return 7703
    }
}
@_cdecl("ef_SPString") public func efSPString(_ a: Int, _ b: Int) -> Int { wtSPString(mkSPString(a, b)) }

// A struct with a spare pattern: the Bool's byte. a is on == 2, b is
// on == 3, and n is zero for both.
public struct Flagged { public var on: Bool; public var n: UInt8 }
public enum SPSpare { case v(Flagged), a, b }
// a&3 == 0: v(on: b is odd, n: low byte of b >> 1). 1: a. 2: b.
// 3: v(on: true, n: 77).
@inline(never) public func mkSPSpare(_ a: Int, _ b: Int) -> SPSpare {
    switch a & 3 {
    case 0: return .v(Flagged(on: (b & 1) != 0, n: UInt8(truncatingIfNeeded: b >> 1)))
    case 1: return .a
    case 2: return .b
    default: return .v(Flagged(on: true, n: 77))
    }
}
// v(f): f.n*2 + (f.on ? 8001 : 8000). a: 8803. b: 9907.
@inline(never) public func wtSPSpare(_ e: SPSpare) -> Int {
    switch e {
    case .v(let f): return Int(f.n) &* 2 &+ (f.on ? 8001 : 8000)
    case .a: return 8803
    case .b: return 9907
    }
}
@_cdecl("ef_SPSpare") public func efSPSpare(_ a: Int, _ b: Int) -> Int { wtSPSpare(mkSPSpare(a, b)) }

// A struct with no spare pattern: eight payload bytes and a tag byte. The
// empty cases have tag 1 and their index in the payload's low 32 bits.
public struct Pair32 { public var x: Int32; public var y: Int32 }
public enum SPFull { case v(Pair32), a, b }
// a&3 == 0: v(x: low 32 of b, y: high 32 of b). 1: a. 2: b.
// 3: v(x: 19, y: low 32 of b).
@inline(never) public func mkSPFull(_ a: Int, _ b: Int) -> SPFull {
    switch a & 3 {
    case 0: return .v(Pair32(x: Int32(truncatingIfNeeded: b), y: Int32(truncatingIfNeeded: b >> 32)))
    case 1: return .a
    case 2: return .b
    default: return .v(Pair32(x: 19, y: Int32(truncatingIfNeeded: b)))
    }
}
// v(p): p.x*3 + p.y*5 + 10000 (each sign-extended). a: 10101. b: 10202.
@inline(never) public func wtSPFull(_ e: SPFull) -> Int {
    switch e {
    case .v(let p): return Int(p.x) &* 3 &+ Int(p.y) &* 5 &+ 10000
    case .a: return 10101
    case .b: return 10202
    }
}
@_cdecl("ef_SPFull") public func efSPFull(_ a: Int, _ b: Int) -> Int { wtSPFull(mkSPFull(a, b)) }

// MARK: multi-payload enums

// Two native class references: the tag is in the pointer's top spare bits.
// l is the raw pointer, r has bit 62, the empty cases have bit 63 and their
// index in the occupied bits.
public enum MPRef { case l(Box), r(Crate), e0, e1 }
// a&3 == 0: l(Box(b)). 1: r(Crate(b)). 2: e0. 3: e1.
@inline(never) public func mkMPRef(_ a: Int, _ b: Int) -> MPRef {
    switch a & 3 {
    case 0: return .l(Box(b))
    case 1: return .r(Crate(b))
    case 2: return .e0
    default: return .e1
    }
}
// l(o): o.v*3+20000. r(c): c.w*5+30000. e0: 40001. e1: 50002.
@inline(never) public func wtMPRef(_ e: MPRef) -> Int {
    switch e {
    case .l(let o): return o.v &* 3 &+ 20000
    case .r(let c): return c.w &* 5 &+ 30000
    case .e0: return 40001
    case .e1: return 50002
    }
}
@_cdecl("ef_MPRef") public func efMPRef(_ a: Int, _ b: Int) -> Int { wtMPRef(mkMPRef(a, b)) }

// An Int and a class: Int has no spare bits, so the tag is an extra byte in
// w1. i is tag 0, o is tag 1, z is tag 2 with x0 zero.
public enum MPIntRef { case i(Int), o(Box), z }
// a&3 == 0: i(b). 1: o(Box(b)). 2: z. 3: i(b ^ 0x55).
@inline(never) public func mkMPIntRef(_ a: Int, _ b: Int) -> MPIntRef {
    switch a & 3 {
    case 0: return .i(b)
    case 1: return .o(Box(b))
    case 2: return .z
    default: return .i(b ^ 0x55)
    }
}
// i(x): x*7+60000. o(p): p.v*11+70000. z: 80003.
@inline(never) public func wtMPIntRef(_ e: MPIntRef) -> Int {
    switch e {
    case .i(let x): return x &* 7 &+ 60000
    case .o(let p): return p.v &* 11 &+ 70000
    case .z: return 80003
    }
}
@_cdecl("ef_MPIntRef") public func efMPIntRef(_ a: Int, _ b: Int) -> Int { wtMPIntRef(mkMPIntRef(a, b)) }

// Payloads of 1, 6 and 16 bytes: two payload words in x0 and x1 and a tag
// byte in w2. s is tag 0, m is 1, l is 2, none is 3.
public enum MPStructs { case s(Int8), m(Int32, Int16), l(Int, Int), none }
// a&3 == 0: s(low byte of b). 1: m(low 32 of b, low 16 of b >> 32).
// 2: l(b, a). 3: none.
@inline(never) public func mkMPStructs(_ a: Int, _ b: Int) -> MPStructs {
    switch a & 3 {
    case 0: return .s(Int8(truncatingIfNeeded: b))
    case 1: return .m(Int32(truncatingIfNeeded: b), Int16(truncatingIfNeeded: b >> 32))
    case 2: return .l(b, a)
    default: return .none
    }
}
// s(x): x*3+90000. m(p, q): p*5+q*7+91000. l(x, y): x*11+y*13+92000.
// none: 93001. Narrow payloads are sign-extended.
@inline(never) public func wtMPStructs(_ e: MPStructs) -> Int {
    switch e {
    case .s(let x): return Int(x) &* 3 &+ 90000
    case .m(let p, let q): return Int(p) &* 5 &+ Int(q) &* 7 &+ 91000
    case .l(let x, let y): return x &* 11 &+ y &* 13 &+ 92000
    case .none: return 93001
    }
}
@_cdecl("ef_MPStructs") public func efMPStructs(_ a: Int, _ b: Int) -> Int { wtMPStructs(mkMPStructs(a, b)) }

// MARK: indirect cases

// Every payload case is a box reference; the tag is in the pointer's spare
// bits and the payload is read from the box at +0x10.
public indirect enum Tree { case leaf(Int), node(Tree, Tree), empty }
// a&3 == 0: leaf(b). 1: node(leaf(b), empty). 2: empty.
// 3: node(leaf(a), leaf(b)).
@inline(never) public func mkTree(_ a: Int, _ b: Int) -> Tree {
    switch a & 3 {
    case 0: return .leaf(b)
    case 1: return .node(.leaf(b), .empty)
    case 2: return .empty
    default: return .node(.leaf(a), .leaf(b))
    }
}
// leaf(x): x*3+110000. node(l, r): wt(l)*5 + wt(r)*7 + 120000.
// empty: 130001.
@inline(never) public func wtTree(_ e: Tree) -> Int {
    switch e {
    case .leaf(let x): return x &* 3 &+ 110000
    case .node(let l, let r): return wtTree(l) &* 5 &+ wtTree(r) &* 7 &+ 120000
    case .empty: return 130001
    }
}
@_cdecl("ef_Tree") public func efTree(_ a: Int, _ b: Int) -> Int { wtTree(mkTree(a, b)) }

// MARK: Optionals

// Int??: payload in x0, one tag byte in w1: 0 some(some), 1 some(nil),
// 2 nil.
// a&3 == 0: b. 1: some(nil). 2: nil. 3: b+3.
@inline(never) public func mkOInt2(_ a: Int, _ b: Int) -> Int?? {
    switch a & 3 {
    case 0: return .some(.some(b))
    case 1: return .some(.none)
    case 2: return .none
    default: return .some(.some(b &+ 3))
    }
}
// some(some(x)): x*3+140000. some(nil): 150001. nil: 160002.
@inline(never) public func wtOInt2(_ e: Int??) -> Int {
    switch e {
    case .some(.some(let x)): return x &* 3 &+ 140000
    case .some(.none): return 150001
    case .none: return 160002
    }
}
@_cdecl("ef_OInt2") public func efOInt2(_ a: Int, _ b: Int) -> Int { wtOInt2(mkOInt2(a, b)) }

// Bool??: one byte: false 0, true 1, some(nil) 2, nil 3.
// a&3 == 0: b is odd. 1: some(nil). 2: nil. 3: false.
@inline(never) public func mkOBool2(_ a: Int, _ b: Int) -> Bool?? {
    switch a & 3 {
    case 0: return .some(.some((b & 1) != 0))
    case 1: return .some(.none)
    case 2: return .none
    default: return .some(.some(false))
    }
}
// true: 171. false: 173. some(nil): 179. nil: 181.
@inline(never) public func wtOBool2(_ e: Bool??) -> Int {
    switch e {
    case .some(.some(let t)): return t ? 171 : 173
    case .some(.none): return 179
    case .none: return 181
    }
}
@_cdecl("ef_OBool2") public func efOBool2(_ a: Int, _ b: Int) -> Int { wtOBool2(mkOBool2(a, b)) }

// String?: nil is the second word (x1) zero.
// a&3 == 0: decimal text of b & 0xff. 1: nil. 2: "". 3: a 26-byte literal.
@inline(never) public func mkOString(_ a: Int, _ b: Int) -> String? {
    switch a & 3 {
    case 0: return String(b & 0xff)
    case 1: return nil
    case 2: return ""
    default: return "abcdefghijklmnopqrstuvwxyz"
    }
}
// nil: 190001. some(s): (UTF-8 length of s)*13+191000.
@inline(never) public func wtOString(_ e: String?) -> Int {
    switch e {
    case .none: return 190001
    case .some(let s): return s.utf8.count &* 13 &+ 191000
    }
}
@_cdecl("ef_OString") public func efOString(_ a: Int, _ b: Int) -> Int { wtOString(mkOString(a, b)) }

// MPRef?: nil is the next unused pattern of the tag bits, not zero.
// a&3 == 0: l(Box(b)). 1: nil. 2: e1. 3: r(Crate(b)).
@inline(never) public func mkOMPRef(_ a: Int, _ b: Int) -> MPRef? {
    switch a & 3 {
    case 0: return .l(Box(b))
    case 1: return nil
    case 2: return .e1
    default: return .r(Crate(b))
    }
}
// l(o): o.v*3+200000. r(c): c.w*5+210000. e0: 220001. e1: 230002.
// nil: 240003.
@inline(never) public func wtOMPRef(_ e: MPRef?) -> Int {
    switch e {
    case .some(.l(let o)): return o.v &* 3 &+ 200000
    case .some(.r(let c)): return c.w &* 5 &+ 210000
    case .some(.e0): return 220001
    case .some(.e1): return 230002
    case .none: return 240003
    }
}
@_cdecl("ef_OMPRef") public func efOMPRef(_ a: Int, _ b: Int) -> Int { wtOMPRef(mkOMPRef(a, b)) }

// An Optional closure: function in x0, context in x1; nil is x0 == 0 and
// the context word is not part of the test.
// a&3 == 0: { $0 + b }. 1: nil. 2: { $0 * b }. 3: { $0 ^ b }.
@inline(never) public func mkOClosure(_ a: Int, _ b: Int) -> ((Int) -> Int)? {
    switch a & 3 {
    case 0: return { $0 &+ b }
    case 1: return nil
    case 2: return { $0 &* b }
    default: return { $0 ^ b }
    }
}
// nil: k+250001. some(f): f(k)*3+260000.
@inline(never) public func wtOClosure(_ e: ((Int) -> Int)?, _ k: Int) -> Int {
    switch e {
    case .none: return k &+ 250001
    case .some(let f): return f(k) &* 3 &+ 260000
    }
}
@_cdecl("ef_OClosure") public func efOClosure(_ a: Int, _ b: Int) -> Int { wtOClosure(mkOClosure(a, b), a) }

// Any?: four words, nil is the metadata word (the fourth) zero.
// a&3 == 0: b as Int. 1: nil. 2: Box(b). 3: (b is odd) as Bool.
@inline(never) public func mkOAny(_ a: Int, _ b: Int) -> Any? {
    switch a & 3 {
    case 0: return b
    case 1: return nil
    case 2: return Box(b)
    default: return (b & 1) != 0
    }
}
// nil: 270001. an Int x: x*3+280000. a Box o: o.v*5+290000.
// anything else: 300007.
@inline(never) public func wtOAny(_ e: Any?) -> Int {
    guard let value = e else { return 270001 }
    if let x = value as? Int { return x &* 3 &+ 280000 }
    if let o = value as? Box { return o.v &* 5 &+ 290000 }
    return 300007
}
@_cdecl("ef_OAny") public func efOAny(_ a: Int, _ b: Int) -> Int { wtOAny(mkOAny(a, b)) }

// MARK: comparing two enums

// Two one-byte tags compared. equal: 311. different: 313.
@inline(never) public func sameE3(_ p: E3, _ q: E3) -> Int { p == q ? 311 : 313 }
@_cdecl("ef_sameE3") public func efSameE3(_ a: Int, _ b: Int) -> Int { sameE3(mkE3(a, b), mkE3(b, a)) }

// Two (x0, w1) pairs. both v with equal payloads: 331. both v, different
// payloads: 337. both a: 347. both b: 349. different cases: 353.
@inline(never) public func sameSPInt(_ p: SPInt, _ q: SPInt) -> Int {
    switch (p, q) {
    case (.v(let x), .v(let y)): return x == y ? 331 : 337
    case (.a, .a): return 347
    case (.b, .b): return 349
    default: return 353
    }
}
@_cdecl("ef_sameSPInt") public func efSameSPInt(_ a: Int, _ b: Int) -> Int { sameSPInt(mkSPInt(a, b), mkSPInt(b, a)) }

// Two spare-bit tags compared, payloads ignored. both l: 401. both r: 409.
// both e0: 419. both e1: 421. different cases: 431.
@inline(never) public func sameMPRef(_ p: MPRef, _ q: MPRef) -> Int {
    switch (p, q) {
    case (.l, .l): return 401
    case (.r, .r): return 409
    case (.e0, .e0): return 419
    case (.e1, .e1): return 421
    default: return 431
    }
}
@_cdecl("ef_sameMPRef") public func efSameMPRef(_ a: Int, _ b: Int) -> Int { sameMPRef(mkMPRef(a, b), mkMPRef(b, a)) }

// MARK: mapping over an Optional

// Int?: payload in x0, tag byte in w1 (1 is nil).
// a is even: b. a is odd: nil.
@inline(never) public func mkOInt(_ a: Int, _ b: Int) -> Int? { (a & 1) == 0 ? b : nil }
// nil: 320001. some(x): x*17+330000.
@inline(never) public func wtOInt(_ e: Int?) -> Int {
    switch e {
    case .none: return 320001
    case .some(let x): return x &* 17 &+ 330000
    }
}
// nil stays nil; some(x) becomes some(x*k+5).
@inline(never) public func mapInt(_ e: Int?, _ k: Int) -> Int? { e.map { $0 &* k &+ 5 } }
@_cdecl("ef_mapInt") public func efMapInt(_ a: Int, _ b: Int) -> Int { wtOInt(mapInt(mkOInt(a, b), a)) }

// Box?: one register, nil is zero.
// a is even: Box(b+61). a is odd: nil.
@inline(never) public func mkOBox(_ a: Int, _ b: Int) -> Box? { (a & 1) == 0 ? Box(b &+ 61) : nil }
// nil stays nil (x0 0, w1 1); some(o) becomes some(o.v+77).
@inline(never) public func mapBox(_ e: Box?) -> Int? { e.map { $0.v &+ 77 } }
@_cdecl("ef_mapBox") public func efMapBox(_ a: Int, _ b: Int) -> Int { wtOInt(mapBox(mkOBox(a, b))) }

// MARK: controls (no enum: these must render exactly)

// a*3 + b + 1234.
@inline(never) public func ctlAdd(_ a: Int, _ b: Int) -> Int { a &* 3 &+ b &+ 1234 }
@_cdecl("ef_ctlAdd") public func efCtlAdd(_ a: Int, _ b: Int) -> Int { ctlAdd(a, b) }

// a is even: b+501. a is odd: b-502. The same test as mkE2 and mkOInt.
@inline(never) public func ctlPick(_ a: Int, _ b: Int) -> Int { (a & 1) == 0 ? b &+ 501 : b &- 502 }
@_cdecl("ef_ctlPick") public func efCtlPick(_ a: Int, _ b: Int) -> Int { ctlPick(a, b) }

// A class field read with no enum around it: o.v*9+77.
@inline(never) public func ctlBoxRead(_ o: Box) -> Int { o.v &* 9 &+ 77 }
@_cdecl("ef_ctlBoxRead") public func efCtlBoxRead(_ a: Int, _ b: Int) -> Int { ctlBoxRead(Box(a ^ b)) }

// Two registers with no tag: (a+1, b+2). The neighbour of every
// payload-and-tag result.
@inline(never) public func ctlTuple(_ a: Int, _ b: Int) -> (Int, Int) { (a &+ 1, b &+ 2) }
@_cdecl("ef_ctlTuple") public func efCtlTuple(_ a: Int, _ b: Int) -> Int {
    let t = ctlTuple(a, b)
    return t.0 &* 19 &+ t.1
}

// A three-way integer switch with no enum: the neighbour of wtE3.
// e == 0: k*7+501. e == 1: k*11+502. otherwise: k*13+503.
@inline(never) public func ctlSwitch(_ e: UInt8, _ k: Int) -> Int {
    switch e {
    case 0: return k &* 7 &+ 501
    case 1: return k &* 11 &+ 502
    default: return k &* 13 &+ 503
    }
}
@_cdecl("ef_ctlSwitch") public func efCtlSwitch(_ a: Int, _ b: Int) -> Int { ctlSwitch(UInt8(truncatingIfNeeded: a & 3), b) }

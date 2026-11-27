// How Swift passes and returns structs and tuples in registers (-Onone, -O, -Osize).
//
// Generated. Every function under test returns one Int: a per-function
// constant plus each field and each later argument times its own odd weight, all
// wrapping. A narrow integer enters by its own sign (Int8 sign-extends, UInt8
// zero-extends), a Bool as 0 or 1, a float by its bit pattern, a pointer by its
// address, a class reference by its Box.v, and an Optional as weight*payload when
// present and weight*107+1 when nil. The `lowered` line is the function's LLVM
// signature measured with `swiftc -O -emit-ir`. The e_ functions are C entry
// points for a native driver: they build the values from eight integers and are
// not under test.

public final class Box { public let v: Int; public init(_ v: Int) { self.v = v } }

// single-field wrapper: one i64
public struct Wrap1 { public var a: Int }
// two i64
public struct Pair { public var a: Int; public var b: Int }
// three i64
public struct Tri { public var a: Int; public var b: UInt; public var c: Int }
// exactly four register units
public struct Quad { public var a: Int; public var b: Int; public var c: Int; public var d: Int }
// five units: by address
public struct Five { public var a: Int; public var b: Int; public var c: Int; public var d: Int; public var e: Int }
// six units: by address
public struct Six { public var a: Int; public var b: Int32; public var c: Int; public var d: Int16; public var e: Int; public var f: Int8 }
// i8@0 i16@2 i32@4 packed into one 8-byte unit
public struct Packed { public var a: Int8; public var b: Int16; public var c: Int32 }
// bool@0 u8@1 u16@2 u32@4 packed into one unit
public struct PackedU { public var a: Bool; public var b: UInt8; public var c: UInt16; public var d: UInt32 }
// i8, padding to 8, i64, i8: three units
public struct Straddle { public var a: Int8; public var b: Int; public var c: Int8 }
// u8@0 u16@2 u32@4 in one unit, then u64
public struct UMix { public var a: UInt8; public var b: UInt16; public var c: UInt32; public var d: UInt }
// integer then double: x and d
public struct IntDouble { public var a: Int; public var b: Double }
// double then integer: d and x
public struct DoubleInt { public var a: Double; public var b: Int }
// i32@0, float@4, i32@8: the float sits in the first unit beside an integer
public struct FloatMid { public var a: Int32; public var b: Float; public var c: Int32 }
// i16, Float16, i16, i16 in ONE 8-byte unit: the half splits the integers
public struct HalfMid { public var a: Int16; public var b: Float16; public var c: Int16; public var d: Int16 }
// i32, float, double, i64: four scalars over two banks
public struct MixFour { public var a: Int32; public var b: Float; public var c: Double; public var d: Int }
// four doubles: d0..d3
public struct FourD { public var a: Double; public var b: Double; public var c: Double; public var d: Double }
// two floats in one 8-byte unit: s0, s1
public struct TwoF { public var a: Float; public var b: Float }
// five floats: by address
public struct FiveF { public var a: Float; public var b: Float; public var c: Float; public var d: Float; public var e: Float }
// raw pointer, class reference, Bool
public struct PtrRef { public var p: UnsafeRawPointer?; public var r: Box; public var f: Bool }
// Int32? (payload + tag in one unit) then Int? (i64 + tag byte)
public struct Opts { public var a: Int32?; public var b: Int? }
// Double? (payload as integer bits + tag) then Int8
public struct OptD { public var a: Double?; public var b: Int8 }
// no stored fields: takes no register
public struct Empty { }
// Pair, Int32, Packed nested: i64, i64, i32, then a packed unit
public struct Nested { public var p: Pair; public var k: Int32; public var q: Packed }
// a tuple (Int16, Int) then UInt8
public struct WithTuple { public var t: (Int16, Int); public var u: UInt8 }
// empty fields around an Int and an Int32
public struct Hollow { public var e: Empty; public var a: Int; public var f: Empty; public var b: Int32 }

// sThenInts_Wrap1: p0 single-field wrapper: one i64
// result = 1001 + 3*p0.a + 5*p1 + 7*p2
// lowered: i64 (i64, i64, i64)
@inline(never) public func sThenInts_Wrap1(_ p0: Wrap1, _ p1: Int, _ p2: Int) -> Int {
    var h = 1001
    h = h &+ p0.a &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    return h
}

// intsThenS_Wrap1: p3 single-field wrapper: one i64
// result = 1003 + 3*p0 + 5*p1 + 7*p2 + 11*p3.a
// lowered: i64 (i64, i64, i64, i64)
@inline(never) public func intsThenS_Wrap1(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Wrap1) -> Int {
    var h = 1003
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3.a &* 11
    return h
}

// make_Wrap1: returns Wrap1 (single-field wrapper: one i64); each field is one argument plus its own constant, narrowed to the field
// a = a0+300
// lowered: i64 (i64)
@inline(never) public func make_Wrap1(_ a0: Int) -> Wrap1 {
    return Wrap1(a: a0 &+ 300)
}

// sThenInts_Pair: p0 two i64
// result = 1007 + 3*p0.a + 5*p0.b + 7*p1 + 11*p2 + 13*p3
// lowered: i64 (i64, i64, i64, i64, i64)
@inline(never) public func sThenInts_Pair(_ p0: Pair, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1007
    h = h &+ p0.a &* 3
    h = h &+ p0.b &* 5
    h = h &+ p1 &* 7
    h = h &+ p2 &* 11
    h = h &+ p3 &* 13
    return h
}

// intsThenS_Pair: p2 two i64
// result = 1009 + 3*p0 + 5*p1 + 7*p2.a + 11*p2.b
// lowered: i64 (i64, i64, i64, i64)
@inline(never) public func intsThenS_Pair(_ p0: Int, _ p1: Int, _ p2: Pair) -> Int {
    var h = 1009
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2.a &* 7
    h = h &+ p2.b &* 11
    return h
}

// make_Pair: returns Pair (two i64); each field is one argument plus its own constant, narrowed to the field
// a = a0+600, b = a1+601
// lowered: { i64, i64 } (i64, i64)
@inline(never) public func make_Pair(_ a0: Int, _ a1: Int) -> Pair {
    return Pair(a: a0 &+ 600, b: a1 &+ 601)
}

// sThenInts_Tri: p0 three i64
// result = 1013 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p1 + 13*p2
// lowered: i64 (i64, i64, i64, i64, i64)
@inline(never) public func sThenInts_Tri(_ p0: Tri, _ p1: Int, _ p2: Int) -> Int {
    var h = 1013
    h = h &+ p0.a &* 3
    h = h &+ Int(bitPattern: p0.b) &* 5
    h = h &+ p0.c &* 7
    h = h &+ p1 &* 11
    h = h &+ p2 &* 13
    return h
}

// intsThenS_Tri: p3 three i64
// result = 1015 + 3*p0 + 5*p1 + 7*p2 + 11*p3.a + 13*p3.b + 17*p3.c
// lowered: i64 (i64, i64, i64, i64, i64, i64)
@inline(never) public func intsThenS_Tri(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Tri) -> Int {
    var h = 1015
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3.a &* 11
    h = h &+ Int(bitPattern: p3.b) &* 13
    h = h &+ p3.c &* 17
    return h
}

// make_Tri: returns Tri (three i64); each field is one argument plus its own constant, narrowed to the field
// a = a0+900, b = a1+901, c = a0+902
// lowered: { i64, i64, i64 } (i64, i64)
@inline(never) public func make_Tri(_ a0: Int, _ a1: Int) -> Tri {
    return Tri(a: a0 &+ 900, b: UInt(bitPattern: a1 &+ 901), c: a0 &+ 902)
}

// sThenInts_Quad: p0 exactly four register units
// result = 1019 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1 + 17*p2 + 19*p3
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64)
@inline(never) public func sThenInts_Quad(_ p0: Quad, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1019
    h = h &+ p0.a &* 3
    h = h &+ p0.b &* 5
    h = h &+ p0.c &* 7
    h = h &+ p0.d &* 11
    h = h &+ p1 &* 13
    h = h &+ p2 &* 17
    h = h &+ p3 &* 19
    return h
}

// intsThenS_Quad: p2 exactly four register units
// result = 1021 + 3*p0 + 5*p1 + 7*p2.a + 11*p2.b + 13*p2.c + 17*p2.d
// lowered: i64 (i64, i64, i64, i64, i64, i64)
@inline(never) public func intsThenS_Quad(_ p0: Int, _ p1: Int, _ p2: Quad) -> Int {
    var h = 1021
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2.a &* 7
    h = h &+ p2.b &* 11
    h = h &+ p2.c &* 13
    h = h &+ p2.d &* 17
    return h
}

// make_Quad: returns Quad (exactly four register units); each field is one argument plus its own constant, narrowed to the field
// a = a0+1200, b = a1+1201, c = a2+1202, d = a0+1203
// lowered: { i64, i64, i64, i64 } (i64, i64, i64)
@inline(never) public func make_Quad(_ a0: Int, _ a1: Int, _ a2: Int) -> Quad {
    return Quad(a: a0 &+ 1200, b: a1 &+ 1201, c: a2 &+ 1202, d: a0 &+ 1203)
}

// sThenInts_Five: p0 five units: by address
// result = 1025 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p0.e + 17*p1 + 19*p2
// lowered: i64 (ptr, i64, i64)
@inline(never) public func sThenInts_Five(_ p0: Five, _ p1: Int, _ p2: Int) -> Int {
    var h = 1025
    h = h &+ p0.a &* 3
    h = h &+ p0.b &* 5
    h = h &+ p0.c &* 7
    h = h &+ p0.d &* 11
    h = h &+ p0.e &* 13
    h = h &+ p1 &* 17
    h = h &+ p2 &* 19
    return h
}

// intsThenS_Five: p3 five units: by address
// result = 1027 + 3*p0 + 5*p1 + 7*p2 + 11*p3.a + 13*p3.b + 17*p3.c + 19*p3.d + 23*p3.e
// lowered: i64 (i64, i64, i64, ptr)
@inline(never) public func intsThenS_Five(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Five) -> Int {
    var h = 1027
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3.a &* 11
    h = h &+ p3.b &* 13
    h = h &+ p3.c &* 17
    h = h &+ p3.d &* 19
    h = h &+ p3.e &* 23
    return h
}

// make_Five: returns Five (five units: by address); each field is one argument plus its own constant, narrowed to the field
// a = a0+1500, b = a1+1501, c = a0+1502, d = a1+1503, e = a0+1504
// lowered: void (ptr sret(%T14StructLowering4FiveV), i64, i64)
@inline(never) public func make_Five(_ a0: Int, _ a1: Int) -> Five {
    return Five(a: a0 &+ 1500, b: a1 &+ 1501, c: a0 &+ 1502, d: a1 &+ 1503, e: a0 &+ 1504)
}

// sThenInts_Six: p0 six units: by address
// result = 1031 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p0.e + 17*p0.f + 19*p1 + 23*p2 + 29*p3
// lowered: i64 (ptr, i64, i64, i64)
@inline(never) public func sThenInts_Six(_ p0: Six, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1031
    h = h &+ p0.a &* 3
    h = h &+ Int(p0.b) &* 5
    h = h &+ p0.c &* 7
    h = h &+ Int(p0.d) &* 11
    h = h &+ p0.e &* 13
    h = h &+ Int(p0.f) &* 17
    h = h &+ p1 &* 19
    h = h &+ p2 &* 23
    h = h &+ p3 &* 29
    return h
}

// intsThenS_Six: p2 six units: by address
// result = 1033 + 3*p0 + 5*p1 + 7*p2.a + 11*p2.b + 13*p2.c + 17*p2.d + 19*p2.e + 23*p2.f
// lowered: i64 (i64, i64, ptr)
@inline(never) public func intsThenS_Six(_ p0: Int, _ p1: Int, _ p2: Six) -> Int {
    var h = 1033
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2.a &* 7
    h = h &+ Int(p2.b) &* 11
    h = h &+ p2.c &* 13
    h = h &+ Int(p2.d) &* 17
    h = h &+ p2.e &* 19
    h = h &+ Int(p2.f) &* 23
    return h
}

// make_Six: returns Six (six units: by address); each field is one argument plus its own constant, narrowed to the field
// a = a0+1800, b = a1+1801, c = a2+1802, d = a0+1803, e = a1+1804, f = a2+1805
// lowered: void (ptr sret(%T14StructLowering3SixV), i64, i64, i64)
@inline(never) public func make_Six(_ a0: Int, _ a1: Int, _ a2: Int) -> Six {
    return Six(a: a0 &+ 1800, b: Int32(truncatingIfNeeded: a1 &+ 1801), c: a2 &+ 1802, d: Int16(truncatingIfNeeded: a0 &+ 1803), e: a1 &+ 1804, f: Int8(truncatingIfNeeded: a2 &+ 1805))
}

// sThenInts_Packed: p0 i8@0 i16@2 i32@4 packed into one 8-byte unit
// result = 1037 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p1 + 13*p2
// lowered: i64 (i64, i64, i64)
@inline(never) public func sThenInts_Packed(_ p0: Packed, _ p1: Int, _ p2: Int) -> Int {
    var h = 1037
    h = h &+ Int(p0.a) &* 3
    h = h &+ Int(p0.b) &* 5
    h = h &+ Int(p0.c) &* 7
    h = h &+ p1 &* 11
    h = h &+ p2 &* 13
    return h
}

// intsThenS_Packed: p3 i8@0 i16@2 i32@4 packed into one 8-byte unit
// result = 1039 + 3*p0 + 5*p1 + 7*p2 + 11*p3.a + 13*p3.b + 17*p3.c
// lowered: i64 (i64, i64, i64, i64)
@inline(never) public func intsThenS_Packed(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Packed) -> Int {
    var h = 1039
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ Int(p3.a) &* 11
    h = h &+ Int(p3.b) &* 13
    h = h &+ Int(p3.c) &* 17
    return h
}

// make_Packed: returns Packed (i8@0 i16@2 i32@4 packed into one 8-byte unit); each field is one argument plus its own constant, narrowed to the field
// a = a0+2100, b = a1+2101, c = a0+2102
// lowered: i64 (i64, i64)
@inline(never) public func make_Packed(_ a0: Int, _ a1: Int) -> Packed {
    return Packed(a: Int8(truncatingIfNeeded: a0 &+ 2100), b: Int16(truncatingIfNeeded: a1 &+ 2101), c: Int32(truncatingIfNeeded: a0 &+ 2102))
}

// sThenInts_PackedU: p0 bool@0 u8@1 u16@2 u32@4 packed into one unit
// result = 1043 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1 + 17*p2 + 19*p3
// lowered: i64 (i64, i64, i64, i64)
@inline(never) public func sThenInts_PackedU(_ p0: PackedU, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1043
    h = h &+ (p0.a ? 1 : 0) &* 3
    h = h &+ Int(p0.b) &* 5
    h = h &+ Int(p0.c) &* 7
    h = h &+ Int(p0.d) &* 11
    h = h &+ p1 &* 13
    h = h &+ p2 &* 17
    h = h &+ p3 &* 19
    return h
}

// intsThenS_PackedU: p2 bool@0 u8@1 u16@2 u32@4 packed into one unit
// result = 1045 + 3*p0 + 5*p1 + 7*p2.a + 11*p2.b + 13*p2.c + 17*p2.d
// lowered: i64 (i64, i64, i64)
@inline(never) public func intsThenS_PackedU(_ p0: Int, _ p1: Int, _ p2: PackedU) -> Int {
    var h = 1045
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ (p2.a ? 1 : 0) &* 7
    h = h &+ Int(p2.b) &* 11
    h = h &+ Int(p2.c) &* 13
    h = h &+ Int(p2.d) &* 17
    return h
}

// make_PackedU: returns PackedU (bool@0 u8@1 u16@2 u32@4 packed into one unit); each field is one argument plus its own constant, narrowed to the field
// a = a0+2400, b = a1+2401, c = a2+2402, d = a0+2403
// lowered: i64 (i64, i64, i64)
@inline(never) public func make_PackedU(_ a0: Int, _ a1: Int, _ a2: Int) -> PackedU {
    return PackedU(a: ((a0 &+ 2400) & 1) != 0, b: UInt8(truncatingIfNeeded: a1 &+ 2401), c: UInt16(truncatingIfNeeded: a2 &+ 2402), d: UInt32(truncatingIfNeeded: a0 &+ 2403))
}

// sThenInts_Straddle: p0 i8, padding to 8, i64, i8: three units
// result = 1049 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p1 + 13*p2
// lowered: i64 (i8, i64, i8, i64, i64)
@inline(never) public func sThenInts_Straddle(_ p0: Straddle, _ p1: Int, _ p2: Int) -> Int {
    var h = 1049
    h = h &+ Int(p0.a) &* 3
    h = h &+ p0.b &* 5
    h = h &+ Int(p0.c) &* 7
    h = h &+ p1 &* 11
    h = h &+ p2 &* 13
    return h
}

// intsThenS_Straddle: p3 i8, padding to 8, i64, i8: three units
// result = 1051 + 3*p0 + 5*p1 + 7*p2 + 11*p3.a + 13*p3.b + 17*p3.c
// lowered: i64 (i64, i64, i64, i8, i64, i8)
@inline(never) public func intsThenS_Straddle(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Straddle) -> Int {
    var h = 1051
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ Int(p3.a) &* 11
    h = h &+ p3.b &* 13
    h = h &+ Int(p3.c) &* 17
    return h
}

// make_Straddle: returns Straddle (i8, padding to 8, i64, i8: three units); each field is one argument plus its own constant, narrowed to the field
// a = a0+2700, b = a1+2701, c = a0+2702
// lowered: { i8, i64, i8 } (i64, i64)
@inline(never) public func make_Straddle(_ a0: Int, _ a1: Int) -> Straddle {
    return Straddle(a: Int8(truncatingIfNeeded: a0 &+ 2700), b: a1 &+ 2701, c: Int8(truncatingIfNeeded: a0 &+ 2702))
}

// sThenInts_UMix: p0 u8@0 u16@2 u32@4 in one unit, then u64
// result = 1055 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1 + 17*p2 + 19*p3
// lowered: i64 (i64, i64, i64, i64, i64)
@inline(never) public func sThenInts_UMix(_ p0: UMix, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1055
    h = h &+ Int(p0.a) &* 3
    h = h &+ Int(p0.b) &* 5
    h = h &+ Int(p0.c) &* 7
    h = h &+ Int(bitPattern: p0.d) &* 11
    h = h &+ p1 &* 13
    h = h &+ p2 &* 17
    h = h &+ p3 &* 19
    return h
}

// intsThenS_UMix: p2 u8@0 u16@2 u32@4 in one unit, then u64
// result = 1057 + 3*p0 + 5*p1 + 7*p2.a + 11*p2.b + 13*p2.c + 17*p2.d
// lowered: i64 (i64, i64, i64, i64)
@inline(never) public func intsThenS_UMix(_ p0: Int, _ p1: Int, _ p2: UMix) -> Int {
    var h = 1057
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ Int(p2.a) &* 7
    h = h &+ Int(p2.b) &* 11
    h = h &+ Int(p2.c) &* 13
    h = h &+ Int(bitPattern: p2.d) &* 17
    return h
}

// make_UMix: returns UMix (u8@0 u16@2 u32@4 in one unit, then u64); each field is one argument plus its own constant, narrowed to the field
// a = a0+3000, b = a1+3001, c = a2+3002, d = a0+3003
// lowered: { i64, i64 } (i64, i64, i64)
@inline(never) public func make_UMix(_ a0: Int, _ a1: Int, _ a2: Int) -> UMix {
    return UMix(a: UInt8(truncatingIfNeeded: a0 &+ 3000), b: UInt16(truncatingIfNeeded: a1 &+ 3001), c: UInt32(truncatingIfNeeded: a2 &+ 3002), d: UInt(bitPattern: a0 &+ 3003))
}

// sThenInts_IntDouble: p0 integer then double: x and d
// result = 1061 + 3*p0.a + 5*p0.b + 7*p1 + 11*p2
// lowered: i64 (i64, double, i64, i64)
@inline(never) public func sThenInts_IntDouble(_ p0: IntDouble, _ p1: Int, _ p2: Int) -> Int {
    var h = 1061
    h = h &+ p0.a &* 3
    h = h &+ Int(bitPattern: UInt(p0.b.bitPattern)) &* 5
    h = h &+ p1 &* 7
    h = h &+ p2 &* 11
    return h
}

// intsThenS_IntDouble: p3 integer then double: x and d
// result = 1063 + 3*p0 + 5*p1 + 7*p2 + 11*p3.a + 13*p3.b
// lowered: i64 (i64, i64, i64, i64, double)
@inline(never) public func intsThenS_IntDouble(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: IntDouble) -> Int {
    var h = 1063
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3.a &* 11
    h = h &+ Int(bitPattern: UInt(p3.b.bitPattern)) &* 13
    return h
}

// make_IntDouble: returns IntDouble (integer then double: x and d); each field is one argument plus its own constant, narrowed to the field
// a = a0+3300, b = a1+3301
// lowered: { i64, double } (i64, i64)
@inline(never) public func make_IntDouble(_ a0: Int, _ a1: Int) -> IntDouble {
    return IntDouble(a: a0 &+ 3300, b: Double(bitPattern: UInt64(bitPattern: Int64(a1 &+ 3301))))
}

// sThenInts_DoubleInt: p0 double then integer: d and x
// result = 1067 + 3*p0.a + 5*p0.b + 7*p1 + 11*p2 + 13*p3
// lowered: i64 (double, i64, i64, i64, i64)
@inline(never) public func sThenInts_DoubleInt(_ p0: DoubleInt, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1067
    h = h &+ Int(bitPattern: UInt(p0.a.bitPattern)) &* 3
    h = h &+ p0.b &* 5
    h = h &+ p1 &* 7
    h = h &+ p2 &* 11
    h = h &+ p3 &* 13
    return h
}

// intsThenS_DoubleInt: p2 double then integer: d and x
// result = 1069 + 3*p0 + 5*p1 + 7*p2.a + 11*p2.b
// lowered: i64 (i64, i64, double, i64)
@inline(never) public func intsThenS_DoubleInt(_ p0: Int, _ p1: Int, _ p2: DoubleInt) -> Int {
    var h = 1069
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ Int(bitPattern: UInt(p2.a.bitPattern)) &* 7
    h = h &+ p2.b &* 11
    return h
}

// make_DoubleInt: returns DoubleInt (double then integer: d and x); each field is one argument plus its own constant, narrowed to the field
// a = a0+3600, b = a1+3601
// lowered: { double, i64 } (i64, i64)
@inline(never) public func make_DoubleInt(_ a0: Int, _ a1: Int) -> DoubleInt {
    return DoubleInt(a: Double(bitPattern: UInt64(bitPattern: Int64(a0 &+ 3600))), b: a1 &+ 3601)
}

// sThenInts_FloatMid: p0 i32@0, float@4, i32@8: the float sits in the first unit beside an integer
// result = 1073 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p1 + 13*p2
// lowered: i64 (i32, float, i32, i64, i64)
@inline(never) public func sThenInts_FloatMid(_ p0: FloatMid, _ p1: Int, _ p2: Int) -> Int {
    var h = 1073
    h = h &+ Int(p0.a) &* 3
    h = h &+ Int(p0.b.bitPattern) &* 5
    h = h &+ Int(p0.c) &* 7
    h = h &+ p1 &* 11
    h = h &+ p2 &* 13
    return h
}

// intsThenS_FloatMid: p3 i32@0, float@4, i32@8: the float sits in the first unit beside an integer
// result = 1075 + 3*p0 + 5*p1 + 7*p2 + 11*p3.a + 13*p3.b + 17*p3.c
// lowered: i64 (i64, i64, i64, i32, float, i32)
@inline(never) public func intsThenS_FloatMid(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: FloatMid) -> Int {
    var h = 1075
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ Int(p3.a) &* 11
    h = h &+ Int(p3.b.bitPattern) &* 13
    h = h &+ Int(p3.c) &* 17
    return h
}

// make_FloatMid: returns FloatMid (i32@0, float@4, i32@8: the float sits in the first unit beside an integer); each field is one argument plus its own constant, narrowed to the field
// a = a0+3900, b = a1+3901, c = a0+3902
// lowered: { i32, float, i32 } (i64, i64)
@inline(never) public func make_FloatMid(_ a0: Int, _ a1: Int) -> FloatMid {
    return FloatMid(a: Int32(truncatingIfNeeded: a0 &+ 3900), b: Float(bitPattern: UInt32(truncatingIfNeeded: a1 &+ 3901)), c: Int32(truncatingIfNeeded: a0 &+ 3902))
}

// sThenInts_HalfMid: p0 i16, Float16, i16, i16 in ONE 8-byte unit: the half splits the integers
// result = 1079 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1 + 17*p2 + 19*p3
// lowered: i64 (i16, half, i32, i64, i64, i64)
@inline(never) public func sThenInts_HalfMid(_ p0: HalfMid, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1079
    h = h &+ Int(p0.a) &* 3
    h = h &+ Int(p0.b.bitPattern) &* 5
    h = h &+ Int(p0.c) &* 7
    h = h &+ Int(p0.d) &* 11
    h = h &+ p1 &* 13
    h = h &+ p2 &* 17
    h = h &+ p3 &* 19
    return h
}

// intsThenS_HalfMid: p2 i16, Float16, i16, i16 in ONE 8-byte unit: the half splits the integers
// result = 1081 + 3*p0 + 5*p1 + 7*p2.a + 11*p2.b + 13*p2.c + 17*p2.d
// lowered: i64 (i64, i64, i16, half, i32)
@inline(never) public func intsThenS_HalfMid(_ p0: Int, _ p1: Int, _ p2: HalfMid) -> Int {
    var h = 1081
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ Int(p2.a) &* 7
    h = h &+ Int(p2.b.bitPattern) &* 11
    h = h &+ Int(p2.c) &* 13
    h = h &+ Int(p2.d) &* 17
    return h
}

// make_HalfMid: returns HalfMid (i16, Float16, i16, i16 in ONE 8-byte unit: the half splits the integers); each field is one argument plus its own constant, narrowed to the field
// a = a0+4200, b = a1+4201, c = a2+4202, d = a0+4203
// lowered: { i16, half, i32 } (i64, i64, i64)
@inline(never) public func make_HalfMid(_ a0: Int, _ a1: Int, _ a2: Int) -> HalfMid {
    return HalfMid(a: Int16(truncatingIfNeeded: a0 &+ 4200), b: Float16(bitPattern: UInt16(truncatingIfNeeded: a1 &+ 4201)), c: Int16(truncatingIfNeeded: a2 &+ 4202), d: Int16(truncatingIfNeeded: a0 &+ 4203))
}

// sThenInts_MixFour: p0 i32, float, double, i64: four scalars over two banks
// result = 1085 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1 + 17*p2
// lowered: i64 (i32, float, double, i64, i64, i64)
@inline(never) public func sThenInts_MixFour(_ p0: MixFour, _ p1: Int, _ p2: Int) -> Int {
    var h = 1085
    h = h &+ Int(p0.a) &* 3
    h = h &+ Int(p0.b.bitPattern) &* 5
    h = h &+ Int(bitPattern: UInt(p0.c.bitPattern)) &* 7
    h = h &+ p0.d &* 11
    h = h &+ p1 &* 13
    h = h &+ p2 &* 17
    return h
}

// intsThenS_MixFour: p3 i32, float, double, i64: four scalars over two banks
// result = 1087 + 3*p0 + 5*p1 + 7*p2 + 11*p3.a + 13*p3.b + 17*p3.c + 19*p3.d
// lowered: i64 (i64, i64, i64, i32, float, double, i64)
@inline(never) public func intsThenS_MixFour(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: MixFour) -> Int {
    var h = 1087
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ Int(p3.a) &* 11
    h = h &+ Int(p3.b.bitPattern) &* 13
    h = h &+ Int(bitPattern: UInt(p3.c.bitPattern)) &* 17
    h = h &+ p3.d &* 19
    return h
}

// make_MixFour: returns MixFour (i32, float, double, i64: four scalars over two banks); each field is one argument plus its own constant, narrowed to the field
// a = a0+4500, b = a1+4501, c = a0+4502, d = a1+4503
// lowered: { i32, float, double, i64 } (i64, i64)
@inline(never) public func make_MixFour(_ a0: Int, _ a1: Int) -> MixFour {
    return MixFour(a: Int32(truncatingIfNeeded: a0 &+ 4500), b: Float(bitPattern: UInt32(truncatingIfNeeded: a1 &+ 4501)), c: Double(bitPattern: UInt64(bitPattern: Int64(a0 &+ 4502))), d: a1 &+ 4503)
}

// sThenInts_FourD: p0 four doubles: d0..d3
// result = 1091 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1 + 17*p2 + 19*p3
// lowered: i64 (double, double, double, double, i64, i64, i64)
@inline(never) public func sThenInts_FourD(_ p0: FourD, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1091
    h = h &+ Int(bitPattern: UInt(p0.a.bitPattern)) &* 3
    h = h &+ Int(bitPattern: UInt(p0.b.bitPattern)) &* 5
    h = h &+ Int(bitPattern: UInt(p0.c.bitPattern)) &* 7
    h = h &+ Int(bitPattern: UInt(p0.d.bitPattern)) &* 11
    h = h &+ p1 &* 13
    h = h &+ p2 &* 17
    h = h &+ p3 &* 19
    return h
}

// intsThenS_FourD: p2 four doubles: d0..d3
// result = 1093 + 3*p0 + 5*p1 + 7*p2.a + 11*p2.b + 13*p2.c + 17*p2.d
// lowered: i64 (i64, i64, double, double, double, double)
@inline(never) public func intsThenS_FourD(_ p0: Int, _ p1: Int, _ p2: FourD) -> Int {
    var h = 1093
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ Int(bitPattern: UInt(p2.a.bitPattern)) &* 7
    h = h &+ Int(bitPattern: UInt(p2.b.bitPattern)) &* 11
    h = h &+ Int(bitPattern: UInt(p2.c.bitPattern)) &* 13
    h = h &+ Int(bitPattern: UInt(p2.d.bitPattern)) &* 17
    return h
}

// make_FourD: returns FourD (four doubles: d0..d3); each field is one argument plus its own constant, narrowed to the field
// a = a0+4800, b = a1+4801, c = a2+4802, d = a0+4803
// lowered: { double, double, double, double } (i64, i64, i64)
@inline(never) public func make_FourD(_ a0: Int, _ a1: Int, _ a2: Int) -> FourD {
    return FourD(a: Double(bitPattern: UInt64(bitPattern: Int64(a0 &+ 4800))), b: Double(bitPattern: UInt64(bitPattern: Int64(a1 &+ 4801))), c: Double(bitPattern: UInt64(bitPattern: Int64(a2 &+ 4802))), d: Double(bitPattern: UInt64(bitPattern: Int64(a0 &+ 4803))))
}

// sThenInts_TwoF: p0 two floats in one 8-byte unit: s0, s1
// result = 1097 + 3*p0.a + 5*p0.b + 7*p1 + 11*p2
// lowered: i64 (float, float, i64, i64)
@inline(never) public func sThenInts_TwoF(_ p0: TwoF, _ p1: Int, _ p2: Int) -> Int {
    var h = 1097
    h = h &+ Int(p0.a.bitPattern) &* 3
    h = h &+ Int(p0.b.bitPattern) &* 5
    h = h &+ p1 &* 7
    h = h &+ p2 &* 11
    return h
}

// intsThenS_TwoF: p3 two floats in one 8-byte unit: s0, s1
// result = 1099 + 3*p0 + 5*p1 + 7*p2 + 11*p3.a + 13*p3.b
// lowered: i64 (i64, i64, i64, float, float)
@inline(never) public func intsThenS_TwoF(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: TwoF) -> Int {
    var h = 1099
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ Int(p3.a.bitPattern) &* 11
    h = h &+ Int(p3.b.bitPattern) &* 13
    return h
}

// make_TwoF: returns TwoF (two floats in one 8-byte unit: s0, s1); each field is one argument plus its own constant, narrowed to the field
// a = a0+5100, b = a1+5101
// lowered: { float, float } (i64, i64)
@inline(never) public func make_TwoF(_ a0: Int, _ a1: Int) -> TwoF {
    return TwoF(a: Float(bitPattern: UInt32(truncatingIfNeeded: a0 &+ 5100)), b: Float(bitPattern: UInt32(truncatingIfNeeded: a1 &+ 5101)))
}

// sThenInts_FiveF: p0 five floats: by address
// result = 1103 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p0.e + 17*p1 + 19*p2 + 23*p3
// lowered: i64 (ptr, i64, i64, i64)
@inline(never) public func sThenInts_FiveF(_ p0: FiveF, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1103
    h = h &+ Int(p0.a.bitPattern) &* 3
    h = h &+ Int(p0.b.bitPattern) &* 5
    h = h &+ Int(p0.c.bitPattern) &* 7
    h = h &+ Int(p0.d.bitPattern) &* 11
    h = h &+ Int(p0.e.bitPattern) &* 13
    h = h &+ p1 &* 17
    h = h &+ p2 &* 19
    h = h &+ p3 &* 23
    return h
}

// intsThenS_FiveF: p2 five floats: by address
// result = 1105 + 3*p0 + 5*p1 + 7*p2.a + 11*p2.b + 13*p2.c + 17*p2.d + 19*p2.e
// lowered: i64 (i64, i64, ptr)
@inline(never) public func intsThenS_FiveF(_ p0: Int, _ p1: Int, _ p2: FiveF) -> Int {
    var h = 1105
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ Int(p2.a.bitPattern) &* 7
    h = h &+ Int(p2.b.bitPattern) &* 11
    h = h &+ Int(p2.c.bitPattern) &* 13
    h = h &+ Int(p2.d.bitPattern) &* 17
    h = h &+ Int(p2.e.bitPattern) &* 19
    return h
}

// make_FiveF: returns FiveF (five floats: by address); each field is one argument plus its own constant, narrowed to the field
// a = a0+5400, b = a1+5401, c = a2+5402, d = a0+5403, e = a1+5404
// lowered: void (ptr sret(%T14StructLowering5FiveFV), i64, i64, i64)
@inline(never) public func make_FiveF(_ a0: Int, _ a1: Int, _ a2: Int) -> FiveF {
    return FiveF(a: Float(bitPattern: UInt32(truncatingIfNeeded: a0 &+ 5400)), b: Float(bitPattern: UInt32(truncatingIfNeeded: a1 &+ 5401)), c: Float(bitPattern: UInt32(truncatingIfNeeded: a2 &+ 5402)), d: Float(bitPattern: UInt32(truncatingIfNeeded: a0 &+ 5403)), e: Float(bitPattern: UInt32(truncatingIfNeeded: a1 &+ 5404)))
}

// sThenInts_PtrRef: p0 raw pointer, class reference, Bool
// result = 1109 + 3*p0.p + 5*p0.r + 7*p0.f + 11*p1 + 13*p2
// lowered: i64 (i64, ptr, i1, i64, i64)
@inline(never) public func sThenInts_PtrRef(_ p0: PtrRef, _ p1: Int, _ p2: Int) -> Int {
    var h = 1109
    h = h &+ Int(bitPattern: p0.p) &* 3
    h = h &+ p0.r.v &* 5
    h = h &+ (p0.f ? 1 : 0) &* 7
    h = h &+ p1 &* 11
    h = h &+ p2 &* 13
    return h
}

// intsThenS_PtrRef: p3 raw pointer, class reference, Bool
// result = 1111 + 3*p0 + 5*p1 + 7*p2 + 11*p3.p + 13*p3.r + 17*p3.f
// lowered: i64 (i64, i64, i64, i64, ptr, i1)
@inline(never) public func intsThenS_PtrRef(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: PtrRef) -> Int {
    var h = 1111
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ Int(bitPattern: p3.p) &* 11
    h = h &+ p3.r.v &* 13
    h = h &+ (p3.f ? 1 : 0) &* 17
    return h
}

// make_PtrRef: returns PtrRef (raw pointer, class reference, Bool); each field is one argument plus its own constant, narrowed to the field
// p = a0+5700, r = a1+5701, f = a0+5702
// lowered: { i64, ptr, i1 } (i64, i64)
@inline(never) public func make_PtrRef(_ a0: Int, _ a1: Int) -> PtrRef {
    return PtrRef(p: UnsafeRawPointer(bitPattern: a0 &+ 5700), r: Box(a1 &+ 5701), f: ((a0 &+ 5702) & 1) != 0)
}

// sThenInts_Opts: p0 Int32? (payload + tag in one unit) then Int? (i64 + tag byte)
// result = 1115 + 3*p0.a + 5*p0.b + 7*p1 + 11*p2 + 13*p3
// lowered: i64 (i64, i64, i8, i64, i64, i64)
@inline(never) public func sThenInts_Opts(_ p0: Opts, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1115
    if let t = p0.a { h = h &+ Int(t) &* 3 } else { h = h &+ 322 }
    if let t = p0.b { h = h &+ t &* 5 } else { h = h &+ 536 }
    h = h &+ p1 &* 7
    h = h &+ p2 &* 11
    h = h &+ p3 &* 13
    return h
}

// intsThenS_Opts: p2 Int32? (payload + tag in one unit) then Int? (i64 + tag byte)
// result = 1117 + 3*p0 + 5*p1 + 7*p2.a + 11*p2.b
// lowered: i64 (i64, i64, i64, i64, i8)
@inline(never) public func intsThenS_Opts(_ p0: Int, _ p1: Int, _ p2: Opts) -> Int {
    var h = 1117
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    if let t = p2.a { h = h &+ Int(t) &* 7 } else { h = h &+ 750 }
    if let t = p2.b { h = h &+ t &* 11 } else { h = h &+ 1178 }
    return h
}

// make_Opts: returns Opts (Int32? (payload + tag in one unit) then Int? (i64 + tag byte)); each field is one argument plus its own constant, narrowed to the field
// a = a0+6000, b = a1+6001
// lowered: { i64, i64, i8 } (i64, i64)
@inline(never) public func make_Opts(_ a0: Int, _ a1: Int) -> Opts {
    return Opts(a: (((a0 &+ 6000) & 1) == 0 ? nil : Int32(truncatingIfNeeded: (a0 &+ 6000) >> 1)), b: (((a1 &+ 6001) & 1) == 0 ? nil : ((a1 &+ 6001) >> 1)))
}

// sThenInts_OptD: p0 Double? (payload as integer bits + tag) then Int8
// result = 1121 + 3*p0.a + 5*p0.b + 7*p1 + 11*p2
// lowered: i64 (i64, i16, i64, i64)
@inline(never) public func sThenInts_OptD(_ p0: OptD, _ p1: Int, _ p2: Int) -> Int {
    var h = 1121
    if let t = p0.a { h = h &+ Int(bitPattern: UInt(t.bitPattern)) &* 3 } else { h = h &+ 322 }
    h = h &+ Int(p0.b) &* 5
    h = h &+ p1 &* 7
    h = h &+ p2 &* 11
    return h
}

// intsThenS_OptD: p3 Double? (payload as integer bits + tag) then Int8
// result = 1123 + 3*p0 + 5*p1 + 7*p2 + 11*p3.a + 13*p3.b
// lowered: i64 (i64, i64, i64, i64, i16)
@inline(never) public func intsThenS_OptD(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: OptD) -> Int {
    var h = 1123
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    if let t = p3.a { h = h &+ Int(bitPattern: UInt(t.bitPattern)) &* 11 } else { h = h &+ 1178 }
    h = h &+ Int(p3.b) &* 13
    return h
}

// make_OptD: returns OptD (Double? (payload as integer bits + tag) then Int8); each field is one argument plus its own constant, narrowed to the field
// a = a0+6300, b = a1+6301
// lowered: { i64, i16 } (i64, i64)
@inline(never) public func make_OptD(_ a0: Int, _ a1: Int) -> OptD {
    return OptD(a: (((a0 &+ 6300) & 1) == 0 ? nil : Double(bitPattern: UInt64(bitPattern: Int64((a0 &+ 6300) >> 1)))), b: Int8(truncatingIfNeeded: a1 &+ 6301))
}

// sThenInts_Empty: p0 no stored fields: takes no register
// result = 1127 + 3*p1 + 5*p2 + 7*p3
// lowered: i64 (i64, i64, i64)
@inline(never) public func sThenInts_Empty(_ p0: Empty, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1127
    h = h &+ p1 &* 3
    h = h &+ p2 &* 5
    h = h &+ p3 &* 7
    return h
}

// intsThenS_Empty: p2 no stored fields: takes no register
// result = 1129 + 3*p0 + 5*p1
// lowered: i64 (i64, i64)
@inline(never) public func intsThenS_Empty(_ p0: Int, _ p1: Int, _ p2: Empty) -> Int {
    var h = 1129
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    return h
}

// sThenInts_Nested: p0 Pair, Int32, Packed nested: i64, i64, i32, then a packed unit
// result = 1131 + 3*p0.p.a + 5*p0.p.b + 7*p0.k + 11*p0.q.a + 13*p0.q.b + 17*p0.q.c + 19*p1 + 23*p2
// lowered: i64 (i64, i64, i64, i32, i64, i64)
@inline(never) public func sThenInts_Nested(_ p0: Nested, _ p1: Int, _ p2: Int) -> Int {
    var h = 1131
    h = h &+ p0.p.a &* 3
    h = h &+ p0.p.b &* 5
    h = h &+ Int(p0.k) &* 7
    h = h &+ Int(p0.q.a) &* 11
    h = h &+ Int(p0.q.b) &* 13
    h = h &+ Int(p0.q.c) &* 17
    h = h &+ p1 &* 19
    h = h &+ p2 &* 23
    return h
}

// intsThenS_Nested: p3 Pair, Int32, Packed nested: i64, i64, i32, then a packed unit
// result = 1133 + 3*p0 + 5*p1 + 7*p2 + 11*p3.p.a + 13*p3.p.b + 17*p3.k + 19*p3.q.a + 23*p3.q.b + 29*p3.q.c
// lowered: i64 (i64, i64, i64, i64, i64, i64, i32)
@inline(never) public func intsThenS_Nested(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Nested) -> Int {
    var h = 1133
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3.p.a &* 11
    h = h &+ p3.p.b &* 13
    h = h &+ Int(p3.k) &* 17
    h = h &+ Int(p3.q.a) &* 19
    h = h &+ Int(p3.q.b) &* 23
    h = h &+ Int(p3.q.c) &* 29
    return h
}

// make_Nested: returns Nested (Pair, Int32, Packed nested: i64, i64, i32, then a packed unit); each field is one argument plus its own constant, narrowed to the field
// p.a = a0+6800, p.b = a1+6801, k = a0+6802, q.a = a1+6803, q.b = a0+6804, q.c = a1+6805
// lowered: { i64, i64, i64, i32 } (i64, i64)
@inline(never) public func make_Nested(_ a0: Int, _ a1: Int) -> Nested {
    return Nested(p: Pair(a: a0 &+ 6800, b: a1 &+ 6801), k: Int32(truncatingIfNeeded: a0 &+ 6802), q: Packed(a: Int8(truncatingIfNeeded: a1 &+ 6803), b: Int16(truncatingIfNeeded: a0 &+ 6804), c: Int32(truncatingIfNeeded: a1 &+ 6805)))
}

// sThenInts_WithTuple: p0 a tuple (Int16, Int) then UInt8
// result = 1137 + 3*p0.t.0 + 5*p0.t.1 + 7*p0.u + 11*p1 + 13*p2 + 17*p3
// lowered: i64 (i16, i64, i8, i64, i64, i64)
@inline(never) public func sThenInts_WithTuple(_ p0: WithTuple, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1137
    h = h &+ Int(p0.t.0) &* 3
    h = h &+ p0.t.1 &* 5
    h = h &+ Int(p0.u) &* 7
    h = h &+ p1 &* 11
    h = h &+ p2 &* 13
    h = h &+ p3 &* 17
    return h
}

// intsThenS_WithTuple: p2 a tuple (Int16, Int) then UInt8
// result = 1139 + 3*p0 + 5*p1 + 7*p2.t.0 + 11*p2.t.1 + 13*p2.u
// lowered: i64 (i64, i64, i16, i64, i8)
@inline(never) public func intsThenS_WithTuple(_ p0: Int, _ p1: Int, _ p2: WithTuple) -> Int {
    var h = 1139
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ Int(p2.t.0) &* 7
    h = h &+ p2.t.1 &* 11
    h = h &+ Int(p2.u) &* 13
    return h
}

// make_WithTuple: returns WithTuple (a tuple (Int16, Int) then UInt8); each field is one argument plus its own constant, narrowed to the field
// t.0 = a0+7100, t.1 = a1+7101, u = a2+7102
// lowered: { i16, i64, i8 } (i64, i64, i64)
@inline(never) public func make_WithTuple(_ a0: Int, _ a1: Int, _ a2: Int) -> WithTuple {
    return WithTuple(t: (Int16(truncatingIfNeeded: a0 &+ 7100), a1 &+ 7101), u: UInt8(truncatingIfNeeded: a2 &+ 7102))
}

// sThenInts_Hollow: p0 empty fields around an Int and an Int32
// result = 1143 + 3*p0.a + 5*p0.b + 7*p1 + 11*p2
// lowered: i64 (i64, i32, i64, i64)
@inline(never) public func sThenInts_Hollow(_ p0: Hollow, _ p1: Int, _ p2: Int) -> Int {
    var h = 1143
    h = h &+ p0.a &* 3
    h = h &+ Int(p0.b) &* 5
    h = h &+ p1 &* 7
    h = h &+ p2 &* 11
    return h
}

// intsThenS_Hollow: p3 empty fields around an Int and an Int32
// result = 1145 + 3*p0 + 5*p1 + 7*p2 + 11*p3.a + 13*p3.b
// lowered: i64 (i64, i64, i64, i64, i32)
@inline(never) public func intsThenS_Hollow(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Hollow) -> Int {
    var h = 1145
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3.a &* 11
    h = h &+ Int(p3.b) &* 13
    return h
}

// make_Hollow: returns Hollow (empty fields around an Int and an Int32); each field is one argument plus its own constant, narrowed to the field
// a = a0+7400, b = a1+7401
// lowered: { i64, i32 } (i64, i64)
@inline(never) public func make_Hollow(_ a0: Int, _ a1: Int) -> Hollow {
    return Hollow(e: Empty(), a: a0 &+ 7400, f: Empty(), b: Int32(truncatingIfNeeded: a1 &+ 7401))
}

// sThenInts_Tup3: p0 a bare tuple parameter (Int8, Int, Int8)
// result = 1149 + 3*p0.0 + 5*p0.1 + 7*p0.2 + 11*p1 + 13*p2 + 17*p3
// lowered: i64 (i8, i64, i8, i64, i64, i64)
@inline(never) public func sThenInts_Tup3(_ p0: (Int8, Int, Int8), _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
    var h = 1149
    h = h &+ Int(p0.0) &* 3
    h = h &+ p0.1 &* 5
    h = h &+ Int(p0.2) &* 7
    h = h &+ p1 &* 11
    h = h &+ p2 &* 13
    h = h &+ p3 &* 17
    return h
}

// intsThenS_Tup3: p2 a bare tuple parameter (Int8, Int, Int8)
// result = 1151 + 3*p0 + 5*p1 + 7*p2.0 + 11*p2.1 + 13*p2.2
// lowered: i64 (i64, i64, i8, i64, i8)
@inline(never) public func intsThenS_Tup3(_ p0: Int, _ p1: Int, _ p2: (Int8, Int, Int8)) -> Int {
    var h = 1151
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ Int(p2.0) &* 7
    h = h &+ p2.1 &* 11
    h = h &+ Int(p2.2) &* 13
    return h
}

// two_Pair_Wrap1: p0 two i64; p2 single-field wrapper: one i64
// result = 1153 + 3*p0.a + 5*p0.b + 7*p1 + 11*p2.a + 13*p3
// lowered: i64 (i64, i64, i64, i64, i64)
@inline(never) public func two_Pair_Wrap1(_ p0: Pair, _ p1: Int, _ p2: Wrap1, _ p3: Int) -> Int {
    var h = 1153
    h = h &+ p0.a &* 3
    h = h &+ p0.b &* 5
    h = h &+ p1 &* 7
    h = h &+ p2.a &* 11
    h = h &+ p3 &* 13
    return h
}

// two_Packed_IntDouble: p0 i8@0 i16@2 i32@4 packed into one 8-byte unit; p2 integer then double: x and d
// result = 1155 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p1 + 13*p2.a + 17*p2.b + 19*p3
// lowered: i64 (i64, i64, i64, double, i64)
@inline(never) public func two_Packed_IntDouble(_ p0: Packed, _ p1: Int, _ p2: IntDouble, _ p3: Int) -> Int {
    var h = 1155
    h = h &+ Int(p0.a) &* 3
    h = h &+ Int(p0.b) &* 5
    h = h &+ Int(p0.c) &* 7
    h = h &+ p1 &* 11
    h = h &+ p2.a &* 13
    h = h &+ Int(bitPattern: UInt(p2.b.bitPattern)) &* 17
    h = h &+ p3 &* 19
    return h
}

// two_FloatMid_Tri: p0 i32@0, float@4, i32@8: the float sits in the first unit beside an integer; p2 three i64
// result = 1157 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p1 + 13*p2.a + 17*p2.b + 19*p2.c + 23*p3
// lowered: i64 (i32, float, i32, i64, i64, i64, i64, i64)
@inline(never) public func two_FloatMid_Tri(_ p0: FloatMid, _ p1: Int, _ p2: Tri, _ p3: Int) -> Int {
    var h = 1157
    h = h &+ Int(p0.a) &* 3
    h = h &+ Int(p0.b.bitPattern) &* 5
    h = h &+ Int(p0.c) &* 7
    h = h &+ p1 &* 11
    h = h &+ p2.a &* 13
    h = h &+ Int(bitPattern: p2.b) &* 17
    h = h &+ p2.c &* 19
    h = h &+ p3 &* 23
    return h
}

// two_Quad_Pair: p0 exactly four register units; p2 two i64
// result = 1159 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1 + 17*p2.a + 19*p2.b + 23*p3
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64)
@inline(never) public func two_Quad_Pair(_ p0: Quad, _ p1: Int, _ p2: Pair, _ p3: Int) -> Int {
    var h = 1159
    h = h &+ p0.a &* 3
    h = h &+ p0.b &* 5
    h = h &+ p0.c &* 7
    h = h &+ p0.d &* 11
    h = h &+ p1 &* 13
    h = h &+ p2.a &* 17
    h = h &+ p2.b &* 19
    h = h &+ p3 &* 23
    return h
}

// two_Five_Packed: p0 five units: by address; p2 i8@0 i16@2 i32@4 packed into one 8-byte unit
// result = 1161 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p0.e + 17*p1 + 19*p2.a + 23*p2.b + 29*p2.c + 31*p3
// lowered: i64 (ptr, i64, i64, i64)
@inline(never) public func two_Five_Packed(_ p0: Five, _ p1: Int, _ p2: Packed, _ p3: Int) -> Int {
    var h = 1161
    h = h &+ p0.a &* 3
    h = h &+ p0.b &* 5
    h = h &+ p0.c &* 7
    h = h &+ p0.d &* 11
    h = h &+ p0.e &* 13
    h = h &+ p1 &* 17
    h = h &+ Int(p2.a) &* 19
    h = h &+ Int(p2.b) &* 23
    h = h &+ Int(p2.c) &* 29
    h = h &+ p3 &* 31
    return h
}

// two_TwoF_FourD: p0 two floats in one 8-byte unit: s0, s1; p2 four doubles: d0..d3
// result = 1163 + 3*p0.a + 5*p0.b + 7*p1 + 11*p2.a + 13*p2.b + 17*p2.c + 19*p2.d + 23*p3
// lowered: i64 (float, float, i64, double, double, double, double, i64)
@inline(never) public func two_TwoF_FourD(_ p0: TwoF, _ p1: Int, _ p2: FourD, _ p3: Int) -> Int {
    var h = 1163
    h = h &+ Int(p0.a.bitPattern) &* 3
    h = h &+ Int(p0.b.bitPattern) &* 5
    h = h &+ p1 &* 7
    h = h &+ Int(bitPattern: UInt(p2.a.bitPattern)) &* 11
    h = h &+ Int(bitPattern: UInt(p2.b.bitPattern)) &* 13
    h = h &+ Int(bitPattern: UInt(p2.c.bitPattern)) &* 17
    h = h &+ Int(bitPattern: UInt(p2.d.bitPattern)) &* 19
    h = h &+ p3 &* 23
    return h
}

// two_HalfMid_Straddle: p0 i16, Float16, i16, i16 in ONE 8-byte unit: the half splits the integers; p2 i8, padding to 8, i64, i8: three units
// result = 1165 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1 + 17*p2.a + 19*p2.b + 23*p2.c + 29*p3
// lowered: i64 (i16, half, i32, i64, i8, i64, i8, i64)
@inline(never) public func two_HalfMid_Straddle(_ p0: HalfMid, _ p1: Int, _ p2: Straddle, _ p3: Int) -> Int {
    var h = 1165
    h = h &+ Int(p0.a) &* 3
    h = h &+ Int(p0.b.bitPattern) &* 5
    h = h &+ Int(p0.c) &* 7
    h = h &+ Int(p0.d) &* 11
    h = h &+ p1 &* 13
    h = h &+ Int(p2.a) &* 17
    h = h &+ p2.b &* 19
    h = h &+ Int(p2.c) &* 23
    h = h &+ p3 &* 29
    return h
}

// two_MixFour_MixFour: p0 i32, float, double, i64: four scalars over two banks; p2 i32, float, double, i64: four scalars over two banks
// result = 1167 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1 + 17*p2.a + 19*p2.b + 23*p2.c + 29*p2.d + 31*p3
// lowered: i64 (i32, float, double, i64, i64, i32, float, double, i64, i64)
@inline(never) public func two_MixFour_MixFour(_ p0: MixFour, _ p1: Int, _ p2: MixFour, _ p3: Int) -> Int {
    var h = 1167
    h = h &+ Int(p0.a) &* 3
    h = h &+ Int(p0.b.bitPattern) &* 5
    h = h &+ Int(bitPattern: UInt(p0.c.bitPattern)) &* 7
    h = h &+ p0.d &* 11
    h = h &+ p1 &* 13
    h = h &+ Int(p2.a) &* 17
    h = h &+ Int(p2.b.bitPattern) &* 19
    h = h &+ Int(bitPattern: UInt(p2.c.bitPattern)) &* 23
    h = h &+ p2.d &* 29
    h = h &+ p3 &* 31
    return h
}

// two_Opts_PackedU: p0 Int32? (payload + tag in one unit) then Int? (i64 + tag byte); p2 bool@0 u8@1 u16@2 u32@4 packed into one unit
// result = 1169 + 3*p0.a + 5*p0.b + 7*p1 + 11*p2.a + 13*p2.b + 17*p2.c + 19*p2.d + 23*p3
// lowered: i64 (i64, i64, i8, i64, i64, i64)
@inline(never) public func two_Opts_PackedU(_ p0: Opts, _ p1: Int, _ p2: PackedU, _ p3: Int) -> Int {
    var h = 1169
    if let t = p0.a { h = h &+ Int(t) &* 3 } else { h = h &+ 322 }
    if let t = p0.b { h = h &+ t &* 5 } else { h = h &+ 536 }
    h = h &+ p1 &* 7
    h = h &+ (p2.a ? 1 : 0) &* 11
    h = h &+ Int(p2.b) &* 13
    h = h &+ Int(p2.c) &* 17
    h = h &+ Int(p2.d) &* 19
    h = h &+ p3 &* 23
    return h
}

// two_Empty_Nested: p0 no stored fields: takes no register; p2 Pair, Int32, Packed nested: i64, i64, i32, then a packed unit
// result = 1171 + 3*p1 + 5*p2.p.a + 7*p2.p.b + 11*p2.k + 13*p2.q.a + 17*p2.q.b + 19*p2.q.c + 23*p3
// lowered: i64 (i64, i64, i64, i64, i32, i64)
@inline(never) public func two_Empty_Nested(_ p0: Empty, _ p1: Int, _ p2: Nested, _ p3: Int) -> Int {
    var h = 1171
    h = h &+ p1 &* 3
    h = h &+ p2.p.a &* 5
    h = h &+ p2.p.b &* 7
    h = h &+ Int(p2.k) &* 11
    h = h &+ Int(p2.q.a) &* 13
    h = h &+ Int(p2.q.b) &* 17
    h = h &+ Int(p2.q.c) &* 19
    h = h &+ p3 &* 23
    return h
}

// two_Quad_Quad: p0 exactly four register units; p2 exactly four register units
// result = 1173 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1 + 17*p2.a + 19*p2.b + 23*p2.c + 29*p2.d + 31*p3
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64)
@inline(never) public func two_Quad_Quad(_ p0: Quad, _ p1: Int, _ p2: Quad, _ p3: Int) -> Int {
    var h = 1173
    h = h &+ p0.a &* 3
    h = h &+ p0.b &* 5
    h = h &+ p0.c &* 7
    h = h &+ p0.d &* 11
    h = h &+ p1 &* 13
    h = h &+ p2.a &* 17
    h = h &+ p2.b &* 19
    h = h &+ p2.c &* 23
    h = h &+ p2.d &* 29
    h = h &+ p3 &* 31
    return h
}

// Pair.borrowHash: borrowing self Pair (two i64)
// result = 1175 + 3*self.a + 5*self.b + 7*k0 + 11*k1
// lowered: i64 (i64, i64, i64, i64)
extension Pair { @inline(never) public borrowing func borrowHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1175
    h = h &+ self.a &* 3
    h = h &+ self.b &* 5
    h = h &+ k0 &* 7
    h = h &+ k1 &* 11
    return h
} }

// Pair.consumeHash: consuming self Pair (two i64)
// result = 1177 + 3*self.a + 5*self.b + 7*k0
// lowered: i64 (i64, i64, i64)
extension Pair { @inline(never) public consuming func consumeHash(_ k0: Int) -> Int {
    var h = 1177
    h = h &+ self.a &* 3
    h = h &+ self.b &* 5
    h = h &+ k0 &* 7
    return h
} }

// Pair.mutateHash: mutating self Pair (two i64)
// result = 1179 + 3*self.a + 5*self.b + 7*k0 + 11*k1; then stores k0+1179 (narrowed) into self.b
// lowered: i64 (i64, i64, ptr swiftself)
extension Pair { @inline(never) public mutating func mutateHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1179
    h = h &+ self.a &* 3
    h = h &+ self.b &* 5
    h = h &+ k0 &* 7
    h = h &+ k1 &* 11
    self.b = k0 &+ 1179
    return h
} }

// Quad.borrowHash: borrowing self Quad (exactly four register units)
// result = 1181 + 3*self.a + 5*self.b + 7*self.c + 11*self.d + 13*k0 + 17*k1
// lowered: i64 (i64, i64, i64, i64, i64, i64)
extension Quad { @inline(never) public borrowing func borrowHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1181
    h = h &+ self.a &* 3
    h = h &+ self.b &* 5
    h = h &+ self.c &* 7
    h = h &+ self.d &* 11
    h = h &+ k0 &* 13
    h = h &+ k1 &* 17
    return h
} }

// Quad.consumeHash: consuming self Quad (exactly four register units)
// result = 1183 + 3*self.a + 5*self.b + 7*self.c + 11*self.d + 13*k0
// lowered: i64 (i64, i64, i64, i64, i64)
extension Quad { @inline(never) public consuming func consumeHash(_ k0: Int) -> Int {
    var h = 1183
    h = h &+ self.a &* 3
    h = h &+ self.b &* 5
    h = h &+ self.c &* 7
    h = h &+ self.d &* 11
    h = h &+ k0 &* 13
    return h
} }

// Quad.mutateHash: mutating self Quad (exactly four register units)
// result = 1185 + 3*self.a + 5*self.b + 7*self.c + 11*self.d + 13*k0 + 17*k1; then stores k0+1185 (narrowed) into self.d
// lowered: i64 (i64, i64, ptr swiftself)
extension Quad { @inline(never) public mutating func mutateHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1185
    h = h &+ self.a &* 3
    h = h &+ self.b &* 5
    h = h &+ self.c &* 7
    h = h &+ self.d &* 11
    h = h &+ k0 &* 13
    h = h &+ k1 &* 17
    self.d = k0 &+ 1185
    return h
} }

// Five.borrowHash: borrowing self Five (five units: by address)
// result = 1187 + 3*self.a + 5*self.b + 7*self.c + 11*self.d + 13*self.e + 17*k0 + 19*k1
// lowered: i64 (i64, i64, ptr swiftself)
extension Five { @inline(never) public borrowing func borrowHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1187
    h = h &+ self.a &* 3
    h = h &+ self.b &* 5
    h = h &+ self.c &* 7
    h = h &+ self.d &* 11
    h = h &+ self.e &* 13
    h = h &+ k0 &* 17
    h = h &+ k1 &* 19
    return h
} }

// Five.consumeHash: consuming self Five (five units: by address)
// result = 1189 + 3*self.a + 5*self.b + 7*self.c + 11*self.d + 13*self.e + 17*k0
// lowered: i64 (i64, ptr swiftself)
extension Five { @inline(never) public consuming func consumeHash(_ k0: Int) -> Int {
    var h = 1189
    h = h &+ self.a &* 3
    h = h &+ self.b &* 5
    h = h &+ self.c &* 7
    h = h &+ self.d &* 11
    h = h &+ self.e &* 13
    h = h &+ k0 &* 17
    return h
} }

// Five.mutateHash: mutating self Five (five units: by address)
// result = 1191 + 3*self.a + 5*self.b + 7*self.c + 11*self.d + 13*self.e + 17*k0 + 19*k1; then stores k0+1191 (narrowed) into self.e
// lowered: i64 (i64, i64, ptr swiftself)
extension Five { @inline(never) public mutating func mutateHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1191
    h = h &+ self.a &* 3
    h = h &+ self.b &* 5
    h = h &+ self.c &* 7
    h = h &+ self.d &* 11
    h = h &+ self.e &* 13
    h = h &+ k0 &* 17
    h = h &+ k1 &* 19
    self.e = k0 &+ 1191
    return h
} }

// Packed.borrowHash: borrowing self Packed (i8@0 i16@2 i32@4 packed into one 8-byte unit)
// result = 1193 + 3*self.a + 5*self.b + 7*self.c + 11*k0 + 13*k1
// lowered: i64 (i64, i64, i64)
extension Packed { @inline(never) public borrowing func borrowHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1193
    h = h &+ Int(self.a) &* 3
    h = h &+ Int(self.b) &* 5
    h = h &+ Int(self.c) &* 7
    h = h &+ k0 &* 11
    h = h &+ k1 &* 13
    return h
} }

// Packed.consumeHash: consuming self Packed (i8@0 i16@2 i32@4 packed into one 8-byte unit)
// result = 1195 + 3*self.a + 5*self.b + 7*self.c + 11*k0
// lowered: i64 (i64, i64)
extension Packed { @inline(never) public consuming func consumeHash(_ k0: Int) -> Int {
    var h = 1195
    h = h &+ Int(self.a) &* 3
    h = h &+ Int(self.b) &* 5
    h = h &+ Int(self.c) &* 7
    h = h &+ k0 &* 11
    return h
} }

// Packed.mutateHash: mutating self Packed (i8@0 i16@2 i32@4 packed into one 8-byte unit)
// result = 1197 + 3*self.a + 5*self.b + 7*self.c + 11*k0 + 13*k1; then stores k0+1197 (narrowed) into self.c
// lowered: i64 (i64, i64, ptr swiftself)
extension Packed { @inline(never) public mutating func mutateHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1197
    h = h &+ Int(self.a) &* 3
    h = h &+ Int(self.b) &* 5
    h = h &+ Int(self.c) &* 7
    h = h &+ k0 &* 11
    h = h &+ k1 &* 13
    self.c = Int32(truncatingIfNeeded: k0 &+ 1197)
    return h
} }

// FloatMid.borrowHash: borrowing self FloatMid (i32@0, float@4, i32@8: the float sits in the first unit beside an integer)
// result = 1199 + 3*self.a + 5*self.b + 7*self.c + 11*k0 + 13*k1
// lowered: i64 (i64, i64, i32, float, i32)
extension FloatMid { @inline(never) public borrowing func borrowHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1199
    h = h &+ Int(self.a) &* 3
    h = h &+ Int(self.b.bitPattern) &* 5
    h = h &+ Int(self.c) &* 7
    h = h &+ k0 &* 11
    h = h &+ k1 &* 13
    return h
} }

// FloatMid.consumeHash: consuming self FloatMid (i32@0, float@4, i32@8: the float sits in the first unit beside an integer)
// result = 1201 + 3*self.a + 5*self.b + 7*self.c + 11*k0
// lowered: i64 (i64, i32, float, i32)
extension FloatMid { @inline(never) public consuming func consumeHash(_ k0: Int) -> Int {
    var h = 1201
    h = h &+ Int(self.a) &* 3
    h = h &+ Int(self.b.bitPattern) &* 5
    h = h &+ Int(self.c) &* 7
    h = h &+ k0 &* 11
    return h
} }

// FloatMid.mutateHash: mutating self FloatMid (i32@0, float@4, i32@8: the float sits in the first unit beside an integer)
// result = 1203 + 3*self.a + 5*self.b + 7*self.c + 11*k0 + 13*k1; then stores k0+1203 (narrowed) into self.c
// lowered: i64 (i64, i64, ptr swiftself)
extension FloatMid { @inline(never) public mutating func mutateHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1203
    h = h &+ Int(self.a) &* 3
    h = h &+ Int(self.b.bitPattern) &* 5
    h = h &+ Int(self.c) &* 7
    h = h &+ k0 &* 11
    h = h &+ k1 &* 13
    self.c = Int32(truncatingIfNeeded: k0 &+ 1203)
    return h
} }

// HalfMid.borrowHash: borrowing self HalfMid (i16, Float16, i16, i16 in ONE 8-byte unit: the half splits the integers)
// result = 1205 + 3*self.a + 5*self.b + 7*self.c + 11*self.d + 13*k0 + 17*k1
// lowered: i64 (i64, i64, i16, half, i32)
extension HalfMid { @inline(never) public borrowing func borrowHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1205
    h = h &+ Int(self.a) &* 3
    h = h &+ Int(self.b.bitPattern) &* 5
    h = h &+ Int(self.c) &* 7
    h = h &+ Int(self.d) &* 11
    h = h &+ k0 &* 13
    h = h &+ k1 &* 17
    return h
} }

// HalfMid.consumeHash: consuming self HalfMid (i16, Float16, i16, i16 in ONE 8-byte unit: the half splits the integers)
// result = 1207 + 3*self.a + 5*self.b + 7*self.c + 11*self.d + 13*k0
// lowered: i64 (i64, i16, half, i32)
extension HalfMid { @inline(never) public consuming func consumeHash(_ k0: Int) -> Int {
    var h = 1207
    h = h &+ Int(self.a) &* 3
    h = h &+ Int(self.b.bitPattern) &* 5
    h = h &+ Int(self.c) &* 7
    h = h &+ Int(self.d) &* 11
    h = h &+ k0 &* 13
    return h
} }

// HalfMid.mutateHash: mutating self HalfMid (i16, Float16, i16, i16 in ONE 8-byte unit: the half splits the integers)
// result = 1209 + 3*self.a + 5*self.b + 7*self.c + 11*self.d + 13*k0 + 17*k1; then stores k0+1209 (narrowed) into self.d
// lowered: i64 (i64, i64, ptr swiftself)
extension HalfMid { @inline(never) public mutating func mutateHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1209
    h = h &+ Int(self.a) &* 3
    h = h &+ Int(self.b.bitPattern) &* 5
    h = h &+ Int(self.c) &* 7
    h = h &+ Int(self.d) &* 11
    h = h &+ k0 &* 13
    h = h &+ k1 &* 17
    self.d = Int16(truncatingIfNeeded: k0 &+ 1209)
    return h
} }

// MixFour.borrowHash: borrowing self MixFour (i32, float, double, i64: four scalars over two banks)
// result = 1211 + 3*self.a + 5*self.b + 7*self.c + 11*self.d + 13*k0 + 17*k1
// lowered: i64 (i64, i64, i32, float, double, i64)
extension MixFour { @inline(never) public borrowing func borrowHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1211
    h = h &+ Int(self.a) &* 3
    h = h &+ Int(self.b.bitPattern) &* 5
    h = h &+ Int(bitPattern: UInt(self.c.bitPattern)) &* 7
    h = h &+ self.d &* 11
    h = h &+ k0 &* 13
    h = h &+ k1 &* 17
    return h
} }

// MixFour.consumeHash: consuming self MixFour (i32, float, double, i64: four scalars over two banks)
// result = 1213 + 3*self.a + 5*self.b + 7*self.c + 11*self.d + 13*k0
// lowered: i64 (i64, i32, float, double, i64)
extension MixFour { @inline(never) public consuming func consumeHash(_ k0: Int) -> Int {
    var h = 1213
    h = h &+ Int(self.a) &* 3
    h = h &+ Int(self.b.bitPattern) &* 5
    h = h &+ Int(bitPattern: UInt(self.c.bitPattern)) &* 7
    h = h &+ self.d &* 11
    h = h &+ k0 &* 13
    return h
} }

// MixFour.mutateHash: mutating self MixFour (i32, float, double, i64: four scalars over two banks)
// result = 1215 + 3*self.a + 5*self.b + 7*self.c + 11*self.d + 13*k0 + 17*k1; then stores k0+1215 (narrowed) into self.d
// lowered: i64 (i64, i64, ptr swiftself)
extension MixFour { @inline(never) public mutating func mutateHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1215
    h = h &+ Int(self.a) &* 3
    h = h &+ Int(self.b.bitPattern) &* 5
    h = h &+ Int(bitPattern: UInt(self.c.bitPattern)) &* 7
    h = h &+ self.d &* 11
    h = h &+ k0 &* 13
    h = h &+ k1 &* 17
    self.d = k0 &+ 1215
    return h
} }

// Straddle.borrowHash: borrowing self Straddle (i8, padding to 8, i64, i8: three units)
// result = 1217 + 3*self.a + 5*self.b + 7*self.c + 11*k0 + 13*k1
// lowered: i64 (i64, i64, i8, i64, i8)
extension Straddle { @inline(never) public borrowing func borrowHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1217
    h = h &+ Int(self.a) &* 3
    h = h &+ self.b &* 5
    h = h &+ Int(self.c) &* 7
    h = h &+ k0 &* 11
    h = h &+ k1 &* 13
    return h
} }

// Straddle.consumeHash: consuming self Straddle (i8, padding to 8, i64, i8: three units)
// result = 1219 + 3*self.a + 5*self.b + 7*self.c + 11*k0
// lowered: i64 (i64, i8, i64, i8)
extension Straddle { @inline(never) public consuming func consumeHash(_ k0: Int) -> Int {
    var h = 1219
    h = h &+ Int(self.a) &* 3
    h = h &+ self.b &* 5
    h = h &+ Int(self.c) &* 7
    h = h &+ k0 &* 11
    return h
} }

// Straddle.mutateHash: mutating self Straddle (i8, padding to 8, i64, i8: three units)
// result = 1221 + 3*self.a + 5*self.b + 7*self.c + 11*k0 + 13*k1; then stores k0+1221 (narrowed) into self.c
// lowered: i64 (i64, i64, ptr swiftself)
extension Straddle { @inline(never) public mutating func mutateHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1221
    h = h &+ Int(self.a) &* 3
    h = h &+ self.b &* 5
    h = h &+ Int(self.c) &* 7
    h = h &+ k0 &* 11
    h = h &+ k1 &* 13
    self.c = Int8(truncatingIfNeeded: k0 &+ 1221)
    return h
} }

// Opts.borrowHash: borrowing self Opts (Int32? (payload + tag in one unit) then Int? (i64 + tag byte))
// result = 1223 + 3*self.a + 5*self.b + 7*k0 + 11*k1
// lowered: i64 (i64, i64, i64, i64, i8)
extension Opts { @inline(never) public borrowing func borrowHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1223
    if let t = self.a { h = h &+ Int(t) &* 3 } else { h = h &+ 322 }
    if let t = self.b { h = h &+ t &* 5 } else { h = h &+ 536 }
    h = h &+ k0 &* 7
    h = h &+ k1 &* 11
    return h
} }

// Opts.consumeHash: consuming self Opts (Int32? (payload + tag in one unit) then Int? (i64 + tag byte))
// result = 1225 + 3*self.a + 5*self.b + 7*k0
// lowered: i64 (i64, i64, i64, i8)
extension Opts { @inline(never) public consuming func consumeHash(_ k0: Int) -> Int {
    var h = 1225
    if let t = self.a { h = h &+ Int(t) &* 3 } else { h = h &+ 322 }
    if let t = self.b { h = h &+ t &* 5 } else { h = h &+ 536 }
    h = h &+ k0 &* 7
    return h
} }

// Opts.mutateHash: mutating self Opts (Int32? (payload + tag in one unit) then Int? (i64 + tag byte))
// result = 1227 + 3*self.a + 5*self.b + 7*k0 + 11*k1; then stores k0+1227 (narrowed) into self.b
// lowered: i64 (i64, i64, ptr swiftself)
extension Opts { @inline(never) public mutating func mutateHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1227
    if let t = self.a { h = h &+ Int(t) &* 3 } else { h = h &+ 322 }
    if let t = self.b { h = h &+ t &* 5 } else { h = h &+ 536 }
    h = h &+ k0 &* 7
    h = h &+ k1 &* 11
    self.b = (((k0 &+ 1227) & 1) == 0 ? nil : ((k0 &+ 1227) >> 1))
    return h
} }

// PtrRef.borrowHash: borrowing self PtrRef (raw pointer, class reference, Bool)
// result = 1229 + 3*self.p + 5*self.r + 7*self.f + 11*k0 + 13*k1
// lowered: i64 (i64, i64, i64, ptr, i1)
extension PtrRef { @inline(never) public borrowing func borrowHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1229
    h = h &+ Int(bitPattern: self.p) &* 3
    h = h &+ self.r.v &* 5
    h = h &+ (self.f ? 1 : 0) &* 7
    h = h &+ k0 &* 11
    h = h &+ k1 &* 13
    return h
} }

// PtrRef.consumeHash: consuming self PtrRef (raw pointer, class reference, Bool)
// result = 1231 + 3*self.p + 5*self.r + 7*self.f + 11*k0
// lowered: i64 (i64, i64, ptr, i1)
extension PtrRef { @inline(never) public consuming func consumeHash(_ k0: Int) -> Int {
    var h = 1231
    h = h &+ Int(bitPattern: self.p) &* 3
    h = h &+ self.r.v &* 5
    h = h &+ (self.f ? 1 : 0) &* 7
    h = h &+ k0 &* 11
    return h
} }

// Wrap1.borrowHash: borrowing self Wrap1 (single-field wrapper: one i64)
// result = 1233 + 3*self.a + 5*k0 + 7*k1
// lowered: i64 (i64, i64, i64)
extension Wrap1 { @inline(never) public borrowing func borrowHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1233
    h = h &+ self.a &* 3
    h = h &+ k0 &* 5
    h = h &+ k1 &* 7
    return h
} }

// Wrap1.consumeHash: consuming self Wrap1 (single-field wrapper: one i64)
// result = 1235 + 3*self.a + 5*k0
// lowered: i64 (i64, i64)
extension Wrap1 { @inline(never) public consuming func consumeHash(_ k0: Int) -> Int {
    var h = 1235
    h = h &+ self.a &* 3
    h = h &+ k0 &* 5
    return h
} }

// Wrap1.mutateHash: mutating self Wrap1 (single-field wrapper: one i64)
// result = 1237 + 3*self.a + 5*k0 + 7*k1; then stores k0+1237 (narrowed) into self.a
// lowered: i64 (i64, i64, ptr swiftself)
extension Wrap1 { @inline(never) public mutating func mutateHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1237
    h = h &+ self.a &* 3
    h = h &+ k0 &* 5
    h = h &+ k1 &* 7
    self.a = k0 &+ 1237
    return h
} }

// Empty.borrowHash: borrowing self Empty (no stored fields: takes no register)
// result = 1239 + 3*k0 + 5*k1
// lowered: i64 (i64, i64)
extension Empty { @inline(never) public borrowing func borrowHash(_ k0: Int, _ k1: Int) -> Int {
    var h = 1239
    h = h &+ k0 &* 3
    h = h &+ k1 &* 5
    return h
} }

// Empty.consumeHash: consuming self Empty (no stored fields: takes no register)
// result = 1241 + 3*k0
// lowered: i64 (i64)
extension Empty { @inline(never) public consuming func consumeHash(_ k0: Int) -> Int {
    var h = 1241
    h = h &+ k0 &* 3
    return h
} }

// eightThenQuad: p8 exactly four register units
// result = 1243 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6 + 23*p7 + 29*p8.a + 31*p8.b + 37*p8.c + 41*p8.d
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64)
@inline(never) public func eightThenQuad(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int, _ p5: Int, _ p6: Int, _ p7: Int, _ p8: Quad) -> Int {
    var h = 1243
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3 &* 11
    h = h &+ p4 &* 13
    h = h &+ p5 &* 17
    h = h &+ p6 &* 19
    h = h &+ p7 &* 23
    h = h &+ p8.a &* 29
    h = h &+ p8.b &* 31
    h = h &+ p8.c &* 37
    h = h &+ p8.d &* 41
    return h
}

// sixThenQuad: p6 exactly four register units
// result = 1245 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6.a + 23*p6.b + 29*p6.c + 31*p6.d
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64)
@inline(never) public func sixThenQuad(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int, _ p5: Int, _ p6: Quad) -> Int {
    var h = 1245
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3 &* 11
    h = h &+ p4 &* 13
    h = h &+ p5 &* 17
    h = h &+ p6.a &* 19
    h = h &+ p6.b &* 23
    h = h &+ p6.c &* 29
    h = h &+ p6.d &* 31
    return h
}

// sevenThenPair: p7 two i64
// result = 1247 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6 + 23*p7.a + 29*p7.b
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, i64)
@inline(never) public func sevenThenPair(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int, _ p5: Int, _ p6: Int, _ p7: Pair) -> Int {
    var h = 1247
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3 &* 11
    h = h &+ p4 &* 13
    h = h &+ p5 &* 17
    h = h &+ p6 &* 19
    h = h &+ p7.a &* 23
    h = h &+ p7.b &* 29
    return h
}

// eightThenPacked: p8 i8@0 i16@2 i32@4 packed into one 8-byte unit
// result = 1249 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6 + 23*p7 + 29*p8.a + 31*p8.b + 37*p8.c
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, i64)
@inline(never) public func eightThenPacked(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int, _ p5: Int, _ p6: Int, _ p7: Int, _ p8: Packed) -> Int {
    var h = 1249
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3 &* 11
    h = h &+ p4 &* 13
    h = h &+ p5 &* 17
    h = h &+ p6 &* 19
    h = h &+ p7 &* 23
    h = h &+ Int(p8.a) &* 29
    h = h &+ Int(p8.b) &* 31
    h = h &+ Int(p8.c) &* 37
    return h
}

// eightThenWrap1: p8 single-field wrapper: one i64
// result = 1251 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6 + 23*p7 + 29*p8.a + 31*p9
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64)
@inline(never) public func eightThenWrap1(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int, _ p5: Int, _ p6: Int, _ p7: Int, _ p8: Wrap1, _ p9: Int) -> Int {
    var h = 1251
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3 &* 11
    h = h &+ p4 &* 13
    h = h &+ p5 &* 17
    h = h &+ p6 &* 19
    h = h &+ p7 &* 23
    h = h &+ p8.a &* 29
    h = h &+ p9 &* 31
    return h
}

// eightThenFive: p8 five units: by address
// result = 1253 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6 + 23*p7 + 29*p8.a + 31*p8.b + 37*p8.c + 41*p8.d + 43*p8.e
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, ptr)
@inline(never) public func eightThenFive(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int, _ p5: Int, _ p6: Int, _ p7: Int, _ p8: Five) -> Int {
    var h = 1253
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3 &* 11
    h = h &+ p4 &* 13
    h = h &+ p5 &* 17
    h = h &+ p6 &* 19
    h = h &+ p7 &* 23
    h = h &+ p8.a &* 29
    h = h &+ p8.b &* 31
    h = h &+ p8.c &* 37
    h = h &+ p8.d &* 41
    h = h &+ p8.e &* 43
    return h
}

// sevenThenFive: p7 five units: by address
// result = 1255 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6 + 23*p7.a + 29*p7.b + 31*p7.c + 37*p7.d + 41*p7.e + 43*p8
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, ptr, i64)
@inline(never) public func sevenThenFive(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int, _ p5: Int, _ p6: Int, _ p7: Five, _ p8: Int) -> Int {
    var h = 1255
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3 &* 11
    h = h &+ p4 &* 13
    h = h &+ p5 &* 17
    h = h &+ p6 &* 19
    h = h &+ p7.a &* 23
    h = h &+ p7.b &* 29
    h = h &+ p7.c &* 31
    h = h &+ p7.d &* 37
    h = h &+ p7.e &* 41
    h = h &+ p8 &* 43
    return h
}

// eightThenIntDouble: p8 integer then double: x and d
// result = 1257 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6 + 23*p7 + 29*p8.a + 31*p8.b
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, i64, double)
@inline(never) public func eightThenIntDouble(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int, _ p5: Int, _ p6: Int, _ p7: Int, _ p8: IntDouble) -> Int {
    var h = 1257
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3 &* 11
    h = h &+ p4 &* 13
    h = h &+ p5 &* 17
    h = h &+ p6 &* 19
    h = h &+ p7 &* 23
    h = h &+ p8.a &* 29
    h = h &+ Int(bitPattern: UInt(p8.b.bitPattern)) &* 31
    return h
}

// sevenDThenFourD: p7 four doubles: d0..d3
// result = 1259 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6 + 23*p7.a + 29*p7.b + 31*p7.c + 37*p7.d
// lowered: i64 (double, double, double, double, double, double, double, double, double, double, double)
@inline(never) public func sevenDThenFourD(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ p4: Double, _ p5: Double, _ p6: Double, _ p7: FourD) -> Int {
    var h = 1259
    h = h &+ Int(bitPattern: UInt(p0.bitPattern)) &* 3
    h = h &+ Int(bitPattern: UInt(p1.bitPattern)) &* 5
    h = h &+ Int(bitPattern: UInt(p2.bitPattern)) &* 7
    h = h &+ Int(bitPattern: UInt(p3.bitPattern)) &* 11
    h = h &+ Int(bitPattern: UInt(p4.bitPattern)) &* 13
    h = h &+ Int(bitPattern: UInt(p5.bitPattern)) &* 17
    h = h &+ Int(bitPattern: UInt(p6.bitPattern)) &* 19
    h = h &+ Int(bitPattern: UInt(p7.a.bitPattern)) &* 23
    h = h &+ Int(bitPattern: UInt(p7.b.bitPattern)) &* 29
    h = h &+ Int(bitPattern: UInt(p7.c.bitPattern)) &* 31
    h = h &+ Int(bitPattern: UInt(p7.d.bitPattern)) &* 37
    return h
}

// eightDThenDoubleInt: p8 double then integer: d and x
// result = 1261 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6 + 23*p7 + 29*p8.a + 31*p8.b + 37*p9
// lowered: i64 (double, double, double, double, double, double, double, double, double, i64, i64)
@inline(never) public func eightDThenDoubleInt(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ p4: Double, _ p5: Double, _ p6: Double, _ p7: Double, _ p8: DoubleInt, _ p9: Int) -> Int {
    var h = 1261
    h = h &+ Int(bitPattern: UInt(p0.bitPattern)) &* 3
    h = h &+ Int(bitPattern: UInt(p1.bitPattern)) &* 5
    h = h &+ Int(bitPattern: UInt(p2.bitPattern)) &* 7
    h = h &+ Int(bitPattern: UInt(p3.bitPattern)) &* 11
    h = h &+ Int(bitPattern: UInt(p4.bitPattern)) &* 13
    h = h &+ Int(bitPattern: UInt(p5.bitPattern)) &* 17
    h = h &+ Int(bitPattern: UInt(p6.bitPattern)) &* 19
    h = h &+ Int(bitPattern: UInt(p7.bitPattern)) &* 23
    h = h &+ Int(bitPattern: UInt(p8.a.bitPattern)) &* 29
    h = h &+ p8.b &* 31
    h = h &+ p9 &* 37
    return h
}

// quadQuadInt: p0 exactly four register units; p1 exactly four register units
// result = 1263 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1.a + 17*p1.b + 19*p1.c + 23*p1.d + 29*p2
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, i64)
@inline(never) public func quadQuadInt(_ p0: Quad, _ p1: Quad, _ p2: Int) -> Int {
    var h = 1263
    h = h &+ p0.a &* 3
    h = h &+ p0.b &* 5
    h = h &+ p0.c &* 7
    h = h &+ p0.d &* 11
    h = h &+ p1.a &* 13
    h = h &+ p1.b &* 17
    h = h &+ p1.c &* 19
    h = h &+ p1.d &* 23
    h = h &+ p2 &* 29
    return h
}

// fourDFourDDoubleInt: p0 four doubles: d0..d3; p1 four doubles: d0..d3
// result = 1265 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1.a + 17*p1.b + 19*p1.c + 23*p1.d + 29*p2 + 31*p3
// lowered: i64 (double, double, double, double, double, double, double, double, double, i64)
@inline(never) public func fourDFourDDoubleInt(_ p0: FourD, _ p1: FourD, _ p2: Double, _ p3: Int) -> Int {
    var h = 1265
    h = h &+ Int(bitPattern: UInt(p0.a.bitPattern)) &* 3
    h = h &+ Int(bitPattern: UInt(p0.b.bitPattern)) &* 5
    h = h &+ Int(bitPattern: UInt(p0.c.bitPattern)) &* 7
    h = h &+ Int(bitPattern: UInt(p0.d.bitPattern)) &* 11
    h = h &+ Int(bitPattern: UInt(p1.a.bitPattern)) &* 13
    h = h &+ Int(bitPattern: UInt(p1.b.bitPattern)) &* 17
    h = h &+ Int(bitPattern: UInt(p1.c.bitPattern)) &* 19
    h = h &+ Int(bitPattern: UInt(p1.d.bitPattern)) &* 23
    h = h &+ Int(bitPattern: UInt(p2.bitPattern)) &* 29
    h = h &+ p3 &* 31
    return h
}

// mixFourTwiceTail: p0 i32, float, double, i64: four scalars over two banks; p2 i32, float, double, i64: four scalars over two banks
// result = 1267 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p1 + 17*p2.a + 19*p2.b + 23*p2.c + 29*p2.d + 31*p3 + 37*p4
// lowered: i64 (i32, float, double, i64, i64, i32, float, double, i64, double, i64)
@inline(never) public func mixFourTwiceTail(_ p0: MixFour, _ p1: Int, _ p2: MixFour, _ p3: Double, _ p4: Int) -> Int {
    var h = 1267
    h = h &+ Int(p0.a) &* 3
    h = h &+ Int(p0.b.bitPattern) &* 5
    h = h &+ Int(bitPattern: UInt(p0.c.bitPattern)) &* 7
    h = h &+ p0.d &* 11
    h = h &+ p1 &* 13
    h = h &+ Int(p2.a) &* 17
    h = h &+ Int(p2.b.bitPattern) &* 19
    h = h &+ Int(bitPattern: UInt(p2.c.bitPattern)) &* 23
    h = h &+ p2.d &* 29
    h = h &+ Int(bitPattern: UInt(p3.bitPattern)) &* 31
    h = h &+ p4 &* 37
    return h
}

// triTriTri: p0 three i64; p1 three i64; p2 three i64
// result = 1269 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p1.a + 13*p1.b + 17*p1.c + 19*p2.a + 23*p2.b + 29*p2.c
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, i64)
@inline(never) public func triTriTri(_ p0: Tri, _ p1: Tri, _ p2: Tri) -> Int {
    var h = 1269
    h = h &+ p0.a &* 3
    h = h &+ Int(bitPattern: p0.b) &* 5
    h = h &+ p0.c &* 7
    h = h &+ p1.a &* 11
    h = h &+ Int(bitPattern: p1.b) &* 13
    h = h &+ p1.c &* 17
    h = h &+ p2.a &* 19
    h = h &+ Int(bitPattern: p2.b) &* 23
    h = h &+ p2.c &* 29
    return h
}

// fiveFive: p0 five units: by address; p2 five units: by address
// result = 1271 + 3*p0.a + 5*p0.b + 7*p0.c + 11*p0.d + 13*p0.e + 17*p1 + 19*p2.a + 23*p2.b + 29*p2.c + 31*p2.d + 37*p2.e + 41*p3
// lowered: i64 (ptr, i64, ptr, i64)
@inline(never) public func fiveFive(_ p0: Five, _ p1: Int, _ p2: Five, _ p3: Int) -> Int {
    var h = 1271
    h = h &+ p0.a &* 3
    h = h &+ p0.b &* 5
    h = h &+ p0.c &* 7
    h = h &+ p0.d &* 11
    h = h &+ p0.e &* 13
    h = h &+ p1 &* 17
    h = h &+ p2.a &* 19
    h = h &+ p2.b &* 23
    h = h &+ p2.c &* 29
    h = h &+ p2.d &* 31
    h = h &+ p2.e &* 37
    h = h &+ p3 &* 41
    return h
}

// eightThenEmptyInt: p8 no stored fields: takes no register
// result = 1273 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6 + 23*p7 + 29*p9
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, i64)
@inline(never) public func eightThenEmptyInt(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int, _ p5: Int, _ p6: Int, _ p7: Int, _ p8: Empty, _ p9: Int) -> Int {
    var h = 1273
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3 &* 11
    h = h &+ p4 &* 13
    h = h &+ p5 &* 17
    h = h &+ p6 &* 19
    h = h &+ p7 &* 23
    h = h &+ p9 &* 29
    return h
}

// eightThenHalfMid: p8 i16, Float16, i16, i16 in ONE 8-byte unit: the half splits the integers
// result = 1275 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6 + 23*p7 + 29*p8.a + 31*p8.b + 37*p8.c + 41*p8.d
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, i16, half, i32)
@inline(never) public func eightThenHalfMid(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int, _ p5: Int, _ p6: Int, _ p7: Int, _ p8: HalfMid) -> Int {
    var h = 1275
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3 &* 11
    h = h &+ p4 &* 13
    h = h &+ p5 &* 17
    h = h &+ p6 &* 19
    h = h &+ p7 &* 23
    h = h &+ Int(p8.a) &* 29
    h = h &+ Int(p8.b.bitPattern) &* 31
    h = h &+ Int(p8.c) &* 37
    h = h &+ Int(p8.d) &* 41
    return h
}

// controlFiveInts: control, scalars only
// result = 1277 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4
// lowered: i64 (i64, i64, i64, i64, i64)
@inline(never) public func controlFiveInts(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int) -> Int {
    var h = 1277
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3 &* 11
    h = h &+ p4 &* 13
    return h
}

// controlNineInts: control, scalars only
// result = 1279 + 3*p0 + 5*p1 + 7*p2 + 11*p3 + 13*p4 + 17*p5 + 19*p6 + 23*p7 + 29*p8
// lowered: i64 (i64, i64, i64, i64, i64, i64, i64, i64, i64)
@inline(never) public func controlNineInts(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int, _ p5: Int, _ p6: Int, _ p7: Int, _ p8: Int) -> Int {
    var h = 1279
    h = h &+ p0 &* 3
    h = h &+ p1 &* 5
    h = h &+ p2 &* 7
    h = h &+ p3 &* 11
    h = h &+ p4 &* 13
    h = h &+ p5 &* 17
    h = h &+ p6 &* 19
    h = h &+ p7 &* 23
    h = h &+ p8 &* 29
    return h
}

// controlIntsDoubles: control, scalars only
// result = 1281 + 3*p0 + 5*p1 + 7*p2 + 11*p3
// lowered: i64 (i64, double, i64, double)
@inline(never) public func controlIntsDoubles(_ p0: Int, _ p1: Double, _ p2: Int, _ p3: Double) -> Int {
    var h = 1281
    h = h &+ p0 &* 3
    h = h &+ Int(bitPattern: UInt(p1.bitPattern)) &* 5
    h = h &+ p2 &* 7
    h = h &+ Int(bitPattern: UInt(p3.bitPattern)) &* 11
    return h
}

// The driver's entry points.
@_cdecl("e_sThenInts_Wrap1") public func e_sThenInts_Wrap1(_ v: UnsafePointer<Int>) -> Int { sThenInts_Wrap1(Wrap1(a: v[0]), v[1], v[2]) }
@_cdecl("e_intsThenS_Wrap1") public func e_intsThenS_Wrap1(_ v: UnsafePointer<Int>) -> Int { intsThenS_Wrap1(v[0], v[1], v[2], Wrap1(a: v[3])) }
@_cdecl("e_make_Wrap1") public func e_make_Wrap1(_ v: UnsafePointer<Int>) -> Int { let s = make_Wrap1(v[0]); var h = 1005; h = h &+ s.a &* 3; return h }
@_cdecl("e_sThenInts_Pair") public func e_sThenInts_Pair(_ v: UnsafePointer<Int>) -> Int { sThenInts_Pair(Pair(a: v[0], b: v[1]), v[2], v[3], v[4]) }
@_cdecl("e_intsThenS_Pair") public func e_intsThenS_Pair(_ v: UnsafePointer<Int>) -> Int { intsThenS_Pair(v[0], v[1], Pair(a: v[2], b: v[3])) }
@_cdecl("e_make_Pair") public func e_make_Pair(_ v: UnsafePointer<Int>) -> Int { let s = make_Pair(v[0], v[1]); var h = 1011; h = h &+ s.a &* 3; h = h &+ s.b &* 5; return h }
@_cdecl("e_sThenInts_Tri") public func e_sThenInts_Tri(_ v: UnsafePointer<Int>) -> Int { sThenInts_Tri(Tri(a: v[0], b: UInt(bitPattern: v[1]), c: v[2]), v[3], v[4]) }
@_cdecl("e_intsThenS_Tri") public func e_intsThenS_Tri(_ v: UnsafePointer<Int>) -> Int { intsThenS_Tri(v[0], v[1], v[2], Tri(a: v[3], b: UInt(bitPattern: v[4]), c: v[5])) }
@_cdecl("e_make_Tri") public func e_make_Tri(_ v: UnsafePointer<Int>) -> Int { let s = make_Tri(v[0], v[1]); var h = 1017; h = h &+ s.a &* 3; h = h &+ Int(bitPattern: s.b) &* 5; h = h &+ s.c &* 7; return h }
@_cdecl("e_sThenInts_Quad") public func e_sThenInts_Quad(_ v: UnsafePointer<Int>) -> Int { sThenInts_Quad(Quad(a: v[0], b: v[1], c: v[2], d: v[3]), v[4], v[5], v[6]) }
@_cdecl("e_intsThenS_Quad") public func e_intsThenS_Quad(_ v: UnsafePointer<Int>) -> Int { intsThenS_Quad(v[0], v[1], Quad(a: v[2], b: v[3], c: v[4], d: v[5])) }
@_cdecl("e_make_Quad") public func e_make_Quad(_ v: UnsafePointer<Int>) -> Int { let s = make_Quad(v[0], v[1], v[2]); var h = 1023; h = h &+ s.a &* 3; h = h &+ s.b &* 5; h = h &+ s.c &* 7; h = h &+ s.d &* 11; return h }
@_cdecl("e_sThenInts_Five") public func e_sThenInts_Five(_ v: UnsafePointer<Int>) -> Int { sThenInts_Five(Five(a: v[0], b: v[1], c: v[2], d: v[3], e: v[4]), v[5], v[6]) }
@_cdecl("e_intsThenS_Five") public func e_intsThenS_Five(_ v: UnsafePointer<Int>) -> Int { intsThenS_Five(v[0], v[1], v[2], Five(a: v[3], b: v[4], c: v[5], d: v[6], e: v[7])) }
@_cdecl("e_make_Five") public func e_make_Five(_ v: UnsafePointer<Int>) -> Int { let s = make_Five(v[0], v[1]); var h = 1029; h = h &+ s.a &* 3; h = h &+ s.b &* 5; h = h &+ s.c &* 7; h = h &+ s.d &* 11; h = h &+ s.e &* 13; return h }
@_cdecl("e_sThenInts_Six") public func e_sThenInts_Six(_ v: UnsafePointer<Int>) -> Int { sThenInts_Six(Six(a: v[0], b: Int32(truncatingIfNeeded: v[1]), c: v[2], d: Int16(truncatingIfNeeded: v[3]), e: v[4], f: Int8(truncatingIfNeeded: v[5])), v[6], v[7], (v[0] ^ 23138)) }
@_cdecl("e_intsThenS_Six") public func e_intsThenS_Six(_ v: UnsafePointer<Int>) -> Int { intsThenS_Six(v[0], v[1], Six(a: v[2], b: Int32(truncatingIfNeeded: v[3]), c: v[4], d: Int16(truncatingIfNeeded: v[5]), e: v[6], f: Int8(truncatingIfNeeded: v[7]))) }
@_cdecl("e_make_Six") public func e_make_Six(_ v: UnsafePointer<Int>) -> Int { let s = make_Six(v[0], v[1], v[2]); var h = 1035; h = h &+ s.a &* 3; h = h &+ Int(s.b) &* 5; h = h &+ s.c &* 7; h = h &+ Int(s.d) &* 11; h = h &+ s.e &* 13; h = h &+ Int(s.f) &* 17; return h }
@_cdecl("e_sThenInts_Packed") public func e_sThenInts_Packed(_ v: UnsafePointer<Int>) -> Int { sThenInts_Packed(Packed(a: Int8(truncatingIfNeeded: v[0]), b: Int16(truncatingIfNeeded: v[1]), c: Int32(truncatingIfNeeded: v[2])), v[3], v[4]) }
@_cdecl("e_intsThenS_Packed") public func e_intsThenS_Packed(_ v: UnsafePointer<Int>) -> Int { intsThenS_Packed(v[0], v[1], v[2], Packed(a: Int8(truncatingIfNeeded: v[3]), b: Int16(truncatingIfNeeded: v[4]), c: Int32(truncatingIfNeeded: v[5]))) }
@_cdecl("e_make_Packed") public func e_make_Packed(_ v: UnsafePointer<Int>) -> Int { let s = make_Packed(v[0], v[1]); var h = 1041; h = h &+ Int(s.a) &* 3; h = h &+ Int(s.b) &* 5; h = h &+ Int(s.c) &* 7; return h }
@_cdecl("e_sThenInts_PackedU") public func e_sThenInts_PackedU(_ v: UnsafePointer<Int>) -> Int { sThenInts_PackedU(PackedU(a: ((v[0]) & 1) != 0, b: UInt8(truncatingIfNeeded: v[1]), c: UInt16(truncatingIfNeeded: v[2]), d: UInt32(truncatingIfNeeded: v[3])), v[4], v[5], v[6]) }
@_cdecl("e_intsThenS_PackedU") public func e_intsThenS_PackedU(_ v: UnsafePointer<Int>) -> Int { intsThenS_PackedU(v[0], v[1], PackedU(a: ((v[2]) & 1) != 0, b: UInt8(truncatingIfNeeded: v[3]), c: UInt16(truncatingIfNeeded: v[4]), d: UInt32(truncatingIfNeeded: v[5]))) }
@_cdecl("e_make_PackedU") public func e_make_PackedU(_ v: UnsafePointer<Int>) -> Int { let s = make_PackedU(v[0], v[1], v[2]); var h = 1047; h = h &+ (s.a ? 1 : 0) &* 3; h = h &+ Int(s.b) &* 5; h = h &+ Int(s.c) &* 7; h = h &+ Int(s.d) &* 11; return h }
@_cdecl("e_sThenInts_Straddle") public func e_sThenInts_Straddle(_ v: UnsafePointer<Int>) -> Int { sThenInts_Straddle(Straddle(a: Int8(truncatingIfNeeded: v[0]), b: v[1], c: Int8(truncatingIfNeeded: v[2])), v[3], v[4]) }
@_cdecl("e_intsThenS_Straddle") public func e_intsThenS_Straddle(_ v: UnsafePointer<Int>) -> Int { intsThenS_Straddle(v[0], v[1], v[2], Straddle(a: Int8(truncatingIfNeeded: v[3]), b: v[4], c: Int8(truncatingIfNeeded: v[5]))) }
@_cdecl("e_make_Straddle") public func e_make_Straddle(_ v: UnsafePointer<Int>) -> Int { let s = make_Straddle(v[0], v[1]); var h = 1053; h = h &+ Int(s.a) &* 3; h = h &+ s.b &* 5; h = h &+ Int(s.c) &* 7; return h }
@_cdecl("e_sThenInts_UMix") public func e_sThenInts_UMix(_ v: UnsafePointer<Int>) -> Int { sThenInts_UMix(UMix(a: UInt8(truncatingIfNeeded: v[0]), b: UInt16(truncatingIfNeeded: v[1]), c: UInt32(truncatingIfNeeded: v[2]), d: UInt(bitPattern: v[3])), v[4], v[5], v[6]) }
@_cdecl("e_intsThenS_UMix") public func e_intsThenS_UMix(_ v: UnsafePointer<Int>) -> Int { intsThenS_UMix(v[0], v[1], UMix(a: UInt8(truncatingIfNeeded: v[2]), b: UInt16(truncatingIfNeeded: v[3]), c: UInt32(truncatingIfNeeded: v[4]), d: UInt(bitPattern: v[5]))) }
@_cdecl("e_make_UMix") public func e_make_UMix(_ v: UnsafePointer<Int>) -> Int { let s = make_UMix(v[0], v[1], v[2]); var h = 1059; h = h &+ Int(s.a) &* 3; h = h &+ Int(s.b) &* 5; h = h &+ Int(s.c) &* 7; h = h &+ Int(bitPattern: s.d) &* 11; return h }
@_cdecl("e_sThenInts_IntDouble") public func e_sThenInts_IntDouble(_ v: UnsafePointer<Int>) -> Int { sThenInts_IntDouble(IntDouble(a: v[0], b: Double(bitPattern: UInt64(bitPattern: Int64(v[1])))), v[2], v[3]) }
@_cdecl("e_intsThenS_IntDouble") public func e_intsThenS_IntDouble(_ v: UnsafePointer<Int>) -> Int { intsThenS_IntDouble(v[0], v[1], v[2], IntDouble(a: v[3], b: Double(bitPattern: UInt64(bitPattern: Int64(v[4]))))) }
@_cdecl("e_make_IntDouble") public func e_make_IntDouble(_ v: UnsafePointer<Int>) -> Int { let s = make_IntDouble(v[0], v[1]); var h = 1065; h = h &+ s.a &* 3; h = h &+ Int(bitPattern: UInt(s.b.bitPattern)) &* 5; return h }
@_cdecl("e_sThenInts_DoubleInt") public func e_sThenInts_DoubleInt(_ v: UnsafePointer<Int>) -> Int { sThenInts_DoubleInt(DoubleInt(a: Double(bitPattern: UInt64(bitPattern: Int64(v[0]))), b: v[1]), v[2], v[3], v[4]) }
@_cdecl("e_intsThenS_DoubleInt") public func e_intsThenS_DoubleInt(_ v: UnsafePointer<Int>) -> Int { intsThenS_DoubleInt(v[0], v[1], DoubleInt(a: Double(bitPattern: UInt64(bitPattern: Int64(v[2]))), b: v[3])) }
@_cdecl("e_make_DoubleInt") public func e_make_DoubleInt(_ v: UnsafePointer<Int>) -> Int { let s = make_DoubleInt(v[0], v[1]); var h = 1071; h = h &+ Int(bitPattern: UInt(s.a.bitPattern)) &* 3; h = h &+ s.b &* 5; return h }
@_cdecl("e_sThenInts_FloatMid") public func e_sThenInts_FloatMid(_ v: UnsafePointer<Int>) -> Int { sThenInts_FloatMid(FloatMid(a: Int32(truncatingIfNeeded: v[0]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1])), c: Int32(truncatingIfNeeded: v[2])), v[3], v[4]) }
@_cdecl("e_intsThenS_FloatMid") public func e_intsThenS_FloatMid(_ v: UnsafePointer<Int>) -> Int { intsThenS_FloatMid(v[0], v[1], v[2], FloatMid(a: Int32(truncatingIfNeeded: v[3]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[4])), c: Int32(truncatingIfNeeded: v[5]))) }
@_cdecl("e_make_FloatMid") public func e_make_FloatMid(_ v: UnsafePointer<Int>) -> Int { let s = make_FloatMid(v[0], v[1]); var h = 1077; h = h &+ Int(s.a) &* 3; h = h &+ Int(s.b.bitPattern) &* 5; h = h &+ Int(s.c) &* 7; return h }
@_cdecl("e_sThenInts_HalfMid") public func e_sThenInts_HalfMid(_ v: UnsafePointer<Int>) -> Int { sThenInts_HalfMid(HalfMid(a: Int16(truncatingIfNeeded: v[0]), b: Float16(bitPattern: UInt16(truncatingIfNeeded: v[1])), c: Int16(truncatingIfNeeded: v[2]), d: Int16(truncatingIfNeeded: v[3])), v[4], v[5], v[6]) }
@_cdecl("e_intsThenS_HalfMid") public func e_intsThenS_HalfMid(_ v: UnsafePointer<Int>) -> Int { intsThenS_HalfMid(v[0], v[1], HalfMid(a: Int16(truncatingIfNeeded: v[2]), b: Float16(bitPattern: UInt16(truncatingIfNeeded: v[3])), c: Int16(truncatingIfNeeded: v[4]), d: Int16(truncatingIfNeeded: v[5]))) }
@_cdecl("e_make_HalfMid") public func e_make_HalfMid(_ v: UnsafePointer<Int>) -> Int { let s = make_HalfMid(v[0], v[1], v[2]); var h = 1083; h = h &+ Int(s.a) &* 3; h = h &+ Int(s.b.bitPattern) &* 5; h = h &+ Int(s.c) &* 7; h = h &+ Int(s.d) &* 11; return h }
@_cdecl("e_sThenInts_MixFour") public func e_sThenInts_MixFour(_ v: UnsafePointer<Int>) -> Int { sThenInts_MixFour(MixFour(a: Int32(truncatingIfNeeded: v[0]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1])), c: Double(bitPattern: UInt64(bitPattern: Int64(v[2]))), d: v[3]), v[4], v[5]) }
@_cdecl("e_intsThenS_MixFour") public func e_intsThenS_MixFour(_ v: UnsafePointer<Int>) -> Int { intsThenS_MixFour(v[0], v[1], v[2], MixFour(a: Int32(truncatingIfNeeded: v[3]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[4])), c: Double(bitPattern: UInt64(bitPattern: Int64(v[5]))), d: v[6])) }
@_cdecl("e_make_MixFour") public func e_make_MixFour(_ v: UnsafePointer<Int>) -> Int { let s = make_MixFour(v[0], v[1]); var h = 1089; h = h &+ Int(s.a) &* 3; h = h &+ Int(s.b.bitPattern) &* 5; h = h &+ Int(bitPattern: UInt(s.c.bitPattern)) &* 7; h = h &+ s.d &* 11; return h }
@_cdecl("e_sThenInts_FourD") public func e_sThenInts_FourD(_ v: UnsafePointer<Int>) -> Int { sThenInts_FourD(FourD(a: Double(bitPattern: UInt64(bitPattern: Int64(v[0]))), b: Double(bitPattern: UInt64(bitPattern: Int64(v[1]))), c: Double(bitPattern: UInt64(bitPattern: Int64(v[2]))), d: Double(bitPattern: UInt64(bitPattern: Int64(v[3])))), v[4], v[5], v[6]) }
@_cdecl("e_intsThenS_FourD") public func e_intsThenS_FourD(_ v: UnsafePointer<Int>) -> Int { intsThenS_FourD(v[0], v[1], FourD(a: Double(bitPattern: UInt64(bitPattern: Int64(v[2]))), b: Double(bitPattern: UInt64(bitPattern: Int64(v[3]))), c: Double(bitPattern: UInt64(bitPattern: Int64(v[4]))), d: Double(bitPattern: UInt64(bitPattern: Int64(v[5]))))) }
@_cdecl("e_make_FourD") public func e_make_FourD(_ v: UnsafePointer<Int>) -> Int { let s = make_FourD(v[0], v[1], v[2]); var h = 1095; h = h &+ Int(bitPattern: UInt(s.a.bitPattern)) &* 3; h = h &+ Int(bitPattern: UInt(s.b.bitPattern)) &* 5; h = h &+ Int(bitPattern: UInt(s.c.bitPattern)) &* 7; h = h &+ Int(bitPattern: UInt(s.d.bitPattern)) &* 11; return h }
@_cdecl("e_sThenInts_TwoF") public func e_sThenInts_TwoF(_ v: UnsafePointer<Int>) -> Int { sThenInts_TwoF(TwoF(a: Float(bitPattern: UInt32(truncatingIfNeeded: v[0])), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1]))), v[2], v[3]) }
@_cdecl("e_intsThenS_TwoF") public func e_intsThenS_TwoF(_ v: UnsafePointer<Int>) -> Int { intsThenS_TwoF(v[0], v[1], v[2], TwoF(a: Float(bitPattern: UInt32(truncatingIfNeeded: v[3])), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[4])))) }
@_cdecl("e_make_TwoF") public func e_make_TwoF(_ v: UnsafePointer<Int>) -> Int { let s = make_TwoF(v[0], v[1]); var h = 1101; h = h &+ Int(s.a.bitPattern) &* 3; h = h &+ Int(s.b.bitPattern) &* 5; return h }
@_cdecl("e_sThenInts_FiveF") public func e_sThenInts_FiveF(_ v: UnsafePointer<Int>) -> Int { sThenInts_FiveF(FiveF(a: Float(bitPattern: UInt32(truncatingIfNeeded: v[0])), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1])), c: Float(bitPattern: UInt32(truncatingIfNeeded: v[2])), d: Float(bitPattern: UInt32(truncatingIfNeeded: v[3])), e: Float(bitPattern: UInt32(truncatingIfNeeded: v[4]))), v[5], v[6], v[7]) }
@_cdecl("e_intsThenS_FiveF") public func e_intsThenS_FiveF(_ v: UnsafePointer<Int>) -> Int { intsThenS_FiveF(v[0], v[1], FiveF(a: Float(bitPattern: UInt32(truncatingIfNeeded: v[2])), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[3])), c: Float(bitPattern: UInt32(truncatingIfNeeded: v[4])), d: Float(bitPattern: UInt32(truncatingIfNeeded: v[5])), e: Float(bitPattern: UInt32(truncatingIfNeeded: v[6])))) }
@_cdecl("e_make_FiveF") public func e_make_FiveF(_ v: UnsafePointer<Int>) -> Int { let s = make_FiveF(v[0], v[1], v[2]); var h = 1107; h = h &+ Int(s.a.bitPattern) &* 3; h = h &+ Int(s.b.bitPattern) &* 5; h = h &+ Int(s.c.bitPattern) &* 7; h = h &+ Int(s.d.bitPattern) &* 11; h = h &+ Int(s.e.bitPattern) &* 13; return h }
@_cdecl("e_sThenInts_PtrRef") public func e_sThenInts_PtrRef(_ v: UnsafePointer<Int>) -> Int { sThenInts_PtrRef(PtrRef(p: UnsafeRawPointer(bitPattern: v[0]), r: Box(v[1]), f: ((v[2]) & 1) != 0), v[3], v[4]) }
@_cdecl("e_intsThenS_PtrRef") public func e_intsThenS_PtrRef(_ v: UnsafePointer<Int>) -> Int { intsThenS_PtrRef(v[0], v[1], v[2], PtrRef(p: UnsafeRawPointer(bitPattern: v[3]), r: Box(v[4]), f: ((v[5]) & 1) != 0)) }
@_cdecl("e_make_PtrRef") public func e_make_PtrRef(_ v: UnsafePointer<Int>) -> Int { let s = make_PtrRef(v[0], v[1]); var h = 1113; h = h &+ Int(bitPattern: s.p) &* 3; h = h &+ s.r.v &* 5; h = h &+ (s.f ? 1 : 0) &* 7; return h }
@_cdecl("e_sThenInts_Opts") public func e_sThenInts_Opts(_ v: UnsafePointer<Int>) -> Int { sThenInts_Opts(Opts(a: (((v[0]) & 1) == 0 ? nil : Int32(truncatingIfNeeded: (v[0]) >> 1)), b: (((v[1]) & 1) == 0 ? nil : ((v[1]) >> 1))), v[2], v[3], v[4]) }
@_cdecl("e_intsThenS_Opts") public func e_intsThenS_Opts(_ v: UnsafePointer<Int>) -> Int { intsThenS_Opts(v[0], v[1], Opts(a: (((v[2]) & 1) == 0 ? nil : Int32(truncatingIfNeeded: (v[2]) >> 1)), b: (((v[3]) & 1) == 0 ? nil : ((v[3]) >> 1)))) }
@_cdecl("e_make_Opts") public func e_make_Opts(_ v: UnsafePointer<Int>) -> Int { let s = make_Opts(v[0], v[1]); var h = 1119; if let t = s.a { h = h &+ Int(t) &* 3 } else { h = h &+ 322 }; if let t = s.b { h = h &+ t &* 5 } else { h = h &+ 536 }; return h }
@_cdecl("e_sThenInts_OptD") public func e_sThenInts_OptD(_ v: UnsafePointer<Int>) -> Int { sThenInts_OptD(OptD(a: (((v[0]) & 1) == 0 ? nil : Double(bitPattern: UInt64(bitPattern: Int64((v[0]) >> 1)))), b: Int8(truncatingIfNeeded: v[1])), v[2], v[3]) }
@_cdecl("e_intsThenS_OptD") public func e_intsThenS_OptD(_ v: UnsafePointer<Int>) -> Int { intsThenS_OptD(v[0], v[1], v[2], OptD(a: (((v[3]) & 1) == 0 ? nil : Double(bitPattern: UInt64(bitPattern: Int64((v[3]) >> 1)))), b: Int8(truncatingIfNeeded: v[4]))) }
@_cdecl("e_make_OptD") public func e_make_OptD(_ v: UnsafePointer<Int>) -> Int { let s = make_OptD(v[0], v[1]); var h = 1125; if let t = s.a { h = h &+ Int(bitPattern: UInt(t.bitPattern)) &* 3 } else { h = h &+ 322 }; h = h &+ Int(s.b) &* 5; return h }
@_cdecl("e_sThenInts_Empty") public func e_sThenInts_Empty(_ v: UnsafePointer<Int>) -> Int { sThenInts_Empty(Empty(), v[0], v[1], v[2]) }
@_cdecl("e_intsThenS_Empty") public func e_intsThenS_Empty(_ v: UnsafePointer<Int>) -> Int { intsThenS_Empty(v[0], v[1], Empty()) }
@_cdecl("e_sThenInts_Nested") public func e_sThenInts_Nested(_ v: UnsafePointer<Int>) -> Int { sThenInts_Nested(Nested(p: Pair(a: v[0], b: v[1]), k: Int32(truncatingIfNeeded: v[2]), q: Packed(a: Int8(truncatingIfNeeded: v[3]), b: Int16(truncatingIfNeeded: v[4]), c: Int32(truncatingIfNeeded: v[5]))), v[6], v[7]) }
@_cdecl("e_intsThenS_Nested") public func e_intsThenS_Nested(_ v: UnsafePointer<Int>) -> Int { intsThenS_Nested(v[0], v[1], v[2], Nested(p: Pair(a: v[3], b: v[4]), k: Int32(truncatingIfNeeded: v[5]), q: Packed(a: Int8(truncatingIfNeeded: v[6]), b: Int16(truncatingIfNeeded: v[7]), c: Int32(truncatingIfNeeded: (v[0] ^ 23138))))) }
@_cdecl("e_make_Nested") public func e_make_Nested(_ v: UnsafePointer<Int>) -> Int { let s = make_Nested(v[0], v[1]); var h = 1135; h = h &+ s.p.a &* 3; h = h &+ s.p.b &* 5; h = h &+ Int(s.k) &* 7; h = h &+ Int(s.q.a) &* 11; h = h &+ Int(s.q.b) &* 13; h = h &+ Int(s.q.c) &* 17; return h }
@_cdecl("e_sThenInts_WithTuple") public func e_sThenInts_WithTuple(_ v: UnsafePointer<Int>) -> Int { sThenInts_WithTuple(WithTuple(t: (Int16(truncatingIfNeeded: v[0]), v[1]), u: UInt8(truncatingIfNeeded: v[2])), v[3], v[4], v[5]) }
@_cdecl("e_intsThenS_WithTuple") public func e_intsThenS_WithTuple(_ v: UnsafePointer<Int>) -> Int { intsThenS_WithTuple(v[0], v[1], WithTuple(t: (Int16(truncatingIfNeeded: v[2]), v[3]), u: UInt8(truncatingIfNeeded: v[4]))) }
@_cdecl("e_make_WithTuple") public func e_make_WithTuple(_ v: UnsafePointer<Int>) -> Int { let s = make_WithTuple(v[0], v[1], v[2]); var h = 1141; h = h &+ Int(s.t.0) &* 3; h = h &+ s.t.1 &* 5; h = h &+ Int(s.u) &* 7; return h }
@_cdecl("e_sThenInts_Hollow") public func e_sThenInts_Hollow(_ v: UnsafePointer<Int>) -> Int { sThenInts_Hollow(Hollow(e: Empty(), a: v[0], f: Empty(), b: Int32(truncatingIfNeeded: v[1])), v[2], v[3]) }
@_cdecl("e_intsThenS_Hollow") public func e_intsThenS_Hollow(_ v: UnsafePointer<Int>) -> Int { intsThenS_Hollow(v[0], v[1], v[2], Hollow(e: Empty(), a: v[3], f: Empty(), b: Int32(truncatingIfNeeded: v[4]))) }
@_cdecl("e_make_Hollow") public func e_make_Hollow(_ v: UnsafePointer<Int>) -> Int { let s = make_Hollow(v[0], v[1]); var h = 1147; h = h &+ s.a &* 3; h = h &+ Int(s.b) &* 5; return h }
@_cdecl("e_sThenInts_Tup3") public func e_sThenInts_Tup3(_ v: UnsafePointer<Int>) -> Int { sThenInts_Tup3((Int8(truncatingIfNeeded: v[0]), v[1], Int8(truncatingIfNeeded: v[2])), v[3], v[4], v[5]) }
@_cdecl("e_intsThenS_Tup3") public func e_intsThenS_Tup3(_ v: UnsafePointer<Int>) -> Int { intsThenS_Tup3(v[0], v[1], (Int8(truncatingIfNeeded: v[2]), v[3], Int8(truncatingIfNeeded: v[4]))) }
@_cdecl("e_two_Pair_Wrap1") public func e_two_Pair_Wrap1(_ v: UnsafePointer<Int>) -> Int { two_Pair_Wrap1(Pair(a: v[0], b: v[1]), v[2], Wrap1(a: v[3]), v[4]) }
@_cdecl("e_two_Packed_IntDouble") public func e_two_Packed_IntDouble(_ v: UnsafePointer<Int>) -> Int { two_Packed_IntDouble(Packed(a: Int8(truncatingIfNeeded: v[0]), b: Int16(truncatingIfNeeded: v[1]), c: Int32(truncatingIfNeeded: v[2])), v[3], IntDouble(a: v[4], b: Double(bitPattern: UInt64(bitPattern: Int64(v[5])))), v[6]) }
@_cdecl("e_two_FloatMid_Tri") public func e_two_FloatMid_Tri(_ v: UnsafePointer<Int>) -> Int { two_FloatMid_Tri(FloatMid(a: Int32(truncatingIfNeeded: v[0]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1])), c: Int32(truncatingIfNeeded: v[2])), v[3], Tri(a: v[4], b: UInt(bitPattern: v[5]), c: v[6]), v[7]) }
@_cdecl("e_two_Quad_Pair") public func e_two_Quad_Pair(_ v: UnsafePointer<Int>) -> Int { two_Quad_Pair(Quad(a: v[0], b: v[1], c: v[2], d: v[3]), v[4], Pair(a: v[5], b: v[6]), v[7]) }
@_cdecl("e_two_Five_Packed") public func e_two_Five_Packed(_ v: UnsafePointer<Int>) -> Int { two_Five_Packed(Five(a: v[0], b: v[1], c: v[2], d: v[3], e: v[4]), v[5], Packed(a: Int8(truncatingIfNeeded: v[6]), b: Int16(truncatingIfNeeded: v[7]), c: Int32(truncatingIfNeeded: (v[0] ^ 23138))), (v[1] ^ 23139)) }
@_cdecl("e_two_TwoF_FourD") public func e_two_TwoF_FourD(_ v: UnsafePointer<Int>) -> Int { two_TwoF_FourD(TwoF(a: Float(bitPattern: UInt32(truncatingIfNeeded: v[0])), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1]))), v[2], FourD(a: Double(bitPattern: UInt64(bitPattern: Int64(v[3]))), b: Double(bitPattern: UInt64(bitPattern: Int64(v[4]))), c: Double(bitPattern: UInt64(bitPattern: Int64(v[5]))), d: Double(bitPattern: UInt64(bitPattern: Int64(v[6])))), v[7]) }
@_cdecl("e_two_HalfMid_Straddle") public func e_two_HalfMid_Straddle(_ v: UnsafePointer<Int>) -> Int { two_HalfMid_Straddle(HalfMid(a: Int16(truncatingIfNeeded: v[0]), b: Float16(bitPattern: UInt16(truncatingIfNeeded: v[1])), c: Int16(truncatingIfNeeded: v[2]), d: Int16(truncatingIfNeeded: v[3])), v[4], Straddle(a: Int8(truncatingIfNeeded: v[5]), b: v[6], c: Int8(truncatingIfNeeded: v[7])), (v[0] ^ 23138)) }
@_cdecl("e_two_MixFour_MixFour") public func e_two_MixFour_MixFour(_ v: UnsafePointer<Int>) -> Int { two_MixFour_MixFour(MixFour(a: Int32(truncatingIfNeeded: v[0]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1])), c: Double(bitPattern: UInt64(bitPattern: Int64(v[2]))), d: v[3]), v[4], MixFour(a: Int32(truncatingIfNeeded: v[5]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[6])), c: Double(bitPattern: UInt64(bitPattern: Int64(v[7]))), d: (v[0] ^ 23138)), (v[1] ^ 23139)) }
@_cdecl("e_two_Opts_PackedU") public func e_two_Opts_PackedU(_ v: UnsafePointer<Int>) -> Int { two_Opts_PackedU(Opts(a: (((v[0]) & 1) == 0 ? nil : Int32(truncatingIfNeeded: (v[0]) >> 1)), b: (((v[1]) & 1) == 0 ? nil : ((v[1]) >> 1))), v[2], PackedU(a: ((v[3]) & 1) != 0, b: UInt8(truncatingIfNeeded: v[4]), c: UInt16(truncatingIfNeeded: v[5]), d: UInt32(truncatingIfNeeded: v[6])), v[7]) }
@_cdecl("e_two_Empty_Nested") public func e_two_Empty_Nested(_ v: UnsafePointer<Int>) -> Int { two_Empty_Nested(Empty(), v[0], Nested(p: Pair(a: v[1], b: v[2]), k: Int32(truncatingIfNeeded: v[3]), q: Packed(a: Int8(truncatingIfNeeded: v[4]), b: Int16(truncatingIfNeeded: v[5]), c: Int32(truncatingIfNeeded: v[6]))), v[7]) }
@_cdecl("e_two_Quad_Quad") public func e_two_Quad_Quad(_ v: UnsafePointer<Int>) -> Int { two_Quad_Quad(Quad(a: v[0], b: v[1], c: v[2], d: v[3]), v[4], Quad(a: v[5], b: v[6], c: v[7], d: (v[0] ^ 23138)), (v[1] ^ 23139)) }
@_cdecl("e_Pair_borrowHash") public func e_Pair_borrowHash(_ v: UnsafePointer<Int>) -> Int { let s = Pair(a: v[0], b: v[1]); return s.borrowHash(v[2], v[3]) }
@_cdecl("e_Pair_consumeHash") public func e_Pair_consumeHash(_ v: UnsafePointer<Int>) -> Int { let s = Pair(a: v[0], b: v[1]); return s.consumeHash(v[2]) }
@_cdecl("e_Pair_mutateHash") public func e_Pair_mutateHash(_ v: UnsafePointer<Int>) -> Int { var s = Pair(a: v[0], b: v[1]); let r = s.mutateHash(v[2], v[3]); var g = r &* 1000003; g = g &+ s.a &* 3; g = g &+ s.b &* 5; return g }
@_cdecl("e_Quad_borrowHash") public func e_Quad_borrowHash(_ v: UnsafePointer<Int>) -> Int { let s = Quad(a: v[0], b: v[1], c: v[2], d: v[3]); return s.borrowHash(v[4], v[5]) }
@_cdecl("e_Quad_consumeHash") public func e_Quad_consumeHash(_ v: UnsafePointer<Int>) -> Int { let s = Quad(a: v[0], b: v[1], c: v[2], d: v[3]); return s.consumeHash(v[4]) }
@_cdecl("e_Quad_mutateHash") public func e_Quad_mutateHash(_ v: UnsafePointer<Int>) -> Int { var s = Quad(a: v[0], b: v[1], c: v[2], d: v[3]); let r = s.mutateHash(v[4], v[5]); var g = r &* 1000003; g = g &+ s.a &* 3; g = g &+ s.b &* 5; g = g &+ s.c &* 7; g = g &+ s.d &* 11; return g }
@_cdecl("e_Five_borrowHash") public func e_Five_borrowHash(_ v: UnsafePointer<Int>) -> Int { let s = Five(a: v[0], b: v[1], c: v[2], d: v[3], e: v[4]); return s.borrowHash(v[5], v[6]) }
@_cdecl("e_Five_consumeHash") public func e_Five_consumeHash(_ v: UnsafePointer<Int>) -> Int { let s = Five(a: v[0], b: v[1], c: v[2], d: v[3], e: v[4]); return s.consumeHash(v[5]) }
@_cdecl("e_Five_mutateHash") public func e_Five_mutateHash(_ v: UnsafePointer<Int>) -> Int { var s = Five(a: v[0], b: v[1], c: v[2], d: v[3], e: v[4]); let r = s.mutateHash(v[5], v[6]); var g = r &* 1000003; g = g &+ s.a &* 3; g = g &+ s.b &* 5; g = g &+ s.c &* 7; g = g &+ s.d &* 11; g = g &+ s.e &* 13; return g }
@_cdecl("e_Packed_borrowHash") public func e_Packed_borrowHash(_ v: UnsafePointer<Int>) -> Int { let s = Packed(a: Int8(truncatingIfNeeded: v[0]), b: Int16(truncatingIfNeeded: v[1]), c: Int32(truncatingIfNeeded: v[2])); return s.borrowHash(v[3], v[4]) }
@_cdecl("e_Packed_consumeHash") public func e_Packed_consumeHash(_ v: UnsafePointer<Int>) -> Int { let s = Packed(a: Int8(truncatingIfNeeded: v[0]), b: Int16(truncatingIfNeeded: v[1]), c: Int32(truncatingIfNeeded: v[2])); return s.consumeHash(v[3]) }
@_cdecl("e_Packed_mutateHash") public func e_Packed_mutateHash(_ v: UnsafePointer<Int>) -> Int { var s = Packed(a: Int8(truncatingIfNeeded: v[0]), b: Int16(truncatingIfNeeded: v[1]), c: Int32(truncatingIfNeeded: v[2])); let r = s.mutateHash(v[3], v[4]); var g = r &* 1000003; g = g &+ Int(s.a) &* 3; g = g &+ Int(s.b) &* 5; g = g &+ Int(s.c) &* 7; return g }
@_cdecl("e_FloatMid_borrowHash") public func e_FloatMid_borrowHash(_ v: UnsafePointer<Int>) -> Int { let s = FloatMid(a: Int32(truncatingIfNeeded: v[0]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1])), c: Int32(truncatingIfNeeded: v[2])); return s.borrowHash(v[3], v[4]) }
@_cdecl("e_FloatMid_consumeHash") public func e_FloatMid_consumeHash(_ v: UnsafePointer<Int>) -> Int { let s = FloatMid(a: Int32(truncatingIfNeeded: v[0]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1])), c: Int32(truncatingIfNeeded: v[2])); return s.consumeHash(v[3]) }
@_cdecl("e_FloatMid_mutateHash") public func e_FloatMid_mutateHash(_ v: UnsafePointer<Int>) -> Int { var s = FloatMid(a: Int32(truncatingIfNeeded: v[0]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1])), c: Int32(truncatingIfNeeded: v[2])); let r = s.mutateHash(v[3], v[4]); var g = r &* 1000003; g = g &+ Int(s.a) &* 3; g = g &+ Int(s.b.bitPattern) &* 5; g = g &+ Int(s.c) &* 7; return g }
@_cdecl("e_HalfMid_borrowHash") public func e_HalfMid_borrowHash(_ v: UnsafePointer<Int>) -> Int { let s = HalfMid(a: Int16(truncatingIfNeeded: v[0]), b: Float16(bitPattern: UInt16(truncatingIfNeeded: v[1])), c: Int16(truncatingIfNeeded: v[2]), d: Int16(truncatingIfNeeded: v[3])); return s.borrowHash(v[4], v[5]) }
@_cdecl("e_HalfMid_consumeHash") public func e_HalfMid_consumeHash(_ v: UnsafePointer<Int>) -> Int { let s = HalfMid(a: Int16(truncatingIfNeeded: v[0]), b: Float16(bitPattern: UInt16(truncatingIfNeeded: v[1])), c: Int16(truncatingIfNeeded: v[2]), d: Int16(truncatingIfNeeded: v[3])); return s.consumeHash(v[4]) }
@_cdecl("e_HalfMid_mutateHash") public func e_HalfMid_mutateHash(_ v: UnsafePointer<Int>) -> Int { var s = HalfMid(a: Int16(truncatingIfNeeded: v[0]), b: Float16(bitPattern: UInt16(truncatingIfNeeded: v[1])), c: Int16(truncatingIfNeeded: v[2]), d: Int16(truncatingIfNeeded: v[3])); let r = s.mutateHash(v[4], v[5]); var g = r &* 1000003; g = g &+ Int(s.a) &* 3; g = g &+ Int(s.b.bitPattern) &* 5; g = g &+ Int(s.c) &* 7; g = g &+ Int(s.d) &* 11; return g }
@_cdecl("e_MixFour_borrowHash") public func e_MixFour_borrowHash(_ v: UnsafePointer<Int>) -> Int { let s = MixFour(a: Int32(truncatingIfNeeded: v[0]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1])), c: Double(bitPattern: UInt64(bitPattern: Int64(v[2]))), d: v[3]); return s.borrowHash(v[4], v[5]) }
@_cdecl("e_MixFour_consumeHash") public func e_MixFour_consumeHash(_ v: UnsafePointer<Int>) -> Int { let s = MixFour(a: Int32(truncatingIfNeeded: v[0]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1])), c: Double(bitPattern: UInt64(bitPattern: Int64(v[2]))), d: v[3]); return s.consumeHash(v[4]) }
@_cdecl("e_MixFour_mutateHash") public func e_MixFour_mutateHash(_ v: UnsafePointer<Int>) -> Int { var s = MixFour(a: Int32(truncatingIfNeeded: v[0]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1])), c: Double(bitPattern: UInt64(bitPattern: Int64(v[2]))), d: v[3]); let r = s.mutateHash(v[4], v[5]); var g = r &* 1000003; g = g &+ Int(s.a) &* 3; g = g &+ Int(s.b.bitPattern) &* 5; g = g &+ Int(bitPattern: UInt(s.c.bitPattern)) &* 7; g = g &+ s.d &* 11; return g }
@_cdecl("e_Straddle_borrowHash") public func e_Straddle_borrowHash(_ v: UnsafePointer<Int>) -> Int { let s = Straddle(a: Int8(truncatingIfNeeded: v[0]), b: v[1], c: Int8(truncatingIfNeeded: v[2])); return s.borrowHash(v[3], v[4]) }
@_cdecl("e_Straddle_consumeHash") public func e_Straddle_consumeHash(_ v: UnsafePointer<Int>) -> Int { let s = Straddle(a: Int8(truncatingIfNeeded: v[0]), b: v[1], c: Int8(truncatingIfNeeded: v[2])); return s.consumeHash(v[3]) }
@_cdecl("e_Straddle_mutateHash") public func e_Straddle_mutateHash(_ v: UnsafePointer<Int>) -> Int { var s = Straddle(a: Int8(truncatingIfNeeded: v[0]), b: v[1], c: Int8(truncatingIfNeeded: v[2])); let r = s.mutateHash(v[3], v[4]); var g = r &* 1000003; g = g &+ Int(s.a) &* 3; g = g &+ s.b &* 5; g = g &+ Int(s.c) &* 7; return g }
@_cdecl("e_Opts_borrowHash") public func e_Opts_borrowHash(_ v: UnsafePointer<Int>) -> Int { let s = Opts(a: (((v[0]) & 1) == 0 ? nil : Int32(truncatingIfNeeded: (v[0]) >> 1)), b: (((v[1]) & 1) == 0 ? nil : ((v[1]) >> 1))); return s.borrowHash(v[2], v[3]) }
@_cdecl("e_Opts_consumeHash") public func e_Opts_consumeHash(_ v: UnsafePointer<Int>) -> Int { let s = Opts(a: (((v[0]) & 1) == 0 ? nil : Int32(truncatingIfNeeded: (v[0]) >> 1)), b: (((v[1]) & 1) == 0 ? nil : ((v[1]) >> 1))); return s.consumeHash(v[2]) }
@_cdecl("e_Opts_mutateHash") public func e_Opts_mutateHash(_ v: UnsafePointer<Int>) -> Int { var s = Opts(a: (((v[0]) & 1) == 0 ? nil : Int32(truncatingIfNeeded: (v[0]) >> 1)), b: (((v[1]) & 1) == 0 ? nil : ((v[1]) >> 1))); let r = s.mutateHash(v[2], v[3]); var g = r &* 1000003; if let t = s.a { g = g &+ Int(t) &* 3 } else { g = g &+ 322 }; if let t = s.b { g = g &+ t &* 5 } else { g = g &+ 536 }; return g }
@_cdecl("e_PtrRef_borrowHash") public func e_PtrRef_borrowHash(_ v: UnsafePointer<Int>) -> Int { let s = PtrRef(p: UnsafeRawPointer(bitPattern: v[0]), r: Box(v[1]), f: ((v[2]) & 1) != 0); return s.borrowHash(v[3], v[4]) }
@_cdecl("e_PtrRef_consumeHash") public func e_PtrRef_consumeHash(_ v: UnsafePointer<Int>) -> Int { let s = PtrRef(p: UnsafeRawPointer(bitPattern: v[0]), r: Box(v[1]), f: ((v[2]) & 1) != 0); return s.consumeHash(v[3]) }
@_cdecl("e_Wrap1_borrowHash") public func e_Wrap1_borrowHash(_ v: UnsafePointer<Int>) -> Int { let s = Wrap1(a: v[0]); return s.borrowHash(v[1], v[2]) }
@_cdecl("e_Wrap1_consumeHash") public func e_Wrap1_consumeHash(_ v: UnsafePointer<Int>) -> Int { let s = Wrap1(a: v[0]); return s.consumeHash(v[1]) }
@_cdecl("e_Wrap1_mutateHash") public func e_Wrap1_mutateHash(_ v: UnsafePointer<Int>) -> Int { var s = Wrap1(a: v[0]); let r = s.mutateHash(v[1], v[2]); var g = r &* 1000003; g = g &+ s.a &* 3; return g }
@_cdecl("e_Empty_borrowHash") public func e_Empty_borrowHash(_ v: UnsafePointer<Int>) -> Int { let s = Empty(); return s.borrowHash(v[0], v[1]) }
@_cdecl("e_Empty_consumeHash") public func e_Empty_consumeHash(_ v: UnsafePointer<Int>) -> Int { let s = Empty(); return s.consumeHash(v[0]) }
@_cdecl("e_eightThenQuad") public func e_eightThenQuad(_ v: UnsafePointer<Int>) -> Int { eightThenQuad(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], Quad(a: (v[0] ^ 23138), b: (v[1] ^ 23139), c: (v[2] ^ 23140), d: (v[3] ^ 23141))) }
@_cdecl("e_sixThenQuad") public func e_sixThenQuad(_ v: UnsafePointer<Int>) -> Int { sixThenQuad(v[0], v[1], v[2], v[3], v[4], v[5], Quad(a: v[6], b: v[7], c: (v[0] ^ 23138), d: (v[1] ^ 23139))) }
@_cdecl("e_sevenThenPair") public func e_sevenThenPair(_ v: UnsafePointer<Int>) -> Int { sevenThenPair(v[0], v[1], v[2], v[3], v[4], v[5], v[6], Pair(a: v[7], b: (v[0] ^ 23138))) }
@_cdecl("e_eightThenPacked") public func e_eightThenPacked(_ v: UnsafePointer<Int>) -> Int { eightThenPacked(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], Packed(a: Int8(truncatingIfNeeded: (v[0] ^ 23138)), b: Int16(truncatingIfNeeded: (v[1] ^ 23139)), c: Int32(truncatingIfNeeded: (v[2] ^ 23140)))) }
@_cdecl("e_eightThenWrap1") public func e_eightThenWrap1(_ v: UnsafePointer<Int>) -> Int { eightThenWrap1(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], Wrap1(a: (v[0] ^ 23138)), (v[1] ^ 23139)) }
@_cdecl("e_eightThenFive") public func e_eightThenFive(_ v: UnsafePointer<Int>) -> Int { eightThenFive(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], Five(a: (v[0] ^ 23138), b: (v[1] ^ 23139), c: (v[2] ^ 23140), d: (v[3] ^ 23141), e: (v[4] ^ 23142))) }
@_cdecl("e_sevenThenFive") public func e_sevenThenFive(_ v: UnsafePointer<Int>) -> Int { sevenThenFive(v[0], v[1], v[2], v[3], v[4], v[5], v[6], Five(a: v[7], b: (v[0] ^ 23138), c: (v[1] ^ 23139), d: (v[2] ^ 23140), e: (v[3] ^ 23141)), (v[4] ^ 23142)) }
@_cdecl("e_eightThenIntDouble") public func e_eightThenIntDouble(_ v: UnsafePointer<Int>) -> Int { eightThenIntDouble(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], IntDouble(a: (v[0] ^ 23138), b: Double(bitPattern: UInt64(bitPattern: Int64((v[1] ^ 23139)))))) }
@_cdecl("e_sevenDThenFourD") public func e_sevenDThenFourD(_ v: UnsafePointer<Int>) -> Int { sevenDThenFourD(Double(bitPattern: UInt64(bitPattern: Int64(v[0]))), Double(bitPattern: UInt64(bitPattern: Int64(v[1]))), Double(bitPattern: UInt64(bitPattern: Int64(v[2]))), Double(bitPattern: UInt64(bitPattern: Int64(v[3]))), Double(bitPattern: UInt64(bitPattern: Int64(v[4]))), Double(bitPattern: UInt64(bitPattern: Int64(v[5]))), Double(bitPattern: UInt64(bitPattern: Int64(v[6]))), FourD(a: Double(bitPattern: UInt64(bitPattern: Int64(v[7]))), b: Double(bitPattern: UInt64(bitPattern: Int64((v[0] ^ 23138)))), c: Double(bitPattern: UInt64(bitPattern: Int64((v[1] ^ 23139)))), d: Double(bitPattern: UInt64(bitPattern: Int64((v[2] ^ 23140)))))) }
@_cdecl("e_eightDThenDoubleInt") public func e_eightDThenDoubleInt(_ v: UnsafePointer<Int>) -> Int { eightDThenDoubleInt(Double(bitPattern: UInt64(bitPattern: Int64(v[0]))), Double(bitPattern: UInt64(bitPattern: Int64(v[1]))), Double(bitPattern: UInt64(bitPattern: Int64(v[2]))), Double(bitPattern: UInt64(bitPattern: Int64(v[3]))), Double(bitPattern: UInt64(bitPattern: Int64(v[4]))), Double(bitPattern: UInt64(bitPattern: Int64(v[5]))), Double(bitPattern: UInt64(bitPattern: Int64(v[6]))), Double(bitPattern: UInt64(bitPattern: Int64(v[7]))), DoubleInt(a: Double(bitPattern: UInt64(bitPattern: Int64((v[0] ^ 23138)))), b: (v[1] ^ 23139)), (v[2] ^ 23140)) }
@_cdecl("e_quadQuadInt") public func e_quadQuadInt(_ v: UnsafePointer<Int>) -> Int { quadQuadInt(Quad(a: v[0], b: v[1], c: v[2], d: v[3]), Quad(a: v[4], b: v[5], c: v[6], d: v[7]), (v[0] ^ 23138)) }
@_cdecl("e_fourDFourDDoubleInt") public func e_fourDFourDDoubleInt(_ v: UnsafePointer<Int>) -> Int { fourDFourDDoubleInt(FourD(a: Double(bitPattern: UInt64(bitPattern: Int64(v[0]))), b: Double(bitPattern: UInt64(bitPattern: Int64(v[1]))), c: Double(bitPattern: UInt64(bitPattern: Int64(v[2]))), d: Double(bitPattern: UInt64(bitPattern: Int64(v[3])))), FourD(a: Double(bitPattern: UInt64(bitPattern: Int64(v[4]))), b: Double(bitPattern: UInt64(bitPattern: Int64(v[5]))), c: Double(bitPattern: UInt64(bitPattern: Int64(v[6]))), d: Double(bitPattern: UInt64(bitPattern: Int64(v[7])))), Double(bitPattern: UInt64(bitPattern: Int64((v[0] ^ 23138)))), (v[1] ^ 23139)) }
@_cdecl("e_mixFourTwiceTail") public func e_mixFourTwiceTail(_ v: UnsafePointer<Int>) -> Int { mixFourTwiceTail(MixFour(a: Int32(truncatingIfNeeded: v[0]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[1])), c: Double(bitPattern: UInt64(bitPattern: Int64(v[2]))), d: v[3]), v[4], MixFour(a: Int32(truncatingIfNeeded: v[5]), b: Float(bitPattern: UInt32(truncatingIfNeeded: v[6])), c: Double(bitPattern: UInt64(bitPattern: Int64(v[7]))), d: (v[0] ^ 23138)), Double(bitPattern: UInt64(bitPattern: Int64((v[1] ^ 23139)))), (v[2] ^ 23140)) }
@_cdecl("e_triTriTri") public func e_triTriTri(_ v: UnsafePointer<Int>) -> Int { triTriTri(Tri(a: v[0], b: UInt(bitPattern: v[1]), c: v[2]), Tri(a: v[3], b: UInt(bitPattern: v[4]), c: v[5]), Tri(a: v[6], b: UInt(bitPattern: v[7]), c: (v[0] ^ 23138))) }
@_cdecl("e_fiveFive") public func e_fiveFive(_ v: UnsafePointer<Int>) -> Int { fiveFive(Five(a: v[0], b: v[1], c: v[2], d: v[3], e: v[4]), v[5], Five(a: v[6], b: v[7], c: (v[0] ^ 23138), d: (v[1] ^ 23139), e: (v[2] ^ 23140)), (v[3] ^ 23141)) }
@_cdecl("e_eightThenEmptyInt") public func e_eightThenEmptyInt(_ v: UnsafePointer<Int>) -> Int { eightThenEmptyInt(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], Empty(), (v[0] ^ 23138)) }
@_cdecl("e_eightThenHalfMid") public func e_eightThenHalfMid(_ v: UnsafePointer<Int>) -> Int { eightThenHalfMid(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], HalfMid(a: Int16(truncatingIfNeeded: (v[0] ^ 23138)), b: Float16(bitPattern: UInt16(truncatingIfNeeded: (v[1] ^ 23139))), c: Int16(truncatingIfNeeded: (v[2] ^ 23140)), d: Int16(truncatingIfNeeded: (v[3] ^ 23141)))) }
@_cdecl("e_controlFiveInts") public func e_controlFiveInts(_ v: UnsafePointer<Int>) -> Int { controlFiveInts(v[0], v[1], v[2], v[3], v[4]) }
@_cdecl("e_controlNineInts") public func e_controlNineInts(_ v: UnsafePointer<Int>) -> Int { controlNineInts(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], (v[0] ^ 23138)) }
@_cdecl("e_controlIntsDoubles") public func e_controlIntsDoubles(_ v: UnsafePointer<Int>) -> Int { controlIntsDoubles(v[0], Double(bitPattern: UInt64(bitPattern: Int64(v[1]))), v[2], Double(bitPattern: UInt64(bitPattern: Int64(v[3])))) }

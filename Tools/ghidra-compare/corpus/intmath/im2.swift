// Signedness/width probes.
@inline(never) public func ubitNeg(_ a: UInt) -> Bool { Int(bitPattern: a) < 0 }      // true iff top bit set
@inline(never) public func ubitLt(_ a: UInt, _ b: UInt) -> Bool { Int(bitPattern: a) < Int(bitPattern: b) } // signed compare
@inline(never) public func iUlt(_ a: Int, _ b: Int) -> Bool { UInt(bitPattern: a) < UInt(bitPattern: b) }   // unsigned compare
@inline(never) public func u32lt(_ a: UInt, _ b: UInt) -> Bool { UInt32(truncatingIfNeeded: a) < UInt32(truncatingIfNeeded: b) } // low 32 bits unsigned
@inline(never) public func i32lt(_ a: Int, _ b: Int) -> Bool { Int32(truncatingIfNeeded: a) < Int32(truncatingIfNeeded: b) }     // low 32 bits signed
@inline(never) public func ubitSel(_ a: UInt, _ b: UInt) -> UInt { Int(bitPattern: a) > Int(bitPattern: b) ? a : b }               // signed max
@inline(never) public func two(_ a: Int, _ b: Int) -> Bool { a == 3 || b > 7 }        // ccmp chain
@inline(never) public func both(_ a: Int, _ b: Int) -> Int { if a > 0 && b < 0 { return 1 }; return 2 }
@inline(never) public func bothU(_ a: UInt, _ b: UInt) -> Int { if a > 5 && b < a { return 1 }; return 2 }
@inline(never) public func i8ret(_ a: Int8, _ b: Int8) -> Int8 { a &* b }             // low 8 bits of product
@inline(never) public func i8sum(_ a: Int8, _ b: Int8) -> Int { Int(a) + Int(b) }     // sign-extended sum
@inline(never) public func u8sum(_ a: UInt8, _ b: UInt8) -> Int { Int(a) + Int(b) }
@inline(never) public func i8trap(_ a: Int8, _ b: Int8) -> Int8 { a + b }             // traps outside -128...127
@inline(never) public func u16trap(_ a: UInt16, _ b: UInt16) -> UInt16 { a + b }      // traps > 65535
@inline(never) public func i32trap(_ a: Int32, _ b: Int32) -> Int32 { a * b }
@inline(never) public func subTrapU(_ a: UInt, _ b: UInt) -> UInt { a - b }           // traps if b > a
@inline(never) public func negTrap(_ a: Int) -> Int { -a }                            // traps Int.min
@inline(never) public func shlConst(_ a: Int8) -> Int8 { a &<< 3 }
@inline(never) public func sar8(_ a: Int8) -> Int8 { a >> 2 }                         // arithmetic
@inline(never) public func shr8u(_ a: UInt8) -> UInt8 { a >> 2 }
@inline(never) public func divFull(_ hi: Int, _ lo: UInt, _ d: Int) -> Int { d.dividingFullWidth((high: hi, low: lo)).quotient }
@inline(never) public func ifNeg(_ a: Int) -> Int { if a < 0 { return 10 }; return 20 }
@inline(never) public func ifUHigh(_ a: UInt) -> Int { if a > 0x7fff_ffff_ffff_ffff { return 10 }; return 20 }
@inline(never) public func ifU32(_ a: UInt32) -> Int { if a > 0x8000_0000 { return 10 }; return 20 }
@inline(never) public func ifI32neg(_ a: Int32) -> Int { if a < -5 { return 10 }; return 20 }
@inline(never) public func ifI8(_ a: Int8) -> Int { if a < 0 { return 10 }; return 20 }
@inline(never) public func mask32(_ a: Int) -> Int { a & 0xffff_ffff }
@inline(never) public func neg32(_ a: Int32) -> Int32 { 0 &- a }
@inline(never) public func notF(_ a: UInt) -> UInt { ~a }
@inline(never) public func eor(_ a: UInt, _ b: UInt) -> UInt { a ^ ~b }
@inline(never) public func madd(_ a: Int, _ b: Int, _ c: Int) -> Int { a &* b &+ c }
@inline(never) public func msub(_ a: Int, _ b: Int, _ c: Int) -> Int { c &- a &* b }
@inline(never) public func mneg(_ a: Int, _ b: Int) -> Int { 0 &- a &* b }
@inline(never) public func lsl32(_ a: UInt32, _ n: UInt32) -> UInt32 { a &<< n }    // mask n&31
@inline(never) public func shiftBig(_ a: UInt32) -> UInt64 { UInt64(a) << 40 }
@inline(never) public func smull(_ a: Int32, _ b: Int32) -> Int { Int(a) * Int(b) }  // no trap: fits
@inline(never) public func umull(_ a: UInt32, _ b: UInt32) -> UInt { UInt(a) * UInt(b) }

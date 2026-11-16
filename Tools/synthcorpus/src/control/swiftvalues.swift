// LEVELS: O Osize Onone
// Values computed from conditions (cset, csel, csinc, cneg, csinv), where
// a Swift signature makes the renderer print the returned value or the
// argument, so a wrong sign or signedness is visible.
// An unsigned machine compare renders as a plain operator only on an
// operand proven unsigned (UInt); otherwise it must carry ᵁ.
// EXPECT structured * ugtV :: return (arg1 < arg0)
// EXPECT structured * slt32 :: < (((arg1 & 0xffffffff) << 32) >>ˢ 32))
// FORBID structured * slt32 :: ᵁ
// EXPECT structured * belowMinus5 :: return (arg0 < -5)
// EXPECT structured * isIntMin :: return (arg0 == 0x8000000000000000)
// EXPECT structured O,Osize subBorrows :: return (arg0 < arg1)
// EXPECT structured O,Osize minSink :: sink(((arg0 < arg1) ? arg0 : arg1))
// EXPECT structured O,Osize absSink :: sink(((arg0 < 0) ? -arg0 : arg0))
// EXPECT structured O,Osize pickInc :: sink(((arg0 == arg1) ? arg2 : (arg3 + 1)))
// FORBID structured * pickInc :: (arg0 != arg1) ? arg2
// pickInv: x >= 0 ? y : ~y is y ^ (x >> 63) arithmetic.
// FORBID structured * pickInv :: >>ᵁ 63
// EXPECT structured O,Osize clampSink :: sink(((arg0 < 255) ? arg0 : 255))
// FORBID structured * clampSink :: (arg0 > 255) ? arg0
// uNearMax: x > UInt.max - 5. -Onone is `mov x8, #-6; subs x8, x8, x0;
// cset lo`: 0xfffffffffffffffa <u x. On a UInt the constant is
// 0xfffffffffffffffa; `arg0 > -6` names a value no UInt holds and reads as
// always true.
// FORBID structured * uNearMax :: arg0 > -6)
// EXPECT structured Onone uNearMax :: re:0xfffffffffffffffa|\(arg0 >ᵁ -6\)
// intAsUnsigned: Int operands compared unsigned keep ᵁ.
// EXPECT structured Onone intAsUnsigned :: return (arg0 <ᵁ arg1)
// FORBID structured * intAsUnsigned :: re:arg0 < arg1\)|arg1 > arg0\)
// EXPECT structured Onone intAboveNeg16 :: return ((arg0 + 16) <ᵁ arg0)
// EXPECT structured O,Osize intAboveNeg16 :: <ᵁ arg0)
// EXPECT structured Onone u32NearMax :: return ((arg0 & 0xffffffff) > 0xfffffffa)
// fge/fne: never an inverted ordered compare.
// FORBID structured * fge :: re:arg0 < arg1|arg1 > arg0
// FORBID structured * fnle :: re:arg0 > arg1|arg1 < arg0
// EXPECT structured * bit40 :: re:bit 0x28 of x0 set|arg0 & 0x10000000000\) != 0
// FORBID structured * bit40 :: re:bit (0x27|0x29|39|41) of
// EXPECT structured * nonNeg :: re:arg0 < 0\)|arg0 >= 0\)
// FORBID structured * nonNeg :: re:arg0 (<|>=)ᵁ 0
// eachBit (-O, -Osize): `cmp w19, #1; lsr w19, w19, #1; b.ls`: the flags
// read w19 before the shift; at the branch w19 is shifted, so
// `w19 <=ᵁ 1` there is one step off (true: shifted w19 == 0).
// FORBID structured O,Osize eachBit :: re:w19 (<=ᵁ|>ᵁ) 1\)
// down2: the test reads i before each `-= 2`.
// EXPECT structured Onone down2 :: while (i > 2)
// EXPECT structured O,Osize down2 :: if (arg0 >= 3)
// FORBID structured * down2 :: re:(x19|i) (>|<=) 0\)
@inline(never) public func sink(_ x: Int) { print(x) }

// `cmp x1, x0; cset w0, lo`. TRUE: a > b, unsigned.
public func ugtV(_ a: UInt, _ b: UInt) -> Bool { a > b }
// `cmp; cset ls`. TRUE: a <= b, unsigned.
public func uleV(_ a: UInt, _ b: UInt) -> Bool { a <= b }
// `cmp; cset hs`. TRUE: a >= b, unsigned.
public func ugeV(_ a: UInt, _ b: UInt) -> Bool { a >= b }
// `cmp w0, w1; cset hi`. TRUE: a > b, unsigned 32-bit.
public func ugt32(_ a: UInt32, _ b: UInt32) -> Bool { a > b }
// `cmp; cset lt`. TRUE: a < b, signed 32-bit.
public func slt32(_ a: Int32, _ b: Int32) -> Bool { a < b }
// `cmn x0, #5; cset lt`. TRUE: x < -5, signed.
public func belowMinus5(_ x: Int) -> Bool { x < -5 }
// TRUE: x == Int.min.
public func isIntMin(_ x: Int) -> Bool { x == Int.min }
// TRUE: x == UInt32.max.
public func isU32Max(_ x: UInt32) -> Bool { x == UInt32.max }
// `cmn; cset vs`. TRUE: a + b overflows Int.
public func addOverflows(_ a: Int, _ b: Int) -> Bool { a.addingReportingOverflow(b).overflow }
// `cmn; cset hs`. TRUE: a + b carries out of UInt.
public func addCarries(_ a: UInt, _ b: UInt) -> Bool { a.addingReportingOverflow(b).overflow }
// `cmp; cset lo`. TRUE: a - b borrows (a < b unsigned).
public func subBorrows(_ a: UInt, _ b: UInt) -> Bool { a.subtractingReportingOverflow(b).overflow }

// csel lt: TRUE: sink(min(a, b)) signed.
public func minSink(_ a: Int, _ b: Int) { sink(a < b ? a : b) }
// csel lo: TRUE: sink(min(a, b)) unsigned.
public func uminSink(_ a: UInt, _ b: UInt) { sink(Int(bitPattern: a < b ? a : b)) }
// cneg mi: TRUE: sink(|x|) with wrapping negation.
public func absSink(_ x: Int) { sink(x < 0 ? 0 &- x : x) }
// csinc eq: TRUE: sink(a == b ? c : d + 1).
public func pickInc(_ a: Int, _ b: Int, _ c: Int, _ d: Int) { sink(a == b ? c : d &+ 1) }
// csinv ge: TRUE: sink(x >= 0 ? y : ~y).
public func pickInv(_ x: Int, _ y: Int) { sink(x >= 0 ? y : ~y) }
// Sign function: TRUE: sink(-1, 0 or 1) by the sign of x.
public func signSink(_ x: Int) { sink((x > 0 ? 1 : 0) - (x < 0 ? 1 : 0)) }
// Unsigned clamp: TRUE: sink(x > 255 ? 255 : x) unsigned.
public func clampSink(_ x: UInt) { sink(Int(bitPattern: x > 255 ? 255 : x)) }
// Count of true conditions. TRUE: (a < b) + (c > d unsigned) + (e == 0).
public func countFlags(_ a: Int, _ b: Int, _ c: UInt, _ d: UInt, _ e: Int) -> Int {
  (a < b ? 1 : 0) + (c > d ? 1 : 0) + (e == 0 ? 1 : 0)
}

// Float compares with NaN.
// TRUE: a >= b, false when either is NaN.
public func fge(_ a: Double, _ b: Double) -> Bool { a >= b }
// TRUE: a != b, true when either is NaN.
public func fne(_ a: Double, _ b: Double) -> Bool { a != b }
// TRUE: x is NaN.
public func fnan(_ x: Double) -> Bool { x.isNaN }
// TRUE: sink(1) iff a > 0 (false for NaN), else sink(2).
public func fpos(_ a: Double) { sink(a > 0 ? 1 : 2) }
// TRUE: sink(3) iff !(a <= b): NaN or greater.
public func fnle(_ a: Double, _ b: Double) { if !(a <= b) { sink(3) } }

// tbnz on bit 40. TRUE: sink(40) iff bit 40 of x is set.
public func bit40(_ x: UInt64) { if x & (1 << 40) != 0 { sink(40) } }
// tbz on bit 63 (sign). TRUE: sink(63) iff x >= 0.
public func nonNeg(_ x: Int) { if x >= 0 { sink(63) } }

// A loop over set bits that shifts after the compare:
// TRUE: sink(i) for each set bit i of m.
public func eachBit(_ m: UInt32) {
  var m = m, i = 0
  while m != 0 { if m & 1 != 0 { sink(i) }; m >>= 1; i += 1 }
}

// Unsigned compare against a constant near the top of the range:
// `cmn x0, #6; cset hi`. TRUE: x > UInt.max - 5, i.e. x >= 0xfffffffffffffffb.
public func uNearMax(_ x: UInt) -> Bool { x > UInt.max - 5 }
// TRUE: x >= 2^63 as UInt (the top bit).
public func uHigh(_ x: UInt) -> Bool { x >= 1 << 63 }
// Int operands compared unsigned: TRUE: a <ᵁ b; a signed `<` is wrong.
public func intAsUnsigned(_ a: Int, _ b: Int) -> Bool { UInt(bitPattern: a) < UInt(bitPattern: b) }
// Int against a negative constant compared unsigned: TRUE: a >=ᵁ 0xfffffffffffffff0.
public func intAboveNeg16(_ a: Int) -> Bool { UInt(bitPattern: a) >= UInt(bitPattern: -16) }
// TRUE: x > UInt32.max - 5 (unsigned 32-bit).
public func u32NearMax(_ x: UInt32) -> Bool { x > UInt32.max - 5 }

// A wrapping countdown by 2 whose subs writes the compared register:
// TRUE: sink(n - 2), sink(n - 4), ... while the value before each step
// is above 2 (signed); the test reads the value before the subtraction.
public func down2(_ n: Int) {
  var i = n
  while i > 2 { i &-= 2; sink(i) }
}

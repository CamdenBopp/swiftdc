// F7: branch conditions, arithmetic idioms and loops, from the Swift front end.
// Every function takes Int arguments and returns one Int. A function that
// chooses between paths returns a constant of its own for each path
// (function number * 100 + path), so the result names the path the machine
// took. Each comment names the lowering expected at -O and the true behaviour.
// The emulator sweep runs every function and holds each rendered return
// to what the machine returns.

// ---------------------------------------------------------------- comparisons
// Two variables at each width. Narrow forms extend both operands first
// (`sxtb`/`and #0xff`, `cmp w, w`), so the width and signedness are the claim.

// 01 `sxtb w8,w0; cmp w8, w1, sxtb; cset lt`: 101 iff Int8(a) < Int8(b).
@inline(never) public func s01_slt8(_ a: Int, _ b: Int) -> Int {
    return Int8(truncatingIfNeeded: a) < Int8(truncatingIfNeeded: b) ? 101 : 102
}
// 02 `and w8,w0,#0xff; cmp w8, w1, uxtb; lo`: 201 iff UInt8(a) < UInt8(b).
@inline(never) public func s02_ult8(_ a: Int, _ b: Int) -> Int {
    return UInt8(truncatingIfNeeded: a) < UInt8(truncatingIfNeeded: b) ? 201 : 202
}
// 03 `sxth; cmp; lt`: 301 iff Int16(a) < Int16(b).
@inline(never) public func s03_slt16(_ a: Int, _ b: Int) -> Int {
    return Int16(truncatingIfNeeded: a) < Int16(truncatingIfNeeded: b) ? 301 : 302
}
// 04 `uxth; cmp; ls`: 401 iff UInt16(a) <= UInt16(b).
@inline(never) public func s04_ule16(_ a: Int, _ b: Int) -> Int {
    return UInt16(truncatingIfNeeded: a) <= UInt16(truncatingIfNeeded: b) ? 401 : 402
}
// 05 `cmp w0, w1; lt`: 501 iff Int32(a) < Int32(b).
@inline(never) public func s05_slt32(_ a: Int, _ b: Int) -> Int {
    return Int32(truncatingIfNeeded: a) < Int32(truncatingIfNeeded: b) ? 501 : 502
}
// 06 `cmp w0, w1; hi`: 601 iff UInt32(a) > UInt32(b).
@inline(never) public func s06_ugt32(_ a: Int, _ b: Int) -> Int {
    return UInt32(truncatingIfNeeded: a) > UInt32(truncatingIfNeeded: b) ? 601 : 602
}
// 07 control `cmp x0, x1; lt`: 701 iff a < b.
@inline(never) public func s07_slt64(_ a: Int, _ b: Int) -> Int {
    return a < b ? 701 : 702
}
// 08 `cmp x0, x1; lo`: 801 iff UInt(a) < UInt(b).
@inline(never) public func s08_ult64(_ a: Int, _ b: Int) -> Int {
    return UInt(bitPattern: a) < UInt(bitPattern: b) ? 801 : 802
}
// 09 `cmp x0, x1; ge`: 901 iff a >= b.
@inline(never) public func s09_sge64(_ a: Int, _ b: Int) -> Int {
    return a >= b ? 901 : 902
}
// 10 `sxtb; cmp; gt`: 1001 iff Int8(a) > Int8(b).
@inline(never) public func s10_sgt8(_ a: Int, _ b: Int) -> Int {
    return Int8(truncatingIfNeeded: a) > Int8(truncatingIfNeeded: b) ? 1001 : 1002
}
// 11 mixed widths: 1101 iff Int(Int8(a)) < Int(UInt16(b)) (sign-extend one,
// zero-extend the other, compare at 32 or 64 bits signed).
@inline(never) public func s11_mixwidth(_ a: Int, _ b: Int) -> Int {
    return Int(Int8(truncatingIfNeeded: a)) < Int(UInt16(truncatingIfNeeded: b)) ? 1101 : 1102
}

// ------------------------------------------------- comparisons with constants
// Ladders: each rung is one boundary. The result names the first rung taken.

// 12 Int8 ladder: v = Int8(a). v < -1 -> 1201; v < 1 -> 1202 (v is -1 or 0);
// v < 127 -> 1203; else 1204 (v == 127).
@inline(never) public func s12_ladder_s8(_ a: Int) -> Int {
    let v = Int8(truncatingIfNeeded: a)
    if v < -1 { return 1201 }
    if v < 1 { return 1202 }
    if v < 127 { return 1203 }
    return 1204
}
// 13 UInt8 ladder: v = UInt8(a). v == 0 -> 1301; v <= 127 -> 1302;
// v < 255 -> 1303; else 1304 (v == 255).
@inline(never) public func s13_ladder_u8(_ a: Int) -> Int {
    let v = UInt8(truncatingIfNeeded: a)
    if v == 0 { return 1301 }
    if v <= 127 { return 1302 }
    if v < 255 { return 1303 }
    return 1304
}
// 14 Int16 ladder: v = Int16(a). v < -128 -> 1401; v < 0 -> 1402;
// v <= 127 -> 1403; v < 256 -> 1404; v < 32767 -> 1405; else 1406.
@inline(never) public func s14_ladder_s16(_ a: Int) -> Int {
    let v = Int16(truncatingIfNeeded: a)
    if v < -128 { return 1401 }
    if v < 0 { return 1402 }
    if v <= 127 { return 1403 }
    if v < 256 { return 1404 }
    if v < 32767 { return 1405 }
    return 1406
}
// 15 UInt16 ladder: v = UInt16(a). v < 1 -> 1501; v <= 255 -> 1502;
// v <= 256 -> 1503; v < 0x8000 -> 1504; v < 0xffff -> 1505; else 1506.
@inline(never) public func s15_ladder_u16(_ a: Int) -> Int {
    let v = UInt16(truncatingIfNeeded: a)
    if v < 1 { return 1501 }
    if v <= 255 { return 1502 }
    if v <= 256 { return 1503 }
    if v < 0x8000 { return 1504 }
    if v < 0xffff { return 1505 }
    return 1506
}
// 16 Int32 ladder: v = Int32(a). v == Int32.min -> 1601; v < -1 -> 1602;
// v <= 0 -> 1603; v < 128 -> 1604; v <= 255 -> 1605; v < 0x7fffffff -> 1606;
// else 1607.
@inline(never) public func s16_ladder_s32(_ a: Int) -> Int {
    let v = Int32(truncatingIfNeeded: a)
    if v == Int32.min { return 1601 }
    if v < -1 { return 1602 }
    if v <= 0 { return 1603 }
    if v < 128 { return 1604 }
    if v <= 255 { return 1605 }
    if v < 0x7fffffff { return 1606 }
    return 1607
}
// 17 UInt32 ladder: v = UInt32(a). v == 0 -> 1701; v < 256 -> 1702;
// v <= 0x7fffffff -> 1703; v == 0x80000000 -> 1704; v < 0xffffffff -> 1705;
// else 1706.
@inline(never) public func s17_ladder_u32(_ a: Int) -> Int {
    let v = UInt32(truncatingIfNeeded: a)
    if v == 0 { return 1701 }
    if v < 256 { return 1702 }
    if v <= 0x7fffffff { return 1703 }
    if v == 0x80000000 { return 1704 }
    if v < 0xffffffff { return 1705 }
    return 1706
}
// 18 Int ladder: a == Int.min -> 1801; a < -0x80000000 -> 1802; a < -1 -> 1803;
// a < 1 -> 1804; a <= 127 -> 1805; a <= 255 -> 1806; a < 0x7fffffff -> 1807;
// a <= 0x80000000 -> 1808; a < Int.max -> 1809; else 1810.
@inline(never) public func s18_ladder_s64(_ a: Int) -> Int {
    if a == Int.min { return 1801 }
    if a < -0x80000000 { return 1802 }
    if a < -1 { return 1803 }
    if a < 1 { return 1804 }
    if a <= 127 { return 1805 }
    if a <= 255 { return 1806 }
    if a < 0x7fffffff { return 1807 }
    if a <= 0x80000000 { return 1808 }
    if a < Int.max { return 1809 }
    return 1810
}
// 19 UInt ladder: v = UInt(a). v == 0 -> 1901; v < 128 -> 1902; v <= 256 -> 1903;
// v < 0x80000000 -> 1904; v <= 0xffffffff -> 1905; v <= UInt(Int.max) -> 1906;
// v < UInt.max -> 1907; else 1908.
@inline(never) public func s19_ladder_u64(_ a: Int) -> Int {
    let v = UInt(bitPattern: a)
    if v == 0 { return 1901 }
    if v < 128 { return 1902 }
    if v <= 256 { return 1903 }
    if v < 0x80000000 { return 1904 }
    if v <= 0xffffffff { return 1905 }
    if v <= UInt(Int.max) { return 1906 }
    if v < UInt.max { return 1907 }
    return 1908
}
// Single constants as a select. The compiler is free to rewrite `> c` as
// `>= c+1`; the render must land on the same boundary.
// 20 `cmp x0, #0; cset gt`-like: 2001 iff a > 0.
@inline(never) public func s20_gt0(_ a: Int) -> Int { return a > 0 ? 2001 : 2002 }
// 21 `tbnz x0, #63` or `cmp x0,#0; lt`: 2101 iff a < 0.
@inline(never) public func s21_lt0(_ a: Int) -> Int { return a < 0 ? 2101 : 2102 }
// 22 `cmn x0, #1; gt`: 2201 iff a > -1 (same as a >= 0).
@inline(never) public func s22_gtm1(_ a: Int) -> Int { return a > -1 ? 2201 : 2202 }
// 23 `sxtb; cmn w8, #1; le`-like: 2301 iff Int8(a) <= -1.
@inline(never) public func s23_s8_lem1(_ a: Int) -> Int {
    return Int8(truncatingIfNeeded: a) <= -1 ? 2301 : 2302
}
// 24 `tbnz w0, #7`: 2401 iff UInt8(a) >= 128.
@inline(never) public func s24_u8_ge128(_ a: Int) -> Int {
    return UInt8(truncatingIfNeeded: a) >= 128 ? 2401 : 2402
}
// 25 `cmp w8, #255; hi` on a uxth: 2501 iff UInt16(a) > 255.
@inline(never) public func s25_u16_gt255(_ a: Int) -> Int {
    return UInt16(truncatingIfNeeded: a) > 255 ? 2501 : 2502
}
// 26 `sxth; cmp w8, #128; lt`: 2601 iff Int16(a) < 128.
@inline(never) public func s26_s16_lt128(_ a: Int) -> Int {
    return Int16(truncatingIfNeeded: a) < 128 ? 2601 : 2602
}
// 27 `tbnz w0, #31`: 2701 iff UInt32(a) >= 0x80000000.
@inline(never) public func s27_u32_ge_8(_ a: Int) -> Int {
    return UInt32(truncatingIfNeeded: a) >= 0x80000000 ? 2701 : 2702
}
// 28 2801 iff Int32(a) > 0x7ffffffe (only Int32.max).
@inline(never) public func s28_s32_gt_max1(_ a: Int) -> Int {
    return Int32(truncatingIfNeeded: a) > 0x7ffffffe ? 2801 : 2802
}
// 29 2901 iff UInt(a) > 0x7fffffffffffffff (a sign test).
@inline(never) public func s29_u64_gt_smax(_ a: Int) -> Int {
    return UInt(bitPattern: a) > 0x7fffffffffffffff ? 2901 : 2902
}
// 30 `lsr x8, x0, #8; cbz`-like or `cmp x0,#256; lo`: 3001 iff UInt(a) < 256.
@inline(never) public func s30_u64_lt256(_ a: Int) -> Int {
    return UInt(bitPattern: a) < 256 ? 3001 : 3002
}
// 31 3101 iff a <= 0x80000000 (a 64-bit signed compare with a constant that
// is negative at 32 bits).
@inline(never) public func s31_s64_le_8(_ a: Int) -> Int {
    return a <= 0x80000000 ? 3101 : 3102
}
// 32 3201 iff a != Int.min && a != Int.max.
@inline(never) public func s32_notextreme(_ a: Int) -> Int {
    return (a != Int.min && a != Int.max) ? 3201 : 3202
}

// -------------------------------------------------------------- range checks
// 33 `sub x8, x0, #10; cmp x8, #10; lo`: 3301 iff 10 <= a < 20.
@inline(never) public func s33_range_const(_ a: Int) -> Int {
    return (10 <= a && a < 20) ? 3301 : 3302
}
// 34 `cmp; ccmp; lt`: 3401 iff b <= a && a < c.
@inline(never) public func s34_range_var(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return (b <= a && a < c) ? 3401 : 3402
}
// 35 `sub x8, x0, x1; cmp x8, x2; lo`: 3501 iff UInt(a &- b) < UInt(c).
@inline(never) public func s35_range_sub(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return UInt(bitPattern: a &- b) < UInt(bitPattern: c) ? 3501 : 3502
}
// 36 `add x8, x0, #5; cmp x8, #11; lo`: 3601 iff -5 <= a <= 5.
@inline(never) public func s36_range_neg(_ a: Int) -> Int {
    return (-5 <= a && a <= 5) ? 3601 : 3602
}
// 37 the complement: 3701 iff a < 10 || a >= 20.
@inline(never) public func s37_range_out(_ a: Int) -> Int {
    return (a < 10 || a >= 20) ? 3701 : 3702
}
// 38 a byte class: v = UInt8(a); 3801 iff 'a'(97) <= v <= 'z'(122);
// 3802 iff '0'(48) <= v <= '9'(57); else 3803.
@inline(never) public func s38_range_u8(_ a: Int) -> Int {
    let v = UInt8(truncatingIfNeeded: a)
    if v >= 97 && v <= 122 { return 3801 }
    if v >= 48 && v <= 57 { return 3802 }
    return 3803
}
// 39 ClosedRange.contains: 3901 iff 100 <= a <= 1000.
@inline(never) public func s39_range_contains(_ a: Int) -> Int {
    return (100...1000).contains(a) ? 3901 : 3902
}

// --------------------------------------------------------- compound conditions
// 40 `cmp; ccmp; b`: 4001 iff a < b && b < c.
@inline(never) public func s40_and2(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return (a < b && b < c) ? 4001 : 4002
}
// 41 4101 iff a < b || b < c.
@inline(never) public func s41_or2(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return (a < b || b < c) ? 4101 : 4102
}
// 42 4201 iff a > 3 && b > 3 && c > 3.
@inline(never) public func s42_and3(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return (a > 3 && b > 3 && c > 3) ? 4201 : 4202
}
// 43 4301 iff a == 7 || b == 7 || c == 7.
@inline(never) public func s43_or3(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return (a == 7 || b == 7 || c == 7) ? 4301 : 4302
}
// 44 4401 iff a < b && b < c && a != 0 && c <= 100.
@inline(never) public func s44_and4(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return (a < b && b < c && a != 0 && c <= 100) ? 4401 : 4402
}
// 45 4501 iff a == b || b == c || a > 100 || c < -100.
@inline(never) public func s45_or4(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return (a == b || b == c || a > 100 || c < -100) ? 4501 : 4502
}
// 46 4601 iff (a < b && c > 5) || (a == c).
@inline(never) public func s46_andor(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return ((a < b && c > 5) || a == c) ? 4601 : 4602
}
// 47 mixed signedness: 4701 iff a < b (signed) && UInt(a) < UInt(c).
@inline(never) public func s47_mixsign(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return (a < b && UInt(bitPattern: a) < UInt(bitPattern: c)) ? 4701 : 4702
}
// 48 mixed widths in one chain: 4801 iff Int32(a) < Int32(b) && c >= 0 && UInt8(b) != 0.
@inline(never) public func s48_mixwidth_and(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return (Int32(truncatingIfNeeded: a) < Int32(truncatingIfNeeded: b) && c >= 0
            && UInt8(truncatingIfNeeded: b) != 0) ? 4801 : 4802
}
// 49 `cmn`/`ccmn`: 4901 iff a == -1 && b == -7.
@inline(never) public func s49_ccmn(_ a: Int, _ b: Int) -> Int {
    return (a == -1 && b == -7) ? 4901 : 4902
}
// 50 four paths, not folded to one boolean: a < b: (b < c ? 5001 : 5002);
// else (a < c ? 5003 : 5004).
@inline(never) public func s50_tree(_ a: Int, _ b: Int, _ c: Int) -> Int {
    if a < b { return b < c ? 5001 : 5002 }
    return a < c ? 5003 : 5004
}

// --------------------------------------------------------- conditional selects
// 51 `csel`: a < b ? a : c.
@inline(never) public func s51_csel(_ a: Int, _ b: Int, _ c: Int) -> Int { return a < b ? a : c }
// 52 `csinc`: a < b ? c : b + 1 (wrapping).
@inline(never) public func s52_csinc(_ a: Int, _ b: Int, _ c: Int) -> Int { return a < b ? c : b &+ 1 }
// 53 `csinv`: UInt(a) < UInt(b) ? c : ~b.
@inline(never) public func s53_csinv(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return UInt(bitPattern: a) < UInt(bitPattern: b) ? c : ~b
}
// 54 `csneg`: a >= b ? c : 0 - b (wrapping).
@inline(never) public func s54_csneg(_ a: Int, _ b: Int, _ c: Int) -> Int { return a >= b ? c : 0 &- b }
// 55 `cset; add`: (a <= b ? 1 : 0) + 5500.
@inline(never) public func s55_cset(_ a: Int, _ b: Int) -> Int { return (a <= b ? 1 : 0) &+ 5500 }
// 56 `csetm; and`: (a != b ? -1 : 0) & 0x5656.
@inline(never) public func s56_csetm(_ a: Int, _ b: Int) -> Int { return (a != b ? -1 : 0) & 0x5656 }
// 57 `cinc`: a + (b > 9 ? 1 : 0) (wrapping).
@inline(never) public func s57_cinc(_ a: Int, _ b: Int) -> Int { return a &+ (b > 9 ? 1 : 0) }
// 58 `cneg`: b < 0 ? 0 - a : a (wrapping).
@inline(never) public func s58_cneg(_ a: Int, _ b: Int) -> Int { return b < 0 ? 0 &- a : a }
// 59 a 32-bit select: Int(Int32(a) < Int32(b) ? Int32(a) : Int32(b)) (min at 32 bits).
@inline(never) public func s59_csel32(_ a: Int, _ b: Int) -> Int {
    let x = Int32(truncatingIfNeeded: a), y = Int32(truncatingIfNeeded: b)
    return Int(x < y ? x : y)
}

// ------------------------------------------------------------------ bit tests
// 60 `tbnz w0, #5`: 6001 iff bit 5 of a is set.
@inline(never) public func s60_bit5(_ a: Int) -> Int { return a & 32 != 0 ? 6001 : 6002 }
// 61 `tbz x0, #40`: 6101 iff bit 40 of a is clear.
@inline(never) public func s61_bit40clear(_ a: Int) -> Int { return a & (1 << 40) == 0 ? 6101 : 6102 }
// 62 `tst x0, #0xf0; eq`: 6201 iff a & 0xf0 == 0.
@inline(never) public func s62_mask_zero(_ a: Int) -> Int { return a & 0xf0 == 0 ? 6201 : 6202 }
// 63 `mvn; tst #0xf0` or `and; cmp #0xf0`: 6301 iff a & 0xf0 == 0xf0.
@inline(never) public func s63_mask_all(_ a: Int) -> Int { return a & 0xf0 == 0xf0 ? 6301 : 6302 }
// 64 `bics xzr, x1, x0; eq`: 6401 iff b & ~a == 0 (a contains b).
@inline(never) public func s64_bics(_ a: Int, _ b: Int) -> Int { return b & ~a == 0 ? 6401 : 6402 }
// 65 `tst x0, x1; ne`: 6501 iff a & b != 0.
@inline(never) public func s65_tst(_ a: Int, _ b: Int) -> Int { return a & b != 0 ? 6501 : 6502 }
// 66 `lsr x8, x0, x1; tbnz w8, #0`: 6601 iff bit (b & 63) of a is set.
@inline(never) public func s66_bitvar(_ a: Int, _ b: Int) -> Int {
    return (a &>> b) & 1 != 0 ? 6601 : 6602
}
// 67 the sign of a narrow value: 6701 iff Int16(a) < 0 (`tbnz w0, #15`).
@inline(never) public func s67_sign16(_ a: Int) -> Int {
    return Int16(truncatingIfNeeded: a) < 0 ? 6701 : 6702
}
// 68 `tst w0, #0x80000001`-like: 6801 iff a & 0x80000001 == 0x80000001;
// 6802 iff exactly one of the two bits; 6803 iff neither.
@inline(never) public func s68_twobits(_ a: Int) -> Int {
    let m = a & 0x80000001
    if m == 0x80000001 { return 6801 }
    if m != 0 { return 6802 }
    return 6803
}
// 69 parity and a mask in one: 6901 iff a is odd && a & 0xff00 == 0.
@inline(never) public func s69_odd_lowbyte(_ a: Int) -> Int {
    return (a & 1 == 1 && a & 0xff00 == 0) ? 6901 : 6902
}

// -------------------------------------------------------------------- switches
// 70 dense 0...7, a different operation in each case so it stays a jump table
// (8-bit entries at -O, 32-bit at -Onone). default: 7099.
@inline(never) public func s70_switch_dense(_ a: Int, _ b: Int) -> Int {
    switch a {
    case 0: return b &+ 7000
    case 1: return b &* 3
    case 2: return b ^ 0x7002
    case 3: return b &- 7003
    case 4: return b & 0x7004
    case 5: return b | 0x7005
    case 6: return b &<< 6
    case 7: return 0 &- b
    default: return 7099
    }
}
@inline(__always) func mix(_ r: Int, _ k: Int) -> Int {
    var x = r
    x = (x &* 31) ^ (x &>> 7) &+ k
    x = (x &* 17) ^ (x &>> 11) &+ (k &* 3)
    x = (x &* 13) ^ (x &>> 5) &+ (k &* 5)
    x = (x &* 29) ^ (x &>> 3) &+ (k &* 7)
    x = (x &* 37) ^ (x &>> 9) &+ (k &* 11)
    x = (x &* 41) ^ (x &>> 13) &+ (k &* 13)
    x = (x &* 43) ^ (x &>> 17) &+ (k &* 17)
    x = (x &* 47) ^ (x &>> 19) &+ (k &* 19)
    return x
}
// 71 dense 10...21 with bulky bodies, so the table needs 16-bit entries at -O.
// Case k returns mix(b, 7100 + k), repeated k % 3 + 1 times; default 7199.
@inline(never) public func s71_switch_wide(_ a: Int, _ b: Int) -> Int {
    switch a {
    case 10: return mix(b, 7110)
    case 11: return mix(mix(b, 7111), 7111)
    case 12: return mix(mix(mix(b, 7112), 7112), 7112)
    case 13: return mix(b, 7113)
    case 14: return mix(mix(b, 7114), 7114)
    case 15: return mix(mix(mix(b, 7115), 7115), 7115)
    case 16: return mix(b, 7116)
    case 17: return mix(mix(b, 7117), 7117)
    case 18: return mix(mix(mix(b, 7118), 7118), 7118)
    case 19: return mix(b, 7119)
    case 20: return mix(mix(b, 7120), 7120)
    case 21: return mix(mix(mix(b, 7121), 7121), 7121)
    default: return 7199
    }
}
// 72 sparse: a compare tree. 3->7201, 17->7202, 100->7203, 1000->7204,
// 5000->7205, 70000->7206, -9->7207, 0x100000000->7208, default 7299.
// Each case also uses b so the arms are not a lookup table.
@inline(never) public func s72_switch_sparse(_ a: Int, _ b: Int) -> Int {
    switch a {
    case 3: return 7201
    case 17: return b &+ 7202
    case 100: return b ^ 7203
    case 1000: return b &* 7204
    case 5000: return b | 7205
    case 70000: return b & 7206
    case -9: return b &- 7207
    case 0x1_0000_0000: return 7208
    default: return 7299
    }
}
// 73 groups: 1,3,5 -> 7301; 2,4 -> 7302; 10...20 -> 7303; 0 -> 7304; default 7399.
@inline(never) public func s73_switch_groups(_ a: Int) -> Int {
    switch a {
    case 1, 3, 5: return 7301
    case 2, 4: return 7302
    case 10...20: return 7303
    case 0: return 7304
    default: return 7399
    }
}
// 74 ranges: ..<0 -> 7401; 0..<10 -> 7402; 10..<100 -> 7403; 100..<1000 -> 7404;
// 1000... -> 7405.
@inline(never) public func s74_switch_ranges(_ a: Int) -> Int {
    switch a {
    case ..<0: return 7401
    case 0..<10: return 7402
    case 10..<100: return 7403
    case 100..<1000: return 7404
    default: return 7405
    }
}
public enum Shade: Int { case red = 0, orange, yellow, green, blue, violet }
// 75 over an enum built from a raw value: nil -> 7500; red -> b+7501;
// orange -> b*5; yellow -> b^7503; green -> 7504-b; blue -> b>>2 (arithmetic);
// violet -> ~b.
@inline(never) public func s75_switch_enum(_ a: Int, _ b: Int) -> Int {
    guard let s = Shade(rawValue: a) else { return 7500 }
    switch s {
    case .red: return b &+ 7501
    case .orange: return b &* 5
    case .yellow: return b ^ 7503
    case .green: return 7504 &- b
    case .blue: return b >> 2
    case .violet: return ~b
    }
}
// 76 a dense table of constants: the compiler may make it a data lookup.
// 0->7613, 1->7607, 2->7641, 3->7602, 4->7629, 5->7611, 6->7653, default 7699.
@inline(never) public func s76_switch_lookup(_ a: Int) -> Int {
    switch a {
    case 0: return 7613
    case 1: return 7607
    case 2: return 7641
    case 3: return 7602
    case 4: return 7629
    case 5: return 7611
    case 6: return 7653
    default: return 7699
    }
}
// 77 a switch on a narrow value: v = UInt8(a). 0x41 -> 7701, 0x42 -> 7702,
// 0x80 -> 7703, 0xff -> 7704, default 7799.
@inline(never) public func s77_switch_u8(_ a: Int) -> Int {
    switch UInt8(truncatingIfNeeded: a) {
    case 0x41: return 7701
    case 0x42: return 7702
    case 0x80: return 7703
    case 0xff: return 7704
    default: return 7799
    }
}

// --------------------------------------------------- overflow-checked arithmetic
// 78 `adds; b.vs -> brk`: a + b, traps on signed overflow.
@inline(never) public func s78_add_trap(_ a: Int, _ b: Int) -> Int { return a + b }
// 79 `subs; b.vs`: a - b, traps on signed overflow.
@inline(never) public func s79_sub_trap(_ a: Int, _ b: Int) -> Int { return a - b }
// 80 `mul; smulh; cmp x9, x8, asr #63; b.ne`: a * b, traps on overflow.
@inline(never) public func s80_mul_trap(_ a: Int, _ b: Int) -> Int { return a * b }
// 81 control: wrapping a &+ b &* 3 &- 81.
@inline(never) public func s81_wrap(_ a: Int, _ b: Int) -> Int { return a &+ b &* 3 &- 81 }
// 82 the smart shift: a << b. b >= 64 gives 0; b < 0 shifts right
// (arithmetic), b <= -64 gives 0 or -1.
@inline(never) public func s82_shl_smart(_ a: Int, _ b: Int) -> Int { return a << b }
// 83 the masking shift: a &<< b uses b & 63.
@inline(never) public func s83_shl_mask(_ a: Int, _ b: Int) -> Int { return (a &<< b) ^ 83 }
// 84 arithmetic shift right, smart: a >> b. b >= 64 gives 0 or -1.
@inline(never) public func s84_shr_smart(_ a: Int, _ b: Int) -> Int { return a >> b }
// 85 logical shift right, masking: Int(UInt(a) &>> b).
@inline(never) public func s85_lsr_mask(_ a: Int, _ b: Int) -> Int {
    return Int(bitPattern: UInt(bitPattern: a) &>> UInt(bitPattern: b)) &+ 85
}
// 86 addingReportingOverflow: overflow ? 8601 : partial ^ 8600.
@inline(never) public func s86_add_report(_ a: Int, _ b: Int) -> Int {
    let (v, o) = a.addingReportingOverflow(b)
    return o ? 8601 : v ^ 8600
}
// 87 multipliedReportingOverflow: overflow ? 8701 : partial.
@inline(never) public func s87_mul_report(_ a: Int, _ b: Int) -> Int {
    let (v, o) = a.multipliedReportingOverflow(by: b)
    return o ? 8701 : v
}
// 88 32-bit trapping add: Int(Int32(a) + Int32(b)), traps on 32-bit overflow.
@inline(never) public func s88_add_trap32(_ a: Int, _ b: Int) -> Int {
    return Int(Int32(truncatingIfNeeded: a) + Int32(truncatingIfNeeded: b))
}
// 89 8-bit trapping add: Int(Int8(a) + Int8(b)), traps outside -128...127.
@inline(never) public func s89_add_trap8(_ a: Int, _ b: Int) -> Int {
    return Int(Int8(truncatingIfNeeded: a) + Int8(truncatingIfNeeded: b))
}
// 90 unsigned trapping add: `adds; b.hs`: Int(bitPattern: UInt(a) + UInt(b)).
@inline(never) public func s90_uadd_trap(_ a: Int, _ b: Int) -> Int {
    return Int(bitPattern: UInt(bitPattern: a) + UInt(bitPattern: b))
}
// 91 unsigned trapping subtract: `subs; b.lo`: traps iff UInt(a) < UInt(b).
@inline(never) public func s91_usub_trap(_ a: Int, _ b: Int) -> Int {
    return Int(bitPattern: UInt(bitPattern: a) - UInt(bitPattern: b))
}
// 92 negation: -a traps for Int.min; result ^ 92.
@inline(never) public func s92_neg_trap(_ a: Int) -> Int { return (-a) ^ 92 }
// 93 exact narrowing: Int(Int8(a)) traps unless -128 <= a <= 127; result + 9300.
@inline(never) public func s93_narrow_trap(_ a: Int) -> Int { return Int(Int8(a)) &+ 9300 }
// 94 sign conversion: Int(bitPattern: UInt(a)) traps for a < 0; result ^ 94.
@inline(never) public func s94_unsigned_trap(_ a: Int) -> Int { return Int(bitPattern: UInt(a)) ^ 94 }
// 95 Int8(exactly:): nil -> 9500; else value + 9550.
@inline(never) public func s95_exactly(_ a: Int) -> Int {
    guard let v = Int8(exactly: a) else { return 9500 }
    return Int(v) &+ 9550
}
// 96 clamping: Int(UInt8(clamping: a)) + 9600.
@inline(never) public func s96_clamping(_ a: Int) -> Int { return Int(UInt8(clamping: a)) &+ 9600 }

// ------------------------------------------------------ division and remainder
// 97 `add x8, x0, #7; csel lt; asr #3`: a / 8 (toward zero).
@inline(never) public func s97_sdiv8(_ a: Int) -> Int { return a / 8 }
// 98 `smulh` by a magic constant: a / 10.
@inline(never) public func s98_sdiv10(_ a: Int) -> Int { return a / 10 }
// 99 a / -7.
@inline(never) public func s99_sdivm7(_ a: Int) -> Int { return a / -7 }
// 100 a / 3 at 32 bits: Int(Int32(a) / 3).
@inline(never) public func s100_sdiv3_32(_ a: Int) -> Int { return Int(Int32(truncatingIfNeeded: a) / 3) }
// 101 `lsr #4`: Int(UInt(a) / 16).
@inline(never) public func s101_udiv16(_ a: Int) -> Int { return Int(bitPattern: UInt(bitPattern: a) / 16) }
// 102 `umulh`: Int(UInt(a) / 10).
@inline(never) public func s102_udiv10(_ a: Int) -> Int { return Int(bitPattern: UInt(bitPattern: a) / 10) }
// 103 Int(UInt(a) / 7) (the 65-bit magic: umulh, sub, lsr, add, lsr).
@inline(never) public func s103_udiv7(_ a: Int) -> Int { return Int(bitPattern: UInt(bitPattern: a) / 7) }
// 104 `negs; and; and; csneg`: a % 8 (sign of a).
@inline(never) public func s104_srem8(_ a: Int) -> Int { return a % 8 }
// 105 a % 10 (smulh, msub).
@inline(never) public func s105_srem10(_ a: Int) -> Int { return a % 10 }
// 106 `and x0, x0, #0xf`: Int(UInt(a) % 16).
@inline(never) public func s106_urem16(_ a: Int) -> Int { return Int(bitPattern: UInt(bitPattern: a) % 16) }
// 107 Int(UInt(a) % 10).
@inline(never) public func s107_urem10(_ a: Int) -> Int { return Int(bitPattern: UInt(bitPattern: a) % 10) }
// 108 a / b: traps for b == 0 and for Int.min / -1.
@inline(never) public func s108_sdiv_var(_ a: Int, _ b: Int) -> Int { return a / b }
// 109 a % b: traps for b == 0 and for Int.min % -1.
@inline(never) public func s109_srem_var(_ a: Int, _ b: Int) -> Int { return a % b }
// 110 UInt(a) / UInt(b): traps for b == 0 only.
@inline(never) public func s110_udiv_var(_ a: Int, _ b: Int) -> Int {
    return Int(bitPattern: UInt(bitPattern: a) / UInt(bitPattern: b))
}
// 111 a.isMultiple(of: 3) ? 11101 : 11102 (multiply by the inverse, ror, cmp).
@inline(never) public func s111_multiple3(_ a: Int) -> Int { return a.isMultiple(of: 3) ? 11101 : 11102 }
// 112 quotient and remainder together: (a / 1000) * 7 + a % 1000.
@inline(never) public func s112_divmod1000(_ a: Int) -> Int { return (a / 1000) &* 7 &+ a % 1000 }
// 113 Int8 division by 2: Int(Int8(a) / 2).
@inline(never) public func s113_sdiv2_8(_ a: Int) -> Int { return Int(Int8(truncatingIfNeeded: a) / 2) }

// ------------------------------------------------------ min, max, abs, clamp
// 114 `cmp; csel lt`: min(a, b).
@inline(never) public func s114_min(_ a: Int, _ b: Int) -> Int { return min(a, b) }
// 115 `cmp; csel gt`: max(a, b) ^ 115.
@inline(never) public func s115_max(_ a: Int, _ b: Int) -> Int { return max(a, b) ^ 115 }
// 116 unsigned min: Int(min(UInt(a), UInt(b))) + 116.
@inline(never) public func s116_umin(_ a: Int, _ b: Int) -> Int {
    return Int(bitPattern: min(UInt(bitPattern: a), UInt(bitPattern: b))) &+ 116
}
// 117 abs(a): traps for Int.min.
@inline(never) public func s117_abs(_ a: Int) -> Int { return abs(a) }
// 118 `cmp x0,#0; cneg mi`: Int(bitPattern: a.magnitude) - 118, no trap.
@inline(never) public func s118_magnitude(_ a: Int) -> Int { return Int(bitPattern: a.magnitude) &- 118 }
// 119 clamp to -100...100: min(max(a, -100), 100).
@inline(never) public func s119_clamp(_ a: Int) -> Int { return min(max(a, -100), 100) }
// 120 clamp to variable bounds: min(max(a, b), c).
@inline(never) public func s120_clamp_var(_ a: Int, _ b: Int, _ c: Int) -> Int { return min(max(a, b), c) }
// 121 max of three: max(a, b, c).
@inline(never) public func s121_max3(_ a: Int, _ b: Int, _ c: Int) -> Int { return max(a, b, c) }
// 122 signum: a > 0 -> 1, a == 0 -> 0, a < 0 -> -1; + 12200.
@inline(never) public func s122_signum(_ a: Int) -> Int { return a.signum() &+ 12200 }
// 123 absolute difference without overflow: a > b ? a &- b : b &- a.
@inline(never) public func s123_absdiff(_ a: Int, _ b: Int) -> Int { return a > b ? a &- b : b &- a }

// ------------------------------------------------------------ bit manipulation
// 124 `clz x0, x0`: a.leadingZeroBitCount + 12400.
@inline(never) public func s124_clz(_ a: Int) -> Int { return a.leadingZeroBitCount &+ 12400 }
// 125 `rbit; clz`: a.trailingZeroBitCount + 12500.
@inline(never) public func s125_ctz(_ a: Int) -> Int { return a.trailingZeroBitCount &+ 12500 }
// 126 `fmov; cnt; addv` (NEON): a.nonzeroBitCount + 12600.
@inline(never) public func s126_popcount(_ a: Int) -> Int { return a.nonzeroBitCount &+ 12600 }
// 127 `rev x0, x0`: a.byteSwapped.
@inline(never) public func s127_bswap(_ a: Int) -> Int { return a.byteSwapped }
// 128 `ror x0, x0, #51`: rotate left 13: (a << 13) | (UInt(a) >> 51).
@inline(never) public func s128_rotl13(_ a: Int) -> Int {
    let u = UInt(bitPattern: a)
    return Int(bitPattern: (u &<< 13) | (u &>> 51))
}
// 129 `neg; ror x0, x0, x8`: rotate left by b & 63.
@inline(never) public func s129_rotl_var(_ a: Int, _ b: Int) -> Int {
    let u = UInt(bitPattern: a), n = UInt(bitPattern: b) & 63
    return Int(bitPattern: (u &<< n) | (u &>> ((64 &- n) & 63)))
}
// 130 `ubfx x0, x0, #12, #8`: (a >> 12) & 0xff.
@inline(never) public func s130_ubfx(_ a: Int) -> Int { return (a >> 12) & 0xff }
// 131 `sbfx x0, x0, #12, #8`: Int(Int8(truncating: a >> 12)).
@inline(never) public func s131_sbfx(_ a: Int) -> Int { return Int(Int8(truncatingIfNeeded: a >> 12)) }
// 132 `bfi x0, x1, #8, #8`: (a & ~0xff00) | ((b & 0xff) << 8).
@inline(never) public func s132_bfi(_ a: Int, _ b: Int) -> Int { return (a & ~0xff00) | ((b & 0xff) << 8) }
// 133 `sxtb x0, w0`: Int(Int8(truncating: a)) ^ 133.
@inline(never) public func s133_sext8(_ a: Int) -> Int { return Int(Int8(truncatingIfNeeded: a)) ^ 133 }
// 134 `sxth`: Int(Int16(truncating: a)) + 134.
@inline(never) public func s134_sext16(_ a: Int) -> Int { return Int(Int16(truncatingIfNeeded: a)) &+ 134 }
// 135 `sxtw`: Int(Int32(truncating: a)) - 135.
@inline(never) public func s135_sext32(_ a: Int) -> Int { return Int(Int32(truncatingIfNeeded: a)) &- 135 }
// 136 `and #0xff`: Int(UInt8(truncating: a)) + 13600.
@inline(never) public func s136_zext8(_ a: Int) -> Int { return Int(UInt8(truncatingIfNeeded: a)) &+ 13600 }
// 137 `and #0xffff`: Int(UInt16(truncating: a)) ^ 0x13700000.
@inline(never) public func s137_zext16(_ a: Int) -> Int { return Int(UInt16(truncatingIfNeeded: a)) ^ 0x13700000 }
// 138 `mov w0, w0`: Int(UInt32(truncating: a)) + 138.
@inline(never) public func s138_zext32(_ a: Int) -> Int { return Int(UInt32(truncatingIfNeeded: a)) &+ 138 }
// 139 `clz w0, w0`: Int32(a).leadingZeroBitCount + 13900.
@inline(never) public func s139_clz32(_ a: Int) -> Int {
    return Int32(truncatingIfNeeded: a).leadingZeroBitCount &+ 13900
}
// 140 `rev16`/`rev w; lsr #16`: Int(UInt16(a).byteSwapped).
@inline(never) public func s140_bswap16(_ a: Int) -> Int { return Int(UInt16(truncatingIfNeeded: a).byteSwapped) }
// 141 `ror w0, w0, #7` at 32 bits: rotate right 7 of UInt32(a).
@inline(never) public func s141_rotr7_32(_ a: Int) -> Int {
    let u = UInt32(truncatingIfNeeded: a)
    return Int((u &>> 7) | (u &<< 25))
}
// 142 lowest set bit and its clearing: (a & -a) * 3 ^ (a & (a - 1)), wrapping.
// (Without the * 3 the two halves recombine to a and the function folds.)
@inline(never) public func s142_lowbit(_ a: Int) -> Int { return ((a & (0 &- a)) &* 3) ^ (a & (a &- 1)) }
// 143 power of two test: a > 0 && a & (a-1) == 0 ? 14301 : 14302.
@inline(never) public func s143_ispow2(_ a: Int) -> Int { return (a > 0 && a & (a &- 1) == 0) ? 14301 : 14302 }

// --------------------------------------------------- multiplication by constants
// 144 `add x0, x0, x0, lsl #1`: a * 3 (wrapping).
@inline(never) public func s144_mul3(_ a: Int) -> Int { return a &* 3 }
// 145 `lsl #3; sub`: a * 7.
@inline(never) public func s145_mul7(_ a: Int) -> Int { return a &* 7 }
// 146 `add lsl #2; lsl #1`: a * 10.
@inline(never) public func s146_mul10(_ a: Int) -> Int { return a &* 10 }
// 147 `add x0, x0, x0, lsl #4`: a * 17.
@inline(never) public func s147_mul17(_ a: Int) -> Int { return a &* 17 }
// 148 `mov w8,#100; mul`: a * 100.
@inline(never) public func s148_mul100(_ a: Int) -> Int { return a &* 100 }
// 149 `sub x0, x0, x0, lsl #2`: a * -3.
@inline(never) public func s149_mulm3(_ a: Int) -> Int { return a &* -3 }
// 150 `madd`: a * 24 + b * 5 + 150.
@inline(never) public func s150_mul_mix(_ a: Int, _ b: Int) -> Int { return a &* 24 &+ b &* 5 &+ 150 }
// 151 `lsl #16; add`: a * 65537.
@inline(never) public func s151_mul65537(_ a: Int) -> Int { return a &* 65537 }

// ----------------------------------------------------------------------- loops
// The accumulations are multiply-xor recurrences, which have no closed form
// the compiler can substitute, so each loop stays a loop.

// 152 known trip count 10: acc = a; for i in 0..<10 { acc = acc * 31 ^ i }.
@inline(never) public func s152_loop_known(_ a: Int) -> Int {
    var acc = a
    for i in 0..<10 { acc = (acc &* 31) ^ i }
    return acc
}
// 153 count from an argument: acc = b; i from 0 while i < a: acc = acc*33 + i.
// a <= 0 runs zero times and returns b.
@inline(never) public func s153_loop_n(_ a: Int, _ b: Int) -> Int {
    var acc = b, i = 0
    while i < a { acc = acc &* 33 &+ i; i &+= 1 }
    return acc
}
// 154 `for i in 0..<a`: the same body with 37, but a < 0 traps (range check).
@inline(never) public func s154_loop_range(_ a: Int, _ b: Int) -> Int {
    var acc = b
    for i in 0..<a { acc = acc &* 37 &+ i }
    return acc
}
// 155 countdown: i = a; while i > 0 { acc = acc*5 ^ i; i -= 1 }.
@inline(never) public func s155_loop_down(_ a: Int, _ b: Int) -> Int {
    var acc = b, i = a
    while i > 0 { acc = (acc &* 5) ^ i; i &-= 1 }
    return acc
}
// 156 step 2: stride(from: 0, to: a, by: 2): acc = acc*7 + i.
@inline(never) public func s156_loop_step2(_ a: Int, _ b: Int) -> Int {
    var acc = b
    for i in stride(from: 0, to: a, by: 2) { acc = acc &* 7 &+ i }
    return acc
}
// 157 step 3 from 1: i = 1; while i <= a { acc = acc*11 ^ i; i += 3 }.
@inline(never) public func s157_loop_step3(_ a: Int, _ b: Int) -> Int {
    var acc = b, i = 1
    while i <= a { acc = (acc &* 11) ^ i; i &+= 3 }
    return acc
}
// 158 compound exit: while i < a && acc < 100000 { acc = acc*3 + i + 1; i += 1 };
// returns acc*100 + i (which exit is visible in i).
@inline(never) public func s158_loop_compound(_ a: Int, _ b: Int) -> Int {
    var acc = b, i = 0
    while i < a && acc < 100000 { acc = acc &* 3 &+ i &+ 1; i &+= 1 }
    return acc &* 100 &+ i
}
// 159 nested: for i < a, for j < b: acc = acc*3 ^ (i*16 + j).
@inline(never) public func s159_loop_nested(_ a: Int, _ b: Int) -> Int {
    var acc = 159, i = 0
    while i < a {
        var j = 0
        while j < b { acc = (acc &* 3) ^ (i &* 16 &+ j); j &+= 1 }
        i &+= 1
    }
    return acc
}
// 160 break and continue: for i < a: i % 3 == 1 skips; acc > b (b as a limit)
// breaks; else acc = acc*2 + i. Returns acc*64 + i at exit.
@inline(never) public func s160_loop_break(_ a: Int, _ b: Int) -> Int {
    var acc = 1, i = 0
    while i < a {
        if i % 3 == 1 { i &+= 1; continue }
        if acc > b { break }
        acc = acc &* 2 &+ i
        i &+= 1
    }
    return acc &* 64 &+ i
}
// 161 two accumulators: s += i*i (wrapping), p = p*3 ^ i, for i in 1...a
// (while form); returns s * 1000003 ^ p.
@inline(never) public func s161_loop_two(_ a: Int, _ b: Int) -> Int {
    var s = 0, p = b, i = 1
    while i <= a { s &+= i &* i; p = (p &* 3) ^ i; i &+= 1 }
    return (s &* 1000003) ^ p
}
// 162 stride downward through: stride(from: a, through: 0, by: -4):
// acc = acc*13 + i.
@inline(never) public func s162_loop_stride_down(_ a: Int, _ b: Int) -> Int {
    var acc = b
    for i in stride(from: a, through: 0, by: -4) { acc = acc &* 13 &+ i }
    return acc
}
let table163: [Int] = [3, 1, 4, 1, 5, 9, 2, 6]
// 163 an array of known contents: acc = b; for v in [3,1,4,1,5,9,2,6]:
// acc = acc * a + v (Horner, wrapping).
@inline(never) public func s163_loop_array(_ a: Int, _ b: Int) -> Int {
    var acc = b
    for v in table163 { acc = acc &* a &+ v }
    return acc
}
// 164 repeat-while (runs at least once): repeat { acc = acc*17 ^ i; i += 1 } while i < a.
@inline(never) public func s164_loop_repeat(_ a: Int, _ b: Int) -> Int {
    var acc = b, i = 0
    repeat { acc = (acc &* 17) ^ i; i &+= 1 } while i < a
    return acc
}
// 165 data-dependent exit: count trailing even halvings of a, at most 70:
// while x != 0 && x & 1 == 0 { x >>= 1; n += 1 }; returns n*1000 + (x & 0xff).
@inline(never) public func s165_loop_halve(_ a: Int) -> Int {
    var x = a, n = 0
    while x != 0 && x & 1 == 0 { x >>= 1; n &+= 1 }
    return n &* 1000 &+ (x & 0xff)
}
// 166 Euclid on magnitudes below 2^62: x = a & 0xffff, y = b & 0xffff;
// while y != 0 { (x, y) = (y, x % y) }; returns x + 16600.
@inline(never) public func s166_loop_gcd(_ a: Int, _ b: Int) -> Int {
    var x = a & 0xffff, y = b & 0xffff
    while y != 0 { (x, y) = (y, x % y) }
    return x &+ 16600
}
// 167 a trapping accumulation: sum of i*a for i in 1...10 with checked
// arithmetic (traps when a is huge).
@inline(never) public func s167_loop_checked(_ a: Int) -> Int {
    var acc = 167
    for i in 1...10 { acc += i * a }
    return acc
}
// 168 a search loop with an early return: first i in 0..<16 with
// (a >> i) & 1 == 1 and i >= b; returns 16800 + i, or 16899 if none.
@inline(never) public func s168_loop_find(_ a: Int, _ b: Int) -> Int {
    var i = 0
    while i < 16 {
        if (a &>> i) & 1 == 1 && i >= b { return 16800 &+ i }
        i &+= 1
    }
    return 16899
}

// ------------------------------------------------- loops with a visible body
// The body is a call, so the number of iterations is a statement the render
// makes and the machine can be asked: each tick adds 1000000 + i.
public var tickCount = 0
@inline(never) public func tick(_ i: Int) { tickCount &+= 1000000 &+ i }
// 170 top-tested: tickCount = b; i from 0 while i < a: tick(i). Runs max(a, 0)
// times; -O rotates it into a guard and a bottom-tested loop.
@inline(never) public func s170_loop_calls(_ a: Int, _ b: Int) -> Int {
    tickCount = b
    var i = 0
    while i < a { tick(i); i &+= 1 }
    return tickCount
}
// 171 bottom-tested: repeat { tick(i); i += 1 } while i < a. Runs max(a, 1) times.
@inline(never) public func s171_loop_calls_repeat(_ a: Int, _ b: Int) -> Int {
    tickCount = b
    var i = 0
    repeat { tick(i); i &+= 1 } while i < a
    return tickCount
}
// 172 step 2 from 0 while i < a: runs ceil(a / 2) times for a > 0.
@inline(never) public func s172_loop_calls_step2(_ a: Int, _ b: Int) -> Int {
    tickCount = b
    var i = 0
    while i < a { tick(i); i &+= 2 }
    return tickCount
}
// 173 countdown: i = a; while i > 0 { tick(i); i -= 1 }. Runs max(a, 0) times.
@inline(never) public func s173_loop_calls_down(_ a: Int, _ b: Int) -> Int {
    tickCount = b
    var i = a
    while i > 0 { tick(i); i &-= 1 }
    return tickCount
}

// ============================================================ second batch
// Conditions whose flags come from arithmetic, not from a compare of the two
// values the source names. The classic wrong render turns `(a - b) < 0` into
// `a < b`: they differ whenever the subtraction overflows.

// 200 `subs/cmp; cset mi`: 20001 iff (a &- b) < 0. NOT a < b: (Int.min, 1) is
// 20002 here though Int.min < 1.
@inline(never) public func s200_diff_neg(_ a: Int, _ b: Int) -> Int { return (a &- b) < 0 ? 20001 : 20002 }
// 201 20101 iff (a &- b) > 0. NOT a > b.
@inline(never) public func s201_diff_pos(_ a: Int, _ b: Int) -> Int { return (a &- b) > 0 ? 20101 : 20102 }
// 202 `cmn x0, x1; mi`: 20201 iff (a &+ b) < 0. NOT a < -b.
@inline(never) public func s202_sum_neg(_ a: Int, _ b: Int) -> Int { return (a &+ b) < 0 ? 20201 : 20202 }
// 203 `cmn x0, x1; eq`: 20301 iff a &+ b == 0.
@inline(never) public func s203_sum_zero(_ a: Int, _ b: Int) -> Int { return (a &+ b) == 0 ? 20301 : 20302 }
// 204 `adds; hs`: the carry out of an unsigned add: 20401 iff UInt(a) &+ UInt(b) < UInt(a).
@inline(never) public func s204_carry(_ a: Int, _ b: Int) -> Int {
    return UInt(bitPattern: a) &+ UInt(bitPattern: b) < UInt(bitPattern: a) ? 20401 : 20402
}
// 205 the borrow of an unsigned subtract: 20501 iff UInt(a) &- UInt(b) > UInt(a) (iff UInt(a) < UInt(b)).
@inline(never) public func s205_borrow(_ a: Int, _ b: Int) -> Int {
    return UInt(bitPattern: a) &- UInt(bitPattern: b) > UInt(bitPattern: a) ? 20501 : 20502
}
// 206 at 32 bits: 20601 iff (Int32(a) &- Int32(b)) < 0.
@inline(never) public func s206_diff_neg32(_ a: Int, _ b: Int) -> Int {
    return (Int32(truncatingIfNeeded: a) &- Int32(truncatingIfNeeded: b)) < 0 ? 20601 : 20602
}
// 207 `adds x8, x0, #5; mi`-like: 20701 iff (a &+ 5) < 0. NOT a < -5 (Int.max - 4 ... Int.max wrap).
@inline(never) public func s207_addconst_neg(_ a: Int) -> Int { return (a &+ 5) < 0 ? 20701 : 20702 }
// 208 20801 iff (a &- 1) >= 0. NOT a >= 1 (Int.min wraps to Int.max).
@inline(never) public func s208_subconst_nonneg(_ a: Int) -> Int { return (a &- 1) >= 0 ? 20801 : 20802 }
// 209 `(a &* 2) < 0`: bit 62 of a. 20901 iff set.
@inline(never) public func s209_double_neg(_ a: Int) -> Int { return (a &* 2) < 0 ? 20901 : 20902 }
// 210 signed conditions on a test: `tst x0, x1; mi`: 21001 iff (a & b) < 0.
@inline(never) public func s210_and_neg(_ a: Int, _ b: Int) -> Int { return (a & b) < 0 ? 21001 : 21002 }
// 211 `tst; gt`: 21101 iff (a & b) > 0.
@inline(never) public func s211_and_pos(_ a: Int, _ b: Int) -> Int { return (a & b) > 0 ? 21101 : 21102 }
// 212 `tst; le`: 21201 iff (a & b) <= 0.
@inline(never) public func s212_and_le0(_ a: Int, _ b: Int) -> Int { return (a & b) <= 0 ? 21201 : 21202 }
// 213 `eor; tbnz #63`: 21301 iff a and b differ in sign.
@inline(never) public func s213_signs_differ(_ a: Int, _ b: Int) -> Int { return (a ^ b) < 0 ? 21301 : 21302 }
// 214 at 32 bits: 21401 iff (Int32(a) & Int32(b)) < 0 (bit 31 of both).
@inline(never) public func s214_and_neg32(_ a: Int, _ b: Int) -> Int {
    return (Int32(truncatingIfNeeded: a) & Int32(truncatingIfNeeded: b)) < 0 ? 21401 : 21402
}
// 215 three-way compare: a < b -> -1, a == b -> 0, a > b -> 1; + 21500
// (`cmp; cset gt; csinv lt`: one compare read twice).
@inline(never) public func s215_threeway(_ a: Int, _ b: Int) -> Int {
    return (a < b ? -1 : (a == b ? 0 : 1)) &+ 21500
}
// 216 unsigned three-way + 21600.
@inline(never) public func s216_threeway_u(_ a: Int, _ b: Int) -> Int {
    let x = UInt(bitPattern: a), y = UInt(bitPattern: b)
    return (x < y ? -1 : (x == y ? 0 : 1)) &+ 21600
}
// 217 two booleans compared: 21701 iff (a < b) == (b < c).
@inline(never) public func s217_booleq(_ a: Int, _ b: Int, _ c: Int) -> Int {
    return (a < b) == (b < c) ? 21701 : 21702
}
// 218 signed and unsigned order disagree: 21801 iff (a < b) != (UInt(a) < UInt(b)).
@inline(never) public func s218_order_disagree(_ a: Int, _ b: Int) -> Int {
    return (a < b) != (UInt(bitPattern: a) < UInt(bitPattern: b)) ? 21801 : 21802
}
// 219 `cmp x0, x1, lsl #3`: 21901 iff a < (b &<< 3).
@inline(never) public func s219_cmp_shift(_ a: Int, _ b: Int) -> Int { return a < (b &<< 3) ? 21901 : 21902 }
// 220 `cmp x0, w1, sxtw`: 22001 iff a < Int(Int32(truncating: b)).
@inline(never) public func s220_cmp_sxtw(_ a: Int, _ b: Int) -> Int {
    return a < Int(Int32(truncatingIfNeeded: b)) ? 22001 : 22002
}
// 221 `cmp x0, w1, uxtb`: 22101 iff UInt(a) <= UInt(UInt8(truncating: b)).
@inline(never) public func s221_cmp_uxtb(_ a: Int, _ b: Int) -> Int {
    return UInt(bitPattern: a) <= UInt(UInt8(truncatingIfNeeded: b)) ? 22101 : 22102
}
// 222 `cmp x0, x1, asr #2`: 22201 iff a == (b >> 2).
@inline(never) public func s222_cmp_asr(_ a: Int, _ b: Int) -> Int { return a == (b >> 2) ? 22201 : 22202 }
// 223 narrow equality: 22301 iff Int8(a) == Int8(b) (`eor; tst #0xff`).
@inline(never) public func s223_eq8(_ a: Int, _ b: Int) -> Int {
    return Int8(truncatingIfNeeded: a) == Int8(truncatingIfNeeded: b) ? 22301 : 22302
}
// 224 22401 iff UInt16(a) != UInt16(b).
@inline(never) public func s224_ne16(_ a: Int, _ b: Int) -> Int {
    return UInt16(truncatingIfNeeded: a) != UInt16(truncatingIfNeeded: b) ? 22401 : 22402
}
// 225 `orr; cbz`: 22501 iff a == 0 && b == 0.
@inline(never) public func s225_bothzero(_ a: Int, _ b: Int) -> Int { return (a == 0 && b == 0) ? 22501 : 22502 }
// 226 `cmp; ccmp #0, #4, ne`: 22601 iff a != 0 && b != 0.
@inline(never) public func s226_neitherzero(_ a: Int, _ b: Int) -> Int { return (a != 0 && b != 0) ? 22601 : 22602 }
// 227 `and x0, x1, x0, asr #63`: (a >> 63) & b.
@inline(never) public func s227_signmask(_ a: Int, _ b: Int) -> Int { return (a >> 63) & b }
// 228 `add x0, x1, x0, lsr #63`: b + (a < 0 ? 1 : 0), wrapping.
@inline(never) public func s228_signbit_add(_ a: Int, _ b: Int) -> Int {
    return b &+ Int(bitPattern: UInt(bitPattern: a) >> 63)
}
// 229 saturating add: `adds; asr #63; eor #0x8000…; csel vc`: overflow ?
// (a < 0 ? Int.min : Int.max) : a + b.
@inline(never) public func s229_sat_add(_ a: Int, _ b: Int) -> Int {
    let (v, o) = a.addingReportingOverflow(b)
    return o ? (a < 0 ? Int.min : Int.max) : v
}
// 230 unsigned saturating subtract: `subs; csel lo`: UInt(a) >= UInt(b) ? a - b : 0.
@inline(never) public func s230_usat_sub(_ a: Int, _ b: Int) -> Int {
    let x = UInt(bitPattern: a), y = UInt(bitPattern: b)
    return Int(bitPattern: x >= y ? x &- y : 0)
}
// 231 d = a &- b; d > 0 ? d : 0. The select is on d, NOT on a > b.
@inline(never) public func s231_relu_diff(_ a: Int, _ b: Int) -> Int { let d = a &- b; return d > 0 ? d : 0 }
// 232 `adds; cset hs; add`: carry + (sum >> 1): Int(c ? 1 : 0) + Int(lo >> 1).
@inline(never) public func s232_carry_value(_ a: Int, _ b: Int) -> Int {
    let (lo, c) = UInt(bitPattern: a).addingReportingOverflow(UInt(bitPattern: b))
    return (c ? 1 : 0) &+ Int(bitPattern: lo >> 1)
}
// 233 `umulh`: the high word of UInt(a) * UInt(b).
@inline(never) public func s233_mulhi_u(_ a: Int, _ b: Int) -> Int {
    return Int(bitPattern: UInt(bitPattern: a).multipliedFullWidth(by: UInt(bitPattern: b)).high)
}
// 234 `smulh`: the high word of a * b, ^ 234.
@inline(never) public func s234_mulhi_s(_ a: Int, _ b: Int) -> Int { return a.multipliedFullWidth(by: b).high ^ 234 }
// 235 a dense switch with negative cases, -3...4 (`add x8, x0, #3; cmp x8, #7`):
// -3 -> b+23501, -2 -> b*7, -1 -> b^23503, 0 -> 23504-b, 1 -> b<<3, 2 -> b>>1,
// 3 -> ~b, 4 -> b|0x235, default 23599.
@inline(never) public func s235_switch_neg(_ a: Int, _ b: Int) -> Int {
    switch a {
    case -3: return b &+ 23501
    case -2: return b &* 7
    case -1: return b ^ 23503
    case 0: return 23504 &- b
    case 1: return b &<< 3
    case 2: return b >> 1
    case 3: return ~b
    case 4: return b | 0x235
    default: return 23599
    }
}
// 236 a dense switch on a byte, '0'...'9' (0x30...0x39): v = UInt8(a); digit d
// returns b op d with a different op for each; default 23699. A selector of
// 0x130 must take case '0', 0x100000030 too.
@inline(never) public func s236_switch_u8_dense(_ a: Int, _ b: Int) -> Int {
    switch UInt8(truncatingIfNeeded: a) {
    case 0x30: return b &+ 23600
    case 0x31: return b &* 11
    case 0x32: return b ^ 23602
    case 0x33: return 23603 &- b
    case 0x34: return b &<< 4
    case 0x35: return b >> 3
    case 0x36: return ~b
    case 0x37: return b | 0x236
    case 0x38: return b & 0x2368
    case 0x39: return 0 &- b
    default: return 23699
    }
}
// 237 a dense switch on a signed byte with negative cases: v = Int8(a),
// -2...5; 0xfe must take case -2. default 23799.
@inline(never) public func s237_switch_s8_dense(_ a: Int, _ b: Int) -> Int {
    switch Int8(truncatingIfNeeded: a) {
    case -2: return b &+ 23700
    case -1: return b &* 13
    case 0: return b ^ 23702
    case 1: return 23703 &- b
    case 2: return b &<< 5
    case 3: return b >> 4
    case 4: return ~b
    case 5: return b | 0x237
    default: return 23799
    }
}
// 238 a loop with a byte counter that the compare narrows: n = UInt8(a);
// var i: UInt8 = 0; while i < n { tick(Int(i)); i &+= 1 }. Runs a & 0xff times.
@inline(never) public func s238_loop_u8(_ a: Int, _ b: Int) -> Int {
    tickCount = b
    let n = UInt8(truncatingIfNeeded: a)
    var i: UInt8 = 0
    while i < n { tick(Int(i)); i &+= 1 }
    return tickCount
}
// 239 an unsigned countdown that stops at zero from above: i = UInt(a & 0x3f);
// while i != 0 { i -= 1; tick(Int(i)) }.
@inline(never) public func s239_loop_udown(_ a: Int, _ b: Int) -> Int {
    tickCount = b
    var i = UInt(bitPattern: a & 0x3f)
    while i != 0 { i &-= 1; tick(Int(bitPattern: i)) }
    return tickCount
}
// 240 an inclusive loop: for i in a...(a + 3) with wrapping bound, a clamped to
// 0...1000: tick(i) four times.
@inline(never) public func s240_loop_inclusive(_ a: Int, _ b: Int) -> Int {
    tickCount = b
    let lo = min(max(a, 0), 1000)
    var i = lo
    while i <= lo &+ 3 { tick(i); i &+= 1 }
    return tickCount
}
// 241 nested with a triangular bound: for i < (a & 15), for j <= i: tick(i*16 + j).
@inline(never) public func s241_loop_triangle(_ a: Int, _ b: Int) -> Int {
    tickCount = b
    let n = a & 15
    var i = 0
    while i < n {
        var j = 0
        while j <= i { tick(i &* 16 &+ j); j &+= 1 }
        i &+= 1
    }
    return tickCount
}
// 242 22 comparisons of one value against constants, as a sum of weights:
// each term adds its weight when true, so the result is a bit set of outcomes.
// a < -128: 1; a <= -1: 2; a < 0x80: 4; a <= 0xff: 8; a < 0x100: 16;
// a >= 0x7fffffff: 32; a > 0x7fffffff: 64; a >= -0x80000000: 128;
// a > -0x80000001: 256; UInt(a) >= 0x80000000: 512; UInt(a) > 0xffffffff: 1024.
@inline(never) public func s242_weights(_ a: Int) -> Int {
    var r = 0
    if a < -128 { r |= 1 }
    if a <= -1 { r |= 2 }
    if a < 0x80 { r |= 4 }
    if a <= 0xff { r |= 8 }
    if a < 0x100 { r |= 16 }
    if a >= 0x7fffffff { r |= 32 }
    if a > 0x7fffffff { r |= 64 }
    if a >= -0x80000000 { r |= 128 }
    if a > -0x80000001 { r |= 256 }
    if UInt(bitPattern: a) >= 0x80000000 { r |= 512 }
    if UInt(bitPattern: a) > 0xffffffff { r |= 1024 }
    return r
}
// 243 the same idea at 32 bits: v = Int32(a). v < -128: 1; v > 127: 2;
// v >= 0x7fffffff: 4; v <= Int32.min: 8; UInt32(a) > 0x7fffffff: 16;
// UInt32(a) >= 0xffffff00: 32; v == -1: 64; v != 0: 128.
@inline(never) public func s243_weights32(_ a: Int) -> Int {
    let v = Int32(truncatingIfNeeded: a), u = UInt32(truncatingIfNeeded: a)
    var r = 0
    if v < -128 { r |= 1 }
    if v > 127 { r |= 2 }
    if v >= 0x7fffffff { r |= 4 }
    if v <= Int32.min { r |= 8 }
    if u > 0x7fffffff { r |= 16 }
    if u >= 0xffffff00 { r |= 32 }
    if v == -1 { r |= 64 }
    if v != 0 { r |= 128 }
    return r
}
// 244 and at 8 bits: v = Int8(a), u = UInt8(a). v < -1: 1; v > 1: 2; v >= 127: 4;
// v <= -128: 8; u > 127: 16; u >= 0xf0: 32; u < 2: 64; v == -1: 128.
@inline(never) public func s244_weights8(_ a: Int) -> Int {
    let v = Int8(truncatingIfNeeded: a), u = UInt8(truncatingIfNeeded: a)
    var r = 0
    if v < -1 { r |= 1 }
    if v > 1 { r |= 2 }
    if v >= 127 { r |= 4 }
    if v <= -128 { r |= 8 }
    if u > 127 { r |= 16 }
    if u >= 0xf0 { r |= 32 }
    if u < 2 { r |= 64 }
    if v == -1 { r |= 128 }
    return r
}

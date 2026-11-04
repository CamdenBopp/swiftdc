// A float's bit pattern read as an integer. `fmov x8, d0` (or `fmov w8, s0`)
// moves the IEEE bits into a general register, where every later operation
// and comparison is an integer one. The truth below is written per function:
// the decompiler must render the moved value as a bit pattern and its
// constants as integers, never as the float and float literals.

@inline(never) func sink(_ x: Int) { print(x) }
@inline(never) func sinkPair(_ x: Double, _ i: Int) { print(x, i) }

// -O `Int(a)`: `fmov x8, d0; and x8, x8, #0x7fffffffffffffff;
// mov x9, #0x7fefffffffffffff; cmp x8, x9; b.gt trap`. A signed integer
// compare of the magnitude bits: traps iff a is NaN or infinite. Read as a
// float compare against 1.7976931348623157e+308 it would not trap on NaN.
@inline(never) public func truncatingConversion(_ a: Double) { sinkPair(a, Int(a)) }

// `fmov x8, d0; and x8, x8, #0xff; cmp x8, #7; b.ne`: taken iff the low byte
// of the bits is not 7.
@inline(never) public func lowByte(_ a: Double) {
    if a.bitPattern & 0xff == 7 { sink(1) } else { sink(2) }
}

// `fmov x8, d0; cmp x8, #0x65; b.lo`: an unsigned compare of the bits. For
// a = 1.0 (bits 0x3ff0000000000000) the bits are above 100.
@inline(never) public func bitsAbove(_ a: Double) {
    if a.bitPattern > 100 { sink(7) } else { sink(8) }
}

// `fmov x8, d0; lsr x8, x8, #52; cmp x8, #0x3ff; b.ne`: the sign and
// exponent field compared with 1023.
@inline(never) public func exponentField(_ a: Double) {
    if (a.bitPattern >> 52) == 0x3ff { sink(9) } else { sink(10) }
}

// The Float form: `fmov w8, s0; and w8, w8, #0xff; cmp w8, #7`.
@inline(never) public func floatLowByte(_ a: Float) {
    if a.bitPattern & 0xff == 7 { sink(11) } else { sink(12) }
}

// -Onone spills the Double and reloads its low byte, with no `fmov`:
// `str d0, [sp]; ldrb w8, [sp]; subs x8, x8, #0x7; b.ne`. Taken iff the low
// byte of the bits is not 7.
@inline(never) public func bitCastLowByte(_ a: Double) {
    if unsafeBitCast(a, to: Int.self) & 0xff == 7 { sink(13) } else { sink(14) }
}

// -Onone, the same spill and a whole reload, byte-reversed:
// `str d0, [sp]; ldr x8, [sp]; rev x8, x8; subs x8, x8, #0x7`. Taken iff
// the byte-reversed bits are not 7.
@inline(never) public func bitCastByteSwapped(_ a: Double) {
    if unsafeBitCast(a, to: Int.self).byteSwapped == 7 { sink(15) } else { sink(16) }
}

// The bits compared whole with no operator between, against a NaN payload so
// the compiler cannot use `fcmp`: `fmov x8, d0; cmp x8, x9; cinc x0, x8, ne`.
// 18 iff the bits are not 0x7ff8000000000001; that constant is an integer,
// not the Double `nan` (as a float compare, `a != nan` is always true).
@inline(never) public func bitsEqualPayload(_ a: Double) {
    if a.bitPattern == 0x7ff8000000000001 { sink(17) } else { sink(18) }
}

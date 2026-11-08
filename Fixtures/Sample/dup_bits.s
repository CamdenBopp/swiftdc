// `dup` of a general register into a vector register, returned as a
// Double: `DupBits.bitsToDouble(_: UInt64) -> Double` is `dup v0.2d, x0;
// ret`. True behaviour: the result is the integer's bits read as a Double,
// `Double(bitPattern: bits)` (native execution returns 1.0, 2.0 and -1.0
// for 0x3ff0000000000000, 0x4000000000000000 and 0xbff0000000000000),
// not the integer's value. `bitsToInt` moves the lane back with `fmov x0,
// d0` and returns the bits unchanged.
.text
.globl _$s7DupBits12bitsToDoubleySds6UInt64VF
.p2align 2
_$s7DupBits12bitsToDoubleySds6UInt64VF:
  dup v0.2d, x0
  ret

.globl _$s7DupBits9bitsToIntys6UInt64VADF
.p2align 2
_$s7DupBits9bitsToIntys6UInt64VADF:
  dup v1.2d, x0
  fmov x0, d1
  ret

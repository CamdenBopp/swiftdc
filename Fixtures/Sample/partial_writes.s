// Writes that replace part of a value. Every probe takes (x0, x1) and
// returns x0. Native execution is the oracle: the tracer may decline a
// probe's result but never claim a different one.
.text
.p2align 2

// movk replaces one 16-bit field and keeps the rest of the register.
// True result: (x0 & ~0xffff) | 1.
.globl _movk_argument_low
_movk_argument_low:
  movk x0, #1
  ret

// True result: (x0 & ~(0xffff << 48)) | (0x1234 << 48).
.globl _movk_argument_high
_movk_argument_high:
  movk x0, #0x1234, lsl #48
  ret

// The W form zero-extends. True result: (x0 & 0xffff) | 0x10000.
.globl _movk_argument_w
_movk_argument_w:
  movk w0, #1, lsl #16
  ret

// The register holds a value the tracer does not model (rbit). True
// result: (rbit(x0) & ~0xffff) | 1.
.globl _movk_unmodelled
_movk_unmodelled:
  rbit x8, x0
  movk x8, #1
  mov x0, x8
  ret

// Control: a constant built with mov/movk. True result: 0x50007.
.globl _movk_constant
_movk_constant:
  mov x0, #0x50000
  movk x0, #7
  ret

// Values known only at a width: writes that replace part of a register,
// and frame slots and flags that paths set at different widths. Every
// probe takes (x0, x1) and returns x0. Native execution is the oracle: the
// tracer may decline a probe's result but never claim a different one.
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

// A frame slot stored as eight bytes on one path and four on the other,
// then read as eight. The branch tests a value the tracer does not model
// (rbit), so the join forms no select. True result: 1 when x1 != 0, else
// 0xffffffff00000001 (the upper half is the earlier store's).
.globl _slot_width_join
_slot_width_join:
  sub sp, sp, #16
  mov x9, #-1
  str x9, [sp]
  mov x8, #1
  rbit x10, x1
  cbz x10, 1f
  str x8, [sp]
  b 2f
1:
  str w8, [sp]
2:
  ldr x0, [sp]
  add sp, sp, #16
  ret

// Control: both paths store eight bytes. True result: 1.
.globl _slot_width_agree
_slot_width_agree:
  sub sp, sp, #16
  mov x9, #-1
  str x9, [sp]
  mov x8, #1
  rbit x10, x1
  cbz x10, 1f
  str x8, [sp]
  b 2f
1:
  str x8, [sp]
2:
  ldr x0, [sp]
  add sp, sp, #16
  ret

// The flags of the same constants compared at 64 bits on one path and 32
// on the other: 0x80000000 - 1 overflows only at 32 bits, so `lt` holds on
// the narrow path alone. True result: 1 when x1 == 0, else 0.
.globl _flags_width_join
_flags_width_join:
  rbit x10, x1
  mov x8, #0x80000000
  cbz x10, 1f
  cmp x8, #1
  b 2f
1:
  cmp w8, #1
2:
  cset x0, lt
  ret

// Control: both paths compare at 32 bits. True result: 1.
.globl _flags_width_agree
_flags_width_agree:
  rbit x10, x1
  mov x8, #0x80000000
  cbz x10, 1f
  cmp w8, #1
  b 2f
1:
  cmp w8, #1
2:
  cset x0, lt
  ret

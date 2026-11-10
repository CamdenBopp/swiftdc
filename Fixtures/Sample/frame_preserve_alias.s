// A saved entry value may also be a word of the object passed to a call.
// These internal fragments intentionally use a nonstandard convention: the
// changed fragment rewrites x19. The public wrappers restore the C ABI and
// return 11 for the write case, 7 for the read-only control. A load in each
// helper keeps its complete memory effect outside the literal-store subset.
.text
.p2align 2

.globl _$s18FramePreserveAlias7changedSiyF
_$s18FramePreserveAlias7changedSiyF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, #7
  bl _frame_preserve_write_fragment
  mov x0, x19
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

.globl _$s18FramePreserveAlias9untouchedSiyF
_$s18FramePreserveAlias9untouchedSiyF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, #7
  bl _frame_preserve_read_fragment
  mov x0, x19
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

.globl _frame_preserve_write_fragment
_frame_preserve_write_fragment:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  // Two words of one local: zero and the incoming x19.
  str x19, [sp, #8]
  str xzr, [sp]
  mov x19, xzr
  mov x0, sp
  bl _frame_preserve_read_then_write_upper
  ldr x19, [sp, #8]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

.globl _frame_preserve_read_fragment
_frame_preserve_read_fragment:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  // Two words of one local: zero and the incoming x19.
  str x19, [sp, #8]
  str xzr, [sp]
  mov x19, xzr
  mov x0, sp
  bl _frame_preserve_read_only
  ldr x19, [sp, #8]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

.globl _frame_preserve_read_then_write_upper
_frame_preserve_read_then_write_upper:
  ldr x9, [x0]
  mov x9, #11
  str x9, [x0, #8]
  ret

.globl _frame_preserve_read_only
_frame_preserve_read_only:
  ldr x9, [x0]
  ret

.data
.p2align 3
.globl _frame_preserve_alias_anchor
_frame_preserve_alias_anchor:
  .quad 0
.subsections_via_symbols

// Resolved register calls to an in-image one-argument function.
// one_arg(x) = x*4 + 9 reads only x0.
// reg_call_stale: x1=7 is scratch left by the caller; truth one_arg(3), not one_arg(3, 7).
// direct_call_stale: same through bl; truth one_arg(3).
// reg_tail_unknown: x0 untouched, truth one_arg(?) (body proves one argument).
.text
.globl _one_arg
.p2align 2
_one_arg:
  lsl x0, x0, #2
  add x0, x0, #9
  ret

.globl _reg_call_stale
.p2align 2
_reg_call_stale:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  adrp x8, _one_arg@PAGE
  add x8, x8, _one_arg@PAGEOFF
  mov x0, #3
  mov x1, #7
  blr x8
  ldp x29, x30, [sp], #16
  ret

.globl _direct_call_stale
.p2align 2
_direct_call_stale:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  mov x0, #3
  mov x1, #7
  bl _one_arg
  ldp x29, x30, [sp], #16
  ret

.globl _reg_tail_unknown
.p2align 2
_reg_tail_unknown:
  adrp x16, _one_arg@PAGE
  add x16, x16, _one_arg@PAGEOFF
  br x16

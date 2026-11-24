// A callee that stores above the sp it was entered with writes its
// caller's frame, with no address of it passed. Each probe stores 3 in its
// own [sp, #8], calls, and returns what it loads back from that slot.
//
// _frame_reach_direct_probe   -> 99: the callee stores at its entry sp + 8.
// _frame_reach_through_probe  -> 99: the callee's own callee does, from
//                                16 bytes further down.
// _frame_reach_forward_probe  -> 99: the callee stores above, then leaves by
//                                a tail branch to a body that reads x1.
// _frame_reach_clobber_probe  -> 99: the callee stores above, then calls a
//                                body that overwrites x19.
// _frame_reach_indexed_probe  -> 99: the callee stores at sp indexed by a
//                                register, which nothing bounds.
// _frame_reach_control_probe  -> 3:  the callee stores inside its own frame.
.text
.p2align 2
.globl _frame_reach_direct_probe
_frame_reach_direct_probe:
  sub sp, sp, #32
  str x30, [sp, #24]
  mov x9, #3
  str x9, [sp, #8]
  bl _frame_reach_store_above
  ldr x0, [sp, #8]
  ldr x30, [sp, #24]
  add sp, sp, #32
  ret

.p2align 2
.globl _frame_reach_through_probe
_frame_reach_through_probe:
  sub sp, sp, #32
  str x30, [sp, #24]
  mov x9, #3
  str x9, [sp, #8]
  bl _frame_reach_wrapper
  ldr x0, [sp, #8]
  ldr x30, [sp, #24]
  add sp, sp, #32
  ret

.p2align 2
.globl _frame_reach_control_probe
_frame_reach_control_probe:
  sub sp, sp, #32
  str x30, [sp, #24]
  mov x9, #3
  str x9, [sp, #8]
  bl _frame_reach_quiet
  ldr x0, [sp, #8]
  ldr x30, [sp, #24]
  add sp, sp, #32
  ret

.p2align 2
.globl _frame_reach_forward_probe
_frame_reach_forward_probe:
  sub sp, sp, #32
  str x30, [sp, #24]
  mov x9, #3
  str x9, [sp, #8]
  bl _frame_reach_store_forward
  ldr x0, [sp, #8]
  ldr x30, [sp, #24]
  add sp, sp, #32
  ret

.p2align 2
.globl _frame_reach_clobber_probe
_frame_reach_clobber_probe:
  sub sp, sp, #32
  str x30, [sp, #24]
  mov x9, #3
  str x9, [sp, #8]
  bl _frame_reach_store_clobber
  ldr x0, [sp, #8]
  ldr x30, [sp, #24]
  add sp, sp, #32
  ret

.p2align 2
.globl _frame_reach_indexed_probe
_frame_reach_indexed_probe:
  sub sp, sp, #32
  str x30, [sp, #24]
  mov x9, #3
  str x9, [sp, #8]
  bl _frame_reach_store_indexed
  ldr x0, [sp, #8]
  ldr x30, [sp, #24]
  add sp, sp, #32
  ret

.p2align 2
.globl _frame_reach_store_indexed
_frame_reach_store_indexed:
  mov x9, #99
  mov x10, #1
  str x9, [sp, x10, lsl #3]
  ret

.p2align 2
.globl _frame_reach_store_forward
_frame_reach_store_forward:
  mov x9, #99
  str x9, [sp, #8]
  b _frame_reach_reader

.p2align 2
.globl _frame_reach_reader
_frame_reach_reader:
  mov x0, x1
  ret

.p2align 2
.globl _frame_reach_store_clobber
_frame_reach_store_clobber:
  sub sp, sp, #16
  str x30, [sp, #8]
  mov x9, #99
  str x9, [sp, #24]
  bl _frame_reach_overwrites_x19
  ldr x30, [sp, #8]
  add sp, sp, #16
  ret

.p2align 2
.globl _frame_reach_overwrites_x19
_frame_reach_overwrites_x19:
  mov x19, #1
  ret

.p2align 2
.globl _frame_reach_store_above
_frame_reach_store_above:
  mov x9, #99
  str x9, [sp, #8]
  ret

.p2align 2
.globl _frame_reach_wrapper
_frame_reach_wrapper:
  sub sp, sp, #16
  str x30, [sp, #8]
  bl _frame_reach_store_far
  ldr x30, [sp, #8]
  add sp, sp, #16
  ret

.p2align 2
.globl _frame_reach_store_far
_frame_reach_store_far:
  mov x9, #99
  str x9, [sp, #24]
  ret

.p2align 2
.globl _frame_reach_quiet
_frame_reach_quiet:
  sub sp, sp, #16
  mov x9, #99
  str x9, [sp, #8]
  add sp, sp, #16
  ret
.subsections_via_symbols

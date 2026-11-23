.text
.p2align 2
// Public C-callable reductions restore the platform frame record. Internal
// fragments deliberately make preservation unprovable without changing the
// actual FP. A later fragment can still use that FP to reach a negative offset.
.globl _$s8FrameMay10directCellSiyF
_$s8FrameMay10directCellSiyF:
  sub sp, sp, #64
  stp x19, x20, [sp, #32]
  stp x29, x30, [sp, #48]
  add x29, sp, #48
  mov x9, #7
  str x9, [sp, #8]
  str x29, [sp, #16]
  add x0, sp, #16
  bl _frame_may_restore_from_cell
  bl _frame_may_write_through_fp
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #48]
  ldp x19, x20, [sp, #32]
  add sp, sp, #64
  ret

.globl _$s8FrameMay10shadowSaveSiyF
_$s8FrameMay10shadowSaveSiyF:
  sub sp, sp, #64
  stp x19, x20, [sp, #32]
  stp x29, x30, [sp, #48]
  add x29, sp, #48
  mov x9, #7
  str x9, [sp, #8]
  bl _frame_may_opaque_restore
  bl _frame_may_write_through_fp
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #48]
  ldp x19, x20, [sp, #32]
  add sp, sp, #64
  ret

.globl _frame_may_restore_from_cell
_frame_may_restore_from_cell:
  ldr x29, [x0]
  ret

.globl _frame_may_opaque_restore
_frame_may_opaque_restore:
  stur x29, [sp, #-8]
  mov x29, #0
  mov x10, x30
  bl _frame_may_unknown_no_write
  mov x30, x10
  ldur x29, [sp, #-8]
  ret

.globl _frame_may_unknown_no_write
_frame_may_unknown_no_write:
  ldr x9, [sp]
  ret

.globl _frame_may_write_through_fp
_frame_may_write_through_fp:
  ldur x9, [x29, #-40]
  mov x9, #99
  stur x9, [x29, #-40]
  ret

// Losing FP preservation can also hide a write by that same callee. It
// reloads the FP from a cell; no incoming-FP use is proven by the body scan.
.globl _$s8FrameMay8sameCallSiyF
_$s8FrameMay8sameCallSiyF:
  sub sp, sp, #64
  stp x29, x30, [sp, #48]
  add x29, sp, #48
  mov x9, #7
  str x9, [sp, #8]
  str x29, [sp, #16]
  add x0, sp, #16
  bl _frame_may_reload_and_write
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #48]
  add sp, sp, #64
  ret

.globl _frame_may_reload_and_write
_frame_may_reload_and_write:
  ldr x29, [x0]
  ldur x9, [x29, #-40]
  mov x9, #99
  stur x9, [x29, #-40]
  ret

// A complete register-only body proves it leaves FP and memory intact.
.globl _$s8FrameMay10keepProvenSiyF
_$s8FrameMay10keepProvenSiyF:
  sub sp, sp, #64
  stp x29, x30, [sp, #48]
  add x29, sp, #48
  mov x9, #7
  str x9, [sp, #8]
  bl _frame_may_known_no_write
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #48]
  add sp, sp, #64
  ret

.globl _frame_may_known_no_write
_frame_may_known_no_write:
  mov x13, #9
  ret

// An unsupported memory read does not itself lose FP preservation. Its
// ordinary private local must survive without a frame-pointer MAY escape.
.globl _$s8FrameMay12keepUnprovedSiyF
_$s8FrameMay12keepUnprovedSiyF:
  sub sp, sp, #64
  stp x29, x30, [sp, #48]
  add x29, sp, #48
  str xzr, [sp]
  mov x9, #7
  str x9, [sp, #8]
  bl _frame_may_unknown_no_write
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #48]
  add sp, sp, #64
  ret

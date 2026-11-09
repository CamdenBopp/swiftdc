.text
.p2align 2
// Each C-callable wrapper reads the most recent callee's below-SP store.
// The helpers stay within Darwin's128-byte red zone; the caller makes no
// ABI claim that such memory survives a call. An unproved callee can reuse it.

.globl _$s13StackLifetime12reuseUnknownSiyF
_$s13StackLifetime12reuseUnknownSiyF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  str xzr, [sp]
  mov x12, #9
  bl _stack_lifetime_seed
  bl _stack_lifetime_unproved
  ldur x0, [sp, #-8]
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret

.globl _$s13StackLifetime11reuseProvenSiyF
_$s13StackLifetime11reuseProvenSiyF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  str xzr, [sp]
  mov x12, #9
  bl _stack_lifetime_seed
  bl _stack_lifetime_no_write
  ldur x0, [sp, #-8]
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret

.globl _$s13StackLifetime10reuseExactSiyF
_$s13StackLifetime10reuseExactSiyF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  str xzr, [sp]
  mov x12, #9
  bl _stack_lifetime_seed
  bl _stack_lifetime_exact
  ldur x0, [sp, #-8]
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret

.globl _stack_lifetime_seed
_stack_lifetime_seed:
  mov x9, #7
  stur x9, [sp, #-8]
  ret

// The load makes the whole body unsupported by the current complete-call
// subset. Its result is ignored; native execution still writes99 belowSP.
.globl _stack_lifetime_unproved
_stack_lifetime_unproved:
  ldr x9, [sp]
  mov x9, #99
  stur x9, [sp, #-8]
  ret

// A complete register-only literal body proves this call writes no memory.
.globl _stack_lifetime_no_write
_stack_lifetime_no_write:
  mov x13, #9
  ret

.globl _stack_lifetime_exact
_stack_lifetime_exact:
  mov x9, #99
  stur x9, [sp, #-8]
  ret

// Caller-allocated storage aboveSP survives a callee's belowSP write.
.globl _$s13StackLifetime10reuseAboveSiyF
_$s13StackLifetime10reuseAboveSiyF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  mov x9, #7
  str x9, [sp, #8]
  bl _stack_lifetime_unproved
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret

// The unknown call-timeSP can reuse the old word for0, but not for16.
// Both inputs are aligned; x19/x20 and the frame record are restored.
.globl _$s13StackLifetime12reuseDynamicyS2iF
_$s13StackLifetime12reuseDynamicyS2iF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x0
  str xzr, [sp]
  bl _stack_lifetime_seed
  sub sp, sp, x20
  bl _stack_lifetime_unproved
  mov sp, x19
  ldur x0, [sp, #-8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

.globl _$s13StackLifetime17reusePreservationSiyF
_$s13StackLifetime17reusePreservationSiyF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, #7
  bl _stack_lifetime_loses_save
  mov x0, x19
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

.globl _$s13StackLifetime16keepPreservationSiyF
_$s13StackLifetime16keepPreservationSiyF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, #7
  bl _stack_lifetime_keeps_save
  mov x0, x19
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// Internal nonstandard fragment changes x19; its public wrapper restores ABI.
.globl _stack_lifetime_loses_save
_stack_lifetime_loses_save:
  sub sp, sp, #32
  str x30, [sp, #16]
  str xzr, [sp]
  stur x19, [sp, #-8]
  mov x19, xzr
  bl _stack_lifetime_unproved
  ldur x19, [sp, #-8]
  ldr x30, [sp, #16]
  add sp, sp, #32
  ret

// Internal nonstandard fragment changes x19; its public wrapper restores ABI.
.globl _stack_lifetime_keeps_save
_stack_lifetime_keeps_save:
  sub sp, sp, #32
  str x30, [sp, #16]
  str xzr, [sp]
  stur x19, [sp, #-8]
  mov x19, xzr
  bl _stack_lifetime_no_write
  ldur x19, [sp, #-8]
  ldr x30, [sp, #16]
  add sp, sp, #32
  ret

.globl _$s13StackLifetime17reuseDynamicAboveyS2iF
_$s13StackLifetime17reuseDynamicAboveyS2iF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x0
  str xzr, [sp]
  mov x9, #7
  str x9, [sp, #8]
  sub sp, sp, x20
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

.globl _$s13StackLifetime12reusePointerSiyF
_$s13StackLifetime12reusePointerSiyF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  mov x9, #7
  str x9, [sp, #8]
  add x9, sp, #8
  stur x9, [sp, #-8]
  bl _stack_lifetime_read_pointer
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret

.globl _stack_lifetime_read_pointer
_stack_lifetime_read_pointer:
  ldur x9, [sp, #-8]
  mov x10, #99
  str x10, [x9]
  ret
.subsections_via_symbols

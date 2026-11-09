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

// Swift's dynamic allocation: `___chkstk_darwin` probes x9 bytes below sp
// and faults on wrap or overflow, so its return proves `sp - x9` is a
// valid downward allocation. The 16-byte rounding of that size moves sp
// below the frame top k, and the next callee's stack starts below k: the
// word at k + 8 survives. Native: 7 for any small n.
.globl _$s13StackLifetime11reuseProbedyS2iF
_$s13StackLifetime11reuseProbedyS2iF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x9, #7
  str x9, [sp, #8]
  mov x9, x0
  add x8, x9, #15
  and x8, x8, #0xfffffffffffffff0
  bl ___chkstk_darwin
  mov x9, sp
  sub x8, x9, x8
  mov sp, x8
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// The probed size itself, unrounded, is also a proven downward move.
// Native: 7 for any multiple of 16 (sp stays aligned for the callee).
.globl _$s13StackLifetime14reuseProbedRawyS2iF
_$s13StackLifetime14reuseProbedRawyS2iF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x9, #7
  str x9, [sp, #8]
  mov x8, x0
  mov x9, x8
  bl ___chkstk_darwin
  mov x9, sp
  sub x8, x9, x8
  mov sp, x8
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// Two probed allocations stacked: each moves sp down from the last, so
// the callee stack still starts below k. Native: 7 for any small n.
.globl _$s13StackLifetime16reuseProbedTwiceyS2iF
_$s13StackLifetime16reuseProbedTwiceyS2iF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x0
  mov x9, #7
  str x9, [sp, #8]
  mov x9, x20
  add x8, x9, #15
  and x8, x8, #0xfffffffffffffff0
  bl ___chkstk_darwin
  mov x9, sp
  sub x8, x9, x8
  mov sp, x8
  mov x9, x20
  add x8, x9, #15
  and x8, x8, #0xfffffffffffffff0
  bl ___chkstk_darwin
  mov x9, sp
  sub x8, x9, x8
  mov sp, x8
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// A probed allocation on top of an unprobed `sub sp, sp, x20`: the first
// move is unproved. The word at k + 8 is stored after both, through x19.
// With m = -16 and n = 0, sp ends 16 above k and the next callee writes 99
// over it.
.globl _$s13StackLifetime12probeStackedyS2i_SitF
_$s13StackLifetime12probeStackedyS2i_SitF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x1
  sub sp, sp, x20
  mov x9, x0
  add x8, x9, #15
  and x8, x8, #0xfffffffffffffff0
  bl ___chkstk_darwin
  mov x9, sp
  sub x8, x9, x8
  mov sp, x8
  mov x9, #7
  str x9, [x19, #8]
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// The probe proves n bytes, but sp moves by m. With m = -16 sp moves up
// and the next callee writes 99 over the word at k + 8.
.globl _$s13StackLifetime13probeMismatchyS2i_SitF
_$s13StackLifetime13probeMismatchyS2i_SitF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x1
  mov x9, #7
  str x9, [sp, #8]
  mov x9, x0
  bl ___chkstk_darwin
  mov x9, sp
  sub x8, x9, x20
  mov sp, x8
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// The probed size is read from the global, then *q = m (q == &global) and
// the size is read again: the same load, a different value. With m = -16 sp moves up
// and the next callee writes 99 over the word at k + 8.
.globl _$s13StackLifetime11probeReloadySiSpySiG_SitF
_$s13StackLifetime11probeReloadySiSpySiG_SitF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x0
  mov x9, #7
  str x9, [sp, #8]
  adrp x10, _stack_lifetime_size@PAGE
  ldr x9, [x10, _stack_lifetime_size@PAGEOFF]
  bl ___chkstk_darwin
  str x1, [x2]
  adrp x10, _stack_lifetime_size@PAGE
  ldr x8, [x10, _stack_lifetime_size@PAGEOFF]
  mov x9, sp
  sub x8, x9, x8
  mov sp, x8
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// As probeReload, but a call stores m through q: a call between the probe
// and the allocation can change what the reload reads.
.globl _$s13StackLifetime9probeCallySiSpySiG_SitF
_$s13StackLifetime9probeCallySiSpySiG_SitF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x0
  mov x9, #7
  str x9, [sp, #8]
  adrp x10, _stack_lifetime_size@PAGE
  ldr x9, [x10, _stack_lifetime_size@PAGEOFF]
  bl ___chkstk_darwin
  mov x0, x2
  bl _stack_lifetime_store
  adrp x10, _stack_lifetime_size@PAGE
  ldr x8, [x10, _stack_lifetime_size@PAGEOFF]
  mov x9, sp
  sub x8, x9, x8
  mov sp, x8
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// The load makes the body unsupported; it stores x1 through x0.
.globl _stack_lifetime_store
_stack_lifetime_store:
  ldr x9, [sp]
  str x1, [x0]
  ret

// A probed allocation of the global's size, sp restored, *q = m, then the same reload
// allocates again with no probe: the second sp spells the first. With
// m = -16 sp moves up and the next callee writes 99 over the word at k + 8.
.globl _$s13StackLifetime10probeTwiceySiSpySiG_SitF
_$s13StackLifetime10probeTwiceySiSpySiG_SitF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x0
  mov x9, #7
  str x9, [sp, #8]
  adrp x10, _stack_lifetime_size@PAGE
  ldr x9, [x10, _stack_lifetime_size@PAGEOFF]
  bl ___chkstk_darwin
  adrp x10, _stack_lifetime_size@PAGE
  ldr x8, [x10, _stack_lifetime_size@PAGEOFF]
  mov x9, sp
  sub x8, x9, x8
  mov sp, x8
  mov sp, x19
  str x1, [x2]
  adrp x10, _stack_lifetime_size@PAGE
  ldr x8, [x10, _stack_lifetime_size@PAGEOFF]
  mov x9, sp
  sub x8, x9, x8
  mov sp, x8
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

.data
.p2align 3
.globl _stack_lifetime_size
_stack_lifetime_size:
  .quad 16

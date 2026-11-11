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

// Swift spills the new sp to a frame slot between the probe and the move
// (`stur x9, [x29, #-0xb0]; mov sp, x9`). A store to an unescaped slot of
// this frame cannot change the probed size, so the proof holds. Native: 7.
.globl _$s13StackLifetime18reuseProbedSpilledyS2iF
_$s13StackLifetime18reuseProbedSpilledyS2iF:
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
  str x8, [x19]
  mov sp, x8
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// A local's address escapes before the probe (a stale `add x8, sp, #16`,
// frame offset -48, passed to a call), and the new sp is then spilled to
// [sp], at -64. An escaped local reaches only upward from itself, so the
// spill cannot change what the size was read from and the proof holds.
// Native: 7.
.globl _$s13StackLifetime25reuseProbedSpilledEscapedyS2iF
_$s13StackLifetime25reuseProbedSpilledEscapedyS2iF:
  sub sp, sp, #64
  stp x19, x20, [sp, #32]
  stp x29, x30, [sp, #48]
  add x29, sp, #48
  mov x19, sp
  mov x20, x0
  mov x9, #7
  str x9, [sp, #8]
  add x8, sp, #16
  bl _stack_lifetime_no_write
  mov x9, x20
  add x8, x9, #15
  and x8, x8, #0xfffffffffffffff0
  bl ___chkstk_darwin
  mov x9, sp
  sub x8, x9, x8
  str x8, [x19]
  mov sp, x8
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #48]
  ldp x19, x20, [sp, #32]
  add sp, sp, #64
  ret

// The control: the size lives in a local whose address escaped and comes
// back as a call result. A store to that local (reachable by the escape)
// changes what the size is reloaded from: storing -16 and reloading moves
// sp up by 16, into the frame, and the unproved callee overwrites the 7.
// The proof must end at the store. Native: 99.
.globl _$s13StackLifetime18probeSpillReachingyS2iF
_$s13StackLifetime18probeSpillReachingyS2iF:
  sub sp, sp, #64
  stp x19, x20, [sp, #32]
  stp x29, x30, [sp, #48]
  add x29, sp, #48
  mov x19, sp
  mov x9, #7
  str x9, [sp, #8]
  str x0, [sp, #16]
  add x0, sp, #16
  bl _stack_lifetime_launder
  mov x20, x0
  ldr x9, [x20]
  bl ___chkstk_darwin
  mov x9, #-16
  str x9, [x19, #16]
  ldr x10, [x20]
  add x8, x10, #15
  and x8, x8, #0xfffffffffffffff0
  mov x9, sp
  sub x8, x9, x8
  mov sp, x8
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #48]
  ldp x19, x20, [sp, #32]
  add sp, sp, #64
  ret

// Returns its argument through arithmetic no analysis follows.
.globl _stack_lifetime_launder
_stack_lifetime_launder:
  eor x9, x0, #1
  eor x0, x9, #1
  ret

// Seven probed allocations in a row, one per buffer, as a synthesized
// Codable init makes one per keyed container. Each nests sp one
// subtraction deeper; the seventh went past the arithmetic depth limit and
// sp became unknown, so the call forgot the frame. Native: 7.
.globl _$s13StackLifetime16reuseProbedChainyS2iF
_$s13StackLifetime16reuseProbedChainyS2iF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x0
  mov x9, #7
  str x9, [sp]
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
  mov x9, x20
  add x8, x9, #15
  and x8, x8, #0xfffffffffffffff0
  bl ___chkstk_darwin
  mov x9, sp
  sub x8, x9, x8
  mov sp, x8
  bl _stack_lifetime_unproved
  ldr x0, [x19]
  mov sp, x19
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// The control: the rebased sp is "some amount below the base", never the
// base itself. The fourth allocation of a chain is the one rebased, and a
// store at its bottom may land on the base word (every size zero), so it
// cannot read as 5 or 7. Native: 7 for any size above zero, 5 for zero.
.globl _$s13StackLifetime15probeChainStoreyS2iF
_$s13StackLifetime15probeChainStoreyS2iF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x0
  mov x9, #7
  str x9, [sp]
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
  mov x9, #5
  str x9, [sp]
  ldr x0, [x19]
  mov sp, x19
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// A size three loads deep (`**pp` then one more load: metadata, its
// value-witness table, the table's size word in a Swift body) is unknown to
// the tracer, which models two loads through an argument. The preservation
// summary names a size by its load and proves the allocation, and the
// tracer takes that proof for the move. The probe is called through the
// GOT, as Swift calls it. Native: 7 for any small n.
.globl _$s13StackLifetime19reuseProbedDeepSizeyS2iF
_$s13StackLifetime19reuseProbedDeepSizeyS2iF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x9, #7
  str x9, [sp, #8]
  ldr x8, [x0]
  ldr x8, [x8]
  ldr x8, [x8]
  mov x9, x8
  adrp x16, ___chkstk_darwin@GOTPAGE
  ldr x16, [x16, ___chkstk_darwin@GOTPAGEOFF]
  blr x16
  add x8, x8, #15
  and x8, x8, #0xfffffffffffffff0
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

// The control: the size is overwritten through another pointer to it
// (x1) after the probe and reloaded, so the summary proves nothing, and the
// reloaded -16 moves sp up into the frame. Native: 99.
.globl _$s13StackLifetime15probeDeepReloadyS2i_SitF
_$s13StackLifetime15probeDeepReloadyS2i_SitF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x0
  mov x9, #7
  str x9, [sp, #8]
  ldr x8, [x20]
  ldr x8, [x8]
  ldr x8, [x8]
  mov x9, x8
  adrp x16, ___chkstk_darwin@GOTPAGE
  ldr x16, [x16, ___chkstk_darwin@GOTPAGEOFF]
  blr x16
  mov x10, #-16
  str x10, [x1]
  ldr x8, [x20]
  ldr x8, [x8]
  ldr x8, [x8]
  add x8, x8, #15
  and x8, x8, #0xfffffffffffffff0
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

// Outgoing stack arguments pushed and popped below a probed allocation,
// by an immediate (`sub sp, sp, #0x20 ... add sp, sp, #0x20`) and by
// writeback (`str xzr, [sp, #-0x10]! ... ldr x9, [sp], #0x10`). sp still
// hangs below the allocation's base around every call. Native: 7.
.globl _$s13StackLifetime17reuseProbedPushedyS2iF
_$s13StackLifetime17reuseProbedPushedyS2iF:
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
  sub sp, sp, #0x20
  bl _stack_lifetime_unproved
  add sp, sp, #0x20
  str xzr, [sp, #-0x10]!
  bl _stack_lifetime_unproved
  ldr x9, [sp], #0x10
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// The control: a pop past the push (`sub sp, sp, #0x10; add sp, sp,
// #0x20`) can leave sp above the allocation's base when its size is zero,
// and the callee's store below sp then reaches the 7. Native: 99 for
// size 0, 7 for 32.
.globl _$s13StackLifetime16probePopPastPushyS2iF
_$s13StackLifetime16probePopPastPushyS2iF:
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
  sub sp, sp, #0x10
  add sp, sp, #0x20
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// A second probe of an unknown size (`***pp`) ends the first probe's proof:
// the allocation after it reuses the first, rounded size (x12), which this
// probe did not cover. Native: 7, but nothing proves it; `return ?`.
.globl _$s13StackLifetime14probeStaleSizeyS2i_SitF
_$s13StackLifetime14probeStaleSizeyS2i_SitF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x0
  mov x21, x1
  mov x9, #7
  str x9, [sp, #8]
  mov x9, x20
  add x12, x9, #15
  and x12, x12, #0xfffffffffffffff0
  bl ___chkstk_darwin
  mov x9, sp
  sub x8, x9, x12
  mov sp, x8
  ldr x9, [x21]
  ldr x9, [x9]
  ldr x9, [x9]
  bl ___chkstk_darwin
  mov x9, sp
  sub x8, x9, x12
  mov sp, x8
  bl _stack_lifetime_unproved
  mov sp, x19
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret

// Two allocations of a size three loads deep. The summary proves both,
// but sp stays `below(k)` across the second move, and a move whose
// abstract value did not change went unreported to the tracer. Native: 7.
.globl _$s13StackLifetime20reuseProbedDeepTwiceyS2iF
_$s13StackLifetime20reuseProbedDeepTwiceyS2iF:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x19, sp
  mov x20, x0
  mov x9, #7
  str x9, [sp, #8]
  ldr x8, [x20]
  ldr x8, [x8]
  ldr x8, [x8]
  mov x9, x8
  adrp x16, ___chkstk_darwin@GOTPAGE
  ldr x16, [x16, ___chkstk_darwin@GOTPAGEOFF]
  blr x16
  add x8, x8, #15
  and x8, x8, #0xfffffffffffffff0
  mov x9, sp
  sub x8, x9, x8
  mov sp, x8
  ldr x8, [x20]
  ldr x8, [x8]
  ldr x8, [x8]
  mov x9, x8
  adrp x16, ___chkstk_darwin@GOTPAGE
  ldr x16, [x16, ___chkstk_darwin@GOTPAGEOFF]
  blr x16
  add x8, x8, #15
  and x8, x8, #0xfffffffffffffff0
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

// Two spilled probed allocations: the first leaves a dynamic-allocation
// marker, which is no escape, so the second spill keeps its proof too.
// Native: 7.
.globl _$s13StackLifetime23reuseProbedSpilledTwiceyS2iF
_$s13StackLifetime23reuseProbedSpilledTwiceyS2iF:
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
  str x8, [x19]
  mov sp, x8
  mov x9, x20
  add x8, x9, #15
  and x8, x8, #0xfffffffffffffff0
  bl ___chkstk_darwin
  mov x9, sp
  sub x8, x9, x8
  str x8, [x19]
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

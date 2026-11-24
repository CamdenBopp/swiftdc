// A callee-saved register a body stores and never loads back, reached
// through a second body. No default-convention function does this: it is
// what a body compiled for a convention with fewer preserved registers
// looks like (clang's preserve_none takes arguments in x20 and up, spills
// them and reuses the registers), and what an outlined fragment that parks
// a value does. The store is no save, because nothing reads it back.
//
// Each Swift caller is (Int, Int) -> Int. It keeps arg0 in x19 across one
// call and returns x19; it saves and restores its own caller's x19, so
// every function here can be called natively.
//
// True behaviour, with (1, 2):
//   direct    2  calls spill_leaf, which spills x19 and writes x19 = arg1
//   relayed   2  reaches spill_leaf through a framed body that calls it
//   tailed    2  reaches spill_leaf through a body that tail-branches to it
//   parked    2  reaches park_leaf, which writes x19 = arg1 and then
//                stores that value
//   fixed    11  keeps 7 in x19, not arg0; fixed_leaf spills x19 and
//                writes 11
//   saved     1  saved_leaf stores x19, overwrites it and loads it back
//   reloaded  1  veiled_leaf does the same around a store into its own
//                padding, through an address made with orr
//   handed    1  handed_helper saves x19 and x20, lets rewrite replace
//                both, and gets them back from veiled_reload, which loads
//                them from the helper's frame after a store into its own
//                scratch word through an address made with orr
//   restored  1  escaped_helper saves x19 and x20, lets rewrite replace
//                both, stores into its own padding through an address made
//                with orr, and gets them back from clean_reload
//   nearReloaded, nearHanded, nearRestored  1 each: the same three bodies
//                called with no body between. Nothing proves their
//                reloads, so one call away x19 is unknown.
//
// sp is 16-byte aligned at every `orr x9, x9, #8`, so the address is sp + 8.
.text
.p2align 2
.macro caller name, callee
.globl _$s10SpillCarry\name\()yS2i_SitF
_$s10SpillCarry\name\()yS2i_SitF:
 stp x19, x30, [sp, #-16]!
 mov x19, x0
 bl \callee
 mov x0, x19
 ldp x19, x30, [sp], #16
 ret
.endm
// A framed body that calls `callee` and touches no other callee-saved
// register.
.macro relay name, callee
.globl \name
\name:
 stp x29, x30, [sp, #-16]!
 mov x29, sp
 bl \callee
 ldp x29, x30, [sp], #16
 ret
.endm
caller 6direct, _spill_leaf
caller 7relayed, _spill_relay
caller 6tailed, _spill_tail
caller 6parked, _park_relay
caller 5saved, _saved_relay
caller 8reloaded, _veiled_relay
caller 6handed, _handed_relay
caller 8restored, _escaped_relay
caller 12nearReloaded, _veiled_leaf
caller 10nearHanded, _handed_helper
caller 12nearRestored, _escaped_helper

// SpillCarry.fixed(Swift.Int, Swift.Int) -> Swift.Int
// x19 = 7 across the call; returns x19, which fixed_leaf left at 11.
.globl _$s10SpillCarry5fixedyS2i_SitF
_$s10SpillCarry5fixedyS2i_SitF:
 stp x19, x30, [sp, #-16]!
 mov x19, #7
 bl _fixed_relay
 mov x0, x19
 ldp x19, x30, [sp], #16
 ret

// Returns with x19 = x1. The entry x19 stays in the popped slot.
.globl _spill_leaf
_spill_leaf:
 str x19, [sp, #-16]!
 mov x19, x1
 add sp, sp, #16
 ret
relay _spill_relay, _spill_leaf
.globl _spill_tail
_spill_tail:
 b _spill_leaf

// Returns with x19 = x1. The store writes the new value, not the entry one.
.globl _park_leaf
_park_leaf:
 sub sp, sp, #16
 mov x19, x1
 str x19, [sp]
 add sp, sp, #16
 ret
relay _park_relay, _park_leaf

// Returns with x19 = 11.
.globl _fixed_leaf
_fixed_leaf:
 str x19, [sp, #-16]!
 mov x19, #11
 add sp, sp, #16
 ret
relay _fixed_relay, _fixed_leaf

// Returns with x19 as it was entered.
.globl _saved_leaf
_saved_leaf:
 str x19, [sp, #-16]!
 mov x19, x1
 ldr x19, [sp], #16
 ret
relay _saved_relay, _saved_leaf

// Returns with x19 as it was entered: the save is at sp + 16 and the store
// through x9 lands at sp + 8.
.globl _veiled_leaf
_veiled_leaf:
 sub sp, sp, #32
 str x19, [sp, #16]
 mov x19, x1
 mov x9, sp
 orr x9, x9, #8
 str x1, [x9]
 ldr x19, [sp, #16]
 add sp, sp, #32
 ret
relay _veiled_relay, _veiled_leaf

// Returns with x19 = x1 and x20 = x0.
.globl _rewrite
_rewrite:
 mov x19, x1
 mov x20, x0
 ret

// Entered with its caller's x20 and x19 saves at sp and sp + 8; returns
// with both registers loaded from them. The store through x9 lands in the
// 16 bytes this body pushed and popped.
.globl _veiled_reload
_veiled_reload:
 sub sp, sp, #16
 mov x9, sp
 orr x9, x9, #8
 str x1, [x9]
 add sp, sp, #16
 ldp x20, x19, [sp]
 ret

// Returns with x19 and x20 as they were entered.
.globl _handed_helper
_handed_helper:
 stp x20, x19, [sp, #-0x20]!
 stp x29, x30, [sp, #0x10]
 add x29, sp, #0x10
 bl _rewrite
 bl _veiled_reload
 ldp x29, x30, [sp, #0x10]
 add sp, sp, #0x20
 ret
relay _handed_relay, _handed_helper

// Entered with its caller's x20 and x19 saves at sp + 16 and sp + 24;
// returns with both registers loaded from them.
.globl _clean_reload
_clean_reload:
 ldp x20, x19, [sp, #0x10]
 ret

// Returns with x19 and x20 as they were entered: the saves are at sp + 16
// and sp + 24, and the store through x9 lands at sp + 8.
.globl _escaped_helper
_escaped_helper:
 sub sp, sp, #0x30
 stp x20, x19, [sp, #0x10]
 stp x29, x30, [sp, #0x20]
 add x29, sp, #0x20
 bl _rewrite
 mov x9, sp
 orr x9, x9, #8
 str x1, [x9]
 bl _clean_reload
 ldp x29, x30, [sp, #0x20]
 add sp, sp, #0x30
 ret
relay _escaped_relay, _escaped_helper

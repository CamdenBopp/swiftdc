// Authored fragment reductions: incoming pointers may reach caller-owned
// memory at or above entry SP. An eight-byte save crossing SP is not private.
.text
.p2align 2
.macro caller name, fragment
.globl _$s8ABIFrame\name\()yS2i_SitF
_$s8ABIFrame\name\()yS2i_SitF:
 sub sp, sp, #64
 stp x19, x30, [sp, #32]
 mov x19, x0
 mov x0, sp
 bl \fragment
 mov x0, x19
 ldp x19, x30, [sp, #32]
 add sp, sp, #64
 ret
.endm
caller 8positive, _positive_frame_fragment
caller 8straddle, _straddling_frame_fragment
caller 5owned, _owned_frame_fragment
.globl _positive_frame_fragment
_positive_frame_fragment:
 str x19, [sp]
 mov x19, xzr
 str x1, [x0]
 ldr x19, [sp]
 ret
.globl _straddling_frame_fragment
_straddling_frame_fragment:
 stur x19, [sp, #-4]
 mov x19, xzr
 str w1, [x0]
 ldur x19, [sp, #-4]
 ret
.globl _owned_frame_fragment
_owned_frame_fragment:
 str x19, [sp, #-16]!
 mov x19, xzr
 str x1, [x0]
 ldr x19, [sp], #16
 ret
// An incoming pointer can also reach caller-owned saves through a helper.
caller 8callthru, _callthrough_frame_fragment
.globl _callthrough_frame_fragment
_callthrough_frame_fragment:
 str x19, [sp]
 str x30, [sp, #-16]!
 mov x19, xzr
 bl _write_incoming_frame_pointer
 ldr x30, [sp], #16
 ldr x19, [sp]
 ret
.globl _write_incoming_frame_pointer
_write_incoming_frame_pointer:
 str x1, [x0]
 ret

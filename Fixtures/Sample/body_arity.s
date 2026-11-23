// C ABI controls for proved input reads versus possible reads at an opaque
// import. x5=37 is live at every call but is never a source argument.
.text
.globl _body_arity_one
.p2align 2
_body_arity_one:
 stp x19, x30, [sp, #-16]!
 mov x19, x0
 bl _body_arity_opaque_effect
 add x0, x19, #9
 ldp x19, x30, [sp], #16
 ret
.globl _body_arity_zero
.p2align 2
_body_arity_zero:
 str x30, [sp, #-16]!
 bl _body_arity_opaque_effect
 mov x0, #9
 ldr x30, [sp], #16
 ret
.globl _body_arity_third
.p2align 2
_body_arity_third:
 stp x19, x30, [sp, #-16]!
 mov x19, x2
 bl _body_arity_opaque_effect
 add x0, x19, #9
 ldp x19, x30, [sp], #16
 ret
.globl _body_arity_float
.p2align 2
_body_arity_float:
 stp d8, d9, [sp, #-32]!
 str x30, [sp, #16]
 fmov d8, d0
 bl _body_arity_opaque_effect
 fmov d1, #1.0
 fadd d0, d8, d1
 ldr x30, [sp, #16]
 ldp d8, d9, [sp], #32
 ret
.globl _body_arity_mixed
.p2align 2
_body_arity_mixed:
 stp x19, x30, [sp, #-32]!
 str d8, [sp, #16]
 mov x19, x0
 fmov d8, d0
 bl _body_arity_opaque_effect
 ucvtf d1, x19
 fadd d0, d8, d1
 ldr d8, [sp, #16]
 ldp x19, x30, [sp], #32
 ret
.globl _body_arity_closed_one
.p2align 2
_body_arity_closed_one:
 add x0, x0, #9
 ret
.globl _body_arity_closed_float
.p2align 2
_body_arity_closed_float:
 fmov d1, #1.0
 fadd d0, d0, d1
 ret
.globl _body_arity_alias
.p2align 2
_body_arity_alias:
 b _body_arity_closed_one
.globl _body_arity_framed_one
.p2align 2
_body_arity_framed_one:
 stp x29, x30, [sp, #-16]!
 mov x29, sp
 bl _body_arity_closed_one
 ldp x29, x30, [sp], #16
 ret
.globl _body_arity_framed_float
.p2align 2
_body_arity_framed_float:
 stp x29, x30, [sp, #-16]!
 mov x29, sp
 bl _body_arity_closed_float
 ldp x29, x30, [sp], #16
 ret

// One-word callers forward x0; other callers have no source parameters.
// A separate target must prove its own argument words, regardless of x5.
.macro invoke name, target
.globl _body_arity_call_\name
.p2align 2
_body_arity_call_\name:
 str x30, [sp, #-16]!
.endm
.macro finish target
 mov x5, #37
 bl _body_arity_\target
 ldr x30, [sp], #16
 ret
.endm
invoke one, one
finish one
invoke zero, zero
 mov x0, #17
finish zero
invoke third, third
 mov x2, x0
 mov x0, #17
 mov x1, #19
finish third
invoke float, float
 fmov d0, #1.0
finish float
invoke mixed, mixed
 mov x0, #11
 fmov d0, #1.0
finish mixed
invoke closed_one, closed_one
 mov x0, #11
finish closed_one
invoke closed_float, closed_float
 fmov d0, #1.0
finish closed_float
invoke alias, alias
 mov x0, #11
finish alias
invoke framed_one, framed_one
 mov x0, #11
finish framed_one
invoke framed_float, framed_float
 fmov d0, #1.0
finish framed_float

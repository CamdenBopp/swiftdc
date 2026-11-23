// A valid LR-only wrapper forwards an incoming word through an ordinary BL.
// The leaf reads that word. It is not a proof of zero source parameters.
.text
.p2align 2
_sub_BLInput_leaf:
    add x0, x0, #1
    ret
.p2align 2
_sub_BLInput_wrapper:
    str x30, [sp, #-16]!
    bl _sub_BLInput_leaf
    ldr x30, [sp], #16
    ret
.globl _sub_BLInput_caller
.p2align 2
_sub_BLInput_caller:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x8, x9
    bl _sub_BLInput_wrapper
    ldp x29, x30, [sp], #16
    ret
// Same valid BL wrapper in the independent floating-point argument bank.
.p2align 2
_sub_BLInput_fpLeaf:
    fadd d0, d0, d0
    ret
.p2align 2
_sub_BLInput_fpWrapper:
    str x30, [sp, #-16]!
    bl _sub_BLInput_fpLeaf
    ldr x30, [sp], #16
    ret
.globl _sub_BLInput_fpCaller
.p2align 2
_sub_BLInput_fpCaller:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x8, x9
    bl _sub_BLInput_fpWrapper
    ldp x29, x30, [sp], #16
    ret

// Positive controls: exact FP/LR frames already have a finite input proof.
.p2align 2
_sub_BLInput_canonicalGP:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _sub_BLInput_leaf
    ldp x29, x30, [sp], #16
    ret
.p2align 2
_sub_BLInput_canonicalFP:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _sub_BLInput_fpLeaf
    ldp x29, x30, [sp], #16
    ret

// Negative controls consume no incoming argument word in either bank.
.p2align 2
_sub_BLInput_zeroGPLeaf:
    mov x0, #91
    ret
.p2align 2
_sub_BLInput_zeroFPLeaf:
    fmov d0, #1.0
    ret
.p2align 2
_sub_BLInput_zeroGP:
    str x30, [sp, #-16]!
    bl _sub_BLInput_zeroGPLeaf
    ldr x30, [sp], #16
    ret
.p2align 2
_sub_BLInput_zeroFP:
    str x30, [sp, #-16]!
    bl _sub_BLInput_zeroFPLeaf
    ldr x30, [sp], #16
    ret
.p2align 2
_sub_BLInput_overwriteGP:
    str x30, [sp, #-16]!
    mov x0, #73
    bl _sub_BLInput_leaf
    ldr x30, [sp], #16
    ret
.p2align 2
_sub_BLInput_overwriteFP:
    str x30, [sp, #-16]!
    fmov d0, #3.0
    bl _sub_BLInput_fpLeaf
    ldr x30, [sp], #16
    ret

// The caller bodies clear x8 solely to exercise genuinely empty snapshots.
.macro BL_INPUT_CALLER name, target
.globl _sub_BLInput_\name
.p2align 2
_sub_BLInput_\name:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x8, x9
    bl _sub_BLInput_\target
    ldp x29, x30, [sp], #16
    ret
.endm
BL_INPUT_CALLER canonicalGPCaller, canonicalGP
BL_INPUT_CALLER canonicalFPCaller, canonicalFP
BL_INPUT_CALLER zeroGPCaller, zeroGP
BL_INPUT_CALLER zeroFPCaller, zeroFP
BL_INPUT_CALLER overwriteGPCaller, overwriteGP
BL_INPUT_CALLER overwriteFPCaller, overwriteFP

// A tracked value does not prove the wrapper's source count either.
.globl _sub_BLInput_liveGPCaller
.p2align 2
_sub_BLInput_liveGPCaller:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x8, x9
    mov x0, #73
    bl _sub_BLInput_wrapper
    ldp x29, x30, [sp], #16
    ret
.globl _sub_BLInput_liveFPCaller
.p2align 2
_sub_BLInput_liveFPCaller:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x8, x9
    fmov d0, #3.0
    bl _sub_BLInput_fpWrapper
    ldp x29, x30, [sp], #16
    ret

// Sparse possible inputs establish no four/eight-parameter source prefix.
.p2align 2
_sub_BLInput_sparseGPLeaf:
    add x0, x3, #1
    ret
.p2align 2
_sub_BLInput_sparseFPLeaf:
    fadd d0, d7, d7
    ret
.p2align 2
_sub_BLInput_sparseGP:
    str x30, [sp, #-16]!
    bl _sub_BLInput_sparseGPLeaf
    ldr x30, [sp], #16
    ret
.p2align 2
_sub_BLInput_sparseFP:
    str x30, [sp, #-16]!
    bl _sub_BLInput_sparseFPLeaf
    ldr x30, [sp], #16
    ret
BL_INPUT_CALLER sparseGPCaller, sparseGP
BL_INPUT_CALLER sparseFPCaller, sparseFP

// x0 is a proved incoming word; FP0 is only forwarded through BL. Their
// source order is not in this body, so a known GP word cannot be placed first.
.p2align 2
_sub_BLInput_mixed:
    str x30, [sp, #-16]!
    add x0, x0, #0
    bl _sub_BLInput_fpLeaf
    fmov x1, d0
    eor x0, x0, x1
    ldr x30, [sp], #16
    ret
BL_INPUT_CALLER mixedCaller, mixed
.globl _sub_BLInput_liveMixedCaller
.p2align 2
_sub_BLInput_liveMixedCaller:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x8, x9
    mov x0, #73
    fmov d0, #3.0
    bl _sub_BLInput_mixed
    ldp x29, x30, [sp], #16
    ret

// A value produced by an earlier call is not an incoming argument.
.p2align 2
_sub_BLInput_resultGP:
    str x30, [sp, #-16]!
    bl _sub_BLInput_zeroGPLeaf
    bl _sub_BLInput_leaf
    ldr x30, [sp], #16
    ret
.p2align 2
_sub_BLInput_resultFP:
    str x30, [sp, #-16]!
    bl _sub_BLInput_zeroFPLeaf
    bl _sub_BLInput_fpLeaf
    ldr x30, [sp], #16
    ret
BL_INPUT_CALLER resultGPCaller, resultGP
BL_INPUT_CALLER resultFPCaller, resultFP

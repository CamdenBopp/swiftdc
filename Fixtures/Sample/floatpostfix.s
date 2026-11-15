// FNEG changes a float's sign bit before FMOV reads its integer bits.
// Parentheses must keep that order in the reconstructed source. Plain and
// compound receivers are controls: their existing grouping is sufficient.
.text
nop
.p2align 2
.globl _$s12FloatPostfix5neg64ys6UInt64VSdF
_$s12FloatPostfix5neg64ys6UInt64VSdF:
    fneg d0, d0
    fmov x0, d0
    ret
.p2align 2
.globl _$s12FloatPostfix5neg32ys6UInt32VSfF
_$s12FloatPostfix5neg32ys6UInt32VSfF:
    fneg s0, s0
    fmov w0, s0
    ret
.p2align 2
.globl _$s12FloatPostfix7spilledys6UInt64VSdF
_$s12FloatPostfix7spilledys6UInt64VSdF:
    sub sp, sp, #16
    fneg d0, d0
    str q0, [sp]
    ldr x0, [sp]
    add sp, sp, #16
    ret
.p2align 2
.globl _$s12FloatPostfix7literalys6UInt64VyF
_$s12FloatPostfix7literalys6UInt64VyF:
    fmov d0, #1.0
    fneg d0, d0
    fmov x0, d0
    ret
.p2align 2
.globl _$s12FloatPostfix4zeroys6UInt64VyF
_$s12FloatPostfix4zeroys6UInt64VyF:
    fmov d0, xzr
    fneg d0, d0
    fmov x0, d0
    ret
.p2align 2
.globl _$s12FloatPostfix8compoundys6UInt64VSdF
_$s12FloatPostfix8compoundys6UInt64VSdF:
    fneg d0, d0
    fadd d0, d0, d0
    fmov x0, d0
    ret
.p2align 2
.globl _$s12FloatPostfix5plainys6UInt64VSdF
_$s12FloatPostfix5plainys6UInt64VSdF:
    fmov x0, d0
    ret

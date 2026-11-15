// Raw integer lanes must become IEEE values when read through d0. Conversely,
// a scalar FP spill loaded through Q and read as an integer keeps its bits.
.text
nop
.p2align 2
.globl _$s9BitVector4bitsySds6UInt64VF
_$s9BitVector4bitsySds6UInt64VF:
    dup v0.2d, x0
    ret
.p2align 2
.globl _$s9BitVector5spillySds6UInt64VF
_$s9BitVector5spillySds6UInt64VF:
    sub sp, sp, #16
    dup v0.2d, x0
    str q0, [sp]
    ldr d0, [sp]
    add sp, sp, #16
    ret
.p2align 2
.globl _$s9BitVector4wordys6UInt64VSdF
_$s9BitVector4wordys6UInt64VSdF:
    sub sp, sp, #32
    str d0, [sp]
    ldr q1, [sp]
    str q1, [sp, #16]
    ldr x0, [sp, #16]
    add sp, sp, #32
    ret
.p2align 2
.globl _$s9BitVector5floatyS2dF
_$s9BitVector5floatyS2dF:
    sub sp, sp, #16
    str d0, [sp]
    ldr q0, [sp]
    add sp, sp, #16
    ret
.p2align 2
.globl _$s9BitVector5roundys6UInt64VADF
_$s9BitVector5roundys6UInt64VADF:
    sub sp, sp, #16
    dup v0.2d, x0
    str d0, [sp]
    ldr x0, [sp]
    add sp, sp, #16
    ret
.p2align 2
.globl _$s9BitVector6directys6UInt64VSdF
_$s9BitVector6directys6UInt64VSdF:
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp]
    add sp, sp, #16
    ret

// AAPCS64 preserves only the bottom 64 bits of v8-v15. _vectorChangeHigh
// leaves d8 unchanged and sets v8.d[1] to 19, which the ABI allows; each
// caller here saves d8 for its own caller. Hand-written because a compiler
// never reads q8 after a call.
// Native results: high() == 19, umovHigh() == 19, low() == 0, noCall() == 0,
// scalar() == 7, dupLow() == 7, untouched() == 0.
// The decompiler does not model the helper's lane write, so high() and
// umovHigh() must decline their results rather than reuse the zero or the
// seven from before the call. The low lane, scalar or whole, must survive.
// untouched() calls a helper that writes nothing: the high lane really does
// survive, but nothing summarises v8, so the decompiler declines that too.
.text
.p2align 2
.globl _$s17VectorCallClobber4highSiyF
_$s17VectorCallClobber4highSiyF:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str d8, [sp, #16]
    movi v8.2d, #0
    bl _vectorChangeHigh
    str q8, [sp, #32]
    ldr x0, [sp, #40]
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

.p2align 2
.globl _$s17VectorCallClobber3lowSiyF
_$s17VectorCallClobber3lowSiyF:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str d8, [sp, #16]
    movi v8.2d, #0
    bl _vectorChangeHigh
    str q8, [sp, #32]
    ldr x0, [sp, #32]
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

.p2align 2
.globl _$s17VectorCallClobber6noCallSiyF
_$s17VectorCallClobber6noCallSiyF:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str d8, [sp, #16]
    movi v8.2d, #0
    str q8, [sp, #32]
    ldr x0, [sp, #40]
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

// A scalar d8 is what the ABI does preserve.
.p2align 2
.globl _$s17VectorCallClobber6scalarSiyF
_$s17VectorCallClobber6scalarSiyF:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str d8, [sp, #16]
    mov x9, #7
    fmov d8, x9
    bl _vectorChangeHigh
    fmov x0, d8
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// The low lane of a whole vector, read as a scalar.
.p2align 2
.globl _$s17VectorCallClobber6dupLowSiyF
_$s17VectorCallClobber6dupLowSiyF:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str d8, [sp, #16]
    mov x9, #7
    dup v8.2d, x9
    bl _vectorChangeHigh
    fmov x0, d8
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// The high lane read straight from the register, not through a spill.
.p2align 2
.globl _$s17VectorCallClobber8umovHighSiyF
_$s17VectorCallClobber8umovHighSiyF:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str d8, [sp, #16]
    mov x9, #7
    dup v8.2d, x9
    bl _vectorChangeHigh
    mov x0, v8.d[1]
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.p2align 2
.globl _$s17VectorCallClobber9untouchedSiyF
_$s17VectorCallClobber9untouchedSiyF:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str d8, [sp, #16]
    movi v8.2d, #0
    bl _vectorLeaveAlone
    str q8, [sp, #32]
    ldr x0, [sp, #40]
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

.p2align 2
.globl _vectorChangeHigh
.private_extern _vectorChangeHigh
_vectorChangeHigh:
    mov x9, #19
    mov v8.d[1], x9
    ret

.p2align 2
.globl _vectorLeaveAlone
.private_extern _vectorLeaveAlone
_vectorLeaveAlone:
    nop
    ret

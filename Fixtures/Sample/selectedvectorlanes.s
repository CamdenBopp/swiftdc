// A branch selects low words 7 or 11. An ordinary call changes only the
// high word to 19; Q spills and reloads must retain the selected low word.
// Preserve incoming d8 and execute these leaves in the native oracle.
.text
nop
.p2align 2
.globl _$s10VectorJoin3lowyS2iF
_$s10VectorJoin3lowyS2iF:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str d8, [sp, #16]
    cbz x0, L_low_zero
    mov x9, #7
    dup v8.2d, x9
    b L_low_join
L_low_zero:
    mov x9, #11
    dup v8.2d, x9
L_low_join:
    bl _selectedVectorChangeHigh
    str q8, [sp, #32]
    ldr q9, [sp, #32]
    str q9, [sp, #48]
    ldr x0, [sp, #48]
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #64
    ret
.p2align 2
.globl _$s10VectorJoin4highyS2iF
_$s10VectorJoin4highyS2iF:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str d8, [sp, #16]
    cbz x0, L_high_zero
    mov x9, #7
    dup v8.2d, x9
    b L_high_join
L_high_zero:
    mov x9, #11
    dup v8.2d, x9
L_high_join:
    bl _selectedVectorChangeHigh
    str q8, [sp, #32]
    ldr q9, [sp, #32]
    str q9, [sp, #48]
    ldr x0, [sp, #56]
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #64
    ret
.p2align 2
.globl _$s10VectorJoin6noCallyS2iF
_$s10VectorJoin6noCallyS2iF:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str d8, [sp, #16]
    cbz x0, L_noCall_zero
    mov x9, #7
    dup v8.2d, x9
    b L_noCall_join
L_noCall_zero:
    mov x9, #11
    dup v8.2d, x9
L_noCall_join:
    str q8, [sp, #32]
    ldr q9, [sp, #32]
    str q9, [sp, #48]
    ldr x0, [sp, #56]
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #64
    ret
.p2align 2
.globl _selectedVectorChangeHigh
.private_extern _selectedVectorChangeHigh
_selectedVectorChangeHigh:
    mov x9, #19
    mov v8.d[1], x9
    ret

.p2align 2
.globl _$s10VectorJoin6scalaryS2iF
_$s10VectorJoin6scalaryS2iF:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str d8, [sp, #16]
    cbz x0, L_scalar_zero
    mov x9, #7
    dup v8.2d, x9
    b L_scalar_join
L_scalar_zero:
    mov x9, #11
    dup v8.2d, x9
L_scalar_join:
    fmov x0, d8
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

.p2align 2
.globl _$s10VectorJoin11scalarSpillyS2iF
_$s10VectorJoin11scalarSpillyS2iF:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str d8, [sp, #16]
    cbz x0, L_scalarSpill_zero
    mov x9, #7
    dup v8.2d, x9
    b L_scalarSpill_join
L_scalarSpill_zero:
    mov x9, #11
    dup v8.2d, x9
L_scalarSpill_join:
    str d8, [sp, #32]
    ldr x0, [sp, #32]
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

.p2align 2
.globl _$s10VectorJoin5floatySdSiF
_$s10VectorJoin5floatySdSiF:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str d8, [sp, #16]
    cbz x0, L_float_zero
    mov x9, #0x3ff0000000000000
    dup v8.2d, x9
    b L_float_join
L_float_zero:
    mov x9, #0x4000000000000000
    dup v8.2d, x9
L_float_join:
    fmov d0, d8
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #64
    ret


.p2align 2
.globl _$s10VectorJoin7float32ySfSiF
_$s10VectorJoin7float32ySfSiF:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str d8, [sp, #16]
    cbz x0, L_float32_zero
    mov x9, #0x3f800000
    dup v8.2d, x9
    b L_float32_join
L_float32_zero:
    mov x9, #0x40000000
    dup v8.2d, x9
L_float32_join:
    fmov s0, s8
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #64
    ret


.p2align 2
.globl _$s10VectorJoin7float16ys7Float16VSiF
_$s10VectorJoin7float16ys7Float16VSiF:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str d8, [sp, #16]
    cbz x0, L_float16_zero
    mov x9, #0x3c00
    dup v8.2d, x9
    b L_float16_join
L_float16_zero:
    mov x9, #0x4000
    dup v8.2d, x9
L_float16_join:
    fmov h0, h8
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #64
    ret


.p2align 2
.globl _$s10VectorJoin8floatSumySdSiF
_$s10VectorJoin8floatSumySdSiF:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str d8, [sp, #16]
    cbz x0, L_floatSum_zero
    mov x9, #0x3ff0000000000000
    dup v8.2d, x9
    b L_floatSum_join
L_floatSum_zero:
    mov x9, #0x4000000000000000
    dup v8.2d, x9
L_floatSum_join:
    fadd d0, d8, d8
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #64
    ret


.p2align 2
.globl _$s10VectorJoin9floatCallySdSiF
_$s10VectorJoin9floatCallySdSiF:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str d8, [sp, #16]
    cbz x0, L_floatCall_zero
    mov x9, #0x3ff0000000000000
    dup v8.2d, x9
    b L_floatCall_join
L_floatCall_zero:
    mov x9, #0x4000000000000000
    dup v8.2d, x9
L_floatCall_join:
    fmov d0, d8
    bl _$s10VectorJoin10takeDoubleyS2dF
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #64
    ret


.p2align 2
.globl _$s10VectorJoin13floatBodyCallys6UInt64VSiF
_$s10VectorJoin13floatBodyCallys6UInt64VSiF:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str d8, [sp, #16]
    cbz x0, L_floatBodyCall_zero
    mov x9, #0x3ff0000000000000
    dup v8.2d, x9
    b L_floatBodyCall_join
L_floatBodyCall_zero:
    mov x9, #0x4000000000000000
    dup v8.2d, x9
L_floatBodyCall_join:
    fmov d0, d8
    bl _selectedVectorBits
    ldr d8, [sp, #16]
    ldp x29, x30, [sp], #64
    ret


.p2align 2
.globl _$s10VectorJoin10takeDoubleyS2dF
_$s10VectorJoin10takeDoubleyS2dF:
    ret
.p2align 2
.globl _selectedVectorBits
.private_extern _selectedVectorBits
_selectedVectorBits:
    fmov x0, d0
    ret
// The Swift Float16 leaf returns h0. Expose a Double only for its native oracle.
.p2align 2
.globl _selectedVectorHalfAsDouble
_selectedVectorHalfAsDouble:
    stp x29, x30, [sp, #-16]!
    bl _$s10VectorJoin7float16ys7Float16VSiF
    fcvt d0, h0
    ldp x29, x30, [sp], #16
    ret

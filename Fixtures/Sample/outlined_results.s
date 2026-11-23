// Machine-outlined helpers keep each result bank they never write.
// The store and x19 write prevent fragment inlining. Native wrappers save
// x19/LR, call each helper exactly once, and expose GP/FP transport separately.
.text

.globl _$s15OutlinedResults6keepGPSiyF
.p2align 2
_$s15OutlinedResults6keepGPSiyF:
    stp x19, x30, [sp, #-16]!
    mov x0, #37
    adrp x1, _outlined_result_effects@PAGE
    add x1, x1, _outlined_result_effects@PAGEOFF
    bl _OUTLINED_FUNCTION_0
    add x0, x0, #5
    ldp x19, x30, [sp], #16
    ret

.globl _$s15OutlinedResults6keepFPSdyF
.p2align 2
_$s15OutlinedResults6keepFPSdyF:
    stp x19, x30, [sp, #-16]!
    fmov d0, #1.5
    adrp x1, _outlined_result_effects@PAGE
    add x1, x1, _outlined_result_effects@PAGEOFF
    bl _OUTLINED_FUNCTION_0
    fadd d0, d0, d0
    ldp x19, x30, [sp], #16
    ret

.globl _$s15OutlinedResults10gpAcrossFPSiyF
.p2align 2
_$s15OutlinedResults10gpAcrossFPSiyF:
    stp x19, x30, [sp, #-16]!
    mov x0, #37
    adrp x1, _outlined_result_effects@PAGE
    add x1, x1, _outlined_result_effects@PAGEOFF
    bl _OUTLINED_FUNCTION_1
    add x0, x0, #5
    ldp x19, x30, [sp], #16
    ret

.globl _$s15OutlinedResults10fpAcrossGPSdyF
.p2align 2
_$s15OutlinedResults10fpAcrossGPSdyF:
    stp x19, x30, [sp, #-16]!
    fmov d0, #1.5
    adrp x1, _outlined_result_effects@PAGE
    add x1, x1, _outlined_result_effects@PAGEOFF
    bl _OUTLINED_FUNCTION_2
    fadd d0, d0, d0
    ldp x19, x30, [sp], #16
    ret

.globl _$s15OutlinedResults12keepProducerSiyF
.p2align 2
_$s15OutlinedResults12keepProducerSiyF:
    stp x19, x30, [sp, #-16]!
    bl _$s15OutlinedResults8producerSiyF
    adrp x1, _outlined_result_effects@PAGE
    add x1, x1, _outlined_result_effects@PAGEOFF
    bl _OUTLINED_FUNCTION_0
    add x0, x0, #5
    ldp x19, x30, [sp], #16
    ret

.globl _$s15OutlinedResults7writeGPSiyF
.p2align 2
_$s15OutlinedResults7writeGPSiyF:
    stp x19, x30, [sp, #-16]!
    mov x0, #37
    adrp x1, _outlined_result_effects@PAGE
    add x1, x1, _outlined_result_effects@PAGEOFF
    bl _OUTLINED_FUNCTION_2
    add x0, x0, #5
    ldp x19, x30, [sp], #16
    ret

.globl _$s15OutlinedResults7writeFPSdyF
.p2align 2
_$s15OutlinedResults7writeFPSdyF:
    stp x19, x30, [sp, #-16]!
    fmov d0, #1.5
    adrp x1, _outlined_result_effects@PAGE
    add x1, x1, _outlined_result_effects@PAGEOFF
    bl _OUTLINED_FUNCTION_1
    fadd d0, d0, d0
    ldp x19, x30, [sp], #16
    ret

.globl _$s15OutlinedResults8producerSiyF
.p2align 2
_$s15OutlinedResults8producerSiyF:
    mov x0, #37
    ret

.p2align 2
_OUTLINED_FUNCTION_0:
    mov x19, x0
    ldr x9, [x1]
    add x9, x9, #1
    str x9, [x1]
    ret

.p2align 2
_OUTLINED_FUNCTION_1:
    mov x19, x0
    ldr x9, [x1]
    add x9, x9, #1
    str x9, [x1]
    fmov d0, #2.0
    ret

.p2align 2
_OUTLINED_FUNCTION_2:
    mov x19, x0
    ldr x9, [x1]
    add x9, x9, #1
    str x9, [x1]
    mov x0, #11
    ret

.data
.globl _outlined_result_effects
.p2align 3
_outlined_result_effects:
    .quad 0

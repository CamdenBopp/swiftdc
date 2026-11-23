// Both Swift entries initialize the incoming 40-byte result, then hand x8
// to the foreign Swift malloc. Native results replace every initialized word.
.section __TEXT,__text,regular,pure_instructions
.macro initialize_five
    mov x9, #1
    str x9, [x8]
    mov x9, #2
    str x9, [x8, #8]
    mov x9, #3
    str x9, [x8, #16]
    mov x9, #4
    str x9, [x8, #24]
    mov x9, #5
    str x9, [x8, #32]
.endm
.globl _$s12BufferClient7forwardyAA4FiveVs5Int64VF
.p2align 2
_$s12BufferClient7forwardyAA4FiveVs5Int64VF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    initialize_five
    bl _malloc
    ldp x29, x30, [sp], #16
    ret
.globl _$s12BufferClient8indirectyAA4FiveVs5Int64VF
.p2align 2
_$s12BufferClient8indirectyAA4FiveVs5Int64VF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    initialize_five
    adrp x16, _malloc@GOTPAGE
    ldr x16, [x16, _malloc@GOTPAGEOFF]
    blr x16
    ldp x29, x30, [sp], #16
    ret

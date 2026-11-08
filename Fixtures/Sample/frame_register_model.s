// Authored current-frame register-copy and writeback controls.
// Every callee-saved register changed here is restored; x9/x10/x12 are scratch.
.text
.p2align 2
.globl _frame_register_model_postindex_copy
_frame_register_model_postindex_copy:
    sub sp, sp, #32
    mov x12, #11
    str x12, [sp, #16]
    add x9, sp, #8
    mov x10, x9
    str x19, [x10], #8
    mov x19, xzr
    ldur x19, [x10, #-8]
    ldr x0, [x10]
    add sp, sp, #32
    ret

.p2align 2
.globl _frame_register_model_preindex_copy
_frame_register_model_preindex_copy:
    sub sp, sp, #32
    mov x12, #11
    str x12, [sp, #16]
    add x9, sp, #0
    mov x10, x9
    str x19, [x10, #8]!
    mov x19, xzr
    ldr x19, [x10]
    ldr x0, [x10, #8]
    add sp, sp, #32
    ret

.p2align 2
.globl _frame_register_model_pair_copy
_frame_register_model_pair_copy:
    sub sp, sp, #48
    stp x19, x20, [sp, #8]
    add x9, sp, #8
    mov x10, x9
    mov x19, xzr
    mov x20, xzr
    ldr x19, [x10]
    ldr x20, [x10, #8]
    mov x0, #11
    add sp, sp, #48
    ret

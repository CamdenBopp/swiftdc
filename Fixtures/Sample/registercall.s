// Calls through a register whose value is an in-image function's address.
// `one_arg` reads only x0 (`lsl x0, x0, #2; add x0, x0, #9; ret`).
//   reg_call:  x0 = 3, x1 = 7 (not an argument), `blr x8`   -> one_arg(3)
//   reg_tail:  x0 unknown, `br x16`                         -> one_arg(?)
//   direct:    the same call by `bl`, the control           -> one_arg(3)
    .section __TEXT,__text,regular,pure_instructions
    .p2align 2
_one_arg:
    lsl x0, x0, #2
    add x0, x0, #9
    ret
    .globl _reg_call
    .p2align 2
_reg_call:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x8, _one_arg@PAGE
    add x8, x8, _one_arg@PAGEOFF
    mov x0, #3
    mov x1, #7
    blr x8
    ldp x29, x30, [sp], #16
    ret
    .globl _direct
    .p2align 2
_direct:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x0, #3
    mov x1, #7
    bl _one_arg
    ldp x29, x30, [sp], #16
    ret
    .globl _reg_tail
    .p2align 2
_reg_tail:
    adrp x16, _one_arg@PAGE
    add x16, x16, _one_arg@PAGEOFF
    ldr x0, [x0]
    br x16

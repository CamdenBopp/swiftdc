// A two-word local at sp+16. Computing its second word's address after the
// call does not prove a different object's boundary. The helper changes the
// second word from 7 to 11; native execution must return 11.
.text
.p2align 2
.globl _$s16FrameLayoutAlias12forwardAliasSiyF
_$s16FrameLayoutAlias12forwardAliasSiyF:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    mov x9, #7
    str x9, [sp, #24]
    add x0, sp, #16
    bl _frame_layout_write_upper
    add x10, sp, #24
    ldr x0, [x10]
    ldp x29, x30, [sp], #32
    ret

// This control never gives a frame pointer to a call and returns 7.
.p2align 2
.globl _$s16FrameLayoutAlias8noEscapeSiyF
_$s16FrameLayoutAlias8noEscapeSiyF:
    sub sp, sp, #32
    mov x9, #7
    str x9, [sp, #24]
    add x10, sp, #24
    ldr x0, [x10]
    add sp, sp, #32
    ret

.p2align 2
.globl _frame_layout_write_upper
_frame_layout_write_upper:
    mov x9, #11
    str x9, [x0, #8]
    ret

// Case 0 leaves the loop and calls finished; cases 1...9 and out-of-range
// inputs advance to the next input. LLVM-style compressed byte table bounded
// by cmp; b.hi, with its address setup kept in the dispatch block.
.text
.p2align 2
.globl _loopSwitchExit
_loopSwitchExit:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
Lheader:
    ldr w0, [x1], #4
    cmp x0, #9
    b.hi Lback
    adrp x9, Ltable@PAGE
    add x9, x9, Ltable@PAGEOFF
    adr x10, Lexit
    ldrb w11, [x9, x0]
    add x10, x10, x11, lsl #2
    br x10
Lexit:
    bl _finished
    ldp x29, x30, [sp], #16
    ret
Lback:
    b Lheader
.globl _finished
_finished:
    ret
.section __TEXT,__const
Ltable:
    .byte 0, 3, 3, 3, 3, 3, 3, 3, 3, 3

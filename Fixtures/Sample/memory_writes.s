// Stores the pseudocode must show, and stores it must not. Each function is a
// C symbol, so swiftdc has no signature for it. True behaviour per function:
// mw_field: *(x0 + 16) = x1 (an 8-byte store through an argument).
// mw_release: *(uint8_t *)x0 = w1, a release store of one byte.
// mw_indexed: *(x0 + x1 * 8) = x2.
// mw_spill: x0 spilled to the frame and reloaded; no memory outside it.
// mw_result: 16 bytes written through the indirect-result register x8.
// mw_dynamic: as mw_spill, after an sp change the frame layout cannot follow.
.text
.p2align 2
.globl _mw_field
_mw_field:
    str x1, [x0, #16]
    ret
.globl _mw_release
_mw_release:
    stlrb w1, [x0]
    ret
.globl _mw_indexed
_mw_indexed:
    str x2, [x0, x1, lsl #3]
    ret
.globl _mw_spill
_mw_spill:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [sp, #16]
    stur x0, [x29, #24]
    ldr x0, [sp, #16]
    ldp x29, x30, [sp], #32
    ret
.globl _mw_result
_mw_result:
    stp x0, x1, [x8]
    ret
// mw_dynamic: a dynamic stack allocation the tracer cannot follow; the store
// still addresses the stack, so nothing outside the frame is written.
.globl _mw_dynamic
_mw_dynamic:
    sub sp, sp, x1
    str x0, [sp]
    add sp, sp, x1
    ret

// Shared frame-fact migration controls. Authored assembly, not app code.
// memmove must snapshot all source words before destination invalidation:
// forward/backward overlap return 11/13, and a ten-byte copy returns 11
// from its trailing two-byte word. Every call preserves the native link/frame.
.text
.p2align 2
.macro copy_control name, destination, source, length, load
.globl _frame_fact_\name
_frame_fact_\name:
    sub sp, sp, #64
    stp x29, x30, [sp, #48]
    add x29, sp, #48
    mov x9, #7
    str x9, [sp]
    mov x9, #11
    str x9, [sp, #8]
    mov x9, #13
    str x9, [sp, #16]
    add x0, sp, #\destination
    add x1, sp, #\source
    mov x2, #\length
    bl _memmove
    \load
    ldp x29, x30, [sp, #48]
    add sp, sp, #64
    ret
.endm
copy_control forward_overlap, 8, 0, 16, "ldr x0, [sp, #16]"
copy_control backward_overlap, 0, 8, 16, "ldr x0, [sp, #8]"
copy_control partial_overlap, 8, 0, 10, "ldrh w0, [sp, #16]"

// Both native paths return 7: the initial zero defines the upper bytes of
// the narrow store. The tracer deliberately declines the joined wide load
// when stored-width facts disagree. Migration must retain that boundary.
.globl _frame_fact_width_join
_frame_fact_width_join:
    sub sp, sp, #32
    str xzr, [sp]
    mov x9, #7
    cbz x0, Lwidth_narrow
    str x9, [sp]
    b Lwidth_merge
Lwidth_narrow:
    str w9, [sp]
Lwidth_merge:
    ldr x0, [sp]
    add sp, sp, #32
    ret

// Equal bits stored from different register banks still disagree on their
// semantic bank metadata. Both native paths return 7; the tracer declines.
.globl _frame_fact_bank_join
_frame_fact_bank_join:
    sub sp, sp, #32
    mov x9, #7
    cbz x0, Lbank_float
    str x9, [sp]
    b Lbank_merge
Lbank_float:
    fmov d0, x9
    str d0, [sp]
Lbank_merge:
    ldr x0, [sp]
    add sp, sp, #32
    ret

// One four-component frame fact plus registers: budget accounting must
// count legacy components rather than treating the row as one fact.
.globl _frame_fact_budget
_frame_fact_budget:
    sub sp, sp, #32
    mov x9, #7
    str x9, [sp, #16]
    ldr x0, [sp, #16]
    add sp, sp, #32
    ret

// Exact local projection bodies, expressed from their memory/register rules.
// Both read the container/metadata; only the second uses private stack slots.
.text
.p2align 2
.globl ___swift_project_boxed_opaque_existential_0
___swift_project_boxed_opaque_existential_0:
    ldur x8, [x1, #-8]
    ldr w8, [x8, #0x50]
    tbz w8, #17, LoptimizedReturn
    ldr x9, [x0]
    and x8, x8, #0xff
    add x10, x8, #0x10
    bic x8, x10, x8
    add x0, x9, x8
LoptimizedReturn:
    ret

.p2align 2
.globl ___swift_project_boxed_opaque_existential_1
___swift_project_boxed_opaque_existential_1:
    sub sp, sp, #0x10
    str x0, [sp]
    ldur x8, [x1, #-8]
    ldr w8, [x8, #0x50]
    str x8, [sp, #8]
    tbnz w8, #17, LunoptimizedBox
    b LunoptimizedInline
LunoptimizedInline:
    ldr x0, [sp]
    add sp, sp, #0x10
    ret
LunoptimizedBox:
    ldr x9, [sp, #8]
    ldr x8, [sp]
    ldr x8, [x8]
    and x10, x9, #0xff
    add x9, x10, #0x10
    bic x9, x9, x10
    add x0, x8, x9
    add sp, sp, #0x10
    ret

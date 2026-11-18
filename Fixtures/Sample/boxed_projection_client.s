// Each caller stores 7 in a local, passes its address to a helper and then
// consumes the reloaded word. Genuine projections leave it at 7; the foreign
// and near-shape helpers write 41. The consumer adds one: native 8 versus 42.
.text
.macro caller name, target, mode=0
.p2align 2
.globl _\name
_\name:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    mov x1, x0
    mov w8, #7
    str w8, [sp, #16]
    add x0, sp, #16
.if \mode == 1
    adrp x16, \target@GOTPAGE
    ldr x16, [x16, \target@GOTPAGEOFF]
    blr x16
.elseif \mode == 2
    adrp x16, LreadonlyProjectionSlot@PAGE
    ldr x16, [x16, LreadonlyProjectionSlot@PAGEOFF]
    blr x16
.elseif \mode == 3
    adrp x16, _boxedProjectionMutableSlot@PAGE
    ldr x16, [x16, _boxedProjectionMutableSlot@PAGEOFF]
    blr x16
.elseif \mode == 4
    mov x9, #41
    bl \target
.else
    bl \target
.endif
    ldr w0, [sp, #16]
    bl _boxedProjectionConsumeWord
    ldp x29, x30, [sp], #32
    ret
.endmacro

caller boxedProjectionForeignDirect, ___swift_project_boxed_opaque_existential_0
caller boxedProjectionForeignIndirect, ___swift_project_boxed_opaque_existential_0, 1
caller boxedProjectionGenuineOptimized, ___swift_project_boxed_opaque_existential_1
caller boxedProjectionGenuineDebug, ___swift_project_boxed_opaque_existential_2
caller boxedProjectionGenuineIndirect, ___swift_project_boxed_opaque_existential_1, 2
caller boxedProjectionMutatingLookalike, ___swift_project_boxed_opaque_existential_3, 4
caller boxedProjectionMutableCall, ___swift_project_boxed_opaque_existential_1, 3

.p2align 2
.globl _boxedProjectionConsumeWord
_boxedProjectionConsumeWord:
    add w0, w0, #1
    ret

.p2align 2
.globl _boxedProjectionSetMutableTarget
_boxedProjectionSetMutableTarget:
    adrp x8, _boxedProjectionMutableSlot@PAGE
    str x0, [x8, _boxedProjectionMutableSlot@PAGEOFF]
    ret

// The two compiler projection shapes read the container/metadata and only
// write private stack storage. Preserve the names in the normal fixture;
// strip -x removes them in the companion, retaining function starts.
.p2align 2
.globl ___swift_project_boxed_opaque_existential_1
.private_extern ___swift_project_boxed_opaque_existential_1
___swift_project_boxed_opaque_existential_1:
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
.globl ___swift_project_boxed_opaque_existential_2
.private_extern ___swift_project_boxed_opaque_existential_2
___swift_project_boxed_opaque_existential_2:
    sub sp, sp, #0x10
    str x0, [sp]
    ldur x8, [x1, #-8]
    ldr w8, [x8, #0x50]
    str x8, [sp, #8]
    tbnz w8, #17, LdebugBox
    b LdebugInline
LdebugInline:
    ldr x0, [sp]
    add sp, sp, #0x10
    ret
LdebugBox:
    ldr x9, [sp, #8]
    ldr x8, [sp]
    ldr x8, [x8]
    and x10, x9, #0xff
    add x9, x10, #0x10
    bic x9, x9, x10
    add x0, x8, x9
    add sp, sp, #0x10
    ret

// One changed instruction makes this a mutator. It must not receive a
// projection contract from the matching name, length or surrounding code.
.p2align 2
.globl ___swift_project_boxed_opaque_existential_3
.private_extern ___swift_project_boxed_opaque_existential_3
___swift_project_boxed_opaque_existential_3:
    ldur x8, [x1, #-8]
    ldr w8, [x8, #0x50]
    tbz w8, #17, LlookalikeReturn
    str x9, [x0]
    and x8, x8, #0xff
    add x10, x8, #0x10
    bic x8, x10, x8
    add x0, x9, x8
LlookalikeReturn:
    ret

.section __DATA_CONST,__const
.p2align 3
LreadonlyProjectionSlot:
    .quad ___swift_project_boxed_opaque_existential_1

.data
.p2align 3
.globl _boxedProjectionMutableSlot
.private_extern _boxedProjectionMutableSlot
_boxedProjectionMutableSlot:
    .quad ___swift_project_boxed_opaque_existential_1

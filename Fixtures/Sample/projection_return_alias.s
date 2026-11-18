// Own-source inline/boxed pointer-return probe. The genuine projection
// itself writes no caller memory. Its returned pointer is then ignored,
// written through directly, passed to a mutator, spilled/reloaded, or copied
// through a callee-saved register. A real zero-argument getpid call is an
// unrelated-effect positive control. Mutation cases must reload 41, then add 1.
.text
.macro caller name, helper, boxed=0, mode=0
.p2align 2
.globl _\name
_\name:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    .if \boxed == 2
    // The payload header crosses a saved word, but the projection never
    // writes that header. Register-save boundaries are not payload bounds.
    str x19, [sp, #40]
    .else
    str x19, [sp, #16]
    .endif
    mov x1, x0
    mov w8, #7
    .if \boxed == 2
    str w8, [sp, #48]
    .else
    str w8, [sp, #80]
    .endif
.if \boxed == 2
    // The payload precedes its container: container-only reach is unsound.
    add x8, sp, #32
    str x8, [sp, #64]
    add x0, sp, #64
.elseif \boxed == 1
    add x8, sp, #64
    str x8, [sp, #32]
    add x0, sp, #32
.else
    add x0, sp, #80
.endif
    .if \mode == 6
    mov x2, #1
    .endif
    .if \mode == 8
    adrp x16, LprojectionAliasTarget@PAGE
    ldr x16, [x16, LprojectionAliasTarget@PAGEOFF]
    blr x16
    .else
    bl \helper
    .endif
.if \mode == 0
    bl _projectionAliasNoEffect
.elseif \mode == 1
    mov w8, #41
    str w8, [x0]
.elseif \mode == 2
    bl _projectionAliasMutate
.elseif \mode == 3
    str x0, [sp, #88]
    bl _projectionAliasNoEffect
    ldr x0, [sp, #88]
    bl _projectionAliasMutate
.elseif \mode == 4
    mov x19, x0
    bl _projectionAliasNoEffect
    mov x0, x19
    bl _projectionAliasMutate
.elseif \mode == 5
    bl _getpid
.elseif \mode == 6
    // x2 really remains1 across either exact helper. A normal call trace
    // forgets caller-saved x2, so this MUL must retain unknown MAY reach.
    mul x0, x0, x2
    mov w8, #41
    str w8, [x0]
.elseif \mode == 8
    bl _projectionAliasMutate
.endif
    .if \boxed == 2
    ldr w0, [sp, #48]
    .else
    ldr w0, [sp, #80]
    .endif
    bl _projectionAliasConsumeWord
    .if \boxed == 2
    ldr x19, [sp, #40]
    .else
    ldr x19, [sp, #16]
    .endif
    ldp x29, x30, [sp], #96
    ret
.endmacro
caller projectionAliasS1B0M0, ___swift_project_boxed_opaque_existential_1, 0, 0
caller projectionAliasS1B0M1, ___swift_project_boxed_opaque_existential_1, 0, 1
caller projectionAliasS1B0M2, ___swift_project_boxed_opaque_existential_1, 0, 2
caller projectionAliasS1B0M3, ___swift_project_boxed_opaque_existential_1, 0, 3
caller projectionAliasS1B0M4, ___swift_project_boxed_opaque_existential_1, 0, 4
caller projectionAliasS1B1M0, ___swift_project_boxed_opaque_existential_1, 1, 0
caller projectionAliasS1B1M1, ___swift_project_boxed_opaque_existential_1, 1, 1
caller projectionAliasS1B1M2, ___swift_project_boxed_opaque_existential_1, 1, 2
caller projectionAliasS1B1M3, ___swift_project_boxed_opaque_existential_1, 1, 3
caller projectionAliasS1B1M4, ___swift_project_boxed_opaque_existential_1, 1, 4
caller projectionAliasS2B0M0, ___swift_project_boxed_opaque_existential_2, 0, 0
caller projectionAliasS2B0M1, ___swift_project_boxed_opaque_existential_2, 0, 1
caller projectionAliasS2B0M2, ___swift_project_boxed_opaque_existential_2, 0, 2
caller projectionAliasS2B0M3, ___swift_project_boxed_opaque_existential_2, 0, 3
caller projectionAliasS2B0M4, ___swift_project_boxed_opaque_existential_2, 0, 4
caller projectionAliasS2B1M0, ___swift_project_boxed_opaque_existential_2, 1, 0
caller projectionAliasS2B1M1, ___swift_project_boxed_opaque_existential_2, 1, 1
caller projectionAliasS2B1M2, ___swift_project_boxed_opaque_existential_2, 1, 2
caller projectionAliasS2B1M3, ___swift_project_boxed_opaque_existential_2, 1, 3
caller projectionAliasS2B1M4, ___swift_project_boxed_opaque_existential_2, 1, 4

.p2align 2
.globl _projectionAliasNoEffect
_projectionAliasNoEffect:
    ret
.p2align 2
.globl _projectionAliasMutate
_projectionAliasMutate:
    mov w8, #41
    str w8, [x0]
    ret
.p2align 2
.globl _projectionAliasConsumeWord
_projectionAliasConsumeWord:
    add w0, w0, #1
    ret

// Exact local projection bodies, expressed from their memory/register rules.
// Both read the container/metadata; only the second uses private stack slots.
.text
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

// The projected address is not passed to this genuine zero-argument import.
caller projectionAliasS1B0M5, ___swift_project_boxed_opaque_existential_1, 0, 5
caller projectionAliasS1B1M5, ___swift_project_boxed_opaque_existential_1, 1, 5
caller projectionAliasS2B0M5, ___swift_project_boxed_opaque_existential_2, 0, 5
caller projectionAliasS2B1M5, ___swift_project_boxed_opaque_existential_2, 1, 5

// A boxed payload can precede the existential container in this same frame.
caller projectionAliasS1B2M0, ___swift_project_boxed_opaque_existential_1, 2, 0
caller projectionAliasS1B2M1, ___swift_project_boxed_opaque_existential_1, 2, 1
caller projectionAliasS1B2M2, ___swift_project_boxed_opaque_existential_1, 2, 2
caller projectionAliasS1B2M3, ___swift_project_boxed_opaque_existential_1, 2, 3
caller projectionAliasS1B2M4, ___swift_project_boxed_opaque_existential_1, 2, 4
caller projectionAliasS1B2M5, ___swift_project_boxed_opaque_existential_1, 2, 5
caller projectionAliasS2B2M0, ___swift_project_boxed_opaque_existential_2, 2, 0
caller projectionAliasS2B2M1, ___swift_project_boxed_opaque_existential_2, 2, 1
caller projectionAliasS2B2M2, ___swift_project_boxed_opaque_existential_2, 2, 2
caller projectionAliasS2B2M3, ___swift_project_boxed_opaque_existential_2, 2, 3
caller projectionAliasS2B2M4, ___swift_project_boxed_opaque_existential_2, 2, 4
caller projectionAliasS2B2M5, ___swift_project_boxed_opaque_existential_2, 2, 5

// A write through the projected pointer cannot reach the separate word at
// sp+24: the local/container starts at sp+80 and the mutator writes offset0.
// Native: (41+123)+1=165. A whole-frame fallback would lose the second word.
.p2align 2
.globl _projectionAliasUnrelatedFrameWord
_projectionAliasUnrelatedFrameWord:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    str x19, [sp, #16]
    mov x1, x0
    mov w8, #7
    str w8, [sp, #80]
    mov w8, #123
    str w8, [sp, #24]
    add x0, sp, #80
    bl ___swift_project_boxed_opaque_existential_1
    bl _projectionAliasMutate
    ldr w0, [sp, #80]
    ldr w1, [sp, #24]
    bl _projectionAliasConsumePair
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #96
    ret
.p2align 2
.globl _projectionAliasConsumePair
_projectionAliasConsumePair:
    add w0, w0, w1
    add w0, w0, #1
    ret

// Unknown arithmetic may still be the identity on the actual pointer.
caller projectionAliasS1B0M6, ___swift_project_boxed_opaque_existential_1, 0, 6
caller projectionAliasS1B1M6, ___swift_project_boxed_opaque_existential_1, 1, 6
caller projectionAliasS1B2M6, ___swift_project_boxed_opaque_existential_1, 2, 6
caller projectionAliasS2B0M6, ___swift_project_boxed_opaque_existential_2, 0, 6
caller projectionAliasS2B1M6, ___swift_project_boxed_opaque_existential_2, 1, 6
caller projectionAliasS2B2M6, ___swift_project_boxed_opaque_existential_2, 2, 6

// Two producers call the same helper; P2's write cannot reach P1's lower word.
.p2align 2
.globl _projectionAliasTwoProducers
_projectionAliasTwoProducers:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x20, x0
    mov w8, #7
    str w8, [sp, #48]
    mov w8, #9
    str w8, [sp, #80]
    mov x1, x20
    add x0, sp, #48
    bl ___swift_project_boxed_opaque_existential_1
    mov x19, x0
    mov x1, x20
    add x0, sp, #80
    bl ___swift_project_boxed_opaque_existential_1
    bl _projectionAliasMutate
    ldr w0, [sp, #48]
    ldr w1, [sp, #80]
    bl _projectionAliasConsumePair
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

caller projectionAliasIndirectResult, ___swift_project_boxed_opaque_existential_1, 0, 8

// A valid Swift word identity and a valid two-word pointer/Int result.
// The tuple signature is compiler-derived from our carryPair source:
// define swiftcc {ptr,i64}(ptr,i64), returning those same two words.
.p2align 2
.globl _$s13ProjectionABI8identityyS2iF
_$s13ProjectionABI8identityyS2iF:
    ret
.p2align 2
.globl _$s13ProjectionABI9carryPairySv_SitSv_SitF
_$s13ProjectionABI9carryPairySv_SitSv_SitF:
    ret

.macro logicalCaller name, kind=0
.p2align 2
.globl _\name
_\name:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    mov x1, x0
    mov w8, #7
    str w8, [sp, #80]
    add x0, sp, #80
    bl ___swift_project_boxed_opaque_existential_1
.if \kind == 2
    mov x1, #0
    bl _$s13ProjectionABI9carryPairySv_SitSv_SitF
.else
    bl _$s13ProjectionABI8identityyS2iF
.endif
.if \kind == 1
    bl _getpid
.else
    mov w8, #41
    str w8, [x0]
.endif
    ldr w0, [sp, #80]
    bl _projectionAliasConsumeWord
    ldp x29, x30, [sp], #96
    ret
.endmacro
logicalCaller projectionAliasLogicalResultWrites, 0
logicalCaller projectionAliasLogicalResultIgnored, 1
logicalCaller projectionAliasTupleResultWrites, 2

.section __DATA_CONST,__const
.p2align 3
LprojectionAliasTarget:
    .quad ___swift_project_boxed_opaque_existential_1

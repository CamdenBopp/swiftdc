// See resultrole.swift. The symbols are Swift functions of module
// ResultRole returning its Big. Each fills the result buffer with its own
// constant and calls with x8 still the buffer; the calls are never run.
.text
.globl _$s10ResultRole16keptAfterReleaseAA3BigVyF
.p2align 2
_$s10ResultRole16keptAfterReleaseAA3BigVyF:
    stp x29, x30, [sp, #-0x10]!
    mov x9, #9
    stp x9, x9, [x8]
    stp x9, x9, [x8, #16]
    str x9, [x8, #32]
    bl _swift_release
    ldp x29, x30, [sp], #0x10
    ret

.globl _$s10ResultRole20keptAfterAllocObjectAA3BigVyF
.p2align 2
_$s10ResultRole20keptAfterAllocObjectAA3BigVyF:
    stp x29, x30, [sp, #-0x10]!
    mov x9, #11
    stp x9, x9, [x8]
    stp x9, x9, [x8, #16]
    str x9, [x8, #32]
    bl _swift_allocObject
    ldp x29, x30, [sp], #0x10
    ret

.globl _$s10ResultRole17keptAfterAllocBoxAA3BigVyF
.p2align 2
_$s10ResultRole17keptAfterAllocBoxAA3BigVyF:
    stp x29, x30, [sp, #-0x10]!
    mov x9, #13
    stp x9, x9, [x8]
    stp x9, x9, [x8, #16]
    str x9, [x8, #32]
    bl _swift_allocBox
    ldp x29, x30, [sp], #0x10
    ret

.globl _$s10ResultRole17keptAfterReleaseNAA3BigVyF
.p2align 2
_$s10ResultRole17keptAfterReleaseNAA3BigVyF:
    stp x29, x30, [sp, #-0x10]!
    mov x9, #15
    stp x9, x9, [x8]
    stp x9, x9, [x8, #16]
    str x9, [x8, #32]
    bl _swift_release_n
    ldp x29, x30, [sp], #0x10
    ret

.globl _$s10ResultRole23staleAfterForeignFutureAA3BigVyF
.p2align 2
_$s10ResultRole23staleAfterForeignFutureAA3BigVyF:
    stp x29, x30, [sp, #-0x10]!
    mov x9, #17
    stp x9, x9, [x8]
    stp x9, x9, [x8, #16]
    str x9, [x8, #32]
    bl _swift_opaqueResult
    ldp x29, x30, [sp], #0x10
    ret

.globl _$s10ResultRole22staleAfterForeignAllocAA3BigVyF
.p2align 2
_$s10ResultRole22staleAfterForeignAllocAA3BigVyF:
    stp x29, x30, [sp, #-0x10]!
    mov x9, #19
    stp x9, x9, [x8]
    stp x9, x9, [x8, #16]
    str x9, [x8, #32]
    bl _swift_slowAlloc
    ldp x29, x30, [sp], #0x10
    ret

.globl _$s10ResultRole17staleAfterVersionAA3BigVyF
.p2align 2
_$s10ResultRole17staleAfterVersionAA3BigVyF:
    stp x29, x30, [sp, #-0x10]!
    mov x9, #23
    stp x9, x9, [x8]
    stp x9, x9, [x8, #16]
    str x9, [x8, #32]
    bl __swift_stdlib_operatingSystemVersion
    ldp x29, x30, [sp], #0x10
    ret
.globl _$s10ResultRole17staleAfterForwardAA3BigVyF
.p2align 2
_$s10ResultRole17staleAfterForwardAA3BigVyF:
    stp x29, x30, [sp, #-0x10]!
    mov x9, #27
    stp x9, x9, [x8]
    stp x9, x9, [x8, #16]
    str x9, [x8, #32]
    bl __objc_msgForward
    ldp x29, x30, [sp], #0x10
    ret

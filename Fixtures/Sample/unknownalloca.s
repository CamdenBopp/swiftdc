// The symbols are Swift functions `(Int) -> Int` of module UnknownAlloca;
// the argument is the address the size is read from.
// A dynamic stack allocation of a size the analysis does not know:
// `ldr x8, [x0]` loads it, `mov x9, sp; sub x9, x9, x8; mov sp, x9`
// allocates it below the frame. The local at [x29, #-8] holds 5 across
// the getpid call: the allocation lies below sp, under every frame slot,
// so `keptLocal(_:)` returns 5. The control writes through the allocation
// with an unknown displacement (`str xzr, [x9, x10]`) and may reach the
// slot, so `clobberedLocal(_:)` declines.
    .text
    .p2align 2
    .globl _$s13UnknownAlloca9keptLocalyS2iF
_$s13UnknownAlloca9keptLocalyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #16
    mov x9, #5
    stur x9, [x29, #-8]
    ldr x8, [x0]
    mov x9, sp
    sub x9, x9, x8
    mov sp, x9
    bl _getpid
    ldur x0, [x29, #-8]
    mov sp, x29
    ldp x29, x30, [sp], #16
    ret
    .globl _$s13UnknownAlloca14clobberedLocalyS2iF
_$s13UnknownAlloca14clobberedLocalyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #16
    mov x9, #5
    stur x9, [x29, #-8]
    ldr x8, [x0]
    mov x9, sp
    sub x9, x9, x8
    mov sp, x9
    ldr x10, [x0, #8]
    str xzr, [x9, x10]
    bl _getpid
    ldur x0, [x29, #-8]
    mov sp, x29
    ldp x29, x30, [sp], #16
    ret

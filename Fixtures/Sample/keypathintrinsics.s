// The reference key path setter called with x3 set: swiftc always
// retains the root first, which clobbers x3, so only assembly shows a
// live register past the three arguments. `setr` writes the value at
// x2's address through the key path in x1 on the root at x0; x3 = 9 is
// not an argument. True call: swift_setAtReferenceWritableKeyPath(x0, x1, x2).
    .section __TEXT,__text,regular,pure_instructions
    .globl _setr
    .p2align 2
_setr:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x3, #9
    bl _swift_setAtReferenceWritableKeyPath
    ldp x29, x30, [sp], #16
    ret

// The getter writes its result through the buffer in x8: a 77 stored there
// before the call is not what the load after it reads. True: x0 is the
// key path's value, unknown here.
    .globl _getslot
    .p2align 2
_getslot:
    sub sp, sp, #32
    stp x29, x30, [sp, #16]
    mov x9, #77
    str x9, [sp]
    mov x8, sp
    bl _swift_getAtKeyPath
    ldr x0, [sp]
    ldp x29, x30, [sp, #16]
    add sp, sp, #32
    ret

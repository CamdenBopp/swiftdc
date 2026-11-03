// A value-witness call on metadata loaded from a slot the loader binds:
// `adrp x2, _$sSiN@GOTPAGE; ldr x2, [x2, _$sSiN@GOTPAGEOFF]` loads Int's
// metadata from the GOT, `ldur x8, [x2, #-0x8]` its value-witness table,
// `ldr x8, [x8, #0x10]` slot 2: initializeWithCopy value witness for
// Swift.Int. The same metadata pointer in a writable __DATA slot
// (_metaCopy) proves nothing: the program could store another there.
    .section __DATA,__data
    .p2align 3
_metaCopy:
    .quad _$sSiN
    .text
    .p2align 2
    .globl _copyThroughGOT
_copyThroughGOT:
    stp x29, x30, [sp, #-16]!
    adrp x2, _$sSiN@GOTPAGE
    ldr x2, [x2, _$sSiN@GOTPAGEOFF]
    ldur x8, [x2, #-0x8]
    ldr x8, [x8, #0x10]
    blr x8
    ldp x29, x30, [sp], #16
    ret
    .globl _copyThroughWritable
_copyThroughWritable:
    stp x29, x30, [sp, #-16]!
    adrp x2, _metaCopy@PAGE
    ldr x2, [x2, _metaCopy@PAGEOFF]
    ldur x8, [x2, #-0x8]
    ldr x8, [x8, #0x10]
    blr x8
    ldp x29, x30, [sp], #16
    ret

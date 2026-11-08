// See resultbuffer.swift. The symbols are Swift functions of module
// ResultBuffer returning its Big.
.text
.globl _$s12ResultBuffer17staleAfterKeyPathAA3BigVyF
.p2align 2
_$s12ResultBuffer17staleAfterKeyPathAA3BigVyF:
    stp x29, x30, [sp, #-0x10]!
    mov x9, #7
    stp x9, x9, [x8]
    stp x9, x9, [x8, #16]
    str x9, [x8, #32]
    bl _swift_getAtKeyPath
    ldp x29, x30, [sp], #0x10
    ret

.globl _$s12ResultBuffer15keptAfterRetainAA3BigVyF
.p2align 2
_$s12ResultBuffer15keptAfterRetainAA3BigVyF:
    stp x29, x30, [sp, #-0x10]!
    mov x9, #7
    stp x9, x9, [x8]
    stp x9, x9, [x8, #16]
    str x9, [x8, #32]
    bl _swift_retain
    ldp x29, x30, [sp], #0x10
    ret

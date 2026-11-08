.text
.p2align 2
.globl _$s9ABISource17abiMakeAliasedOneyAA10ABIOneWordVSiF
_$s9ABISource17abiMakeAliasedOneyAA10ABIOneWordVSiF:
    // The result still goes through incoming x8, but via an alias. The narrow
    // decompiler rule intentionally declines this body until alias writes can
    // be tracked to the complete result buffer.
    mov x10, x8
    add x9, x0, #17
    str x9, [x10]
    ret

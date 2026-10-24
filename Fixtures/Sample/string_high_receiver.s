// A String result's second word kept in a callee-saved register and
// copied into x20 before a call, as Terminal does before String.hasPrefix
// (`mov x20, x22`). x20 is no receiver here: hasPrefix's self travels in
// x2 and x3, the String makeString returned.
//
// True behaviour: keptValue returns makeString(3).hasPrefix("-").
.text
.p2align 2
.globl _$s4High10makeStringySSSiF
_$s4High10makeStringySSSiF:
    mov x0, #3
    mov x1, #-0x1f00000000000000
    ret

.globl _$s4High9keptValueSbyF
_$s4High9keptValueSbyF:
    stp x22, x21, [sp, #-48]!
    stp x20, x19, [sp, #16]
    stp x29, x30, [sp, #32]
    add x29, sp, #32
    mov x0, #3
    bl _$s4High10makeStringySSSiF
    mov x21, x0
    mov x22, x1
    mov w0, #0x2d
    mov x1, #-0x1f00000000000000
    mov x2, x21
    mov x20, x22
    mov x3, x22
    bl _$sSS9hasPrefixySbSSF
    ldp x29, x30, [sp, #32]
    ldp x20, x19, [sp, #16]
    ldp x22, x21, [sp], #48
    ret

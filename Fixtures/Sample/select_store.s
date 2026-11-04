// Methods of selectstore.swift's Box, by hand: two selects, one per word
// of a String, each on its own compare of self.flag. The same load on
// either side of a write that may reach the field is two values, so x0
// and x1 can come from different arms: no pick, `return ?`. A compiler
// keeps one compare for one ternary, which is why these are written out.
// - steady: nothing between the loads. Both read one value: the pick.
// - stored: an unknown value stored to the field between the loads.
// - aliased: a store through an argument, which may be self.
// - called: a call between the loads, which may write the field.
// - argued: one compare of an argument, flags kept across a store: the
//   store reaches no argument, so the pick stands.
.text
.p2align 2

.macro WORDS
    mov w10, #0x6f6e
    mov w11, #0x6579
    movk w11, #0x73, lsl #16
    mov x12, #-0x1e00000000000000
    mov x13, #-0x1d00000000000000
.endm

.globl _$s11SelectStore3BoxC6steadySSyF
_$s11SelectStore3BoxC6steadySSyF:
    WORDS
    ldr x9, [x20, #0x10]
    cmp x9, #0
    csel x0, x11, x10, ne
    ldr x9, [x20, #0x10]
    cmp x9, #0
    csel x1, x13, x12, ne
    ret

// x0 is an UnsafePointer<Int>: the value stored is read through it.
.globl _$s11SelectStore3BoxC6storedySSSPySiGF
_$s11SelectStore3BoxC6storedySSSPySiGF:
    ldr x14, [x0]
    WORDS
    ldr x9, [x20, #0x10]
    cmp x9, #0
    csel x0, x11, x10, ne
    str x14, [x20, #0x10]
    ldr x9, [x20, #0x10]
    cmp x9, #0
    csel x1, x13, x12, ne
    ret

.globl _$s11SelectStore3BoxC7aliasedySSSpySiGF
_$s11SelectStore3BoxC7aliasedySSSpySiGF:
    mov x15, x0
    WORDS
    ldr x9, [x20, #0x10]
    cmp x9, #0
    csel x0, x11, x10, ne
    mov x14, #1
    str x14, [x15]
    ldr x9, [x20, #0x10]
    cmp x9, #0
    csel x1, x13, x12, ne
    ret

.globl _$s11SelectStore3BoxC6calledSSyF
_$s11SelectStore3BoxC6calledSSyF:
    stp x22, x21, [sp, #-48]!
    stp x20, x19, [sp, #16]
    stp x29, x30, [sp, #32]
    add x29, sp, #32
    WORDS
    ldr x9, [x20, #0x10]
    cmp x9, #0
    csel x19, x11, x10, ne
    mov x0, x20
    bl _$s11SelectStore5touchyyAA3BoxCF
    mov x12, #-0x1e00000000000000
    mov x13, #-0x1d00000000000000
    ldr x9, [x20, #0x10]
    cmp x9, #0
    csel x1, x13, x12, ne
    mov x0, x19
    ldp x29, x30, [sp, #32]
    ldp x20, x19, [sp, #16]
    ldp x22, x21, [sp], #48
    ret

.globl _$s11SelectStore3BoxC6arguedySSSbF
_$s11SelectStore3BoxC6arguedySSSbF:
    WORDS
    tst w0, #1
    csel x0, x11, x10, ne
    mov x14, #1
    str x14, [x20, #0x10]
    csel x1, x13, x12, ne
    ret

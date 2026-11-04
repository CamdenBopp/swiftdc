// A float's bits read at a width other than the float's own. Each function
// is a Swift `(Float) -> Int`, so the argument arrives in s0.
//   word:  `fmov w0, s0`: the Float's 32 bits, `a.bitPattern`.
//   whole: `fmov x0, d0`: all of d0, whose upper half the Float does not
//          define. It is no `a.bitPattern`, and must not read as one.
// copied and swapped, Swift `(Double) -> Int`, move the Double between two
// frame words with memcpy, so the word they reload has no known register
// file: `str d0, [sp, #8]; memcpy(sp, sp + 8, 8); ldrb w8, [sp]; cmp w8, #7`.
// Each returns whether the bits it read are not 7, and the 7 is an integer.
// swapped reads the whole word and reverses it: `ldr x8, [sp]; rev x8, x8`.
.text
.p2align 2
.globl _$s14FloatBitsWidth4wordySiSfF
_$s14FloatBitsWidth4wordySiSfF:
    fmov w0, s0
    ret
.globl _$s14FloatBitsWidth5wholeySiSfF
_$s14FloatBitsWidth5wholeySiSfF:
    fmov x0, d0
    ret
.globl _$s14FloatBitsWidth6copiedySiSdF
_$s14FloatBitsWidth6copiedySiSdF:
    sub sp, sp, #32
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    str d0, [sp, #8]
    mov x0, sp
    add x1, sp, #8
    mov x2, #8
    bl _memcpy
    ldrb w8, [sp]
    cmp w8, #7
    cset w0, ne
    ldp x29, x30, [sp, #16]
    add sp, sp, #32
    ret
.globl _$s14FloatBitsWidth7swappedySiSdF
_$s14FloatBitsWidth7swappedySiSdF:
    sub sp, sp, #32
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    str d0, [sp, #8]
    mov x0, sp
    add x1, sp, #8
    mov x2, #8
    bl _memcpy
    ldr x8, [sp]
    rev x8, x8
    cmp x8, #7
    cset w0, ne
    ldp x29, x30, [sp, #16]
    add sp, sp, #32
    ret

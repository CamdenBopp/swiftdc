// A float's bits read at a width other than the float's own. Each function
// is a Swift `(Float) -> Int`, so the argument arrives in s0.
//   word:  `fmov w0, s0`: the Float's 32 bits, `a.bitPattern`.
//   whole: `fmov x0, d0`: all of d0, whose upper half the Float does not
//          define. It is no `a.bitPattern`, and must not read as one.
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

// Bitfield moves, extends and negation, each a two-argument function
// (x0, x1) -> x0, executed natively by BitfieldOracleTests. True behaviour:
// ubfx d, s, #l, #w = (s >> l) & (2^w - 1); ubfiz = (s & (2^w - 1)) << l;
// sbfx/sbfiz sign-extend the w-bit field; bfi/bfxil insert into d and keep
// its other bits; sxt*/uxt* extend the low byte, halfword or word; neg is
// 0 - s. A W destination zero-extends into x0.
.text
.p2align 2
.macro probe name, a, b, c, d, e
.globl _bits_\name
_bits_\name:
    \a \b, \c, \d, \e
    ret
.endm
.macro probe2 name, a, b, c
.globl _bits_\name
_bits_\name:
    \a \b, \c
    ret
.endm
probe ubfx_x, ubfx, x0, x0, #13, #20
probe ubfx_w, ubfx, w0, w0, #3, #5
probe ubfx_wtop, ubfx, w0, w0, #24, #8
probe ubfx_xtop, ubfx, x0, x0, #1, #63
probe ubfiz_x, ubfiz, x0, x0, #7, #20
probe ubfiz_w, ubfiz, w0, w0, #28, #4
probe sbfx_x, sbfx, x0, x0, #4, #8
probe sbfx_w, sbfx, w0, w0, #31, #1
probe sbfx_xwide, sbfx, x0, x0, #3, #40
probe sbfiz_x, sbfiz, x0, x0, #2, #6
probe sbfiz_w, sbfiz, w0, w0, #16, #16
probe bfi_x, bfi, x0, x1, #8, #12
probe bfi_w, bfi, w0, w1, #4, #4
probe bfxil_x, bfxil, x0, x1, #20, #16
probe bfxil_w, bfxil, w0, w1, #0, #8
probe2 sxtb_x, sxtb, x0, w0
probe2 sxth_w, sxth, w0, w0
probe2 sxtw, sxtw, x0, w0
probe2 uxtb, uxtb, w0, w0
probe2 uxth, uxth, w0, w0
probe2 neg_x, neg, x0, x0
probe2 neg_w, neg, w0, w0
.globl _bits_neg_shift
_bits_neg_shift:
    neg x0, x1, lsl #3
    ret

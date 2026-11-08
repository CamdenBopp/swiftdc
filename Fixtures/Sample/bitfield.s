// Bitfield moves, extends and negation, each a two-argument function
// (x0, x1) -> x0, executed natively by BitfieldOracleTests. True behaviour:
// ubfx d, s, #l, #w = (s >> l) & (2^w - 1); ubfiz = (s & (2^w - 1)) << l;
// sbfx/sbfiz sign-extend the w-bit field; bfi/bfxil insert into d and keep
// its other bits; sxt*/uxt* extend the low byte, halfword or word; neg is
// 0 - s. bic is n & ~m and eon n ^ ~m, m shifted first; mneg is 0 - n * m;
// movn is ~(imm << s); a ROR operand rotates within its register's width,
// and ror by a register rotates by its value mod the width. clz counts
// leading zeros, cls the bits after the sign equal to it, rbit reverses.
// A W destination zero-extends into x0.
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
.globl _bits_bic_x
_bits_bic_x:
    bic x0, x0, x1, lsl #5
    ret
.globl _bits_bics_w
_bits_bics_w:
    bics w0, w0, w1, asr #3
    ret
.globl _bits_eon_x
_bits_eon_x:
    eon x0, x0, x1, lsr #7
    ret
.globl _bits_negs_w
_bits_negs_w:
    negs w0, w1, lsl #2
    ret
.globl _bits_mneg_x
_bits_mneg_x:
    mneg x0, x0, x1
    ret
.globl _bits_movn_w
_bits_movn_w:
    movn w0, #0xffff
    ret
.globl _bits_and_ror_x
_bits_and_ror_x:
    and x0, x0, x1, ror #13
    ret
.globl _bits_orr_ror_w
_bits_orr_ror_w:
    orr w0, w0, w1, ror #31
    ret
.globl _bits_rorv_x
_bits_rorv_x:
    ror x0, x0, x1
    ret
.globl _bits_rorv_w
_bits_rorv_w:
    ror w0, w0, w1
    ret
.globl _bits_clz_x
_bits_clz_x:
    clz x0, x0
    ret
.globl _bits_clz_w
_bits_clz_w:
    clz w0, w0
    ret
.globl _bits_cls_x
_bits_cls_x:
    cls x0, x0
    ret
.globl _bits_cls_w
_bits_cls_w:
    cls w0, w0
    ret
.globl _bits_rbit_x
_bits_rbit_x:
    rbit x0, x0
    ret
.globl _bits_rbit_w
_bits_rbit_w:
    rbit w0, w0
    ret
// Conditional increment, negate and invert after a compare of x0 and x1:
// cinc d, n, cc = cc ? n + 1 : n, cneg negates and cinv complements.
.globl _bits_cinc_lt
_bits_cinc_lt:
    cmp x0, x1
    cinc x0, x0, lt
    ret
.globl _bits_cneg_mi
_bits_cneg_mi:
    cmp x0, #0
    cneg x0, x0, mi
    ret
.globl _bits_cinv_hi
_bits_cinv_hi:
    cmp x0, x1
    cinv x0, x1, hi
    ret
.globl _bits_cinc_w_eq
_bits_cinc_w_eq:
    cmp w0, w1
    cinc w0, w0, eq
    ret
.globl _bits_abs_safe
_bits_abs_safe:
    cmp x0, #0
    cneg x8, x0, mi
    mov x9, #-0x8000000000000000
    cmp x0, x9
    csinv x0, x8, xzr, ne
    ret

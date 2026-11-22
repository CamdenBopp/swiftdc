// AAPCS64 C entry points: uint64_t in x0, uint64_t out in x0.
// FMOV S0,W0 copies 32 input bits and clears D0[63:32].
// FMOV X0,D0 returns the resulting 64-bit word without FP conversion.
.text
.p2align 2
.globl _fpwide_word
_fpwide_word:
    fmov s0, w0
    fmov x0, d0
    ret

// FEAT_FP16 equivalent: FMOV H0,W0 copies the low 16 bits and clears
// D0[63:16]. The second move reads the full defined D0 word.
.globl _fpwide_half
_fpwide_half:
    fmov h0, w0
    fmov x0, d0
    ret

.subsections_via_symbols

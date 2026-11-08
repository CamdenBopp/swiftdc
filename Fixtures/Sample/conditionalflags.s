// Native oracle: every CCMP fallback NZCV, consumer condition, and width.
.text
.p2align 2
.macro probe width, prior, observed, fallback
.globl _ccmp_\width\()_\prior\()_\observed\()_\fallback
_ccmp_\width\()_\prior\()_\observed\()_\fallback:
    cmp \width\()0, \width\()1
    ccmp \width\()2, \width\()3, #\fallback, \prior
    cset x0, \observed
    ret
.endm

.macro conditions width, prior, fallback
    probe \width, \prior, eq, \fallback
    probe \width, \prior, ne, \fallback
    probe \width, \prior, hs, \fallback
    probe \width, \prior, lo, \fallback
    probe \width, \prior, mi, \fallback
    probe \width, \prior, pl, \fallback
    probe \width, \prior, vs, \fallback
    probe \width, \prior, vc, \fallback
    probe \width, \prior, hi, \fallback
    probe \width, \prior, ls, \fallback
    probe \width, \prior, ge, \fallback
    probe \width, \prior, lt, \fallback
    probe \width, \prior, gt, \fallback
    probe \width, \prior, le, \fallback
.endm

.macro fallbacks width, prior
    conditions \width, \prior, 0
    conditions \width, \prior, 1
    conditions \width, \prior, 2
    conditions \width, \prior, 3
    conditions \width, \prior, 4
    conditions \width, \prior, 5
    conditions \width, \prior, 6
    conditions \width, \prior, 7
    conditions \width, \prior, 8
    conditions \width, \prior, 9
    conditions \width, \prior, 10
    conditions \width, \prior, 11
    conditions \width, \prior, 12
    conditions \width, \prior, 13
    conditions \width, \prior, 14
    conditions \width, \prior, 15
.endm

fallbacks x, eq
fallbacks x, lt
fallbacks w, eq
fallbacks w, lt

// CSETM consumes the same flags but materializes a mask, including the
// zero-extension of a write to w0.
.globl _flag_mask_x
_flag_mask_x:
    cmp x0, x1
    ccmp x2, x3, #0, eq
    csetm x0, eq
    ret
.globl _flag_mask_w
_flag_mask_w:
    cmp x0, x1
    ccmp x2, x3, #0, eq
    csetm w0, eq
    ret

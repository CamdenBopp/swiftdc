// Absolute symbols (N_ABS) are constants, not addresses. pixman's NEON
// assembly defines `mask_bpp_shift` as -1, and swiftdc trapped converting
// it to an address ("Negative value is not representable", SIGTRAP from
// every xrefs/disasm path on Emacs's and KiCad's libpixman). `_abs_value`
// is absolute too: tests set it, in a copy, to `_real`'s address, as a
// constant that happens to equal a code address. True behaviour: `_real`
// returns 7 and is named `_real`; `_caller` tail-calls it; neither absolute
// symbol names anything.
    .text
    .globl _real
    .p2align 2
_real:
    mov w0, #7
    ret

    .globl _caller
    .p2align 2
_caller:
    b _real

    .set mask_bpp_shift, -1
    .globl _abs_value
    .set _abs_value, 0x10
.subsections_via_symbols

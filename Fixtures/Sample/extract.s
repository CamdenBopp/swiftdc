// EXTR takes a width-sized window from high:low. ROR immediate uses
// the same register for both halves. W forms zero-extend the result.
.text
.p2align 2
.macro extract_probe width, reg, shift
.globl _extract_\width\()_\shift
_extract_\width\()_\shift:
    extr \reg\()0, \reg\()0, \reg\()1, #\shift
    ret
.globl _rotate_\width\()_\shift
_rotate_\width\()_\shift:
    ror \reg\()0, \reg\()0, #\shift
    ret
.endm
.irp amount,0,1,2,7,15,16,23,31
    extract_probe 32, w, \amount
.endr
.irp amount,0,1,2,7,15,16,23,31,32,33,47,62,63
    extract_probe 64, x, \amount
.endr

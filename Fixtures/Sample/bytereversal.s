// REV reverses the whole register; REV16 swaps bytes in each halfword;
// REV32 swaps bytes in each 32-bit word. W results zero-extend into x0.
.text
.p2align 2
.macro reverse_probe name, instruction, reg
.globl _byte_\name
_byte_\name:
    \instruction \reg\()0, \reg\()0
    ret
.endm
reverse_probe revx, rev, x
reverse_probe revw, rev, w
reverse_probe rev16x, rev16, x
reverse_probe rev16w, rev16, w
reverse_probe rev32x, rev32, x

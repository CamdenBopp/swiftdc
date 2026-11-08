// SVE instructions write z and p registers, which swiftdc's tracer does not
// model (Capstone gives them no bank). libcrypto's ChaCha20 (`lsr z9.s,
// z9.s, #0x19`) reached the scalar shift model with a 0-bit register and
// trapped ("Negative value is not representable") in xrefs, disasm and
// analyze. A z register's low 128 bits are the v register of the same
// number. True behaviour: `_sve_alias` sets d0 to 2.0, then shifts every
// 32-bit lane of z0 right by one, so it does not return 2.0 (the low lane
// pattern of 2.0 is 0x4000000000000000; shifted per lane it is
// 0x2000000000000000, which is 1.0842e-19).
    .text
    .globl _sve_alias
    .p2align 2
_sve_alias:
    fmov d0, #2.0
    lsr z0.s, z0.s, #1
    ret

    .globl _sve_and
    .p2align 2
_sve_and:
    mov x0, #5
    and z1.d, z1.d, #0xff
    ret
.subsections_via_symbols

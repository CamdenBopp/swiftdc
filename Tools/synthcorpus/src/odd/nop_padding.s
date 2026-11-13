// `nop` padding: before a loop head aligned with `.p2align 4` (filled with
// nops), and after the `ret` up to the next function's 32-byte alignment.
// True behaviour: padSum(n) returns n + (n-1) + ... + 1, or 0 for n < 1
// (signed); after() returns 7. The padding does nothing: it must not end
// padSum early, appear as statements, or merge after() into padSum.
.text
.globl _$s3Odd6padSumyS2iF
.p2align 2
_$s3Odd6padSumyS2iF:
    mov x8, #0
    cmp x0, #1
    b.lt 2f
    nop
    nop
    .p2align 4
1:
    add x8, x8, x0
    subs x0, x0, #1
    b.ne 1b
2:
    mov x0, x8
    ret
    nop
    nop
    nop
    .p2align 5
.globl _$s3Odd5afterSiyF
_$s3Odd5afterSiyF:
    mov x0, #7
    ret

// EXPECT structured * Odd.after( :: return 7
// FORBID structured * Odd.padSum( :: return 7
// FORBID structured * Odd.padSum( :: nop
// FORBID structured * Odd.padSum( :: continues into
// The trailing nops are padding, not a block of padSum:
// FORBID structured * Odd.padSum( :: re:loc_[0-9a-f]+:\s*\n\s*// no fall-through
// FORBID structured * Odd.padSum( :: re:(?m)return (arg0|x0)[ \t]*$
// EXPECT structured * Odd.padSum( :: re:while|loop|do \{

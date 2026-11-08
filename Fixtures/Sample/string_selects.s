// Two selects that are no one String pick (hand-written, as no compiler
// emits them for one ternary):
// - Picks.mixed(Bool, Bool) selects x0 on its first argument and x1 on its
//   second: the words of "yes" and "no" can mix, so no `c ? "yes" : "no"`
//   holds. True behaviour: a String of x0 from one pick and x1 from the
//   other, `return ?`.
// - Picks.swapped(Bool) selects x0 on `ne` and x1 on `eq` over one `tst`:
//   true is x0 of "yes" with x1 of "no". `return ?`.
.text
.p2align 2
.globl _$s5Picks5mixedySSSb_SbtF
_$s5Picks5mixedySSSb_SbtF:
    mov w8, #0x6f6e
    mov w9, #0x6579
    movk w9, #0x73, lsl #16
    mov x10, #-0x1e00000000000000
    mov x11, #-0x1d00000000000000
    tst w0, #0x1
    csel x0, x9, x8, ne
    tst w1, #0x1
    csel x1, x11, x10, ne
    ret

.globl _$s5Picks7swappedySSSbF
_$s5Picks7swappedySSSbF:
    mov w8, #0x6f6e
    mov w9, #0x6579
    movk w9, #0x73, lsl #16
    mov x10, #-0x1e00000000000000
    mov x11, #-0x1d00000000000000
    tst w0, #0x1
    csel x0, x9, x8, ne
    csel x1, x10, x11, eq
    ret

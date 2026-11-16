// A function cut in two. The functions carry Swift mangled names so the
// decompiler knows each returns an Int and renders return values.
//
// `cut_tail` is a local, non-temporary label in the middle of
// `Odd.cut(_:)`, so the linker lists it in LC_FUNCTION_STARTS and the symbol
// table. `Odd.cut` has no `ret` of its own: it falls through into
// `cut_tail`. True behaviour: cut(x) returns (x + 1) * 2; the code at
// cut_tail returns x0 * 2. A render of `Odd.cut` that stops at the cut must
// not claim a return there: x + 1 is not what the caller gets.
//
// `Odd.cutCond(_:)`: `cbz x0` whose fall-through is the cut `cond_tail`,
// and whose taken target (x0 = 0; ret) lies after cond_tail's `ret`, inside
// cond_tail's span. True behaviour: cutCond(x) returns 0 when x == 0, else
// x * 3. Its render must show both ways out: the test of x == 0 and the
// continuation into the cut. Dropping the `cbz` reads as "always continues
// into cond_tail", which loses the x == 0 path.
.text
.globl _$s3Odd3cutyS2iF
.p2align 2
_$s3Odd3cutyS2iF:
    add x0, x0, #1
cut_tail:
    lsl x0, x0, #1
    ret

.globl _$s3Odd7cutCondyS2iF
.p2align 2
_$s3Odd7cutCondyS2iF:
    cbz x0, 1f
cond_tail:
    add x0, x0, x0, lsl #1
    ret
1:
    mov x0, #0
    ret

// EXPECT listing * Odd.cut( :: cut_tail:
// EXPECT structured * Odd.cut( :: continues into
// FORBID structured * Odd.cut( :: re:(?m)^\s*return\b
// FORBID pseudo * Odd.cut( :: re:(?m)^\s*return\b
// EXPECT structured * Odd.cutCond( :: continues into
// EXPECT structured * Odd.cutCond( :: re:== 0
// FORBID structured * Odd.cutCond( :: re:(?m)return (x0|arg0)[ \t]*$

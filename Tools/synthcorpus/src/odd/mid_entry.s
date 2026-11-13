// Functions that branch into the middle of another function.
//
// Odd.inner(_:): x0 += 100, then (at the temporary label Linner_mid)
// x0 *= 2 and returns. True behaviour: returns (x + 100) * 2.
//
// Odd.jumper(_:): x0 = 3, then `b Linner_mid`, inner's tail from the
// middle. True behaviour: returns 6 for any input. It must not claim to
// return 3, nor (3 + 100) * 2 = 206 (entering inner at its start).
//
// Odd.cjumper(_:): if x == 0, branches into inner's middle with x0 == 0
// (returns 0); else returns 5. True behaviour: returns 0 or 5.
.text
.globl _$s3Odd5inneryS2iF
.p2align 2
_$s3Odd5inneryS2iF:
    add x0, x0, #100
Linner_mid:
    lsl x0, x0, #1
    ret

.globl _$s3Odd6jumperyS2iF
.p2align 2
_$s3Odd6jumperyS2iF:
    mov x0, #3
    b Linner_mid

.globl _$s3Odd7cjumperyS2iF
.p2align 2
_$s3Odd7cjumperyS2iF:
    cbz x0, Linner_mid
    mov x0, #5
    ret

// FORBID structured * Odd.jumper( :: return 3
// FORBID structured * Odd.jumper( :: re:return (206|0xce)\b
// FORBID structured * Odd.jumper( :: re:\binner\(
// FORBID structured * Odd.jumper( :: re:(?m)return[ \t]*$
// FORBID structured * Odd.cjumper( :: re:\binner\(
// EXPECT structured * Odd.cjumper( :: return 5
// FORBID structured * Odd.cjumper( :: re:return (200|0xc8)\b
// FORBID structured * Odd.cjumper( :: re:(?m)return (arg0|x0)[ \t]*$
// Both ways out of cjumper must show: the x == 0 branch into inner's middle
// is a path, and `return 5` alone claims it is the only one.
// EXPECT structured * Odd.cjumper( :: re:== 0
// jumper's whole effect is the branch: an empty body drops it.
// EXPECT structured * Odd.jumper( :: re:0x2c4|inner\b|goto|continues
// EXPECT pseudo * Odd.jumper( :: re:0x2c4|inner\b|goto|continues

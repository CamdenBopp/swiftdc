// x16/x17 (IP0/IP1) and x18 (the Darwin platform register) as scratch.
//
// Odd.ipSum(_:_:): x16 = x0, x17 = x16 + x1, returns x17. True behaviour:
// returns x0 + x1.
//
// Odd.ipAcross(_:): x16 = 5, calls ext(x0), returns x16. A call, and any
// stub or veneer on its way, may clobber x16 and x17, so the returned
// value is unknown, not 5. Odd.x18Across(_:) is the same with x18 = 7:
// x18 is not callee-saved and the platform may change it at any time.
//
// Odd.x18Local(_:): x18 = x * 2, returns x18 + 1 with no call between.
// True behaviour (as executed): returns 2x + 1.
.text
.globl _$s3Odd5ipSumyS2i_SitF
.p2align 2
_$s3Odd5ipSumyS2i_SitF:
    mov x16, x0
    add x17, x16, x1
    mov x0, x17
    ret

.globl _$s3Odd8ipAcrossyS2iF
.p2align 2
_$s3Odd8ipAcrossyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x16, #5
    bl _ext
    mov x0, x16
    ldp x29, x30, [sp], #16
    ret

.globl _$s3Odd9x18AcrossyS2iF
.p2align 2
_$s3Odd9x18AcrossyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x18, #7
    bl _ext
    mov x0, x18
    ldp x29, x30, [sp], #16
    ret

.globl _$s3Odd8x18LocalyS2iF
.p2align 2
_$s3Odd8x18LocalyS2iF:
    lsl x18, x0, #1
    add x0, x18, #1
    ret

// EXPECT structured * Odd.ipSum( :: re:return \(?((arg0|x0) \+ (arg1|x1)|(arg1|x1) \+ (arg0|x0))
// FORBID structured * Odd.ipAcross( :: return 5
// FORBID structured * Odd.x18Across( :: return 7
// FORBID pseudo * Odd.ipAcross( :: return 5
// FORBID pseudo * Odd.x18Across( :: return 7
// EXPECT structured * Odd.x18Local( :: re:return \(*(arg0|x0) (<< 1|\* 2)\)? \+ 1

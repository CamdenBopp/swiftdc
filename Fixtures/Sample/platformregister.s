// x18 is the platform register: Apple reserves it, and nothing promises
// it survives a call. x18Across(_:) sets x18 = 7, calls ext, and returns
// x18: the value after the call is not proven, so the return is `?`, never
// 7. x18Local(_:) uses x18 with no call between: it returns x * 2 + 1.
// Named as Swift functions (`(Swift.Int) -> Swift.Int`) so the return value
// renders.
.globl _$s16PlatformRegister9x18AcrossyS2iF
.p2align 2
_$s16PlatformRegister9x18AcrossyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x18, #7
    bl _ext
    mov x0, x18
    ldp x29, x30, [sp], #16
    ret

.globl _$s16PlatformRegister8x18LocalyS2iF
.p2align 2
_$s16PlatformRegister8x18LocalyS2iF:
    lsl x18, x0, #1
    add x0, x18, #1
    ret

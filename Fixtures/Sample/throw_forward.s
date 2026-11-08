// Throwing functions that end in a throwing call and `ret`, by hand:
// - ThrowAsm.forward hands its argument on: `return try risky(arg0)`.
// - ThrowAsm.armed sets x21 to 5 before the call. On success risky leaves
//   x21 as it found it, so armed throws the 5 either way: no forward.
// - ThrowAsm.ignored returns 7 whatever risky returned, so the value is
//   not the call's: `_ = try risky(arg0); return 7`, which this does not
//   claim.
// - ThrowAsm.restored writes x21 after the call (`mov x21, x19`): the
//   exit's error is no longer the callee's.
// - ThrowAsm.clobbered calls plain, which throws nothing but leaves x21
//   changed: what x21 then holds is no error the callee threw.
// - ThrowAsm.boxes calls typed, whose `throws(Refused)` error does not
//   travel as an `any Error` in x21: boxes must box it to rethrow.
// - ThrowAsm.combined calls base, then forwards risky plus base's result:
//   `let r0 = base(arg0)` before the forwarded call, `return try
//   (risky(arg0) + r0)`, not base moved after risky into the return.
// risky(n) throws for a negative n (x21 = n) and returns n * 2.
.text
.p2align 2
.globl _$s8ThrowAsm5riskyyS2iKF
_$s8ThrowAsm5riskyyS2iKF:
    tbnz x0, #63, 1f
    lsl x0, x0, #1
    ret
1:  mov x21, x0
    ret

.globl _$s8ThrowAsm7forwardyS2iKF
_$s8ThrowAsm7forwardyS2iKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _$s8ThrowAsm5riskyyS2iKF
    ldp x29, x30, [sp], #16
    ret

.globl _$s8ThrowAsm5armedyS2iKF
_$s8ThrowAsm5armedyS2iKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x21, #5
    bl _$s8ThrowAsm5riskyyS2iKF
    ldp x29, x30, [sp], #16
    ret

.globl _$s8ThrowAsm7ignoredyS2iKF
_$s8ThrowAsm7ignoredyS2iKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _$s8ThrowAsm5riskyyS2iKF
    mov x0, #7
    ldp x29, x30, [sp], #16
    ret

.globl _$s8ThrowAsm8restoredyS2iKF
_$s8ThrowAsm8restoredyS2iKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _$s8ThrowAsm5riskyyS2iKF
    mov x21, x19
    ldp x29, x30, [sp], #16
    ret

.globl _$s8ThrowAsm5plainyS2iF
_$s8ThrowAsm5plainyS2iF:
    mov x21, x0
    add x0, x0, #1
    ret

.globl _$s8ThrowAsm9clobberedyS2iKF
_$s8ThrowAsm9clobberedyS2iKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _$s8ThrowAsm5plainyS2iF
    ldp x29, x30, [sp], #16
    ret

.globl _$s8ThrowAsm5typedyS2iAA7RefusedVYKF
_$s8ThrowAsm5typedyS2iAA7RefusedVYKF:
    tbnz x0, #63, 1f
    lsl x0, x0, #1
    ret
1:  mov x21, #1
    ret

.globl _$s8ThrowAsm5boxesyS2iKF
_$s8ThrowAsm5boxesyS2iKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _$s8ThrowAsm5typedyS2iAA7RefusedVYKF
    ldp x29, x30, [sp], #16
    ret

.globl _$s8ThrowAsm4baseyS2iF
_$s8ThrowAsm4baseyS2iF:
    add x0, x0, #3
    ret

.globl _$s8ThrowAsm8combinedyS2iKF
_$s8ThrowAsm8combinedyS2iKF:
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    mov x20, x0
    bl _$s8ThrowAsm4baseyS2iF
    mov x19, x0
    mov x0, x20
    bl _$s8ThrowAsm5riskyyS2iKF
    add x0, x0, x19
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    ret

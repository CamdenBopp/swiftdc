// Callers of a callee whose result is `Never`, by hand, in the shapes that
// read x0 after it:
// - NoSuccessAsm.stop(n) throws -> Never throws for a negative n (x21 = n,
//   x0 left as scratch) and traps otherwise. It has no success value.
// - NoSuccessAsm.halt(n) throws(Refused) -> Never throws for a negative n
//   with its typed error in x0 (-n) and x21 set, and traps otherwise.
// - NoSuccessAsm.count(n) throws -> Int throws for a negative n and
//   returns n * 2.
// - NoSuccessAsm.ordinary(n) throws(Never) -> Int returns n * 3 and cannot
//   throw: the Never is the thrown type, not the result.
// - nosuccess_opaque has no signature and returns n + 5.
// - NoSuccessAsm.relay ends in `bl stop`, its epilogue and `ret`: it
//   throws what stop threw, and returns nothing of stop's.
// - NoSuccessAsm.code calls halt and returns x0 + 1: the error payload
//   plus one, which is no value of halt's.
// - NoSuccessAsm.relayCount is relay over count: `return try count(arg0)`.
// - NoSuccessAsm.useOrdinary returns ordinary(n) + 1.
// - NoSuccessAsm.useOpaque returns nosuccess_opaque(n) + 1.
.text
.p2align 2
.globl _$s12NoSuccessAsm4stopys5NeverOSiKF
_$s12NoSuccessAsm4stopys5NeverOSiKF:
    tbnz x0, #63, 1f
    brk #1
1:  mov x21, x0
    lsl x0, x0, #1
    ret

.globl _$s12NoSuccessAsm4haltys5NeverOSiAA7RefusedVYKF
_$s12NoSuccessAsm4haltys5NeverOSiAA7RefusedVYKF:
    tbnz x0, #63, 1f
    brk #1
1:  neg x0, x0
    mov x21, #1
    ret

.globl _$s12NoSuccessAsm5countyS2iKF
_$s12NoSuccessAsm5countyS2iKF:
    tbnz x0, #63, 1f
    lsl x0, x0, #1
    ret
1:  mov x21, x0
    ret

.globl _$s12NoSuccessAsm8ordinaryyS2is5NeverOYKF
_$s12NoSuccessAsm8ordinaryyS2is5NeverOYKF:
    add x0, x0, x0, lsl #1
    ret

.globl _nosuccess_opaque
_nosuccess_opaque:
    add x0, x0, #5
    ret

.globl _$s12NoSuccessAsm5relayyS2iKF
_$s12NoSuccessAsm5relayyS2iKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _$s12NoSuccessAsm4stopys5NeverOSiKF
    ldp x29, x30, [sp], #16
    ret

.globl _$s12NoSuccessAsm4codeyS2iF
_$s12NoSuccessAsm4codeyS2iF:
    stp x22, x21, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    mov x21, #0
    bl _$s12NoSuccessAsm4haltys5NeverOSiAA7RefusedVYKF
    add x0, x0, #1
    ldp x29, x30, [sp, #16]
    ldp x22, x21, [sp], #32
    ret

.globl _$s12NoSuccessAsm10relayCountyS2iKF
_$s12NoSuccessAsm10relayCountyS2iKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _$s12NoSuccessAsm5countyS2iKF
    ldp x29, x30, [sp], #16
    ret

.globl _$s12NoSuccessAsm11useOrdinaryyS2iF
_$s12NoSuccessAsm11useOrdinaryyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _$s12NoSuccessAsm8ordinaryyS2is5NeverOYKF
    add x0, x0, #1
    ldp x29, x30, [sp], #16
    ret

.globl _$s12NoSuccessAsm9useOpaqueyS2iF
_$s12NoSuccessAsm9useOpaqueyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _nosuccess_opaque
    add x0, x0, #1
    ldp x29, x30, [sp], #16
    ret

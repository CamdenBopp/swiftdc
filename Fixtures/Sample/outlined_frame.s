// An outlined fragment that moves the caller's frame pointer, inlined at a
// `bl`. `thing() throws` spills its incoming x21 (Swift's error register,
// zero on entry) to [x29, #16] the way -Onone does and reloads it from
// [x29, #16] on the way out. In between, `bl _OUTLINED_FUNCTION_0` runs
// `add x29, sp, #8; b _swift_retain`: x29 now points 8 bytes higher, so
// the reload reads [sp, #24], not the spill.
//
// True behaviour: x21 at the `ret` is whatever [sp, #24] held, not the
// entry's zero, so no normal return is proven. With the site rendered as
// `bl swift_retain`, a pass that reads the instructions sees x29 unchanged
// unless it counts the inlined prefix's writes as the call's.
    .text
    .globl _$s4Test5thingyyKF
    .p2align 2
_$s4Test5thingyyKF:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x21, [x29, #16]
    bl _OUTLINED_FUNCTION_0
    ldr x21, [x29, #16]
    ldp x29, x30, [sp], #32
    ret

    .p2align 2
_OUTLINED_FUNCTION_0:
    add x29, sp, #8
    b _swift_retain

// The control: the same body with a fragment that leaves x29 alone
// (`mov x1, #0; b _swift_retain`). Its reload is the spill, and the normal
// return is proven.
    .globl _$s4Test7controlyyKF
    .p2align 2
_$s4Test7controlyyKF:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x21, [x29, #16]
    bl _OUTLINED_FUNCTION_1
    ldr x21, [x29, #16]
    ldp x29, x30, [sp], #32
    ret

    .p2align 2
_OUTLINED_FUNCTION_1:
    mov x1, #0
    b _swift_retain

// x20 is an async throwing function's error at its return through the
// context's ResumeParent. Both bodies call a fragment that rewrites it
// (`add x20, sp, #8; b _swift_retain`), the site rendering as `bl
// swift_retain`.
//
// True behaviour: `cleared` zeroes x20 and then the fragment makes it
// non-zero, so its `mov x20, #0` proves nothing at the exit. `relay` tests
// x20 and the fragment rewrites it on the non-zero edge, so the exit there
// is no rethrow of what the test saw.
    .globl _$s4Test7clearedyyYaKF
    .p2align 2
_$s4Test7clearedyyYaKF:
    str x30, [sp, #-16]!
    mov x20, #0
    bl _OUTLINED_FUNCTION_2
    ldr x1, [x22, #8]
    ldr x30, [sp], #16
    br x1

    .globl _$s4Test5relayyyYaKF
    .p2align 2
_$s4Test5relayyyYaKF:
    str x30, [sp, #-16]!
    cbz x20, Lrelay_clear
    bl _OUTLINED_FUNCTION_2
    ldr x1, [x22, #8]
    ldr x30, [sp], #16
    br x1
Lrelay_clear:
    mov x20, #0
    ldr x1, [x22, #8]
    ldr x30, [sp], #16
    br x1

    .p2align 2
_OUTLINED_FUNCTION_2:
    add x20, sp, #8
    b _swift_retain

.section __TEXT,__swift_as_entry,regular,no_dead_strip
.p2align 2
.long _$s4Test7clearedyyYaKF-.
.long _$s4Test5relayyyYaKF-.

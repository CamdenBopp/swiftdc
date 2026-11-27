// x0 read after a call to a name twin of a void runtime entry point.
//
// The runtime's swift_job_run, swift_willThrow and swift_willThrowTypedImpl
// return nothing, so x0 after a call to one is no result. voidruntimetwin.c
// defines functions of those names in this image that do return a value.
// Nothing in a call site tells the two apart except the binding, and
// swift_willThrow has no row in the provider table, so its binding is
// never proven: after a call under one of these names x0 is claimed by
// nothing. The compiler does not emit these, and it refuses a Swift
// declaration of swift_job_run with another type: they are the smallest
// bodies in which the name and the behaviour disagree. The `add` keeps
// each call from being a tail branch.
.text
.p2align 2

// VoidRuntimeTwin.afterJobRun(Swift.Int) -> Swift.Int
// Returns p * 3 + 38.
.globl _$s15VoidRuntimeTwin11afterJobRunyS2iF
_$s15VoidRuntimeTwin11afterJobRunyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _swift_job_run
    add x0, x0, #1
    ldp x29, x30, [sp], #16
    ret

// VoidRuntimeTwin.afterWillThrow(Swift.Int) -> Swift.Int
// Returns p * 5 + 42.
.globl _$s15VoidRuntimeTwin14afterWillThrowyS2iF
_$s15VoidRuntimeTwin14afterWillThrowyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _swift_willThrow
    add x0, x0, #1
    ldp x29, x30, [sp], #16
    ret

// VoidRuntimeTwin.afterTypedImpl(Swift.Int) -> Swift.Int
// Returns p * 7 + 44.
.globl _$s15VoidRuntimeTwin14afterTypedImplyS2iF
_$s15VoidRuntimeTwin14afterTypedImplyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _swift_willThrowTypedImpl
    add x0, x0, #1
    ldp x29, x30, [sp], #16
    ret

// VoidRuntimeTwin.afterPlain(Swift.Int) -> Swift.Int
// The control: returns p * 9 + 48, the result of a call no table names.
.globl _$s15VoidRuntimeTwin10afterPlainyS2iF
_$s15VoidRuntimeTwin10afterPlainyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _plain_result
    add x0, x0, #1
    ldp x29, x30, [sp], #16
    ret

// Authored throwing functions in which one path calls the runtime's
// swift_willThrow and another leaves with the same value in x21 and no
// hook. A Swift function throws by returning with x21 non-zero. Where the
// hook ran, its value is an error. Where it did not, the value is the
// second argument, which may be zero: a normal return. The compiler does
// not emit these; they are the smallest bodies in which the hook's
// evidence is true on one path only.
.text
.p2align 2

// HookPath.either(Swift.Bool, Swift.Int) throws -> Swift.Int
// Two exits. b set: hook, then throw the argument. b clear: x21 = the
// argument, x0 = 7, return or throw as the argument is zero or not.
.globl _$s8HookPath6eitherySiSb_SitKF
_$s8HookPath6eitherySiSb_SitKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    tbz w0, #0, 1f
    mov x21, x1
    bl _swift_willThrow
    ldp x29, x30, [sp], #16
    ret
1:
    mov x21, x1
    mov x0, #7
    ldp x29, x30, [sp], #16
    ret

// HookPath.merged(Swift.Bool, Swift.Int) throws -> Swift.Int
// The same two paths into one shared ret.
.globl _$s8HookPath6mergedySiSb_SitKF
_$s8HookPath6mergedySiSb_SitKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x21, x1
    tbz w0, #0, 2f
    bl _swift_willThrow
    b 3f
2:
    mov x0, #7
3:
    ldp x29, x30, [sp], #16
    ret

// HookPath.always(Swift.Bool, Swift.Int) throws -> Swift.Int
// The control: the hook runs on every path, before the branch. x19 holds
// the flag across the call and is saved: run natively without that, the
// caller's x19 was gone (sprintnative.c found it).
.globl _$s8HookPath6alwaysySiSb_SitKF
_$s8HookPath6alwaysySiSb_SitKF:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    mov x21, x1
    mov x19, x0
    bl _swift_willThrow
    tbz w19, #0, 4f
    mov x0, #1
4:
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

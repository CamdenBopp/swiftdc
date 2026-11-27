// Authored callers of an in-image function named swift_willThrow
// (willthrowtwin.c), which reads x0 and returns x0 * 5 + 41. The
// runtime's hook of that name takes the thrown error in x21 and nothing
// in x0, and is called only with an error about to be thrown. Neither is
// true of this one. The compiler does not emit these: they are the
// smallest bodies in which the name and the behaviour disagree.
.text
.p2align 2

// WillThrowTwin.plain(Swift.Int) -> Swift.Int
// Calls the twin with its argument. Returns p * 5 + 42.
.globl _$s13WillThrowTwin5plainyS2iF
_$s13WillThrowTwin5plainyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _swift_willThrow
    add x0, x0, #1
    ldp x29, x30, [sp], #16
    ret

// WillThrowTwin.stale(Swift.Int, Swift.Int) -> Swift.Int
// x21 holds the second argument at the call; the twin is called with the
// first. Returns a * 5 + 43. x21 is saved and restored.
.globl _$s13WillThrowTwin5staleyS2i_SitF
_$s13WillThrowTwin5staleyS2i_SitF:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x21, [sp, #16]
    mov x21, x1
    bl _swift_willThrow
    add x0, x0, #2
    ldr x21, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

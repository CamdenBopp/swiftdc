// Authored throwing functions that return normally after calling a
// function spelled like the error runtime's (errorlookalike.c). A Swift
// function throws by returning with x21 non-zero; each of these returns
// with x21 zero or with whatever its callee returned, which is null.
// The compiler does not emit these: they are the smallest bodies in
// which the spelling and the behaviour disagree.
.text
.p2align 2

// Lookalike.viaAllocLog(Swift.Int) throws -> Swift.Int
// x21 = swift_allocErrorLog(x), which is null. Returns 5: no error.
.globl _$s9Lookalike11viaAllocLogyS2iKF
_$s9Lookalike11viaAllocLogyS2iKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _swift_allocErrorLog
    mov x21, x0
    mov x0, #5
    ldp x29, x30, [sp], #16
    ret

// Lookalike.viaLocalAlloc(Swift.Int) throws -> Swift.Int
// The same through this image's own swift_allocError. Returns 7.
.globl _$s9Lookalike13viaLocalAllocyS2iKF
_$s9Lookalike13viaLocalAllocyS2iKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _swift_allocError
    mov x21, x0
    mov x0, #7
    ldp x29, x30, [sp], #16
    ret

// Lookalike.viaWillThrowLog(Swift.Int) throws -> Swift.Int
// x21 is zero at the lookalike's call and at the ret. Returns 6.
.globl _$s9Lookalike15viaWillThrowLogyS2iKF
_$s9Lookalike15viaWillThrowLogyS2iKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x21, #0
    bl _swift_willThrowLookalike
    mov x0, #6
    ldp x29, x30, [sp], #16
    ret

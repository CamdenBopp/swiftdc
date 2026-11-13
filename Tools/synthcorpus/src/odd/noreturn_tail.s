// Functions that end in a call to a noreturn function, with no `ret`.
//
// Odd.check(_:): if x < 0 calls abort(); otherwise returns x. The abort
// path never returns, so it must not render a `return` of any value,
// `return ?` included.
//
// Odd.guarded(_:): a stack-protector epilogue. Copies the guard into a slot,
// computes x + 5, compares the slot with the guard and returns x + 5 on a
// match; otherwise calls __stack_chk_fail (noreturn) with no `ret` after it.
//
// Odd.dieInt(): typed as returning Int, but calls abort() with nothing
// after it; `Odd.next()` (returns 9) starts right after the `bl`. True
// behaviour: dieInt never returns. next's `return 9` is not dieInt's.
.text
.globl _$s3Odd5checkyS2iF
.p2align 2
_$s3Odd5checkyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    tbnz x0, #63, 1f
    ldp x29, x30, [sp], #16
    ret
1:
    bl _abort

.globl _$s3Odd7guardedyS2iF
.p2align 2
_$s3Odd7guardedyS2iF:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    adrp x8, ___stack_chk_guard@GOTPAGE
    ldr x8, [x8, ___stack_chk_guard@GOTPAGEOFF]
    ldr x9, [x8]
    str x9, [sp, #24]
    add x0, x0, #5
    ldr x10, [sp, #24]
    ldr x9, [x8]
    cmp x9, x10
    b.ne 1f
    ldp x29, x30, [sp], #32
    ret
1:
    bl ___stack_chk_fail

.globl _$s3Odd6dieIntSiyF
.p2align 2
_$s3Odd6dieIntSiyF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _abort
.globl _$s3Odd4nextSiyF
_$s3Odd4nextSiyF:
    mov x0, #9
    ret

// EXPECT structured * Odd.check( :: abort
// EXPECT structured * Odd.check( :: re:(?m)return (arg0|x0)[ \t]*$
// FORBID structured * Odd.check( :: return ?
// FORBID structured * Odd.check( :: re:(?m)return[ \t]*$
// EXPECT structured * Odd.guarded( :: __stack_chk_fail
// EXPECT structured * Odd.guarded( :: re:return \(?(arg0|x0) \+ 5
// FORBID structured * Odd.guarded( :: return ?
// EXPECT structured * Odd.dieInt( :: abort
// FORBID structured * Odd.dieInt( :: return 9
// FORBID structured * Odd.dieInt( :: return ?
// FORBID pseudo * Odd.dieInt( :: return 9
// FORBID pseudo * Odd.dieInt( :: return ?
// EXPECT structured * Odd.next( :: return 9

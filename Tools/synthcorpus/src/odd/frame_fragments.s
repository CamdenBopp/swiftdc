// Outlined fragments that run on their caller's frame.
//
// Odd.usesFrag(_:_:): stores x1 at [sp, #8] of its own frame, then
// `bl _OUTLINED_read8`, a fragment that reads [sp, #8] (the caller's slot:
// `bl` does not move sp) and returns it plus x0. True behaviour: returns
// x0 + x1. The fragment reads a slot it never wrote, so its own render
// must not present that read as a known value, and the caller must not
// claim the fragment's call takes only x0 or returns x0 unchanged.
//
// Odd.usesEpi(_:): sets up a frame, computes x * 3, and leaves through
// `b _OUTLINED_epilog`, a fragment that pops the caller's frame
// (`ldp x29, x30, [sp], #16`) and returns. True behaviour: returns x * 3.
//
// Odd.usesPro(_:): saves x30 in x16, `bl _OUTLINED_prolog` (pushes
// x20/x19 below the caller's sp and returns with sp moved), restores x30,
// builds a frame, keeps x + 2 in x19 across a call to sink, and pops both
// frames. True behaviour: returns x + 2.
.text
.globl _$s3Odd8usesFragyS2i_SitF
.p2align 2
_$s3Odd8usesFragyS2i_SitF:
    sub sp, sp, #32
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    str x1, [sp, #8]
    bl _OUTLINED_read8
    ldp x29, x30, [sp, #16]
    add sp, sp, #32
    ret

.p2align 2
_OUTLINED_read8:
    ldr x9, [sp, #8]
    add x0, x0, x9
    ret

.globl _$s3Odd7usesEpiyS2iF
.p2align 2
_$s3Odd7usesEpiyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    add x0, x0, x0, lsl #1
    b _OUTLINED_epilog

.p2align 2
_OUTLINED_epilog:
    ldp x29, x30, [sp], #16
    ret

.globl _$s3Odd7usesProyS2iF
.p2align 2
_$s3Odd7usesProyS2iF:
    mov x16, x30
    bl _OUTLINED_prolog
    mov x30, x16
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    add x19, x0, #2
    bl _sink
    mov x0, x19
    ldp x29, x30, [sp], #16
    ldp x20, x19, [sp], #16
    ret

.p2align 2
_OUTLINED_prolog:
    stp x20, x19, [sp, #-16]!
    ret

// FORBID structured * Odd.usesFrag( :: re:_OUTLINED_read8\((arg0|x0)\)
// FORBID structured * Odd.usesFrag( :: re:(?m)return (arg0|x0)[ \t]*$
// FORBID structured * Odd.usesFrag( :: re:(?m)return (arg1|x1)[ \t]*$
// FORBID structured * Odd.usesEpi( :: re:(?m)return[ \t]*$
// FORBID structured * Odd.usesEpi( :: re:(?m)return (arg0|x0)[ \t]*$
// FORBID structured * Odd.usesPro( :: re:(?m)return (arg0|x0)[ \t]*$

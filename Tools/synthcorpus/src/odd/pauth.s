// Pointer-authentication instructions.
//
// Odd.signedFrame(_:): `pacibsp` / `retab` around a framed call. True
// behaviour: returns ext(x + 1).
//
// Odd.authLoad(_:_:) (x0 = p, x1 = mod): `autia x0, x1` then loads [x0].
// True behaviour: returns the word at auth(p, mod), the authenticated and
// stripped pointer (a failed check faults on the load). It must not render
// as returning p, or as loading through mod.
//
// Odd.authCall(_:_:_:) (x0 = fn, x1 = disc, x2 = arg): `blraa x8, x9`, a call
// through fn with discriminator disc, arg in x0. True behaviour: returns
// fn(arg).
//
// Odd.authTail(_:_:) (x0 = fn, x1 = disc): `braa x16, x17`, a tail call
// through an authenticated pointer, x0 and x1 left in place. True
// behaviour: returns fn(...) of unknown arity. Must not render a plain
// return or return one of its own arguments.
.text
.arch armv8.3-a
.globl _$s3Odd11signedFrameyS2iF
.p2align 2
_$s3Odd11signedFrameyS2iF:
    pacibsp
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    add x0, x0, #1
    bl _ext
    ldp x29, x30, [sp], #16
    retab

.globl _$s3Odd8authLoadyS2i_SitF
.p2align 2
_$s3Odd8authLoadyS2i_SitF:
    autia x0, x1
    ldr x0, [x0]
    ret

.globl _$s3Odd8authCallyS2i_S2itF
.p2align 2
_$s3Odd8authCallyS2i_S2itF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x8, x0
    mov x9, x1
    mov x0, x2
    blraa x8, x9
    ldp x29, x30, [sp], #16
    ret

.globl _$s3Odd8authTailyS2i_SitF
.p2align 2
_$s3Odd8authTailyS2i_SitF:
    mov x16, x0
    mov x17, x1
    braa x16, x17

// EXPECT structured * Odd.signedFrame( :: re:\bext\(
// EXPECT structured * Odd.signedFrame( :: re:return
// FORBID structured * Odd.signedFrame( :: re:(?m)return[ \t]*$
// FORBID structured * Odd.signedFrame( :: re:(?m)return (arg0|x0) \+ 1[ \t]*$
// FORBID structured * Odd.authLoad( :: re:(?m)return (arg0|x0)[ \t]*$
// FORBID structured * Odd.authLoad( :: re:\*\(?(arg1|x1)\b|\[(arg1|x1)\]
// FORBID structured * Odd.authLoad( :: re:(?m)\*\(?(arg0|x0)\)?[ \t]*$
// FORBID structured * Odd.authCall( :: re:(?m)return (arg2|x2|arg0|x0)[ \t]*$
// FORBID structured * Odd.authCall( :: re:(?m)return[ \t]*$
// FORBID structured * Odd.authTail( :: re:(?m)return[ \t]*$
// FORBID structured * Odd.authTail( :: re:(?m)return (arg[01]|x[01])[ \t]*$

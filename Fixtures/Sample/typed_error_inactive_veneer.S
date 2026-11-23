#ifndef INACTIVE_X0
#error "Define INACTIVE_X0 as 0 or 1"
#endif

.text
.p2align 2
.globl _$s15TypedErrorProbe12probeWrappedyAA8BigValueVSiAA11TinyFailureOYKF
_$s15TypedErrorProbe12probeWrappedyAA8BigValueVSiAA11TinyFailureOYKF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    // Exact probeIndirect ABI: x8 success buffer, x0 mode, x1 error buffer,
    // x21 error discriminator. The delegate initializes the active buffer.
    bl _$s15TypedErrorProbe13probeIndirectyAA8BigValueVSiAA11TinyFailureOYKF
    cbz x21, Lsuccess
    // The typed-error flag is already one. Restating it here keeps the
    // regression focused on projection, not a separate nonzero-edge proof.
    mov w21, #1
    mov w0, #INACTIVE_X0
    ldp x29, x30, [sp], #16
    ret
Lsuccess:
    ldp x29, x30, [sp], #16
    ret
.subsections_via_symbols

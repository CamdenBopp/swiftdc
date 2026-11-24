// Authored typed-throwing functions whose error travels through memory
// while x0 holds the tag of a different case. Each follows the indirect
// typed-error convention: the thrown case is stored through the error
// buffer, x21 is the non-zero flag, and x0 is undefined to the caller. The
// compiler leaves x0 as it happens to be; these set it to 1, the tag of
// ErrorCarrier.Fault.mid, which neither function throws. The types are
// errorcarrier.swift's.
.text
.p2align 2

// ErrorCarrier.wide(Swift.Int) throws(ErrorCarrier.Fault) -> ErrorCarrier.Quint
// A five-word result: x8 is the result buffer, x0 mode, x1 the error
// buffer. mode == 0: throws .high (tag 2, stored through x1). Otherwise
// returns a Quint of five sevens through x8.
.globl _$s12ErrorCarrier4wideyAA5QuintVSiAA5FaultOYKF
_$s12ErrorCarrier4wideyAA5QuintVSiAA5FaultOYKF:
    cbnz x0, 1f
    mov w9, #2
    strb w9, [x1]
    mov w21, #1
    mov w0, #1
    ret
1:
    mov x9, #7
    stp x9, x9, [x8]
    stp x9, x9, [x8, #16]
    str x9, [x8, #32]
    ret

// ErrorCarrier.opaque<A>(A, Swift.Int) throws(ErrorCarrier.Fault) -> A
// A generic result is returned by address: x8 is the result buffer, x0 the
// borrowed value's address, x1 mode, x2 A's metadata, x3 the error buffer.
// Always throws .high (tag 2, stored through x3); the result buffer is
// left uninitialized, as a throw leaves it.
.globl _$s12ErrorCarrier6opaqueyxx_SitAA5FaultOYKlF
_$s12ErrorCarrier6opaqueyxx_SitAA5FaultOYKlF:
    mov w9, #2
    strb w9, [x3]
    mov w21, #1
    mov w0, #1
    ret
.subsections_via_symbols

.text
.p2align 2
.globl _$s8SelfRole4TinyV4readSiyF
_$s8SelfRole4TinyV4readSiyF:
    sub sp, sp, #48
    stp x20, x30, [sp, #32]
    mov x20, x0
    str xzr, [sp]
    mov x0, sp
    bl _selfrole_touch
    mov x0, x20
    ldp x20, x30, [sp, #32]
    add sp, sp, #48
    ret

// A load excludes the current literal-store-only body summary. Native code
// reads and changes only its one-word local, never the saved entry x20.
.globl _selfrole_touch
_selfrole_touch:
    ldr x8, [x0]
    add x8, x8, #1
    str x8, [x0]
    ret

// A no-argument Int wrapper also follows the C register/stack convention.
// Its fresh x20 is an unrelated frame address; Tiny's self is the x0 word.
.globl _$s8SelfRole7wrapperSiyF
_$s8SelfRole7wrapperSiyF:
    sub sp, sp, #48
    stp x20, x30, [sp, #32]
    add x20, sp, #16
    mov x0, #7
    bl _$s8SelfRole4TinyV4readSiyF
    ldp x20, x30, [sp, #32]
    add sp, sp, #48
    ret

// Positive: an actual context self, read directly through entry x20.
.globl _$s8SelfRole4TinyV12mutatingReadSiyF
_$s8SelfRole4TinyV12mutatingReadSiyF:
    ldr x0, [x20]
    ret

// Positive: preserve a proven context role through an in-image tail forwarder.
.globl _$s8SelfRole4TinyV14forwardingReadSiyF
_$s8SelfRole4TinyV14forwardingReadSiyF:
    b _$s8SelfRole4TinyV12mutatingReadSiyF

.globl _$s8SelfRole14contextWrapperSiyF
_$s8SelfRole14contextWrapperSiyF:
    sub sp, sp, #48
    stp x20, x30, [sp, #32]
    mov x8, #9
    str x8, [sp, #16]
    add x20, sp, #16
    bl _$s8SelfRole4TinyV12mutatingReadSiyF
    ldp x20, x30, [sp, #32]
    add sp, sp, #48
    ret

.globl _$s8SelfRole17forwardingWrapperSiyF
_$s8SelfRole17forwardingWrapperSiyF:
    sub sp, sp, #48
    stp x20, x30, [sp, #32]
    mov x8, #11
    str x8, [sp, #16]
    add x20, sp, #16
    bl _$s8SelfRole4TinyV14forwardingReadSiyF
    ldp x20, x30, [sp, #32]
    add sp, sp, #48
    ret

// A real context ABI that never consumes self. An unknown call can still
// read its saved x20; neither that MAY read nor absence of positive context
// evidence proves a value receiver in the unrelated incoming x0.
.globl _$s8SelfRole4TinyV13unusedContextSiyF
_$s8SelfRole4TinyV13unusedContextSiyF:
    sub sp, sp, #48
    stp x20, x30, [sp, #32]
    mov x20, #0
    str xzr, [sp]
    mov x0, sp
    bl _selfrole_touch
    mov x0, #42
    ldp x20, x30, [sp, #32]
    add sp, sp, #48
    ret

.globl _$s8SelfRole13unusedWrapperSiyF
_$s8SelfRole13unusedWrapperSiyF:
    sub sp, sp, #48
    stp x20, x30, [sp, #32]
    add x20, sp, #16
    mov x0, #29
    bl _$s8SelfRole4TinyV13unusedContextSiyF
    ldp x20, x30, [sp, #32]
    add sp, sp, #48
    ret

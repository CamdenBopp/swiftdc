// x20 is a value type's `self` only when the type passes it there. A
// system module's frozen struct passes a loadable `self` as its words
// after the formals: Duration.components.getter is `(i64, i64)`, so the 7
// in x20 is no receiver. A resilient one passes `self` by address in x20:
// Date.timeIntervalSince1970.getter is `(ptr swiftself)`, whatever the
// caller put there.
    .text
    .p2align 2
    .globl _frozenSelf
_frozenSelf:
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    mov x20, #7
    mov x0, #1
    mov x1, #2
    bl _$ss8DurationV10componentss5Int64V7seconds_AE11attosecondstvg
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    ret
    .globl _resilientSelf
_resilientSelf:
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    mov x20, #7
    bl _$s10Foundation4DateV21timeIntervalSince1970Sdvg
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    ret

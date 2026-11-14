// A call of a resilient struct's getter whose receiver this image gives
// no way to trace: x20 is whatever the caller of `_untraced_total` left
// there. The getter still takes a receiver in x20, so the call renders
// `RS.Point.total.getter(self: ?)`, never `RS.Point.total.getter()`.
        .text
        .globl _untraced_total
        .p2align 2
_untraced_total:
        stp x29, x30, [sp, #-16]!
        mov x29, sp
        bl _$s2RS5PointV5totalSivg
        add x0, x0, #1
        ldp x29, x30, [sp], #16
        ret

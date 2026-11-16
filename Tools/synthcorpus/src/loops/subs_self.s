// Hand-written loops whose flag-setting instruction writes the register it
// compares (`subs w19, w19, #k` / `adds x19, x19, #k`), followed by an
// ordered condition. The flags describe the *pre-step* operand against k
// exactly (gt after `subs a, a, #3` is `old a > 3`, signed); the stepped
// value against 0 agrees only when the step does not wrap. Raw `x19`/`w19`
// at the branch means the stepped value, so `w19 > 3` is one step off and
// `w19 > 0` is wrong at the wrap. A correct render declines (`?`) or names
// the pre-step value (`(i - 3) > 0` on the old i).
//
// _subs_gt(w0 = n):      w19 = n; do { sink(w19); } while (old w19 > 3, signed 32-bit; w19 -= 3)
// _adds_lt(x0 = n):      x19 = n; do { sink(x19); } while (old x19 + 5 < 0 without overflow, i.e. N != V)
// _subs_hi(w0 = n):      w19 = n; do { sink(w19); } while (old w19 >u 2; w19 -= 2)
// _subs_ge_cmp0(w0 = n): w19 = n; do { sink(w19); } while (old w19 >= 1 signed; w19 -= 1)
//
// FORBID structured * _subs_gt :: re:\b[wx]19 >
// FORBID structured * _adds_lt :: re:\bx19 <
// FORBID structured * _subs_hi :: re:\b[wx]19 >
// FORBID structured * _subs_ge_cmp0 :: re:\b[wx]19 >=
// Each loop's call survives:
// EXPECT structured * _subs_gt :: sink(
// EXPECT structured * _adds_lt :: sink(
.text
.globl _subs_gt
.p2align 2
_subs_gt:
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    mov w19, w0
1:
    mov w0, w19
    bl _sink
    subs w19, w19, #3
    b.gt 1b
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    ret

.globl _adds_lt
.p2align 2
_adds_lt:
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    mov x19, x0
1:
    mov x0, x19
    bl _sink
    adds x19, x19, #5
    b.lt 1b
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    ret

.globl _subs_hi
.p2align 2
_subs_hi:
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    mov w19, w0
1:
    mov w0, w19
    bl _sink
    subs w19, w19, #2
    b.hi 1b
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    ret

.globl _subs_ge_cmp0
.p2align 2
_subs_ge_cmp0:
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    mov w19, w0
1:
    mov w0, w19
    bl _sink
    subs w19, w19, #1
    b.ge 1b
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    ret

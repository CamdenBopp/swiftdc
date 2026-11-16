// Functions that write sp in unusual ways.
//
// Odd.allocaFill(_:_:) (x0 = n, x1 = v): an alloca. Rounds n up to 16,
// moves sp down with `sub sp, sp, x8`, stores v at the new sp, passes the
// buffer to use(buf) and returns use's result after restoring sp from x29.
// True behaviour: returns use(buf) where buf[0] == v.
//
// Odd.movSP(_:) (x0 = n): computes a new stack top in x9 and installs it
// with `mov sp, x9`, stores 42 there, reloads it, restores sp with
// `mov sp, x29` and returns the reloaded value. True behaviour: returns
// 42. The slot's offset from the entry sp depends on n, so the store and
// the reload alias only because both go through the same new sp.
.text
.globl _$s3Odd10allocaFillyS2i_SitF
.p2align 2
_$s3Odd10allocaFillyS2i_SitF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    add x8, x0, #15
    and x8, x8, #0xfffffffffffffff0
    sub sp, sp, x8
    str x1, [sp]
    mov x0, sp
    bl _use
    mov sp, x29
    ldp x29, x30, [sp], #16
    ret

.globl _$s3Odd5movSPyS2iF
.p2align 2
_$s3Odd5movSPyS2iF:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    lsl x8, x0, #4
    mov x9, sp
    sub x9, x9, x8
    sub x9, x9, #16
    mov sp, x9
    mov x10, #42
    str x10, [sp]
    ldr x0, [sp]
    mov sp, x29
    ldp x29, x30, [sp], #16
    ret

// EXPECT structured * Odd.allocaFill( :: re:\buse\(
// FORBID structured * Odd.allocaFill( :: re:(?m)return (arg1|x1|arg0|x0)[ \t]*$
// FORBID structured * Odd.allocaFill( :: re:\buse\(\)
// FORBID structured * Odd.movSP( :: re:(?m)return (arg0|x0)[ \t]*$
// FORBID structured * Odd.movSP( :: re:(?m)return (?!(42|0x2a|\?)[ \t]*$)\S

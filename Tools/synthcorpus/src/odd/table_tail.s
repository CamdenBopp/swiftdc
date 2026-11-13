// Tail calls through `br` to a register loaded from a table.
//
// Odd.dispatch(_:_:) (x0 = i, x1 = arg): loads handler i from `_handlers`
// (a pointer table in __DATA holding h0, h1) into x16 and `br x16`s to it
// with x0 = arg. True behaviour: returns handlers[i](arg), i.e.
// h0(arg) = arg + 1 or h1(arg) = arg * 4 (index unchecked). The callee is
// not one fixed function: the render must not name h0 or h1 as the callee,
// must not return a value that ignores the call, and must not present the
// unknown callee as taking no arguments.
//
// Odd.dispatchFixed(_:): the same with a constant index 1. True behaviour:
// returns h1(x) = x * 4. Naming h1 is provable from the table's rebased
// contents (if the table is not written elsewhere: it is writable __DATA,
// so declining is also right); naming h0 is wrong.
.text
.globl _$s3Odd8dispatchyS2i_SitF
.p2align 2
_$s3Odd8dispatchyS2i_SitF:
    adrp x8, _handlers@PAGE
    add x8, x8, _handlers@PAGEOFF
    ldr x16, [x8, x0, lsl #3]
    mov x0, x1
    br x16

.globl _$s3Odd2h0yS2iF
.p2align 2
_$s3Odd2h0yS2iF:
    add x0, x0, #1
    ret

.globl _$s3Odd2h1yS2iF
.p2align 2
_$s3Odd2h1yS2iF:
    lsl x0, x0, #2
    ret

.globl _$s3Odd13dispatchFixedyS2iF
.p2align 2
_$s3Odd13dispatchFixedyS2iF:
    adrp x8, _handlers@PAGE
    add x8, x8, _handlers@PAGEOFF
    ldr x16, [x8, #8]
    br x16

.data
.p2align 3
.globl _handlers
_handlers:
    .quad _$s3Odd2h0yS2iF
    .quad _$s3Odd2h1yS2iF

// FORBID structured * Odd.dispatch( :: re:\bh0\(
// FORBID structured * Odd.dispatch( :: re:\bh1\(
// FORBID structured * Odd.dispatch( :: re:(?m)return[ \t]*$
// FORBID structured * Odd.dispatch( :: re:(?m)return (arg[01]|x[01])[ \t]*$
// FORBID structured * Odd.dispatch( :: re:x16\(\)
// FORBID structured * Odd.dispatchFixed( :: re:\bh0\b
// FORBID structured * Odd.dispatchFixed( :: re:(?m)return[ \t]*$
// FORBID structured * Odd.dispatchFixed( :: re:(?m)return (arg0|x0)[ \t]*$
// EXPECT structured * Odd.h1( :: re:return \(?(x0|arg0) (<< 2|\* 4)

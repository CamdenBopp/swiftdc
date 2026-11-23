// Data inside __text.
//
// Odd.bigConst(): a literal pool after the `ret` (`ldr x0, Lpool` is a
// pc-relative literal load of 8 bytes). True behaviour: returns
// 0x1122334455667788. Both words of the pool are data, not instructions:
// the second word happens to decode (`add w4, w26, #0x88c`), and no view
// may present it as code of bigConst or say bigConst continues past its
// `ret` into the next function.
//
// Odd.tswitch(_:): an inline byte jump table directly after the `br`,
// clang's compact-table lowering (`adr` base; `ldrb`; `add …, lsl #2`;
// `br`) with the table in __text. True behaviour: 0 -> 10, 1 -> 20,
// 2 -> 30, anything else (unsigned > 2) -> 0.
//
// Odd.constSwitch(_:): the same table placed in __TEXT,__const, the place
// clang puts it. Same true behaviour.
.text
.globl _$s3Odd8bigConstSiyF
.p2align 2
_$s3Odd8bigConstSiyF:
    ldr x0, Lpool
    ret
.p2align 3
Lpool:
    .quad 0x1122334455667788

.globl _$s3Odd7tswitchyS2iF
.p2align 2
_$s3Odd7tswitchyS2iF:
    cmp x0, #2
    b.hi Ldefault
    adr x9, Lcase0
    adr x10, Ltable
    ldrb w11, [x10, x0]
    add x9, x9, x11, lsl #2
    br x9
Ltable:
    .byte 0, 2, 4, 0
Lcase0:
    mov x0, #10
    ret
    mov x0, #20
    ret
    mov x0, #30
    ret
Ldefault:
    mov x0, #0
    ret

.globl _$s3Odd11constSwitchyS2iF
.p2align 2
_$s3Odd11constSwitchyS2iF:
    cmp x0, #2
    b.hi Lcdefault
    adr x9, Lccase0
    adrp x10, Lctable@PAGE
    add x10, x10, Lctable@PAGEOFF
    ldrb w11, [x10, x0]
    add x9, x9, x11, lsl #2
    br x9
Lccase0:
    mov x0, #10
    ret
    mov x0, #20
    ret
    mov x0, #30
    ret
Lcdefault:
    mov x0, #0
    ret

.section __TEXT,__const
Lctable:
    .byte 0, 2, 4, 0

// FORBID listing * * :: add	w4, w26, #0x88c
// FORBID structured * Odd.bigConst( :: continues into
// FORBID structured * Odd.bigConst( :: loc_
// FORBID structured * Odd.bigConst( :: re:(?m)return (0x)?0?[ \t]*$
// FORBID structured * Odd.bigConst( :: re:return 0x(55667788|11223344)\b
// FORBID structured * Odd.tswitch( :: re:(?m)return (?!(0|10|20|30|0xa|0x14|0x1e|\?)[ \t]*$)\S
// FORBID structured * Odd.constSwitch( :: re:(?m)return (?!(0|10|20|30|0xa|0x14|0x1e|\?)[ \t]*$)\S
// EXPECT structured * Odd.tswitch( :: re:return (30|0x1e)\b
// The inline table's bytes are read-only __text, as resolvable as the
// __const one:
// EXPECT structured * Odd.tswitch( :: case 2:
// The pool is read-only __text too, so the value is provable:
// EXPECT structured * Odd.bigConst( :: re:return 0x1122334455667788\b
// EXPECT structured * Odd.constSwitch( :: re:return (30|0x1e)\b

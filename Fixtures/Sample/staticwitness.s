// A call through two pointers the image fixes: `ldur x8, [meta, #-0x8]`
// reads a value-witness table pointer from read-only metadata, `ldr x8,
// [x8, #0x28]` its sixth slot, and `blr x8` calls _slot5. Each pointer is a
// rebase in __DATA_CONST, so the call target is the image's own bytes.
// The same shape in writable __DATA (_metaRW) proves nothing: the program
// could have stored another table there, so its call stays unresolved. So
// does either pointer alone being writable: a writable metadata slot to the
// read-only table (_metaSlotRW), or a read-only slot to the writable table
// (_metaTableRW).
    .section __DATA_CONST,__const
    .p2align 3
_table:
    .quad _slot0, _slot1, _slot2, _slot3, _slot4, _slot5
    .quad _table
_meta:
    .quad 0x200
    .quad _tableRW
_metaTableRW:
    .quad 0x200
    .section __DATA,__data
    .p2align 3
_tableRW:
    .quad _slot0, _slot1, _slot2, _slot3, _slot4, _slot5
    .quad _tableRW
_metaRW:
    .quad 0x200
    .quad _table
_metaSlotRW:
    .quad 0x200
    .text
    .p2align 2
_slot0: ret
_slot1: ret
_slot2: ret
_slot3: ret
_slot4: ret
_slot5: ret
    .globl _callThroughWitness
_callThroughWitness:
    stp x29, x30, [sp, #-16]!
    adrp x2, _meta@PAGE
    add x2, x2, _meta@PAGEOFF
    ldur x8, [x2, #-0x8]
    ldr x8, [x8, #0x28]
    blr x8
    ldp x29, x30, [sp], #16
    ret
    .globl _callThroughWritable
_callThroughWritable:
    stp x29, x30, [sp, #-16]!
    adrp x2, _metaRW@PAGE
    add x2, x2, _metaRW@PAGEOFF
    ldur x8, [x2, #-0x8]
    ldr x8, [x8, #0x28]
    blr x8
    ldp x29, x30, [sp], #16
    ret
    .globl _callSlotWritable
_callSlotWritable:
    stp x29, x30, [sp, #-16]!
    adrp x2, _metaSlotRW@PAGE
    add x2, x2, _metaSlotRW@PAGEOFF
    ldur x8, [x2, #-0x8]
    ldr x8, [x8, #0x28]
    blr x8
    ldp x29, x30, [sp], #16
    ret
    .globl _callTableWritable
_callTableWritable:
    stp x29, x30, [sp, #-16]!
    adrp x2, _metaTableRW@PAGE
    add x2, x2, _metaTableRW@PAGEOFF
    ldur x8, [x2, #-0x8]
    ldr x8, [x8, #0x28]
    blr x8
    ldp x29, x30, [sp], #16
    ret

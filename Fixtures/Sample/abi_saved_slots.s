// Authored outliner-style fragments deliberately violate preservation of x19.
// Saving and reloading x19 does not preserve it when a store overwrites bytes
// of the save: narrowCaller replaces byte 3, overlapCaller replaces bits 32...63.
// The callers preserve their own caller's x19 and expose the changed value.
.text
.p2align 2
.globl _$s13ABIStackSlots12narrowCalleryS2i_SitF
_$s13ABIStackSlots12narrowCalleryS2i_SitF:
    stp x19, x30, [sp, #-16]!
    mov x19, x0
    bl _abi_saved_byte_fragment
    mov x0, x19
    ldp x19, x30, [sp], #16
    ret
.globl _abi_saved_byte_fragment
_abi_saved_byte_fragment:
    str x19, [sp, #-16]!
    mov x19, xzr
    strb w1, [sp, #3]
    ldr x19, [sp], #16
    ret
.globl _$s13ABIStackSlots13overlapCalleryS2i_SitF
_$s13ABIStackSlots13overlapCalleryS2i_SitF:
    stp x19, x30, [sp, #-16]!
    mov x19, x0
    bl _abi_saved_overlap_fragment
    mov x0, x19
    ldp x19, x30, [sp], #16
    ret
.globl _abi_saved_overlap_fragment
_abi_saved_overlap_fragment:
    str x19, [sp, #-16]!
    mov x19, xzr
    stur x1, [sp, #4]
    ldr x19, [sp], #16
    ret

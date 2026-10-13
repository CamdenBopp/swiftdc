// Authored reductions of save-area pointer escape, join and unsupported offset.
// These fragments intentionally return x19 replaced with the second argument.
.text
.p2align 2
.macro caller name, fragment
.globl _$s8ABIAlias\name\()yS2i_SitF
_$s8ABIAlias\name\()yS2i_SitF:
 stp x19, x30, [sp, #-16]!
 mov x19, x0
 bl \fragment
 mov x0, x19
 ldp x19, x30, [sp], #16
 ret
.endm
caller 7escaped, _escaped_save_fragment
caller 6before, _before_save_fragment
caller 6merged, _merged_save_fragment
caller 6offset, _offset_save_fragment
caller 6stored, _stored_save_fragment
caller 7control, _control_save_fragment
.globl _escaped_save_fragment
_escaped_save_fragment:
 stp x19, x30, [sp, #-16]!
 mov x19, xzr
 mov x0, sp
 bl _overwrite_save_pointer
 ldp x19, x30, [sp], #16
 ret
.globl _before_save_fragment
_before_save_fragment:
 sub sp, sp, #32
 str x30, [sp, #16]
 mov x9, sp
 adrp x10, _escaped_save_pointer@PAGE
 str x9, [x10, _escaped_save_pointer@PAGEOFF]
 mov x9, xzr
 str x19, [sp]
 mov x19, xzr
 bl _overwrite_escaped_pointer
 ldr x19, [sp]
 ldr x30, [sp, #16]
 add sp, sp, #32
 ret
.globl _merged_save_fragment
_merged_save_fragment:
 str x19, [sp, #-16]!
 mov x19, xzr
 mov x9, sp
 cbz xzr, 1f
 mov x9, x2
1:
 str x1, [x9]
 ldr x19, [sp], #16
 ret
.globl _offset_save_fragment
_offset_save_fragment:
 str x19, [sp, #-16]!
 mov x19, xzr
 mov x9, sp
 mov x2, xzr
 add x9, x9, x2
 str x1, [x9]
 ldr x19, [sp], #16
 ret
.globl _stored_save_fragment
_stored_save_fragment:
 stp x19, x30, [sp, #-16]!
 mov x19, xzr
 mov x9, sp
 adrp x10, _escaped_save_pointer@PAGE
 str x9, [x10, _escaped_save_pointer@PAGEOFF]
 mov x9, xzr
 bl _overwrite_escaped_pointer
 ldp x19, x30, [sp], #16
 ret
.globl _control_save_fragment
_control_save_fragment:
 stp x19, x30, [sp, #-16]!
 mov x19, xzr
 bl _ordinary_noop
 ldp x19, x30, [sp], #16
 ret
.globl _overwrite_save_pointer
_overwrite_save_pointer:
 str x1, [x0]
 ret
.globl _overwrite_escaped_pointer
_overwrite_escaped_pointer:
 adrp x9, _escaped_save_pointer@PAGE
 ldr x9, [x9, _escaped_save_pointer@PAGEOFF]
 str x1, [x9]
 ret
.globl _ordinary_noop
_ordinary_noop:
 ret
.data
.p2align 3
_escaped_save_pointer:
 .quad 0

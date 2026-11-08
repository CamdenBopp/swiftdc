// A clobber inside a switch case. table_switch dispatches on x0 through a
// jump table in clang's shape (`cmp x0, #3; b.hi; adrp; add; adr;
// ldrb w11, [x9, x0]; add x10, x10, x11, lsl #2; br x10`); case 2 calls
// table_clobber, which leaves x19 = x1 and does not restore it. Each Swift
// caller keeps arg0 in x19 across one call and returns x19: direct calls
// table_switch, wrapped calls table_wrapper, which calls table_switch,
// and deep calls table_deep_wrapper, which calls table_wrapper.
//
// True behaviour: with (2, 5) all three return 5, because case 2 runs; with
// (1, 5) all three return 1.
.text
.p2align 2
.macro caller name, callee
.globl _$s11SwitchTable\name\()yS2i_SitF
_$s11SwitchTable\name\()yS2i_SitF:
 stp x19, x30, [sp, #-16]!
 mov x19, x0
 bl \callee
 mov x0, x19
 ldp x19, x30, [sp], #16
 ret
.endm
caller 6direct, _table_switch
caller 7wrapped, _table_wrapper
caller 4deep, _table_deep_wrapper
.globl _table_clobber
_table_clobber:
 mov x19, x1
 ret
.globl _table_switch
_table_switch:
 stp x29, x30, [sp, #-16]!
 mov x29, sp
 cmp x0, #3
 b.hi Ldone
 adrp x9, Ltable@PAGE
 add x9, x9, Ltable@PAGEOFF
 adr x10, Lcase0
 ldrb w11, [x9, x0]
 add x10, x10, x11, lsl #2
 br x10
Lcase0:
 mov x0, #10
 b Ldone
Lcase1:
 mov x0, #11
 b Ldone
Lcase2:
 bl _table_clobber
 mov x0, #12
 b Ldone
Lcase3:
 mov x0, #13
Ldone:
 ldp x29, x30, [sp], #16
 ret
.globl _table_wrapper
_table_wrapper:
 stp x29, x30, [sp, #-16]!
 mov x29, sp
 bl _table_switch
 ldp x29, x30, [sp], #16
 ret
.globl _table_deep_wrapper
_table_deep_wrapper:
 stp x29, x30, [sp, #-16]!
 mov x29, sp
 bl _table_wrapper
 ldp x29, x30, [sp], #16
 ret
.section __TEXT,__const
Ltable:
 .byte (Lcase0-Lcase0)>>2, (Lcase1-Lcase0)>>2, (Lcase2-Lcase0)>>2, (Lcase3-Lcase0)>>2

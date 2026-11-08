// Hardened signed-offset jump tables require the CMP to bound every index bit
// the load reads, and CSEL must consume that CMP's flags. With index 0x100000001,
// the narrow/full-index form selects an out-of-range index. A call between CMP
// and CSEL also destroys the bound: NZCV are caller-clobbered, even when x19 is
// preserved. A SUBS overwriting the index compares its old value and can leave
// an underflowed index even on LS/HI fall-through. CMP aliases and SUBS writing
// a separate destination are valid controls.

.macro table_body name, compare_register, memory_index, rewrite_index=0
.text
.p2align 2
.globl _\name
_\name:
  .if \rewrite_index == 1
  subs x0, x0, #1
  .elseif \rewrite_index == 2
  subs x8, x0, #1
  .else
  cmp \compare_register, #1
  .endif
  csel x0, x0, xzr, ls
  adrp x9, L\name\()_table@PAGE
  add x9, x9, L\name\()_table@PAGEOFF
  adr x11, L\name\()_case0
  ldrsw x10, [x9, \memory_index]
  add x10, x11, x10
  br x10
L\name\()_case0:
  mov w0, #10
  ret
L\name\()_case1:
  mov w0, #20
  ret
.section __TEXT,__const
.p2align 2
L\name\()_table:
  .long L\name\()_case0 - L\name\()_case0
  .long L\name\()_case1 - L\name\()_case0
.endm

table_body jumpTableWideCompare, x0, "x0, lsl #2"
table_body jumpTableNarrowCompare, w0, "x0, lsl #2"
table_body jumpTableNarrowLoad, w0, "w0, uxtw #2"
table_body jumpTableRewrittenClampIndex, x0, "x0, lsl #2", 1
table_body jumpTableSeparateClampResult, x0, "x0, lsl #2", 2

.macro guard_table_body name, result_register
.text
.p2align 2
.globl _\name
_\name:
  subs \result_register, x0, #1
  b.hi L\name\()_default
  adrp x9, L\name\()_table@PAGE
  add x9, x9, L\name\()_table@PAGEOFF
  adr x11, L\name\()_case0
  ldrb w10, [x9, x0]
  add x10, x11, x10, lsl #2
  br x10
L\name\()_case0:
  mov w0, #10
  ret
L\name\()_case1:
  mov w0, #20
  ret
L\name\()_default:
  mov w0, #30
  ret
.section __TEXT,__const
.p2align 2
L\name\()_table:
  .byte (L\name\()_case0 - L\name\()_case0) / 4
  .byte (L\name\()_case1 - L\name\()_case0) / 4
.endm

guard_table_body jumpTableRewrittenGuardIndex, x0
guard_table_body jumpTableSeparateGuardResult, x8

.macro call_table_body name, recompare
.text
.p2align 2
.globl _\name
_\name:
  stp x19, x30, [sp, #-16]!
  mov x19, x0
  cmp x19, #1
  bl _jumpTableSetFlags
  .if \recompare
  cmp x19, #1
  .endif
  csel x19, x19, xzr, ls
  adrp x9, L\name\()_table@PAGE
  add x9, x9, L\name\()_table@PAGEOFF
  adr x11, L\name\()_case0
  ldrsw x10, [x9, x19, lsl #2]
  add x10, x11, x10
  br x10
L\name\()_case0:
  mov w0, #10
  ldp x19, x30, [sp], #16
  ret
L\name\()_case1:
  mov w0, #20
  ldp x19, x30, [sp], #16
  ret
.section __TEXT,__const
.p2align 2
L\name\()_table:
  .long L\name\()_case0 - L\name\()_case0
  .long L\name\()_case1 - L\name\()_case0
.endm

call_table_body jumpTableClobberedFlags, 0
call_table_body jumpTableRecheckedFlags, 1

.text
.p2align 2
.globl _jumpTableSetFlags
_jumpTableSetFlags:
  cmp xzr, xzr
  ret

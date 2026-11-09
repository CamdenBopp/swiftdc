// Value-witness calls through metadata that arrives as an argument, with no
// signature to say so (`valueWitnessCall`).
//
// _vwDestroy: `[[x1 - 8] + 8]` is destroy(x, T); the call passes x1, the
// metadata it loaded the table from, as T: named.
// _vwOtherMetadata: the same loads, but the call passes x2 where destroy
// takes its metadata, so nothing proves x1 is the metadata of this call:
// unresolved.
// _vwNotTheTable: `[[x1 - 16] + 8]` is not the word before the metadata:
// unresolved.
.text
.globl _vwDestroy
.p2align 2
_vwDestroy:
  stp x29, x30, [sp, #-16]!
  ldur x8, [x1, #-8]
  ldr x8, [x8, #0x8]
  blr x8
  ldp x29, x30, [sp], #16
  ret

.globl _vwOtherMetadata
.p2align 2
_vwOtherMetadata:
  stp x29, x30, [sp, #-16]!
  ldur x8, [x1, #-8]
  ldr x8, [x8, #0x8]
  mov x1, x2
  blr x8
  ldp x29, x30, [sp], #16
  ret

.globl _vwNotTheTable
.p2align 2
_vwNotTheTable:
  stp x29, x30, [sp, #-16]!
  ldur x8, [x1, #-16]
  ldr x8, [x8, #0x8]
  blr x8
  ldp x29, x30, [sp], #16
  ret

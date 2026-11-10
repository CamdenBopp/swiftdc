// A signature-derived receiver layout can consume entry-register proofs
// without Swift mangling, imports or metadata. This is an authored analysis
// contract, not a claim about a compiler-generated Swift calling convention.
// The native wrapper returns 11 through entry x20, forwarded as helper x0.
// The signature's formal x0 is 7; stale x1 = 29 is never a value receiver.
.text
.p2align 2
.globl _entry_role_consumer_native
_entry_role_consumer_native:
  stp x19, x20, [sp, #-48]!
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x8, #11
  str x8, [sp, #16]
  add x20, sp, #16
  mov x0, #7
  mov x1, #29
  bl "_EntryProof.Context.read(Swift.Int) -> Swift.Int"
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp], #48
  ret
.globl "_EntryProof.Context.read(Swift.Int) -> Swift.Int"
"_EntryProof.Context.read(Swift.Int) -> Swift.Int":
  mov x0, x20
  mov x20, xzr
  b _entry_role_consumer_helper
.globl _entry_role_consumer_helper
_entry_role_consumer_helper:
  ldr x0, [x0]
  ret

// An ordinary receiver is a positive consumer too. The authored Int method
// takes formal x0=7 and value-self x1=29, and returns value-self+1=30.
// An escaped save still MAY expose old x20; only the explicit x1 use proves
// that the receiver belongs in the ordinary argument list.
.globl _entry_role_value_consumer_native
_entry_role_value_consumer_native:
  stp x20, x30, [sp, #-32]!
  mov x0, #7
  mov x1, #29
  bl "_Swift.Int.roleRead(Swift.Int) -> Swift.Int"
  ldp x20, x30, [sp], #32
  ret
.globl "_Swift.Int.roleRead(Swift.Int) -> Swift.Int"
"_Swift.Int.roleRead(Swift.Int) -> Swift.Int":
  sub sp, sp, #48
  stp x20, x30, [sp, #32]
  add x20, x1, #1
  str xzr, [sp]
  mov x0, sp
  bl _entry_role_consumer_touch
  mov x0, x20
  ldp x20, x30, [sp, #32]
  add sp, sp, #48
  ret
.globl _entry_role_consumer_touch
_entry_role_consumer_touch:
  ldr x8, [x0]
  add x8, x8, #1
  str x8, [x0]
  ret
.subsections_via_symbols

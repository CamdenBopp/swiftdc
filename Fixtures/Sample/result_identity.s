// A retain returns the same object. Its result is an identity edge to the
// original producer, so a later use must not print another construction.
// These wrappers use the C ABI and real platform Swift ARC entry points.
.text
.p2align 2

.globl _$s14ResultIdentity3runSiyF
_$s14ResultIdentity3runSiyF:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  str x19, [sp, #16]
  add x29, sp, #32
  bl _result_identity_make
  bl _swift_bridgeObjectRetain
  mov x19, x0
  bl _result_identity_sink
  str x0, [sp, #24]
  mov x0, x19
  bl _result_identity_destroy
  mov x0, x19
  bl _result_identity_destroy
  ldr x0, [sp, #24]
  ldr x19, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

.globl _$s14ResultIdentity5twiceSiyF
_$s14ResultIdentity5twiceSiyF:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  str x19, [sp, #16]
  add x29, sp, #32
  bl _result_identity_make
  bl _swift_bridgeObjectRetain
  bl _swift_bridgeObjectRetain
  mov x19, x0
  bl _result_identity_sink
  str x0, [sp, #24]
  mov x0, x19
  bl _result_identity_destroy
  mov x0, x19
  bl _result_identity_destroy
  mov x0, x19
  bl _result_identity_destroy
  ldr x0, [sp, #24]
  ldr x19, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

// Return the pointer's word directly. This control may inline its one
// immediate use; the native test owns and releases the returned reference.
.globl _$s14ResultIdentity9immediateSiyF
_$s14ResultIdentity9immediateSiyF:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  bl _result_identity_make
  ldp x29, x30, [sp], #16
  ret

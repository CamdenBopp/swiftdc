// Recursive entry BL effects, without conditional external
// tails or non-entry BL targets. Private helpers intentionally clobber private
// GPR/vector registers. Public zero-argument wrappers preserve all AAPCS64
// callee-saved registers those helpers can change (vectors: low 64 bits only).
.text
.p2align 2
.macro general_caller name, helper, depth
.globl \name
\name:
  stp x29, x30, [sp, #-64]!
  stp x19, x20, [sp, #16]
  stp x21, x22, [sp, #32]
  mov x19, #2
  mov x0, #\depth
  bl \helper
  mov x0, x19
  ldp x21, x22, [sp, #32]
  ldp x19, x20, [sp, #16]
  ldp x29, x30, [sp], #64
  ret
.endm
.macro vector_caller name, helper, depth
.globl \name
\name:
  stp x29, x30, [sp, #-64]!
  stp d8, d9, [sp, #16]
  stp d10, d11, [sp, #32]
  fmov d8, #2.0
  mov x0, #\depth
  bl \helper
  fmov d0, d8
  ldp d10, d11, [sp, #32]
  ldp d8, d9, [sp, #16]
  ldp x29, x30, [sp], #64
  ret
.endm
general_caller _$s16SummaryRecursion6gprOnes6UInt64VyF, _rec_gpr_one, 1
general_caller _$s16SummaryRecursion6gprTwos6UInt64VyF, _rec_gpr_two, 2
general_caller _$s16SummaryRecursion7gprKepts6UInt64VyF, _rec_gpr_kept, 1
vector_caller _$s16SummaryRecursion9vectorOneSdyF, _rec_vector_one, 1
vector_caller _$s16SummaryRecursion9vectorTwoSdyF, _rec_vector_two, 2
vector_caller _$s16SummaryRecursion10vectorKeptSdyF, _rec_vector_kept, 1

.p2align 2
.globl _rec_gpr_one
_rec_gpr_one:
  cbz x0, Lgpr_one_base
  stp x29, x30, [sp, #-16]!
  mov x20, x19
  sub x0, x0, #1
  bl _rec_gpr_one
  mov x19, x20
  ldp x29, x30, [sp], #16
  ret
Lgpr_one_base:
  mov x20, #1
  ret
.p2align 2
.globl _rec_vector_one
_rec_vector_one:
  cbz x0, Lvector_one_base
  stp x29, x30, [sp, #-16]!
  fmov d9, d8
  sub x0, x0, #1
  bl _rec_vector_one
  fmov d8, d9
  ldp x29, x30, [sp], #16
  ret
Lvector_one_base:
  fmov d9, #1.0
  ret

// x22/v10 clobbers first reach x20/v9, then x19/v8 on another closure round.
.p2align 2
.globl _rec_gpr_two
_rec_gpr_two:
  cbz x0, Lgpr_two_base
  stp x29, x30, [sp, #-16]!
  mov x22, x20
  mov x20, x19
  sub x0, x0, #1
  bl _rec_gpr_two
  mov x19, x20
  mov x20, x22
  ldp x29, x30, [sp], #16
  ret
Lgpr_two_base:
  mov x22, #1
  ret
.p2align 2
.globl _rec_vector_two
_rec_vector_two:
  cbz x0, Lvector_two_base
  stp x29, x30, [sp, #-16]!
  fmov d10, d9
  fmov d9, d8
  sub x0, x0, #1
  bl _rec_vector_two
  fmov d8, d9
  fmov d9, d10
  ldp x29, x30, [sp], #16
  ret
Lvector_two_base:
  fmov d10, #1.0
  ret

// Real local saves reload the root, despite the temporary's recursive clobber.
.p2align 2
.globl _rec_gpr_kept
_rec_gpr_kept:
  cbz x0, Lgpr_kept_base
  stp x29, x30, [sp, #-32]!
  str x19, [sp, #16]
  mov x20, x19
  sub x0, x0, #1
  bl _rec_gpr_kept
  mov x19, x20
  ldr x19, [sp, #16]
  ldp x29, x30, [sp], #32
  ret
Lgpr_kept_base:
  mov x20, #1
  ret
.p2align 2
.globl _rec_vector_kept
_rec_vector_kept:
  cbz x0, Lvector_kept_base
  stp x29, x30, [sp, #-32]!
  str d8, [sp, #16]
  fmov d9, d8
  sub x0, x0, #1
  bl _rec_vector_kept
  fmov d8, d9
  ldr d8, [sp, #16]
  ldp x29, x30, [sp], #32
  ret
Lvector_kept_base:
  fmov d9, #1.0
  ret

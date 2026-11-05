// Conditional external tails. Private leaves use nonstandard callee-saved
// registers; public wrappers preserve the incoming ABI state. The frame
// countercase writes a scratch slot, never the public wrapper's ABI saves.
.text
.p2align 2
.macro gpr_caller name, helper, condition, reload
.globl \name
\name:
  stp x29, x30, [sp, #-64]!
  stp x19, x20, [sp, #16]
  mov x19, #2
  str x19, [sp, #32]
  mov x0, #\condition
  bl \helper
.if \reload
  ldr x19, [sp, #32]
.endif
  mov x0, x19
  ldp x19, x20, [sp, #16]
  ldp x29, x30, [sp], #64
  ret
.endm
.macro vector_caller name, helper, condition, reload
.globl \name
\name:
  stp x29, x30, [sp, #-64]!
  stp d8, d9, [sp, #16]
  fmov d8, #2.0
  str d8, [sp, #32]
  mov x0, #\condition
  bl \helper
.if \reload
  ldr d8, [sp, #32]
.endif
  fmov d0, d8
  ldp d8, d9, [sp, #16]
  ldp x29, x30, [sp], #64
  ret
.endm
gpr_caller _$s11TailEffects8gprTakens6UInt64VyF, _ct_gpr_dispatch, 0, 0
gpr_caller _$s11TailEffects10gprUntakens6UInt64VyF, _ct_gpr_dispatch, 1, 0
gpr_caller _$s11TailEffects7gprSafes6UInt64VyF, _ct_safe_dispatch, 0, 0
gpr_caller _$s11TailEffects9gprReloads6UInt64VyF, _ct_gpr_dispatch, 0, 1
vector_caller _$s11TailEffects11vectorTakenSdyF, _ct_vector_dispatch, 0, 0
vector_caller _$s11TailEffects13vectorUntakenSdyF, _ct_vector_dispatch, 1, 0
vector_caller _$s11TailEffects10vectorSafeSdyF, _ct_safe_dispatch, 0, 0
vector_caller _$s11TailEffects12vectorReloadSdyF, _ct_vector_dispatch, 0, 1
.globl _$s11TailEffects12frameScratchs6UInt64VyF
_$s11TailEffects12frameScratchs6UInt64VyF:
  stp x29, x30, [sp, #-64]!
  mov x9, #2
  str x9, [sp, #32]
  add x29, sp, #32
  mov x0, #0
  bl _ct_frame_dispatch
  ldr x0, [sp, #32]
  ldp x29, x30, [sp], #64
  ret
.p2align 2
.globl _ct_gpr_dispatch
_ct_gpr_dispatch:
  cbz x0, _ct_gpr_leaf
  ret
.globl _ct_gpr_leaf
_ct_gpr_leaf:
  mov x19, #1
  ret
.globl _ct_vector_dispatch
_ct_vector_dispatch:
  cbz x0, _ct_vector_leaf
  ret
.globl _ct_vector_leaf
_ct_vector_leaf:
  fmov d8, #1.0
  ret
.globl _ct_safe_dispatch
_ct_safe_dispatch:
  cbz x0, _ct_identity
  ret
.globl _ct_identity
_ct_identity:
  ret
.globl _ct_frame_dispatch
_ct_frame_dispatch:
  cbz x0, _ct_frame_leaf
  ret
.globl _ct_frame_leaf
_ct_frame_leaf:
  mov x9, #1
  str x9, [x29]
  ret

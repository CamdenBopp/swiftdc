// One native allocation is used through x20, directly and via an sret word.
// Keep the owning object alive in x28 or its result-buffer slot; release once.
.text
.p2align 2
.globl _self_use_context_only_shape
_self_use_context_only_shape:
  stp x20, x28, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  bl _$s7SelfUse04makeaB3BoxAA0abD0CyF
  mov x28, x0
  bl _$s7SelfUse04selfB6EffectyyF
  mov x20, x28
  mov x0, #9
  bl _$s7SelfUse0aB3BoxC3useyys5Int64VF
  mov x0, x28
  bl _swift_release
  ldp x29, x30, [sp, #16]
  ldp x20, x28, [sp], #32
  ret
.globl _self_use_mixed_shape
_self_use_mixed_shape:
  stp x20, x28, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  bl _$s7SelfUse04makeaB3BoxAA0abD0CyF
  mov x28, x0
  bl _$s7SelfUse04takeaB3BoxyyAA0abD0CF
  mov x20, x28
  mov x0, #9
  bl _$s7SelfUse0aB3BoxC3useyys5Int64VF
  mov x0, x28
  bl _swift_release
  ldp x29, x30, [sp, #16]
  ldp x20, x28, [sp], #32
  ret
.globl _self_use_direct_shape
_self_use_direct_shape:
  stp x20, x28, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  bl _$s7SelfUse04makeaB3BoxAA0abD0CyF
  mov x28, x0
  mov x20, x28
  mov x0, #9
  bl _$s7SelfUse0aB3BoxC3useyys5Int64VF
  mov x0, x28
  bl _swift_release
  ldp x29, x30, [sp, #16]
  ldp x20, x28, [sp], #32
  ret


.globl _self_use_indirect_shape
_self_use_indirect_shape:
  sub sp, sp, #80
  stp x20, x28, [sp, #48]
  stp x29, x30, [sp, #64]
  add x29, sp, #64
  mov x8, sp
  bl _$s7SelfUse04makeaB6HolderAA0abD0VyF
  ldr x28, [sp]
  bl _$s7SelfUse04selfB6EffectyyF
  mov x20, x28
  mov x0, #9
  bl _$s7SelfUse0aB3BoxC3useyys5Int64VF
  ldr x0, [sp]
  bl _swift_release
  ldp x29, x30, [sp, #64]
  ldp x20, x28, [sp, #48]
  add sp, sp, #80
  ret
.subsections_via_symbols

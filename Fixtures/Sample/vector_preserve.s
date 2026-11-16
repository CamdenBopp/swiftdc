// A scalar kept in a callee-saved vector register across a call, then
// stored whole. AAPCS64 preserves only the low 64 bits of v8-v15 across a
// call. `scalarStore` sets d8 to 7 (which clears v8's high lane), calls
// `helper`, which sets v8's high lane to 19 as the convention allows,
// and stores q8. True behaviour: the store writes 7 and then 19 (native
// execution prints lo=7 hi=19); before the call the high lane was 0, and
// after it nothing about it is known.
.text
.globl _helper
.p2align 2
_helper:
  mov x9, #19
  mov v8.d[1], x9
  ret

.globl _scalarStore
.p2align 2
_scalarStore:
  stp d9, d8, [sp, #-48]!
  stp x20, x19, [sp, #16]
  stp x29, x30, [sp, #32]
  mov x19, x0
  mov x9, #7
  fmov d8, x9
  bl _helper
  str q8, [x19]
  ldp x29, x30, [sp, #32]
  ldp x20, x19, [sp, #16]
  ldp d9, d8, [sp], #48
  ret

.globl _scalarStoreNoCall
.p2align 2
_scalarStoreNoCall:
  mov x9, #7
  fmov d8, x9
  str q8, [x0]
  ret

// `keep(_ f: Float) -> Float` holds f in s8 across the call and returns it:
// the low lane survives, so the result is f.
.globl _$s14VectorPreserve4keepyS2fF
.p2align 2
_$s14VectorPreserve4keepyS2fF:
  stp d9, d8, [sp, #-32]!
  stp x29, x30, [sp, #16]
  fmov s8, s0
  bl _helper
  fmov s0, s8
  ldp x29, x30, [sp, #16]
  ldp d9, d8, [sp], #32
  ret

// The complete callers save and restore their incoming x19; only the outlined
// fragment has a private convention. It saves x19, hands that slot's address
// to a callback in d0 or in v0.d[1], and reloads x19. The callback is an
// ordinary void(double) or void(short vector) and writes 99 through it.
// True behaviour: indirect() == upper() == 99, never the 7 set before the call.
.text
nop
.globl _$s7FPAlias8indirectSiyF
_$s7FPAlias8indirectSiyF:
  stp x19, x30, [sp, #-32]!
  mov x19, #7
  adr x0, _poke_bits
  bl _OUTLINED_FUNCTION_FP
  mov x0, x19
  ldp x19, x30, [sp], #32
  ret
.globl _OUTLINED_FUNCTION_FP
_OUTLINED_FUNCTION_FP:
  stp x19, x30, [sp, #-16]!
  mov x16, x0
  mov x0, sp
  fmov d0, x0
  mov x0, xzr
  blr x16
  ldp x19, x30, [sp], #16
  ret
.globl _poke_bits
_poke_bits:
  fmov x8, d0
  mov w9, #99
  str x9, [x8]
  ret
.globl _$s7FPAlias5upperSiyF
_$s7FPAlias5upperSiyF:
  stp x19, x30, [sp, #-32]!
  mov x19, #7
  adr x0, _poke_upper
  bl _OUTLINED_FUNCTION_UPPER
  mov x0, x19
  ldp x19, x30, [sp], #32
  ret
.globl _OUTLINED_FUNCTION_UPPER
_OUTLINED_FUNCTION_UPPER:
  stp x19, x30, [sp, #-16]!
  mov x16, x0
  mov x0, sp
  movi v0.2d, #0
  mov v0.d[1], x0
  mov x0, xzr
  blr x16
  ldp x19, x30, [sp], #16
  ret
.globl _poke_upper
_poke_upper:
  mov x8, v0.d[1]
  mov w9, #99
  str x9, [x8]
  ret

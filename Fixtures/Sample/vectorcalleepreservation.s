// A reduced outlined helper changes d8 without preserving it. The callers
// obey the ordinary ABI by saving/restoring their incoming d8 themselves.
// stale/nested really return 1.0; keptD/keptQ return 2.0. swiftdc need not
// reconstruct the helper's value, but must never claim the old 2.0 survived.
.text
.macro caller name, helper
.globl \name
\name:
  stp x29, x30, [sp, #-32]!
  str d8, [sp, #16]
  fmov d8, #2.0
  bl \helper
  fmov d0, d8
  ldr d8, [sp, #16]
  ldp x29, x30, [sp], #32
  ret
.endm
caller _$s15VectorSummaries5staleSdyF, _OUTLINED_FUNCTION_0
caller _$s15VectorSummaries5keptDSdyF, _OUTLINED_FUNCTION_1
caller _$s15VectorSummaries5keptQSdyF, _OUTLINED_FUNCTION_2
caller _$s15VectorSummaries6nestedSdyF, _OUTLINED_FUNCTION_3
.globl _OUTLINED_FUNCTION_0
_OUTLINED_FUNCTION_0:
  fmov d8, #1.0
  ret
.globl _OUTLINED_FUNCTION_1
_OUTLINED_FUNCTION_1:
  str d8, [sp, #-16]!
  fmov d8, #1.0
  ldr d8, [sp], #16
  ret
.globl _OUTLINED_FUNCTION_2
_OUTLINED_FUNCTION_2:
  str q8, [sp, #-16]!
  fmov d8, #1.0
  ldr q8, [sp], #16
  ret
.globl _OUTLINED_FUNCTION_3
_OUTLINED_FUNCTION_3:
  stp x29, x30, [sp, #-16]!
  bl _OUTLINED_FUNCTION_0
  ldp x29, x30, [sp], #16
  ret

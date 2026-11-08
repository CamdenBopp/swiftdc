// Functions with no signature whose result only their callers can prove.
// True behaviour: `leaf` returns 7 in x0 and `dleaf` 1.5 in d0, and a
// caller reads each; a float's width needs a type, so only `leaf` is shown. `pair` returns 1 and 2 in x0 and x1, a two-word
// result, so x0 alone is not it. `thrower` may throw (its caller tests
// x21 after the call), `fwd`'s caller returns right after reading x0,
// handing on whatever x21 holds, and `setsError` writes x21 itself, so none
// of those results is proven.
.text
.globl _sink
.p2align 2
_sink:
  ret

.globl _leaf
.p2align 2
_leaf:
  mov x0, #7
  ret

.globl _dleaf
.p2align 2
_dleaf:
  fmov d0, #1.5
  ret

.globl _pair
.p2align 2
_pair:
  mov x0, #1
  mov x1, #2
  ret

.globl _thrower
.p2align 2
_thrower:
  mov x0, #3
  ret

.globl _fwd
.p2align 2
_fwd:
  mov x0, #4
  ret

.globl _setsError
.p2align 2
_setsError:
  mov x21, #1
  mov x0, #5
  ret

.globl _callSetsError
.p2align 2
_callSetsError:
  stp x29, x30, [sp, #-16]!
  bl _setsError
  add x0, x0, #1
  bl _sink
  ldp x29, x30, [sp], #16
  ret

.globl _tailLeaf
.p2align 2
_tailLeaf:
  cbz x0, 1f
  b _leaf
1:
  mov x0, #3
  ret

.globl _callTailLeaf
.p2align 2
_callTailLeaf:
  stp x29, x30, [sp, #-16]!
  bl _tailLeaf
  add x0, x0, #1
  bl _sink
  ldp x29, x30, [sp], #16
  ret

.globl _callLeaf
.p2align 2
_callLeaf:
  stp x29, x30, [sp, #-16]!
  bl _leaf
  add x0, x0, #1
  bl _sink
  ldp x29, x30, [sp], #16
  ret

.globl _callDleaf
.p2align 2
_callDleaf:
  stp x29, x30, [sp, #-16]!
  bl _dleaf
  fadd d0, d0, d0
  bl _sink
  ldp x29, x30, [sp], #16
  ret

.globl _callPair
.p2align 2
_callPair:
  stp x29, x30, [sp, #-16]!
  bl _pair
  add x0, x0, x1
  bl _sink
  ldp x29, x30, [sp], #16
  ret

.globl _callThrower
.p2align 2
_callThrower:
  stp x29, x30, [sp, #-16]!
  mov x21, #0
  bl _thrower
  add x0, x0, #1
  cbnz x21, 1f
  bl _sink
1:
  ldp x29, x30, [sp], #16
  ret

.globl _callFwd
.p2align 2
_callFwd:
  stp x29, x30, [sp, #-16]!
  bl _fwd
  add x0, x0, #1
  ldp x29, x30, [sp], #16
  ret

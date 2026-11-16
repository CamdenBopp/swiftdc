// Tail branches to bodies that never write x0. True behaviour:
// `callKeep(n)` branches to `keep`, a lone `ret`, so it returns n.
// `callStore(n)` branches to `store`, which writes n to the global `seen`
// and returns without touching x0, so it also returns n, and the store is
// an effect the render must keep. `callWrite(n)` branches to `bump`,
// which returns n + 1, so its result is not its argument.
.text
.p2align 2
_keep:
  ret

.p2align 2
_store:
  adrp x8, _seen@PAGE
  str x0, [x8, _seen@PAGEOFF]
  ret

.p2align 2
_bump:
  add x0, x0, #1
  ret

.globl _$s11Passthrough8callKeepyS2iF
.p2align 2
_$s11Passthrough8callKeepyS2iF:
  b _keep

.globl _$s11Passthrough9callStoreyS2iF
.p2align 2
_$s11Passthrough9callStoreyS2iF:
  b _store

.globl _$s11Passthrough9callWriteyS2iF
.p2align 2
_$s11Passthrough9callWriteyS2iF:
  b _bump

.data
.globl _seen
.p2align 3
_seen:
  .quad 0

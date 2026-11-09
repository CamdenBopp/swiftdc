// A value witness that returns nothing leaves x0 holding whatever it last
// computed (swift/include/swift/ABI/ValueWitness.def: destroy is void).
//
// _vwVoidThenUse: destroy value witness for Swift.Int (its metadata bound
// through the GOT), then a call to _vwSink, which reads x0. Nothing proves
// what x0 holds there: `_vwSink(?)`, never the destroy's "result".
// _vwCopyThenUse: initializeWithCopy returns its destination in x0, so the
// sink's argument is that call.
.text
.globl _vwSink
.p2align 2
_vwSink:
  add x0, x0, #1
  ret

.globl _vwVoidThenUse
.p2align 2
_vwVoidThenUse:
  stp x29, x30, [sp, #-16]!
  adrp x1, _$sSiN@GOTPAGE
  ldr x1, [x1, _$sSiN@GOTPAGEOFF]
  ldur x8, [x1, #-8]
  ldr x8, [x8, #0x8]
  blr x8
  bl _vwSink
  ldp x29, x30, [sp], #16
  ret

.globl _vwCopyThenUse
.p2align 2
_vwCopyThenUse:
  stp x29, x30, [sp, #-16]!
  adrp x2, _$sSiN@GOTPAGE
  ldr x2, [x2, _$sSiN@GOTPAGEOFF]
  ldur x8, [x2, #-8]
  ldr x8, [x8, #0x10]
  blr x8
  bl _vwSink
  ldp x29, x30, [sp], #16
  ret

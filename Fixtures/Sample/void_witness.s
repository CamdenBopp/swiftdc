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

// _vwEnumSlotOther: `[[Swift.Int metadata - 8] + 0x58]` is an enum
// witness slot, which only an enum's table has, and the call passes x2,
// not that metadata, where getEnumTag takes T: nothing proves it a witness
// call. Unresolved, never `getEnumTag value witness for Swift.Int`.
.globl _vwEnumSlotOther
.p2align 2
_vwEnumSlotOther:
  stp x29, x30, [sp, #-16]!
  adrp x1, _$sSiN@GOTPAGE
  ldr x1, [x1, _$sSiN@GOTPAGEOFF]
  ldur x8, [x1, #-8]
  ldr x8, [x8, #0x58]
  mov x1, x2
  blr x8
  ldp x29, x30, [sp], #16
  ret

// An associated type's metadata: swift_getAssociatedTypeWitness(request,
// table, T, requirements base, associated type descriptor for
// Swift.Sequence.Element) returns T.Element's metadata in x0.
// _vwAssocDestroy calls its destroy witness passing that metadata back:
// `destroy value witness for arg6.Element`. _vwAssocOther passes arg5 (kept
// in x20 across the call) where destroy takes its metadata: unresolved.
.globl _vwAssocDestroy
.p2align 2
_vwAssocDestroy:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  mov x0, #0
  mov x1, x5
  mov x2, x6
  adrp x3, _$sSTTL@GOTPAGE
  ldr x3, [x3, _$sSTTL@GOTPAGEOFF]
  adrp x4, _$s7ElementSTTl@GOTPAGE
  ldr x4, [x4, _$s7ElementSTTl@GOTPAGEOFF]
  bl _swift_getAssociatedTypeWitness
  mov x19, x0
  ldur x8, [x0, #-8]
  ldr x8, [x8, #0x8]
  mov x0, x7
  mov x1, x19
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

.globl _vwAssocOther
.p2align 2
_vwAssocOther:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  mov x20, x5
  mov x0, #0
  mov x1, x5
  mov x2, x6
  adrp x3, _$sSTTL@GOTPAGE
  ldr x3, [x3, _$sSTTL@GOTPAGEOFF]
  adrp x4, _$s7ElementSTTl@GOTPAGE
  ldr x4, [x4, _$s7ElementSTTl@GOTPAGEOFF]
  bl _swift_getAssociatedTypeWitness
  mov x19, x0
  ldur x8, [x0, #-8]
  ldr x8, [x8, #0x8]
  mov x0, x19
  mov x1, x20
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

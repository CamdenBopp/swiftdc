// Protocol witness calls through a table swift_conformsToProtocol2 returned
// for a hand-built protocol descriptor (Demo.Shape: a module descriptor,
// then kind 3 with two instance requirements, a method and a getter;
// include/swift/ABI/Metadata.h TargetProtocolDescriptor).
//
// _pwArea calls word 1 passing (T, table) last: `Demo.Shape requirement 0
// (method) witness for arg0`. _pwSides calls word 2 the same way: the
// getter. _pwNotTheTable passes x21 where the table goes: nothing proves a
// witness call, so it stays unresolved.
.section __TEXT,__const
.p2align 2
_demoModule:
  .long 0
  .long 0
  .long _demoModuleName - .
_shapeProtocol:
  .long 3
  .long _demoModule - .
  .long _shapeName - .
  .long 0
  .long 2
  .long 0
  .long 0x11
  .long 0
  .long 0x13
  .long 0
.section __TEXT,__cstring,cstring_literals
_demoModuleName: .asciz "Demo"
_shapeName: .asciz "Shape"

.text
.globl _pwArea
.p2align 2
_pwArea:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  mov x19, x0
  adrp x1, _shapeProtocol@PAGE
  add x1, x1, _shapeProtocol@PAGEOFF
  bl _swift_conformsToProtocol2
  ldr x8, [x0, #8]
  mov x1, x0
  mov x0, x19
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

.globl _pwSides
.p2align 2
_pwSides:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  mov x19, x0
  adrp x1, _shapeProtocol@PAGE
  add x1, x1, _shapeProtocol@PAGEOFF
  bl _swift_conformsToProtocol2
  ldr x8, [x0, #16]
  mov x1, x0
  mov x0, x19
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

.globl _pwNotTheTable
.p2align 2
_pwNotTheTable:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  mov x19, x0
  mov x20, x1
  adrp x1, _shapeProtocol@PAGE
  add x1, x1, _shapeProtocol@PAGEOFF
  bl _swift_conformsToProtocol2
  ldr x8, [x0, #8]
  mov x1, x20
  mov x0, x19
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

// _pwNotTheType passes the table last but arg1, not the metadata looked
// up, before it. _pwUnknownType looks up a type read from memory and calls
// with another word read from memory: both unknown, which proves no
// identity. Both stay unresolved.
.globl _pwNotTheType
.p2align 2
_pwNotTheType:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  mov x19, x0
  mov x20, x1
  adrp x1, _shapeProtocol@PAGE
  add x1, x1, _shapeProtocol@PAGEOFF
  bl _swift_conformsToProtocol2
  ldr x8, [x0, #8]
  mov x1, x0
  mov x0, x20
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

.globl _pwUnknownType
.p2align 2
_pwUnknownType:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  mov x20, x1
  ldr x0, [x0]
  adrp x1, _shapeProtocol@PAGE
  add x1, x1, _shapeProtocol@PAGEOFF
  bl _swift_conformsToProtocol2
  ldr x8, [x0, #8]
  mov x1, x0
  ldr x0, [x20]
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

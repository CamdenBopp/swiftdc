// Calls through the three words past a value-witness table's common part
// (+0x58, +0x60, +0x68), each passing the metadata the table was loaded
// through where an enum witness takes its metadata. Only an enum's table
// has functions there (EnumValueWitnessTable, swift/include/swift/ABI/
// Metadata.h); any other table ends at +0x58.
//
// The metadata's symbol spells its nominal kind:
//   Swift.FloatingPointSign  $ss17FloatingPointSignON / …OMa   an enum
//   Swift.Int                $sSiN / $sSiMa                    a struct
//   Swift._ContiguousArrayStorage  $ss23_ContiguousArrayStorageCMa  a class
//
// _esBoundEnumTag, _esAccessorEnumTag, _esAccessorEnumProject,
// _esAccessorEnumInject: the enum's getEnumTag (value, T),
// destructiveProjectEnumData (value, T) and destructiveInjectEnumTag
// (value, tag, T), named for Swift.FloatingPointSign.
// _esBoundStructTag, _esBoundStructProject, _esAccessorStructTag,
// _esAccessorClassTag, _esAccessorClassInject: the word past a struct's or
// a class's table is not a witness. Each call is to an unknown function
// and stays unresolved; none is an enum operation on Swift.Int or on
// Swift._ContiguousArrayStorage.
// _esBoundStructDestroy: +0x8 is destroy in every table, so the struct's
// is still named.
.text
.globl _esBoundEnumTag
.p2align 2
_esBoundEnumTag:
  stp x29, x30, [sp, #-16]!
  adrp x1, _$ss17FloatingPointSignON@GOTPAGE
  ldr x1, [x1, _$ss17FloatingPointSignON@GOTPAGEOFF]
  ldur x8, [x1, #-8]
  ldr x8, [x8, #0x58]
  blr x8
  ldp x29, x30, [sp], #16
  ret

.globl _esBoundStructTag
.p2align 2
_esBoundStructTag:
  stp x29, x30, [sp, #-16]!
  adrp x1, _$sSiN@GOTPAGE
  ldr x1, [x1, _$sSiN@GOTPAGEOFF]
  ldur x8, [x1, #-8]
  ldr x8, [x8, #0x58]
  blr x8
  ldp x29, x30, [sp], #16
  ret

.globl _esBoundStructProject
.p2align 2
_esBoundStructProject:
  stp x29, x30, [sp, #-16]!
  adrp x1, _$sSiN@GOTPAGE
  ldr x1, [x1, _$sSiN@GOTPAGEOFF]
  ldur x8, [x1, #-8]
  ldr x8, [x8, #0x60]
  blr x8
  ldp x29, x30, [sp], #16
  ret

.globl _esBoundStructDestroy
.p2align 2
_esBoundStructDestroy:
  stp x29, x30, [sp, #-16]!
  adrp x1, _$sSiN@GOTPAGE
  ldr x1, [x1, _$sSiN@GOTPAGEOFF]
  ldur x8, [x1, #-8]
  ldr x8, [x8, #0x8]
  blr x8
  ldp x29, x30, [sp], #16
  ret

.globl _esAccessorEnumTag
.p2align 2
_esAccessorEnumTag:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  mov x19, x0
  mov x0, #0
  bl _$ss17FloatingPointSignOMa
  mov x1, x0
  ldur x8, [x0, #-8]
  ldr x8, [x8, #0x58]
  mov x0, x19
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

.globl _esAccessorEnumProject
.p2align 2
_esAccessorEnumProject:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  mov x19, x0
  mov x0, #0
  bl _$ss17FloatingPointSignOMa
  mov x1, x0
  ldur x8, [x0, #-8]
  ldr x8, [x8, #0x60]
  mov x0, x19
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

.globl _esAccessorEnumInject
.p2align 2
_esAccessorEnumInject:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  mov x19, x0
  mov x20, x1
  mov x0, #0
  bl _$ss17FloatingPointSignOMa
  mov x2, x0
  ldur x8, [x0, #-8]
  ldr x8, [x8, #0x68]
  mov x0, x19
  mov x1, x20
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

.globl _esAccessorStructTag
.p2align 2
_esAccessorStructTag:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  mov x19, x0
  mov x0, #0
  bl _$sSiMa
  mov x1, x0
  ldur x8, [x0, #-8]
  ldr x8, [x8, #0x58]
  mov x0, x19
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

.globl _esAccessorClassTag
.p2align 2
_esAccessorClassTag:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  mov x19, x0
  mov x0, #0
  bl _$ss23_ContiguousArrayStorageCMa
  mov x1, x0
  ldur x8, [x0, #-8]
  ldr x8, [x8, #0x58]
  mov x0, x19
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

.globl _esAccessorClassInject
.p2align 2
_esAccessorClassInject:
  stp x20, x19, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  mov x19, x0
  mov x20, x1
  mov x0, #0
  bl _$ss23_ContiguousArrayStorageCMa
  mov x2, x0
  ldur x8, [x0, #-8]
  ldr x8, [x8, #0x68]
  mov x0, x19
  mov x1, x20
  blr x8
  ldp x29, x30, [sp, #16]
  ldp x20, x19, [sp], #32
  ret

// _esWritableSlotEnumTag: the enum's metadata again, loaded from a pointer
// in __DATA,__data that the loader binds and the program may rewrite. What
// it holds at the call is not proven, so the call stays unresolved.
.globl _esWritableSlotEnumTag
.p2align 2
_esWritableSlotEnumTag:
  stp x29, x30, [sp, #-16]!
  adrp x9, _es_writable_slot@PAGE
  ldr x1, [x9, _es_writable_slot@PAGEOFF]
  ldur x8, [x1, #-8]
  ldr x8, [x8, #0x58]
  blr x8
  ldp x29, x30, [sp], #16
  ret

.data
.p2align 3
_es_writable_slot:
  .quad _$ss17FloatingPointSignON

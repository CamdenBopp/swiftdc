// ExistentialWitness.unpassed(any Shape) -> Int, written by hand: it loads
// a word of its existential argument's witness table and calls it, but
// passes neither the metadata nor the table, as no witness call does.
// Nothing proves that word is a requirement called as one, so it stays an
// unresolved call. (Never executed; the oracle module does not call it.)
.text
.p2align 2
.globl _$s18ExistentialWitness8unpassedySiAA5Shape_pF
_$s18ExistentialWitness8unpassedySiAA5Shape_pF:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  ldp x9, x10, [x0, #0x18]
  ldr x8, [x10, #8]
  mov x0, #0
  mov x1, #0
  blr x8
  ldp x29, x30, [sp], #16
  ret

// ExistentialWitness.unpassedNamed(any Named) -> Int, by hand: a class-bound
// existential's table (x1) is read and a word of it called, but the call
// passes neither swift_getObjectType(object) nor the table.
.globl _$s18ExistentialWitness13unpassedNamedySiAA0D0_pF
_$s18ExistentialWitness13unpassedNamedySiAA0D0_pF:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  ldr x8, [x1, #8]
  mov x0, #0
  mov x1, #0
  blr x8
  ldp x29, x30, [sp], #16
  ret

// unpassedTable(any Named): the metadata is swift_getObjectType(object),
// but the table is not passed (x1 = 0).
.globl _$s18ExistentialWitness13unpassedTableySiAA5Named_pF
_$s18ExistentialWitness13unpassedTableySiAA5Named_pF:
  stp x29, x30, [sp, #-32]!
  mov x29, sp
  stp x19, x20, [sp, #16]
  mov x19, x1
  mov x20, x0
  bl _swift_getObjectType
  ldr x8, [x19, #8]
  mov x1, #0
  blr x8
  ldp x19, x20, [sp, #16]
  ldp x29, x30, [sp], #32
  ret

// retainedType(any Named): the table is passed, but the metadata is
// swift_getObjectType of another value (the table), not of the object.
.globl _$s18ExistentialWitness12retainedTypeySiAA5Named_pF
_$s18ExistentialWitness12retainedTypeySiAA5Named_pF:
  stp x29, x30, [sp, #-32]!
  mov x29, sp
  stp x19, x20, [sp, #16]
  mov x19, x1
  mov x20, x0
  mov x0, x19
  bl _swift_getObjectType
  ldr x8, [x19, #8]
  mov x1, x19
  blr x8
  ldp x19, x20, [sp, #16]
  ldp x29, x30, [sp], #32
  ret

// existential_vw_unpassed(container): slot 0 of the container's metadata's
// value-witness table, called with no metadata where the witness takes it.
.globl _existential_vw_unpassed
_existential_vw_unpassed:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  ldr x2, [x0, #0x18]
  ldur x8, [x2, #-8]
  ldr x8, [x8]
  mov x1, x0
  mov x2, #0
  blr x8
  ldp x29, x30, [sp], #16
  ret

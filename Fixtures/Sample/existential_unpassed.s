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

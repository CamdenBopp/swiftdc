// The complete result is one producer's 40 bytes, followed by effect().
// Required render: let r = make_packet(); effect(); return r.
// Read incoming x8 explicitly so the body's result convention is provable.
.text
.p2align 2
.globl _$s13IndirectOrder7orderedAA6PacketVyF
_$s13IndirectOrder7orderedAA6PacketVyF:
  stp x19, x20, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  mov x19, x8
  mov x8, x19
  bl _indirect_order_make_packet
  bl _$s13IndirectOrder6effectyyF
  ldp x29, x30, [sp, #16]
  ldp x19, x20, [sp], #32
  ret

.globl _$s13IndirectOrder12aliasOrderedAA6PacketVyF
_$s13IndirectOrder12aliasOrderedAA6PacketVyF:
  sub sp, sp, #64
  stp x21, x22, [sp, #32]
  stp x29, x30, [sp, #48]
  add x29, sp, #48
  mov x21, x8
  str x21, [sp, #8]
  mov x0, sp
  mov x8, x21
  bl _alias_result_make
  ldr x21, [sp, #8]
  mov x22, #8
  add x0, x21, x22
  mov x1, #99
  bl _alias_result_mutate
  ldp x29, x30, [sp, #48]
  ldp x21, x22, [sp, #32]
  add sp, sp, #64
  ret

// A complete overwrite removes the pointer before the frame escapes, so
// that local no longer exposes the result buffer. Keep its valid whole return.
.globl _$s13IndirectOrder12aliasClearedAA6PacketVyF
_$s13IndirectOrder12aliasClearedAA6PacketVyF:
  sub sp, sp, #64
  stp x21, x22, [sp, #32]
  stp x29, x30, [sp, #48]
  add x29, sp, #48
  mov x21, x8
  str x21, [sp, #8]
  str xzr, [sp, #8]
  mov x0, sp
  mov x8, x21
  bl _alias_result_make
  ldp x29, x30, [sp, #48]
  ldp x21, x22, [sp, #32]
  add sp, sp, #64
  ret
// One predecessor spills the pointer, the other stores zero. Their join
// loses its exact value but must retain the possibility of a result alias.
.globl _$s13IndirectOrder11aliasJoinedyAA6PacketVs5Int64VF
_$s13IndirectOrder11aliasJoinedyAA6PacketVs5Int64VF:
  sub sp, sp, #80
  stp x19, x20, [sp, #32]
  stp x21, x22, [sp, #48]
  stp x29, x30, [sp, #64]
  add x29, sp, #64
  mov x19, x0
  mov x21, x8
  str xzr, [sp]
  bl _alias_plain_make
  cbz x19, Lalias_no_pointer
  str x21, [sp, #8]
  b Lalias_join
Lalias_no_pointer:
  str xzr, [sp, #8]
Lalias_join:
  mov x0, sp
  bl _alias_result_touch
  cbz x19, Lalias_return
  ldr x21, [sp, #8]
  add x0, x21, #8
  mov x1, #99
  bl _alias_result_mutate
Lalias_return:
  ldp x29, x30, [sp, #64]
  ldp x21, x22, [sp, #48]
  ldp x19, x20, [sp, #32]
  add sp, sp, #80
  ret
// x20 is callee-saved storage across the plain producer, then the actual
// mutating receiver. Only the second callee may access the result through it.
.globl _$s13IndirectOrder12aliasContextAA6PacketVyF
_$s13IndirectOrder12aliasContextAA6PacketVyF:
  stp x19, x20, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  mov x20, x8
  bl _alias_plain_make
  bl _$s13IndirectOrder6PacketV7mutateByyF
  ldp x29, x30, [sp, #16]
  ldp x19, x20, [sp], #32
  ret


.globl _$s13IndirectOrder13aliasOutlinedAA6PacketVyF
_$s13IndirectOrder13aliasOutlinedAA6PacketVyF:
  stp x19, x20, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  mov x20, x8
  bl _alias_plain_make
  bl _alias_outlined_forward
  ldp x29, x30, [sp, #16]
  ldp x19, x20, [sp], #32
  ret

.globl _$s13IndirectOrder18aliasOutlinedRelayAA6PacketVyF
_$s13IndirectOrder18aliasOutlinedRelayAA6PacketVyF:
  stp x19, x20, [sp, #-32]!
  stp x29, x30, [sp, #16]
  add x29, sp, #16
  mov x20, x8
  bl _alias_plain_make
  bl _alias_outlined_relay
  ldp x29, x30, [sp, #16]
  ldp x19, x20, [sp], #32
  ret

// The first forwarding edge existed before preservation was settled.
.globl _alias_outlined_forward
_alias_outlined_forward:
  b _alias_outlined_mutate

.globl _alias_outlined_mutate
_alias_outlined_mutate:
  sub sp, sp, #32
  str x20, [sp, #8]
  str x30, [sp, #16]
  mov x20, #0
  bl _alias_outlined_middle
  mov x0, #99
  str x0, [x20, #8]
  ldr x30, [sp, #16]
  add sp, sp, #32
  ret

// This context-forward edge appears only after the outlined reload is known.
.globl _alias_outlined_relay
_alias_outlined_relay:
  sub sp, sp, #32
  str x20, [sp, #8]
  str x30, [sp, #16]
  mov x20, #0
  bl _alias_outlined_middle
  bl _alias_outlined_leaf_mutate
  ldr x30, [sp, #16]
  add sp, sp, #32
  ret

.globl _alias_outlined_leaf_mutate
_alias_outlined_leaf_mutate:
  mov x0, #99
  str x0, [x20, #8]
  ret

.globl _alias_outlined_middle
_alias_outlined_middle:
  b _alias_outlined_reload
.globl _alias_outlined_reload
_alias_outlined_reload:
  ldr x20, [sp, #8]
  ret
.subsections_via_symbols

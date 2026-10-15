// Frame slots reachable through an escaped address. Every function stores 7
// to a frame slot and returns what the slot holds at the end; the true value
// is in the comment. A slot whose address escaped (stored to memory, passed
// to a call, or derived beyond the tracer's arithmetic) may be rewritten by
// any later call or any store through a pointer of unknown origin.
.text
.p2align 2

// The address goes to one call, which keeps it; a later call writes 11
// through it. True result: 11.
.globl _$s11FrameEscape12callPersistsSiyF
_$s11FrameEscape12callPersistsSiyF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  add x0, sp, #8
  bl _frame_escape_stash
  mov x8, #7
  str x8, [sp, #8]
  bl _frame_escape_write_stashed
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret

// The address escapes on one path only; the other stashes a harmless
// global. True result: 11 when the argument is non-zero, 7 otherwise.
.globl _$s11FrameEscape12joinPersistsyS2iF
_$s11FrameEscape12joinPersistsyS2iF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  cbz x0, LjoinHarmless
  add x0, sp, #8
  b LjoinStash
LjoinHarmless:
  adrp x0, _frame_escape_dummy@PAGE
  add x0, x0, _frame_escape_dummy@PAGEOFF
LjoinStash:
  bl _frame_escape_stash
  mov x8, #7
  str x8, [sp, #8]
  bl _frame_escape_write_stashed
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret

// The address escapes through a call on one path, before the join; no
// frame address reaches the join itself. True result: 11 when the argument
// is non-zero, 7 otherwise.
.globl _$s11FrameEscape17joinEscapedBeforeyS2iF
_$s11FrameEscape17joinEscapedBeforeyS2iF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  cbz x0, LjebHarmless
  add x0, sp, #8
  bl _frame_escape_stash
  b LjebJoin
LjebHarmless:
  adrp x0, _frame_escape_dummy@PAGE
  add x0, x0, _frame_escape_dummy@PAGEOFF
  bl _frame_escape_stash
LjebJoin:
  mov x8, #7
  str x8, [sp, #8]
  bl _frame_escape_write_stashed
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret

// The address is stored to a global and fetched back as a pointer of
// unknown origin; after the slot gets 7, a store through that pointer
// writes 11 with no call in between. True result: 11.
.globl _$s11FrameEscape12storeThroughSiyF
_$s11FrameEscape12storeThroughSiyF:
  sub sp, sp, #32
  stp x19, x30, [sp, #16]
  add x8, sp, #8
  adrp x9, _frame_escape_slot@PAGE
  str x8, [x9, _frame_escape_slot@PAGEOFF]
  bl _frame_escape_load_stashed
  mov x19, x0
  mov x10, #7
  str x10, [sp, #8]
  mov x12, #11
  str x12, [x19]
  ldr x0, [sp, #8]
  ldp x19, x30, [sp, #16]
  add sp, sp, #32
  ret

// A store at an index the tracer cannot compute. True result: 11 for an
// index of 8, 7 for an index of 16.
.globl _$s11FrameEscape12indexedStoreyS2iF
_$s11FrameEscape12indexedStoreyS2iF:
  sub sp, sp, #32
  mov x8, #7
  str x8, [sp, #8]
  mov x9, #11
  str x9, [sp, x0]
  ldr x0, [sp, #8]
  add sp, sp, #32
  ret

// A vector store the tracer does not model writes the slot. True result: 0.
.globl _$s11FrameEscape11vectorStoreSiyF
_$s11FrameEscape11vectorStoreSiyF:
  sub sp, sp, #32
  mov x8, #7
  str x8, [sp, #8]
  movi v0.2d, #0
  add x9, sp, #8
  st1 {v0.2d}, [x9]
  ldr x0, [sp, #8]
  add sp, sp, #32
  ret

// The address escapes bit-reversed, a transform the tracer does not model;
// the callee reverses it back and writes 11. True result: 11.
.globl _$s11FrameEscape10rbitEscapeSiyF
_$s11FrameEscape10rbitEscapeSiyF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  add x12, sp, #8
  rbit x9, x12
  mov x12, #0
  adrp x10, _frame_escape_slot@PAGE
  str x9, [x10, _frame_escape_slot@PAGEOFF]
  mov x11, #7
  str x11, [sp, #8]
  bl _frame_escape_write_reversed
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret

// Control: the slot's address never leaves the function, so the call cannot
// reach it under the ordinary frame ABI. True result: 7.
.globl _$s11FrameEscape8noEscapeSiyF
_$s11FrameEscape8noEscapeSiyF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  mov x8, #7
  str x8, [sp, #8]
  bl _frame_escape_nop
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret

// A dynamic allocation sized by the argument; the block's address goes to a
// call that writes 11 into the block, after a store into the block itself.
// Under the frame ABI the block lies below the fixed frame, so the fixed
// slot keeps 7. True result: 7.
.globl _$s11FrameEscape17dynamicAllocationyS2iF
_$s11FrameEscape17dynamicAllocationyS2iF:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  sub sp, sp, #32
  mov x8, #7
  stur x8, [x29, #-8]
  add x0, x0, #1
  mov x9, sp
  sub x10, x9, x0, lsl #4
  mov sp, x10
  mov x11, #5
  str x11, [x10, #8]
  mov x0, x10
  bl _frame_escape_fill
  ldur x0, [x29, #-8]
  mov sp, x29
  ldp x29, x30, [sp], #16
  ret

// The address leaves as an outgoing stack argument. True result: 11.
.globl _$s11FrameEscape13stackArgumentSiyF
_$s11FrameEscape13stackArgumentSiyF:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  add x10, sp, #24
  str x10, [sp]
  bl _frame_escape_stash_stack
  mov x9, #7
  str x9, [sp, #24]
  bl _frame_escape_write_stashed
  ldr x0, [sp, #24]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

// Slot A's address has escaped. Slot B's address is stored into slot A,
// read back through the escaped alias, and slot A is cleared before the
// call that receives the read-back pointer. True result: 11.
.globl _$s11FrameEscape12slotReadBackSiyF
_$s11FrameEscape12slotReadBackSiyF:
  sub sp, sp, #48
  stp x19, x30, [sp, #32]
  add x0, sp, #8
  bl _frame_escape_stash
  bl _frame_escape_load_stashed
  mov x19, x0
  add x12, sp, #16
  str x12, [sp, #8]
  ldr x10, [x19]
  str xzr, [sp, #8]
  mov x9, #7
  str x9, [sp, #16]
  mov x0, x10
  bl _frame_escape_fill
  ldr x0, [sp, #16]
  ldp x19, x30, [sp, #32]
  add sp, sp, #48
  ret

// Slot B's address is stored into slot A before A's own address escapes;
// a later call follows A to B. True result: 11.
.globl _$s11FrameEscape14slotChainLaterSiyF
_$s11FrameEscape14slotChainLaterSiyF:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  add x12, sp, #16
  str x12, [sp, #8]
  mov x9, #7
  str x9, [sp, #16]
  add x0, sp, #8
  bl _frame_escape_stash
  bl _frame_escape_write_chain
  ldr x0, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

// Slot A holds slot B's address when an indexed store makes every frame
// fact unknown; A is reloaded (still B's address) and handed to a call that
// writes 11 into B. True result: 11 for an index of 24.
.globl _$s11FrameEscape15slotIndexedLossyS2iF
_$s11FrameEscape15slotIndexedLossyS2iF:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  add x12, sp, #16
  str x12, [sp, #8]
  mov x9, #3
  str x9, [sp, x0]
  mov x9, #7
  str x9, [sp, #16]
  ldr x0, [sp, #8]
  bl _frame_escape_fill
  ldr x0, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

// Two frame addresses meet at a join with no recoverable condition; the
// survivor goes to a call that writes 11 through it. True result: 11 when
// the flag word is zero, 7 otherwise.
.globl _$s11FrameEscape11joinDroppedyS2iF
_$s11FrameEscape11joinDroppedyS2iF:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  ldr x11, [x0]
  add x10, sp, #8
  cbz x11, LjoinDroppedJoin
  add x10, sp, #16
LjoinDroppedJoin:
  mov x9, #7
  str x9, [sp, #8]
  str x9, [sp, #16]
  mov x0, x10
  bl _frame_escape_fill
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

// A 16-byte local escapes by its first word's address; the call writes 11
// into its second word. True result: 11.
.globl _$s11FrameEscape10wideEscapeSiyF
_$s11FrameEscape10wideEscapeSiyF:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  add x0, sp, #8
  bl _frame_escape_stash
  mov x9, #7
  str x9, [sp, #16]
  bl _frame_escape_write_stashed_second
  ldr x0, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

// Control: after the slot escapes, a load through a pointer of unknown
// origin reads memory; it writes nothing. True result: 7.
.globl _$s11FrameEscape11unknownLoadSiyF
_$s11FrameEscape11unknownLoadSiyF:
  sub sp, sp, #32
  stp x19, x30, [sp, #16]
  add x0, sp, #8
  bl _frame_escape_stash
  bl _frame_escape_dummy_pointer
  mov x19, x0
  mov x8, #7
  str x8, [sp, #8]
  ldr x10, [x19]
  ldr x0, [sp, #8]
  ldp x19, x30, [sp, #16]
  add sp, sp, #32
  ret

// Control: after the slot escapes, a store goes through the incoming
// pointer, which predates the frame and cannot reach it. True result: 7.
.globl _$s11FrameEscape13argumentStoreyS2iF
_$s11FrameEscape13argumentStoreyS2iF:
  sub sp, sp, #32
  stp x19, x30, [sp, #16]
  mov x19, x0
  add x0, sp, #8
  bl _frame_escape_stash
  mov x8, #7
  str x8, [sp, #8]
  mov x9, #11
  str x9, [x19]
  ldr x0, [sp, #8]
  ldp x19, x30, [sp, #16]
  add sp, sp, #32
  ret

.globl _frame_escape_write_stashed_second
_frame_escape_write_stashed_second:
  adrp x8, _frame_escape_slot@PAGE
  ldr x8, [x8, _frame_escape_slot@PAGEOFF]
  mov x9, #11
  str x9, [x8, #8]
  ret
.globl _frame_escape_dummy_pointer
_frame_escape_dummy_pointer:
  adrp x0, _frame_escape_dummy@PAGE
  add x0, x0, _frame_escape_dummy@PAGEOFF
  ret
// Control: a frame address sits in x8 at a call to `free`, whose one
// parameter is x0. True result: 7.
.globl _$s11FrameEscape10arityBoundSiyF
_$s11FrameEscape10arityBoundSiyF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  mov x9, #7
  str x9, [sp, #8]
  add x8, sp, #8
  mov x0, xzr
  bl _free
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret

// Control: a frame address saved at [sp, #8] with nothing stored at [sp] is
// not a stack argument. True result: 7.
.globl _$s11FrameEscape11outgoingGapSiyF
_$s11FrameEscape11outgoingGapSiyF:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  add x12, sp, #16
  str x12, [sp, #8]
  mov x9, #7
  str x9, [sp, #16]
  bl _frame_escape_nop
  ldr x0, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

// Control: a frame address at [sp] meets a Swift callee whose one Int
// parameter travels in x0; it reads no stack argument. True result: 7.
.globl _$s11FrameEscape17stackPrefixNoArgsSiyF
_$s11FrameEscape17stackPrefixNoArgsSiyF:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  add x12, sp, #16
  str x12, [sp]
  mov x9, #7
  str x9, [sp, #16]
  mov x0, #1
  bl _$s11FrameEscape4sinkyySiF
  ldr x0, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret
.globl _$s11FrameEscape4sinkyySiF
_$s11FrameEscape4sinkyySiF:
  ret

// Control: two locals addressed from x29. The lower one's address goes to
// a call that writes 11 through it; the upper one's address is taken
// separately, so it is a different variable and keeps 7. True result: 7.
.globl _$s11FrameEscape10fpBoundarySiyF
_$s11FrameEscape10fpBoundarySiyF:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  mov x9, #7
  stur x9, [x29, #-8]
  sub x0, x29, #16
  bl _frame_escape_fill
  sub x9, x29, #8
  ldr x0, [x9]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

// Control: the same with x29 at the frame's base and the locals above it.
// True result: 7.
.globl _$s11FrameEscape15fpAboveBoundarySiyF
_$s11FrameEscape15fpAboveBoundarySiyF:
  stp x29, x30, [sp, #-48]!
  mov x29, sp
  mov x9, #7
  str x9, [x29, #24]
  add x0, x29, #16
  bl _frame_escape_fill
  add x9, x29, #24
  ldr x0, [x9]
  ldp x29, x30, [sp], #48
  ret

.globl _frame_escape_stash_stack
_frame_escape_stash_stack:
  ldr x9, [sp]
  adrp x8, _frame_escape_slot@PAGE
  str x9, [x8, _frame_escape_slot@PAGEOFF]
  ret
.globl _frame_escape_write_chain
_frame_escape_write_chain:
  adrp x8, _frame_escape_slot@PAGE
  ldr x8, [x8, _frame_escape_slot@PAGEOFF]
  ldr x8, [x8]
  mov x9, #11
  str x9, [x8]
  ret
.globl _frame_escape_fill
_frame_escape_fill:
  mov x9, #11
  str x9, [x0]
  ret
.globl _frame_escape_stash
_frame_escape_stash:
  adrp x8, _frame_escape_slot@PAGE
  str x0, [x8, _frame_escape_slot@PAGEOFF]
  ret
.globl _frame_escape_load_stashed
_frame_escape_load_stashed:
  adrp x8, _frame_escape_slot@PAGE
  ldr x0, [x8, _frame_escape_slot@PAGEOFF]
  ret
.globl _frame_escape_write_stashed
_frame_escape_write_stashed:
  adrp x8, _frame_escape_slot@PAGE
  ldr x8, [x8, _frame_escape_slot@PAGEOFF]
  mov x9, #11
  str x9, [x8]
  ret
.globl _frame_escape_write_reversed
_frame_escape_write_reversed:
  adrp x8, _frame_escape_slot@PAGE
  ldr x8, [x8, _frame_escape_slot@PAGEOFF]
  rbit x8, x8
  mov x9, #11
  str x9, [x8]
  ret
.globl _frame_escape_nop
_frame_escape_nop:
  ret

.data
.p2align 3
_frame_escape_slot:
  .quad 0
_frame_escape_dummy:
  .quad 0

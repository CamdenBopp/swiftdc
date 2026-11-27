// ExistentialMetatypesClient.staleFour(Int) -> Int, written by hand: it
// stores 7 in a stack slot, passes that slot in x8 to makeFour, and returns
// the slot's first word. makeFour returns five words through x8, so it
// overwrites the slot and the function returns a metadata pointer, never 7.
.text
.p2align 2
.globl _$s26ExistentialMetatypesClient9staleFouryS2iF
_$s26ExistentialMetatypesClient9staleFouryS2iF:
  sub sp, sp, #0x40
  stp x29, x30, [sp, #0x30]
  add x29, sp, #0x30
  mov w9, #7
  str x9, [sp, #8]
  add x8, sp, #8
  bl _$s20ExistentialMetatypes8makeFouryAA2P1_AA2P2AA2P3AA2P4pXpSiF
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #0x30]
  add sp, sp, #0x40
  ret

// ExistentialMetatypesClient.staleThree(Int) -> Int, by hand: the same slot
// holds 9 across a call to makeThree, which returns four words in x0 to x3
// and is given no buffer. The slot is the function's own and it returns 9.
.globl _$s26ExistentialMetatypesClient10staleThreeyS2iF
_$s26ExistentialMetatypesClient10staleThreeyS2iF:
  sub sp, sp, #0x40
  stp x29, x30, [sp, #0x30]
  add x29, sp, #0x30
  mov w9, #9
  str x9, [sp, #8]
  bl _$s20ExistentialMetatypes9makeThreeyAA2P1_AA2P2AA2P3pXpSiF
  ldr x0, [sp, #8]
  ldp x29, x30, [sp, #0x30]
  add sp, sp, #0x40
  ret

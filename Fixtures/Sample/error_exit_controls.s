.text
.p2align 2
.globl _$s9ExitProof7successSiyKF
_$s9ExitProof7successSiyKF:
  mov x21, #0
  mov x0, #13
  ret
.globl _$s9ExitProof5errorSiyKF
_$s9ExitProof5errorSiyKF:
  mov x21, #1
  mov x0, #13
  ret
.globl _$s9ExitProof12unknownErroryS2iKF
_$s9ExitProof12unknownErroryS2iKF:
  ldr x21, [x0]
  mov x0, #13
  ret
.globl _$s9ExitProof12unknownValueyS2iKF
_$s9ExitProof12unknownValueyS2iKF:
  mov x21, #0
  ldr x0, [x0]
  ret

.globl _$s9ExitProof14guardedSuccessyS2iKF
_$s9ExitProof14guardedSuccessyS2iKF:
  ldr x21, [x0]
  cbnz x21, LsuccessError
  mov x0, #13
  ret
LsuccessError:
  mov x21, #1
  ret
.globl _$s9ExitProof14guardedClobberyS2iKF
_$s9ExitProof14guardedClobberyS2iKF:
  ldr x21, [x0]
  cbnz x21, LclobberError
  ldr x21, [x0]
  mov x0, #13
  ret
LclobberError:
  mov x21, #1
  ret
.globl _$s9ExitProof13guardedNarrowyS2iKF
_$s9ExitProof13guardedNarrowyS2iKF:
  ldr x21, [x0]
  cbnz w21, LnarrowError
  mov x0, #13
  ret
LnarrowError:
  mov x21, #1
  ret
.globl _$s9ExitProof11guardedJoinyS2iKF
_$s9ExitProof11guardedJoinyS2iKF:
  ldr x21, [x0]
  cbnz x21, LjoinOther
  nop
  b LjoinReturn
LjoinOther:
  nop
  b LjoinReturn
LjoinReturn:
  mov x0, #13
  b LjoinActualReturn
LjoinActualReturn:
  ret

.globl _$s9ExitProof13guardedOpaqueyS2iKF
_$s9ExitProof13guardedOpaqueyS2iKF:
  ldr x21, [x0]
  cbz x21, LopaqueReturn
  ldr x1, [x0, #8]
  br x1
LopaqueReturn:
  mov x0, #13
  ret

.globl _$s9ExitProof12opaqueBypassyS2iKF
_$s9ExitProof12opaqueBypassyS2iKF:
  ldr x21, [x0]
  cbz x2, LbypassZero
  ldr x1, [x0, #8]
  br x1
LbypassZero:
  mov x21, #0
LbypassReturn:
  mov x0, #13
  ret
.globl _$s9ExitProof17opaqueThrowBypassyS2iKF
_$s9ExitProof17opaqueThrowBypassyS2iKF:
  ldr x21, [x0]
  cbz x2, LbypassNonzero
  ldr x1, [x0, #8]
  br x1
LbypassNonzero:
  mov x21, #1
LbypassThrowReturn:
  mov x0, #13
  ret

// Normal-exit proofs beyond an explicit zero. A function throws only by
// writing x21, so a path that leaves it as it arrived returns normally:
// untouched, across a call that keeps it, or spilled and reloaded intact.
// Each negative twin loses that proof. True behaviour: the positive forms
// return 13; the negative forms may return either way.
.globl _$s9ExitProof9untouchedyS2iKF
_$s9ExitProof9untouchedyS2iKF:
  mov x0, #13
  ret
.globl _$s9ExitProof14preservingCallyS2iKF
_$s9ExitProof14preservingCallyS2iKF:
  stp x29, x30, [sp, #-16]!
  bl _exit_proof_keeps_x21
  mov x0, #13
  ldp x29, x30, [sp], #16
  ret
// A callee that may throw redefines x21; returning straight after it
// forwards whatever it left there.
.globl _$s9ExitProof12throwingCallyS2iKF
_$s9ExitProof12throwingCallyS2iKF:
  stp x29, x30, [sp, #-16]!
  bl _$s9ExitProof5errorSiyKF
  mov x0, #13
  ldp x29, x30, [sp], #16
  ret
// A C-named helper cannot throw, but its body writes x21 and never
// restores it (`CalleeRegisterSummary`).
.globl _$s9ExitProof14clobberingCallyS2iKF
_$s9ExitProof14clobberingCallyS2iKF:
  stp x29, x30, [sp, #-16]!
  bl _exit_proof_clobbers_x21
  mov x0, #13
  ldp x29, x30, [sp], #16
  ret
// The entry block is also a loop target, reached again after x21 is loaded.
.globl _$s9ExitProof13entryBackEdgeyS2iKF
_$s9ExitProof13entryBackEdgeyS2iKF:
LbackEntry:
  cbz x1, LbackReturn
  ldr x21, [x2]
  b LbackEntry
LbackReturn:
  mov x0, #13
  ret
// The second `ret` has no modelled predecessor; whatever reaches it is not
// the function's own entry.
.globl _$s9ExitProof12orphanReturnyS2iKF
_$s9ExitProof12orphanReturnyS2iKF:
  mov x0, #13
  ret
LorphanBlock:
  mov x0, #7
  ret
// An unreachable block loads x21 and joins the return path.
.globl _$s9ExitProof10orphanJumpyS2iKF
_$s9ExitProof10orphanJumpyS2iKF:
  mov x0, #13
LorphanJoin:
  ret
LorphanLoad:
  ldr x21, [x2]
  b LorphanJoin
// One path leaves x21 untouched, the other zeroes it: both normal, though
// no single value describes the join.
.globl _$s9ExitProof15untouchedOrZeroyS2iKF
_$s9ExitProof15untouchedOrZeroyS2iKF:
  cbz x0, LuozJoin
  mov x21, #0
LuozJoin:
  mov x0, #13
  ret
// A throw merged into the normal epilogue: the zero edge's path returns
// normally once the proven throw path (`mov x21, #1`) is set aside.
.globl _$s9ExitProof14mergedZeroEdgeyS2iKF
_$s9ExitProof14mergedZeroEdgeyS2iKF:
  ldr x21, [x1]
  cbnz x21, LmzThrow
  b LmzReturn
LmzThrow:
  mov x21, #1
LmzReturn:
  mov x0, #13
  ret
// -Onone shape: the incoming x21 is spilled and reloaded on the way out.
.globl _$s9ExitProof11spillReloadyS2iKF
_$s9ExitProof11spillReloadyS2iKF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  str x21, [sp, #8]
  bl _exit_proof_keeps_x21
  ldr x21, [sp, #8]
  mov x0, #13
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret
// The same reload after the save slot was overwritten.
.globl _$s9ExitProof12spillClobberyS2iKF
_$s9ExitProof12spillClobberyS2iKF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  str x21, [sp, #8]
  str x0, [sp, #8]
  ldr x21, [sp, #8]
  mov x0, #13
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret
// The save slot's address reaches a call, which may rewrite it.
.globl _$s9ExitProof11spillEscapeyS2iKF
_$s9ExitProof11spillEscapeyS2iKF:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  str x21, [sp, #8]
  add x0, sp, #8
  bl _exit_proof_keeps_x21
  ldr x21, [sp, #8]
  mov x0, #13
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret
// -O shape: the incoming x21 is parked in a callee-saved register.
.globl _$s9ExitProof12registerCopyyS2iKF
_$s9ExitProof12registerCopyyS2iKF:
  stp x19, x30, [sp, #-16]!
  mov x19, x21
  bl _exit_proof_keeps_x21
  mov x21, x19
  mov x0, #13
  ldp x19, x30, [sp], #16
  ret
// An unresolved callee may be a throwing Swift function; nothing proves
// it hands x21 back.
.globl _$s9ExitProof13indirectThrowyS2iKF
_$s9ExitProof13indirectThrowyS2iKF:
  stp x29, x30, [sp, #-16]!
  blr x1
  mov x0, #13
  ldp x29, x30, [sp], #16
  ret
// A proven normal exit with no result: a bare return, single-block and
// branching (the structurer renders only the second itself).
.globl _$s9ExitProof8voidExityyKF
_$s9ExitProof8voidExityyKF:
  ret
.globl _$s9ExitProof10voidBranchyySiKF
_$s9ExitProof10voidBranchyySiKF:
  cbz x0, LvoidBranchEnd
  nop
LvoidBranchEnd:
  ret
.globl _exit_proof_keeps_x21
_exit_proof_keeps_x21:
  ret
.globl _exit_proof_clobbers_x21
_exit_proof_clobbers_x21:
  mov x21, #5
  ret

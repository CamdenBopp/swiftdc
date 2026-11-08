// Fixpoint visiting order. The tracer's worklist starts with every block
// in address order.
.text
.p2align 2

// A loop whose body lies before, in address order, the jump into it. The
// body ran before any predecessor had, from an empty state, and that
// "nothing known" chased the real facts around the cycle forever
// (`values.fixpoint-cap`). Reduced from a 39-block app function by keeping
// only its control flow and register copies. Both paths set x25 to the
// target's page. True result: the page of _fixpoint_target, for any
// arguments (x1 counts the outer loop down).
.globl _$s10FixedPoint9unsettledyS2i_SitF
_$s10FixedPoint9unsettledyS2i_SitF:
  str x25, [sp, #-16]!
  adrp x25, _fixpoint_target@PAGE
Lhead:
  b Ltest
Lbody:
  cbz x0, Lnext
  adrp x25, _fixpoint_target@PAGE
Ltest:
  cbz x0, Lbody
Lnext:
  subs x1, x1, #1
  b.gt Lhead
  mov x0, x25
  ldr x25, [sp], #16
  ret

// A cycle entered only through a branch the CFG cannot follow (the target
// is hidden behind rbit), flowing into the join both paths reach. A
// block no modelled edge reaches must still run, from nothing, or the
// join sees only the direct path. True result: 1 when x0 == 0, else 2.
.globl _$s10FixedPoint14unmodelledLoopyS2i_SitF
_$s10FixedPoint14unmodelledLoopyS2i_SitF:
  mov x8, #1
  cbz x0, Ljoin
  adr x9, Lcycle
  rbit x9, x9
  rbit x9, x9
  br x9
Lcycle:
  mov x8, #2
  subs x1, x1, #1
  b.gt Lcycle
Ljoin:
  mov x0, x8
  ret

// A block no modelled edge reaches, like a landing pad, starts from
// nothing; the blocks it leads to wait for it, so what it sets reaches
// them. True result: 3.
.globl _$s10FixedPoint11handlerTailyS2i_SitF
_$s10FixedPoint11handlerTailyS2i_SitF:
  adr x9, Lhandler
  rbit x9, x9
  rbit x9, x9
  br x9
Lhandler:
  mov x8, #3
  b Ltail
Ltail:
  mov x0, x8
  ret

.data
.p2align 12
.globl _fixpoint_target
_fixpoint_target:
  .quad 0

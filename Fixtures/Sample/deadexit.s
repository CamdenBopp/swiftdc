// Two loops with several exits each, reduced from a stripped swift-syntax
// index walk (`index(_:offsetBy:)` forward and back). Each loop body ends
// in an if/else whose arms both leave (`goto` the result store or the
// not-found store), and the body's emission stops at the epilogue: a
// transfer added there is dead. True behaviour: x1 < 0 walks x23 down
// from 0 while x23 > x1, else x21 counts x1 down to 0; either loop stops
// early at x8 == x24 (or x23) and stores 0, otherwise stores x8.
.globl _twoExits
.p2align 2
_twoExits:
  stp x29, x30, [sp, #-16]!
  mov x21, x1
  tbnz x1, #63, 3f
  cbz x21, 4f
1:
  cmp x8, x23
  b.eq 5f
  bl _step
  subs x21, x21, #1
  b.ne 1b
  b 4f
3:
  mov x23, #0
2:
  cmp x8, x24
  b.eq 5f
  sub x23, x23, #1
  bl _step
  cmp x23, x21
  b.gt 2b
4:
  str x8, [x19]
  b 6f
5:
  str xzr, [x19]
6:
  ldp x29, x30, [sp], #16
  ret
.globl _step
.p2align 2
_step:
  ret

// Interior-jump shapes. True behaviour in comments.
.text
.globl _shared_b     // shared_b(x) = (x*4) + 9 ; its tail at Lshared adds 9 and returns
.p2align 2
_shared_b:
  lsl x0, x0, #2
Lshared:
  add x0, x0, #9
  ret

.globl _shared_a     // shared_a(x) = (x - 1) + 9 : jumps into shared_b's tail, NOT a call to shared_b
.p2align 2
_shared_a:
  sub x0, x0, #1
  b Lshared

.globl _call_mid     // calls the interior of shared_b at Lshared (x0=5) then adds 1 : returns 15
.p2align 2
_call_mid:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  mov x0, #5
  bl Lshared
  add x0, x0, #1
  ldp x29, x30, [sp], #16
  ret

.globl _adr_tail     // indirect tail call through adr: returns shared_b(x0)
.p2align 2
_adr_tail:
  adr x16, _shared_b
  br x16

.globl _adr_call     // indirect call through adrp/add then blr: shared_b(3)+0
.p2align 2
_adr_call:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  adrp x8, _shared_b@PAGE
  add x8, x8, _shared_b@PAGEOFF
  mov x0, #3
  blr x8
  ldp x29, x30, [sp], #16
  ret

.globl _stub_tail    // tail call to libSystem abs via stub: returns abs(x0)
.p2align 2
_stub_tail:
  b _abs

.globl _tail_noreturn_cmp // if x0 > 10 tail-calls shared_b(x0) else tail-calls shared_a(x0)
.p2align 2
_tail_noreturn_cmp:
  cmp x0, #10
  b.gt _shared_b
  b _shared_a

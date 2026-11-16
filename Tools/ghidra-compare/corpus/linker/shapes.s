// Hand-written linker shapes. True behaviour in comments.
.text
.globl _real_add      // returns x0 + x1
.p2align 2
_real_add:
  add x0, x0, x1
  ret

.globl _tail_caller   // tail call: returns real_add(x0*2, 7) ; b is a call+return
.p2align 2
_tail_caller:
  lsl x0, x0, #1
  mov x1, #7
  b _real_add

.globl _outer         // has an alt_entry _inner in the middle; outer(x)=x+3+? : outer adds 1 then falls into inner which adds 2 and returns
.p2align 2
_outer:
  add x0, x0, #1
.globl _inner
.alt_entry _inner
_inner:
  add x0, x0, #2
  ret

.globl _got_caller    // calls _puts through a GOT load (no stub): puts(x0)
.p2align 2
_got_caller:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  adrp x16, _puts@GOTPAGE
  ldr x16, [x16, _puts@GOTPAGEOFF]
  blr x16
  ldp x29, x30, [sp], #16
  ret

.globl _got_tail      // tail-jumps to _puts via GOT: puts(x0)
.p2align 2
_got_tail:
  adrp x16, _puts@GOTPAGE
  ldr x16, [x16, _puts@GOTPAGEOFF]
  br x16

.globl _leaf_noframe  // leaf with no frame: returns x0*x0 + 1
.p2align 2
_leaf_noframe:
  mul x0, x0, x0
  add x0, x0, #1
  ret

.p2align 2
_local_helper:        // local (strippable) symbol: returns x0 - 5
  sub x0, x0, #5
  ret

.globl _calls_local   // returns local_helper(x0) + 10 via bl
.p2align 2
_calls_local:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  bl _local_helper
  add x0, x0, #10
  ldp x29, x30, [sp], #16
  ret

.globl _calls_inner   // calls the alt entry _inner (not _outer): returns x0+2
.p2align 2
_calls_inner:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  bl _inner
  ldp x29, x30, [sp], #16
  ret

.globl _cond_tail     // if x0==0 tail-call real_add(0,x1) else return 9
.p2align 2
_cond_tail:
  cbz x0, Ltail
  mov x0, #9
  ret
Ltail:
  b _real_add

.globl _fallthrough_a  // no ret: falls through into _fallthrough_b. a(x)= x+100+1
.p2align 2
_fallthrough_a:
  add x0, x0, #100
.globl _fallthrough_b  // separate function start; b(x) = x+1
_fallthrough_b:
  add x0, x0, #1
  ret

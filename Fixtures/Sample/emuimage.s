// What the emulator oracle must get right about an image and about runs,
// apart from the program's own arithmetic.
//
// _emu_image_rebased()        -> 77: loads a pointer the loader rebases, then
//                                 the word it points at.
// _emu_image_bound()          -> the address of an import, loaded from its
//                                 GOT slot: one the loader binds.
// _emu_image_two_imports()    -> the two imports' addresses xored: not 0,
//                                 since each import has its own.
// _emu_image_call_pointer()   -> 5: calls an import through that pointer and
//                                 returns a constant of its own.
// _emu_image_uses_result()    -> the import's result plus 1: nothing the
//                                 emulator can know.
// _emu_image_passes_local()   -> 9, after handing an import the address of a
//                                 local.
// _emu_image_count()          -> 1 on every run: adds 1 to a word of data
//                                 that starts at 0.
// _emu_image_fill_vector()    -> 1, leaving all of v0 set.
// _emu_image_vector_upper()   -> 0: the upper half of v0 as the run began.
// _emu_image_below_write(a)   -> a, stored below sp. Breaks no rule: a leaf
//                                 may use the red zone Darwin does not have
//                                 only in a fixture.
// _emu_image_below_read()     -> 0: the word below sp as the run began.
// _emu_image_spin()           -> 0 after 5000 trips of a loop: more branch
//                                 events than one reply lists.
// EmuImage.keep(n)            -> n: what objc_retain returns, its argument.
//                                 Only the emulator runs it; n is no object.
// EmuImage.fixed()            -> 1: retains nil, which returns nil, and
//                                 branches on that.
// _emu_image_clobbers()       -> 1, with x19 changed. Breaks the ABI on purpose.
// _emu_image_unbalanced()     -> 2, with sp 16 lower. Breaks the ABI on purpose.
.text
.p2align 2
.globl _emu_image_rebased
_emu_image_rebased:
  adrp x8, _emu_image_cell@PAGE
  ldr x8, [x8, _emu_image_cell@PAGEOFF]
  ldr x0, [x8]
  ret

.p2align 2
.globl _emu_image_bound
_emu_image_bound:
  adrp x8, _getpid@GOTPAGE
  ldr x0, [x8, _getpid@GOTPAGEOFF]
  ret

.p2align 2
.globl _emu_image_two_imports
_emu_image_two_imports:
  adrp x8, _getpid@GOTPAGE
  ldr x8, [x8, _getpid@GOTPAGEOFF]
  adrp x9, _getuid@GOTPAGE
  ldr x9, [x9, _getuid@GOTPAGEOFF]
  eor x0, x8, x9
  ret

.p2align 2
.globl _emu_image_call_pointer
_emu_image_call_pointer:
  stp x29, x30, [sp, #-16]!
  adrp x8, _getpid@GOTPAGE
  ldr x8, [x8, _getpid@GOTPAGEOFF]
  blr x8
  mov x0, #5
  ldp x29, x30, [sp], #16
  ret

.p2align 2
.globl _emu_image_uses_result
_emu_image_uses_result:
  stp x29, x30, [sp, #-16]!
  bl _getppid
  add x0, x0, #1
  ldp x29, x30, [sp], #16
  ret

.p2align 2
.globl _emu_image_passes_local
_emu_image_passes_local:
  sub sp, sp, #32
  stp x29, x30, [sp, #16]
  add x0, sp, #8
  bl _getppid
  mov x0, #9
  ldp x29, x30, [sp, #16]
  add sp, sp, #32
  ret

.p2align 2
.globl _emu_image_count
_emu_image_count:
  adrp x8, _emu_image_counter@PAGE
  ldr x9, [x8, _emu_image_counter@PAGEOFF]
  add x9, x9, #1
  str x9, [x8, _emu_image_counter@PAGEOFF]
  mov x0, x9
  ret

.p2align 2
.globl _emu_image_fill_vector
_emu_image_fill_vector:
  movi.16b v0, #0xff
  mov x0, #1
  ret

.p2align 2
.globl _emu_image_vector_upper
_emu_image_vector_upper:
  mov x0, v0.d[1]
  ret

.p2align 2
.globl _emu_image_below_write
_emu_image_below_write:
  stur x0, [sp, #-16]
  ret

.p2align 2
.globl _emu_image_below_read
_emu_image_below_read:
  ldur x0, [sp, #-16]
  ret

.p2align 2
.globl _emu_image_spin
_emu_image_spin:
  mov x0, #5000
1:
  sub x0, x0, #1
  cbnz x0, 1b
  ret

.p2align 2
.globl _$s8EmuImage4keepyS2iF
_$s8EmuImage4keepyS2iF:
  stp x29, x30, [sp, #-16]!
  bl _objc_retain
  ldp x29, x30, [sp], #16
  ret

.p2align 2
.globl _$s8EmuImage5fixedSiyF
_$s8EmuImage5fixedSiyF:
  stp x29, x30, [sp, #-16]!
  mov x0, #0
  bl _objc_retain
  cbnz x0, 1f
  mov x0, #1
  b 2f
1:
  mov x0, #2
2:
  ldp x29, x30, [sp], #16
  ret

.p2align 2
.globl _emu_image_clobbers
_emu_image_clobbers:
  mov x19, #1
  mov x0, #1
  ret

.p2align 2
.globl _emu_image_unbalanced
_emu_image_unbalanced:
  sub sp, sp, #16
  mov x0, #2
  ret

.data
.p2align 3
_emu_image_value:
  .quad 77
_emu_image_cell:
  .quad _emu_image_value
_emu_image_counter:
  .quad 0
.subsections_via_symbols

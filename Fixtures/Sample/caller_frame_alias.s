// Native caller-owned frame alias and private-frame precision controls.
// The C caller owns an initialized Cell at its call-timeSP+64 and passes it
// inx20 under the independently declared mutating value-self ABI. In F,
// that same address is a POSITIVE frame coordinate(+64). No sret/global
// coincidence is involved. The complete leaf transports entryself tox0.
.text
.p2align 2
.globl _$s9FrameSelf4CellV11cachedAliasSiyF
_$s9FrameSelf4CellV11cachedAliasSiyF:
  sub sp, sp, #32
  str x30, [sp, #16]
  mov x9, #7
  str x9, [sp, #96]
  bl _complete_frame_return_self
  mov x9, #99
  str x9, [x0]
  // Actual x0 aliases frame(+64); reciprocal owner must discard cached7.
  ldr x0, [sp, #96]
  ldr x30, [sp, #16]
  add sp, sp, #32
  ret

.p2align 2
.globl _$s9FrameSelf4CellV12privateCacheSiyF
_$s9FrameSelf4CellV12privateCacheSiyF:
  sub sp, sp, #32
  str x30, [sp, #16]
  mov x9, #7
  str x9, [sp, #8]
  bl _complete_frame_return_self
  mov x9, #99
  str x9, [x0]
  // Private frame(-24) cannot alias entryself, which predates this frame.
  ldr x0, [sp, #8]
  ldr x30, [sp, #16]
  add sp, sp, #32
  ret

.p2align 2
.globl _complete_frame_return_self
_complete_frame_return_self:
  mov x0, x20
  ret

// Both C oracles keep native SP16-aligned and preserve callee-savedx20.
// Cell's word is Int64-sized/aligned under the ordinary Apple ARM64 ABI.
.p2align 2
.globl _complete_frame_self_alias_oracle
_complete_frame_self_alias_oracle:
  sub sp, sp, #96
  stp x20, x30, [sp, #80]
  mov x9, #17
  str x9, [sp, #56]
  mov x9, #7
  str x9, [sp, #64]
  mov x9, #19
  str x9, [sp, #72]
  add x20, sp, #64
  bl _$s9FrameSelf4CellV11cachedAliasSiyF
  cmp x0, #99
  b.ne Lframe_self_alias_fail
  ldr x9, [sp, #64]
  cmp x9, #99
  b.ne Lframe_self_alias_fail
  ldr x9, [sp, #56]
  cmp x9, #17
  b.ne Lframe_self_alias_fail
  ldr x9, [sp, #72]
  cmp x9, #19
  b.ne Lframe_self_alias_fail
  mov x0, #99
  b Lframe_self_alias_end
Lframe_self_alias_fail:
  mov x0, #-1
Lframe_self_alias_end:
  ldp x20, x30, [sp, #80]
  add sp, sp, #96
  ret

.p2align 2
.globl _complete_frame_self_private_oracle
_complete_frame_self_private_oracle:
  sub sp, sp, #96
  stp x20, x30, [sp, #80]
  mov x9, #17
  str x9, [sp, #56]
  mov x9, #7
  str x9, [sp, #64]
  mov x9, #19
  str x9, [sp, #72]
  add x20, sp, #64
  bl _$s9FrameSelf4CellV12privateCacheSiyF
  cmp x0, #7
  b.ne Lframe_self_private_fail
  ldr x9, [sp, #64]
  cmp x9, #99
  b.ne Lframe_self_private_fail
  ldr x9, [sp, #56]
  cmp x9, #17
  b.ne Lframe_self_private_fail
  ldr x9, [sp, #72]
  cmp x9, #19
  b.ne Lframe_self_private_fail
  // Both the exact private return7 and actual mutation99 were checked.
  mov x0, #799
  b Lframe_self_private_end
Lframe_self_private_fail:
  mov x0, #-1
Lframe_self_private_end:
  ldp x20, x30, [sp, #80]
  add sp, sp, #96
  ret
.subsections_via_symbols

// F.entrySP=oracleSP. F allocates48 bytes:
//   [sp,16]  = private frame(-32), value7
//   [sp,112] = caller-owned frame(+64), saved pointer to private(-32)
// Entry value-self is a DIFFERENT caller-owned Cell at frame(+72).
.text
.p2align 2
.globl _$s9FrameSelf4CellV9lostReachSiyF
_$s9FrameSelf4CellV9lostReachSiyF:
  sub sp, sp, #48
  str x30, [sp, #32]
  mov x9, #7
  str x9, [sp, #16]
  add x9, sp, #16
  str x9, [sp, #112]
  mov x9, #0
  bl _complete_frame_return_self
  mov x9, #99
  str x9, [x0]
  // No explicit private-frame-pointer value survives in an argument/scratch
  // register. Only the actual saved caller-owned slot still holds it.
  mov x0, #0
  mov x8, #0
  mov x9, #0
  mov x10, #0
  bl _complete_frame_lost_reach_write
  ldr x0, [sp, #16]
  ldr x30, [sp, #32]
  add sp, sp, #48
  ret

// Deliberately unproved: the load rejects complete literal-body discovery.
// This implicit caller-frame input follows the machine-outliner contract;
// it is not a C source formal that could independently escape the pointer.
.p2align 2
.globl _complete_frame_lost_reach_write
_complete_frame_lost_reach_write:
  ldr x9, [sp, #112]
  mov x10, #99
  str x10, [x9]
  ret

.p2align 2
.globl _complete_frame_self_lost_reach_oracle
_complete_frame_self_lost_reach_oracle:
  sub sp, sp, #128
  stp x20, x30, [sp, #112]
  mov x9, #17
  str x9, [sp, #56]
  str xzr, [sp, #64]
  mov x9, #7
  str x9, [sp, #72]
  mov x9, #19
  str x9, [sp, #80]
  add x20, sp, #72
  bl _$s9FrameSelf4CellV9lostReachSiyF
  cmp x0, #99
  b.ne Llost_reach_fail
  // self-field store99 and the later private-pointer store99 both occurred.
  ldr x9, [sp, #72]
  cmp x9, #99
  b.ne Llost_reach_fail
  // Validate the saved pointer's coordinate without dereferencing it after
  // F returned. F's private pointer was oracleSP-32.
  ldr x9, [sp, #64]
  sub x10, sp, #32
  cmp x9, x10
  b.ne Llost_reach_fail
  ldr x9, [sp, #56]
  cmp x9, #17
  b.ne Llost_reach_fail
  ldr x9, [sp, #80]
  cmp x9, #19
  b.ne Llost_reach_fail
  mov x0, #99
  b Llost_reach_end
Llost_reach_fail:
  mov x0, #-1
Llost_reach_end:
  ldp x20, x30, [sp, #112]
  add sp, sp, #128
  ret
.subsections_via_symbols

.text
.p2align 2
.globl _$s9FrameSelf18argumentFieldAliasySiAA10PointerBoxCF
_$s9FrameSelf18argumentFieldAliasySiAA10PointerBoxCF:
  sub sp, sp, #64
  stp x19, x30, [sp, #48]
  mov x19, x0
  mov x9, #17
  str x9, [sp, #8]
  mov x9, #7
  str x9, [sp, #16]
  mov x9, #19
  str x9, [sp, #24]
  add x9, sp, #16
  str x9, [x19, #16]
  ldr x1, [x19, #16]
  mov x9, #99
  str x9, [x1]
  ldr x0, [sp, #16]
  // Check both private guard words with straight-line arithmetic so no
  // extra CFG arm can independently obscure the stale cached7 diagnosis.
  ldr x9, [sp, #8]
  sub x9, x9, #17
  ldr x10, [sp, #24]
  sub x10, x10, #19
  orr x9, x9, x10
  cmp x9, #0
  mov x10, #-1
  csel x0, x0, x10, eq
  ldp x19, x30, [sp, #48]
  add sp, sp, #64
  ret
.subsections_via_symbols

.text
.p2align 2
.globl _entry_pointer_probe
_entry_pointer_probe:
  sub sp, sp, #32
  mov x9, #7
  str x9, [sp, #8]
  add x9, sp, #8
  adrp x10, _entry_pointer_positive_captured@PAGE
  str x9, [x10, _entry_pointer_positive_captured@PAGEOFF]
  mov x9, #0
  mov x10, #0
  mov x11, #99
  str x11, [x0]
  ldr x0, [sp, #8]
  add sp, sp, #32
  ret
.data
.p2align 3
.globl _entry_pointer_positive_captured
_entry_pointer_positive_captured:
  .quad 0
.subsections_via_symbols

.text
.p2align 2
.globl _entry_pointer_copy_probe
_entry_pointer_copy_probe:
  sub sp, sp, #96
  stp x29, x30, [sp, #80]
  mov x9, #17
  str x9, [sp, #56]
  mov x9, #3
  str x9, [sp, #64]
  mov x9, #19
  str x9, [sp, #72]
  bl _entry_pointer_copy_body
  cmp x0, #7
  b.ne Lentry_copy_fail
  ldr x9, [sp, #64]
  cmp x9, #99
  b.ne Lentry_copy_fail
  ldr x9, [sp, #56]
  cmp x9, #17
  b.ne Lentry_copy_fail
  ldr x9, [sp, #72]
  cmp x9, #19
  b.ne Lentry_copy_fail
  mov x0, #7
  b Lentry_copy_end
Lentry_copy_fail:
  mov x0, #-1
Lentry_copy_end:
  ldp x29, x30, [sp, #80]
  add sp, sp, #96
  ret

.p2align 2
.globl _entry_pointer_copy_body
_entry_pointer_copy_body:
  sub sp, sp, #80
  str x30, [sp, #64]
  mov x9, #7
  str x9, [sp, #8]
  add x9, sp, #8
  adrp x10, _entry_pointer_copy_captured@PAGE
  str x9, [x10, _entry_pointer_copy_captured@PAGEOFF]
  mov x9, #0
  mov x10, #0
  mov x3, x0
  // Body.entrySP+64 = body.sp+144 = adapter.sp+64.
  add x2, sp, #144
  bl _entry_pointer_copy_literal_helper
  mov x9, #99
  str x9, [x0]
  ldr x0, [sp, #8]
  ldr x30, [sp, #64]
  add sp, sp, #80
  ret

// Entirely modeled literal store + entry-rooted output. Positive frame64
// makes invalidatesFields=true, while outputx0 transports immutable arg0.
.p2align 2
.globl _entry_pointer_copy_literal_helper
_entry_pointer_copy_literal_helper:
  mov x9, #99
  str x9, [x2]
  mov x0, x3
  ret
.data
.p2align 3
.globl _entry_pointer_copy_captured
_entry_pointer_copy_captured:
  .quad 0
.subsections_via_symbols

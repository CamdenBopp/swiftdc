.text
.p2align 2
.globl _$s9PlanAlias11callerStoreAA6PacketVyF
_$s9PlanAlias11callerStoreAA6PacketVyF:
    sub sp, sp, #48
    stp x20, x28, [sp, #16]
    stp x29, x30, [sp, #32]
    mov x28, x8
    bl _negative_may_make_packet
    mov x20, x28
    bl _negative_plan_caller_frame_store
    ldp x20, x28, [sp, #16]
    ldp x29, x30, [sp, #32]
    add sp, sp, #48
    ret

.p2align 2
.globl _negative_plan_caller_frame_store
_negative_plan_caller_frame_store:
    mov x9, #99
    str x9, [sp, #120]
    ret

// A C-exported oracle fixes the caller-owned buffer location independently
// of Swift optimization/layout. The ordinary maker independently establishes
// the40-byte Swift sret ABI in LLVM, as in prior native reductions.
.p2align 2
.globl _negative_plan_caller_frame_oracle
_negative_plan_caller_frame_oracle:
    sub sp, sp, #128
    stp x29, x30, [sp, #112]
    add x8, sp, #64
    bl _$s9PlanAlias11callerStoreAA6PacketVyF
    ldr x9, [sp, #64]
    cmp x9, #1
    b.ne Lnegative_plan_failure
    ldr x9, [sp, #72]
    cmp x9, #99
    b.ne Lnegative_plan_failure
    ldr x9, [sp, #80]
    cmp x9, #3
    b.ne Lnegative_plan_failure
    ldr x9, [sp, #88]
    cmp x9, #4
    b.ne Lnegative_plan_failure
    ldr x9, [sp, #96]
    cmp x9, #5
    b.ne Lnegative_plan_failure
    mov x0, #199
    b Lnegative_plan_finish
Lnegative_plan_failure:
    mov x0, #-1
Lnegative_plan_finish:
    ldp x29, x30, [sp, #112]
    add sp, sp, #128
    ret

// Independent transport shape: no helper stores at all. ADD exports the
// known caller-frame result address in x0; the caller performs the mutation
// directly, so no later generic call can accidentally mask this omission.
.p2align 2
.globl _$s9PlanAlias16transportAddressAA6PacketVyF
_$s9PlanAlias16transportAddressAA6PacketVyF:
    sub sp, sp, #48
    stp x20, x28, [sp, #16]
    stp x29, x30, [sp, #32]
    mov x28, x8
    bl _negative_may_make_packet
    mov x20, x28
    bl _negative_plan_caller_frame_address
    mov x9, #99
    str x9, [x0, #8]
    ldp x20, x28, [sp, #16]
    ldp x29, x30, [sp, #32]
    add sp, sp, #48
    ret

.p2align 2
.globl _negative_plan_caller_frame_address
_negative_plan_caller_frame_address:
    add x0, sp, #112
    ret

.p2align 2
.globl _negative_plan_transport_oracle
_negative_plan_transport_oracle:
    sub sp, sp, #128
    stp x29, x30, [sp, #112]
    add x8, sp, #64
    bl _$s9PlanAlias16transportAddressAA6PacketVyF
    ldr x9, [sp, #64]
    cmp x9, #1
    b.ne Lnegative_plan_transport_failure
    ldr x9, [sp, #72]
    cmp x9, #99
    b.ne Lnegative_plan_transport_failure
    ldr x9, [sp, #80]
    cmp x9, #3
    b.ne Lnegative_plan_transport_failure
    ldr x9, [sp, #88]
    cmp x9, #4
    b.ne Lnegative_plan_transport_failure
    ldr x9, [sp, #96]
    cmp x9, #5
    b.ne Lnegative_plan_transport_failure
    mov x0, #199
    b Lnegative_plan_transport_finish
Lnegative_plan_transport_failure:
    mov x0, #-1
Lnegative_plan_transport_finish:
    ldp x29, x30, [sp, #112]
    add sp, sp, #128
    ret




// Exact register aliases, including nonstandard outlined inputs.
.globl _complete_body_own_alias
_complete_body_own_alias:
  mov x0, x20
  ret
.globl _complete_body_nonstandard_store
_complete_body_nonstandard_store:
  mov x9, #99
  str x9, [x19, #8]
  ret

.globl _$s9PlanAlias8ownAliasAA6PacketVyF
_$s9PlanAlias8ownAliasAA6PacketVyF:
  sub sp, sp, #48
  stp x20, x28, [sp, #16]
  stp x29, x30, [sp, #32]
  mov x28, x8
  bl _negative_may_make_packet
  mov x20, x28
  bl _complete_body_own_alias
  mov x9, #99
  str x9, [x0, #8]
  ldp x20, x28, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

.globl _$s9PlanAlias16nonstandardAliasAA6PacketVyF
_$s9PlanAlias16nonstandardAliasAA6PacketVyF:
  sub sp, sp, #48
  stp x19, x28, [sp, #16]
  stp x29, x30, [sp, #32]
  mov x28, x8
  bl _negative_may_make_packet
  mov x19, x28
  bl _complete_body_nonstandard_store
  ldp x19, x28, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

// A complete scalar producer leaves the pre-call x0 untouched. Its ABI
// result is all40 bytes through x8; later unproved calls may mutate them.
.globl _$s9PlanAlias15literalProducerAA6PacketVyF
_$s9PlanAlias15literalProducerAA6PacketVyF:
  mov x9, #1
  str x9, [x8, #0]
  mov x9, #2
  str x9, [x8, #8]
  mov x9, #3
  str x9, [x8, #16]
  mov x9, #4
  str x9, [x8, #24]
  mov x9, #5
  str x9, [x8, #32]
  ret
.globl _complete_body_unproved_mutator
_complete_body_unproved_mutator:
  ldr x10, [x0]
  mov x9, #99
  str x9, [x0, #8]
  ret

// The positive frame address is established before the exact producer.
// Neither an x8 alias nor a context-self alias reaches the unproved call.
.globl _$s9PlanAlias13escapeAddressAA6PacketVyF
_$s9PlanAlias13escapeAddressAA6PacketVyF:
  sub sp, sp, #48
  stp x20, x28, [sp, #16]
  stp x29, x30, [sp, #32]
  add x0, sp, #112
  bl _$s9PlanAlias15literalProducerAA6PacketVyF
  mov x8, #0
  bl _complete_body_unproved_mutator
  ldp x20, x28, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

// A private coordinate is not an object extent. Keep the possible reach
// after the explicit argument disappears, across a complete producer.
.globl _$s9PlanAlias14escapedCaptureAA6PacketVyF
_$s9PlanAlias14escapedCaptureAA6PacketVyF:
  sub sp, sp, #48
  stp x20, x28, [sp, #16]
  stp x29, x30, [sp, #32]
  mov x28, x8
  add x0, sp, #8
  bl _complete_body_capture
  mov x8, x28
  mov x0, #0
  bl _$s9PlanAlias15literalProducerAA6PacketVyF
  mov x8, #0
  bl _complete_body_captured_mutator
  ldp x20, x28, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret
.globl _complete_body_capture
_complete_body_capture:
  adrp x9, _complete_body_captured@PAGE
  str x0, [x9, _complete_body_captured@PAGEOFF]
  ret
.globl _complete_body_captured_mutator
_complete_body_captured_mutator:
  adrp x9, _complete_body_captured@PAGE
  ldr x0, [x9, _complete_body_captured@PAGEOFF]
  mov x9, #99
  str x9, [x0, #112]
  ret

.globl _complete_body_own_alias_oracle
_complete_body_own_alias_oracle:
  sub sp, sp, #128
  stp x29, x30, [sp, #112]
  add x8, sp, #64
  bl _$s9PlanAlias8ownAliasAA6PacketVyF
  ldr x9, [sp, #64]
  cmp x9, #1
  b.ne L_complete_body_own_alias_oracle_fail
  ldr x9, [sp, #72]
  cmp x9, #99
  b.ne L_complete_body_own_alias_oracle_fail
  ldr x9, [sp, #80]
  cmp x9, #3
  b.ne L_complete_body_own_alias_oracle_fail
  ldr x9, [sp, #88]
  cmp x9, #4
  b.ne L_complete_body_own_alias_oracle_fail
  ldr x9, [sp, #96]
  cmp x9, #5
  b.ne L_complete_body_own_alias_oracle_fail
  mov x0, #199
  b L_complete_body_own_alias_oracle_end
L_complete_body_own_alias_oracle_fail:
  mov x0, #-1
L_complete_body_own_alias_oracle_end:
  ldp x29, x30, [sp, #112]
  add sp, sp, #128
  ret

.globl _complete_body_nonstandard_oracle
_complete_body_nonstandard_oracle:
  sub sp, sp, #128
  stp x29, x30, [sp, #112]
  add x8, sp, #64
  bl _$s9PlanAlias16nonstandardAliasAA6PacketVyF
  ldr x9, [sp, #64]
  cmp x9, #1
  b.ne L_complete_body_nonstandard_oracle_fail
  ldr x9, [sp, #72]
  cmp x9, #99
  b.ne L_complete_body_nonstandard_oracle_fail
  ldr x9, [sp, #80]
  cmp x9, #3
  b.ne L_complete_body_nonstandard_oracle_fail
  ldr x9, [sp, #88]
  cmp x9, #4
  b.ne L_complete_body_nonstandard_oracle_fail
  ldr x9, [sp, #96]
  cmp x9, #5
  b.ne L_complete_body_nonstandard_oracle_fail
  mov x0, #199
  b L_complete_body_nonstandard_oracle_end
L_complete_body_nonstandard_oracle_fail:
  mov x0, #-1
L_complete_body_nonstandard_oracle_end:
  ldp x29, x30, [sp, #112]
  add sp, sp, #128
  ret

.globl _complete_body_escape_oracle
_complete_body_escape_oracle:
  sub sp, sp, #128
  stp x29, x30, [sp, #112]
  add x8, sp, #64
  bl _$s9PlanAlias13escapeAddressAA6PacketVyF
  ldr x9, [sp, #64]
  cmp x9, #1
  b.ne L_complete_body_escape_oracle_fail
  ldr x9, [sp, #72]
  cmp x9, #99
  b.ne L_complete_body_escape_oracle_fail
  ldr x9, [sp, #80]
  cmp x9, #3
  b.ne L_complete_body_escape_oracle_fail
  ldr x9, [sp, #88]
  cmp x9, #4
  b.ne L_complete_body_escape_oracle_fail
  ldr x9, [sp, #96]
  cmp x9, #5
  b.ne L_complete_body_escape_oracle_fail
  mov x0, #199
  b L_complete_body_escape_oracle_end
L_complete_body_escape_oracle_fail:
  mov x0, #-1
L_complete_body_escape_oracle_end:
  ldp x29, x30, [sp, #112]
  add sp, sp, #128
  ret

.globl _complete_body_captured_oracle
_complete_body_captured_oracle:
  sub sp, sp, #128
  stp x29, x30, [sp, #112]
  add x8, sp, #64
  bl _$s9PlanAlias14escapedCaptureAA6PacketVyF
  ldr x9, [sp, #64]
  cmp x9, #1
  b.ne L_complete_body_captured_oracle_fail
  ldr x9, [sp, #72]
  cmp x9, #99
  b.ne L_complete_body_captured_oracle_fail
  ldr x9, [sp, #80]
  cmp x9, #3
  b.ne L_complete_body_captured_oracle_fail
  ldr x9, [sp, #88]
  cmp x9, #4
  b.ne L_complete_body_captured_oracle_fail
  ldr x9, [sp, #96]
  cmp x9, #5
  b.ne L_complete_body_captured_oracle_fail
  mov x0, #199
  b L_complete_body_captured_oracle_end
L_complete_body_captured_oracle_fail:
  mov x0, #-1
L_complete_body_captured_oracle_end:
  ldp x29, x30, [sp, #112]
  add sp, sp, #128
  ret

.globl _complete_body_swap
_complete_body_swap:
  mov x9, x0
  mov x0, x1
  mov x1, x9
  ret
.globl _complete_body_ordered_stores
_complete_body_ordered_stores:
  mov x9, #11
  str x9, [x0]
  add x0, x0, #8
  mov x9, #13
  str x9, [x0]
  ret
.globl _complete_body_vector_fill
_complete_body_vector_fill:
  mov x9, #9
  dup v0.2d, x9
  stp q0, q0, [x0]
  str x9, [x0, #32]
  ret
.globl _complete_body_partial_fill
_complete_body_partial_fill:
  mov x9, #9
  dup v0.2d, x9
  stp q0, q0, [x8]
  ret

.globl _complete_body_swap_oracle
_complete_body_swap_oracle:
  stp x29, x30, [sp, #-16]!
  mov x0, #7
  mov x1, #11
  bl _complete_body_swap
  cmp x0, #11
  b.ne Lswap_fail
  cmp x1, #7
  b.ne Lswap_fail
  mov x0, #1
  b Lswap_end
Lswap_fail:
  mov x0, #-1
Lswap_end:
  ldp x29, x30, [sp], #16
  ret

.globl _complete_body_order_oracle
_complete_body_order_oracle:
  sub sp, sp, #48
  stp x29, x30, [sp, #32]
  mov x9, #19
  str x9, [sp, #16]
  mov x0, sp
  bl _complete_body_ordered_stores
  mov x9, #17
  str x9, [x0]
  ldr x0, [sp]
  cmp x0, #11
  b.ne Lorder_fail
  ldr x0, [sp, #8]
  cmp x0, #17
  b.ne Lorder_fail
  ldr x0, [sp, #16]
  cmp x0, #19
  b.ne Lorder_fail
  mov x0, #1
  b Lorder_end
Lorder_fail:
  mov x0, #-1
Lorder_end:
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

.globl _complete_body_vector_oracle
_complete_body_vector_oracle:
  sub sp, sp, #64
  stp x29, x30, [sp, #48]
  mov x9, #77
  str x9, [sp, #40]
  mov x0, sp
  bl _complete_body_vector_fill
  ldr x9, [sp, #0]
  cmp x9, #9
  b.ne Lvector_fail
  ldr x9, [sp, #8]
  cmp x9, #9
  b.ne Lvector_fail
  ldr x9, [sp, #16]
  cmp x9, #9
  b.ne Lvector_fail
  ldr x9, [sp, #24]
  cmp x9, #9
  b.ne Lvector_fail
  ldr x9, [sp, #32]
  cmp x9, #9
  b.ne Lvector_fail
  ldr x9, [sp, #40]
  cmp x9, #77
  b.ne Lvector_fail
  mov x0, #45
  b Lvector_end
Lvector_fail:
  mov x0, #-1
Lvector_end:
  ldp x29, x30, [sp, #48]
  add sp, sp, #64
  ret
// This body's memory is complete but x1's value can be absent. Failed
// register substitution must not commit its store prefix or hide x19.
.globl _complete_body_fallback_input
_complete_body_fallback_input:
  mov x9, #99
  str x9, [x19, #8]
  mov x0, x1
  ret
.globl _$s9PlanAlias13fallbackInputAA6PacketVyF
_$s9PlanAlias13fallbackInputAA6PacketVyF:
  sub sp, sp, #48
  stp x19, x28, [sp, #16]
  stp x29, x30, [sp, #32]
  mov x28, x8
  bl _negative_may_make_packet
  mov x19, x28
  mov x8, #0
  bl _complete_body_fallback_input
  ldp x19, x28, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret
.globl _complete_body_fallback_oracle
_complete_body_fallback_oracle:
  sub sp, sp, #128
  stp x29, x30, [sp, #112]
  add x8, sp, #64
  bl _$s9PlanAlias13fallbackInputAA6PacketVyF
  ldr x9, [sp, #64]
  cmp x9, #1
  b.ne Lfallback_fail
  ldr x9, [sp, #72]
  cmp x9, #99
  b.ne Lfallback_fail
  ldr x9, [sp, #80]
  cmp x9, #3
  b.ne Lfallback_fail
  ldr x9, [sp, #88]
  cmp x9, #4
  b.ne Lfallback_fail
  ldr x9, [sp, #96]
  cmp x9, #5
  b.ne Lfallback_fail
  mov x0, #199
  b Lfallback_end
Lfallback_fail:
  mov x0, #-1
Lfallback_end:
  ldp x29, x30, [sp, #112]
  add sp, sp, #128
  ret
.data
.p2align 3
_complete_body_captured:
  .quad 0
.subsections_via_symbols

// A caller-frame coordinate can alias the incoming result buffer.
// Use existing PlanAlias.Packet metadata and ordinary5-field40-byte return ABI.
// Child is intentionally untyped/C-spelled: convention indirect(size:nil), so
// complete transfer records its5 literal stores without logical whole projection.
.text
.p2align 2
.globl _$s9PlanAlias19reciprocalFrameReadAA6PacketVyF
_$s9PlanAlias19reciprocalFrameReadAA6PacketVyF:
  sub sp, sp, #48
  stp x20, x28, [sp, #16]
  stp x29, x30, [sp, #32]
  mov x28, x8
  mov x20, x8
  mov x9, #7
  str x9, [sp, #120]
  bl _complete_body_untyped_packet
  // Actual producer changed result.b/frame(+72) to2. If result-space writes
  // do not invalidate caller-owned frame facts, this reload can claim stale7.
  ldr x10, [sp, #120]
  str x10, [x28, #16]
  ldp x20, x28, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret
.p2align 2
.globl _complete_body_untyped_packet
_complete_body_untyped_packet:
  mov x9, #1
  str x9, [x8, #0]
  mov x9, #2
  str x9, [x8, #8]
  mov x9, #3
  str x9, [x8, #16]
  mov x9, #4
  str x9, [x8, #24]
  mov x9, #5
  str x9, [x8, #32]
  ret
.p2align 2
.globl _complete_body_reciprocal_oracle
_complete_body_reciprocal_oracle:
  sub sp, sp, #128
  stp x29, x30, [sp, #112]
  add x8, sp, #64
  bl _$s9PlanAlias19reciprocalFrameReadAA6PacketVyF
  ldr x9, [sp, #64]
  cmp x9, #1
  b.ne Lreciprocal_fail
  ldr x9, [sp, #72]
  cmp x9, #2
  b.ne Lreciprocal_fail
  ldr x9, [sp, #80]
  cmp x9, #2
  b.ne Lreciprocal_fail
  ldr x9, [sp, #88]
  cmp x9, #4
  b.ne Lreciprocal_fail
  ldr x9, [sp, #96]
  cmp x9, #5
  b.ne Lreciprocal_fail
  mov x0, #122
  b Lreciprocal_end
Lreciprocal_fail:
  mov x0, #-1
Lreciprocal_end:
  ldp x29, x30, [sp, #112]
  add sp, sp, #128
  ret

// A writable global can be the incoming result buffer.
// Link with existing PlanAlias.Packet metadata and negative_may_make_packet.
// The caller chooses writable global storage for its40-byte result. F later
// rediscovers the same address independently, transports it through a complete
// MOV-only body, and mutates through the returned absolute address.
.text
.p2align 2
.globl _$s9PlanAlias18globalAddressAliasAA6PacketVyF
_$s9PlanAlias18globalAddressAliasAA6PacketVyF:
  sub sp, sp, #64
  stp x19, x20, [sp, #16]
  str x28, [sp, #32]
  stp x29, x30, [sp, #48]
  mov x28, x8
  bl _negative_may_make_packet
  mov x20, x28
  adrp x19, _complete_body_global_packet@PAGE
  add x19, x19, _complete_body_global_packet@PAGEOFF
  bl _complete_body_copy_global_address
  mov x9, #99
  str x9, [x0, #8]
  ldp x19, x20, [sp, #16]
  ldr x28, [sp, #32]
  ldp x29, x30, [sp, #48]
  add sp, sp, #64
  ret
.p2align 2
.globl _complete_body_copy_global_address
_complete_body_copy_global_address:
  mov x0, x19
  ret
.p2align 2
.globl _complete_body_global_alias_oracle
_complete_body_global_alias_oracle:
  stp x29, x30, [sp, #-16]!
  adrp x8, _complete_body_global_packet@PAGE
  add x8, x8, _complete_body_global_packet@PAGEOFF
  bl _$s9PlanAlias18globalAddressAliasAA6PacketVyF
  adrp x10, _complete_body_global_packet@PAGE
  add x10, x10, _complete_body_global_packet@PAGEOFF
  ldr x9, [x10, #0]
  cmp x9, #1
  b.ne Lglobal_alias_fail
  ldr x9, [x10, #8]
  cmp x9, #99
  b.ne Lglobal_alias_fail
  ldr x9, [x10, #16]
  cmp x9, #3
  b.ne Lglobal_alias_fail
  ldr x9, [x10, #24]
  cmp x9, #4
  b.ne Lglobal_alias_fail
  ldr x9, [x10, #32]
  cmp x9, #5
  b.ne Lglobal_alias_fail
  mov x0, #199
  b Lglobal_alias_end
Lglobal_alias_fail:
  mov x0, #-1
Lglobal_alias_end:
  ldp x29, x30, [sp], #16
  ret
.data
.p2align 3
.globl _complete_body_global_packet
_complete_body_global_packet:
  .quad 0,0,0,0,0
.subsections_via_symbols

// A copied register keeps the old field bits across an aliased store.
// object/self is x20; x8 points at object.a (checked by Swift oracle).
// Loading b makes x1=selfFieldValue24 in the method analysis. The complete
// leaf writes the same b through result+8, then copies the OLD scalar to x0.
// A following real observer call consumes that scalar before any later call
// can hide the false self.b alias from its call-site snapshot.
.text
.p2align 2
.globl _complete_body_field_copy_invoke
_complete_body_field_copy_invoke:
  stp x20, x30, [sp, #-16]!
  mov x20, x0
  mov x8, x1
  bl _$s9PlanAlias8FieldBoxC9staleCopyAA6PacketVyF
  ldp x20, x30, [sp], #16
  ret
.p2align 2
.globl _$s9PlanAlias8FieldBoxC9staleCopyAA6PacketVyF
_$s9PlanAlias8FieldBoxC9staleCopyAA6PacketVyF:
  stp x20, x30, [sp, #-16]!
  ldr x1, [x20, #24]
  bl _complete_body_mutate_and_copy_field
  bl _complete_body_observe_old_field
  ldp x20, x30, [sp], #16
  ret
.p2align 2
.globl _complete_body_mutate_and_copy_field
_complete_body_mutate_and_copy_field:
  mov x9, #99
  str x9, [x8, #8]
  mov x0, x1
  ret
.subsections_via_symbols

.text
.p2align 2
.globl _complete_body_field_copy_readonly_invoke
_complete_body_field_copy_readonly_invoke:
  stp x20, x30, [sp, #-16]!
  mov x20, x0
  mov x8, x1
  bl _$s9PlanAlias8FieldBoxC12readOnlyCopyAA6PacketVyF
  ldp x20, x30, [sp], #16
  ret
.p2align 2
.globl _$s9PlanAlias8FieldBoxC12readOnlyCopyAA6PacketVyF
_$s9PlanAlias8FieldBoxC12readOnlyCopyAA6PacketVyF:
  stp x20, x30, [sp, #-16]!
  ldr x1, [x20, #24]
  bl _complete_body_copy_field
  bl _complete_body_observe_old_field
  ldp x20, x30, [sp], #16
  ret
.p2align 2
.globl _complete_body_copy_field
_complete_body_copy_field:
  mov x0, x1
  ret
.subsections_via_symbols

// Native async alias and private-frame controls.
// Swift async entry hints and ResumeParent layout match the existing public
// async_memory_effects.s reference. Link into the PlanAlias fixture/module.
// Both leaves initialize own contextslot16=7 and resume through contextslot8.
// Coracles fix native x8=context+8; the result-space child writes x8+8,
// hence contextslot16=99. The disjoint child touches only frame(-24).
.text
.p2align 2
.globl _$s9PlanAlias13asyncOwnWriteSiyYaF
_$s9PlanAlias13asyncOwnWriteSiyYaF:
  sub sp, sp, #32
  str x30, [sp, #16]
  mov x9, #7
  str x9, [x22, #16]
  bl _complete_async_own_store
  ldr x0, [x22, #16]
  ldr x1, [x22, #8]
  ldr x30, [sp, #16]
  add sp, sp, #32
  br x1
.p2align 2
.globl _complete_async_own_store
_complete_async_own_store:
  mov x9, #99
  str x9, [x8, #8]
  ret

.p2align 2
.globl _$s9PlanAlias17asyncPrivateWriteSiyYaF
_$s9PlanAlias17asyncPrivateWriteSiyYaF:
  sub sp, sp, #32
  str x30, [sp, #16]
  mov x9, #7
  str x9, [x22, #16]
  bl _complete_async_private_store
  ldr x0, [x22, #16]
  ldr x1, [x22, #8]
  ldr x30, [sp, #16]
  add sp, sp, #32
  br x1
.p2align 2
.globl _complete_async_private_store
_complete_async_private_store:
  mov x9, #99
  str x9, [sp, #8]
  ret

// Zero-argument C oracles allocate context in the caller's own frame. The
// async leaf's private frame lies below it; every native sp stays16-aligned.
.p2align 2
.globl _complete_body_async_own_oracle
_complete_body_async_own_oracle:
  sub sp, sp, #64
  stp x22, x30, [sp, #48]
  mov x22, sp
  mov x9, #17
  str x9, [x22, #0]
  mov x9, #19
  str x9, [x22, #24]
  adr x9, Lcomplete_async_own_resume
  str x9, [x22, #8]
  add x8, x22, #8
  bl _$s9PlanAlias13asyncOwnWriteSiyYaF
  cmp x0, #99
  b.ne Lcomplete_async_own_fail
  ldr x9, [x22, #16]
  cmp x9, #99
  b.ne Lcomplete_async_own_fail
  ldr x9, [x22, #8]
  adr x10, Lcomplete_async_own_resume
  cmp x9, x10
  b.ne Lcomplete_async_own_fail
  ldr x9, [x22, #0]
  cmp x9, #17
  b.ne Lcomplete_async_own_fail
  ldr x9, [x22, #24]
  cmp x9, #19
  b.ne Lcomplete_async_own_fail
  mov x0, #99
  b Lcomplete_async_own_end
Lcomplete_async_own_fail:
  mov x0, #-1
Lcomplete_async_own_end:
  ldp x22, x30, [sp, #48]
  add sp, sp, #64
  ret
Lcomplete_async_own_resume:
  ret

.p2align 2
.globl _complete_body_async_private_oracle
_complete_body_async_private_oracle:
  sub sp, sp, #64
  stp x22, x30, [sp, #48]
  mov x22, sp
  mov x9, #17
  str x9, [x22, #0]
  mov x9, #19
  str x9, [x22, #24]
  adr x9, Lcomplete_async_private_resume
  str x9, [x22, #8]
  add x8, x22, #8
  bl _$s9PlanAlias17asyncPrivateWriteSiyYaF
  cmp x0, #7
  b.ne Lcomplete_async_private_fail
  ldr x9, [x22, #16]
  cmp x9, #7
  b.ne Lcomplete_async_private_fail
  ldr x9, [x22, #8]
  adr x10, Lcomplete_async_private_resume
  cmp x9, x10
  b.ne Lcomplete_async_private_fail
  ldr x9, [x22, #0]
  cmp x9, #17
  b.ne Lcomplete_async_private_fail
  ldr x9, [x22, #24]
  cmp x9, #19
  b.ne Lcomplete_async_private_fail
  mov x0, #7
  b Lcomplete_async_private_end
Lcomplete_async_private_fail:
  mov x0, #-1
Lcomplete_async_private_end:
  ldp x22, x30, [sp, #48]
  add sp, sp, #64
  ret
Lcomplete_async_private_resume:
  ret

.section __TEXT,__swift_as_entry,regular,no_dead_strip
.p2align 2
.long _$s9PlanAlias13asyncOwnWriteSiyYaF-.
.long _$s9PlanAlias17asyncPrivateWriteSiyYaF-.
.subsections_via_symbols

// A fixed-ABI memory helper can overwrite a caller-owned result through sp.
// Link with the existing unchanged negative_may_make_packet Swift maker and
// Packet40 metadata. This uses the EXTERNAL fixed-ABI libSystem memset.
// No own-result alias is placed inx20 or an ordinary argument register.
.text
.p2align 2
.globl _$s9PlanAlias17memsetCallerStoreAA6PacketVyF
_$s9PlanAlias17memsetCallerStoreAA6PacketVyF:
  sub sp, sp, #48
  str x28, [sp, #16]
  stp x29, x30, [sp, #32]
  mov x28, x8
  bl _negative_may_make_packet
  // Fixed oracle result is entrySP+64. At this point sp=entrySP-48,
  // so sp+120 is entrySP+72, exactly result.b.
  add x0, sp, #120
  mov x1, #0
  mov x2, #8
  mov x8, #0
  bl _memset
  ldr x28, [sp, #16]
  ldp x29, x30, [sp, #32]
  add sp, sp, #48
  ret

.p2align 2
.globl _complete_body_memset_caller_oracle
_complete_body_memset_caller_oracle:
  sub sp, sp, #128
  stp x29, x30, [sp, #112]
  mov x9, #17
  str x9, [sp, #56]
  mov x9, #19
  str x9, [sp, #104]
  add x8, sp, #64
  bl _$s9PlanAlias17memsetCallerStoreAA6PacketVyF
  ldr x9, [sp, #64]
  cmp x9, #1
  b.ne Lmemset_caller_fail
  ldr x9, [sp, #72]
  cmp x9, #0
  b.ne Lmemset_caller_fail
  ldr x9, [sp, #80]
  cmp x9, #3
  b.ne Lmemset_caller_fail
  ldr x9, [sp, #88]
  cmp x9, #4
  b.ne Lmemset_caller_fail
  ldr x9, [sp, #96]
  cmp x9, #5
  b.ne Lmemset_caller_fail
  ldr x9, [sp, #56]
  cmp x9, #17
  b.ne Lmemset_caller_fail
  ldr x9, [sp, #104]
  cmp x9, #19
  b.ne Lmemset_caller_fail
  mov x0, #100
  b Lmemset_caller_end
Lmemset_caller_fail:
  mov x0, #-1
Lmemset_caller_end:
  ldp x29, x30, [sp, #112]
  add sp, sp, #128
  ret
.subsections_via_symbols

// Q stores carry raw bits across narrow vector reloads.
.text
.p2align 2
.globl _$s9PlanAlias11qNarrowReads6UInt32VyF
_$s9PlanAlias11qNarrowReads6UInt32VyF:
  sub sp, sp, #80
  str x30, [sp, #64]
  mov x9, #123
  str x9, [sp]
  mov x0, sp
  bl _complete_body_vector_fill
  ldr s0, [sp]
  fmov w0, s0
  ldr x30, [sp, #64]
  add sp, sp, #80
  ret

// Zero-argument C oracle. The Swift UInt32 ABI result isw0; return9 inx0
// only after observing the CPU's actual low32 raw bits from the q-store.
.p2align 2
.globl _complete_body_q_narrow_oracle
_complete_body_q_narrow_oracle:
  stp x29, x30, [sp, #-16]!
  bl _$s9PlanAlias11qNarrowReads6UInt32VyF
  cmp w0, #9
  b.ne Lq_narrow_fail
  mov x0, #9
  b Lq_narrow_end
Lq_narrow_fail:
  mov x0, #-1
Lq_narrow_end:
  ldp x29, x30, [sp], #16
  ret
.subsections_via_symbols

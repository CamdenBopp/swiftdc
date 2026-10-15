// Authored Swift async ABI leaves. Unknown callees can change slot16 through
// an incoming pointer or a previously exported global context pointer. A
// body-proven NOP/RET callee cannot. Already-loaded register snapshots survive.
.text
.p2align 2
.globl _$s10AsyncCalls12incomingLeafyS2iYaF
_$s10AsyncCalls12incomingLeafyS2iYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 bl _async_calls_mutate_input
 ldr x0,[x22,#16]
 bl _$s10AsyncCalls7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
.globl _$s10AsyncCalls10globalLeafSiyYaF
_$s10AsyncCalls10globalLeafSiyYaF:
 str x30,[sp,#-16]!
 adrp x9,_async_calls_exported_context@PAGE
 str x22,[x9,_async_calls_exported_context@PAGEOFF]
 mov x8,#7
 str x8,[x22,#16]
 mov x0,xzr
 bl _async_calls_mutate_global
 ldr x0,[x22,#16]
 bl _$s10AsyncCalls7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
.globl _$s10AsyncCalls12readonlyLeafSiyYaF
_$s10AsyncCalls12readonlyLeafSiyYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 bl _async_calls_no_write
 ldr x0,[x22,#16]
 bl _$s10AsyncCalls7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
.globl _$s10AsyncCalls12snapshotLeafSiyYaF
_$s10AsyncCalls12snapshotLeafSiyYaF:
 stp x19,x30,[sp,#-16]!
 adrp x9,_async_calls_exported_context@PAGE
 str x22,[x9,_async_calls_exported_context@PAGEOFF]
 mov x8,#7
 str x8,[x22,#16]
 ldr x19,[x22,#16]
 mov x0,xzr
 bl _async_calls_mutate_global
 mov x0,x19
 bl _$s10AsyncCalls7observeyS2iF
 ldr x1,[x22,#8]
 ldp x19,x30,[sp],#16
 br x1
.globl _$s10AsyncCalls15conditionalLeafyS2iYaF
_$s10AsyncCalls15conditionalLeafyS2iYaF:
 str x30,[sp,#-16]!
 adrp x9,_async_calls_exported_context@PAGE
 str x22,[x9,_async_calls_exported_context@PAGEOFF]
 mov x8,#7
 str x8,[x22,#16]
 cbz x0,1f
 mov x0,xzr
 bl _async_calls_mutate_global
1:
 ldr x0,[x22,#16]
 bl _$s10AsyncCalls7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
// A callee can use the implicit callee-saved context register without any
// outgoing pointer argument. Preserving x22 does not preserve its pointee.
.globl _$s10AsyncCalls12implicitLeafSiyYaF
_$s10AsyncCalls12implicitLeafSiyYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 mov x0,xzr
 bl _async_calls_mutate_implicit
 ldr x0,[x22,#16]
 bl _$s10AsyncCalls7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
// A pointer into the leaf's own context (slot 16) goes to a call that writes
// 11 there; the context header below it (ResumeParent at 8) is out of reach.
.globl _$s10AsyncCalls12interiorLeafSiyYaF
_$s10AsyncCalls12interiorLeafSiyYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 add x0,x22,#16
 bl _async_calls_mutate_input
 ldr x0,[x22,#16]
 bl _$s10AsyncCalls7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
// The context leaves bit-reversed (a transform the tracer does not model)
// through a global; the call reverses it and writes slot 16.
.globl _$s10AsyncCalls8rbitLeafSiyYaF
_$s10AsyncCalls8rbitLeafSiyYaF:
 str x30,[sp,#-16]!
 rbit x9,x22
 adrp x10,_async_calls_exported_context@PAGE
 str x9,[x10,_async_calls_exported_context@PAGEOFF]
 mov x9,#0
 mov x8,#7
 str x8,[x22,#16]
 bl _async_calls_mutate_reversed
 ldr x0,[x22,#16]
 bl _$s10AsyncCalls7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
// The context reaches a join on one path only, as a register no condition
// selects; the survivor goes to a call that writes slot 16 through it.
.globl _$s10AsyncCalls8joinLeafyS2iYaF
_$s10AsyncCalls8joinLeafyS2iYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 ldr x11,[x0]
 mov x10,x22
 cbz x11,1f
 adrp x10,_async_calls_dummy_context@PAGE
 add x10,x10,_async_calls_dummy_context@PAGEOFF
1:
 mov x0,x10
 bl _async_calls_mutate_plus16
 ldr x0,[x22,#16]
 bl _$s10AsyncCalls7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
// Control: the prologue saves x22 above a local whose address escapes to a
// call that fills the local's 16 bytes. The save area belongs to no local.
.globl _$s10AsyncCalls12saveAreaLeafSiyYaF
_$s10AsyncCalls12saveAreaLeafSiyYaF:
 sub sp,sp,#48
 stp x29,x30,[sp,#32]
 str x22,[sp,#24]
 mov x8,#7
 str x8,[x22,#16]
 mov x0,sp
 bl _async_calls_fill_local
 ldr x0,[x22,#16]
 bl _$s10AsyncCalls7observeyS2iF
 ldr x1,[x22,#8]
 ldp x29,x30,[sp,#32]
 add sp,sp,#48
 br x1
// Control: the prologue's saves of x19 and x22 sit at sp and sp+8 when a
// call to a C function of unknown arity is made; they are not its stack
// arguments.
.globl _$s10AsyncCalls11saveRunLeafSiyYaF
_$s10AsyncCalls11saveRunLeafSiyYaF:
 str x19,[sp,#-32]!
 stp x29,x30,[sp,#16]
 str x22,[sp,#8]
 mov x8,#7
 str x8,[x22,#16]
 mov x0,#3
 bl _async_calls_no_write
 ldr x0,[x22,#16]
 bl _$s10AsyncCalls7observeyS2iF
 ldr x1,[x22,#8]
 ldp x29,x30,[sp,#16]
 ldr x19,[sp],#32
 br x1
// Control: a call on one branch clears the outgoing copy of the saved
// context; the other branch keeps it. The join loses a copy, not a value.
.globl _$s10AsyncCalls14branchCallLeafyS2iYaF
_$s10AsyncCalls14branchCallLeafyS2iYaF:
 sub sp,sp,#32
 stp x29,x30,[sp,#16]
 str x22,[sp,#8]
 mov x8,#7
 str x8,[x22,#16]
 cbz x0,1f
 bl _async_calls_no_write
1:
 bl _async_calls_no_write
 ldr x0,[x22,#16]
 bl _$s10AsyncCalls7observeyS2iF
 ldr x1,[x22,#8]
 ldp x29,x30,[sp,#16]
 add sp,sp,#32
 br x1
.globl _async_calls_fill_local
_async_calls_fill_local:
 mov x8,#11
 stp x8,x8,[x0]
 ret
.globl _async_calls_mutate_reversed
_async_calls_mutate_reversed:
 adrp x9,_async_calls_exported_context@PAGE
 ldr x9,[x9,_async_calls_exported_context@PAGEOFF]
 rbit x9,x9
 mov x8,#11
 str x8,[x9,#16]
 ret
.globl _async_calls_mutate_plus16
_async_calls_mutate_plus16:
 mov x8,#11
 str x8,[x0,#16]
 ret
.globl _async_calls_mutate_input
_async_calls_mutate_input:
 mov x8,#11
 str x8,[x0]
 ret
.globl _async_calls_mutate_global
_async_calls_mutate_global:
 adrp x9,_async_calls_exported_context@PAGE
 ldr x9,[x9,_async_calls_exported_context@PAGEOFF]
 mov x8,#11
 str x8,[x9,#16]
 ret
.globl _async_calls_mutate_implicit
_async_calls_mutate_implicit:
 mov x8,#11
 str x8,[x22,#16]
 ret
.globl _async_calls_no_write
_async_calls_no_write:
 nop
 ret
.globl _$s10AsyncCalls7observeyS2iF
_$s10AsyncCalls7observeyS2iF:
 ret
.macro adapter name, leaf, mode
.globl _async_calls_\name
_async_calls_\name:
 stp x22,x30,[sp,#-16]!
 mov x22,x0
 adr x8,_async_calls_callback
 str x8,[x22,#8]
 .if \mode == 1
 add x0,x22,#16
 .elseif \mode == 2
 mov x0,x1
 .endif
 bl \leaf
 ldp x22,x30,[sp],#16
 ret
.endm
adapter incoming, _$s10AsyncCalls12incomingLeafyS2iYaF, 1
adapter global, _$s10AsyncCalls10globalLeafSiyYaF, 0
adapter implicit, _$s10AsyncCalls12implicitLeafSiyYaF, 0
adapter readonly, _$s10AsyncCalls12readonlyLeafSiyYaF, 0
adapter snapshot, _$s10AsyncCalls12snapshotLeafSiyYaF, 0
adapter conditional, _$s10AsyncCalls15conditionalLeafyS2iYaF, 2
adapter interior, _$s10AsyncCalls12interiorLeafSiyYaF, 0
adapter rbit, _$s10AsyncCalls8rbitLeafSiyYaF, 0
adapter join, _$s10AsyncCalls8joinLeafyS2iYaF, 2
adapter savearea, _$s10AsyncCalls12saveAreaLeafSiyYaF, 0
adapter saverun, _$s10AsyncCalls11saveRunLeafSiyYaF, 0
adapter branchcall, _$s10AsyncCalls14branchCallLeafyS2iYaF, 2
_async_calls_callback:
 ret
.data
.p2align 3
_async_calls_exported_context:
 .quad 0
_async_calls_dummy_context:
 .quad 0, 0, 0, 0
.section __TEXT,__swift_as_entry,regular,no_dead_strip
.p2align 2
.long _$s10AsyncCalls12incomingLeafyS2iYaF-.
.long _$s10AsyncCalls10globalLeafSiyYaF-.
.long _$s10AsyncCalls12readonlyLeafSiyYaF-.
.long _$s10AsyncCalls12snapshotLeafSiyYaF-.
.long _$s10AsyncCalls15conditionalLeafyS2iYaF-.

.long _$s10AsyncCalls12implicitLeafSiyYaF-.
.long _$s10AsyncCalls12interiorLeafSiyYaF-.
.long _$s10AsyncCalls8rbitLeafSiyYaF-.
.long _$s10AsyncCalls8joinLeafyS2iYaF-.
.long _$s10AsyncCalls12saveAreaLeafSiyYaF-.
.long _$s10AsyncCalls11saveRunLeafSiyYaF-.
.long _$s10AsyncCalls14branchCallLeafyS2iYaF-.

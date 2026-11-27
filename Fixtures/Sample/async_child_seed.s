// Authored async ABI chains: what a resume funclet may assume of a context
// slot its entry funclet stored before suspending.
//
// `followed` stores 7 to slot 16 and awaits `parentWrite`, which follows the
// Parent word of its own context back to the caller's and stores 11 to slot
// 16. The resume funclet passes slot 16 to `observe` and returns it: natively
// 11, never the entry's 7.
// `disjoint` awaits `ownWrite`, which stores 11 to its own slot 16: the
// resume funclet observes 7. Nothing in either parent tells the two children
// apart, so neither resume has a proved value for the slot.
// `hopped` suspends through swift_task_switch, which runs nothing else on
// the task: its continuation's slot 16 is the entry's 7.
//
// Neither parent stores or copies its context itself: the child's header is
// filled by the two-instruction leaf -Osize outlines (`stp x22, x8, [x0];
// mov x22, x0; ret`), so the Parent link is the only route to the caller's
// context. The child context comes from an allocator defined here under the
// runtime's name, which lets the chains run without a task.
.text
.p2align 2
.globl _$s14AsyncChildSeed8followedSiyYaF
_$s14AsyncChildSeed8followedSiyYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 mov x0,#32
 bl _swift_task_alloc
 adrp x8,_$s14AsyncChildSeed8followedSiyYaFTQ0_@PAGE
 add x8,x8,_$s14AsyncChildSeed8followedSiyYaFTQ0_@PAGEOFF
 bl _async_child_seed_header
 ldr x30,[sp],#16
 b _$s14AsyncChildSeed11parentWriteSiyYaF
.p2align 2
.globl _$s14AsyncChildSeed8followedSiyYaFTQ0_
_$s14AsyncChildSeed8followedSiyYaFTQ0_:
 str x30,[sp,#-16]!
 ldr x22,[x22]
 ldr x0,[x22,#16]
 bl _$s14AsyncChildSeed7observeyS2iF
 ldr x30,[sp],#16
 ldr x1,[x22,#8]
 br x1
// The awaited child: x22 is its own context, whose first word is the caller's.
.p2align 2
.globl _$s14AsyncChildSeed11parentWriteSiyYaF
_$s14AsyncChildSeed11parentWriteSiyYaF:
 ldr x9,[x22]
 mov x10,#11
 str x10,[x9,#16]
 ldr x1,[x22,#8]
 br x1

.p2align 2
.globl _$s14AsyncChildSeed8disjointSiyYaF
_$s14AsyncChildSeed8disjointSiyYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 mov x0,#40
 bl _swift_task_alloc
 adrp x8,_$s14AsyncChildSeed8disjointSiyYaFTQ0_@PAGE
 add x8,x8,_$s14AsyncChildSeed8disjointSiyYaFTQ0_@PAGEOFF
 bl _async_child_seed_header
 ldr x30,[sp],#16
 b _$s14AsyncChildSeed8ownWriteSiyYaF
.p2align 2
.globl _$s14AsyncChildSeed8disjointSiyYaFTQ0_
_$s14AsyncChildSeed8disjointSiyYaFTQ0_:
 str x30,[sp,#-16]!
 ldr x22,[x22]
 ldr x0,[x22,#16]
 bl _$s14AsyncChildSeed7observeyS2iF
 ldr x30,[sp],#16
 ldr x1,[x22,#8]
 br x1
.p2align 2
.globl _$s14AsyncChildSeed8ownWriteSiyYaF
_$s14AsyncChildSeed8ownWriteSiyYaF:
 mov x10,#11
 str x10,[x22,#16]
 ldr x1,[x22,#8]
 br x1

// Control: an executor hop. Rendered only; it needs a task to run.
.p2align 2
.globl _$s14AsyncChildSeed6hoppedSiyYaF
_$s14AsyncChildSeed6hoppedSiyYaF:
 mov x8,#7
 str x8,[x22,#16]
 adrp x0,_$s14AsyncChildSeed6hoppedSiyYaFTY0_@PAGE
 add x0,x0,_$s14AsyncChildSeed6hoppedSiyYaFTY0_@PAGEOFF
 mov x1,#0
 mov x2,#0
 b _swift_task_switch
.p2align 2
.globl _$s14AsyncChildSeed6hoppedSiyYaFTY0_
_$s14AsyncChildSeed6hoppedSiyYaFTY0_:
 str x30,[sp,#-16]!
 ldr x0,[x22,#16]
 bl _$s14AsyncChildSeed7observeyS2iF
 ldr x30,[sp],#16
 ldr x1,[x22,#8]
 br x1

// The value each resume funclet read from slot 16, passed through.
.p2align 2
.globl _$s14AsyncChildSeed7observeyS2iF
_$s14AsyncChildSeed7observeyS2iF:
 ret

// Parent and ResumeParent of a new context, then the context into x22.
.p2align 2
.globl _async_child_seed_header
_async_child_seed_header:
 stp x22,x8,[x0]
 mov x22,x0
 ret
// One child context at a time, from static storage.
.p2align 2
.globl _swift_task_alloc
_swift_task_alloc:
 adrp x9,_async_child_seed_arena@PAGE
 add x0,x9,_async_child_seed_arena@PAGEOFF
 ret

// C ABI adapters: x0 is the caller's context (at least 24 bytes). They
// install a ResumeParent that returns to them and enter the chain.
.p2align 2
.globl _async_child_seed_run_followed
_async_child_seed_run_followed:
 stp x22,x30,[sp,#-16]!
 mov x22,x0
 adr x8,_async_child_seed_callback
 str x8,[x22,#8]
 bl _$s14AsyncChildSeed8followedSiyYaF
 ldp x22,x30,[sp],#16
 ret
.p2align 2
.globl _async_child_seed_run_disjoint
_async_child_seed_run_disjoint:
 stp x22,x30,[sp,#-16]!
 mov x22,x0
 adr x8,_async_child_seed_callback
 str x8,[x22,#8]
 bl _$s14AsyncChildSeed8disjointSiyYaF
 nop
 ldp x22,x30,[sp],#16
 ret
_async_child_seed_callback:
 ret

.section __TEXT,__swift_as_entry,regular,no_dead_strip
.p2align 2
.long _$s14AsyncChildSeed8followedSiyYaF-.
.long _$s14AsyncChildSeed11parentWriteSiyYaF-.
.long _$s14AsyncChildSeed8disjointSiyYaF-.
.long _$s14AsyncChildSeed8ownWriteSiyYaF-.
.long _$s14AsyncChildSeed6hoppedSiyYaF-.
.section __TEXT,__swift_as_ret,regular,no_dead_strip
.p2align 2
.long _$s14AsyncChildSeed8followedSiyYaFTQ0_-.
.long _$s14AsyncChildSeed8disjointSiyYaFTQ0_-.
.section __TEXT,__swift_as_cont,regular,no_dead_strip
.p2align 2
.long _$s14AsyncChildSeed6hoppedSiyYaFTY0_-.

.section __DATA,__bss
.p2align 4
_async_child_seed_arena:
 .space 64

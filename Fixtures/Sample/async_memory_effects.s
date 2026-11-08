// Authored async ABI leaf: the incoming address may alias own-context slot16.
// ResumeParent and hint format match compiler-generated suspension-free leaves.
.text
.p2align 2
.globl _$s14AsyncMemoryABI16pointerStoreLeafyS2iYaF
_$s14AsyncMemoryABI16pointerStoreLeafyS2iYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 mov x8,#11
 str x8,[x0]
 ldr x0,[x22,#16]
 bl _$s14AsyncMemoryABI7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
.globl _$s14AsyncMemoryABI7observeyS2iF
_$s14AsyncMemoryABI7observeyS2iF:
 ret
.globl _async_memory_pointer
_async_memory_pointer:
 stp x22,x30,[sp,#-16]!
 mov x22,x0
 adr x8,_async_memory_callback
 str x8,[x22,#8]
 add x0,x22,#16
 bl _$s14AsyncMemoryABI16pointerStoreLeafyS2iYaF
 ldp x22,x30,[sp],#16
 ret
_async_memory_callback:
 ret
.section __TEXT,__swift_as_entry,regular,no_dead_strip
.p2align 2
.long _$s14AsyncMemoryABI16pointerStoreLeafyS2iYaF-.
// Independent C ABI execution of the context memory instruction sequences.
// Preserve x22 and return the CPU's raw integer result to the native harness.
.text
.p2align 2
.globl _async_memory_pair
_async_memory_pair:
 stp x22,x30,[sp,#-16]!
 mov x22,x0
 mov x9,#13
 mov x10,#17
 stp x9,x10,[x22,#16]
 ldp x0,x1,[x22,#16]
 add x0,x0,x1
 ldp x22,x30,[sp],#16
 ret
.globl _async_memory_unaligned
_async_memory_unaligned:
 stp x22,x30,[sp,#-16]!
 mov x22,x0
 mov x9,#7
 mov w10,#1
 stur x9,[x22,#20]
 str w10,[x22,#24]
 ldur x0,[x22,#20]
 ldp x22,x30,[sp],#16
 ret
.globl _async_memory_simd
_async_memory_simd:
 stp x22,x30,[sp,#-16]!
 mov x22,x0
 fmov d0,#1.0
 str d0,[x22,#16]
 ldr x0,[x22,#16]
 ldp x22,x30,[sp],#16
 ret
// ST4 writes 64 bytes. Its unknown-width classification must not default to
// eight: entrySP-8 through entrySP+56 reaches caller-owned context slot16.
.text
.p2align 2
.globl _async_memory_st4
_async_memory_st4:
 sub sp,sp,#128
 stp x22,x30,[sp,#104]
 add x22,sp,#32
 mov x9,#7
 str x9,[x22,#16]
 movi v0.16b,#0x11
 movi v1.16b,#0x22
 movi v2.16b,#0x33
 movi v3.16b,#0x44
 bl _async_memory_st4_fragment
 ldr x0,[x22,#16]
 ldp x22,x30,[sp,#104]
 add sp,sp,#128
 ret
.globl _async_memory_st4_fragment
_async_memory_st4_fragment:
 sub sp,sp,#16
 add x0,sp,#8
 st4 {v0.2d-v3.2d},[x0]
 add sp,sp,#16
 ret

// Controlled C ABI prefixes: context-relative offsets can reach the other
// identity without independently known allocation bounds. Native execution
// corroborates memory aliasing; synthetic tests supply the funclet entry seam.
.text
.p2align 2
.globl _async_memory_cross_child
_async_memory_cross_child:
 stp x19,x22,[sp,#-32]!
 str x30,[sp,#16]
 mov x22,x0
 mov x8,#11
 str x8,[x22,#32]
 ldr x19,[x22]
 ldr x0,[x19,#16]
 ldr x30,[sp,#16]
 ldp x19,x22,[sp],#32
 ret
.globl _async_memory_cross_parent
_async_memory_cross_parent:
 stp x19,x20,[sp,#-32]!
 stp x22,x30,[sp,#16]
 mov x22,x0
 ldr x19,[x22]
 stur x1,[x19,#-16]
 ldr x20,[x22]
 ldr x0,[x20,#16]
 ldp x22,x30,[sp,#16]
 ldp x19,x20,[sp],#32
 ret

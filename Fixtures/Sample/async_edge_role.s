// Authored Swift async ABI bodies: what a call hands its callee in x22 when
// the callee has no body in this image. A callee whose own signature is
// `async` takes its context there (`swiftasync`) and may write the storage
// x22 points at. Any other callee receives x22 as callee-saved state.
// The imports are in async_edge_role_provider.s.
.text
.p2align 2
// directLeaf() async -> Int. Stores 7 to slot 16 of its own context, calls
// the imported `endpoint() async`, which stores 11 to slot 16 of the context
// in x22, and observes the slot: 11.
.globl _$s9AsyncEdge10directLeafSiyYaF
_$s9AsyncEdge10directLeafSiyYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 mov x0,xzr
 bl _$s9AsyncEdge8endpointyyYaF
 ldr x0,[x22,#16]
 bl _$s9AsyncEdge7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
// closureLeaf() async -> Int. The same body around the imported synchronous
// `plain(() async -> ()) -> Int`, whose only `async` is its parameter's type.
// It writes no memory: 7.
.globl _$s9AsyncEdge11closureLeafSiyYaF
_$s9AsyncEdge11closureLeafSiyYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 mov x0,xzr
 mov x1,xzr
 bl _$s9AsyncEdge5plainySiyyYaXEF
 ldr x0,[x22,#16]
 bl _$s9AsyncEdge7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
// untypedLeaf() async -> Int. The same body around an imported C function
// with no signature. It writes no memory: 7.
.globl _$s9AsyncEdge11untypedLeafSiyYaF
_$s9AsyncEdge11untypedLeafSiyYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 mov x0,xzr
 bl _async_edge_role_c_import
 ldr x0,[x22,#16]
 bl _$s9AsyncEdge7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
// quietLeaf() async -> Int. The same body around `quiet() async`, whose whole
// body is in this image and never reads x22: 7.
.globl _$s9AsyncEdge9quietLeafSiyYaF
_$s9AsyncEdge9quietLeafSiyYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 mov x0,xzr
 bl _$s9AsyncEdge5quietyyYaF
 ldr x0,[x22,#16]
 bl _$s9AsyncEdge7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
// frameLeaf() -> Int. A synchronous veneer whose context is its own frame:
// x22 = sp, 7 at [sp, #16], then `endpoint() async` stores 11 to slot 16 of
// that context, which is the same word: 11.
.globl _$s9AsyncEdge9frameLeafSiyF
_$s9AsyncEdge9frameLeafSiyF:
 sub sp,sp,#64
 stp x22,x30,[sp,#48]
 mov x22,sp
 mov x8,#7
 str x8,[sp,#16]
 mov x0,xzr
 bl _$s9AsyncEdge8endpointyyYaF
 ldr x0,[sp,#16]
 bl _$s9AsyncEdge7observeyS2iF
 ldp x22,x30,[sp,#48]
 add sp,sp,#64
 ret
// frameControl() -> Int. x22 holds sp across a call to the synchronous
// `plain(() async -> ()) -> Int`, as it does around a dynamic allocation.
// The callee does not take x22 and writes no memory: 7.
.globl _$s9AsyncEdge12frameControlSiyF
_$s9AsyncEdge12frameControlSiyF:
 sub sp,sp,#64
 stp x22,x30,[sp,#48]
 mov x22,sp
 mov x8,#7
 str x8,[sp,#16]
 mov x0,xzr
 mov x1,xzr
 bl _$s9AsyncEdge5plainySiyyYaXEF
 ldr x0,[sp,#16]
 bl _$s9AsyncEdge7observeyS2iF
 ldp x22,x30,[sp,#48]
 add sp,sp,#64
 ret
// quiet() async. Reads and writes nothing.
.globl _$s9AsyncEdge5quietyyYaF
_$s9AsyncEdge5quietyyYaF:
 nop
 ret
// observe(Int) -> Int. Returns its argument.
.globl _$s9AsyncEdge7observeyS2iF
_$s9AsyncEdge7observeyS2iF:
 ret
// C entry points for the native oracle. Each runs one leaf on the context
// in x0, with a ResumeParent that returns to the leaf's caller, and returns
// what the leaf observed.
.macro adapter name, leaf
.globl _async_edge_role_\name
_async_edge_role_\name:
 stp x22,x30,[sp,#-16]!
 mov x22,x0
 adr x8,_async_edge_role_callback
 str x8,[x22,#8]
 bl \leaf
 ldp x22,x30,[sp],#16
 ret
.endm
adapter direct, _$s9AsyncEdge10directLeafSiyYaF
adapter closure, _$s9AsyncEdge11closureLeafSiyYaF
adapter untyped, _$s9AsyncEdge11untypedLeafSiyYaF
adapter quiet, _$s9AsyncEdge9quietLeafSiyYaF
_async_edge_role_callback:
 ret
.section __TEXT,__swift_as_entry,regular,no_dead_strip
.p2align 2
.long _$s9AsyncEdge10directLeafSiyYaF-.
.long _$s9AsyncEdge11closureLeafSiyYaF-.
.long _$s9AsyncEdge11untypedLeafSiyYaF-.
.long _$s9AsyncEdge9quietLeafSiyYaF-.

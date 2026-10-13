// Authored ARM64 oracles: an own-context slot starts at 7.
// A pointer spill/reload permits a call to change it to 18; an overlapping
// byte write changes it to 263. Wrappers preserve the C ABI for native calls.
.text
.globl _async_alias_spill
_async_alias_spill:
 stp x19,x20,[sp,#-48]!
 stp x22,x30,[sp,#16]
 mov x22,x0
 ldr x19,[x22]
 str x19,[sp,#32]
 ldr x20,[sp,#32]
 add x0,x20,#16
 bl _async_alias_mutate
 ldr x0,[x20,#16]
 ldp x22,x30,[sp,#16]
 ldp x19,x20,[sp],#48
 ret
_async_alias_mutate:
 ldr x8,[x0]
 add x8,x8,#11
 str x8,[x0]
 ret
.globl _async_alias_byte
_async_alias_byte:
 str x19,[sp,#-16]!
 ldr x19,[x0]
 mov w8,#1
 strb w8,[x19,#17]
 ldr x0,[x19,#16]
 ldr x19,[sp],#16
 ret
// An interior pointer has no proven write footprint: the callee writes -8.
.globl _async_alias_interior
_async_alias_interior:
 stp x19,x30,[sp,#-16]!
 ldr x19,[x0]
 add x0,x19,#24
 bl _async_alias_mutate_before
 ldr x0,[x19,#16]
 ldp x19,x30,[sp],#16
 ret
_async_alias_mutate_before:
 ldur x8,[x0,#-8]
 add x8,x8,#11
 stur x8,[x0,#-8]
 ret
.globl _async_alias_unaligned
_async_alias_unaligned:
 str x19,[sp,#-16]!
 ldr x19,[x0]
 mov x8,#1
 stur x8,[x19,#17]
 ldr x0,[x19,#16]
 ldr x19,[sp],#16
 ret
// Register-bank copies preserve pointer bits; so do floating-register loads.
.globl _async_alias_fmov
_async_alias_fmov:
 stp x19,x20,[sp,#-32]!
 str x30,[sp,#16]
 ldr x19,[x0]
 fmov d0,x19
 fmov x20,d0
 add x0,x20,#16
 bl _async_alias_mutate
 ldr x0,[x20,#16]
 ldr x30,[sp,#16]
 ldp x19,x20,[sp],#32
 ret
.globl _async_alias_vector_load
_async_alias_vector_load:
 stp x19,x20,[sp,#-32]!
 str x30,[sp,#16]
 ldr d0,[x0]
 fmov x20,d0
 add x0,x20,#16
 bl _async_alias_mutate
 ldr x0,[x20,#16]
 ldr x30,[sp,#16]
 ldp x19,x20,[sp],#32
 ret

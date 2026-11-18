// C's getpid preserves x21. Arming it with zero and returning the comparison
// supplies a positive control for an independently established C ABI.
.text
.p2align 2
.globl _system_error_arm
_system_error_arm:
    stp x21, x30, [sp, #-16]!
    mov x21, #0
    bl _getpid
    cmp x21, #0
    cset w0, eq
    ldp x21, x30, [sp], #16
    ret

// An immutable GOT entry supplies the same C contract through BLR. The first
// trace sees an unnamed call; resolving its ABI must replay that trace.
.p2align 2
.globl _system_error_indirect_arm
_system_error_indirect_arm:
    stp x21, x30, [sp, #-16]!
    mov x21, #0
    adrp x16, _getpid@GOTPAGE
    ldr x16, [x16, _getpid@GOTPAGEOFF]
    blr x16
    cmp x21, #0
    cset w0, eq
    ldp x21, x30, [sp], #16
    ret

// These helpers have no ABI name contract. One local body calls the real
// system getpid; the other is a return reached through two immutable pointer loads.
// Their bodies and every outgoing call must preserve the error register.
.p2align 2
.globl _system_error_body_leaf
_system_error_body_leaf:
    ret

.p2align 2
.globl _system_error_body_direct_arm
_system_error_body_direct_arm:
    stp x21, x30, [sp, #-16]!
    mov x21, #0
    bl _system_error_body_caller
    cmp x21, #0
    cset w0, eq
    ldp x21, x30, [sp], #16
    ret

.p2align 2
.globl _system_error_body_indirect_arm
_system_error_body_indirect_arm:
    stp x21, x30, [sp, #-16]!
    mov x21, #0
    adrp x16, _system_error_body_root@PAGE
    ldr x16, [x16, _system_error_body_root@PAGEOFF]
    ldr x16, [x16]
    blr x16
    cmp x21, #0
    cset w0, eq
    ldp x21, x30, [sp], #16
    ret

.p2align 2
.globl _system_error_body_caller
_system_error_body_caller:
    stp x29, x30, [sp, #-16]!
    bl _getpid
    ldp x29, x30, [sp], #16
    ret


// Explicit slots prevent the linker's local-GOT load relaxation. Distinct
// immutable segments let tests remove either storage proof independently.
.section __DATA_CONST,__const
.p2align 3
.globl _system_error_body_slot
_system_error_body_slot:
    .quad _system_error_body_leaf

.section __AUTH_CONST,__const
.p2align 3
.globl _system_error_body_root
_system_error_body_root:
    .quad _system_error_body_slot

// Return-group instructions can forward code instead of resuming the caller.
.text
.p2align 2
.globl _system_error_return_dispatch
_system_error_return_dispatch:
    ret x0

.p2align 2
.globl _system_error_return_keep
_system_error_return_keep:
    mov x0, #13
    ret

.p2align 2
.globl _system_error_return_throw
_system_error_return_throw:
    mov x21, #1
    mov x0, #13
    ret

.p2align 2
.globl _system_error_return_control
_system_error_return_control:
    stp x21, x30, [sp, #-16]!
    mov x21, #0
    adr x1, _system_error_return_keep
    adr x2, _system_error_return_throw
    cmp x0, #0
    csel x0, x1, x2, eq
    bl _system_error_return_dispatch
    cmp x21, #0
    cset w0, eq
    ldp x21, x30, [sp], #16
    ret

// LR itself can be redirected, while another register carries the caller's LR.
.p2align 2
.globl _system_error_return_lr_dispatch
_system_error_return_lr_dispatch:
    mov x16, x30
    adr x30, _system_error_return_lr_target
    ret
_system_error_return_lr_target:
    mov x21, #1
    mov x0, #13
    ret x16

.p2align 2
.globl _system_error_return_lr_control
_system_error_return_lr_control:
    stp x21, x30, [sp, #-16]!
    mov x21, #0
    bl _system_error_return_lr_dispatch
    cmp x21, #0
    cset w0, eq
    ldp x21, x30, [sp], #16
    ret

// This explicit non-LR return is valid: its target is the entry LR.
.p2align 2
.globl _system_error_return_alias
_system_error_return_alias:
    mov x16, x30
    ret x16

.p2align 2
.globl _system_error_return_alias_control
_system_error_return_alias_control:
    stp x21, x30, [sp, #-16]!
    mov x21, #0
    bl _system_error_return_alias
    cmp x21, #0
    cset w0, eq
    ldp x21, x30, [sp], #16
    ret

// A callee may restore a changed saved register. The carried MAY clobber
// deliberately omits x19; a return-address proof must use direct MUST facts.
.p2align 2
.globl _system_error_return_register_callee
_system_error_return_register_callee:
    stp x19, x30, [sp, #-16]!
    adr x19, _system_error_return_throw
    str x19, [sp]
    ldp x19, x30, [sp], #16
    ret

.p2align 2
.globl _system_error_return_register_dispatch
_system_error_return_register_dispatch:
    stp x19, x30, [sp, #-16]!
    mov x19, x30
    bl _system_error_return_register_callee
    mov x16, x19
    ldp x19, x30, [sp], #16
    ret x16

.p2align 2
.globl _system_error_return_register_control
_system_error_return_register_control:
    stp x21, x30, [sp, #-16]!
    mov x21, #0
    bl _system_error_return_register_dispatch
    cmp x21, #0
    cset w0, eq
    ldp x21, x30, [sp], #16
    ret

.p2align 2
.globl _system_error_return_register_keep
_system_error_return_register_keep:
    stp x19, x30, [sp, #-16]!
    mov x19, #7
    ldp x19, x30, [sp], #16
    ret

.p2align 2
.globl _system_error_return_register_good_dispatch
_system_error_return_register_good_dispatch:
    stp x19, x30, [sp, #-16]!
    mov x19, x30
    bl _system_error_return_register_keep
    mov x16, x19
    ldp x19, x30, [sp], #16
    ret x16

.p2align 2
.globl _system_error_return_register_good_control
_system_error_return_register_good_control:
    stp x21, x30, [sp, #-16]!
    mov x21, #0
    bl _system_error_return_register_good_dispatch
    cmp x21, #0
    cset w0, eq
    ldp x21, x30, [sp], #16
    ret

// Signing/authenticating the caller's LR must retain its return origin.
.text
.arch armv8.3-a
.p2align 2
.globl _system_error_return_auth
_system_error_return_auth:
    pacibsp
    retab

.p2align 2
.globl _system_error_return_auth_control
_system_error_return_auth_control:
    stp x21, x30, [sp, #-16]!
    mov x21, #0
    bl _system_error_return_auth
    cmp x21, #0
    cset w0, eq
    ldp x21, x30, [sp], #16
    ret

// A decoded prefix ending at the next symbol is not a closed body.
.text
.p2align 2
.globl _system_error_return_fallthrough
_system_error_return_fallthrough:
    nop
.globl _system_error_return_fallthrough_error
_system_error_return_fallthrough_error:
    mov x21, #1
    mov x0, #13
    ret
.p2align 2
.globl _system_error_return_fallthrough_control
_system_error_return_fallthrough_control:
    stp x21, x30, [sp, #-16]!
    mov x21, #0
    bl _system_error_return_fallthrough
    cmp x21, #0
    cset w0, eq
    ldp x21, x30, [sp], #16
    ret

// The middle function has no direct x19 write. A direct-only preservation
// fact must not hide the clobber from its caller's saved return address.
.text
.p2align 2
.globl _system_error_return_deep_middle
_system_error_return_deep_middle:
    stp x29, x30, [sp, #-16]!
    bl _system_error_return_register_callee
    ldp x29, x30, [sp], #16
    ret
.globl _system_error_return_deep_dispatch
_system_error_return_deep_dispatch:
    stp x19, x30, [sp, #-16]!
    mov x19, x30
    bl _system_error_return_deep_middle
    mov x16, x19
    ldp x19, x30, [sp], #16
    ret x16
.globl _system_error_return_deep_control
_system_error_return_deep_control:
    stp x21, x30, [sp, #-16]!
    mov x21, #0
    bl _system_error_return_deep_dispatch
    cmp x21, #0
    cset w0, eq
    ldp x21, x30, [sp], #16
    ret

// A returned frame alias must survive MAY/MUST and FP input transport.
.text
.p2align 2
.globl _system_error_return_fp_alias_leaf
_system_error_return_fp_alias_leaf:
    str x19, [sp, #-16]!
    add x19, sp, #24
    add sp, sp, #16
    ret
.globl _system_error_return_fp_alias_write
_system_error_return_fp_alias_write:
    fmov x0, d0
    adr x1, _system_error_return_fp_alias_error
    str x1, [x0]
    ret
.globl _system_error_return_fp_alias_middle
_system_error_return_fp_alias_middle:
    stp x29, x30, [sp, #-16]!
    mov x16, x30
    bl _system_error_return_fp_alias_leaf
    fmov d0, x19
    bl _system_error_return_fp_alias_write
    ldp x29, x30, [sp], #16
    ret
.globl _system_error_return_fp_alias_error
_system_error_return_fp_alias_error:
    mov x21, #1
    ret x16
.globl _system_error_return_fp_alias_control
_system_error_return_fp_alias_control:
    stp x19, x30, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x21, #0
    bl _system_error_return_fp_alias_middle
    cmp x21, #0
    cset w0, eq
    ldp x21, x22, [sp], #16
    ldp x19, x30, [sp], #16
    ret

// A returned frame alias must survive MAY/MUST and GP input transport.
.text
.p2align 2
.globl _system_error_return_gp_alias_leaf
_system_error_return_gp_alias_leaf:
    str x19, [sp, #-16]!
    add x19, sp, #24
    add sp, sp, #16
    ret
.globl __os_log_impl
__os_log_impl:
    mov x0, x9
    adr x1, _system_error_return_gp_alias_error
    str x1, [x0]
    ret
.globl _system_error_return_gp_alias_middle
_system_error_return_gp_alias_middle:
    stp x29, x30, [sp, #-16]!
    mov x16, x30
    bl _system_error_return_gp_alias_leaf
    mov x9, x19
    bl __os_log_impl
    ldp x29, x30, [sp], #16
    ret
.globl _system_error_return_gp_alias_error
_system_error_return_gp_alias_error:
    mov x21, #1
    ret x16
.globl _system_error_return_gp_alias_control
_system_error_return_gp_alias_control:
    stp x19, x30, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x21, #0
    bl _system_error_return_gp_alias_middle
    cmp x21, #0
    cset w0, eq
    ldp x21, x22, [sp], #16
    ldp x19, x30, [sp], #16
    ret

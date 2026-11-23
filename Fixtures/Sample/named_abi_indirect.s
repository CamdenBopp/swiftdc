// GOT calls must retain the actual provider even when the raw spelling
// selects a different SDK parameter/result prototype. Swift error x21 passes through.
.text

.p2align 2
.globl _named_foreign_pid_indirect_entry
_named_foreign_pid_indirect_entry:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x16, _getpid@GOTPAGE
    ldr x16, [x16, _getpid@GOTPAGEOFF]
    blr x16
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl _named_foreign_sqrt_indirect_entry
_named_foreign_sqrt_indirect_entry:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x16, _sqrt@GOTPAGE
    ldr x16, [x16, _sqrt@GOTPAGEOFF]
    blr x16
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl _named_foreign_free_indirect_entry
_named_foreign_free_indirect_entry:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x16, _free@GOTPAGE
    ldr x16, [x16, _free@GOTPAGEOFF]
    blr x16
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl _named_foreign_rect_indirect_entry
_named_foreign_rect_indirect_entry:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x16, _CGRectInset@GOTPAGE
    ldr x16, [x16, _CGRectInset@GOTPAGEOFF]
    blr x16
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl _named_foreign_format_indirect_entry
_named_foreign_format_indirect_entry:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x16, _printf@GOTPAGE
    ldr x16, [x16, _printf@GOTPAGEOFF]
    blr x16
    ldp x29, x30, [sp], #16
    ret

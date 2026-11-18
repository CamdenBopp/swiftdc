// Real system bindings, without the foreign provider in this image's dependencies.
.text
.p2align 2
.globl _named_real_sqrt_indirect
_named_real_sqrt_indirect:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x16, _sqrt@GOTPAGE
    ldr x16, [x16, _sqrt@GOTPAGEOFF]
    blr x16
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl _named_real_pid_indirect
_named_real_pid_indirect:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x16, _getpid@GOTPAGE
    ldr x16, [x16, _getpid@GOTPAGEOFF]
    blr x16
    sxtw x0, w0
    ldp x29, x30, [sp], #16
    ret

// Own-source compare-and-branch width controls. The producer always sets
// bit 32, so its x0 result is nonzero while its w0 view can be zero.
.text
.p2align 2
.globl _widebranch_producer
_widebranch_producer:
    orr x0, x0, #0x100000000
    ret

.p2align 2
.globl _wordbranch_w_cbz
_wordbranch_w_cbz:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _widebranch_producer
    cbz w0, Lwordbranch_w_cbz_taken
    mov x0, #2
    b Lwordbranch_w_cbz_exit
Lwordbranch_w_cbz_taken:
    mov x0, #1
Lwordbranch_w_cbz_exit:
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl _wordbranch_w_cbz_copy
_wordbranch_w_cbz_copy:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _widebranch_producer
    mov x8, x0
    cbz w8, Lwordbranch_w_cbz_copy_taken
    mov x0, #2
    b Lwordbranch_w_cbz_copy_exit
Lwordbranch_w_cbz_copy_taken:
    mov x0, #1
Lwordbranch_w_cbz_copy_exit:
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl _wordbranch_w_cbnz
_wordbranch_w_cbnz:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _widebranch_producer
    cbnz w0, Lwordbranch_w_cbnz_taken
    mov x0, #2
    b Lwordbranch_w_cbnz_exit
Lwordbranch_w_cbnz_taken:
    mov x0, #1
Lwordbranch_w_cbnz_exit:
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl _wordbranch_w_cbnz_copy
_wordbranch_w_cbnz_copy:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _widebranch_producer
    mov x8, x0
    cbnz w8, Lwordbranch_w_cbnz_copy_taken
    mov x0, #2
    b Lwordbranch_w_cbnz_copy_exit
Lwordbranch_w_cbnz_copy_taken:
    mov x0, #1
Lwordbranch_w_cbnz_copy_exit:
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl _wordbranch_x_cbz
_wordbranch_x_cbz:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _widebranch_producer
    cbz x0, Lwordbranch_x_cbz_taken
    mov x0, #2
    b Lwordbranch_x_cbz_exit
Lwordbranch_x_cbz_taken:
    mov x0, #1
Lwordbranch_x_cbz_exit:
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl _wordbranch_x_cbz_copy
_wordbranch_x_cbz_copy:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _widebranch_producer
    mov x8, x0
    cbz x8, Lwordbranch_x_cbz_copy_taken
    mov x0, #2
    b Lwordbranch_x_cbz_copy_exit
Lwordbranch_x_cbz_copy_taken:
    mov x0, #1
Lwordbranch_x_cbz_copy_exit:
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl _wordbranch_x_cbnz
_wordbranch_x_cbnz:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _widebranch_producer
    cbnz x0, Lwordbranch_x_cbnz_taken
    mov x0, #2
    b Lwordbranch_x_cbnz_exit
Lwordbranch_x_cbnz_taken:
    mov x0, #1
Lwordbranch_x_cbnz_exit:
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl _wordbranch_x_cbnz_copy
_wordbranch_x_cbnz_copy:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _widebranch_producer
    mov x8, x0
    cbnz x8, Lwordbranch_x_cbnz_copy_taken
    mov x0, #2
    b Lwordbranch_x_cbnz_copy_exit
Lwordbranch_x_cbnz_copy_taken:
    mov x0, #1
Lwordbranch_x_cbnz_copy_exit:
    ldp x29, x30, [sp], #16
    ret

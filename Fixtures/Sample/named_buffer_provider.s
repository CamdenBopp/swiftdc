// The foreign SDK spelling forwards the caller's x8 unchanged to the
// Swift sret implementation. No C malloc declaration is involved.
.section __TEXT,__text,regular,pure_instructions
.globl _malloc
.p2align 2
_malloc:
    b _named_buffer_allocate

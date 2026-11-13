// A hand-built __cfstring entry whose length (2) disagrees with its bytes
// ("abcd", NUL at 4): the entry says the string is "ab", a C-string read
// says "abcd". Neither is proven, so the literal declines to its address.
    .section __TEXT,__cstring,cstring_literals
Lstr:
    .asciz "abcd"
    .section __DATA,__cfstring
    .p2align 3
Lcf:
    .quad ___CFConstantStringClassReference
    .long 0x7c8
    .space 4
    .quad Lstr
    .quad 2
    .section __TEXT,__text,regular,pure_instructions
    .globl _short
    .p2align 2
_short:
    adrp x0, Lcf@PAGE
    add x0, x0, Lcf@PAGEOFF
    b _NSLog

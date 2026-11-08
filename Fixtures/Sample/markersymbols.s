// A call into a function whose address also carries linker marker symbols.
//
// TinyCC defines `__start_text`, `__init_array_start`, `__init_array_end`
// and friends as ordinary global symbols, and they land on the first
// function in `__text`, here `add3`. The symbol table then lists four names
// at one address and nothing says which one the code is. The true call:
// `callAdd3()` is `add3(1, 2, 3)`, which returns 6; `add3` reads x0, x1
// and x2. The call must not be named after a marker.
    .section __TEXT,__text,regular,pure_instructions
    .globl __start_text
    .globl __init_array_start
    .globl __init_array_end
    .globl _add3
    .p2align 2
__start_text:
__init_array_start:
__init_array_end:
_add3:
    add x0, x0, x1
    add x0, x0, x2
    ret

    .globl _callAdd3
    .p2align 2
_callAdd3:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x0, #1
    mov x1, #2
    mov x2, #3
    bl _add3
    ldp x29, x30, [sp], #16
    ret

// An assembly label inside a function, as hand-written assembly (OpenSSL)
// keeps them. `loop_top` has no `L` prefix, so the linker lists it in
// LC_FUNCTION_STARTS (`_outer+4`) and the starts cut `_outer` in two. True
// behaviour: `_outer` sets x1 to 0 and falls into the loop at `loop_top`,
// which counts x1 up to x0 and returns it; `_outer`'s first span has no
// return of its own.
.text
.globl _outer
.p2align 2
_outer:
    mov x1, #0
loop_top:
    add x1, x1, #1
    cmp x1, x0
    b.lt loop_top
    mov x0, x1
    ret
.globl _second
.p2align 2
_second:
    mov x0, #5
    ret

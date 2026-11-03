// Vector lane moves (assembly; compilers emit `mov.d v0[1], x19` to build
// a 16-byte pair). True behaviour: _ins stores the 16 bytes {x1, x2} at
// x0; _umovzero returns 0, the upper lane `fmov d1, x9` cleared.
.text
.globl _ins
.p2align 2
_ins:
    fmov d0, x1
    mov v0.d[1], x2
    str q0, [x0]
    ret

.globl _umovzero
.p2align 2
_umovzero:
    mov x9, #43
    fmov d1, x9
    mov x0, v1.d[1]
    ret

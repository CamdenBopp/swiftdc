// Returns 61 when 7 <= input < 19, and 71 otherwise.
// Two dependent diamonds separated by straight-line blocks. The shuffled
// version puts its return below the entry address but before all deciders.
.text
.p2align 2
.macro selector name, shuffled
.globl _selectflow_\name
_selectflow_\name:
.if \shuffled
    b Lstart\name
Lreturn\name:
    ret
.endif
Lstart\name:
    cmp x0, #7
    b.lo LfirstFalse\name
    cmp x0, #19
    cset w8, lo
    b LfirstMerge\name
LfirstFalse\name:
    mov w8, #0
LfirstMerge\name:
    b Lmiddle\name
Lmiddle\name:
    eor w8, w8, #1
    b Lsecond\name
Lsecond\name:
    cbnz w8, LsecondFalse\name
    mov x0, #61
    b LlastMerge\name
LsecondFalse\name:
    mov x0, #71
LlastMerge\name:
.if \shuffled
    b Lreturn\name
.else
    ret
.endif
.endm
selector forward, 0
selector shuffled, 1
.globl _selectflow_cycle
_selectflow_cycle:
    and w0, w0, #15
    mov w8, #0
Lcycle:
    cmp w8, w0
    b.hs Lexit
    add w8, w8, #1
    b Lcycle
Lexit:
    mov w0, w8
    ret

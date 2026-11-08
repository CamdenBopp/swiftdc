// Authored return-path probes: zero -> 7, nonzero -> 8, except nested
// (inputs >= 16 -> 9) and joined (inputs < 19 -> 7). The detached 77
// return is unreachable. The cycle and external target must stay unknown.
.text
.p2align 2
.globl _returnpath_split
_returnpath_split:
    cbz x0, LsplitZero
    mov x0, #8
    ret
LsplitZero:
    mov x0, #7
    ret
.globl _returnpath_shuffled
_returnpath_shuffled:
    b LshuffledStart
LshuffledZero:
    mov x0, #7
    ret
LshuffledStart:
    cbz x0, LshuffledZero
    mov x0, #8
    ret
.globl _returnpath_nested
_returnpath_nested:
    cbz x0, LnestedZero
    cmp x0, #16
    b.hs LnestedHigh
    mov x0, #8
    ret
LnestedHigh:
    mov x0, #9
    ret
LnestedZero:
    mov x0, #7
    ret
.globl _returnpath_joined
_returnpath_joined:
    cmp x0, #7
    b.lo LjoinedLow
    cmp x0, #19
    b.lo LjoinedLow
    mov x0, #8
    ret
LjoinedLow:
    mov x0, #7
    ret
.globl _returnpath_detached
_returnpath_detached:
    b LdetachedStart
    mov x0, #77
    ret
LdetachedStart:
    cbz x0, LdetachedZero
    mov x0, #8
    ret
LdetachedZero:
    mov x0, #7
    ret
.globl _returnpath_cycle
_returnpath_cycle:
    mov x8, #0
    and x0, x0, #15
Lcycle:
    cmp x8, x0
    b.hs LcycleExit
    add x8, x8, #1
    b Lcycle
LcycleExit:
    mov x0, x8
    ret
.globl _returnpath_external
_returnpath_external:
    cbz x0, LexternalSink
    mov x0, #8
    ret
.globl _returnpath_sink
_returnpath_sink:
LexternalSink:
    mov x0, #77
    ret

// Native two-argument probes: symbolic addition NZCV at both register widths.
.text
.p2align 2
.macro probe width, kind, condition
.globl _addflags_\kind\()_\width\()_\condition
_addflags_\kind\()_\width\()_\condition:
.ifc \kind, adds
    adds \width\()2, \width\()0, \width\()1
.else
    cmn \width\()0, \width\()1
.endif
    cset x0, \condition
    ret
.endm
.macro allConditions width, kind
.irp code,eq,ne,hs,lo,mi,pl,vs,vc,hi,ls,ge,lt,gt,le
    probe \width, \kind, \code
.endr
.endm
allConditions x, adds
allConditions w, adds
allConditions x, cmn
allConditions w, cmn
// Constant additions exercise the simplified threshold and signed-minimum edge.
.macro constant width, kind, condition
.globl _addflags_\kind\()_\width\()_\condition
_addflags_\kind\()_\width\()_\condition:
.ifc \kind, const11
    adds \width\()2, \width\()0, #11
.else
.ifc \kind, const0
    adds \width\()2, \width\()0, #0
.else
.ifc \kind, cmn0
    cmn \width\()0, #0
.else
.ifc \width, w
    mov w1, #0x80000000
.else
    mov x1, #0x8000000000000000
.endif
    adds \width\()2, \width\()0, \width\()1
.endif
.endif
.endif
    cset x0, \condition
    ret
.endm
.irp code,eq,ne,ge,lt,gt,le
    constant x, const11, \code
    constant w, const11, \code
    constant x, minimum, \code
    constant w, minimum, \code
    constant x, const0, \code
    constant w, const0, \code
    constant x, cmn0, \code
    constant w, cmn0, \code
.endr

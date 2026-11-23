// A foreign compiler-helper spelling is not a readonly contract. This entry
// writes 41 through x0; it is not Swift's existential projection helper.
.text
.p2align 2
.globl ___swift_project_boxed_opaque_existential_0
___swift_project_boxed_opaque_existential_0:
    mov w8, #41
    str w8, [x0]
    mov x0, #3
    ret

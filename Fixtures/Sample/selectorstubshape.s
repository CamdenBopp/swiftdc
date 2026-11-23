// Stubs shaped like selector stubs that do not send. A selector stub
// loads its selector into x1 and goes to objc_msgSend. These two load a
// selector the same way and go somewhere else: one branches straight to a
// function that adds, the other jumps through a slot bound to puts. A
// call to either is a call to that function, with a selector-looking
// second argument. The linker does not emit these; they are the smallest
// bodies in which the stub's opening and its destination disagree.
.section __TEXT,__objc_methname,cstring_literals
L_take: .asciz "take:"
L_show: .asciz "show:"
.section __DATA,__objc_selrefs,literal_pointers,no_dead_strip
.p2align 3
L_take_ref: .quad L_take
L_show_ref: .quad L_show

.section __TEXT,__objc_stubs,regular,pure_instructions
.p2align 5
// adrp x1; ldr x1; b <an ordinary function>
_branching_stub:
    adrp x1, L_take_ref@PAGE
    ldr x1, [x1, L_take_ref@PAGEOFF]
    b _adds_first_and_third
.p2align 5
// adrp x1; ldr x1; adrp x16; ldr x16; br x16, the slot being puts'
_slot_stub:
    adrp x1, L_show_ref@PAGE
    ldr x1, [x1, L_show_ref@PAGEOFF]
    adrp x16, _puts@GOTPAGE
    ldr x16, [x16, _puts@GOTPAGEOFF]
    br x16

.text
.p2align 2
// Returns x0 + x2. It reads no selector.
_adds_first_and_third:
    add x0, x0, x2
    ret

// Calls the branching stub with 7 in x2: returns its argument plus 7.
.globl _calls_branching_stub
_calls_branching_stub:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x2, #7
    bl _branching_stub
    ldp x29, x30, [sp], #16
    ret

// Calls the slot stub: puts(its argument), with x1 clobbered on the way.
.globl _calls_slot_stub
_calls_slot_stub:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _slot_stub
    ldp x29, x30, [sp], #16
    ret

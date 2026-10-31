// The first function in __text is local, and `strip -x` removes its symbol,
// as in most stripped executables (/usr/bin/true's only function). objdump
// prints the file's path and a colon before the listing, the shape of a
// label, and swiftdc named the first function after the path. True
// behaviour: the first function has no name (`sub_<address>`), returns
// x + 41, and `_entry` calls it.
    .text
    .p2align 2
_first:
    add w0, w0, #41
    ret

    .globl _entry
    .p2align 2
_entry:
    stp x29, x30, [sp, #-16]!
    bl _first
    lsl w0, w0, #1
    ldp x29, x30, [sp], #16
    ret

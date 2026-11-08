// Tables in __text that LC_FUNCTION_STARTS marks as functions (the symbols
// are local, so `strip -x` leaves only the starts). True behaviour: `mixed`
// starts with a word no instruction decodes from, then two small words;
// `table` is only such words; `after` is code. Each start is one function,
// at its own address, on every path.
.text
.globl _entry
.p2align 2
_entry:
    b after

.p2align 2
mixed:
    .long 0xffffffff
    .long 0x0000000c
    .long 0x00000014

.p2align 2
table:
    .long 0xffffffff
    .long 0xffffffff
    .long 0xffffffff

.p2align 2
after:
    mov x0, #1
    ret

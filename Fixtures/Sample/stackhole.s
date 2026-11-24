// Authored callers that pass the address of a local as a stack argument,
// with the argument words laid out so that a scan of consecutive 8-byte
// words from sp does not arrive at it. Each caller stores 7 in a local,
// calls, and returns what it loads back from the local. A sink that takes
// the pointer stores 11 through it. The compiler emits these layouts for a
// 16-byte-aligned stack argument and for a call with more than sixteen
// stack words; they are written out here so that each body has one shape.
//
// StackHole.padded() -> Swift.Int       11: [sp] is a word, [sp, #8] is
//                                       padding nothing writes, [sp, #16]
//                                       is &local.
// StackHole.seventeenth() -> Swift.Int  11: sixteen words of 1, then
//                                       &local as the seventeenth.
// StackHole.packed() -> Swift.Int       11: a byte at [sp], a word at
//                                       [sp, #4], &local at [sp, #8].
// StackHole.quiet() -> Swift.Int        7: no address is stored anywhere.
// StackHole.spilled() -> Swift.Int      7: &local is kept in a slot above
//                                       the frame record, which is no
//                                       argument; the sink reads [sp] only.
.text

.p2align 2
.globl _$s9StackHole6paddedSiyF
_$s9StackHole6paddedSiyF:
    sub sp, sp, #64
    stp x29, x30, [sp, #48]
    add x29, sp, #48
    mov x8, #7
    str x8, [sp, #40]
    add x9, sp, #40
    mov x10, #1
    str x10, [sp]
    str x9, [sp, #16]
    bl _stack_hole_sink16
    ldr x0, [sp, #40]
    ldp x29, x30, [sp, #48]
    add sp, sp, #64
    ret

.p2align 2
.globl _$s9StackHole11seventeenthSiyF
_$s9StackHole11seventeenthSiyF:
    sub sp, sp, #176
    stp x29, x30, [sp, #160]
    add x29, sp, #160
    mov x8, #7
    str x8, [sp, #144]
    add x9, sp, #144
    mov x10, #1
    stp x10, x10, [sp]
    stp x10, x10, [sp, #16]
    stp x10, x10, [sp, #32]
    stp x10, x10, [sp, #48]
    stp x10, x10, [sp, #64]
    stp x10, x10, [sp, #80]
    stp x10, x10, [sp, #96]
    stp x10, x10, [sp, #112]
    str x9, [sp, #128]
    bl _stack_hole_sink128
    ldr x0, [sp, #144]
    ldp x29, x30, [sp, #160]
    add sp, sp, #176
    ret

.p2align 2
.globl _$s9StackHole6packedSiyF
_$s9StackHole6packedSiyF:
    sub sp, sp, #64
    stp x29, x30, [sp, #48]
    add x29, sp, #48
    mov x8, #7
    str x8, [sp, #40]
    add x9, sp, #40
    mov w10, #1
    strb w10, [sp]
    str w10, [sp, #4]
    str x9, [sp, #8]
    bl _stack_hole_sink8
    ldr x0, [sp, #40]
    ldp x29, x30, [sp, #48]
    add sp, sp, #64
    ret

.p2align 2
.globl _$s9StackHole5quietSiyF
_$s9StackHole5quietSiyF:
    sub sp, sp, #64
    stp x29, x30, [sp, #48]
    add x29, sp, #48
    mov x8, #7
    str x8, [sp, #40]
    mov x10, #1
    str x10, [sp]
    str x10, [sp, #16]
    bl _stack_hole_reads
    ldr x0, [sp, #40]
    ldp x29, x30, [sp, #48]
    add sp, sp, #64
    ret

.p2align 2
.globl _$s9StackHole7spilledSiyF
_$s9StackHole7spilledSiyF:
    sub sp, sp, #64
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    mov x8, #7
    str x8, [sp, #40]
    add x9, sp, #40
    str x9, [sp, #48]
    mov x10, #1
    str x10, [sp]
    bl _stack_hole_reads
    ldr x0, [sp, #40]
    ldp x29, x30, [sp, #16]
    add sp, sp, #64
    ret

// The sinks. Each reads a stack argument at a fixed offset from the sp it
// was entered with. Three store 11 through the pointer they find there;
// _stack_hole_reads loads its first stack word and writes nothing.
.p2align 2
.globl _stack_hole_sink16
_stack_hole_sink16:
    ldr x8, [sp, #16]
    mov x9, #11
    str x9, [x8]
    ret

.p2align 2
.globl _stack_hole_sink128
_stack_hole_sink128:
    ldr x8, [sp, #128]
    mov x9, #11
    str x9, [x8]
    ret

.p2align 2
.globl _stack_hole_sink8
_stack_hole_sink8:
    ldr x8, [sp, #8]
    mov x9, #11
    str x9, [x8]
    ret

.p2align 2
.globl _stack_hole_reads
_stack_hole_reads:
    ldr x8, [sp]
    ret

// Calls to in-image functions no signature describes. Such a call passes
// what the callee's body reads (CalleeRegisterSummary.argumentReads).
//
// useSecond reads x1 only: it writes x0 before reading it. callUseSecond
// leaves 5 in x0 and 7 in x1 at the call. True behaviour: useSecond's one
// input is 7; the 5 in x0 is never read.
//
// accessorLike writes x0 and x1 and calls memset (known arity 3), whose
// third argument is accessorLike's own untouched x2, as a lazy witness
// table accessor hands its x2 to swift_getWitnessTable. callAccessorLike
// leaves 5 in x0. True behaviour: accessorLike reads x2 only by passing it
// on; the 5 is never read.
.text
.p2align 2
.globl _useSecond
_useSecond:
    mov x0, x1
    add x0, x0, #3
    ret

.globl _callUseSecond
_callUseSecond:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x0, #5
    mov x1, #7
    bl _useSecond
    ldp x29, x30, [sp], #16
    ret

.globl _accessorLike
_accessorLike:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x0, sp
    mov x1, #0
    bl _memset
    ldp x29, x30, [sp], #16
    ret

.globl _callAccessorLike
_callAccessorLike:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x0, #5
    bl _accessorLike
    ldp x29, x30, [sp], #16
    ret

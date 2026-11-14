// How the Swift calling convention uses x20, the `self` (context)
// register, on arm64. Written by hand from the rules themselves (the
// rules are the ones LLVM's AArch64 swiftself code-generation test
// checks; nothing is copied from it). Each function names the rule it
// shows and what it does.
//
//   1. A `self` parameter arrives in x20.
//   2. A caller passes `self` in x20, whatever register held the value.
//   3. x20 is callee-saved: a function that changes it restores it.
//   4. So `self` survives a call, and a second call needs no reload.
//   5. A tail call keeps the caller's x20: same `self`, no move.
//   6. A call on a different `self` moves it into x20 first.
//   7. A callee that returns its `self` returns it in x0 like any result;
//      the caller reads x0, not the x20 it passed.
        .text
        .p2align 2

// SS.C.me() -> SS.C                      rule 1: returns self.
        .globl _$s2SS1CC2meACyF
_$s2SS1CC2meACyF:
        mov x0, x20
        ret

// SS.callMe(SS.C) -> SS.C                rules 2, 3: me(self: arg0).
        .globl _$s2SS6callMeyAA1CCADF
        .p2align 2
_$s2SS6callMeyAA1CCADF:
        stp x20, x19, [sp, #-32]!
        stp x29, x30, [sp, #16]
        add x29, sp, #16
        mov x20, x0
        bl _$s2SS1CC2meACyF
        ldp x29, x30, [sp, #16]
        ldp x20, x19, [sp], #32
        ret

// SS.C.twice() -> ()                     rule 4: me(self: self), twice.
        .globl _$s2SS1CC5twiceyyF
        .p2align 2
_$s2SS1CC5twiceyyF:
        stp x29, x30, [sp, #-16]!
        mov x29, sp
        bl _$s2SS1CC2meACyF
        bl _$s2SS1CC2meACyF
        ldp x29, x30, [sp], #16
        ret

// SS.C.tail() -> SS.C                    rule 5: return me(self: self).
        .globl _$s2SS1CC4tailACyF
        .p2align 2
_$s2SS1CC4tailACyF:
        b _$s2SS1CC2meACyF

// SS.C.other(SS.C) -> SS.C               rule 6: return me(self: arg0),
//                                        not me(self: self).
        .globl _$s2SS1CC5otheryA2CF
        .p2align 2
_$s2SS1CC5otheryA2CF:
        stp x20, x19, [sp, #-32]!
        stp x29, x30, [sp, #16]
        add x29, sp, #16
        mov x20, x0
        bl _$s2SS1CC2meACyF
        ldp x29, x30, [sp, #16]
        ldp x20, x19, [sp], #32
        ret

// SS.C.stored(inout SS.C) -> ()          rule 7: arg0 = me(self: self.next),
//                                        where next is the word at self+0x10.
//                                        The stored word is the call's
//                                        result in x0, not the x20 passed.
        .globl _$s2SS1CC6storedyyACzF
        .p2align 2
_$s2SS1CC6storedyyACzF:
        stp x20, x19, [sp, #-32]!
        stp x29, x30, [sp, #16]
        add x29, sp, #16
        mov x19, x0
        ldr x20, [x20, #0x10]
        bl _$s2SS1CC2meACyF
        str x0, [x19]
        ldp x29, x30, [sp, #16]
        ldp x20, x19, [sp], #32
        ret

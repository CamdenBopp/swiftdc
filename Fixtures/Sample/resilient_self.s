// Bodies that read x20 under names that say it is no enum's self, for
// resilientself.swift. A static witness and an initializer have a metatype
// in x20, a closure its context, so the load is no tag. Fixed is frozen:
// its members take self in x0, and x20 read as a value is no self either.
// A resilient enum's initializer returns through x8, so those two store it.
// An instance witness of Kind is the one here whose x20 is self.
// Asm.overwrite and Asm.jump are named as Asm's own members, but write x20
// before the load reads it: straight-line, and on the only path from the
// entry, where the load comes first in address order.
.text
.p2align 2
.globl _$s13ResilientSelf3AsmOAA4KindA2aDP4makeSiyFZTW
_$s13ResilientSelf3AsmOAA4KindA2aDP4makeSiyFZTW:
    ldrb w0, [x20]
    ret

.globl _$s13ResilientSelf3AsmOAA4KindA2aDP4seedxSi_tcfCTW
_$s13ResilientSelf3AsmOAA4KindA2aDP4seedxSi_tcfCTW:
    ldrb w9, [x20]
    strb w9, [x8]
    ret

.globl _$s13ResilientSelf3AsmO3tagACSi_tcfC
_$s13ResilientSelf3AsmO3tagACSi_tcfC:
    ldrb w9, [x20]
    strb w9, [x8]
    ret

.globl _$s13ResilientSelf3AsmO5boxedSiycvgSiycfU_
_$s13ResilientSelf3AsmO5boxedSiycvgSiycfU_:
    ldrb w0, [x20]
    ret

.globl _$s13ResilientSelf5FixedO4peekSiyF
_$s13ResilientSelf5FixedO4peekSiyF:
    mov x0, x20
    ret

.globl _$s13ResilientSelf3AsmOAA4KindA2aDP4peekSiyFTW
_$s13ResilientSelf3AsmOAA4KindA2aDP4peekSiyFTW:
    ldrb w0, [x20]
    ret

.globl _$s13ResilientSelf3AsmO9overwriteSiyF
_$s13ResilientSelf3AsmO9overwriteSiyF:
    mov x20, x0
    ldrb w0, [x20]
    ret

.globl _$s13ResilientSelf3AsmO4jumpSiyF
_$s13ResilientSelf3AsmO4jumpSiyF:
    b 2f
1:
    ldrb w0, [x20]
    ret
2:
    mov x20, x0
    b 1b

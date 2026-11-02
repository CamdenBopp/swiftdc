// The two helpers IRGen emitted before the V2 helper
// (lib/IRGen/MetadataRequest.cpp), as the swift-syntax dylibs in Xcode 27's
// toolchain carry them. Local symbols, so `strip -x` leaves both unnamed
// (libOldMangledHelper.stripped.dylib). True behaviour: a cached word with
// bit 63 clear is the metadata, returned; otherwise its high half is the
// negated length and its low half the relative offset of a mangled name,
// which is resolved (in the abstract state, 0xff, for the second) and cached.
.text
.p2align 2
___swift_instantiateConcreteTypeFromMangledName:
    mov x8, x0
    ldr x0, [x0]
    tbnz x0, #63, 1f
    ret
1:  stp x20, x19, [sp, #-0x20]!
    stp x29, x30, [sp, #0x10]
    add x29, sp, #0x10
    neg x1, x0, asr #32
    add x0, x8, w0, sxtw
    mov x19, x8
    mov x2, #0
    mov x3, #0
    bl _swift_getTypeByMangledNameInContext2
    str x0, [x19]
    ldp x29, x30, [sp, #0x10]
    ldp x20, x19, [sp], #0x20
    ret

.p2align 2
___swift_instantiateConcreteTypeFromMangledNameAbstract:
    mov x8, x0
    ldr x0, [x0]
    tbnz x0, #63, 1f
    ret
1:  stp x20, x19, [sp, #-0x20]!
    stp x29, x30, [sp, #0x10]
    add x29, sp, #0x10
    neg x2, x0, asr #32
    add x1, x8, w0, sxtw
    mov x19, x8
    mov w0, #0xff
    mov x3, #0
    mov x4, #0
    bl _swift_getTypeByMangledNameInContextInMetadataState2
    str x0, [x19]
    ldp x29, x30, [sp, #0x10]
    ldp x20, x19, [sp], #0x20
    ret

.globl _entry
.p2align 2
_entry:
    stp x29, x30, [sp, #-0x10]!
    // x4 and x5 hold values the helper never reads: it takes the cache
    // variable in x0 alone, and sets x0-x3 for its own runtime call.
    mov x4, #9
    mov x5, #10
    bl ___swift_instantiateConcreteTypeFromMangledName
    mov x4, #9
    mov x5, #10
    bl ___swift_instantiateConcreteTypeFromMangledNameAbstract
    ldp x29, x30, [sp], #0x10
    ret

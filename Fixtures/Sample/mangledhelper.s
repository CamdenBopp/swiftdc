// __swift_instantiateConcreteTypeFromMangledNameV2 as IRGen emits it
// (lib/IRGen/MetadataRequest.cpp), and two look-alikes. Local symbols, so
// `strip -x` leaves all three unnamed (libMangledHelper.stripped.dylib).
// True behaviour: only `genuine` is the helper; `lookalike` calls malloc,
// and `wrongbranch` branches one instruction early.
.text
.p2align 2
genuine:
    stp x20, x19, [sp, #-0x20]!
    stp x29, x30, [sp, #0x10]
    add x29, sp, #0x10
    mov x19, x0
    ldr x0, [x0]
    and x8, x0, #1
    cmp x0, #0
    ccmp x8, #0, #0, ne
    b.eq 1f
    ldr x9, [x1]
    asr x8, x9, #32
    add x0, x1, w9, sxtw
    mov x1, x8
    mov x2, #0
    mov x3, #0
    bl _swift_getTypeByMangledNameInContext
    str x0, [x19]
1:  ldp x29, x30, [sp, #0x10]
    ldp x20, x19, [sp], #0x20
    ret

.p2align 2
lookalike:
    stp x20, x19, [sp, #-0x20]!
    stp x29, x30, [sp, #0x10]
    add x29, sp, #0x10
    mov x19, x0
    ldr x0, [x0]
    and x8, x0, #1
    cmp x0, #0
    ccmp x8, #0, #0, ne
    b.eq 1f
    ldr x9, [x1]
    asr x8, x9, #32
    add x0, x1, w9, sxtw
    mov x1, x8
    mov x2, #0
    mov x3, #0
    bl _malloc
    str x0, [x19]
1:  ldp x29, x30, [sp, #0x10]
    ldp x20, x19, [sp], #0x20
    ret

.p2align 2
wrongbranch:
    stp x20, x19, [sp, #-0x20]!
    stp x29, x30, [sp, #0x10]
    add x29, sp, #0x10
    mov x19, x0
    ldr x0, [x0]
    and x8, x0, #1
    cmp x0, #0
    ccmp x8, #0, #0, ne
    b.eq 1f
    ldr x9, [x1]
    asr x8, x9, #32
    add x0, x1, w9, sxtw
    mov x1, x8
    mov x2, #0
    mov x3, #0
    bl _swift_getTypeByMangledNameInContext
1:  str x0, [x19]
    ldp x29, x30, [sp, #0x10]
    ldp x20, x19, [sp], #0x20
    ret

.globl _entry
.p2align 2
_entry:
    stp x29, x30, [sp, #-0x10]!
    bl genuine
    bl lookalike
    bl wrongbranch
    ldp x29, x30, [sp], #0x10
    ret

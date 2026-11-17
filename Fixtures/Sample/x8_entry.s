// x8 holds an ordinary incoming word copied into a caller-owned pair.
// The wrapper has a direct Int result and saves x22 before using a
// machine-outlined helper that deliberately has no ordinary entry ABI.
.text
.globl _$s14OutlineScratch5probeyS2iF
.p2align 2
_$s14OutlineScratch5probeyS2iF:
    stp x22, x30, [sp, #-32]!
    mov x8, x0
    mov x22, #91
    add x0, sp, #16
    bl _OUTLINED_FUNCTION_0
    ldr x0, [sp, #24]
    ldp x22, x30, [sp], #32
    ret
.p2align 2
_OUTLINED_FUNCTION_0:
.ifdef X8_PRESERVE_CONTEXT
    str x22, [sp, #-16]!
.endif
    stp x22, x8, [x0]
    mov x22, x0
.ifdef X8_PRESERVE_CONTEXT
    ldr x22, [sp], #16
.endif
    ret

// A real x8 result-buffer entry forwards the pointer to the same helper.
// The helper stores the pointer as DATA into the caller's private pair;
// it never writes through it. The caller-owned five words stay unchanged.
.globl _$s14OutlineScratch9unchangedAA4Big5VyF
.p2align 2
_$s14OutlineScratch9unchangedAA4Big5VyF:
    stp x22, x30, [sp, #-32]!
    mov x9, x8
    add x0, sp, #16
    bl _OUTLINED_FUNCTION_0
    ldp x22, x30, [sp], #32
    ret
.globl _outline_unchanged_probe
.p2align 2
_outline_unchanged_probe:
    str x30, [sp, #-16]!
    mov x8, x0
    bl _$s14OutlineScratch9unchangedAA4Big5VyF
    ldr x30, [sp], #16
    ret

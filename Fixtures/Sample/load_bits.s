// These Swift ABI methods return FloatBox.f unchanged. The x20 receiver
// addresses one Float32 field. Sign extension affects only bits above the
// W view read by FMOV, and the masked variant preserves all of that view.
// LoadBits.swift supplies real metadata and C-callable bit-pattern oracles.
.text
.p2align 2

.globl _$s8LoadBits8FloatBoxV9roundTripSfyF
_$s8LoadBits8FloatBoxV9roundTripSfyF:
    ldrsw x8, [x20]
    fmov s0, w8
    ret

.globl _$s8LoadBits8FloatBoxV17roundTripUnscaledSfyF
_$s8LoadBits8FloatBoxV17roundTripUnscaledSfyF:
    ldursw x8, [x20]
    fmov s0, w8
    ret

.globl _$s8LoadBits8FloatBoxV5plainSfyF
_$s8LoadBits8FloatBoxV5plainSfyF:
    // Explicit SXTW leaves a signed X value. FMOV consumes only its W view.
    ldr w8, [x20]
    sxtw x8, w8
    fmov s0, w8
    ret

// The AND keeps every bit of the W operand read by FMOV.
.globl _$s8LoadBits8FloatBoxV6maskedSfyF
_$s8LoadBits8FloatBoxV6maskedSfyF:
    ldr w8, [x20]
    sxtw x8, w8
    and x8, x8, #0x0000ffffffffffff
    fmov s0, w8
    ret

// C ABI uint32_t -> uint32_t. The low byte sign extends into the
// visible low word, so the W copy must retain bits 8 through 31.
.globl _loadbits_byte_to_word
_loadbits_byte_to_word:
    sxtb x8, w0
    mov w0, w8
    ret

// C ABI uint64_t -> uint32_t. Unequal shifts move input bit 1 into
// output bit 0. Reading W0 cannot discard the pair.
.globl _loadbits_unequal_shifts
_loadbits_unequal_shifts:
    lsl x8, x0, #31
    asr x8, x8, #32
    mov w0, w8
    ret

// C ABI uint64_t -> uint32_t. The mask clears a bit visible in W0.
.globl _loadbits_mask_clears_low_bit
_loadbits_mask_clears_low_bit:
    sxtw x8, w0
    and x8, x8, #0xfffffffffffffffe
    mov w0, w8
    ret

.subsections_via_symbols

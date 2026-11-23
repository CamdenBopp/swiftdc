// Native Swift-self reductions: signed loads replicate their source sign;
// W destinations then clear the upper word. MixedWord packs a full word
// and its independently loaded low byte into separate UInt64 lanes.
.text
.p2align 2

.globl _$s14SignedSelfLoad8FloatBoxV9roundTripSfyF
_$s14SignedSelfLoad8FloatBoxV9roundTripSfyF:
    ldrsw x8, [x20]
    fmov s0, w8
    ret

.globl _$s14SignedSelfLoad8FloatBoxV17roundTripUnscaledSfyF
_$s14SignedSelfLoad8FloatBoxV17roundTripUnscaledSfyF:
    ldursw x8, [x20]
    fmov s0, w8
    ret

.globl _$s14SignedSelfLoad8FloatBoxV5plainSfyF
_$s14SignedSelfLoad8FloatBoxV5plainSfyF:
    ldr s0, [x20]
    ret

.globl _$s14SignedSelfLoad9SignedBoxV6signeds5Int64VyF
_$s14SignedSelfLoad9SignedBoxV6signeds5Int64VyF:
    ldrsw x0, [x20]
    ret

.globl _$s14SignedSelfLoad7ByteBoxV4wideSfyF
_$s14SignedSelfLoad7ByteBoxV4wideSfyF:
    ldrsb x8, [x20]
    fmov s0, w8
    ret

.globl _$s14SignedSelfLoad8ShortBoxV4wideSfyF
_$s14SignedSelfLoad8ShortBoxV4wideSfyF:
    ldrsh x8, [x20]
    fmov s0, w8
    ret

.subsections_via_symbols


.text
.p2align 2
.globl _$s14SignedSelfLoad8FloatBoxV7rawWords6UInt64VyF
_$s14SignedSelfLoad8FloatBoxV7rawWords6UInt64VyF:
    ldr w0, [x20]
    ret

.globl _$s14SignedSelfLoad8FloatBoxV10signedWords5Int64VyF
_$s14SignedSelfLoad8FloatBoxV10signedWords5Int64VyF:
    ldrsw x0, [x20]
    // Keep the different typed owner distinct under optimized linker ICF.
    nop
    ret

.text
.p2align 2

.globl _$s14SignedSelfLoad10OffsetByteV13sampleStorages5Int64VyF
_$s14SignedSelfLoad10OffsetByteV13sampleStorages5Int64VyF:
    ldrsb x0, [x20, #8]
    ret

.globl _$s14SignedSelfLoad10OffsetHalfV13sampleStorages5Int64VyF
_$s14SignedSelfLoad10OffsetHalfV13sampleStorages5Int64VyF:
    ldursh x0, [x20, #8]
    ret

.globl _$s14SignedSelfLoad10OffsetWordV13sampleStorages5Int64VyF
_$s14SignedSelfLoad10OffsetWordV13sampleStorages5Int64VyF:
    ldrsw x0, [x20, #8]
    ret

.globl _$s14SignedSelfLoad12UnsignedByteV13sampleStorages5Int64VyF
_$s14SignedSelfLoad12UnsignedByteV13sampleStorages5Int64VyF:
    ldrsb x0, [x20]
    ret

.globl _$s14SignedSelfLoad12UnsignedHalfV13sampleStorages5Int64VyF
_$s14SignedSelfLoad12UnsignedHalfV13sampleStorages5Int64VyF:
    ldrsh x0, [x20]
    ret

.globl _$s14SignedSelfLoad12UnsignedWordV13sampleStorages5Int64VyF
_$s14SignedSelfLoad12UnsignedWordV13sampleStorages5Int64VyF:
    ldrsw x0, [x20]
    // Distinct from SignedBox.signed and the one-NOP FloatBox.signedWord.
    nop
    nop
    ret

.globl _$s14SignedSelfLoad8ZeroByteV13sampleStorages6UInt64VyF
_$s14SignedSelfLoad8ZeroByteV13sampleStorages6UInt64VyF:
    ldrb w0, [x20]
    ret

.globl _$s14SignedSelfLoad8ZeroHalfV13sampleStorages6UInt64VyF
_$s14SignedSelfLoad8ZeroHalfV13sampleStorages6UInt64VyF:
    ldurh w0, [x20]
    ret

.globl _$s14SignedSelfLoad11SignedWByteV13sampleStorages6UInt64VyF
_$s14SignedSelfLoad11SignedWByteV13sampleStorages6UInt64VyF:
    ldrsb w0, [x20]
    ret

.globl _$s14SignedSelfLoad12SignedUWByteV13sampleStorages6UInt64VyF
_$s14SignedSelfLoad12SignedUWByteV13sampleStorages6UInt64VyF:
    ldursb w0, [x20]
    ret

.globl _$s14SignedSelfLoad11SignedWHalfV13sampleStorages6UInt64VyF
_$s14SignedSelfLoad11SignedWHalfV13sampleStorages6UInt64VyF:
    ldrsh w0, [x20]
    ret

.globl _$s14SignedSelfLoad12SignedUWHalfV13sampleStorages6UInt64VyF
_$s14SignedSelfLoad12SignedUWHalfV13sampleStorages6UInt64VyF:
    ldursh w0, [x20]
    ret

.globl _$s14SignedSelfLoad10FloatWByteV13sampleStorageSfyF
_$s14SignedSelfLoad10FloatWByteV13sampleStorageSfyF:
    ldrsb w17, [x20]
    fmov s0, w17
    ret

.globl _$s14SignedSelfLoad10FloatWHalfV13sampleStorageSfyF
_$s14SignedSelfLoad10FloatWHalfV13sampleStorageSfyF:
    ldursh w17, [x20]
    fmov s0, w17
    ret

.globl _$s14SignedSelfLoad9MixedWordV13sampleStorages6UInt64VyF
_$s14SignedSelfLoad9MixedWordV13sampleStorages6UInt64VyF:
    ldrb w8, [x20]
    ldr w0, [x20]
    lsl x8, x8, #32
    orr x0, x0, x8
    ret

.subsections_via_symbols

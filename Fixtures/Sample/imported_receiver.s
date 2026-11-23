.section __TEXT,__text,regular,pure_instructions
.p2align 2
.globl _imported_url_bridge_shape
_imported_url_bridge_shape:
    stp x20, x30, [sp, #-16]!
    mov x20, x0
    mov x0, #4660
    mov x1, #4661
    mov x2, #4662
    mov x3, #4663
    mov x4, #4664
    mov x5, #4665
    mov x6, #4666
    mov x7, #4667
    mov x8, #0
    bl _$s10Foundation3URLV19_bridgeToObjectiveCSo5NSURLCyF
    ldp x20, x30, [sp], #16
    ret

.macro string_words
    mov x0, #0x6261
    movz x1, #0xe200, lsl #48
    // "abc" little endian is 0x636261.
    movz x2, #0x6261
    movk x2, #0x63, lsl #16
    movz x3, #0xe300, lsl #48
    mov x4, #4664
    mov x5, #4665
    mov x6, #4666
    mov x7, #4667
    mov x8, #0
.endmacro

.p2align 2
.globl _imported_string_prefix_address
_imported_string_prefix_address:
    stp x20, x30, [sp, #-32]!
    add x20, sp, #16
    string_words
    bl _$sSS9hasPrefixySbSSF
    ldp x20, x30, [sp], #32
    ret

.p2align 2
.globl _imported_string_prefix_scalar
_imported_string_prefix_scalar:
    stp x20, x30, [sp, #-16]!
    mov x20, #42
    string_words
    adrp x9, _$sSS9hasPrefixySbSSF@GOTPAGE
    ldr x9, [x9, _$sSS9hasPrefixySbSSF@GOTPAGEOFF]
    blr x9
    ldp x20, x30, [sp], #16
    ret

// Pointer input in x0, tuple (UInt,pointer) output in x0/x1. Branch excludes
// the exact straight-line body-transfer optimization; it does not hide an ABI.
.p2align 2
.globl _imported_pointer_words
_imported_pointer_words:
    cbz x0, Lnull_pointer
    mov x1, x0
    mov x0, #0
    ret
Lnull_pointer:
    mov x1, #0
    ret
.p2align 2
.globl _imported_url_bridge_opaque
_imported_url_bridge_opaque:
    stp x20, x30, [sp, #-16]!
    bl _imported_pointer_words
    mov x20, x1
    mov x0, #4660
    mov x1, #4661
    mov x2, #4662
    mov x3, #4663
    mov x4, #4664
    mov x5, #4665
    mov x6, #4666
    mov x7, #4667
    mov x8, #0
    bl _$s10Foundation3URLV19_bridgeToObjectiveCSo5NSURLCyF
    ldp x20, x30, [sp], #16
    ret

.macro prefix_abc
    movz x0, #0x6261
    movk x0, #0x63, lsl #16
    movz x1, #0xe300, lsl #48
.endmacro

.p2align 2
.globl _imported_string_prefix_paired
_imported_string_prefix_paired:
    stp x20, x30, [sp, #-16]!
    bl _$s12ImportedSelf18makeReceiverStringSSyF
    mov x2, x0
    mov x3, x1
    prefix_abc
    mov x20, #42
    bl _$sSS9hasPrefixySbSSF
    ldp x20, x30, [sp], #16
    ret

.p2align 2
.globl _imported_string_prefix_mismatched
_imported_string_prefix_mismatched:
    stp x20, x30, [sp, #-16]!
    bl _$s12ImportedSelf18makeReceiverStringSSyF
    mov x2, x0
    // Same low bytes, but length2 changes "abc" into "ab".
    movz x3, #0xe200, lsl #48
    prefix_abc
    mov x20, #42
    bl _$sSS9hasPrefixySbSSF
    ldp x20, x30, [sp], #16
    ret

.p2align 2
.globl _imported_scalar_receiver_word
_imported_scalar_receiver_word:
    stp x20, x30, [sp, #-16]!
    bl _$s12ImportedSelf18makeReceiverStringSSyF
    // Only the returned low word is the Meter's Int, not the whole String.
    mov x1, x0
    mov x0, #7
    bl _$s12ImportedSelf5MeterV6scaledyS2iF
    ldp x20, x30, [sp], #16
    ret

.p2align 2
.globl _imported_scalar_receiver_whole
_imported_scalar_receiver_whole:
    stp x20, x30, [sp, #-16]!
    bl _$s12ImportedSelf18makeReceiverScalarSiyF
    mov x1, x0
    mov x0, #7
    bl _$s12ImportedSelf5MeterV6scaledyS2iF
    ldp x20, x30, [sp], #16
    ret

.p2align 2
.globl _$s12ImportedSelf11boxWordBitsySiAA9DoubleBoxCF
_$s12ImportedSelf11boxWordBitsySiAA9DoubleBoxCF:
    stp x20, x30, [sp, #-16]!
    ldr x1, [x0, #16]
    mov x0, #3
    bl _$s12ImportedSelf5MeterV6scaledyS2iF
    ldp x20, x30, [sp], #16
    ret

.p2align 2
.globl _$s12ImportedSelf14boxIntegerWordySiAA9DoubleBoxCF
_$s12ImportedSelf14boxIntegerWordySiAA9DoubleBoxCF:
    stp x20, x30, [sp, #-16]!
    ldr x1, [x0, #24]
    mov x0, #3
    bl _$s12ImportedSelf5MeterV6scaledyS2iF
    ldp x20, x30, [sp], #16
    ret

.p2align 2
.globl _$s12ImportedSelf9DoubleBoxC12selfWordBitsSiyF
_$s12ImportedSelf9DoubleBoxC12selfWordBitsSiyF:
    stp x20, x30, [sp, #-16]!
    ldr x1, [x20, #16]
    mov x0, #3
    bl _$s12ImportedSelf5MeterV6scaledyS2iF
    ldp x20, x30, [sp], #16
    ret

.p2align 2
.globl _imported_unused_receiver
_imported_unused_receiver:
    stp x20, x30, [sp, #-16]!
    mov x0, #7
    mov x1, #4660
    bl _$s12ImportedSelf5MeterV6ignoreyS2iF
    ldp x20, x30, [sp], #16
    ret

.p2align 2
.globl _$s12ImportedSelf9DoubleBoxC15selfIntegerWordSiyF
_$s12ImportedSelf9DoubleBoxC15selfIntegerWordSiyF:
    stp x20, x30, [sp, #-16]!
    ldr x1, [x20, #24]
    mov x0, #3
    bl _$s12ImportedSelf5MeterV6scaledyS2iF
    ldp x20, x30, [sp], #16
    ret

.p2align 2
.globl _$s12ImportedSelf9PackedBoxC10packedWordSiyF
_$s12ImportedSelf9PackedBoxC10packedWordSiyF:
    stp x20, x30, [sp, #-16]!
    ldr x1, [x20, #16]
    mov x0, #3
    bl _$s12ImportedSelf5MeterV6scaledyS2iF
    ldp x20, x30, [sp], #16
    ret

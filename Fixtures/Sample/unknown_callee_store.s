// A complete leaf writes 99 through an untracked incoming x10. That pointer
// can alias the async context, even though it has no source argument slot.
// The private-frame control supplies a proved disjoint pointer instead.
.text
.macro async_entry symbol, private, helper
.globl \symbol
.p2align 2
\symbol:
 sub sp, sp, #32
 str x30, [sp, #16]
 mov x9, #7
 str x9, [x22, #16]
.if \private
 mov x10, sp
.endif
 bl \helper
 ldr x0, [x22, #16]
 ldr x1, [x22, #8]
 ldr x30, [sp, #16]
 add sp, sp, #32
 br x1
.endm
async_entry _$s12UnknownStore7unknownSiyYaF, 0, _unknown_store_literal
async_entry _$s12UnknownStore12privateFrameSiyYaF, 1, _unknown_store_literal
async_entry _$s12UnknownStore8crossingSiyYaF, 1, _unknown_store_crossing_literal

.globl _unknown_store_literal
.p2align 2
_unknown_store_literal:
 mov x12, x11
 mov x9, #99
 str x9, [x10, #8]
 ret

// The unknown x11 output prevents a complete MUST transaction. A known
// private base still needs its full write extent checked: sp+48 reaches
// context slot 16 above this async entry's 32-byte frame.
.globl _unknown_store_crossing_literal
.p2align 2
_unknown_store_crossing_literal:
 mov x12, x11
 mov x9, #99
 str x9, [x10, #48]
 ret

// A caller-owned result can be the same untracked store destination.
// This C bridge deliberately passes its address in the nonstandard x10.
.globl _unknown_store_buffer_oracle
.p2align 2
_unknown_store_buffer_oracle:
 sub x10, x0, #8
 b _unknown_store_literal

// A negative displacement writes a private slot below the passed base.
// An unknown x11 output rejects the complete transaction, but must not
// preserve the old value in that slot. Native C passes seven distinct words.
.globl _$s12UnknownStore9frameWordyS2uF
.p2align 2
_$s12UnknownStore9frameWordyS2uF:
 sub sp, sp, #32
 str x30, [sp, #16]
 str x0, [sp, #8]
 add x10, sp, #16
 bl _unknown_store_negative_literal
 ldr x0, [sp, #8]
 ldr x30, [sp, #16]
 add sp, sp, #32
 ret
.globl _unknown_store_negative_literal
.p2align 2
_unknown_store_negative_literal:
 mov x12, x11
 mov x9, #99
 stur x9, [x10, #-8]
 ret

// C wrappers supply x22=context and x10=context+8. The async entries resume
// through context+8; each wrapper checks that pointer and both guard words.
.macro oracle symbol, target, expected
.globl \symbol
.p2align 2
\symbol:
 sub sp, sp, #80
 stp x19, x22, [sp, #48]
 str x30, [sp, #64]
 mov x19, x0
 mov x22, sp
 str x19, [x22]
 mvn x9, x19
 str x9, [x22, #24]
 adr x9, Lresume\@
 str x9, [x22, #8]
 add x10, x22, #8
 bl \target
 cmp x0, #\expected
 b.ne Lfail\@
 ldr x9, [x22, #16]
 cmp x9, #\expected
 b.ne Lfail\@
 ldr x9, [x22]
 cmp x9, x19
 b.ne Lfail\@
 ldr x9, [x22, #24]
 mvn x10, x19
 cmp x9, x10
 b.ne Lfail\@
 ldr x9, [x22, #8]
 adr x10, Lresume\@
 cmp x9, x10
 b.ne Lfail\@
 mov x0, #\expected
 b Lend\@
Lfail\@:
 mov x0, #-1
Lend\@:
 ldr x30, [sp, #64]
 ldp x19, x22, [sp, #48]
 add sp, sp, #80
 ret
Lresume\@:
 ret
.endm
oracle _unknown_store_alias_oracle, _$s12UnknownStore7unknownSiyYaF, 99
oracle _unknown_store_private_oracle, _$s12UnknownStore12privateFrameSiyYaF, 7
oracle _unknown_store_crossing_oracle, _$s12UnknownStore8crossingSiyYaF, 99

.section __TEXT,__swift_as_entry,regular,no_dead_strip
.p2align 2
.long _$s12UnknownStore7unknownSiyYaF-.
.long _$s12UnknownStore12privateFrameSiyYaF-.
.long _$s12UnknownStore8crossingSiyYaF-.
.subsections_via_symbols

// Authored Swift async ABI leaves, matching compiler leaf return sequence
// `ldr x1,[x22,#8]; br x1`. No suspension, context export, or unsupported write.
.text
.p2align 2
.globl _$s15AsyncChronology10beforeLeafSiyYaF
_$s15AsyncChronology10beforeLeafSiyYaF:
 str x30,[sp,#-16]!
 ldr x0,[x22,#16]
 bl _$s15AsyncChronology7observeyS2iF
 mov x8,#7
 str x8,[x22,#16]
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
.p2align 2
.globl _$s15AsyncChronology15conditionalLeafyS2iYaF
_$s15AsyncChronology15conditionalLeafyS2iYaF:
 str x30,[sp,#-16]!
 cbz x0,1f
 mov x8,#7
 str x8,[x22,#16]
1:
 ldr x0,[x22,#16]
 bl _$s15AsyncChronology7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
// Native C adapters install ResumeParent callback in the caller-supplied context.
.p2align 2
.globl _async_chronology_before
_async_chronology_before:
 stp x22,x30,[sp,#-16]!
 mov x22,x0
 adr x8,_async_chronology_callback
 str x8,[x22,#8]
 bl _$s15AsyncChronology10beforeLeafSiyYaF
 ldp x22,x30,[sp],#16
 ret
.p2align 2
.globl _async_chronology_conditional
_async_chronology_conditional:
 stp x22,x30,[sp,#-16]!
 mov x22,x0
 adr x8,_async_chronology_callback
 str x8,[x22,#8]
 mov x0,x1
 bl _$s15AsyncChronology15conditionalLeafyS2iYaF
 ldp x22,x30,[sp],#16
 ret
_async_chronology_callback:
 ret
.p2align 2
.globl _$s15AsyncChronology7observeyS2iF
_$s15AsyncChronology7observeyS2iF:
 ret
.section __TEXT,__swift_as_entry,regular,no_dead_strip
.p2align 2
.long _$s15AsyncChronology10beforeLeafSiyYaF-.
.long _$s15AsyncChronology15conditionalLeafyS2iYaF-.

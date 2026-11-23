// A pointer into a live async context can still reach earlier words by a
// negative displacement. The typed leaf also keeps the physical pointer in
// x0 across a helper whose declared result replaces its logical provenance.
.text
.p2align 2
.globl _$s13AsyncInterior8negativeSiyYaF
_$s13AsyncInterior8negativeSiyYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 add x0,x22,#32
 bl _async_interior_unknown_writer
 ldr x0,[x22,#16]
 bl _$s13AsyncInterior7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
.globl _$s13AsyncInterior8snapshotSiyYaF
_$s13AsyncInterior8snapshotSiyYaF:
 stp x19,x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 ldr x19,[x22,#16]
 add x0,x22,#32
 bl _async_interior_unknown_writer
 mov x0,x19
 bl _$s13AsyncInterior7observeyS2iF
 ldr x1,[x22,#8]
 ldp x19,x30,[sp],#16
 br x1
.globl _$s13AsyncInterior6globalSiyYaF
_$s13AsyncInterior6globalSiyYaF:
 str x30,[sp,#-16]!
 add x9,x22,#32
 adrp x10,_async_interior_export@PAGE
 str x9,[x10,_async_interior_export@PAGEOFF]
 // This fresh value is installed after the interior pointer escaped.
 mov x8,#7
 str x8,[x22,#16]
 mov x0,#0
 mov x8,#0
 mov x9,#0
 mov x10,#0
 bl _async_interior_global_writer
 ldr x0,[x22,#16]
 bl _$s13AsyncInterior7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
.globl _$s13AsyncInterior5typedSiyYaF
_$s13AsyncInterior5typedSiyYaF:
 str x30,[sp,#-16]!
 mov x8,#7
 str x8,[x22,#16]
 add x0,x22,#32
 bl _$s13AsyncInterior6borrowyS2iF
 bl _async_interior_unknown_writer
 ldr x0,[x22,#16]
 bl _$s13AsyncInterior7observeyS2iF
 ldr x1,[x22,#8]
 ldr x30,[sp],#16
 br x1
.globl _async_interior_unknown_writer
_async_interior_unknown_writer:
 ldr x10,[x0]
 mov x8,#11
 stur x8,[x0,#-16]
 ret
.globl _async_interior_global_writer
_async_interior_global_writer:
 adrp x9,_async_interior_export@PAGE
 ldr x0,[x9,_async_interior_export@PAGEOFF]
 ldr x10,[x0]
 mov x8,#11
 stur x8,[x0,#-16]
 ret
.globl _$s13AsyncInterior7observeyS2iF
_$s13AsyncInterior7observeyS2iF:
 ret
.globl _$s13AsyncInterior6borrowyS2iF
_$s13AsyncInterior6borrowyS2iF:
 mov x8,#11
 str x8,[x0]
 ret
.macro adapter name, subject
.globl _async_interior_\name
_async_interior_\name:
 stp x22,x30,[sp,#-16]!
 mov x22,x0
 adrp x8,_async_interior_return@PAGE
 add x8,x8,_async_interior_return@PAGEOFF
 str x8,[x22,#8]
 bl \subject
 ldp x22,x30,[sp],#16
 ret
.endm
adapter negative, _$s13AsyncInterior8negativeSiyYaF
adapter snapshot, _$s13AsyncInterior8snapshotSiyYaF
adapter global, _$s13AsyncInterior6globalSiyYaF
adapter typed, _$s13AsyncInterior5typedSiyYaF
_async_interior_return:
 ret
.data
.p2align 3
_async_interior_export:
 .quad 0
.section __TEXT,__swift_as_entry,regular,no_dead_strip
.long _$s13AsyncInterior8negativeSiyYaF-.
.long _$s13AsyncInterior8snapshotSiyYaF-.
.long _$s13AsyncInterior6globalSiyYaF-.
.long _$s13AsyncInterior5typedSiyYaF-.

// Authored allocation, await-return edge, and merged typed-error exit. Never executed natively.
.text
.p2align 2
.globl _$s10AsyncMerge6chooseyS2iYaAA4CodeVYKF
_$s10AsyncMerge6chooseyS2iYaAA4CodeVYKF:
 stp x22,x30,[sp,#-16]!
 mov x0,#64
 bl _swift_task_alloc
 str x22,[x0]
 adrp x8,_$s10AsyncMerge6chooseyS2iYaAA4CodeVYKFTQ0_@PAGE
 add x8,x8,_$s10AsyncMerge6chooseyS2iYaAA4CodeVYKFTQ0_@PAGEOFF
 str x8,[x0,#8]
 mov x22,x0
 ldp x9,x30,[sp],#16
 b _$s10AsyncMerge5awaityS2iYaF
.globl _$s10AsyncMerge5awaityS2iYaF
_$s10AsyncMerge5awaityS2iYaF:
 ldr x1,[x22,#8]
 br x1
.globl _$s10AsyncMerge6chooseyS2iYaAA4CodeVYKFTQ0_
_$s10AsyncMerge6chooseyS2iYaAA4CodeVYKFTQ0_:
 ldr x22,[x22]
 cbz x0,Lsuccess
 mov w20,#1
 b Ljoin
Lsuccess:
 mov x20,#0
Ljoin:
#ifdef FIXED_STATUS
 mov x20,#FIXED_STATUS
#endif
 ldr x1,[x22,#8]
 mov x0,#13
 br x1
.section __TEXT,__swift_as_entry,regular,no_dead_strip
.long _$s10AsyncMerge6chooseyS2iYaAA4CodeVYKF-.
.section __TEXT,__swift_as_ret,regular,no_dead_strip
.long _$s10AsyncMerge6chooseyS2iYaAA4CodeVYKFTQ0_-.

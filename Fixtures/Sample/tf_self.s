// A function signature specialization that rewrites self's parameter is
// thin (FunctionSignatureOpts.cpp, shouldModifySelfArgument): x20 is no
// self there, whatever a caller left in it. Self is the parameter after the
// formals, so the clause says which case this is.
// - Maker.make has two formals and `Arg[2] = Dead` drops the metatype:
//   caller parks its argument in x20 across the call. Each callee ends in a
//   call that may read x20, so its body does not settle it.
// - Box.count's `Arg[0] = Dead` drops a formal, and self stays in x20:
//   Box.outer passes another Box as it.
.text
.p2align 2
.globl _$s6TfSelf5MakerV4makeyS2i_SitFZTf4nnd_n
_$s6TfSelf5MakerV4makeyS2i_SitFZTf4nnd_n:
    b _$sSS9hasPrefixySbSSF

.globl _$s6TfSelf6calleryS2iF
_$s6TfSelf6calleryS2iF:
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    mov x20, x0
    mov x0, #1
    mov x1, #2
    bl _$s6TfSelf5MakerV4makeyS2i_SitFZTf4nnd_n
    add x0, x0, x20
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    ret

.globl _$s6TfSelf3BoxC5countyS2i_SitFTf4dn_n
_$s6TfSelf3BoxC5countyS2i_SitFTf4dn_n:
    ldr x0, [x20, #0x10]
    ret

.globl _$s6TfSelf3BoxC5outerySiACF
_$s6TfSelf3BoxC5outerySiACF:
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    mov x20, x0
    mov x0, #1
    bl _$s6TfSelf3BoxC5countyS2i_SitFTf4dn_n
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    ret

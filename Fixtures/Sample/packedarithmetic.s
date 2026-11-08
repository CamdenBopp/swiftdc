// Packed operations must not reuse scalar arithmetic semantics.
// `// EXPECT name value`: `?` must decline, a number is the result, `known` any
// proven result. True behaviour of add8B: every byte wraps to 0.
.text
nop
// EXPECT add8B ?
.globl _$s11PackedProbe5add8Bs6UInt64VyF
_$s11PackedProbe5add8Bs6UInt64VyF:
    movi v1.8b, #255
    movi v2.8b, #1
    add v0.8b, v1.8b, v2.8b
    fmov x0, d0
    ret

// EXPECT sub8B ?
.globl _$s11PackedProbe5sub8Bs6UInt64VyF
_$s11PackedProbe5sub8Bs6UInt64VyF:
    movi v1.8b, #0
    movi v2.8b, #1
    sub v0.8b, v1.8b, v2.8b
    fmov x0, d0
    ret

// EXPECT mul8B ?
.globl _$s11PackedProbe5mul8Bs6UInt64VyF
_$s11PackedProbe5mul8Bs6UInt64VyF:
    movi v1.8b, #16
    movi v2.8b, #16
    mul v0.8b, v1.8b, v2.8b
    fmov x0, d0
    ret

// EXPECT add4H ?
.globl _$s11PackedProbe5add4Hs6UInt64VyF
_$s11PackedProbe5add4Hs6UInt64VyF:
    movi v1.4h, #255
    movi v2.4h, #1
    add v0.4h, v1.4h, v2.4h
    fmov x0, d0
    ret

// EXPECT sub4H ?
.globl _$s11PackedProbe5sub4Hs6UInt64VyF
_$s11PackedProbe5sub4Hs6UInt64VyF:
    movi v1.4h, #0
    movi v2.4h, #1
    sub v0.4h, v1.4h, v2.4h
    fmov x0, d0
    ret

// EXPECT mul4H ?
.globl _$s11PackedProbe5mul4Hs6UInt64VyF
_$s11PackedProbe5mul4Hs6UInt64VyF:
    movi v1.4h, #16
    movi v2.4h, #16
    mul v0.4h, v1.4h, v2.4h
    fmov x0, d0
    ret

// EXPECT add2S ?
.globl _$s11PackedProbe5add2Ss6UInt64VyF
_$s11PackedProbe5add2Ss6UInt64VyF:
    movi v1.2s, #255
    movi v2.2s, #1
    add v0.2s, v1.2s, v2.2s
    fmov x0, d0
    ret

// EXPECT sub2S ?
.globl _$s11PackedProbe5sub2Ss6UInt64VyF
_$s11PackedProbe5sub2Ss6UInt64VyF:
    movi v1.2s, #0
    movi v2.2s, #1
    sub v0.2s, v1.2s, v2.2s
    fmov x0, d0
    ret

// EXPECT mul2S ?
.globl _$s11PackedProbe5mul2Ss6UInt64VyF
_$s11PackedProbe5mul2Ss6UInt64VyF:
    movi v1.2s, #16
    movi v2.2s, #16
    mul v0.2s, v1.2s, v2.2s
    fmov x0, d0
    ret

// EXPECT add16B ?
.globl _$s11PackedProbe6add16Bs6UInt64VyF
_$s11PackedProbe6add16Bs6UInt64VyF:
    movi v1.16b, #255
    movi v2.16b, #1
    add v0.16b, v1.16b, v2.16b
    fmov x0, d0
    ret

// EXPECT sub16B ?
.globl _$s11PackedProbe6sub16Bs6UInt64VyF
_$s11PackedProbe6sub16Bs6UInt64VyF:
    movi v1.16b, #0
    movi v2.16b, #1
    sub v0.16b, v1.16b, v2.16b
    fmov x0, d0
    ret

// EXPECT mul16B ?
.globl _$s11PackedProbe6mul16Bs6UInt64VyF
_$s11PackedProbe6mul16Bs6UInt64VyF:
    movi v1.16b, #16
    movi v2.16b, #16
    mul v0.16b, v1.16b, v2.16b
    fmov x0, d0
    ret

// EXPECT add8H ?
.globl _$s11PackedProbe5add8Hs6UInt64VyF
_$s11PackedProbe5add8Hs6UInt64VyF:
    movi v1.8h, #255
    movi v2.8h, #1
    add v0.8h, v1.8h, v2.8h
    fmov x0, d0
    ret

// EXPECT sub8H ?
.globl _$s11PackedProbe5sub8Hs6UInt64VyF
_$s11PackedProbe5sub8Hs6UInt64VyF:
    movi v1.8h, #0
    movi v2.8h, #1
    sub v0.8h, v1.8h, v2.8h
    fmov x0, d0
    ret

// EXPECT mul8H ?
.globl _$s11PackedProbe5mul8Hs6UInt64VyF
_$s11PackedProbe5mul8Hs6UInt64VyF:
    movi v1.8h, #16
    movi v2.8h, #16
    mul v0.8h, v1.8h, v2.8h
    fmov x0, d0
    ret

// EXPECT add4S ?
.globl _$s11PackedProbe5add4Ss6UInt64VyF
_$s11PackedProbe5add4Ss6UInt64VyF:
    movi v1.4s, #255
    movi v2.4s, #1
    add v0.4s, v1.4s, v2.4s
    fmov x0, d0
    ret

// EXPECT sub4S ?
.globl _$s11PackedProbe5sub4Ss6UInt64VyF
_$s11PackedProbe5sub4Ss6UInt64VyF:
    movi v1.4s, #0
    movi v2.4s, #1
    sub v0.4s, v1.4s, v2.4s
    fmov x0, d0
    ret

// EXPECT mul4S ?
.globl _$s11PackedProbe5mul4Ss6UInt64VyF
_$s11PackedProbe5mul4Ss6UInt64VyF:
    movi v1.4s, #16
    movi v2.4s, #16
    mul v0.4s, v1.4s, v2.4s
    fmov x0, d0
    ret

// EXPECT fadd2S ?
.globl _$s11PackedProbe6fadd2Ss6UInt64VyF
_$s11PackedProbe6fadd2Ss6UInt64VyF:
    movi v1.2s, #64, lsl #24
    movi v2.2s, #64, lsl #24
    fadd v0.2s, v1.2s, v2.2s
    fmov x0, d0
    ret

// EXPECT fsub2S ?
.globl _$s11PackedProbe6fsub2Ss6UInt64VyF
_$s11PackedProbe6fsub2Ss6UInt64VyF:
    movi v1.2s, #64, lsl #24
    movi v2.2s, #64, lsl #24
    fsub v0.2s, v1.2s, v2.2s
    fmov x0, d0
    ret

// EXPECT fmul2S ?
.globl _$s11PackedProbe6fmul2Ss6UInt64VyF
_$s11PackedProbe6fmul2Ss6UInt64VyF:
    movi v1.2s, #64, lsl #24
    movi v2.2s, #64, lsl #24
    fmul v0.2s, v1.2s, v2.2s
    fmov x0, d0
    ret

// EXPECT fdiv2S ?
.globl _$s11PackedProbe6fdiv2Ss6UInt64VyF
_$s11PackedProbe6fdiv2Ss6UInt64VyF:
    movi v1.2s, #64, lsl #24
    movi v2.2s, #64, lsl #24
    fdiv v0.2s, v1.2s, v2.2s
    fmov x0, d0
    ret

// EXPECT fneg2S ?
.globl _$s11PackedProbe6fneg2Ss6UInt64VyF
_$s11PackedProbe6fneg2Ss6UInt64VyF:
    movi v1.2s, #64, lsl #24
    movi v2.2s, #64, lsl #24
    fneg v0.2s, v1.2s
    fmov x0, d0
    ret

// EXPECT fabs2S ?
.globl _$s11PackedProbe6fabs2Ss6UInt64VyF
_$s11PackedProbe6fabs2Ss6UInt64VyF:
    movi v1.2s, #64, lsl #24
    movi v2.2s, #64, lsl #24
    fabs v0.2s, v1.2s
    fmov x0, d0
    ret

// EXPECT fsqrt2S ?
.globl _$s11PackedProbe7fsqrt2Ss6UInt64VyF
_$s11PackedProbe7fsqrt2Ss6UInt64VyF:
    movi v1.2s, #64, lsl #24
    movi v2.2s, #64, lsl #24
    fsqrt v0.2s, v1.2s
    fmov x0, d0
    ret

// EXPECT fadd4S ?
.globl _$s11PackedProbe6fadd4Ss6UInt64VyF
_$s11PackedProbe6fadd4Ss6UInt64VyF:
    movi v1.4s, #64, lsl #24
    movi v2.4s, #64, lsl #24
    fadd v0.4s, v1.4s, v2.4s
    fmov x0, d0
    ret

// EXPECT fsub4S ?
.globl _$s11PackedProbe6fsub4Ss6UInt64VyF
_$s11PackedProbe6fsub4Ss6UInt64VyF:
    movi v1.4s, #64, lsl #24
    movi v2.4s, #64, lsl #24
    fsub v0.4s, v1.4s, v2.4s
    fmov x0, d0
    ret

// EXPECT fmul4S ?
.globl _$s11PackedProbe6fmul4Ss6UInt64VyF
_$s11PackedProbe6fmul4Ss6UInt64VyF:
    movi v1.4s, #64, lsl #24
    movi v2.4s, #64, lsl #24
    fmul v0.4s, v1.4s, v2.4s
    fmov x0, d0
    ret

// EXPECT fdiv4S ?
.globl _$s11PackedProbe6fdiv4Ss6UInt64VyF
_$s11PackedProbe6fdiv4Ss6UInt64VyF:
    movi v1.4s, #64, lsl #24
    movi v2.4s, #64, lsl #24
    fdiv v0.4s, v1.4s, v2.4s
    fmov x0, d0
    ret

// EXPECT fneg4S ?
.globl _$s11PackedProbe6fneg4Ss6UInt64VyF
_$s11PackedProbe6fneg4Ss6UInt64VyF:
    movi v1.4s, #64, lsl #24
    movi v2.4s, #64, lsl #24
    fneg v0.4s, v1.4s
    fmov x0, d0
    ret

// EXPECT fabs4S ?
.globl _$s11PackedProbe6fabs4Ss6UInt64VyF
_$s11PackedProbe6fabs4Ss6UInt64VyF:
    movi v1.4s, #64, lsl #24
    movi v2.4s, #64, lsl #24
    fabs v0.4s, v1.4s
    fmov x0, d0
    ret

// EXPECT fsqrt4S ?
.globl _$s11PackedProbe7fsqrt4Ss6UInt64VyF
_$s11PackedProbe7fsqrt4Ss6UInt64VyF:
    movi v1.4s, #64, lsl #24
    movi v2.4s, #64, lsl #24
    fsqrt v0.4s, v1.4s
    fmov x0, d0
    ret

// EXPECT fadd2D ?
.globl _$s11PackedProbe6fadd2Ds6UInt64VyF
_$s11PackedProbe6fadd2Ds6UInt64VyF:
    mov x9, #0x4000000000000000
    dup v1.2d, x9
    dup v2.2d, x9
    fadd v0.2d, v1.2d, v2.2d
    fmov x0, d0
    ret

// EXPECT fsub2D ?
.globl _$s11PackedProbe6fsub2Ds6UInt64VyF
_$s11PackedProbe6fsub2Ds6UInt64VyF:
    mov x9, #0x4000000000000000
    dup v1.2d, x9
    dup v2.2d, x9
    fsub v0.2d, v1.2d, v2.2d
    fmov x0, d0
    ret

// EXPECT fmul2D ?
.globl _$s11PackedProbe6fmul2Ds6UInt64VyF
_$s11PackedProbe6fmul2Ds6UInt64VyF:
    mov x9, #0x4000000000000000
    dup v1.2d, x9
    dup v2.2d, x9
    fmul v0.2d, v1.2d, v2.2d
    fmov x0, d0
    ret

// EXPECT fdiv2D ?
.globl _$s11PackedProbe6fdiv2Ds6UInt64VyF
_$s11PackedProbe6fdiv2Ds6UInt64VyF:
    mov x9, #0x4000000000000000
    dup v1.2d, x9
    dup v2.2d, x9
    fdiv v0.2d, v1.2d, v2.2d
    fmov x0, d0
    ret

// EXPECT fneg2D ?
.globl _$s11PackedProbe6fneg2Ds6UInt64VyF
_$s11PackedProbe6fneg2Ds6UInt64VyF:
    mov x9, #0x4000000000000000
    dup v1.2d, x9
    dup v2.2d, x9
    fneg v0.2d, v1.2d
    fmov x0, d0
    ret

// EXPECT fabs2D ?
.globl _$s11PackedProbe6fabs2Ds6UInt64VyF
_$s11PackedProbe6fabs2Ds6UInt64VyF:
    mov x9, #0x4000000000000000
    dup v1.2d, x9
    dup v2.2d, x9
    fabs v0.2d, v1.2d
    fmov x0, d0
    ret

// EXPECT fsqrt2D ?
.globl _$s11PackedProbe7fsqrt2Ds6UInt64VyF
_$s11PackedProbe7fsqrt2Ds6UInt64VyF:
    mov x9, #0x4000000000000000
    dup v1.2d, x9
    dup v2.2d, x9
    fsqrt v0.2d, v1.2d
    fmov x0, d0
    ret

// EXPECT scalarAdd 8
.globl _$s11PackedProbe9scalarAdds6UInt64VyF
_$s11PackedProbe9scalarAdds6UInt64VyF:
    mov x1, #3
    mov x2, #5
    add x0, x1, x2
    ret

// EXPECT scalarSub 2
.globl _$s11PackedProbe9scalarSubs6UInt64VyF
_$s11PackedProbe9scalarSubs6UInt64VyF:
    mov x1, #7
    mov x2, #5
    sub x0, x1, x2
    ret

// EXPECT scalarMul 15
.globl _$s11PackedProbe9scalarMuls6UInt64VyF
_$s11PackedProbe9scalarMuls6UInt64VyF:
    mov x1, #3
    mov x2, #5
    mul x0, x1, x2
    ret

// EXPECT scalarFloat known
.globl _$s11PackedProbe11scalarFloats6UInt64VyF
_$s11PackedProbe11scalarFloats6UInt64VyF:
    fmov d1, #2.0
    fmov d2, #2.0
    fadd d0, d1, d2
    fmov x0, d0
    ret

// EXPECT fcvtzsPacked ?
.globl _$s11PackedProbe12fcvtzsPackeds6UInt64VyF
_$s11PackedProbe12fcvtzsPackeds6UInt64VyF:
    movi v1.2s, #64, lsl #24
    fcvtzs v0.2s, v1.2s
    fmov x0, d0
    ret

// EXPECT fcvtzuPacked ?
.globl _$s11PackedProbe12fcvtzuPackeds6UInt64VyF
_$s11PackedProbe12fcvtzuPackeds6UInt64VyF:
    movi v1.2s, #64, lsl #24
    fcvtzu v0.2s, v1.2s
    fmov x0, d0
    ret

// EXPECT scvtfPacked ?
.globl _$s11PackedProbe11scvtfPackeds6UInt64VyF
_$s11PackedProbe11scvtfPackeds6UInt64VyF:
    movi v1.2s, #2
    scvtf v0.2s, v1.2s
    fmov x0, d0
    ret

// EXPECT scvtfSimdScalar ?
.globl _$s11PackedProbe15scvtfSimdScalars6UInt64VyF
_$s11PackedProbe15scvtfSimdScalars6UInt64VyF:
    mov x1, #2
    fmov d1, x1
    scvtf d0, d1
    fmov x0, d0
    ret

// EXPECT scvtfGPR known
.globl _$s11PackedProbe8scvtfGPRs6UInt64VyF
_$s11PackedProbe8scvtfGPRs6UInt64VyF:
    mov x1, #2
    scvtf d0, x1
    fmov x0, d0
    ret

// EXPECT ucvtfPacked ?
.globl _$s11PackedProbe11ucvtfPackeds6UInt64VyF
_$s11PackedProbe11ucvtfPackeds6UInt64VyF:
    movi v1.2s, #2
    ucvtf v0.2s, v1.2s
    fmov x0, d0
    ret

// EXPECT ucvtfSimdScalar ?
.globl _$s11PackedProbe15ucvtfSimdScalars6UInt64VyF
_$s11PackedProbe15ucvtfSimdScalars6UInt64VyF:
    mov x1, #2
    fmov d1, x1
    ucvtf d0, d1
    fmov x0, d0
    ret

// EXPECT ucvtfGPR known
.globl _$s11PackedProbe8ucvtfGPRs6UInt64VyF
_$s11PackedProbe8ucvtfGPRs6UInt64VyF:
    mov x1, #2
    ucvtf d0, x1
    fmov x0, d0
    ret

// EXPECT fcvtzsScalar known
.globl _$s11PackedProbe12fcvtzsScalars6UInt64VyF
_$s11PackedProbe12fcvtzsScalars6UInt64VyF:
    fmov d1, #2.0
    fcvtzs x0, d1
    ret

// EXPECT fcvtzuScalar known
.globl _$s11PackedProbe12fcvtzuScalars6UInt64VyF
_$s11PackedProbe12fcvtzuScalars6UInt64VyF:
    fmov d1, #2.0
    fcvtzu x0, d1
    ret

// EXPECT fcvtScalar known
.globl _$s11PackedProbe10fcvtScalars6UInt64VyF
_$s11PackedProbe10fcvtScalars6UInt64VyF:
    fmov d1, #2.0
    fcvt s0, d1
    fmov w0, s0
    ret

.data
.space 1024

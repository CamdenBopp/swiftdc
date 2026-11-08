// Authored ANDS overlap oracle: expected results come from native CSET.
.text
.p2align 2
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_eqs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_nes6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_hss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_los6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_mis6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_pls6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_vss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_vcs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_his6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_lss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_ges6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_lts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_gts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_none_les6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_eqs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_nes6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_hss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_los6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_mis6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_pls6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_vss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_vcs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_his6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_lss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_ges6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_lts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_gts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_none_les6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_eqs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_nes6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_hss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_los6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_mis6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_pls6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_vss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_vcs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_his6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_lss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_ges6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_lts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_gts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_none_les6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_eqs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_nes6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_hss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_los6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_mis6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_pls6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_vss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_vcs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_his6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_lss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_ges6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_lts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_gts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_none_les6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w8, w0, w1, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_eqs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_nes6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_hss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_los6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_mis6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_pls6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_vss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_vcs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_his6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_lss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_ges6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_lts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_gts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_lhs_les6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_eqs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_nes6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_hss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_los6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_mis6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_pls6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_vss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_vcs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_his6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_lss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_ges6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_lts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_gts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_lhs_les6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_eqs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_nes6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_hss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_los6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_mis6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_pls6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_vss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_vcs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_his6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_lss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_ges6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_lts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_gts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_lhs_les6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_eqs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_nes6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_hss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_los6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_mis6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_pls6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_vss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_vcs6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_his6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_lss6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_ges6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_lts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_gts6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_lhs_les6UInt64VyF:
  movz w0, #3
  movz w1, #3
  ands w0, w0, w1, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_eqs6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_nes6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_hss6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_los6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_mis6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_pls6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_vss6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_vcs6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_his6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_lss6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_ges6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_lts6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_gts6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsl_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsl_rhs_les6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_eqs6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_nes6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_hss6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_los6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_mis6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_pls6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_vss6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_vcs6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_his6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_lss6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_ges6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_lts6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_gts6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_lsr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_0_lsr_rhs_les6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_eqs6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_nes6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_hss6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_los6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_mis6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_pls6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_vss6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_vcs6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_his6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_lss6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_ges6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_lts6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_gts6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_asr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_0_asr_rhs_les6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_eqs6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_nes6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_hss6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_los6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_mis6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_pls6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_vss6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_vcs6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_his6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_lss6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_ges6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_lts6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_gts6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_0_ror_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_0_ror_rhs_les6UInt64VyF:
  movz w1, #3
  movz w0, #3
  ands w0, w1, w0, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_eqs6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_nes6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_hss6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_los6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_mis6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_pls6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_vss6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_vcs6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_his6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_lss6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_ges6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_lts6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_gts6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsl_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsl_both_les6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_eqs6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_nes6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_hss6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_los6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_mis6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_pls6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_vss6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_vcs6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_his6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_lss6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_ges6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_lts6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_gts6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_lsr_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_0_lsr_both_les6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_eqs6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_nes6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_hss6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_los6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_mis6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_pls6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_vss6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_vcs6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_his6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_lss6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_ges6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_lts6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_gts6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_asr_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_0_asr_both_les6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_eqs6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_nes6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_hss6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_los6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_mis6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_pls6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_vss6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_vcs6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_his6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_lss6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_ges6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_lts6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_gts6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_0_ror_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_0_ror_both_les6UInt64VyF:
  movz w0, #3
  ands w0, w0, w0, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_eqs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_nes6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_hss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_los6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_mis6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_pls6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_vss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_vcs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_his6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_lss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_ges6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_lts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_gts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_none_les6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_eqs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_nes6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_hss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_los6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_mis6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_pls6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_vss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_vcs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_his6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_lss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_ges6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_lts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_gts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_none_les6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_eqs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_nes6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_hss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_los6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_mis6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_pls6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_vss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_vcs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_his6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_lss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_ges6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_lts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_gts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_none_les6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_eqs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_nes6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_hss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_los6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_mis6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_pls6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_vss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_vcs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_his6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_lss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_ges6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_lts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_gts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_none_les6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_eqs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_nes6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_hss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_los6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_mis6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_pls6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_vss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_vcs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_his6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_lss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_ges6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_lts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_gts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_lhs_les6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_eqs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_nes6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_hss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_los6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_mis6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_pls6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_vss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_vcs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_his6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_lss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_ges6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_lts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_gts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_lhs_les6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_eqs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_nes6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_hss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_los6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_mis6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_pls6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_vss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_vcs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_his6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_lss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_ges6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_lts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_gts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_lhs_les6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_eqs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_nes6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_hss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_los6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_mis6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_pls6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_vss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_vcs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_his6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_lss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_ges6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_lts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_gts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_lhs_les6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  movz w1, #1
  movk w1, #32768, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_eqs6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_nes6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_hss6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_los6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_mis6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_pls6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_vss6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_vcs6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_his6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_lss6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_ges6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_lts6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_gts6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsl_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsl_rhs_les6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_eqs6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_nes6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_hss6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_los6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_mis6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_pls6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_vss6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_vcs6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_his6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_lss6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_ges6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_lts6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_gts6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_lsr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_1_lsr_rhs_les6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_eqs6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_nes6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_hss6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_los6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_mis6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_pls6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_vss6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_vcs6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_his6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_lss6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_ges6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_lts6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_gts6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_asr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_1_asr_rhs_les6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_eqs6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_nes6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_hss6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_los6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_mis6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_pls6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_vss6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_vcs6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_his6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_lss6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_ges6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_lts6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_gts6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_1_ror_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_1_ror_rhs_les6UInt64VyF:
  movz w1, #3
  movk w1, #32768, lsl #16
  movz w0, #1
  movk w0, #32768, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_eqs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_nes6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_hss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_los6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_mis6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_pls6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_vss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_vcs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_his6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_lss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_ges6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_lts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_gts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsl_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsl_both_les6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_eqs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_nes6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_hss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_los6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_mis6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_pls6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_vss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_vcs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_his6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_lss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_ges6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_lts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_gts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_lsr_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_1_lsr_both_les6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_eqs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_nes6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_hss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_los6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_mis6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_pls6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_vss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_vcs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_his6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_lss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_ges6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_lts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_gts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_asr_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_1_asr_both_les6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_eqs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_nes6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_hss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_los6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_mis6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_pls6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_vss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_vcs6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_his6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_lss6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_ges6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_lts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_gts6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_1_ror_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_1_ror_both_les6UInt64VyF:
  movz w0, #3
  movk w0, #32768, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_eqs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_nes6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_hss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_los6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_mis6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_pls6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_vss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_vcs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_his6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_lss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_ges6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_lts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_gts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_none_les6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_eqs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_nes6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_hss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_los6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_mis6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_pls6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_vss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_vcs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_his6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_lss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_ges6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_lts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_gts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_none_les6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_eqs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_nes6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_hss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_los6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_mis6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_pls6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_vss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_vcs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_his6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_lss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_ges6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_lts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_gts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_none_les6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_eqs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_nes6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_hss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_los6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_mis6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_pls6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_vss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_vcs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_his6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_lss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_ges6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_lts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_gts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_none_les6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_eqs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_nes6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_hss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_los6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_mis6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_pls6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_vss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_vcs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_his6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_lss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_ges6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_lts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_gts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_lhs_les6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_eqs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_nes6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_hss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_los6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_mis6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_pls6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_vss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_vcs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_his6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_lss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_ges6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_lts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_gts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_lhs_les6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_eqs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_nes6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_hss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_los6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_mis6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_pls6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_vss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_vcs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_his6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_lss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_ges6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_lts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_gts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_lhs_les6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_eqs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_nes6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_hss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_los6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_mis6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_pls6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_vss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_vcs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_his6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_lss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_ges6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_lts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_gts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_lhs_les6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  movz w1, #61680
  movk w1, #61680, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_eqs6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_nes6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_hss6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_los6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_mis6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_pls6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_vss6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_vcs6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_his6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_lss6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_ges6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_lts6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_gts6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsl_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsl_rhs_les6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_eqs6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_nes6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_hss6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_los6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_mis6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_pls6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_vss6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_vcs6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_his6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_lss6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_ges6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_lts6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_gts6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_lsr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_2_lsr_rhs_les6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_eqs6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_nes6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_hss6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_los6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_mis6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_pls6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_vss6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_vcs6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_his6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_lss6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_ges6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_lts6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_gts6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_asr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_2_asr_rhs_les6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_eqs6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_nes6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_hss6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_los6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_mis6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_pls6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_vss6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_vcs6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_his6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_lss6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_ges6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_lts6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_gts6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_2_ror_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_2_ror_rhs_les6UInt64VyF:
  movz w1, #65535
  movk w1, #65535, lsl #16
  movz w0, #61680
  movk w0, #61680, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_eqs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_nes6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_hss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_los6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_mis6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_pls6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_vss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_vcs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_his6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_lss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_ges6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_lts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_gts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsl_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsl_both_les6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_eqs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_nes6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_hss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_los6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_mis6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_pls6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_vss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_vcs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_his6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_lss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_ges6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_lts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_gts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_lsr_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_2_lsr_both_les6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_eqs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_nes6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_hss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_los6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_mis6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_pls6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_vss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_vcs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_his6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_lss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_ges6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_lts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_gts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_asr_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_2_asr_both_les6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_eqs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_nes6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_hss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_los6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_mis6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_pls6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_vss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_vcs6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_his6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_lss6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_ges6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_lts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_gts6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_2_ror_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_2_ror_both_les6UInt64VyF:
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w0, w0, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_eqs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_nes6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_hss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_los6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_mis6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_pls6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_vss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_vcs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_his6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_lss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_ges6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_lts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_gts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_none_les6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_eqs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_nes6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_hss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_los6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_mis6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_pls6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_vss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_vcs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_his6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_lss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_ges6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_lts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_gts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_none_les6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_eqs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_nes6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_hss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_los6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_mis6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_pls6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_vss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_vcs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_his6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_lss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_ges6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_lts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_gts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_none_les6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_eqs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_nes6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_nes6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_hss6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_hss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_los6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_los6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_mis6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_mis6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_pls6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_pls6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_vss6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_vss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_vcs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_his6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_his6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_lss6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_lss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_ges6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_ges6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_lts6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_lts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_gts6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_gts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_none_les6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_none_les6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w8, w0, w1, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_eqs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_nes6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_hss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_los6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_mis6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_pls6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_vss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_vcs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_his6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_lss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_ges6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_lts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_gts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_lhs_les6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_eqs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_nes6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_hss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_los6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_mis6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_pls6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_vss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_vcs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_his6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_lss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_ges6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_lts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_gts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_lhs_les6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_eqs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_nes6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_hss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_los6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_mis6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_pls6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_vss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_vcs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_his6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_lss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_ges6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_lts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_gts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_lhs_les6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_eqs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_nes6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_hss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_los6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_mis6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_pls6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_vss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_vcs6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_his6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_lss6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_ges6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_lts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_gts6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_lhs_les6UInt64VyF:
  movz w0, #0
  movz w1, #65535
  movk w1, #65535, lsl #16
  ands w0, w0, w1, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_eqs6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_nes6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_hss6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_los6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_mis6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_pls6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_vss6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_vcs6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_his6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_lss6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_ges6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_lts6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_gts6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsl_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsl_rhs_les6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_eqs6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_nes6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_hss6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_los6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_mis6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_pls6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_vss6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_vcs6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_his6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_lss6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_ges6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_lts6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_gts6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_lsr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_3_lsr_rhs_les6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_eqs6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_nes6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_hss6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_los6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_mis6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_pls6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_vss6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_vcs6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_his6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_lss6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_ges6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_lts6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_gts6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_asr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_3_asr_rhs_les6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_eqs6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_nes6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_hss6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_los6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_mis6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_pls6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_vss6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_vcs6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_his6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_lss6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_ges6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_lts6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_gts6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_w_3_ror_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_w_3_ror_rhs_les6UInt64VyF:
  movz w1, #0
  movz w0, #65535
  movk w0, #65535, lsl #16
  ands w0, w1, w0, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_eqs6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_nes6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_hss6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_los6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_mis6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_pls6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_vss6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_vcs6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_his6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_lss6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_ges6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_lts6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_gts6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsl_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsl_both_les6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsl #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_eqs6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_nes6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_hss6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_los6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_mis6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_pls6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_vss6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_vcs6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_his6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_lss6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_ges6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_lts6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_gts6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_lsr_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_3_lsr_both_les6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, lsr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_eqs6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_nes6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_hss6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_los6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_mis6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_pls6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_vss6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_vcs6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_his6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_lss6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_ges6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_lts6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_gts6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_asr_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_3_asr_both_les6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, asr #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_eqs6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_nes6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_nes6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_hss6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_hss6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_los6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_los6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_mis6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_mis6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_pls6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_pls6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_vss6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_vss6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_vcs6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_his6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_his6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_lss6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_lss6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_ges6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_ges6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_lts6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_lts6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_gts6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_gts6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_w_3_ror_both_les6UInt64VyF
_$s11ANDSOverlap20case_w_3_ror_both_les6UInt64VyF:
  movz w0, #0
  ands w0, w0, w0, ror #1
  cset w0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_eqs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_nes6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_hss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_los6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_mis6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_pls6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_vss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_vcs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_his6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_lss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_ges6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_lts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_gts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_none_les6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_eqs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_nes6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_hss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_los6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_mis6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_pls6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_vss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_vcs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_his6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_lss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_ges6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_lts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_gts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_none_les6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_eqs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_nes6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_hss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_los6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_mis6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_pls6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_vss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_vcs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_his6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_lss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_ges6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_lts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_gts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_none_les6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_eqs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_nes6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_hss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_los6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_mis6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_pls6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_vss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_vcs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_his6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_lss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_ges6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_lts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_gts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_none_les6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x8, x0, x1, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_eqs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_nes6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_hss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_los6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_mis6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_pls6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_vss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_vcs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_his6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_lss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_ges6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_lts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_gts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_lhs_les6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_eqs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_nes6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_hss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_los6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_mis6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_pls6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_vss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_vcs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_his6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_lss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_ges6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_lts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_gts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_lhs_les6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_eqs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_nes6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_hss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_los6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_mis6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_pls6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_vss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_vcs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_his6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_lss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_ges6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_lts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_gts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_lhs_les6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_eqs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_nes6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_hss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_los6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_mis6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_pls6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_vss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_vcs6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_his6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_lss6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_ges6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_lts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_gts6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_lhs_les6UInt64VyF:
  movz x0, #3
  movz x1, #3
  ands x0, x0, x1, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_eqs6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_nes6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_hss6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_los6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_mis6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_pls6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_vss6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_vcs6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_his6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_lss6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_ges6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_lts6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_gts6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsl_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsl_rhs_les6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_eqs6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_nes6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_hss6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_los6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_mis6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_pls6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_vss6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_vcs6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_his6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_lss6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_ges6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_lts6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_gts6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_lsr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_0_lsr_rhs_les6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_eqs6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_nes6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_hss6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_los6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_mis6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_pls6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_vss6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_vcs6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_his6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_lss6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_ges6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_lts6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_gts6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_asr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_0_asr_rhs_les6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_eqs6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_nes6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_hss6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_los6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_mis6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_pls6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_vss6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_vcs6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_his6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_lss6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_ges6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_lts6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_gts6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_0_ror_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_0_ror_rhs_les6UInt64VyF:
  movz x1, #3
  movz x0, #3
  ands x0, x1, x0, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_eqs6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_nes6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_hss6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_los6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_mis6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_pls6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_vss6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_vcs6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_his6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_lss6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_ges6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_lts6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_gts6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsl_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsl_both_les6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_eqs6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_nes6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_hss6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_los6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_mis6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_pls6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_vss6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_vcs6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_his6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_lss6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_ges6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_lts6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_gts6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_lsr_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_0_lsr_both_les6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_eqs6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_nes6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_hss6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_los6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_mis6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_pls6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_vss6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_vcs6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_his6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_lss6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_ges6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_lts6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_gts6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_asr_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_0_asr_both_les6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_eqs6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_nes6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_hss6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_los6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_mis6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_pls6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_vss6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_vcs6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_his6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_lss6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_ges6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_lts6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_gts6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_0_ror_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_0_ror_both_les6UInt64VyF:
  movz x0, #3
  ands x0, x0, x0, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_eqs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_nes6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_hss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_los6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_mis6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_pls6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_vss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_vcs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_his6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_lss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_ges6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_lts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_gts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_none_les6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_eqs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_nes6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_hss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_los6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_mis6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_pls6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_vss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_vcs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_his6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_lss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_ges6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_lts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_gts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_none_les6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_eqs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_nes6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_hss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_los6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_mis6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_pls6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_vss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_vcs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_his6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_lss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_ges6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_lts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_gts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_none_les6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_eqs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_nes6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_hss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_los6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_mis6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_pls6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_vss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_vcs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_his6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_lss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_ges6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_lts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_gts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_none_les6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_eqs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_nes6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_hss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_los6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_mis6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_pls6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_vss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_vcs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_his6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_lss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_ges6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_lts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_gts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_lhs_les6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_eqs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_nes6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_hss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_los6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_mis6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_pls6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_vss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_vcs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_his6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_lss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_ges6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_lts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_gts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_lhs_les6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_eqs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_nes6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_hss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_los6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_mis6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_pls6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_vss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_vcs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_his6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_lss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_ges6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_lts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_gts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_lhs_les6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_eqs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_nes6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_hss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_los6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_mis6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_pls6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_vss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_vcs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_his6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_lss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_ges6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_lts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_gts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_lhs_les6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  movz x1, #1
  movk x1, #32768, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_eqs6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_nes6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_hss6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_los6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_mis6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_pls6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_vss6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_vcs6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_his6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_lss6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_ges6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_lts6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_gts6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsl_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsl_rhs_les6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_eqs6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_nes6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_hss6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_los6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_mis6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_pls6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_vss6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_vcs6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_his6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_lss6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_ges6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_lts6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_gts6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_lsr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_1_lsr_rhs_les6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_eqs6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_nes6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_hss6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_los6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_mis6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_pls6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_vss6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_vcs6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_his6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_lss6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_ges6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_lts6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_gts6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_asr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_1_asr_rhs_les6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_eqs6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_nes6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_hss6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_los6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_mis6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_pls6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_vss6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_vcs6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_his6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_lss6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_ges6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_lts6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_gts6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_1_ror_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_1_ror_rhs_les6UInt64VyF:
  movz x1, #3
  movk x1, #32768, lsl #48
  movz x0, #1
  movk x0, #32768, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_eqs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_nes6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_hss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_los6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_mis6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_pls6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_vss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_vcs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_his6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_lss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_ges6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_lts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_gts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsl_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsl_both_les6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_eqs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_nes6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_hss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_los6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_mis6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_pls6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_vss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_vcs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_his6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_lss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_ges6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_lts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_gts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_lsr_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_1_lsr_both_les6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_eqs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_nes6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_hss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_los6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_mis6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_pls6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_vss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_vcs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_his6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_lss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_ges6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_lts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_gts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_asr_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_1_asr_both_les6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_eqs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_nes6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_hss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_los6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_mis6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_pls6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_vss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_vcs6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_his6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_lss6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_ges6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_lts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_gts6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_1_ror_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_1_ror_both_les6UInt64VyF:
  movz x0, #3
  movk x0, #32768, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_eqs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_nes6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_hss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_los6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_mis6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_pls6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_vss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_vcs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_his6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_lss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_ges6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_lts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_gts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_none_les6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_eqs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_nes6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_hss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_los6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_mis6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_pls6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_vss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_vcs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_his6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_lss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_ges6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_lts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_gts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_none_les6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_eqs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_nes6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_hss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_los6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_mis6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_pls6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_vss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_vcs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_his6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_lss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_ges6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_lts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_gts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_none_les6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_eqs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_nes6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_hss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_los6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_mis6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_pls6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_vss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_vcs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_his6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_lss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_ges6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_lts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_gts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_none_les6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_eqs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_nes6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_hss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_los6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_mis6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_pls6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_vss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_vcs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_his6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_lss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_ges6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_lts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_gts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_lhs_les6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_eqs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_nes6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_hss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_los6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_mis6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_pls6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_vss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_vcs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_his6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_lss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_ges6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_lts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_gts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_lhs_les6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_eqs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_nes6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_hss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_los6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_mis6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_pls6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_vss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_vcs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_his6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_lss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_ges6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_lts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_gts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_lhs_les6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_eqs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_nes6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_hss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_los6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_mis6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_pls6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_vss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_vcs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_his6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_lss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_ges6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_lts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_gts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_lhs_les6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  movz x1, #61680
  movk x1, #61680, lsl #16
  movk x1, #61680, lsl #32
  movk x1, #61680, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_eqs6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_nes6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_hss6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_los6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_mis6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_pls6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_vss6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_vcs6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_his6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_lss6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_ges6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_lts6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_gts6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsl_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsl_rhs_les6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_eqs6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_nes6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_hss6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_los6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_mis6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_pls6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_vss6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_vcs6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_his6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_lss6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_ges6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_lts6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_gts6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_lsr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_2_lsr_rhs_les6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_eqs6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_nes6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_hss6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_los6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_mis6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_pls6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_vss6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_vcs6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_his6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_lss6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_ges6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_lts6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_gts6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_asr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_2_asr_rhs_les6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_eqs6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_nes6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_hss6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_los6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_mis6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_pls6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_vss6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_vcs6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_his6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_lss6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_ges6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_lts6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_gts6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_2_ror_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_2_ror_rhs_les6UInt64VyF:
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  movz x0, #61680
  movk x0, #61680, lsl #16
  movk x0, #61680, lsl #32
  movk x0, #61680, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_eqs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_nes6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_hss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_los6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_mis6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_pls6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_vss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_vcs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_his6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_lss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_ges6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_lts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_gts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsl_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsl_both_les6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_eqs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_nes6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_hss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_los6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_mis6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_pls6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_vss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_vcs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_his6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_lss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_ges6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_lts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_gts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_lsr_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_2_lsr_both_les6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_eqs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_nes6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_hss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_los6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_mis6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_pls6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_vss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_vcs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_his6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_lss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_ges6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_lts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_gts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_asr_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_2_asr_both_les6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_eqs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_nes6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_hss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_los6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_mis6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_pls6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_vss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_vcs6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_his6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_lss6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_ges6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_lts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_gts6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_2_ror_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_2_ror_both_les6UInt64VyF:
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x0, x0, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_eqs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_nes6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_hss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_los6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_mis6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_pls6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_vss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_vcs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_his6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_lss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_ges6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_lts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_gts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_none_les6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_eqs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_nes6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_hss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_los6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_mis6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_pls6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_vss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_vcs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_his6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_lss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_ges6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_lts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_gts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_none_les6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_eqs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_nes6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_hss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_los6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_mis6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_pls6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_vss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_vcs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_his6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_lss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_ges6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_lts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_gts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_none_les6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_eqs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_nes6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_nes6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_hss6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_hss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_los6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_los6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_mis6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_mis6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_pls6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_pls6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_vss6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_vss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_vcs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_his6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_his6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_lss6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_lss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_ges6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_ges6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_lts6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_lts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_gts6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_gts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_none_les6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_none_les6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x8, x0, x1, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_eqs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_nes6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_hss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_los6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_mis6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_pls6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_vss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_vcs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_his6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_lss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_ges6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_lts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_gts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_lhs_les6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_eqs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_nes6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_hss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_los6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_mis6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_pls6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_vss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_vcs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_his6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_lss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_ges6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_lts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_gts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_lhs_les6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_eqs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_nes6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_hss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_los6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_mis6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_pls6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_vss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_vcs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_his6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_lss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_ges6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_lts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_gts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_lhs_les6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_eqs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_nes6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_hss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_los6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_mis6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_pls6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_vss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_vcs6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_his6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_lss6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_ges6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_lts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_gts6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_lhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_lhs_les6UInt64VyF:
  movz x0, #0
  movz x1, #65535
  movk x1, #65535, lsl #16
  movk x1, #65535, lsl #32
  movk x1, #65535, lsl #48
  ands x0, x0, x1, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_eqs6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_nes6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_hss6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_los6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_mis6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_pls6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_vss6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_vcs6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_his6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_lss6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_ges6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_lts6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_gts6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsl_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsl_rhs_les6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_eqs6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_nes6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_hss6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_los6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_mis6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_pls6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_vss6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_vcs6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_his6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_lss6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_ges6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_lts6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_gts6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_lsr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_3_lsr_rhs_les6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_eqs6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_nes6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_hss6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_los6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_mis6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_pls6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_vss6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_vcs6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_his6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_lss6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_ges6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_lts6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_gts6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_asr_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_3_asr_rhs_les6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_eqs6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_eqs6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_nes6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_nes6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_hss6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_hss6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_los6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_los6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_mis6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_mis6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_pls6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_pls6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_vss6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_vss6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_vcs6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_vcs6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_his6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_his6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_lss6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_lss6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_ges6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_ges6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_lts6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_lts6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_gts6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_gts6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap19case_x_3_ror_rhs_les6UInt64VyF
_$s11ANDSOverlap19case_x_3_ror_rhs_les6UInt64VyF:
  movz x1, #0
  movz x0, #65535
  movk x0, #65535, lsl #16
  movk x0, #65535, lsl #32
  movk x0, #65535, lsl #48
  ands x0, x1, x0, ror #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_eqs6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_nes6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_hss6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_los6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_mis6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_pls6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_vss6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_vcs6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_his6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_lss6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_ges6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_lts6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_gts6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsl_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsl_both_les6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsl #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_eqs6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_nes6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_hss6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_los6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_mis6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_pls6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_vss6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_vcs6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_his6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_lss6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_ges6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_lts6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_gts6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_lsr_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_3_lsr_both_les6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, lsr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_eqs6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_nes6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_hss6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_los6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_mis6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_pls6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_vss6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_vcs6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_his6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_lss6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_ges6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_lts6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_gts6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_asr_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_3_asr_both_les6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, asr #1
  cset x0, le
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_eqs6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_eqs6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, eq
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_nes6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_nes6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, ne
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_hss6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_hss6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, hs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_los6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_los6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, lo
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_mis6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_mis6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, mi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_pls6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_pls6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, pl
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_vss6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_vss6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, vs
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_vcs6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_vcs6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, vc
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_his6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_his6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, hi
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_lss6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_lss6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, ls
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_ges6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_ges6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, ge
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_lts6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_lts6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, lt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_gts6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_gts6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, gt
  ret
.p2align 2
.globl _$s11ANDSOverlap20case_x_3_ror_both_les6UInt64VyF
_$s11ANDSOverlap20case_x_3_ror_both_les6UInt64VyF:
  movz x0, #0
  ands x0, x0, x0, ror #1
  cset x0, le
  ret

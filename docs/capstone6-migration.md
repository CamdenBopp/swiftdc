# Capstone 5 to 6 migration record

swiftdc's in-process ARM64 decoder moved from Homebrew's libcapstone 5 (the
`CCapstone` system-library target) to Capstone 6.0.100 built from source by
the `capstone` SwiftPM package, because MachOSwiftSection 0.20+ links that
package through swift-capstone and two Capstones in one module graph do not
compile (both clang modules define `cs_insn`). This is the complete list of
what changed, so the same mechanical pass can be applied to code written
against the Capstone 5 names elsewhere (new tracer code for async funclets,
jump tables, integer semantics, flags).

The rename is a word-boundary substitution over every Swift file that imports
the Capstone module; it was generated against capstone 6.0.100's `aarch64.h`
and applied with `sed -E`. Verified: every `disasm`, `disasm --pseudo` and
`xrefs --unreferenced` output over the fixtures, Drafts, Developer and two
dyld-cache images is byte-identical before and after (the one text difference
is on cache images, whose listing is Capstone's own text: branch targets print
`b 0x...` instead of `b #0x...`, which matches llvm-objdump).

## Modules and types

| Capstone 5 | Capstone 6 |
| --- | --- |
| `ARM64_CC_INVALID` | `AArch64CC_Invalid` |
| `ARM64_CC_` | `AArch64CC_` |
| `ARM64_SFT_` | `AARCH64_SFT_` |
| `ARM64_EXT_` | `AARCH64_EXT_` |
| `ARM64_REG_` | `AARCH64_REG_` |
| `ARM64_OP_` | `AARCH64_OP_` |
| `arm64_insn` | `aarch64_insn` |
| `arm64_cc` | `AArch64CC_CondCode` |
| `arm64_shifter` | `aarch64_shifter` |
| `arm64_extender` | `aarch64_extender` |
| `arm64_reg` | `aarch64_reg` |
| `cs_arm64_op` | `cs_aarch64_op` |
| `arm64_op_mem` | `aarch64_op_mem` |
| `CS_ARCH_ARM64` | `CS_ARCH_AARCH64` |
| `import CCapstone$` | `import Ccapstone` |

Also: `cs_option(handle, CS_OPT_DETAIL, value)` takes `UInt` (size_t) for its
value; `cs_detail.arm64` is `cs_detail.aarch64`; `cs_aarch64` has no
`writeback` field, the flag is `cs_detail.writeback`; there is no `V` register
bank (a vector operand is its `Q` register plus a vector-arrangement specifier);
register numbering changed (X0..X28 at 238..266, W0..W30 at 207..237,
FP=2, LR=4, NZCV=5, SP=6, WSP=8, WZR=9, XZR=10, B/D/H/Q/S banks contiguous);
`AArch64CC_EQ` is 0 and `AArch64CC_Invalid` is 16, where Capstone 5 had
`ARM64_CC_INVALID` 0 and `ARM64_CC_EQ` 1.

## Instruction ids with the same name in Capstone 6

Prefix rename only, `ARM64_INS_X` to `AARCH64_INS_X`:

`ADCS`, `ADD`, `ADDS`, `ADR`, `ADRP`, `AND`, `ANDS`, `ASR`, `BICS`, `BLR`, `CAS`, `CASA`, `CASAB`, `CASAH`, `CASAL`, `CASALB`, `CASALH`, `CASB`, `CASH`, `CASL`, `CASLB`, `CASLH`, `CASP`, `CASPA`, `CASPAL`, `CASPL`, `CBNZ`, `CBZ`, `CCMN`, `CCMP`, `CSEL`, `CSINC`, `CSINV`, `CSNEG`, `EOR`, `FABS`, `FADD`, `FCCMP`, `FCCMPE`, `FCMP`, `FCMPE`, `FCVT`, `FCVTZS`, `FCVTZU`, `FDIV`, `FMOV`, `FMUL`, `FNEG`, `FNMUL`, `FSQRT`, `FSUB`, `LDADD`, `LDADDA`, `LDADDAB`, `LDADDAH`, `LDADDAL`, `LDADDALB`, `LDADDALH`, `LDADDB`, `LDADDH`, `LDADDL`, `LDADDLB`, `LDADDLH`, `LDAXP`, `LDCLR`, `LDCLRA`, `LDCLRAB`, `LDCLRAH`, `LDCLRAL`, `LDCLRALB`, `LDCLRALH`, `LDCLRB`, `LDCLRH`, `LDCLRL`, `LDCLRLB`, `LDCLRLH`, `LDEOR`, `LDEORA`, `LDEORAB`, `LDEORAH`, `LDEORAL`, `LDEORALB`, `LDEORALH`, `LDEORB`, `LDEORH`, `LDEORL`, `LDEORLB`, `LDEORLH`, `LDNP`, `LDP`, `LDPSW`, `LDR`, `LDRB`, `LDRH`, `LDRSB`, `LDRSH`, `LDRSW`, `LDSET`, `LDSETA`, `LDSETAB`, `LDSETAH`, `LDSETAL`, `LDSETALB`, `LDSETALH`, `LDSETB`, `LDSETH`, `LDSETL`, `LDSETLB`, `LDSETLH`, `LDSMAX`, `LDSMAXA`, `LDSMAXAB`, `LDSMAXAH`, `LDSMAXAL`, `LDSMAXALB`, `LDSMAXALH`, `LDSMAXB`, `LDSMAXH`, `LDSMAXL`, `LDSMAXLB`, `LDSMAXLH`, `LDSMIN`, `LDSMINA`, `LDSMINAB`, `LDSMINAH`, `LDSMINAL`, `LDSMINALB`, `LDSMINALH`, `LDSMINB`, `LDSMINH`, `LDSMINL`, `LDSMINLB`, `LDSMINLH`, `LDUMAX`, `LDUMAXA`, `LDUMAXAB`, `LDUMAXAH`, `LDUMAXAL`, `LDUMAXALB`, `LDUMAXALH`, `LDUMAXB`, `LDUMAXH`, `LDUMAXL`, `LDUMAXLB`, `LDUMAXLH`, `LDUMIN`, `LDUMINA`, `LDUMINAB`, `LDUMINAH`, `LDUMINAL`, `LDUMINALB`, `LDUMINALH`, `LDUMINB`, `LDUMINH`, `LDUMINL`, `LDUMINLB`, `LDUMINLH`, `LDUR`, `LDURB`, `LDURH`, `LDURSB`, `LDURSH`, `LDURSW`, `LDXP`, `LSL`, `LSR`, `MADD`, `MOV`, `MOVK`, `MOVZ`, `MSUB`, `MUL`, `ORR`, `SBCS`, `SCVTF`, `SDIV`, `ST1`, `ST1B`, `ST1D`, `ST1H`, `ST1Q`, `ST1W`, `ST2`, `ST2B`, `ST2D`, `ST2G`, `ST2H`, `ST2W`, `ST3`, `ST3B`, `ST3D`, `ST3H`, `ST3W`, `ST4`, `ST4B`, `ST4D`, `ST4H`, `ST4W`, `ST64B`, `ST64BV`, `ST64BV0`, `STG`, `STGM`, `STGP`, `STLLR`, `STLLRB`, `STLLRH`, `STLR`, `STLRB`, `STLRH`, `STLUR`, `STLURB`, `STLURH`, `STNP`, `STNT1B`, `STNT1D`, `STNT1H`, `STNT1W`, `STP`, `STR`, `STRB`, `STRH`, `STTR`, `STTRB`, `STTRH`, `STUR`, `STURB`, `STURH`, `STZ2G`, `STZG`, `STZGM`, `SUB`, `SUBS`, `SWP`, `SWPA`, `SWPAB`, `SWPAH`, `SWPAL`, `SWPALB`, `SWPALH`, `SWPB`, `SWPH`, `SWPL`, `SWPLB`, `SWPLH`, `TBNZ`, `TBZ`, `UCVTF`, `UDIV`

## Instruction ids that exist only as aliases in Capstone 6

Capstone 6 reports these with `id` set to the real instruction (`cmp` is
`subs`, `cset` is `csinc`, ...) and the alias in `alias_id`:

| Capstone 5 | Capstone 6 |
| --- | --- |
| `ARM64_INS_CMN` | `AARCH64_INS_ALIAS_CMN` |
| `ARM64_INS_CMP` | `AARCH64_INS_ALIAS_CMP` |
| `ARM64_INS_CSET` | `AARCH64_INS_ALIAS_CSET` |
| `ARM64_INS_CSETM` | `AARCH64_INS_ALIAS_CSETM` |
| `ARM64_INS_STADD` | `AARCH64_INS_ALIAS_STADD` |
| `ARM64_INS_STADDB` | `AARCH64_INS_ALIAS_STADDB` |
| `ARM64_INS_STADDH` | `AARCH64_INS_ALIAS_STADDH` |
| `ARM64_INS_STADDL` | `AARCH64_INS_ALIAS_STADDL` |
| `ARM64_INS_STADDLB` | `AARCH64_INS_ALIAS_STADDLB` |
| `ARM64_INS_STADDLH` | `AARCH64_INS_ALIAS_STADDLH` |
| `ARM64_INS_STCLR` | `AARCH64_INS_ALIAS_STCLR` |
| `ARM64_INS_STCLRB` | `AARCH64_INS_ALIAS_STCLRB` |
| `ARM64_INS_STCLRH` | `AARCH64_INS_ALIAS_STCLRH` |
| `ARM64_INS_STCLRL` | `AARCH64_INS_ALIAS_STCLRL` |
| `ARM64_INS_STCLRLB` | `AARCH64_INS_ALIAS_STCLRLB` |
| `ARM64_INS_STCLRLH` | `AARCH64_INS_ALIAS_STCLRLH` |
| `ARM64_INS_STEOR` | `AARCH64_INS_ALIAS_STEOR` |
| `ARM64_INS_STEORB` | `AARCH64_INS_ALIAS_STEORB` |
| `ARM64_INS_STEORH` | `AARCH64_INS_ALIAS_STEORH` |
| `ARM64_INS_STEORL` | `AARCH64_INS_ALIAS_STEORL` |
| `ARM64_INS_STEORLB` | `AARCH64_INS_ALIAS_STEORLB` |
| `ARM64_INS_STEORLH` | `AARCH64_INS_ALIAS_STEORLH` |
| `ARM64_INS_STSET` | `AARCH64_INS_ALIAS_STSET` |
| `ARM64_INS_STSETB` | `AARCH64_INS_ALIAS_STSETB` |
| `ARM64_INS_STSETH` | `AARCH64_INS_ALIAS_STSETH` |
| `ARM64_INS_STSETL` | `AARCH64_INS_ALIAS_STSETL` |
| `ARM64_INS_STSETLB` | `AARCH64_INS_ALIAS_STSETLB` |
| `ARM64_INS_STSETLH` | `AARCH64_INS_ALIAS_STSETLH` |
| `ARM64_INS_STSMAX` | `AARCH64_INS_ALIAS_STSMAX` |
| `ARM64_INS_STSMAXB` | `AARCH64_INS_ALIAS_STSMAXB` |
| `ARM64_INS_STSMAXH` | `AARCH64_INS_ALIAS_STSMAXH` |
| `ARM64_INS_STSMAXL` | `AARCH64_INS_ALIAS_STSMAXL` |
| `ARM64_INS_STSMAXLB` | `AARCH64_INS_ALIAS_STSMAXLB` |
| `ARM64_INS_STSMAXLH` | `AARCH64_INS_ALIAS_STSMAXLH` |
| `ARM64_INS_STSMIN` | `AARCH64_INS_ALIAS_STSMIN` |
| `ARM64_INS_STSMINB` | `AARCH64_INS_ALIAS_STSMINB` |
| `ARM64_INS_STSMINH` | `AARCH64_INS_ALIAS_STSMINH` |
| `ARM64_INS_STSMINL` | `AARCH64_INS_ALIAS_STSMINL` |
| `ARM64_INS_STSMINLB` | `AARCH64_INS_ALIAS_STSMINLB` |
| `ARM64_INS_STSMINLH` | `AARCH64_INS_ALIAS_STSMINLH` |
| `ARM64_INS_STUMAX` | `AARCH64_INS_ALIAS_STUMAX` |
| `ARM64_INS_STUMAXB` | `AARCH64_INS_ALIAS_STUMAXB` |
| `ARM64_INS_STUMAXH` | `AARCH64_INS_ALIAS_STUMAXH` |
| `ARM64_INS_STUMAXL` | `AARCH64_INS_ALIAS_STUMAXL` |
| `ARM64_INS_STUMAXLB` | `AARCH64_INS_ALIAS_STUMAXLB` |
| `ARM64_INS_STUMAXLH` | `AARCH64_INS_ALIAS_STUMAXLH` |
| `ARM64_INS_STUMIN` | `AARCH64_INS_ALIAS_STUMIN` |
| `ARM64_INS_STUMINB` | `AARCH64_INS_ALIAS_STUMINB` |
| `ARM64_INS_STUMINH` | `AARCH64_INS_ALIAS_STUMINH` |
| `ARM64_INS_STUMINL` | `AARCH64_INS_ALIAS_STUMINL` |
| `ARM64_INS_STUMINLB` | `AARCH64_INS_ALIAS_STUMINLB` |
| `ARM64_INS_STUMINLH` | `AARCH64_INS_ALIAS_STUMINLH` |
| `ARM64_INS_TST` | `AARCH64_INS_ALIAS_TST` |

## Semantic normalisations in `StructuredInsn.decode` (MachineDetail.swift)

A rename alone does not preserve behaviour. Three shapes differ and are
normalised in the decoder so the value tracer sees the Capstone 5 shape:

1. **Alias id.** The id is keyed on `alias_id` when `is_alias`, then folded
   onto the same-named real id where one exists (`AArch64AliasCanon`,
   generated from the header). `cmp`/`tst`/`cset` keep their alias ids and
   the tracer names them `AARCH64_INS_ALIAS_CMP` etc.
2. **Shift aliases.** `lsl x0, x1, #2` arrives as two operands with the shift
   on the source (`[x0, x1 lsl #2]`), and `lsl x0, x1, x2` as `[x0, x1
   lsl_reg x2]` with the register id in the shift value. Both become three
   operands, as Capstone 5 gave.
3. **Post-index.** `ldr x0, [x1], #8` arrives with the amount folded into
   `mem.disp` and `post_index` set. It becomes `mem.disp 0` plus a trailing
   immediate, which is where the tracer reads the writeback delta.

Pinned by `decodesAliasesAsOneIdPerMnemonic` and
`decodesPostIndexAsTrailingImmediate` in StructuredDecodeTests, each proven
red by disabling its normalisation.

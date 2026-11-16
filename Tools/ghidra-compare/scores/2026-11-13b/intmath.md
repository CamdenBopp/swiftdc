# Intmath: Ghidra 12.2 vs swiftdc

Fixtures:
- im.swift (im_O, im_Onone, im_Osize)
- im2.swift (jm_O, jm_Onone, jm_Osize)
- im3.swift (km_O)
- im4.swift (lm_O)
- cm.c (cm_O0, cm_O2, cm_Os)

That is 398 rows. In jm and in cm, the -O/-O2 and -Osize/-Os machine code is byte-identical, so those rows repeat.

**Re-score 2026-11-13b (swiftdc columns only).** Ghidra's columns and renders are unchanged and copied from the 2026-11-13 table. swiftdc was re-scored for the 116 function-builds whose render text changed: 101 cm rows (33 at -O0, 34 each at -O2/-Os), im i8add/u16sum at -O/-Osize (the shared `sub_470`), im2 ubitLt/ubitSel at all levels and ubitNeg at -Onone, and im4 mixU/mixS/uNegConst/uSignedZero. 115 rows changed score (mixU was already CORRECT). Previous swiftdc body totals: 221/30/36/111 overall, 221/27/24/15 Swift, 0/3/12/96 C (C/P/W/D). The interface totals did not move.

## Totals

All 398 rows:

| tool, axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|
| Ghidra interface | 358 | 0 | 34 | 6 |
| Ghidra body | 369 | 0 | 23 | 6 |
| swiftdc interface | 283 | 0 | 0 | 115 |
| swiftdc body | 329 | 37 | 16 | 16 |

Swift fixtures only (287 rows):

| tool, axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|
| Ghidra interface | 252 | 0 | 29 | 6 |
| Ghidra body | 263 | 0 | 18 | 6 |
| swiftdc interface | 283 | 0 | 0 | 4 |
| swiftdc body | 235 | 27 | 14 | 11 |

C fixture only (111 rows):

| tool, axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|
| Ghidra interface | 106 | 0 | 5 | 0 |
| Ghidra body | 106 | 0 | 5 | 0 |
| swiftdc interface | 0 | 0 | 0 | 111 |
| swiftdc body | 94 | 10 | 2 | 5 |

On Swift integer code the two tools are close on volume, but their errors differ in kind.
- **Ghidra:** its errors are interface errors, `void` results and `int` for Int8/UInt16. It also skips one-instruction tail thunks.
- **swiftdc:** its remaining WRONG bodies render a plausible expression that is false.
  - It drops overflow traps: addTrap, absF, subTrapU, negTrap and bound1, 12 rows in the table below (the previous write-up said 13). These renders did not change. The other four WRONG bodies are fullHi/ufullHi at -Onone (call shown without self) and cm between/ubetween at -O0 (bare `return`).
  - The signed-compare-on-UInt defect of the previous run is fixed. ubitLt, ubitSel, mixS, uNegConst, uSignedZero and ubitNeg at -Onone (10 rows) now print `<ˢ`/`>ˢ`/`>=ˢ`, and `ubitLt` no longer reads the same as `ultBool`.
- **On C:** swiftdc now states the returned value as `return // x0 = …` for 101 of 111 bodies (94 CORRECT, 7 PARTIAL: a `?` operand in srem32 at -O0, an elided `sink(…)` argument in branchU/branchS), each checked against the disassembly, with no result claim (interface stays DECLINED for all 111). It still shows only a leaf comment for cnt (all levels) and mod16 at -O2/-Os, and a bare `return` for between and ubetween at -O0.

## Where Ghidra beats swiftdc

1. **im.addTrap, all levels** (truth: `adds x0,x0,x1; b.vs brk`, traps on signed overflow).
   Ghidra: `if (SCARRY8(param_1,param_2)) { SoftwareBreakpoint(1,0x378); } return param_1 + param_2;`
   swiftdc: `return (arg0 + arg1)`. That is the same text it gives the wrapping addWrap, so the trap disappears without a trace.
2. **cm.between and cm.ubetween, O0** (truth: `a > 5 && a < 100`; `a > b && b > 3`).
   Ghidra: both CORRECT.
   swiftdc: `_between { return }`, a bare `return` in a value-returning function. (The previous example here, im2.ubitLt, is fixed: swiftdc now prints `arg0 <ˢ arg1`.)
3. **im3.bound1, O** (truth: `m = a < b ? 7 : a &- b; precondition(m < n); return m`, i.e. `cmp x0,x2; b.hs brk`).
   Ghidra: `if (param_3 <= uVar1) { SoftwareBreakpoint(...) }` keeps the trap, but its `void` prototype loses the result (both axes WRONG).
   swiftdc: `return ((arg0 < arg1) ? 7 : (arg0 - arg1))`. The value is right but the program-logic precondition is silently gone, which is worse for a reader than a missing return.

## Where swiftdc beats Ghidra

1. **im.mulTrap, O/Osize** (truth: returns a*b, traps if smulh != asr(mul,63)).
   Ghidra: `void __s3imO7mulTrapyS2i_SitF(long param_1,long param_2) { if (SUB168(SEXT816(param_1) * SEXT816(param_2),8) != param_1 * param_2 >> 0x3f) trap; return; }`
   swiftdc: `if ((arg0 mulhˢ arg1) != ((arg0 * arg1) >>ˢ 63)) { trap() } else { return (arg0 * arg1) }`. The same `void` loss hits Ghidra's trunc8, i8trap, u16trap, i32trap, divFull, bound2 and Onone fullHi/ufullHi.
2. **im.i8add, Onone** (truth: Int8 result is the low byte of a+b, so 100+100 = -56).
   Ghidra: `int i8add(char param_1,char param_2) { return (int)param_2 + (int)param_1; }` reads 200.
   swiftdc: `-> Swift.Int8 { return (((... + sext8(arg0)) << 56) >>ˢ 56) }` reads -56. Ghidra's i8ret, shlConst and u16sum/u16add (`int`/`short` results) fail the same way.
3. **cm.between, O2/Os** (truth: `a > 5 && a < 100`, lowered `sub x8,x0,#6; cmp x8,#0x5e; cset lo`).
   Ghidra: `return param_1 - 6U < 0x5e;`. In C, long minus unsigned int is long, so this is a signed compare: a = 0 gives -6 < 94, true, where the truth is false.
   swiftdc: `return // x0 = ((arg0 - 6) <ᵁ 94)`, the unsigned compare the machine code performs (a = 0 reads false). swiftdc also declines Onone popc where Ghidra fabricates `CONCAT62(...) & 0xffffffff` (popc(0xffffffff) reads 0x08080020).

## Scoring rules applied

- Ghidra's interface is its decompiled C prototype. A `void` result on a value-returning function is WRONG on both axes. `undefinedN` is typeless and counts as CORRECT when the position is right. A narrow result typed wider (`int` for Int8/UInt16) is a WRONG interface when values leave the narrow range; the body is then judged on the machine bits.
- Comparisons are read in each tool's own type system. Ghidra follows its C types and casts. swiftdc's `<ᵁ`/`>>ˢ` markers say the signedness outright. A plain operator follows the Swift types swiftdc itself declared: plain `<` with a UInt-typed operand is unsigned, which is what its renderer documents (`renderUnsignedComparison`: "proven `UInt` operand → a plain `<`"). In the previous run it also printed that same plain `<` for a signed machine compare on UInt-typed operands, and those rows were WRONG; it now prints `<ˢ` there.
- **2026-11-13b addendum.** `return // x0 = <value>` in a signatureless function is no result claim: the interface result is DECLINED. The commented value is the shown result: right and everything else right is CORRECT, wrong is WRONG, `?` pieces are PARTIAL. A value-returning body that still ends in a bare `return` or shows no value is scored as before. Each commented value was evaluated against the instructions, at edge inputs where it is arithmetic. The C functions declare no types; swiftdc marks every unsigned operator there (`<ᵁ`, `/ᵁ`, `%ᵁ`, `>>ᵁ`), so a plain `<`, `>=`, `/` or `%` on `argN` is read as signed. That reading decides slt32, absl, cselS and branchS (12 rows).
- A dropped trap is WRONG. The one exception is a trap the function's own code proves unreachable from its argument types: an Int8 range after `sxtb`, a masked shift count, `count - 1` on an Array count, the overflow of `endIndex - startIndex` on a valid slice. A trap whose reachability rests on a callee's behaviour (the error-register check after a rethrowing call) still counts.
- This follows the shared RUBRIC.md. A call that omits an argument the callee takes is WRONG; that covers swiftdc's -Onone `multipliedFullWidth(by:)(arg1)` without self and Ghidra's argument-less calls. An argument shown as `?` is PARTIAL. Metadata and witness-table arguments are not required.
- A raw register in a swiftdc body condition (`if (x1 == 0)`) is a PARTIAL body piece. It does not make the interface DECLINED, because the header already names every parameter.
- swiftdc body PARTIAL needs at least one trap, call, store or returned value recovered correctly. A body that keeps only control-flow shape over raw registers plus `return ?` is DECLINED. A function absent from a tool's output, or shown as a bare `sub_XXX`/parameterless C header, is DECLINED.

## Table

| function | level | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| im.addTrap | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc `return (arg0 + arg1)`: the b.vs overflow trap is dropped |
| im.mulTrap | O | WRONG | WRONG | CORRECT | CORRECT | Ghidra types it `void` and drops the returned product; swiftdc exact |
| im.umulTrap | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc trap test `xzr != x8` names an undefined x8 (umulh not shown) |
| im.addWrap | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.mulWrap | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.shlMask | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.shlSmart | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.shrSmart | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.ushrSmart | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.i8add | O | WRONG | CORRECT | DECLINED | CORRECT | shares 0x470 with u16sum (add w0,w1,w0); Ghidra `int` result loses the narrow type (100+100 reads 200); swiftdc `sub_470` now `return // x0 = (((arg1 & 0xffffffff) + (arg0 & 0xffffffff)) & 0xffffffff)`, the exact machine value (was a leaf comment); no name, types or result claim |
| im.i8widen | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.u8widen | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.i16widen | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.i32widen | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.u32widen | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.sdivF | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc divide-by-zero test names raw `x1`; rest exact |
| im.udivF | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc divide-by-zero test names raw `x1`; rest exact |
| im.sremF | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc divide-by-zero test names raw `x1`; rest exact |
| im.uremF | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc divide-by-zero test names raw `x1`; rest exact |
| im.div7 | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.udiv7 | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.rem8 | O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` on negs/csneg; Ghidra csneg exact (ulong types but casts right) |
| im.div8 | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.absF | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the negs/b.vs Int.min trap and returns `?` |
| im.minF | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.umaxF | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.popc | O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` on cnt/addv |
| im.lzc | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.tzc | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.bswap | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.bswap32 | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.rotl | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.rotl13 | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.fullHi | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.ufullHi | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.addOvf | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.ubfx | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.sbfx | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.bfi | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.trunc8 | O | WRONG | WRONG | CORRECT | CORRECT | Ghidra `void trunc8(void)`: parameter and result both lost |
| im.trunc8s | O | DECLINED | DECLINED | CORRECT | CORRECT | `b trunc8` tail thunk: Ghidra emits no function |
| im.exact8 | O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` |
| im.clamp8 | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.ltBool | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.ultBool | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.inRange | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.inRangeU | O | DECLINED | DECLINED | CORRECT | CORRECT | `b inRange` tail thunk: Ghidra emits no function; swiftdc `return inRange(arg0)` |
| im.bigConst | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.negConst | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.negImm | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.andNeg | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.narrowRet | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.u16sum | O | WRONG | CORRECT | DECLINED | CORRECT | shares 0x470 with i8add (add w0,w1,w0); Ghidra `int` result loses the narrow type (100+100 reads 200); swiftdc `sub_470` now `return // x0 = (((arg1 & 0xffffffff) + (arg0 & 0xffffffff)) & 0xffffffff)`, the exact machine value (was a leaf comment); no name, types or result claim |
| im.i16cmp | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.u8cmp | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.selU | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.addTrap | Onone | CORRECT | CORRECT | CORRECT | WRONG | swiftdc `return (arg0 + arg1)`: the adds/b.vs trap is dropped |
| im.mulTrap | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.umulTrap | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc trap test `x8 != 0` names an undefined x8 |
| im.addWrap | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.mulWrap | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.shlMask | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.shlSmart | Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc guards right but every path is `return ?`; Ghidra exact |
| im.shrSmart | Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc guards right but every path is `return ?`; Ghidra exact |
| im.ushrSmart | Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc guards right but every path is `return ?`; Ghidra exact |
| im.i8add | Onone | WRONG | CORRECT | CORRECT | CORRECT | Ghidra `int` result for Int8 (sxtb add not truncated, 100+100 reads 200); swiftdc sign-extends the low byte |
| im.i8widen | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.u8widen | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.i16widen | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.i32widen | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.u32widen | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.sdivF | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc divide-by-zero test names raw `x1`; rest exact |
| im.udivF | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc divide-by-zero test names raw `x1`; rest exact |
| im.sremF | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc divide-by-zero test names raw `x1`; rest exact |
| im.uremF | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc divide-by-zero test names raw `x1`; rest exact |
| im.div7 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.udiv7 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.rem8 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.div8 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.absF | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc shows the generic stdlib call with stack-slot args and `return ?`; Ghidra exact |
| im.minF | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc shows the generic stdlib call with stack-slot args and `return ?`; Ghidra exact |
| im.umaxF | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc shows the generic stdlib call with stack-slot args and `return ?`; Ghidra exact |
| im.popc | Onone | CORRECT | WRONG | CORRECT | DECLINED | Ghidra ORs stale byte popcounts into bits 16-31 after uaddlv (0xffffffff reads 0x08080020); swiftdc `return ?` |
| im.lzc | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.tzc | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.bswap | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.bswap32 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.rotl | Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc only the (unreachable) assertion scaffolding, value `?`; Ghidra exact |
| im.rotl13 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.fullHi | Onone | WRONG | WRONG | CORRECT | WRONG | Ghidra `void f(void)` calling multipliedFullWidth with no args; swiftdc names the call, result `?`; swiftdc WRONG under the shared rubric: `multipliedFullWidth(by:)(arg1)` drops the self argument (x1 = a) |
| im.ufullHi | Onone | WRONG | WRONG | CORRECT | WRONG | Ghidra `void f(void)` calling multipliedFullWidth with no args; swiftdc names the call, result `?`; swiftdc WRONG under the shared rubric: `multipliedFullWidth(by:)(arg1)` drops the self argument (x1 = a) |
| im.addOvf | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.ubfx | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.sbfx | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.bfi | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.trunc8 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.trunc8s | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.exact8 | Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc range guards right, value `?` |
| im.clamp8 | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc shows the generic init(clamping:) call, result `?` |
| im.ltBool | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.ultBool | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.inRange | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.inRangeU | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.bigConst | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.negConst | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.negImm | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.andNeg | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.narrowRet | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.u16sum | Onone | WRONG | CORRECT | CORRECT | CORRECT | Ghidra `int` result for UInt16 (65535+1 reads 65536); swiftdc masks to 16 bits |
| im.i16cmp | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.u8cmp | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.selU | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.addTrap | Osize | CORRECT | CORRECT | CORRECT | WRONG | swiftdc `return (arg0 + arg1)`: the b.vs overflow trap is dropped |
| im.mulTrap | Osize | WRONG | WRONG | CORRECT | CORRECT | Ghidra types it `void` and drops the returned product; swiftdc exact |
| im.umulTrap | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc trap test `xzr != x8` names an undefined x8 (umulh not shown) |
| im.addWrap | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.mulWrap | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.shlMask | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.shlSmart | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.shrSmart | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.ushrSmart | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.i8add | Osize | WRONG | CORRECT | DECLINED | CORRECT | shares 0x470 with u16sum (add w0,w1,w0); Ghidra `int` result loses the narrow type (100+100 reads 200); swiftdc `sub_470` now `return // x0 = (((arg1 & 0xffffffff) + (arg0 & 0xffffffff)) & 0xffffffff)`, the exact machine value (was a leaf comment); no name, types or result claim |
| im.i8widen | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.u8widen | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.i16widen | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.i32widen | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.u32widen | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.sdivF | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc zero test names raw `x1` and the ccmn Int.min/-1 trap condition is `?` |
| im.udivF | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc divide-by-zero test names raw `x1`; rest exact |
| im.sremF | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc zero test names raw `x1` and the ccmn Int.min/-1 trap condition is `?` |
| im.uremF | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc divide-by-zero test names raw `x1`; rest exact |
| im.div7 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.udiv7 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.rem8 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.div8 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.absF | Osize | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the negs/b.vs Int.min trap and returns `?` |
| im.minF | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.umaxF | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.popc | Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` on cnt/addv |
| im.lzc | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.tzc | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.bswap | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.bswap32 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.rotl | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.rotl13 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.fullHi | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.ufullHi | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.addOvf | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.ubfx | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.sbfx | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.bfi | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.trunc8 | Osize | WRONG | WRONG | CORRECT | CORRECT | Ghidra `void trunc8(void)`: parameter and result both lost |
| im.trunc8s | Osize | DECLINED | DECLINED | CORRECT | CORRECT | `b trunc8` tail thunk: Ghidra emits no function |
| im.exact8 | Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` |
| im.clamp8 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.ltBool | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.ultBool | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.inRange | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.inRangeU | Osize | DECLINED | DECLINED | CORRECT | CORRECT | `b inRange` tail thunk: Ghidra emits no function; swiftdc `return inRange(arg0)` |
| im.bigConst | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.negConst | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.negImm | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.andNeg | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.narrowRet | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.u16sum | Osize | WRONG | CORRECT | DECLINED | CORRECT | shares 0x470 with i8add (add w0,w1,w0); Ghidra `int` result loses the narrow type (100+100 reads 200); swiftdc `sub_470` now `return // x0 = (((arg1 & 0xffffffff) + (arg0 & 0xffffffff)) & 0xffffffff)`, the exact machine value (was a leaf comment); no name, types or result claim |
| im.i16cmp | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.u8cmp | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im.selU | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ubitNeg | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ubitLt | O | CORRECT | CORRECT | CORRECT | CORRECT | swiftdc now `arg0 <ˢ arg1`: signed on the UInt bit patterns, matching `cset lt` (was a plain `<`, scored WRONG) |
| im2.iUlt | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.u32lt | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.i32lt | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ubitSel | O | CORRECT | CORRECT | CORRECT | CORRECT | swiftdc now `(arg1 >ˢ arg0) ? arg1 : arg0`: signed, matching the machine `csel gt` (was a plain compare, scored WRONG) |
| im2.two | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.both | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.bothU | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.i8ret | O | WRONG | CORRECT | CORRECT | CORRECT | Ghidra returns `int` product for an Int8 result; value exceeds Int8 range (100*100) |
| im2.i8sum | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.u8sum | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.i8trap | O | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `void`, result dropped; swiftdc trap condition has `?` operands for the sxtb of the sum |
| im2.u16trap | O | WRONG | WRONG | CORRECT | CORRECT | Ghidra `void`, result dropped |
| im2.i32trap | O | WRONG | WRONG | CORRECT | CORRECT | Ghidra `void`, result dropped |
| im2.subTrapU | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the b.lo trap (traps iff b > a) |
| im2.negTrap | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the b.vs trap (Int.min) |
| im2.shlConst | O | WRONG | CORRECT | CORRECT | CORRECT | Ghidra returns `int` p<<3 for an Int8 result; value exceeds Int8 range |
| im2.sar8 | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.shr8u | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.divFull | O | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `void`, quotient dropped; swiftdc uses raw x2/x0/x1 in the two trap conditions |
| im2.ifNeg | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ifUHigh | O | DECLINED | DECLINED | CORRECT | CORRECT | tail branch to ifNeg; absent from Ghidra output |
| im2.ifU32 | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ifI32neg | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ifI8 | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.mask32 | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.neg32 | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.notF | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.eor | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.madd | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.msub | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.mneg | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.lsl32 | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.shiftBig | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.smull | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.umull | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ubitNeg | Onone | CORRECT | CORRECT | CORRECT | CORRECT | swiftdc now `arg0 <ˢ 0`: signed, true iff the top bit is set, matching `subs; cset lt` (was plain `< 0`, scored WRONG) |
| im2.ubitLt | Onone | CORRECT | CORRECT | CORRECT | CORRECT | swiftdc now `arg0 <ˢ arg1`: signed on the UInt bit patterns, matching `cset lt` (was a plain `<`, scored WRONG) |
| im2.iUlt | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.u32lt | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.i32lt | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ubitSel | Onone | CORRECT | CORRECT | CORRECT | CORRECT | swiftdc now `(arg1 >=ˢ arg0) ? arg1 : arg0`: signed, matching the machine `b.ge` (was a plain compare, scored WRONG) |
| im2.two | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.both | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.bothU | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.i8ret | Onone | WRONG | CORRECT | CORRECT | CORRECT | Ghidra returns `int` product for an Int8 result; value exceeds Int8 range |
| im2.i8sum | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.u8sum | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.i8trap | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc trap condition has `?` operands |
| im2.u16trap | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.i32trap | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.subTrapU | Onone | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the b.lo trap |
| im2.negTrap | Onone | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the vs trap |
| im2.shlConst | Onone | WRONG | CORRECT | CORRECT | CORRECT | Ghidra returns `int` p<<3 for an Int8 result |
| im2.sar8 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.shr8u | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.divFull | Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `void f(void)` calls dividingFullWidth with no args or result; swiftdc names the callee, args and result `?` |
| im2.ifNeg | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ifUHigh | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ifU32 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ifI32neg | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ifI8 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.mask32 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.neg32 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.notF | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.eor | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.madd | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.msub | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.mneg | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.lsl32 | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.shiftBig | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.smull | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.umull | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc trap condition reads raw x8 (umulh); trap unreachable |
| im2.ubitNeg | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ubitLt | Osize | CORRECT | CORRECT | CORRECT | CORRECT | swiftdc now `arg0 <ˢ arg1`: signed on the UInt bit patterns, matching `cset lt` (was a plain `<`, scored WRONG) |
| im2.iUlt | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.u32lt | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.i32lt | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ubitSel | Osize | CORRECT | CORRECT | CORRECT | CORRECT | swiftdc now `(arg1 >ˢ arg0) ? arg1 : arg0`: signed, matching the machine `csel gt` (was a plain compare, scored WRONG) |
| im2.two | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.both | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.bothU | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.i8ret | Osize | WRONG | CORRECT | CORRECT | CORRECT | Ghidra returns `int` product for an Int8 result; value exceeds Int8 range (100*100) |
| im2.i8sum | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.u8sum | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.i8trap | Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `void`, result dropped; swiftdc trap condition has `?` operands for the sxtb of the sum |
| im2.u16trap | Osize | WRONG | WRONG | CORRECT | CORRECT | Ghidra `void`, result dropped |
| im2.i32trap | Osize | WRONG | WRONG | CORRECT | CORRECT | Ghidra `void`, result dropped |
| im2.subTrapU | Osize | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the b.lo trap (traps iff b > a) |
| im2.negTrap | Osize | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the b.vs trap (Int.min) |
| im2.shlConst | Osize | WRONG | CORRECT | CORRECT | CORRECT | Ghidra returns `int` p<<3 for an Int8 result; value exceeds Int8 range |
| im2.sar8 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.shr8u | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.divFull | Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `void`, quotient dropped; swiftdc uses raw x2/x0/x1 in the two trap conditions |
| im2.ifNeg | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ifUHigh | Osize | DECLINED | DECLINED | CORRECT | CORRECT | tail branch to ifNeg; absent from Ghidra output |
| im2.ifU32 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ifI32neg | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.ifI8 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.mask32 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.neg32 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.notF | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.eor | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.madd | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.msub | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.mneg | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.lsl32 | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.shiftBig | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.smull | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im2.umull | Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| cm.promote | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = sext32(arg0) * sext32(arg1)` spelled with `<< 32 >>ˢ 32`, exact (ldrsw; mul) (was a leaf comment); no parameters or result claimed |
| cm.promoteU | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 & 0xffffffff) * (arg1 & 0xffffffff))`, exact (umull) (was a leaf comment); no parameters or result claimed |
| cm.wrap32 | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (((arg0 & 0xffffffff) * (arg1 & 0xffffffff)) & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.zext | O0 | CORRECT | CORRECT | DECLINED | CORRECT | Ghidra `undefined4 zext(undefined4)` narrows the 64-bit result but the value is unchanged; swiftdc now `return // x0 = (arg0 & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.sext | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (((arg0 & 0xffffffff) << 32) >>ˢ 32)`, exact (was a leaf comment); no parameters or result claimed |
| cm.ult32 | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 & 0xffffffff) <ᵁ (arg1 & 0xffffffff))`, exact (`cset lo`) (was a leaf comment); no parameters or result claimed |
| cm.slt32 | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (sext32(arg0) < sext32(arg1))` with explicit `>>ˢ 32` operands, exact (`cset lt`) (was a leaf comment); no parameters or result claimed |
| cm.ucmpneg | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = carry(a + 16) & (a + 16 != 0)` on 32 bits: the `hi` of `cmn w0,#16`, true exactly for a > 0xfffffff0 (checked at 0xfffffff0, 0xfffffff1, 0xffffffff, 0) (was a leaf comment); no parameters or result claimed |
| cm.sdiv32 | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((sext32(arg0) / sext32(arg1)) & 0xffffffff)`, exact (INT_MIN / -1 gives 0x80000000 as sdiv does) (was a leaf comment); no parameters or result claimed |
| cm.udiv32 | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (((arg0 & 0xffffffff) /ᵁ (arg1 & 0xffffffff)) & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.srem32 | O0 | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc now `return // x0 = (a - ((? / ?) & 0xffffffff) * b) & 0xffffffff`: shape and outer operands right, the quotient's two operands are `?` (was a leaf comment); no parameters or result claimed |
| cm.sdivc | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 / -3)`, exact (sdiv by -3) (was a leaf comment); no parameters or result claimed |
| cm.mod16 | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 % 16)`, right (sdiv; mul; sub = truncating signed remainder) (was a leaf comment); no parameters or result claimed |
| cm.umod16 | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 %ᵁ 16)`, exact (was a leaf comment); no parameters or result claimed |
| cm.sarv | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 >>ˢ (arg1 & 63))`, exact (was a leaf comment); no parameters or result claimed |
| cm.shrv | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 >>ᵁ (arg1 & 63))`, exact (was a leaf comment); no parameters or result claimed |
| cm.sar32 | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((sext32(arg0) >>ˢ (arg1 & 31)) & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.bigimm | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = 0xffff0000ffff0000`, exact (was a leaf comment); no parameters or result claimed |
| cm.negimm | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 * -7)`, exact (was a leaf comment); no parameters or result claimed |
| cm.cnt | O0 | CORRECT | WRONG | DECLINED | DECLINED | Ghidra O0 `CONCAT62(uVar2>>0x10, NEON_uaddlv(...)) & 0xffffffff` keeps bits 16..31 of the byte counts; uaddlv zeroes them; swiftdc: header shows no parameters or result, body only a leaf comment |
| cm.clz32 | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (leadingZeros32((arg0 & 0xffffffff)) & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.ctz | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = leadingZeros64(bitReverse64(arg0))`, exact (rbit + clz) (was a leaf comment); no parameters or result claimed |
| cm.absl | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 >= 0) ? arg0 : -arg0)`, right (`tbz x8,#63`; was bare `return`, WRONG); no parameters or result claimed |
| cm.bitf | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (((arg0 & 0xffffffff) >>ᵁ 3) & 31)`, exact (ubfx) (was a leaf comment); no parameters or result claimed |
| cm.sbitf | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((sext32((arg0 << 20) & 0xffffffff) >>ˢ 27) & 0xffffffff)`, exact (lsl w; asr w) (was a leaf comment); no parameters or result claimed |
| cm.ovf | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc `mem64[arg2] = (arg0 + arg1)` and now `return // x0 = (same operand signs & result sign differs)`: the V flag of `adds`, right (was: flag dropped, WRONG); no parameters or result claimed |
| cm.u16add | O0 | WRONG | CORRECT | DECLINED | CORRECT | Ghidra `short u16add(short,short)`: unsigned short result 0x8000..0xffff reads negative; swiftdc now `return // x0 = (((arg0 & 0xffff) + (arg1 & 0xffff)) & 0xffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.s8ret | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((((arg0 & 0xffffffff) << 56) >>ˢ 56) & 0xffffffff)`, exact (sxtb w0) (was a leaf comment); no parameters or result claimed |
| cm.fromS8 | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = sext32((sext8(arg0) << 1) & 0xffffffff)`, exact (ldrsb; lsl w; sxtw) (was a leaf comment); no parameters or result claimed |
| cm.fromU16 | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = sext32(((arg0 & 0xffff) + 1) & 0xffffffff)`, exact (ldrh; add w; sxtw) (was a leaf comment); no parameters or result claimed |
| cm.between | O0 | CORRECT | CORRECT | DECLINED | WRONG | swiftdc O0 body is a bare `return`; function returns a value |
| cm.ubetween | O0 | CORRECT | CORRECT | DECLINED | WRONG | swiftdc O0 body is a bare `return`; function returns a value |
| cm.callu | O0 | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `sink(…)`: argument (sxtw of arg) elided |
| cm.cselU | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = sext32((arg0 >=ᵁ arg1) ? 11 : 22)`, exact (was a leaf comment); no parameters or result claimed |
| cm.cselS | O0 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = sext32((arg0 >= arg1) ? 11 : 22)`, right (`csel ge`; plain `>=` read as signed on an untyped argN) (was a leaf comment); no parameters or result claimed |
| cm.branchU | O0 | CORRECT | WRONG | DECLINED | PARTIAL | Ghidra O0 shows `_sink(param_1 - param_2,1)`: two args, sink takes one (x0=1); swiftdc `if (arg0 >ᵁ arg1) { sink(…) }` then `return // x0 = 3`: condition and 3 right, sink argument (1) elided (was bare `return`, WRONG); no parameters or result claimed |
| cm.branchS | O0 | CORRECT | WRONG | DECLINED | PARTIAL | Ghidra O0 shows `_sink(param_1 - param_2,1)`: two args, sink takes one (x0=1); swiftdc `if (arg0 > arg1) { sink(…) }` then `return // x0 = 3`: condition (signed) and 3 right, sink argument (1) elided (was bare `return`, WRONG); no parameters or result claimed |
| cm.promote | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = sext32(arg1) * sext32(arg0)` spelled with `<< 32 >>ˢ 32`, exact (smull) (was a leaf comment); no parameters or result claimed |
| cm.promoteU | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg1 & 0xffffffff) * (arg0 & 0xffffffff))`, exact (umull) (was a leaf comment); no parameters or result claimed |
| cm.wrap32 | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (((arg1 & 0xffffffff) * (arg0 & 0xffffffff)) & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.zext | O2 | CORRECT | CORRECT | DECLINED | CORRECT | Ghidra `undefined4 zext(undefined4)` narrows the 64-bit result but the value is unchanged; swiftdc now `return // x0 = (arg0 & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.sext | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (((arg0 & 0xffffffff) << 32) >>ˢ 32)`, exact (was a leaf comment); no parameters or result claimed |
| cm.ult32 | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 & 0xffffffff) <ᵁ (arg1 & 0xffffffff))`, exact (`cset lo`) (was a leaf comment); no parameters or result claimed |
| cm.slt32 | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (sext32(arg0) < sext32(arg1))` with explicit `>>ˢ 32` operands, exact (`cset lt`) (was a leaf comment); no parameters or result claimed |
| cm.ucmpneg | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = carry(a + 16) & (a + 16 != 0)` on 32 bits: the `hi` of `cmn w0,#16`, true exactly for a > 0xfffffff0 (checked at 0xfffffff0, 0xfffffff1, 0xffffffff, 0) (was a leaf comment); no parameters or result claimed |
| cm.sdiv32 | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((sext32(arg0) / sext32(arg1)) & 0xffffffff)`, exact (INT_MIN / -1 gives 0x80000000 as sdiv does) (was a leaf comment); no parameters or result claimed |
| cm.udiv32 | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (((arg0 & 0xffffffff) /ᵁ (arg1 & 0xffffffff)) & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.srem32 | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (a - (sext32(a) / sext32(b)) * b) & 0xffffffff`, exact (sdiv + msub) (was a leaf comment); no parameters or result claimed |
| cm.sdivc | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 / -3)`: the smulh magic sequence folded; checked equal on 100k values and the Int.min/max edges (was a leaf comment); no parameters or result claimed |
| cm.mod16 | O2 | WRONG | CORRECT | DECLINED | DECLINED | Ghidra types a signed long remainder as `ulong mod16(ulong)`, so a negative result reads as huge; swiftdc: header shows no parameters or result, body only a leaf comment |
| cm.umod16 | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 & 15)`, exact (was a leaf comment); no parameters or result claimed |
| cm.sarv | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 >>ˢ (arg1 & 63))`, exact (was a leaf comment); no parameters or result claimed |
| cm.shrv | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 >>ᵁ (arg1 & 63))`, exact (was a leaf comment); no parameters or result claimed |
| cm.sar32 | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((sext32(arg0) >>ˢ (arg1 & 31)) & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.bigimm | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = 0xffff0000ffff0000`, exact (was a leaf comment); no parameters or result claimed |
| cm.negimm | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 - (arg0 << 3))`, exact (= -7a) (was a leaf comment); no parameters or result claimed |
| cm.cnt | O2 | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc: header shows no parameters or result, body only a leaf comment |
| cm.clz32 | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (leadingZeros32((arg0 & 0xffffffff)) & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.ctz | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = leadingZeros64(bitReverse64(arg0))`, exact (rbit + clz) (was a leaf comment); no parameters or result claimed |
| cm.absl | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 < 0) ? -arg0 : arg0)`, right (`cneg mi`; plain `<` read as signed on an untyped argN) (was a leaf comment); no parameters or result claimed |
| cm.bitf | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (((arg0 & 0xffffffff) >>ᵁ 3) & 31)`, exact (ubfx) (was a leaf comment); no parameters or result claimed |
| cm.sbitf | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = sign-extended bits 7..11, & 0xffffffff`, exact (sbfx w0,w0,#7,#5) (was a leaf comment); no parameters or result claimed |
| cm.ovf | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc `mem64[arg2] = (arg0 + arg1)` and now `return // x0 = (same operand signs & result sign differs)`: the V flag of `adds`, right (was: flag dropped, WRONG); no parameters or result claimed |
| cm.u16add | O2 | WRONG | CORRECT | DECLINED | CORRECT | Ghidra `short u16add(short,short)`: unsigned short result 0x8000..0xffff reads negative; swiftdc now `return // x0 = (((arg1 & 0xffffffff) + (arg0 & 0xffffffff)) & 0xffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.s8ret | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((((arg0 & 0xffffffff) << 56) >>ˢ 56) & 0xffffffff)`, exact (sxtb w0) (was a leaf comment); no parameters or result claimed |
| cm.fromS8 | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = sext32((arg0 << 1) & 0xffffffff)`, exact (lsl w; sxtw) (was a leaf comment); no parameters or result claimed |
| cm.fromU16 | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 & 0xffffffff) + 1)`, exact (was a leaf comment); no parameters or result claimed |
| cm.between | O2 | CORRECT | WRONG | DECLINED | CORRECT | Ghidra `param_1 - 6U < 0x5e`: in C long-unsigned int is long, so the compare is signed; a=0 gives true, truth false; swiftdc now `return // x0 = ((arg0 - 6) <ᵁ 94)`, exact (`sub; cmp #0x5e; cset lo`: a=0 false, 6 true, 99 true, 100 false) (was a leaf comment); no parameters or result claimed |
| cm.ubetween | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 >ᵁ arg1) && (arg1 >ᵁ 3))`, exact (cmp; ccmp hi; cset hi) (was a leaf comment); no parameters or result claimed |
| cm.callu | O2 | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `sink(…)`: argument (sxtw of arg) elided |
| cm.cselU | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 <ᵁ arg1) ? 22 : 11)`, exact (was a leaf comment); no parameters or result claimed |
| cm.cselS | O2 | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 < arg1) ? 22 : 11)`, right (`csel lt`; plain `<` read as signed on an untyped argN) (was a leaf comment); no parameters or result claimed |
| cm.branchU | O2 | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `if (arg0 >ᵁ arg1) { sink(…) }` then `return // x0 = 3`: condition and 3 right, sink argument (1) elided (was bare `return`, WRONG); no parameters or result claimed |
| cm.branchS | O2 | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `if (arg0 > arg1) { sink(…) }` then `return // x0 = 3`: condition (signed) and 3 right, sink argument (1) elided (was bare `return`, WRONG); no parameters or result claimed |
| cm.promote | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = sext32(arg1) * sext32(arg0)` spelled with `<< 32 >>ˢ 32`, exact (smull) (was a leaf comment); no parameters or result claimed |
| cm.promoteU | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg1 & 0xffffffff) * (arg0 & 0xffffffff))`, exact (umull) (was a leaf comment); no parameters or result claimed |
| cm.wrap32 | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (((arg1 & 0xffffffff) * (arg0 & 0xffffffff)) & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.zext | Os | CORRECT | CORRECT | DECLINED | CORRECT | Ghidra `undefined4 zext(undefined4)` narrows the 64-bit result but the value is unchanged; swiftdc now `return // x0 = (arg0 & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.sext | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (((arg0 & 0xffffffff) << 32) >>ˢ 32)`, exact (was a leaf comment); no parameters or result claimed |
| cm.ult32 | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 & 0xffffffff) <ᵁ (arg1 & 0xffffffff))`, exact (`cset lo`) (was a leaf comment); no parameters or result claimed |
| cm.slt32 | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (sext32(arg0) < sext32(arg1))` with explicit `>>ˢ 32` operands, exact (`cset lt`) (was a leaf comment); no parameters or result claimed |
| cm.ucmpneg | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = carry(a + 16) & (a + 16 != 0)` on 32 bits: the `hi` of `cmn w0,#16`, true exactly for a > 0xfffffff0 (checked at 0xfffffff0, 0xfffffff1, 0xffffffff, 0) (was a leaf comment); no parameters or result claimed |
| cm.sdiv32 | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((sext32(arg0) / sext32(arg1)) & 0xffffffff)`, exact (INT_MIN / -1 gives 0x80000000 as sdiv does) (was a leaf comment); no parameters or result claimed |
| cm.udiv32 | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (((arg0 & 0xffffffff) /ᵁ (arg1 & 0xffffffff)) & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.srem32 | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (a - (sext32(a) / sext32(b)) * b) & 0xffffffff`, exact (sdiv + msub) (was a leaf comment); no parameters or result claimed |
| cm.sdivc | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 / -3)`: the smulh magic sequence folded; checked equal on 100k values and the Int.min/max edges (was a leaf comment); no parameters or result claimed |
| cm.mod16 | Os | WRONG | CORRECT | DECLINED | DECLINED | Ghidra types a signed long remainder as `ulong mod16(ulong)`, so a negative result reads as huge; swiftdc: header shows no parameters or result, body only a leaf comment |
| cm.umod16 | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 & 15)`, exact (was a leaf comment); no parameters or result claimed |
| cm.sarv | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 >>ˢ (arg1 & 63))`, exact (was a leaf comment); no parameters or result claimed |
| cm.shrv | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 >>ᵁ (arg1 & 63))`, exact (was a leaf comment); no parameters or result claimed |
| cm.sar32 | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((sext32(arg0) >>ˢ (arg1 & 31)) & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.bigimm | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = 0xffff0000ffff0000`, exact (was a leaf comment); no parameters or result claimed |
| cm.negimm | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (arg0 - (arg0 << 3))`, exact (= -7a) (was a leaf comment); no parameters or result claimed |
| cm.cnt | Os | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc: header shows no parameters or result, body only a leaf comment |
| cm.clz32 | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (leadingZeros32((arg0 & 0xffffffff)) & 0xffffffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.ctz | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = leadingZeros64(bitReverse64(arg0))`, exact (rbit + clz) (was a leaf comment); no parameters or result claimed |
| cm.absl | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 < 0) ? -arg0 : arg0)`, right (`cneg mi`; plain `<` read as signed on an untyped argN) (was a leaf comment); no parameters or result claimed |
| cm.bitf | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = (((arg0 & 0xffffffff) >>ᵁ 3) & 31)`, exact (ubfx) (was a leaf comment); no parameters or result claimed |
| cm.sbitf | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = sign-extended bits 7..11, & 0xffffffff`, exact (sbfx w0,w0,#7,#5) (was a leaf comment); no parameters or result claimed |
| cm.ovf | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc `mem64[arg2] = (arg0 + arg1)` and now `return // x0 = (same operand signs & result sign differs)`: the V flag of `adds`, right (was: flag dropped, WRONG); no parameters or result claimed |
| cm.u16add | Os | WRONG | CORRECT | DECLINED | CORRECT | Ghidra `short u16add(short,short)`: unsigned short result 0x8000..0xffff reads negative; swiftdc now `return // x0 = (((arg1 & 0xffffffff) + (arg0 & 0xffffffff)) & 0xffff)`, exact (was a leaf comment); no parameters or result claimed |
| cm.s8ret | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((((arg0 & 0xffffffff) << 56) >>ˢ 56) & 0xffffffff)`, exact (sxtb w0) (was a leaf comment); no parameters or result claimed |
| cm.fromS8 | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = sext32((arg0 << 1) & 0xffffffff)`, exact (lsl w; sxtw) (was a leaf comment); no parameters or result claimed |
| cm.fromU16 | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 & 0xffffffff) + 1)`, exact (was a leaf comment); no parameters or result claimed |
| cm.between | Os | CORRECT | WRONG | DECLINED | CORRECT | Ghidra `param_1 - 6U < 0x5e`: in C long-unsigned int is long, so the compare is signed; a=0 gives true, truth false; swiftdc now `return // x0 = ((arg0 - 6) <ᵁ 94)`, exact (`sub; cmp #0x5e; cset lo`: a=0 false, 6 true, 99 true, 100 false) (was a leaf comment); no parameters or result claimed |
| cm.ubetween | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 >ᵁ arg1) && (arg1 >ᵁ 3))`, exact (cmp; ccmp hi; cset hi) (was a leaf comment); no parameters or result claimed |
| cm.callu | Os | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `sink(…)`: argument (sxtw of arg) elided |
| cm.cselU | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 <ᵁ arg1) ? 22 : 11)`, exact (was a leaf comment); no parameters or result claimed |
| cm.cselS | Os | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc now `return // x0 = ((arg0 < arg1) ? 22 : 11)`, right (`csel lt`; plain `<` read as signed on an untyped argN) (was a leaf comment); no parameters or result claimed |
| cm.branchU | Os | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `if (arg0 >ᵁ arg1) { sink(…) }` then `return // x0 = 3`: condition and 3 right, sink argument (1) elided (was bare `return`, WRONG); no parameters or result claimed |
| cm.branchS | Os | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `if (arg0 > arg1) { sink(…) }` then `return // x0 = 3`: condition (signed) and 3 right, sink argument (1) elided (was bare `return`, WRONG); no parameters or result claimed |
| im3.bound1 | O | WRONG | WRONG | CORRECT | WRONG | Ghidra `void bound1(...)` drops the return of m; swiftdc `return (arg0<arg1)?7:(arg0-arg1)` drops the precondition trap (m >= n) |
| im3.bound2 | O | WRONG | WRONG | CORRECT | CORRECT | Ghidra `void bound2(...)`: trap right, returned k missing |
| im3.idx | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: raw `x1`, undefined `x8` (count) and `return ?`; both traps right |
| im4.mixU | O | CORRECT | CORRECT | CORRECT | CORRECT | swiftdc now `arg0 <ᵁ arg1` (explicit unsigned, `cset lo`); score unchanged |
| im4.mixS | O | CORRECT | CORRECT | CORRECT | CORRECT | swiftdc now `arg0 <ˢ arg1`: signed, matching `cset lt`, and distinct from mixU (was a plain `<`, scored WRONG) |
| im4.mixSel | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| im4.uNegConst | O | CORRECT | CORRECT | CORRECT | CORRECT | swiftdc now `arg0 >ˢ -6`: signed, matching `cmn x0,#6; cset gt` (was plain `>`, scored WRONG) |
| im4.uSignedZero | O | CORRECT | CORRECT | CORRECT | CORRECT | swiftdc now `((arg0 - arg1) >=ˢ 0) ? 2 : 1`: signed, matching `cinc ge` (was plain `>=`, scored WRONG) |

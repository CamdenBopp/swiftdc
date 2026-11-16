# Switch area: Ghidra 12.2 vs swiftdc (`disasm --structured`)

**Re-score 2026-11-13b (swiftdc columns only).** Ghidra's columns and renders are unchanged and copied from the 2026-11-13 table. swiftdc was re-scored for the 19 function-builds whose render text changed: csw dense_bias/lookup/sparse (all levels), csw loopsw/wide (-O2/-Os), csw2 fall (all levels), csw3 fall (-O2/-Os), ssw2 tokValue (-O/-Osize). Eight rows changed score. Previous swiftdc totals: interface 69/0/60/3, body 12/29/66/25 (C/P/W/D).

Builds: csw, csw2, csw3 (C at -O0, -O2, -Os) and ssw, ssw2 (Swift at -Onone, -O, -Osize). There are 132 function-builds: 63 C and 69 Swift. Every row was checked against `llvm-objdump`/`otool -tV`. The jump tables (C ldrb at csw3 -O2/-Os, ldrsw at csw/csw3 -O0, and the Swift tables noted per row) were decoded by hand from the image bytes.

## Rubric (same for both tools)

- **Interface.** Ghidra is judged on its decompiled prototype (not the `// signature:` comment). swiftdc is judged on its demangled Swift header. For C, swiftdc prints no prototype, so its interface is the `argN` it uses plus its `return` lines. Only parameter count and the presence and width of the result count.
- **Bare `return` (primary rule).** A bare `return` in a value-returning function claims no result, so it is WRONG on both axes. Ghidra's `void` on a value-returning function gets the same treatment. Every C function here returns int, and swiftdc prints a bare `return` in all of them, so the secondary counts below re-score that form as a decline. This matches Structurer.swift's own comment: for a function with an unrecognisable signature it keeps the bare form on purpose.
- **`return // x0 = <value>` (2026-11-13b addendum).** swiftdc now ends a signatureless function with a comment stating x0 at the return. That is no result claim, so the interface result is DECLINED. The commented value is the shown result: right value and everything else right is CORRECT, a wrong value is WRONG, `?` pieces are PARTIAL. A function where any value-returning path still ends in a bare `return` (a tail call's result, a table value) stays WRONG on both axes. 0xffffffff for an int -1 is the right w0 bit pattern.
- **Calls.** A call shown with an argument the callee does not take (`_e0(0)`, `_ext(0,1)`) or with one missing is WRONG. A `(…)`, a `?`, a raw register or an undecoded table is PARTIAL.
- **Dropped code.** A case arm rendered empty whose real body updates state, or a common tail statement (acc++) that is never shown, is WRONG.
- **Shared rubric.** The rules in `ghidra/scores/RUBRIC.md` also apply. In particular, a constant rendered as the address of an unrelated symbol (`&segment_command_00000020…`, `&MACH_HEADER…`) is WRONG. Applying that rule moved three Ghidra Swift rows from PARTIAL to WRONG.
- **Swift-specific.** These rules came from the Swift half and apply to both tools: a value-returning body whose every return is `?` is DECLINED; a misgrouped `print` call, a dropped compared string, or a literal rendered as `""` is WRONG; metadata and witness-table arguments are not scored.

## Scores: C (csw, csw2, csw3)

| function | build | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| dense_bias | csw_O0 | CORRECT | WRONG | DECLINED | PARTIAL | G: `_e0(0)`..`_e7(0)` pass an argument e0(void) does not take. S: now `let rN = eN(…)` and `return // x0 = (x==10 ? r0 : … : 0xffffffff)`: mapping and -1 right, but the 16 and 17 tests are `?` and the result is not claimed (was bare `return`) |
| lookup | csw_O0 | CORRECT | CORRECT | DECLINED | CORRECT | S: now `return // x0 = (x==0 ? 7 : x==1 ? 3 : x==2 ? 9 : x==3 ? 1 : x==4 ? 8 : x==5 ? 2 : 0)`, all seven values right; result not claimed (was a lone `return`) |
| sparse | csw_O0 | CORRECT | WRONG | DECLINED | PARTIAL | G: `_ext(0,1)`..`_ext(0,5)`: two args, ext takes one. S: now `let rN = ext(…)` and `return // x0 = (x==5 ? r0 : … : 0)`: mapping and default right, ext argument still `…`, result not claimed (was bare `return`) |
| bittest | csw_O0 | CORRECT | WRONG | WRONG | WRONG | G: `_ext(param_1 + -0xd,0)`, `_ext(0,9)`. S: mapping right with raw `w8 == 0`, `ext(…)`, bare return |
| duptargets | csw_O0 | CORRECT | WRONG | WRONG | WRONG | G: `_ext(0,0x14)`, `_ext(param_1 + -6,0xffffffff)`. S: raw `w8 == 0` twice (x==0, x-1==0), bare return |
| loopsw | csw_O0 | CORRECT | WRONG | WRONG | WRONG | G: `_ext(iVar1 + -4,local_20)` adds an arg; arithmetic right. S: `if (?)`, arms for 0/3/4 empty, acc and xor dropped |
| interp | csw_O0 | CORRECT | PARTIAL | DECLINED | WRONG | G: switch on label addresses (0xaa0..0xb40), opcode->label table not decoded. S: `indirect_jump(?)`, arms `goto loc_b4c` with acc+=1/acc*=2/-acc dropped, halt return missing |
| wide | csw_O0 | CORRECT | CORRECT | WRONG | WRONG | S: ldrsw table undecoded (`indirect_jump(?)`), 80 unlabelled `ext(…) return` blocks |
| dense_bias | csw_O2 | CORRECT | CORRECT | WRONG | WRONG | S: default now `return // x0 = 0xffffffff` (right), but the eight tail calls still end in a bare `return`: eN() result lost |
| lookup | csw_O2 | CORRECT | PARTIAL | WRONG | WRONG | G: `*(undefined4 *)(param_1 * 4 + 0x8fc)` value table undecoded. S: `if (x >ᵁ 5) return // x0 = 0 else return`: default now shown, the in-range arm is still a bare `return` (table value lost) |
| sparse | csw_O2 | CORRECT | CORRECT | WRONG | WRONG | S: default now `return // x0 = 0`; `ext(…)` still hides the 1..5 argument and the five tail calls end in a bare `return` |
| bittest | csw_O2 | WRONG | WRONG | WRONG | WRONG | G: `void`, tail-call result dropped; table arg undecoded. S: `ext(…)` both paths (structure exact), bare return |
| duptargets | csw_O2 | WRONG | WRONG | WRONG | WRONG | G: `void`, tail-call result dropped. S: `ext(…)`, bare return |
| loopsw | csw_O2 | CORRECT | CORRECT | WRONG | WRONG | S: n<1 exit now `return // x0 = 0`; unchanged otherwise: `if (w8 == 0) { loc_72c: }`, case 0 (acc+=1), 3, 4 render empty; xor and the loop-exit value dropped |
| interp | csw_O2 | WRONG | WRONG | DECLINED | WRONG | G: `void _interp`, computed goto rendered as a call, plus 4 phantom caseD_n functions. S: four `indirect_jump(?)`, acc updates and the halt `ret` dropped |
| wide | csw_O2 | CORRECT | CORRECT | WRONG | WRONG | S: `if (x >ᵁ 79) return // x0 = 0 else { ext(…) return }`: default now shown, arg 3x+1 hidden and the tail-call result lost |
| dense_bias | csw_Os | CORRECT | CORRECT | WRONG | WRONG | S: default now `return // x0 = 0xffffffff` (right), but the eight tail calls still end in a bare `return`: eN() result lost |
| lookup | csw_Os | CORRECT | PARTIAL | WRONG | WRONG | G: `*(undefined4 *)(param_1 * 4 + 0x8fc)` value table undecoded. S: `if (x >ᵁ 5) return // x0 = 0 else return`: default now shown, the in-range arm is still a bare `return` (table value lost) |
| sparse | csw_Os | CORRECT | CORRECT | WRONG | WRONG | S: default now `return // x0 = 0`; `ext(…)` still hides the 1..5 argument and the five tail calls end in a bare `return` |
| bittest | csw_Os | WRONG | WRONG | WRONG | WRONG | G: `void`, tail-call result dropped; table arg undecoded. S: `ext(…)` both paths (structure exact), bare return |
| duptargets | csw_Os | WRONG | WRONG | WRONG | WRONG | G: `void`, tail-call result dropped. S: `ext(…)`, bare return |
| loopsw | csw_Os | CORRECT | CORRECT | WRONG | WRONG | S: n<1 exit now `return // x0 = 0`; unchanged otherwise: `if (w8 == 0) { loc_72c: }`, case 0 (acc+=1), 3, 4 render empty; xor and the loop-exit value dropped |
| interp | csw_Os | WRONG | WRONG | DECLINED | WRONG | G: `void _interp`, computed goto rendered as a call, plus 4 phantom caseD_n functions. S: four `indirect_jump(?)`, acc updates and the halt `ret` dropped |
| wide | csw_Os | CORRECT | CORRECT | WRONG | WRONG | S: `if (x >ᵁ 79) return // x0 = 0 else { ext(…) return }`: default now shown, arg 3x+1 hidden and the tail-call result lost |
| bias | csw2_O0 | CORRECT | WRONG | WRONG | WRONG | G: `_e10(0)`..`_e17(0)` extra arg. S: mapping right, bare return (r+1 lost) |
| holes | csw2_O0 | CORRECT | WRONG | WRONG | WRONG | G: `_e1(0)`, `_e4(0)` extra arg. S: mapping right, raw `w8 == 0` twice, bare return (r+1 lost) |
| fall | csw2_O0 | CORRECT | WRONG | DECLINED | PARTIAL | G: `_e3(0)`, `_e4(0)` extra arg. S: mapping right (raw `w8 == 0` twice, `eN(…)`), now `return // x0 = 0` (right); result not claimed |
| inloop | csw2_O0 | CORRECT | WRONG | WRONG | WRONG | G: `_e3(0)`, `_e4(0)` extra arg. S: `if (?)` then five `w8 == 0` tests meaning different values; acc++ dropped, bare return |
| negbias | csw2_O0 | CORRECT | WRONG | WRONG | WRONG | G: `_e0(0)` etc. extra arg. S: mapping right, bare return (r+1 lost) |
| chars | csw2_O0 | CORRECT | WRONG | WRONG | WRONG | G: `_e0(0)` etc. extra arg. S: mapping right, bare return (r+1 lost) |
| bias | csw2_O2 | CORRECT | CORRECT | WRONG | WRONG | S: compare tree mapping right, bare return (r+1 lost) |
| holes | csw2_O2 | CORRECT | CORRECT | WRONG | WRONG | S: mapping right, raw `w0 == 0`, bare return (r+1 lost) |
| fall | csw2_O2 | CORRECT | CORRECT | DECLINED | PARTIAL | S: mapping right (raw `w0 == 0`/`w0 == 1`, `eN(…)`), now `return // x0 = 0` (right); result not claimed |
| inloop | csw2_O2 | CORRECT | CORRECT | WRONG | WRONG | S: loop via raw `x21`, acc++ silently dropped, bare return |
| negbias | csw2_O2 | CORRECT | CORRECT | WRONG | WRONG | S: compare tree mapping right, bare return (r+1 lost) |
| chars | csw2_O2 | CORRECT | CORRECT | WRONG | WRONG | S: compare tree mapping right, bare return (r+1 lost) |
| bias | csw2_Os | CORRECT | CORRECT | WRONG | WRONG | S: compare tree mapping right, bare return (r+1 lost) |
| holes | csw2_Os | CORRECT | CORRECT | WRONG | WRONG | S: mapping right, raw `w0 == 0`, bare return (r+1 lost) |
| fall | csw2_Os | CORRECT | CORRECT | DECLINED | PARTIAL | S: mapping right (raw `w0 == 0`/`w0 == 1`, `eN(…)`), now `return // x0 = 0` (right); result not claimed |
| inloop | csw2_Os | CORRECT | CORRECT | WRONG | WRONG | S: loop via raw `x21`, acc++ silently dropped, bare return |
| negbias | csw2_Os | CORRECT | CORRECT | WRONG | WRONG | S: compare tree mapping right, bare return (r+1 lost) |
| chars | csw2_Os | CORRECT | CORRECT | WRONG | WRONG | S: compare tree mapping right, bare return (r+1 lost) |
| bias | csw3_O0 | CORRECT | WRONG | WRONG | WRONG | G: switch on target addresses (case 0x554..) not values, and `_fdef(uVar1 - 0xb)` extra arg. S: ldrsw table undecoded, unlabelled `f100(…) return` blocks, +1 lost |
| holes | csw3_O0 | CORRECT | WRONG | WRONG | WRONG | G: address switch, `default: _f0()`, `_fdef(lVar2)` extra arg. S: table undecoded |
| fall | csw3_O0 | CORRECT | CORRECT | WRONG | WRONG | G exact (switch with fallthrough 0->1->2, r=f<x>() for 3..11). S: table undecoded, bare returns |
| inloop | csw3_O0 | CORRECT | WRONG | WRONG | WRONG | G: `_fdef(uVar1 - 0xc)` extra arg, address switch. S: `if (?)`, table arms after the loop body, case 1/2 lost, acc++ dropped |
| negbias | csw3_O0 | CORRECT | WRONG | WRONG | WRONG | G: address switch, `_fdef(uVar1 - 0xb)`. S: table undecoded |
| chars | csw3_O0 | CORRECT | WRONG | WRONG | WRONG | G: `switch(param_1) case 0: _f0()` (case values should be 0x61..0x6c), `_fdef(lVar1)`. S: table undecoded |
| wide64 | csw3_O0 | CORRECT | WRONG | WRONG | WRONG | G: address switch, `_fdef(param_1 - 0xf)`. S: table undecoded, raw `mem32[x29 - 0xc] = w0` spills |
| bias | csw3_O2 | CORRECT | CORRECT | WRONG | WRONG | ldrb table at 0xd04 (decoded by hand, index k -> f(100+k)). S: `indirect_jump(?)`, unlabelled blocks, +1 lost |
| holes | csw3_O2 | CORRECT | CORRECT | WRONG | WRONG | ldrb table at 0xd10: 3,8 -> fdef; G exact. S: table undecoded |
| fall | csw3_O2 | CORRECT | CORRECT | WRONG | WRONG | ldrb table 0xd1e: 3..11 tail-call f<x>; G returns f<x>() right. S: default and the 0/1/2 arm now reach `return // x0 = 0`; table still undecoded, f3..f11 tail results still a bare `return` |
| inloop | csw3_O2 | CORRECT | CORRECT | WRONG | WRONG | S: table arms rendered as dead code after `goto loc_74c`; case 1 (continue) and 2 (break) lost; acc++ dropped |
| negbias | csw3_O2 | CORRECT | CORRECT | WRONG | WRONG | ldrb table 0xd37, index x+4. S: table undecoded |
| chars | csw3_O2 | CORRECT | CORRECT | WRONG | WRONG | ldrb table 0xd43, index c-97. S: table undecoded |
| wide64 | csw3_O2 | CORRECT | CORRECT | WRONG | WRONG | S decodes this one: `switch (?) { case 0: f0(…) … case 15: f15(…) }` mapping right, subject `?`, +1 lost |
| bias | csw3_Os | CORRECT | CORRECT | WRONG | WRONG | ldrb table at 0xd04 (decoded by hand, index k -> f(100+k)). S: `indirect_jump(?)`, unlabelled blocks, +1 lost |
| holes | csw3_Os | CORRECT | CORRECT | WRONG | WRONG | ldrb table at 0xd10: 3,8 -> fdef; G exact. S: table undecoded |
| fall | csw3_Os | CORRECT | CORRECT | WRONG | WRONG | ldrb table 0xd1e: 3..11 tail-call f<x>; G returns f<x>() right. S: default and the 0/1/2 arm now reach `return // x0 = 0`; table still undecoded, f3..f11 tail results still a bare `return` |
| inloop | csw3_Os | CORRECT | CORRECT | WRONG | WRONG | S: table arms rendered as dead code after `goto loc_74c`; case 1 (continue) and 2 (break) lost; acc++ dropped |
| negbias | csw3_Os | CORRECT | CORRECT | WRONG | WRONG | ldrb table 0xd37, index x+4. S: table undecoded |
| chars | csw3_Os | CORRECT | CORRECT | WRONG | WRONG | ldrb table 0xd43, index c-97. S: table undecoded |
| wide64 | csw3_Os | CORRECT | CORRECT | WRONG | WRONG | S decodes this one: `switch (?) { case 0: f0(…) … case 15: f15(…) }` mapping right, subject `?`, +1 lost |

## Scores: Swift (ssw, ssw2)


| function | build | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| sink | ssw_O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra: print args misgrouped (items typed as String with bridgeObject=&segment_command_00000020, separator built from x2/x3, terminator dropped). swiftdc: right call print(r0," ","\n"), raw x0 in stores |
| constReturn | ssw_O | CORRECT | PARTIAL | CORRECT | PARTIAL | both leave the 7-entry value table undecoded (Ghidra *(DAT_1510+x*8), swiftdc return ?) |
| biasCalls | ssw_O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra: sink constants right, but both print arms misgrouped as in sink, strings as hex. swiftdc: sink(?) loses the merged constants, print arms right |
| ranges | ssw_O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| tuple | ssw_O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| guards | ssw_O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| fall | ssw_O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: raw x0 in two conditions |
| area | ssw_O | DECLINED | WRONG | CORRECT | DECLINED | Ghidra: payload read as (byte)param_1.value, rect = in_x1*(byte)x0 (truncates w to 8 bits); tag/second word as in_w2/in_x1. swiftdc: every return ? |
| rectWidth | ssw_O | DECLINED | WRONG | CORRECT | DECLINED | Ghidra returns (byte)x0 instead of the 64-bit width. swiftdc return ? |
| triOr | ssw_O | DECLINED | WRONG | CORRECT | DECLINED | Ghidra returns (byte)x0 instead of n. swiftdc return ? |
| opCode | ssw_O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| sparse | ssw_O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| charSwitch | ssw_O | CORRECT | WRONG | CORRECT | DECLINED | Ghidra: _stringCompareWithSmolCheck((0x61),(0xe1..),expecting=low byte of subject): the compared character is dropped and expecting fabricated (true: lhs literal, rhs subject, expecting 0). swiftdc: all returns ? |
| strSwitch | ssw_O | CORRECT | WRONG | CORRECT | DECLINED | same as charSwitch |
| bitset | ssw_O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra masks right (0x20212a, 0x14) but print misgrouped. swiftdc: mask test as (x8 & x9), print item ? |
| loopSwitch | ssw_O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc: case arms render empty (acc+=1, acc-=5, acc=0, acc*=3 silently missing), sink(?), return ? |
| sink | ssw_Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra: the two default-argument thunks are named Swift::_print, so it shows three print calls with in_x2/in_x3 junk. swiftdc print([…], ?, ?) |
| constReturn | ssw_Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| biasCalls | ssw_Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra: three print calls per print arm (default-arg thunks misnamed). swiftdc: print([…], ?, ?) |
| ranges | ssw_Onone | CORRECT | CORRECT | CORRECT | DECLINED | Ghidra ~= calls and 1/2/3/0 right (its witness-table args are garbled; ABI plumbing, not scored for either tool). swiftdc ~=(?, ?), return ? |
| tuple | ssw_Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc raw-register branches, return ? |
| guards | ssw_Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc return ? |
| fall | ssw_Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc raw x0/x9 in conditions |
| area | ssw_Onone | DECLINED | WRONG | CORRECT | DECLINED | as ssw_O |
| rectWidth | ssw_Onone | DECLINED | WRONG | CORRECT | DECLINED | as ssw_O |
| triOr | ssw_Onone | DECLINED | WRONG | CORRECT | DECLINED | as ssw_O |
| opCode | ssw_Onone | CORRECT | CORRECT | CORRECT | DECLINED | ldrsw jump table at 0x19c8: Ghidra decodes case k -> k+1 (verified by hand). swiftdc indirect_jump(?), return ?, and renders the table as phantom sub_19c8 |
| sparse | ssw_Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| charSwitch | ssw_Onone | CORRECT | PARTIAL | CORRECT | DECLINED | Ghidra: == gets an extra in_x4/in_x5 argument, "é" left as s__00002c77; values right. swiftdc ==(?, ?), return ? |
| strSwitch | ssw_Onone | CORRECT | PARTIAL | CORRECT | DECLINED | Ghidra: extra in_x4/in_x5 argument to ==. swiftdc return ? |
| bitset | ssw_Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra: three print calls per arm (default-arg thunks misnamed). swiftdc raw x0, print([…], ?, ?) |
| loopSwitch | ssw_Onone | CORRECT | PARTIAL | CORRECT | WRONG | Ghidra right, but the iterator element and nil flag are read from locals never shown being written. swiftdc: arms empty, acc updates silently missing |
| sink | ssw_Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra: print hidden in _OUTLINED_FUNCTION_3(). swiftdc folds the outlined fragments into print(r0," ","\n"), raw x0 |
| constReturn | ssw_Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | table undecoded by both |
| biasCalls | ssw_Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | ldrb table at 0x1320 (verified): Ghidra decodes all 8 cases, print arms opaque outlined calls. swiftdc switch(?) on the right index, sink(?), print(?, " ", "\n") |
| ranges | ssw_Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| tuple | ssw_Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| guards | ssw_Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| fall | ssw_Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc raw x0 |
| area | ssw_Osize | DECLINED | DECLINED | CORRECT | DECLINED | ldrb table at 0x1328 (tag 0->1, 1->w*h, 2->n+3, 3->empty/dot): Ghidra "could not recover jumptable", renders an indirect call; swiftdc indirect_jump(?), return ? |
| rectWidth | ssw_Osize | DECLINED | WRONG | CORRECT | DECLINED | as ssw_O |
| triOr | ssw_Osize | DECLINED | WRONG | CORRECT | DECLINED | as ssw_O |
| opCode | ssw_Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| sparse | ssw_Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| charSwitch | ssw_Osize | CORRECT | WRONG | CORRECT | DECLINED | Ghidra values right, compares and epilogue in opaque outlined calls. swiftdc return ?; RUBRIC.md: the "a"/"b" small-string bits shown as `&segment_command_00000020.nsects+1/+2` |
| strSwitch | ssw_Osize | CORRECT | PARTIAL | CORRECT | DECLINED | as charSwitch |
| bitset | ssw_Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra print outlined, strings hex. swiftdc (x8 & x9), print(?, …) |
| loopSwitch | ssw_Osize | CORRECT | PARTIAL | CORRECT | WRONG | ldrb table at 0x132c (verified): Ghidra decodes all 5 arms, returns through _OUTLINED_FUNCTION_5. swiftdc indirect_jump(?), default arm's acc=0 and acc*=3 silently missing |
| s | ssw2_O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra print misgrouped. swiftdc raw x0 |
| t | ssw2_O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra print misgrouped. swiftdc stores raw x20/x19 |
| holes | ssw2_O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra: table undecoded, "Z" shown as &segment_command_00000020.maxprot+2. swiftdc t("Z") / t(?); RUBRIC.md: the "Z" literal shown as `&segment_command_00000020.maxprot+2` (unrelated symbol) is a false claim |
| empties | ssw2_O | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra: right, small strings as hex. swiftdc: t(?) for the merged string, raw x0 |
| big | ssw2_O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra: "b0".."b9", "d0", "e0" rendered as "" (an address 0x30xx read as a string), and the final tail call t(a49/b39/c39/d0/e0/zz) is dropped (LAB_00001158: return). swiftdc: every literal right, shared tail t(?), raw x0 |
| tokValue | ssw2_O | DECLINED | WRONG | CORRECT | PARTIAL | Ghidra: num(n) returns (byte)x0; ident's count built from (byte)x0. swiftdc now `return Swift.String.count.getter(?, ?)` for ident (right callee, tail call at tag 1), args `?`; num and the table arm still `return ?`; tag tests on raw w2/w8 |
| nested | ssw2_O | DECLINED | WRONG | CORRECT | DECLINED | Ghidra: b(n) test is (byte)n < 6 (true: signed n > 5 on 64 bits; wrong for n=256 or n=-1). swiftdc return ? |
| s | ssw2_Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra three print calls (default-arg thunks misnamed). swiftdc print([…], ?, ?) |
| t | ssw2_Onone | CORRECT | WRONG | CORRECT | PARTIAL | as s |
| holes | ssw2_Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc raw x0/x9 |
| empties | ssw2_Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc raw x0/x9 |
| big | ssw2_Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc all 133 literals right, raw x0/x9 |
| tokValue | ssw2_Onone | DECLINED | WRONG | CORRECT | DECLINED | Ghidra (byte)x0 for num; constants shown as &MACH_HEADER.magic+k. swiftdc return ? |
| nested | ssw2_Onone | DECLINED | WRONG | CORRECT | DECLINED | Ghidra (byte)n < 6. swiftdc return ? |
| s | ssw2_Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra print outlined. swiftdc raw x0 |
| t | ssw2_Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra print outlined. swiftdc raw x20/x19 |
| holes | ssw2_Osize | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra table undecoded. swiftdc only t(?), no condition; RUBRIC.md: "Z" shown as `&segment_command_00000020.maxprot+2` |
| empties | ssw2_Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | ldrb table at 0x13b0 (verified): Ghidra decodes it, strings hex. swiftdc switch(?) right, strings ? |
| big | ssw2_Osize | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra: "d0"/"e0" rendered as "", literals as &DAT_ addresses inside outlined calls. swiftdc literals right, switch(?), tail t(?) |
| tokValue | ssw2_Osize | DECLINED | WRONG | CORRECT | PARTIAL | Ghidra: num(n) returns (byte)x0; ident's count built from (byte)x0. swiftdc now `return Swift.String.count.getter(?, ?)` for ident (right callee, tail call at tag 1), args `?`; num and the table arm still `return ?`; tag tests on raw w2/w8 |
| nested | ssw2_Osize | DECLINED | WRONG | CORRECT | DECLINED | as ssw2_O |


## Totals (132 function-builds)

| tool | axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|---|
| Ghidra | interface | 111 | 0 | 6 | 15 |
| Ghidra | body | 60 | 17 | 54 | 1 |
| swiftdc | interface | 69 | 0 | 54 | 9 |
| swiftdc | body | 13 | 36 | 60 | 23 |

Split by language:

| tool | axis | C (63) | Swift (69) |
|---|---|---|---|
| Ghidra | interface | 57 C / 6 W | 54 C / 15 D |
| Ghidra | body | 37 C / 3 P / 23 W | 23 C / 14 P / 31 W / 1 D |
| swiftdc | interface | 54 W / 9 D | 69 C |
| swiftdc | body | 1 C / 5 P / 57 W | 12 C / 31 P / 3 W / 23 D |

**Secondary count (swiftdc's bare `return` read as a decline; 2026-11-13 figures, not recomputed for this run).** This affects only the C functions. swiftdc interface becomes 69 CORRECT / 63 DECLINED. swiftdc body becomes 12 CORRECT / 77 PARTIAL / 15 WRONG / 28 DECLINED. The 15 WRONG that remain all drop real code: loopsw, interp, inloop (both C files) and the Swift loopSwitch. Ghidra is unaffected: it never prints a bare `return`, and its six `void` prototypes are explicit result claims.

**Phantom functions.**
- **Ghidra: 10.**
  - Eight are `switchD_000007b8::caseD_0` to `caseD_3`, in both csw_O2 and csw_Os. These are interior computed-goto labels of interp, each given its own prototype (`void caseD_0(byte *param_1,int param_2)`).
  - Two are the external `dyld_stub_binder` placeholder in the same two builds, decompiled as `halt_baddata()`.
- **swiftdc: 10.** All are ldrsw jump tables rendered as `sub_XXXX { trap() }`, and LC_FUNCTION_STARTS lists every one of these addresses (`_bias+244` and so on):
  - csw_O0: `sub_10ac`.
  - csw3_O0: `sub_604`, `sub_710`, `sub_824`, `sub_988`, `sub_ab0`, `sub_bd4`, `sub_d2c`.
  - ssw_Onone: `sub_17b4`, `sub_19c8`.

**Missing functions.** 0 for both tools.

## Telling examples

### Ghidra beats swiftdc

1. **csw3 bias at -O2/-Os: compressed jump table** (`adr; ldrb w11,[x9,x8]; add x10,x10,x11,lsl #2; br x10`; byte table at 0xd04; decoded by hand: index k goes to f(100+k), default fdef, then +1).
   - Ghidra: `switch(param_1) { case 100: iVar1 = _f100(); break; ... case 0x6f: iVar1 = _f111(); break; default: iVar1 = _fdef(); } return iVar1 + 1;`. This is exact.
   - swiftdc: `/* unresolved indirect branch @ 0x588 */ indirect_jump(?)` followed by unlabelled `loc_58c: f100(…) return`, `loc_594: f111(…) return`, and so on. No case values are shown and the +1 is lost.
   - The same holds for all six adr+ldrb tables in csw3 and both its builds. swiftdc decodes only wide64, which has no bias, and even there it prints `switch (?)`.
2. **loopsw at -O2** (truth: op 0 acc+=1, 1 continue, 2 break, 3 acc*=2, 4 acc-=3, default acc=ext(acc), then acc^=i).
   - Ghidra recovers all of it: `if (iVar1 == 0) { uVar2 = uVar2 + 1; goto LAB_0000072c; } ... uVar2 = uVar2 << 1; ... uVar2 = uVar2 - 3; ... LAB_0000072c: uVar2 = uVar2 ^ (uint)uVar3;`.
   - swiftdc: `if (w8 == 0) { loc_72c: } else { if (w8 != 1) { loc_780: ext(…) goto loc_72c } }` and then `return`. Case 0 reads as a no-op, and case 1 (continue, which skips the xor) looks the same as case 0. The Swift loopSwitch fails the same way in all three builds.
3. **opCode at -Onone** (ldrsw table at 0x19c8; case k returns k+1).
   - Ghidra: `switch(param_1.value) { case 0: local_18 = 1; ... case 9: local_18 = 10; }`.
   - swiftdc: `indirect_jump(?) ... return ?`, and it renders the table itself as a phantom function `sub_19c8 { trap() }`.

### swiftdc beats Ghidra

1. **area, rectWidth and triOr in ssw** (all builds; truth: rect returns w*h on full 64-bit words).
   - Ghidra: `uVar2 = (ulong)(byte)param_1.value; ... _Var1 = in_x1 * uVar2;`. The code is `mul x10, x1, x0`, but Ghidra truncates w to 8 bits, so rect(300, 2) would give 88. Its empty/dot test `in_x1 != 0 || uVar2 != 0` is truncated the same way.
   - swiftdc: `ssw.area(ssw.Shape) -> Swift.Int { if ((w2 & 0xff) > 1) { ... return ? } }`. It declines the values and its header is exact.
   - The same byte truncation makes tokValue and nested (ssw2) WRONG in every build. nested claims `(byte)n < 6`; the truth is a signed 64-bit n > 5.
2. **C at -O0: Ghidra adds call arguments** (truth: `bl _e0` with no argument set up; e0 is `int e0(void)`).
   - Ghidra: `local_14 = _e0(0);`, `_ext(0,1)`, `_ext(param_1 + -0xd,0)`, and in csw3 `_fdef(uVar1 - 0xb)`. A leftover `subs` result is rendered as an argument.
   - This makes 17 of Ghidra's 21 C bodies at -O0 WRONG. csw3_O0 chars also gets wrong case values: `switch(param_1) { case 0: _f0(); ...}` on the raw character, when the truth is 'a' (0x61) -> f0.
   - swiftdc: `e0(…)`, `fdef(…)`. It never invents an argument count, but it never shows one either.
3. **interp at -O2/-Os: function boundary.**
   - Ghidra: `void _interp(byte *param_1) { (**(code **)((ulong)*param_1 * 8 + 0x4000))(param_1 + 1,1); return; }`. It then emits four extra "functions" `switchD_000007b8::caseD_0..3` with invented parameters. The single computed-goto function is split into five, and its int result is claimed `void`.
   - swiftdc keeps one function `_interp` with four `indirect_jump(?)`. That body is still scored WRONG, because the acc updates and the halt return are not shown.
   - Runner-up: **ssw2 big at -O**. Ghidra renders "b0".."b9", "d0" and "e0" as `""` and drops the closing tail call t(…). swiftdc gets all 133 literals right.

## Observation

Ghidra decodes every jump-table form here (compressed ldrb, ldrsw, Swift enum tags at -Onone). Its C bodies at -O2/-Os are 31 of 33 CORRECT or PARTIAL, and its two WRONG there are `void` tail calls. Its 54 WRONG bodies come from fabrication, not from switch recovery:
- extra call arguments at -O0;
- byte-truncated enum payloads;
- misgrouped `print` arguments;
- `void` tail calls.

swiftdc has no compressed-table decoding in C (`indirect_jump(?)` with unlabelled blocks). It still drops most C return values through a bare `return` (every tail-call result and every `r + 1`); the new `// x0 =` comment gets 1 of 63 C bodies right (lookup at -O0) and 5 PARTIAL, and it turns ldrsw tables at -O0 into phantom functions. In Swift it is never wrong about an interface, but it declines 23 bodies and empties the case arms of every loop switch.

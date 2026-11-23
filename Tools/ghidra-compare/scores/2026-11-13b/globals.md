# Globals area: Ghidra 12.2 vs swiftdc (`disasm --structured`)

Scope: 13 builds from five fixtures: cglob.c, cglob2.c and cglob3.m at -O0/-O2/-Os, sglob.swift at -Onone/-O/-Osize, and libext.dylib. Every user-written function in every build is scored: 151 function-builds. libext (extdef.c) defines data only. Both tools correctly report no functions for it, so it gets no rows. Skipped as compiler-generated: addressors, one-time initializers, synthesized getters/setters/modify/init, the `merged bumpCount` helper, OUTLINED_FUNCTION_*, value witnesses and metadata accessors. The static `helper` in cglob.c is user code, so it is scored where it survives (-O0). Ground truth: the fixture comments, plus `llvm-objdump -d`, `nm -m` and `dyld_info -fixups` for every build. -O2 and -Os produce byte-identical text for cglob, cglob2 and cglob3, and both tools emit identical output for those pairs.

Rules, applied identically to both tools. They match the frames scoring (ghidra/scores/frames.md):

- Ghidra's interface is the decompiled prototype; an `in_x0`/`unaff_*` parameter counts as DECLINED. `undefined4`/`undefined8` with a value shown counts as typed. swiftdc C output has no prototype, so its interface comes from the `argN` it uses and the `return` it prints. Swift functions take the demangled header, for both tools.
- A raw address for a global, such as `DAT_00008010`, `0x7c8` or `mem32[0x8000]`, or a raw register value (`w0`, `x8`, `unaff_x19`, `in_x0`), is a declined piece and makes the body PARTIAL. A named global through its GOT slot (`PTR__extVal_00004080`) is a correct identity.
- **`W*`** marks a swiftdc cell that is WRONG only because a value-returning function renders a bare `return`, or no return at all, with the value silently absent. It counts as WRONG in the main totals. The alternative totals read it as a decline: interface DECLINED, body PARTIAL.
- 2026-11-13b re-score, swiftdc columns only (RUBRIC.md addendum). `return // x0 = <value>` states what x0 holds and claims no result: the interface result is DECLINED, and the commented value is scored as the shown result value in the body. A value-returning function that still shows a bare `return` on any path, or no value, stays `W*`. Only rows whose function text changed between the two swiftdc renders were re-scored.
- swiftdc's leaf placeholder `// no non-runtime calls (leaf / pure computation)` makes no claim about the body, so it is DECLINED on both axes. It does not count as WRONG.
- A misattributed value is WRONG: a value shown as another call's "return", or a parameter dereferenced as if it were a global's address. A call shown without an argument the binary passes, with no `?`/`…`, is also WRONG.
- swiftdc writes loads as `mem64[…]`, so a bare symbol (`use(extVal)`, `(extArr + 16)`) is that symbol's address. It never uses a bare name for a value in these outputs. So `use(extVal)` for `use(&extVal)` scores CORRECT, though a reader expecting C syntax would misread it.


| function | build | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| bump | cglob_O0 | W | W | W* | W* | Ghidra `void _bump(void)` drops the returned ++gCounter; swiftdc `mem32[0x8000] = w0`, raw value, no return |
| readOther | cglob_O0 | C | C | D | D | swiftdc leaf placeholder (`// no non-runtime calls`) |
| readHidden | cglob_O0 | C | C | D | D | swiftdc leaf placeholder |
| tableAt | cglob_O0 | C | P | D | D | Ghidra reads kTable as raw `0x7c8`; swiftdc placeholder |
| setY | cglob_O0 | C | P | W* | W* | Ghidra `DAT_0000800c`/`DAT_00008010` for gPoint.y/.z; swiftdc store right (raw address), return missing |
| tlsBump | cglob_O0 | W | W | W* | W* | Ghidra `void`, drops the result; swiftdc unresolved TLV thunk, `mem32[x8] = w0`, no return |
| tlsLongGet | cglob_O0 | C | C | W* | W* | swiftdc unresolved TLV thunk call, no return |
| weakRead | cglob_O0 | C | C | W* | W* | swiftdc bare `return` |
| weakDefRead | cglob_O0 | C | C | D | D | swiftdc placeholder |
| nameGet | cglob_O0 | C | C | D | D | swiftdc placeholder |
| bssSet | cglob_O0 | C | C | C | P | swiftdc `mem32[0x8070 + …]` raw address for bss |
| bssPtr | cglob_O0 | C | P | D | P | Ghidra `&DAT_00008080` for &bss[4]; swiftdc: now `return // x0 = 0x8080`, right (&bss[4]) but a raw address (was placeholder); result not claimed |
| callHelper | cglob_O0 | C | C | D | C | swiftdc: now `let r0 = helper(a)`, `let r1 = helper(a + 1)`, `return // x0 = (r0 + r1)` masked to 32 bits, right (was no sum, no return); result not claimed |
| helper | cglob_O0 | C | C | D | D | swiftdc placeholder |
| bump | cglob_O2 | W | W | W* | W* | Ghidra `void _bump(void)` drops the returned ++gCounter; swiftdc `mem32[0x8000] = w0`, no return |
| readOther | cglob_O2 | C | C | D | D | swiftdc placeholder |
| readHidden | cglob_O2 | C | C | D | C | swiftdc: now `return // x0 = 6`, right (folded sHidden * 2; was placeholder); result not claimed |
| tableAt | cglob_O2 | C | P | D | D | Ghidra raw `0x718` for kTable |
| setY | cglob_O2 | C | P | W* | W* | Ghidra raw DAT_ for gPoint fields; swiftdc store right, return missing |
| tlsBump | cglob_O2 | C | C | W* | W* | swiftdc unresolved TLV thunk, `mem32[x0] = w8`, no return |
| tlsLongGet | cglob_O2 | C | C | W* | W* | swiftdc unresolved TLV thunk, no return |
| weakRead | cglob_O2 | C | C | W* | W* | swiftdc: null branch now `return // x0 = 0xffffffff` (right, -1), but the weakExt branch is still a bare `return` and the condition raw `x8 == 0` |
| weakDefRead | cglob_O2 | C | C | D | D | swiftdc placeholder |
| nameGet | cglob_O2 | C | C | D | D | swiftdc placeholder |
| bssSet | cglob_O2 | C | C | D | D | swiftdc placeholder hides the store |
| bssPtr | cglob_O2 | C | P | D | P | Ghidra `&DAT_00008078`; swiftdc: now `return // x0 = 0x8078`, right (&bss[4]) but a raw address (was placeholder); result not claimed |
| callHelper | cglob_O2 | C | C | D | D | swiftdc placeholder (helper inlined) |
| bump | cglob_Os | W | W | W* | W* | Ghidra `void _bump(void)` drops the returned ++gCounter; swiftdc `mem32[0x8000] = w0`, no return |
| readOther | cglob_Os | C | C | D | D | swiftdc placeholder |
| readHidden | cglob_Os | C | C | D | C | swiftdc: now `return // x0 = 6`, right (folded sHidden * 2; was placeholder); result not claimed |
| tableAt | cglob_Os | C | P | D | D | Ghidra raw `0x718` for kTable |
| setY | cglob_Os | C | P | W* | W* | Ghidra raw DAT_ for gPoint fields; swiftdc store right, return missing |
| tlsBump | cglob_Os | C | C | W* | W* | swiftdc unresolved TLV thunk, `mem32[x0] = w8`, no return |
| tlsLongGet | cglob_Os | C | C | W* | W* | swiftdc unresolved TLV thunk, no return |
| weakRead | cglob_Os | C | C | W* | W* | swiftdc: null branch now `return // x0 = 0xffffffff` (right, -1), but the weakExt branch is still a bare `return` and the condition raw `x8 == 0` |
| weakDefRead | cglob_Os | C | C | D | D | swiftdc placeholder |
| nameGet | cglob_Os | C | C | D | D | swiftdc placeholder |
| bssSet | cglob_Os | C | C | D | D | swiftdc placeholder hides the store |
| bssPtr | cglob_Os | C | P | D | P | Ghidra `&DAT_00008078`; swiftdc: now `return // x0 = 0x8078`, right (&bss[4]) but a raw address (was placeholder); result not claimed |
| callHelper | cglob_Os | C | C | D | D | swiftdc placeholder (helper inlined) |
| use | cglob2_O0 | C | C | C | P | swiftdc `mem64[0x8040]` raw for sink1 |
| use2 | cglob2_O0 | C | C | C | P | swiftdc raw addresses for sink1/sink2 |
| passMut | cglob2_O0 | C | C | C | P | swiftdc `use(?)` (declines the gMut load, does not render 5) |
| passMutTwice | cglob2_O0 | C | C | C | P | swiftdc `mutate(…)`, `use2(?, ?)` |
| passPtr | cglob2_O0 | C | C | C | P | swiftdc `use(?)` |
| passGPtr | cglob2_O0 | C | C | C | P | swiftdc `use(?)` |
| passKStr | cglob2_O0 | C | P | C | C | Ghidra `_use(0x890)` raw cstring address; swiftdc `use("const-str")` |
| passGStr | cglob2_O0 | C | C | C | P | swiftdc `use(?)`; neither renders "mut-str" |
| passArr | cglob2_O0 | C | P | D | P | Ghidra raw kArr address; swiftdc `use(?)`, parameter i never shown |
| passField | cglob2_O0 | C | P | C | P | Ghidra `DAT_00008028` for gS.b; swiftdc `use(?)` |
| storeThenUse | cglob2_O0 | C | C | C | P | swiftdc `mem64[0x8000 + 0x20] = 9` raw for gS.a, `use(?)` (O0 reloads gS.a) |
| passVol | cglob2_O0 | C | C | C | P | swiftdc `use(?)` |
| aliasStore | cglob2_O0 | C | C | C | P | swiftdc `mem64[x10] = 4` raw register for *gPtr, `use(?)` |
| use | cglob2_O2 | C | C | C | P | swiftdc `mem64[0x8040]` raw for sink1 |
| use2 | cglob2_O2 | C | C | C | P | swiftdc raw addresses for sink1/sink2 |
| passMut | cglob2_O2 | C | C | C | P | swiftdc `use(?)` (declines the gMut load, does not render 5) |
| passMutTwice | cglob2_O2 | C | C | C | P | swiftdc `mutate(…)`, `use2(?, ?)` |
| passPtr | cglob2_O2 | C | C | C | P | swiftdc `use(?)` |
| passGPtr | cglob2_O2 | C | C | C | P | swiftdc `use(?)` |
| passKStr | cglob2_O2 | C | P | C | C | Ghidra `_use(0x7a8)` raw cstring address; swiftdc `use("const-str")` |
| passGStr | cglob2_O2 | C | C | C | P | swiftdc `use(?)`; neither renders "mut-str" |
| passArr | cglob2_O2 | C | P | D | P | Ghidra raw kArr address; swiftdc `use(?)`, parameter i never shown |
| passField | cglob2_O2 | C | P | C | P | Ghidra `DAT_00008028` for gS.b; swiftdc `use(?)` |
| storeThenUse | cglob2_O2 | C | C | C | P | swiftdc `mem64[0x8000 + 0x20] = 9` raw for gS.a, `use(9)` |
| passVol | cglob2_O2 | C | C | C | P | swiftdc `use(?)` |
| aliasStore | cglob2_O2 | C | C | C | P | swiftdc `mem64[x8] = 4` raw register for *gPtr, `use(?)` |
| use | cglob2_Os | C | C | C | P | swiftdc `mem64[0x8040]` raw for sink1 |
| use2 | cglob2_Os | C | C | C | P | swiftdc raw addresses for sink1/sink2 |
| passMut | cglob2_Os | C | C | C | P | swiftdc `use(?)` (declines the gMut load, does not render 5) |
| passMutTwice | cglob2_Os | C | C | C | P | swiftdc `mutate(…)`, `use2(?, ?)` |
| passPtr | cglob2_Os | C | C | C | P | swiftdc `use(?)` |
| passGPtr | cglob2_Os | C | C | C | P | swiftdc `use(?)` |
| passKStr | cglob2_Os | C | P | C | C | Ghidra `_use(0x7a8)` raw cstring address; swiftdc `use("const-str")` |
| passGStr | cglob2_Os | C | C | C | P | swiftdc `use(?)`; neither renders "mut-str" |
| passArr | cglob2_Os | C | P | D | P | Ghidra raw kArr address; swiftdc `use(?)`, parameter i never shown |
| passField | cglob2_Os | C | P | C | P | Ghidra `DAT_00008028` for gS.b; swiftdc `use(?)` |
| storeThenUse | cglob2_Os | C | C | C | P | swiftdc `mem64[0x8000 + 0x20] = 9` raw for gS.a, `use(9)` |
| passVol | cglob2_Os | C | C | C | P | swiftdc `use(?)` |
| aliasStore | cglob2_Os | C | C | C | P | swiftdc `mem64[x8] = 4` raw register for *gPtr, `use(?)` |
| use | cglob3_O0 | C | C | C | P | swiftdc raw `mem64[0x8008]` for sink1 |
| useObj | cglob3_O0 | C | C | C | P | swiftdc `objc_storeStrong(local_18, arg0)`, `mem64[0x8008] = x8` |
| passAddr | cglob3_O0 | C | C | C | C |  |
| passVal | cglob3_O0 | C | C | C | P | swiftdc `use(?)` |
| passArr2 | cglob3_O0 | C | C | C | P | swiftdc `use(?)` |
| passArrAddr | cglob3_O0 | C | C | C | C |  |
| passStr | cglob3_O0 | C | C | C | P | swiftdc `use(?)` |
| storeExt | cglob3_O0 | C | C | C | P | swiftdc `mem64[x9] = 3`, raw register for &extVal |
| passKCF | cglob3_O0 | C | C | C | C |  |
| passGCF | cglob3_O0 | C | C | C | P | swiftdc `useObj(?)` |
| passLit | cglob3_O0 | C | C | C | C |  |
| use | cglob3_O2 | C | C | C | P | swiftdc raw `mem64[0x8008]` for sink1 |
| useObj | cglob3_O2 | C | C | C | P | swiftdc `mem64[0x8008] = arg0` raw |
| passAddr | cglob3_O2 | C | C | C | C |  |
| passVal | cglob3_O2 | C | C | C | P | swiftdc `use(?)` |
| passArr2 | cglob3_O2 | C | C | C | P | swiftdc `use(?)` |
| passArrAddr | cglob3_O2 | C | C | C | C |  |
| passStr | cglob3_O2 | C | C | C | P | swiftdc `use(?)` |
| storeExt | cglob3_O2 | C | C | C | P | swiftdc `mem64[x8] = 3`, raw register for &extVal |
| passKCF | cglob3_O2 | C | C | C | C |  |
| passGCF | cglob3_O2 | C | C | C | P | swiftdc `useObj(?)` |
| passLit | cglob3_O2 | C | C | C | C |  |
| use | cglob3_Os | C | C | C | P | swiftdc raw `mem64[0x8008]` for sink1 |
| useObj | cglob3_Os | C | C | C | P | swiftdc `mem64[0x8008] = arg0` raw |
| passAddr | cglob3_Os | C | C | C | C |  |
| passVal | cglob3_Os | C | C | C | P | swiftdc `use(?)` |
| passArr2 | cglob3_Os | C | C | C | P | swiftdc `use(?)` |
| passArrAddr | cglob3_Os | C | C | C | C |  |
| passStr | cglob3_Os | C | C | C | P | swiftdc `use(?)` |
| storeExt | cglob3_Os | C | C | C | P | swiftdc `mem64[x8] = 3`, raw register for &extVal |
| passKCF | cglob3_Os | C | C | C | C |  |
| passGCF | cglob3_Os | C | C | C | P | swiftdc `useObj(?)` |
| passLit | cglob3_Os | C | C | C | C |  |
| bumpCount() | sglob_O | C | W | C | W* | Ghidra `_Var1 = bumpCount();` drops the &gCount argument (indistinguishable from bumpMain); swiftdc `merged ….bumpCount(0x8018)`, no return |
| tableAt(_:) | sglob_O | C | P | C | P | Ghidra `&DAT_00004020` for gTable storage; swiftdc `x0 >ᵁ 3` trap, `return ?` |
| nameCount() | sglob_O | C | C | C | P | swiftdc `x8 != -1`, `String.count.getter(?, ?)` |
| sharedY() | sglob_O | C | C | C | C |  |
| addCounter(_:) | sglob_O | C | C | C | P | swiftdc `mem64[0x8000 + 0x30] = x8` raw value |
| modeName() | sglob_O | C | P | D | P | Ghidra "fast" as raw `0x74736166`; swiftdc: still `sub_b98`, name lost; now `return // x0 = 0x74736166` (was placeholder): "fast" as raw bits, x1 half of the String not shown |
| setPairB(_:) | sglob_O | C | P | C | P | Ghidra `DAT_00008010` for gPair.b; swiftdc `mem64[0x8008 + 0x8] = arg0`, `return ?` |
| bumpMain() | sglob_O | C | W | C | W* | Ghidra `bumpCount()` with no argument (loses mainCounter); swiftdc `merged ….bumpCount(0x8000)`, no return |
| readTwice(_:) | sglob_O | D | P | C | P | Ghidra `(void)` + `in_x0` for the closure; swiftdc unresolved indirect call, `return ?` |
| cEntry(_:) | sglob_O | C | C | C | C |  |
| _c_entry | sglob_O | C | C | D | C | swiftdc: now `return // x0 = ((arg0 << 1) & 0xffffffff)`, right (was placeholder); result not claimed |
| _custom_silgen_fn | sglob_O | C | C | D | C | swiftdc: now `return // x0 = (arg0 + 5)`, right (was placeholder); result not claimed |
| Box.label getter | sglob_O | W | P | C | C | Ghidra `get_label(void *this, Box *param_1)` invents param_1, "box" as raw `0x786f62`; swiftdc `return "box"` |
| bumpCount() | sglob_Onone | C | W | C | P | Ghidra ignores the addressor's x0 (`in_x0`) and returns `*p_Var2` with `p_Var2 = _swift_endAccess(…)`: misattributed; swiftdc addressor calls, `mem64[x9] = x8`, `return ?` |
| tableAt(_:) | sglob_Onone | C | W | C | W | Ghidra `puVar1 = (undefined8 *)param_1; uVar2 = *puVar1`: dereferences the index as the array; swiftdc `Array.subscript.getter(arg0)` drops the array and metadata arguments |
| nameCount() | sglob_Onone | C | P | C | P | Ghidra `in_x0` for the addressor result; swiftdc `String.count.getter(?, ?)` |
| sharedY() | sglob_Onone | C | P | C | P | Ghidra `*(in_x0 + 8)`; swiftdc `return ?` |
| addCounter(_:) | sglob_Onone | C | W | C | P | Ghidra `plVar2 = (long *)param_1; *plVar2 = *plVar2 + param_1`: treats n as the counter's address; swiftdc `mem64[x9] = x8` |
| modeName() | sglob_Onone | C | P | C | P | Ghidra `*in_x0`; swiftdc `return ?` |
| setPairB(_:) | sglob_Onone | C | W | C | P | Ghidra `*(param_1 + 8) = param_1` and return via endAccess's "result"; swiftdc `mem64[x9 + 0x8] = arg0`, `return ?` |
| bumpMain() | sglob_Onone | C | W | C | P | same misattribution as bumpCount; swiftdc `return ?` |
| readTwice(_:) | sglob_Onone | D | W | C | P | Ghidra loads gCount through the closure pointer (`*(long *)in_x0`) and the second load through the closure's "return"; swiftdc `return ?` |
| cEntry(_:) | sglob_Onone | C | C | C | C |  |
| _c_entry | sglob_Onone | W | W | W* | W* | Ghidra `void _c_entry(__int32)` drops the result; swiftdc `SG.cEntry(?)`, no return |
| _custom_silgen_fn | sglob_Onone | C | C | D | C | swiftdc: now `return // x0 = (arg0 + 5)`, right (was placeholder); result not claimed |
| Box.label getter | sglob_Onone | W | C | C | C | Ghidra invents param_1 |
| bumpCount() | sglob_Osize | C | W | C | W* | Ghidra `bumpCount()` with no argument; swiftdc `merged ….bumpCount(0x8018)`, no return |
| tableAt(_:) | sglob_Osize | C | P | C | P | Ghidra `&DAT_00004020`; swiftdc `return ?` |
| nameCount() | sglob_Osize | C | C | C | P | swiftdc `String.count.getter(?, ?)` |
| sharedY() | sglob_Osize | C | C | C | C |  |
| addCounter(_:) | sglob_Osize | C | P | C | P | Ghidra `unaff_x19` for n; swiftdc `mem64[0x8000 + 0x30] = x8` |
| modeName() | sglob_Osize | C | P | D | W* | Ghidra raw "fast" bytes; swiftdc `sub_b60 { OUTLINED_FUNCTION_4() }`: name lost, tail-call result not returned |
| setPairB(_:) | sglob_Osize | C | P | C | P | Ghidra `DAT_00008010 = unaff_x19`; swiftdc `return ?` |
| bumpMain() | sglob_Osize | C | W | C | W* | Ghidra `bumpCount()` with no argument; swiftdc `merged ….bumpCount(0x8000)`, no return |
| readTwice(_:) | sglob_Osize | D | P | C | P | Ghidra `in_x0`; swiftdc `return ?` |
| cEntry(_:) | sglob_Osize | C | C | C | C |  |
| _c_entry | sglob_Osize | D | D | W* | W* | Ghidra emits no function for the tail-branch thunk; swiftdc `SG.cEntry(arg0)`, no return |
| _custom_silgen_fn | sglob_Osize | C | C | D | C | swiftdc: now `return // x0 = (arg0 + 5)`, right (was placeholder); result not claimed |
| Box.label getter | sglob_Osize | W | P | C | C | Ghidra invents param_1, raw "box" bytes |

151 function-builds. C = CORRECT, P = PARTIAL, W = WRONG, D = DECLINED; `W*` counts as WRONG.

## Totals

| tool | axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|---|
| Ghidra | interface | 139 | 0 | 8 | 4 |
| Ghidra | body | 103 | 32 | 15 | 1 |
| swiftdc | interface | 101 | 0 | 17 | 33 |
| swiftdc | body | 30 | 80 | 23 | 18 |

Previous swiftdc totals (2026-11-13): interface 101 / 0 / 18 / 32, body 23 / 76 / 24 / 28. 11 rows changed score. Ghidra's rows are copied from the 2026-11-13 table.

Alternative reading, with every swiftdc `W*` taken as a decline (interface DECLINED, body PARTIAL):

| tool | axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|---|
| swiftdc | interface | 101 | 0 | 0 | 50 |
| swiftdc | body | 30 | 102 | 1 | 18 |

swiftdc body `W*` cells: 22. swiftdc body WRONG not caused by a missing return: 1.

## Where Ghidra beats swiftdc

1. **`tlsBump`, cglob_O2** (truth: `return ++tlsVar`, through the TLV thunk). Ghidra: `piVar2 = (int *)(*(code *)_tlsVar)(); iVar1 = *piVar2; *piVar2 = iVar1 + 1; return iVar1 + 1;`. swiftdc: `/* unresolved call @ 0x664 */ indirect_call(?, recovered_args: [0x8028, …])` then `mem32[x0] = w8`, with no return. Ghidra follows the thread-local descriptor; swiftdc neither names the variable nor returns the value.
2. **`weakRead`, cglob_O2** (truth: `&weakExt ? weakExt : -1`). Ghidra: `if (PTR__weakExt_00004008 == 0) return 0xffffffff; return *(undefined4 *)PTR__weakExt_00004008;`. swiftdc: `if (x8 == 0) { return // x0 = 0xffffffff } else { return }`. swiftdc gets the branch shape right and now shows the -1, but the condition is a raw register and the weakExt result is still gone. This bare-`return` defect in C code accounts for 22 of swiftdc's 23 body WRONGs.
3. **`callHelper`, cglob_O2** (truth: `helper(a) + helper(a+1)` = `6a + 2*gOther + 3`). Ghidra: `return param_1 * 6 + _gOther * 2 + 3;`. swiftdc: `// no non-runtime calls (leaf / pure computation)`. A leaf whose x0 swiftdc can trace now ends in `return // x0 = <value>` (readHidden `6`, `_custom_silgen_fn` `arg0 + 5`), but a leaf that loads a global (readOther, nameGet, tableAt, weakDefRead) or folds a call (this one) still gets the placeholder: 18 swiftdc body DECLINEDs, against 1 for Ghidra.

## Where swiftdc beats Ghidra

1. **`addCounter`, sglob_Onone** (truth: `Config.counter += n`). Ghidra: `plVar2 = (long *)param_1; … *plVar2 = *plVar2 + param_1;`, so it treats `n` as the counter's address, because it does not model the addressor's x0 result. swiftdc: `SG.Config.counter.unsafeMutableAddressor()`, then `mem64[x9] = x8`, then `return`. swiftdc names the right global but leaves the value raw. At -Onone this misattribution makes 6 of the 13 Ghidra bodies WRONG (setPairB writes `*(param_1 + 8) = param_1`). A seventh, `_c_entry`, is WRONG because it drops the result.
2. **`bumpCount` vs `bumpMain`, sglob_O/-Osize** (truth: they bump gCount and mainCounter through one merged body). Ghidra renders both identically: `_Var1 = bumpCount(); return _Var1;`. The `x0` argument is gone, and with it the global's identity. swiftdc: `merged ….bumpCount(0x8018)` and `merged ….bumpCount(0x8000)`. The address is raw but correct and tells the two apart; the return value is still missing.
3. **`readTwice`, sglob_Onone** (truth: `let a = gCount; f(); return a &+ gCount`). Ghidra: `pcVar1 = in_x0; … lVar3 = *(long *)pcVar1; … plVar2 = (long *)(*in_x0)(); lVar4 = *plVar2; return lVar3 + lVar4;`, so it reads "gCount" through the closure pointer, and then through the closure's non-existent return. swiftdc: two `gCount.unsafeMutableAddressor()` calls around the unresolved closure call, then `return ?`. Also on the Swift side: `static Box.label.getter` renders `return "box"` in all three builds, while Ghidra invents a `Box *param_1` and, at -O/-Osize, leaves "box" as `0x786f62`.

## Observations

- Ghidra is ahead on C globals: it names globals through GOT slots, follows TLV thunks, folds `kPtr`, keeps `gMut` live across `mutate()`, and never renders the initial value of a mutable global (`gMut` = 5, `"mut-str"`). swiftdc is not wrong on those values either: it declines every mutable-global load with `?`. But its C output loses a returned value it loads from memory (`W*`), and a leaf function that reads a global is a placeholder.
- swiftdc's only body WRONG that a missing return does not explain is `tableAt` at -Onone. There `Swift.Array.subscript.getter(arg0)` shows one argument where the binary passes the index, the array buffer and Int's metadata, with an indirect result.
- Six of Ghidra's seven -Onone body WRONGs have one cause: it does not take an addressor's x0 as that call's result. It then attributes the global's address to whatever register held it last: the parameter, the closure, or `swift_endAccess`'s "return".
- Neither tool fabricates the static initial value of a mutable global. That was the main soundness trap in cglob2/sglob.

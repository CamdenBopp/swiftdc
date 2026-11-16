# Strings: Ghidra 12.2 vs swiftdc

Fixtures abi2/strings/s1..s5.swift, each at Onone, O and Osize: 267 scored rows (user functions; s2/s5 merged bodies get their own row). Rubric: ghidra/scores/RUBRIC.md. Per-chunk files with judgement calls: ghidra/scores/parts/strings-*.md. The function column names the chunk (s1..s5).

Judgement calls, applied to both tools: Ghidra's `// signature: undefined X(void)` placeholder at Onone is treated as no claim (its declaration line is the interface); omitting a hidden type-metadata argument is not counted as a dropped argument; identical-code-folded functions keep separate rows.

## Totals (267 rows)

| tool | axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|---|
| Ghidra | interface | 240 | - | 8 | 19 |
| Ghidra | body | 38 | 100 | 127 | 2 |
| swiftdc | interface | 228 | - | 2 | 37 |
| swiftdc | body | 107 | 119 | 25 | 16 |

By chunk (interface C/W/D, body C/P/W/D):

| chunk | rows | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body |
|---|---|---|---|---|---|
| s1 literals | 63 | 63/0/0 | 0/37/26/0 | 59/0/4 | 56/7/0/0 |
| s2 O | 28 | 24/0/4 | 2/10/16/0 | 17/0/11 | 5/14/7/2 |
| s2 Onone | 27 | 24/0/3 | 10/9/8/0 | 26/0/1 | 6/21/0/0 |
| s2 Osize | 27 | 24/0/3 | 2/10/15/0 | 21/0/6 | 5/16/4/2 |
| s3 bridging | 42 | 36/4/2 | 9/12/21/0 | 38/0/4 | 20/22/0/0 |
| s4 returns/fields | 57 | 48/2/7 | 15/21/19/2 | 48/0/9 | 15/24/6/12 |
| s5 interpolation | 23 | 21/2/0 | 0/1/22/0 | 19/2/2 | 0/15/8/0 |

## Where Ghidra beats swiftdc

1. countLit, O (s4). Ghidra: `_Var1 = Swift::String::get_count(SVar2); return _Var1;` (SVar2 = raw 0x6f6c6c6568 / 0xe5...). swiftdc: `Swift.String.count.getter("hello")` as a bare statement in a `-> Int` function. Truth: `mov x0,#"hello"; mov x1,#0xe5<<56; b String.count.getter`, so the tail call's result is the return value. swiftdc drops the return (same in fromCString at O/Osize).
2. makePerson, O (s2). Ghidra: `PVar1.name.str = (char *)0x6563696c41; ... PVar1.tag.str = (char *)0xd000000000000018;` (right bits, undecoded). swiftdc: `return ?`. Truth: x0..x3 = Person(name: "Alice", tag: "a-tag-that-is-quite-long").
3. sink, O (s1, interface). Ghidra: `void __swift_stdcall S1O::sink(String param_1)` and stores `param_1.str` / `param_1.bridgeObject`. swiftdc: `mem64[x0 + 0x20] = x20; mem64[x0 + 0x28] = x19`. Truth: `mov x19, x1; mov x20, x0; ... stp x20, x19, [x0, #0x20]`: the parameter's two words. Ghidra names the parameter; swiftdc leaves raw callee-saved copies.

## Where swiftdc beats Ghidra

1. sink, O (s1; every print-calling sink at O/Osize). Ghidra: `SVar2.bridgeObject = &segment_command_00000020; separator.bridgeObject = (void *)((long)&MACH_HEADER.cpusubtype + 2); separator.str = (char *)0xe100000000000000; Swift::_print(SVar2,separator);`. swiftdc: `Swift.print(_:separator:terminator:)(r0, " ", "\n")`. Truth: `mov w1,#0x20; mov x2,#0xe1<<56; mov w3,#0xa; mov x4,#0xe1<<56; bl print`. Ghidra turns " " into load-command addresses and drops the terminator.
2. smallHello, Onone (s1; all 21 callers). Ghidra: `__sSS21_builtinStringLiteral...(0xd00,5,1); __s7S1Onone4sinkyySSF();`: sink called with no argument. swiftdc: `S1Onone.sink(Swift.String.init(_builtinStringLiteral:utf8CodeUnitCount:isASCII:)("hello", 5, 1))`. Truth: `add x0, x0, #0xd00` ("hello"), `bl String.init`, x0/x1 passed straight to `bl sink`.
3. fatal, O (s3). swiftdc: `Swift._assertionFailure(_:_:file:line:flags:)("Fatal error", "boom: fatal message here", "S3O/s3.swift", 31, 0)`. Ghidra: `SVar2.bridgeObject = &MACH_HEADER.magic + 2; SVar2.str = &MACH_HEADER.cpusubtype + 3; _assertionFailure((StaticString)0x1234,SVar2,(StaticString)0xd000000000000018,...)`. Truth: x0 = "Fatal error" (len 11, flags 2), x3/x4 = the 24-byte message, file, line 31, flags 0.

## Per-function table

| function | level | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| sink (s1) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G print(arr,sep.lo,sep.hi,term.lo) drops x4 (terminator high word); S `print([…], ?, ?)` elides array contents, separator/terminator unresolved |
| sink2 (s1) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G print drops x4 (terminator high word); S `print([…], ?, ?)` |
| smallHello (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| small15 (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| large16 (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| emptyStr (s1) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `sink()` called with no arguments, literal only as raw address 0xd18; S literal pointer rendered raw `0xd18` ("" unresolved) |
| smallNonASCII (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| largeNonASCII (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| smallEmoji (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| smallQuote (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| smallNewline (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| smallNUL (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| largeNUL (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| largeEscapes (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| multiline (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| rawLit (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| twoStrings (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink2(a.lo,a.hi,b.lo)` drops x3, literals only as raw addresses 0xda7/0xdb0 |
| small8 (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| smallDEL (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| combining (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| lineSep (s1) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` called with no arguments (drops x0,x1); literal only as raw __cstring address |
| sink (s1) | O | CORRECT | WRONG | DECLINED | PARTIAL | G `Swift::_print(SVar2,separator)` drops terminator, " " words shown as `&segment_command_00000020`/`&MACH_HEADER.cpusubtype + 2`; S shows x20/x19 for s |
| sink2 (s1) | O | CORRECT | WRONG | DECLINED | PARTIAL | G `_print(SVar3,separator)` drops terminator, separator as unrelated symbols; S shows x22/x21, x20/x19 for a, b |
| smallHello (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| small15 (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| large16 (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| emptyStr (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G `sink((String)(ZEXT816(0xe000000000000000) << 0x40))`: raw bits |
| smallNonASCII (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| largeNonASCII (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| smallEmoji (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| smallQuote (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| smallNewline (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| smallNUL (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| largeNUL (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| largeEscapes (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| multiline (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| rawLit (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| twoStrings (s1) | O | CORRECT | WRONG | CORRECT | CORRECT | G "k" (x0=0x6b) rendered `section_00000068.sectname + 3` |
| small8 (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| smallDEL (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| combining (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| lineSep (s1) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| sink (s1) | Osize | CORRECT | PARTIAL | DECLINED | PARTIAL | G print hidden behind `_OUTLINED_FUNCTION_1(lVar2)`, header via `_DAT_00000910`; S shows x20/x19 for s |
| sink2 (s1) | Osize | CORRECT | PARTIAL | DECLINED | PARTIAL | G print hidden behind `_OUTLINED_FUNCTION_1(lVar3)`; S shows x22/x21, x20/x19 for a, b |
| smallHello (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates (via `_OUTLINED_FUNCTION_N`, sink call not visible) |
| small15 (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| large16 (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates (via `_OUTLINED_FUNCTION_N`, sink call not visible) |
| emptyStr (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G `sink((String)(ZEXT816(0xe000000000000000) << 0x40))`: raw bits |
| smallNonASCII (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| largeNonASCII (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| smallEmoji (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| smallQuote (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates (via `_OUTLINED_FUNCTION_N`, sink call not visible) |
| smallNewline (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates (via `_OUTLINED_FUNCTION_N`, sink call not visible) |
| smallNUL (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates (via `_OUTLINED_FUNCTION_N`, sink call not visible) |
| largeNUL (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates (via `_OUTLINED_FUNCTION_N`, sink call not visible) |
| largeEscapes (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates (via `_OUTLINED_FUNCTION_N`, sink call not visible) |
| multiline (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates (via `_OUTLINED_FUNCTION_N`, sink call not visible) |
| rawLit (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| twoStrings (s1) | Osize | CORRECT | WRONG | CORRECT | CORRECT | G "k" (x0=0x6b) rendered `section_00000068.sectname + 3` |
| small8 (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| smallDEL (s1) | Osize | CORRECT | WRONG | CORRECT | CORRECT | G x0=0x7f61 rendered `_OUTLINED_FUNCTION_3(&DAT_00007f61)` |
| combining (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| lineSep (s1) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G literal only as raw immediates |
| sink (s2-O) | O | CORRECT | WRONG | DECLINED | WRONG | Both drop the String-metadata arg (x2) to the merged body: G `sink(param_1)`, S `merged ….sink(?, ?)` |
| sinkC (s2-O) | O | CORRECT | WRONG | DECLINED | WRONG | G `sink((String)param_1)` casts and drops Character metadata x2; S `sink(?, ?)` drops x2 |
| merged sink (sinkTm) (s2-O) | O | DECLINED | WRONG | DECLINED | PARTIAL | G metadata as `in_x2`, print separator count as `&MACH_HEADER.cpusubtype + 2`, terminator dropped; S raw x19/x20/x21, print(r0, " ", "\n") right |
| sinkU (s2-O) | O | CORRECT | WRONG | DECLINED | PARTIAL | G print separator `&MACH_HEADER…`, terminator dropped; S shows w19 |
| sinkS (s2-O) | O | DECLINED | WRONG | DECLINED | PARTIAL | G one StaticString param plus `in_x1`/`in_w2`, print wrong; S raw x21/x20/w19 |
| sinkSub (s2-O) | O | DECLINED | WRONG | DECLINED | PARTIAL | G `in_x1..in_x3`, print wrong; S raw x22..x19, box metadata `0x4010` |
| switchOn (s2-O) | O | CORRECT | WRONG | DECLINED | PARTIAL | G returns 1/2/3/0 right, but each `_stringCompareWithSmolCheck` drops s and passes `expecting = param_1.str._0_1_` (true: 0); S literals right, every return is `?`, raw x20/x19 |
| eqYes (s2-O) | O | CORRECT | WRONG | DECLINED | PARTIAL | G compare drops "yes", `expecting = 0x79` (true: 0); S fast-path condition `?` |
| neLong (s2-O) | O | CORRECT | WRONG | DECLINED | PARTIAL | G compare drops the literal, `expecting = 0x1a`; S raw x0/x8/x3/x1, logic right |
| interp (s2-O) | O | CORRECT | WRONG | CORRECT | WRONG | G appends to garbage `in_x2/in_x3`, "!" as `&segment_command_00000020.cmd + 1`, returns `("", 0xe2…)`; S never shows the "n=" initial value, returns `?` |
| interpName (s2-O) | O | CORRECT | WRONG | DECLINED | WRONG | G passes the stale "Hello, " constant to sink; S drops the "Hello, " prefix, name shown as `?` |
| charX (s2-O) | O | CORRECT | WRONG | CORRECT | PARTIAL | G 0x78 as `section_00000068.segname`; S `sinkC(?)` |
| charE (s2-O) | O | CORRECT | PARTIAL | CORRECT | PARTIAL | G raw bits (`&DAT_0000a9c3`, 0xa2…); S `sinkC(?)` |
| charThumb (s2-O) | O | CORRECT | PARTIAL | CORRECT | PARTIAL | G raw bits 0xbd8f9ff08d919ff0/0xa8…; S `sinkC(?)` |
| scalarA (s2-O) | O | CORRECT | CORRECT | CORRECT | PARTIAL | S `sinkU(?)` |
| scalarEuro (s2-O) | O | CORRECT | CORRECT | CORRECT | PARTIAL | S `sinkU(?)` |
| staticStr (s2-O) | O | CORRECT | WRONG | CORRECT | CORRECT | G `sinkS((StaticString)0x14c0)` drops length 16 and flags 2 |
| fromCString (s2-O) | O | CORRECT | PARTIAL | CORRECT | WRONG | G copies from label `s_cstr_literal_00001400` plus raw `ram0x00001408`; S `String(cString: local_30)` and never shows the "cstr-literal" contents |
| retSmall (s2-O) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G raw bits 0x746572/0xe3… |
| retLarge (s2-O) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G raw large-string bits 0xd…1c/0x8…14c0 |
| sub (s2-O) | O | CORRECT | WRONG | CORRECT | WRONG | G count 2 as `&MACH_HEADER.magic + 2`, dropFirst drops s; S `dropFirst(2)` with no receiver s, `sinkSub(?)` |
| funcName (s2-O) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G raw bits |
| fileName (s2-O) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G raw bits |
| prefixed (s2-O) | O | CORRECT | PARTIAL | DECLINED | PARTIAL | G "pre" as raw bits; S s shown as `?` |
| readGlobal (s2-O) | O | CORRECT | WRONG | CORRECT | PARTIAL | G the global's second word loaded from 0x8008 is named `PTR___mangled_name_ref_for_type_metadata…`; S `sink(?)` |
| makePerson (s2-O) | O | CORRECT | PARTIAL | CORRECT | DECLINED | G raw bits for "Alice" and the tag; S just `return ?` |
| concat (s2-O) | O | CORRECT | WRONG | CORRECT | WRONG | G append("-suffix", garbage) and returns the unchanged param_1; S never shows the buffer initialised to s, returns `?` |
| optStr (s2-O) | O | DECLINED | PARTIAL | CORRECT | DECLINED | G `undefined` / `undefined1[16]` result, raw bits; S just `return ?` |
| sink (s2-Onone) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G renders the two `default argument 1/2 of print` calls (0x9ac, 0x9d8) as two extra `Swift::_print` calls (3 prints, garbage args); S `print([…], ?, ?)` |
| sinkC (s2-Onone) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | same as sink: G three print calls; S separator/terminator `?` |
| sinkU (s2-Onone) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | same as sink |
| sinkS (s2-Onone) | Onone | DECLINED | WRONG | CORRECT | PARTIAL | G prototype has one StaticString word, body reads raw `in_x1`/`in_w2`; three prints. S `print([…], ?, ?)` |
| sinkSub (s2-Onone) | Onone | DECLINED | WRONG | DECLINED | PARTIAL | G Substring words 2-4 as `in_x1..in_x3`, three prints; S box stores show raw `x10, x9, x2, x3` |
| switchOn (s2-Onone) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G all cases and 1/2/3/0 right but each `==` gets a ghost third arg `in_x4/in_x5`; S comparisons right, `""` as raw `0x2588`, s as `?`, `return ?` (case values not recovered) |
| eqYes (s2-Onone) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G ghost `in_x4/in_x5` arg to `==`; S s shown as `?` |
| neLong (s2-Onone) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G ghost `in_x4/in_x5` arg to `==`; S s shown as `?` |
| interp (s2-Onone) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G passes `&MACH_HEADER.magic + 1` as appendLiteral's interpolation (real: x20 = stack slot); S `"n=\(local_40)!"` raw slot for n |
| interpName (s2-Onone) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `&MACH_HEADER.magic + 1` as appendLiteral self; S literal right but `sink(String(stringInterpolation:)(?))` |
| charX (s2-Onone) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S `sinkC(?)` |
| charE (s2-Onone) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G literal as label `s__000025fc`; S as raw `0x25fc` (bytes c3 a9, len 2 right in both); S `sinkC(?)` |
| charThumb (s2-Onone) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G `s__000025ff`; S raw `0x25ff` (8 bytes right); S `sinkC(?)` |
| scalarA (s2-Onone) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S `sinkU(?)` (truth `mov w0, #0x41`) |
| scalarEuro (s2-Onone) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S `sinkU(?)` (truth 0x20ac) |
| staticStr (s2-Onone) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sinkS((StaticString)0x2610)` drops length 16 (x1) and flags 2 (w2) |
| fromCString (s2-Onone) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| retSmall (s2-Onone) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| retLarge (s2-Onone) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| sub (s2-Onone) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | both show only `dropFirst(2)` (receiver s implicit); G passes raw `local_50`, S passes `?` to sinkSub |
| funcName (s2-Onone) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| fileName (s2-Onone) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| prefixed (s2-Onone) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S `hasPrefix("pre", ?)` |
| readGlobal (s2-Onone) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G reads addressor result via raw `in_x0`; S `sink(?)` |
| makePerson (s2-Onone) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S `return ?` after the init call |
| concat (s2-Onone) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G ghost `in_x4/in_x5` arg to `+`; S s as `?` |
| optStr (s2-Onone) | Onone | DECLINED | PARTIAL | CORRECT | PARTIAL | G signature line `undefined`; nil as `ZEXT816(0)`; S `if (arg0) {"some"}` then `return ?`, nil branch not shown |
| sink (s2-Osize) | Osize | CORRECT | WRONG | DECLINED | PARTIAL | G: print is hidden in OUTLINED_FUNCTION_1, which renders `_print(...)` without the terminator and with ' '/'\n' as `&segment_command_00000020`/`&MACH_HEADER.cpusubtype+2`; S: thunk is `merged sink(?, ?)`, merged body shows x21/x20/x19 raw, print(r0, " ", "\n") is right |
| sinkC (s2-Osize) | Osize | CORRECT | WRONG | DECLINED | PARTIAL | G: same broken print tail, and the call is shown as `sink((String)param_1)`; S: same as sink |
| sinkU (s2-Osize) | Osize | CORRECT | WRONG | DECLINED | PARTIAL | G: `_OUTLINED_FUNCTION_1()` drops the array argument, and the print tail is broken; S: stores w19 raw, Scalar metadata and print are right |
| sinkS (s2-Osize) | Osize | DECLINED | WRONG | DECLINED | PARTIAL | G: in_x1/in_w2 raw for the StaticString pieces, broken print tail; S: x21/x20/w19 raw |
| sinkSub (s2-Osize) | Osize | DECLINED | WRONG | DECLINED | PARTIAL | G: in_x1..in_x3 raw, broken print tail; S: x22..x19 raw, box metadata as raw 0x4010 |
| switchOn (s2-Osize) | Osize | CORRECT | WRONG | DECLINED | PARTIAL | G: banana compare is `_OUTLINED_FUNCTION_3(0xd000000000000017)`, dropping x1 (the bridge 0x8000000000001460), and literals are raw bits; S: compares name "apple"/"banana-split-large-name"/"" correctly, but every return is `?` and x20/x19 are raw |
| eqYes (s2-Osize) | Osize | CORRECT | WRONG | CORRECT | PARTIAL | G: `_stringCompareWithSmolCheck(s.str, s.bridge, 0x79)` drops the "yes" arguments and invents expecting=0x79 (the asm passes w4=0); S: fast-path condition is `?` |
| neLong (s2-Osize) | Osize | CORRECT | WRONG | CORRECT | PARTIAL | G: compare(s.str, s.bridge, 0x1a) drops the literal and invents expecting=0x1a; S: `return ?`, condition `?` |
| interp (s2-Osize) | Osize | CORRECT | WRONG | CORRECT | WRONG | G: "!" (0x21) is shown as `&segment_command_00000020.cmd + 1`, append's self is garbage in_x2/in_x3, and it returns {"" , 0xe2..}; S: the initial "n=" store into the local is dropped, `return ?` |
| interpName (s2-Osize) | Osize | CORRECT | WRONG | CORRECT | WRONG | G: `sink("Hello, ")` (smol 0x202c6f6c6c6548) where sink gets the whole built string, and grow(0x22, param_1.bridgeObject) has the wrong self; S: grow(34), append(?) and append(". Welcome back to the app") are right, but the initial "Hello, " is dropped and the call is `sink(?)` |
| charX (s2-Osize) | Osize | CORRECT | WRONG | CORRECT | PARTIAL | G: 0x78 'x' is shown as `section_00000068.segname`, an unrelated symbol; S: `sinkC(?)` |
| charE (s2-Osize) | Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | G: raw 0xa9c3 as `&DAT_0000a9c3`, with 0xa2.. as the bridge; S: `sinkC(?)` |
| charThumb (s2-Osize) | Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | G: raw bits 0xbd8f9ff08d919ff0/0xa8..; S: `sinkC(?)` |
| scalarA (s2-Osize) | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | S: `sinkU(?)` |
| scalarEuro (s2-Osize) | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | S: `sinkU(?)` |
| staticStr (s2-Osize) | Osize | CORRECT | WRONG | CORRECT | CORRECT | G: `sinkS((StaticString)0x14e0)` drops length 16 and flags 2 (x1, w2), and the pointer is raw |
| fromCString (s2-Osize) | Osize | CORRECT | PARTIAL | CORRECT | WRONG | G: the "cstr-literal" smol is raw bits, but it is returned; S: the tail-call result is not returned (a bare call in a -> String function) |
| retSmall (s2-Osize) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G: raw 0x746572/0xe3.. |
| retLarge (s2-Osize) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G: raw 0xd00000000000001c/0x80000000000014e0 |
| sub (s2-Osize) | Osize | CORRECT | WRONG | CORRECT | PARTIAL | G: the Substring argument is `&MACH_HEADER.magic + 2`, an unrelated symbol, and `_dropFirst(2)` drops the string; S: dropFirst args are elided and the call is `sinkSub(?)` |
| funcName (s2-Osize) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G: raw smol bits for "funcName()" |
| fileName (s2-Osize) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G: raw 0xd000000000000010/0x8000000000001500 |
| prefixed (s2-Osize) | Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | G: "pre" as raw 0x657270/0xe3..; S: self is `?` |
| readGlobal (s2-Osize) | Osize | CORRECT | WRONG | CORRECT | PARTIAL | G: globalName's bridge word (0x8008) is labelled `PTR___mangled_name_ref_..._00008008`, an unrelated symbol; S: `sink(?)` |
| makePerson (s2-Osize) | Osize | CORRECT | PARTIAL | CORRECT | DECLINED | G: "Alice" and the 24-byte tag are right but in raw bits; S: only `return ?` |
| concat (s2-Osize) | Osize | CORRECT | WRONG | CORRECT | WRONG | G: returns `param_1` (the unsuffixed s), and append's self is garbage in_x2/in_x3; S: the `local = s` initialisation is dropped, `return ?` |
| optStr (s2-Osize) | Osize | DECLINED | PARTIAL | CORRECT | DECLINED | G: the signature result is `undefined`, the body is right with raw "some" bits; S: only `return ?` |
| intPairNotString (s3) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S elides both integer args as `ext_pair(…)` (no false string claim) |
| intPairLooksLikeHi (s3) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G renders integer 0x6968 as `&DAT_00006968` (pointer claim); S `ext_pair(…)` |
| bridgedLength (s3) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| defaultsKey (s3) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `_bridgeToObjectiveC()` / `_unconditionallyBridgeFromObjectiveC()` drop their args; S `if (x0 != 0)` raw and `return ?` |
| nsStringInit (s3) | Onone | WRONG | WRONG | CORRECT | CORRECT | G declares `void` (returns NSString) and calls `NSString(string:)()` with the "small" String dropped |
| postNote (s3) | Onone | WRONG | WRONG | CORRECT | PARTIAL | G claims `undefined8` result `return 0`, bridge() drops the name, postNotificationName drops `object:nil`; S `[? postNotificationName:? object:?]` + dead nil-branch unresolved calls |
| sinkS (s3) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G print(arr, sep.0, sep.1, term.0) drops terminator's 2nd word; S `print([…], ?, ?)` |
| staticNUL (s3) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | both leave the "ab\0cd…" StaticString as raw address 0x17d0 (S drops len/flags as part of the one unresolved StaticString) |
| staticNonASCII (s3) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G label `s_gr_e_static_string_000016c0`, S `0x16c0`: "größe…" bytes undecoded |
| staticQuote (s3) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| sink (s3) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G print drops terminator's 2nd word; S `print([…], ?, ?)` |
| veryLong (s3) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `sink()` with the 70-char String dropped |
| fatal (s3) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| precond (s3) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| intPairNotString (s3) | O | CORRECT | CORRECT | CORRECT | PARTIAL | S `ext_pair(…)` |
| intPairLooksLikeHi (s3) | O | CORRECT | WRONG | CORRECT | PARTIAL | G `&DAT_00006968` for integer 0x6968; S `ext_pair(…)` |
| bridgedLength (s3) | O | CORRECT | WRONG | CORRECT | CORRECT | G `_objc_msgSend_length()` drops the receiver; literal only as `(StaticString)0x1180` |
| defaultsKey (s3) | O | CORRECT | WRONG | CORRECT | PARTIAL | G drops "key-name" and the stringForKey: argument; S `return ?` |
| nsStringInit (s3) | O | CORRECT | WRONG | CORRECT | CORRECT | G drops "small" and the initWithString: argument |
| postNote (s3) | O | WRONG | WRONG | CORRECT | CORRECT | G declares `undefined8 ... return 0`; drops "did-change-note", name and object args |
| sinkS (s3) | O | DECLINED | WRONG | DECLINED | PARTIAL | G raw `in_x1`/`in_w2`, header words and separator as `&segment_command_00000020`/`&MACH_HEADER.cpusubtype + 2`, terminator dropped; S raw x21/x20/w19 for the StaticString |
| staticNUL (s3) | O | CORRECT | PARTIAL | CORRECT | PARTIAL | both `0x1160` unresolved |
| staticNonASCII (s3) | O | CORRECT | PARTIAL | CORRECT | PARTIAL | both `0x11a0` unresolved |
| staticQuote (s3) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G `(StaticString)0x11c0` unresolved |
| sink (s3) | O | CORRECT | WRONG | DECLINED | PARTIAL | G symbol-address separator, terminator dropped; S raw x20/x19 for s |
| veryLong (s3) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G raw bits 0xd000000000000046 / 0x80000000000011c0 |
| fatal (s3) | O | CORRECT | WRONG | CORRECT | CORRECT | G message String shown as `&MACH_HEADER.cpusubtype + 3`/`&MACH_HEADER.magic + 2`, args shifted |
| precond (s3) | O | CORRECT | CORRECT | CORRECT | CORRECT | |
| intPairNotString (s3) | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | S `ext_pair(…)` |
| intPairLooksLikeHi (s3) | Osize | CORRECT | WRONG | CORRECT | PARTIAL | G `&DAT_00006968`; S `ext_pair(…)` |
| bridgedLength (s3) | Osize | CORRECT | WRONG | CORRECT | CORRECT | G `_objc_msgSend_length()` drops the receiver |
| defaultsKey (s3) | Osize | CORRECT | WRONG | CORRECT | PARTIAL | G drops "key-name" and the key arg; S `return ?` |
| nsStringInit (s3) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G "small" only as raw bits 0x6c6c616d73/0xe500000000000000 |
| postNote (s3) | Osize | WRONG | WRONG | CORRECT | CORRECT | G `undefined8 ... return 0`; drops name and object args |
| sinkS (s3) | Osize | DECLINED | WRONG | DECLINED | PARTIAL | G raw in_x1/in_w2, `_OUTLINED_FUNCTION_0()` drops the array (print hidden); S raw x21/x20/w19 |
| staticNUL (s3) | Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | both `0x11a0` unresolved |
| staticNonASCII (s3) | Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | both `0x11e0` unresolved |
| staticQuote (s3) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G `(StaticString)0x1200` |
| sink (s3) | Osize | CORRECT | PARTIAL | DECLINED | PARTIAL | G print hidden behind `_OUTLINED_FUNCTION_0(lVar2)`; S raw x20/x19 for s |
| veryLong (s3) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G raw String bits |
| fatal (s3) | Osize | CORRECT | WRONG | CORRECT | CORRECT | G message as `&MACH_HEADER.*` addresses |
| precond (s3) | Osize | CORRECT | CORRECT | CORRECT | CORRECT | |
| intPairRet (s4) | Onone | CORRECT | WRONG | CORRECT | DECLINED | G integer 0x6968 as `(__int64)&DAT_00006968` (pointer claim); S only `return ?` |
| twoRet (s4) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S `Two.init(a:b:)(0x6968, 0xe200000000000000)` then `return ?` |
| takeInts (s4) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G three `_print` calls with garbage `in_x2/in_x3` separators; S `print([…], ?, ?)` |
| intPairArg (s4) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| pick (s4) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S both literals right in the if/else, result `return ?` |
| pickLarge (s4) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S both literals right, `return ?` |
| optStr (s4) | Onone | WRONG | CORRECT | CORRECT | PARTIAL | G declares the result `String` for a `String?` (nil = (0,0)); S "some" branch right, nil branch and result `return ?` |
| retChar (s4) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G `s__00001953` label, S raw `0x1953` for the "é" bytes; S also `return ?` |
| retScalar (s4) | Onone | CORRECT | WRONG | CORRECT | DECLINED | G `(Scalar)&DAT_000020ac` pointer claim for 0x20AC; S `return ?` |
| Box.init (s4) | Onone | CORRECT | CORRECT | DECLINED | PARTIAL | S raw x20/x0/x1/x8 stores, bare `"init-label"` / `""` statements, `return ?` |
| Box.set (s4) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S `self.label[0..<8] = String("set-small")`, second word `self.label[8..<16] = …` |
| Box.clear (s4) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S empty literal as raw address `0x1928`, second word `…` |
| Box.setTab (s4) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S "tab\there" right, second word `…` |
| countLit (s4) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S `count.getter(String("hello"), ?)`: stray `?` second operand |
| utf8Count (s4) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S `String.utf8.getter(?, ?)`: the parameter unresolved |
| concatLits (s4) | Onone | CORRECT | WRONG | CORRECT | CORRECT | G `String.+(abc, def, SVar3)` with a garbage third arg from `in_x4/in_x5` |
| rep (s4) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| arr (s4) | Onone | WRONG | WRONG | CORRECT | PARTIAL | G declares `void` and drops the returned array; S literals right, `return […]` |
| dict (s4) | Onone | DECLINED | CORRECT | CORRECT | PARTIAL | G `undefined1[16]` result; S bare `"lookup-key"`, `subscript.getter(?)`, `return ?` |
| intPairRet (s4) | O | DECLINED | DECLINED | DECLINED | DECLINED | aliased with twoRet at 0x928: G emits it only as twoRet; S `sub_928` with an empty body |
| twoRet (s4) | O | CORRECT | WRONG | DECLINED | DECLINED | G `return (Two)&DAT_00006968`: pointer claim, second word 0xe2… dropped; S `sub_928`, empty body |
| takeInts (s4) | O | CORRECT | WRONG | CORRECT | CORRECT | G separator/terminator as `&segment_command_00000020` / `&MACH_HEADER.cpusubtype + 2`, terminator dropped |
| intPairArg (s4) | O | CORRECT | CORRECT | CORRECT | CORRECT | |
| pick (s4) | O | CORRECT | WRONG | CORRECT | CORRECT | G "no" as `&DAT_00006f6e` (pointer claim) |
| pickLarge (s4) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G raw bits 0x74726f6873 / 0xd000000000000017 / 0x8000000000001180 |
| optStr (s4) | O | DECLINED | PARTIAL | CORRECT | DECLINED | G `undefined1[16]` result, "some" as raw bits (nil (0,0) right); S `return ?` |
| retChar (s4) | O | CORRECT | WRONG | CORRECT | DECLINED | G `CVar1.str = &DAT_0000a9c3` pointer claim; S `return ?` |
| retScalar (s4) | O | CORRECT | WRONG | CORRECT | DECLINED | G `&DAT_000020ac`; S `return ?` |
| Box.init (s4) | O | CORRECT | PARTIAL | DECLINED | PARTIAL | both raw bits for "init-label"/""; S raw x20 for self, `return ?` |
| Box.set (s4) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G raw bits for both literals |
| Box.clear (s4) | O | CORRECT | PARTIAL | CORRECT | PARTIAL | G `set_label(this, ZEXT…0xe0…)` raw; S `sub_b40(0, 0xe000000000000000)` raw, callee unnamed |
| Box.setTab (s4) | O | CORRECT | PARTIAL | CORRECT | PARTIAL | both raw 0x6572656809626174 / 0xe8…; S callee `sub_b40` |
| countLit (s4) | O | CORRECT | PARTIAL | CORRECT | WRONG | G "hello" raw bits; S bare tail call `String.count.getter("hello")`, result not returned |
| utf8Count (s4) | O | CORRECT | WRONG | DECLINED | WRONG | G `_foreignCount((UTF8View)param_1.str)` drops the String's 2nd word; S raw x1, `_foreignCount()` drops self, native path `return ?` |
| concatLits (s4) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G raw 0x666564636261 / 0xe6… |
| rep (s4) | O | CORRECT | WRONG | CORRECT | WRONG | G "ab" as `&DAT_00006261`; S bare `String.init(repeating:count:)("ab", 3)`, result not returned |
| arr (s4) | O | CORRECT | PARTIAL | CORRECT | PARTIAL | both `return 0x4000` (static array object; elements not recovered) |
| dict (s4) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | G `undefined1[16]`, key raw bits; S `x8 == 0` raw, `return ?` both paths |
| intPairRet (s4) | Osize | DECLINED | DECLINED | DECLINED | DECLINED | aliased with twoRet at 0x928: G only as twoRet; S `sub_928 { OUTLINED_FUNCTION_6() }` |
| twoRet (s4) | Osize | CORRECT | WRONG | DECLINED | DECLINED | G `return (Two)&DAT_00006968`, second word dropped; S unnamed `sub_928`, no result |
| takeInts (s4) | Osize | CORRECT | WRONG | CORRECT | CORRECT | G symbol-address separator, terminator dropped |
| intPairArg (s4) | Osize | CORRECT | CORRECT | CORRECT | CORRECT | |
| pick (s4) | Osize | CORRECT | WRONG | CORRECT | CORRECT | G "no" as `&DAT_00006f6e` |
| pickLarge (s4) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G raw bits (0x8000000000001140) |
| optStr (s4) | Osize | DECLINED | PARTIAL | CORRECT | DECLINED | G `undefined1[16]`, raw bits; S `return ?` |
| retChar (s4) | Osize | CORRECT | WRONG | CORRECT | DECLINED | G `&DAT_0000a9c3`; S `return ?` |
| retScalar (s4) | Osize | CORRECT | WRONG | CORRECT | DECLINED | G `&DAT_000020ac`; S `return ?` |
| Box.init (s4) | Osize | CORRECT | PARTIAL | DECLINED | PARTIAL | G "init-label" as `extraout_x8/x9` from OUTLINED_FUNCTION_7; S right raw bits but raw x20, `return ?` |
| Box.set (s4) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G raw bits |
| Box.clear (s4) | Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | G `set_label(this, ZEXT…)` raw; S `sub_b24(0, 0xe0…)` raw, callee unnamed |
| Box.setTab (s4) | Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | both raw bits; S callee `sub_b24` |
| countLit (s4) | Osize | CORRECT | PARTIAL | CORRECT | WRONG | G raw bits; S tail call result not returned |
| utf8Count (s4) | Osize | CORRECT | WRONG | DECLINED | WRONG | G drops the String's 2nd word; S raw x1, `_foreignCount()` drops self |
| concatLits (s4) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G raw bits |
| rep (s4) | Osize | CORRECT | WRONG | CORRECT | WRONG | G `&DAT_00006261`; S result not returned |
| arr (s4) | Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | both `return 0x4000` |
| dict (s4) | Osize | DECLINED | PARTIAL | CORRECT | PARTIAL | G `undefined1[16]`, raw key bits; S raw x8, `return ?` |
| sink (s5) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `print(arr, sep.0, sep.1, term.0)` drops the terminator's 2nd word; S `print([…], ?, ?)` |
| two (s5) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `sink()` and every `appendLiteral()` drop their args, `literalCapacity(6)` drops interpolationCount 2, literals only as addr/len (0xdd0,2); S `"a=\(local_48), b=\(local_50)"` exact and in order, but raw slots for a/b and `String(stringInterpolation:)(?)` |
| only (s5) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `sink()` drops its arg, `appendLiteral()` args dropped; S `"\(local_40)"` raw slot, `(?)` |
| escaped (s5) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `sink()` drops arg, literals only as (0xdd9,2)/(0xddc,5); S `"q\"\(local_40)\n\\end"` byte-exact, raw slot, `(?)` |
| nonASCII (s5) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `sink()` drops arg, literals (0xde2,9,0)/(0xdec,4,0) undecoded; S `"größe: \(local_40) €"` byte-exact, raw slot, `(?)` |
| longLead (s5) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `sink()` drops arg (capacity 0x1f,1 right); S literal exact, raw slot, `(?)` |
| bracket (s5) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `sink()` drops arg, `literalCapacity(2)` drops count 1; S `"[\(local_50)]"`, raw slot, `(?)` |
| sink (s5) | O | CORRECT | WRONG | DECLINED | PARTIAL | G separator as `&segment_command_00000020`/`&MACH_HEADER.cpusubtype + 2`, terminator dropped; S raw x20/x19 for s, `print(r0, " ", "\n")` right |
| two (s5) | O | CORRECT | WRONG | CORRECT | WRONG | G `append(desc, in_x2/in_x3)` fabricated args, ends `sink("")`; S drops the "a=" initial value of the buffer (shows only `append(", b=")`), sink(?) |
| only (s5) | O | CORRECT | WRONG | CORRECT | PARTIAL | G `get_description()` drops the value a (self/metadata/witness); S `sink(description(self: local_28))` raw slot for a |
| escaped (s5) | O | CORRECT | WRONG | CORRECT | PARTIAL | G `escaped(param_1)` drops the 4 literal args; S `"q\""` exact, "\n\\end" only as raw bits 0x646e655c0a/0xe5… |
| nonASCII (s5) | O | CORRECT | WRONG | CORRECT | PARTIAL | G `escaped(param_1)` drops the literal args; S both segments only as correct raw bits |
| merged escaped (s5) | O | WRONG | WRONG | WRONG | WRONG | both headers claim one Int param; body reads x1..x4 (lead and tail Strings). G `sink(in_x1,in_x2)` claims the lead literal is sunk; S omits the buffer's initial value (lead segment) and shows tail as `?` |
| longLead (s5) | O | CORRECT | WRONG | CORRECT | WRONG | G `sink(0xd000…1f, 0x8000…a00)` claims sink(lead literal) without the number; S `grow(33)` then append, drops the 31-byte lead literal entirely |
| bracket (s5) | O | CORRECT | WRONG | CORRECT | WRONG | G `append(param_1, in_x2/in_x3)` and "[" / "]" as `&segment_command_00000020.initprot + 1` / `.maxprot + 3`; S drops the "[" initial value, appends s as `?` |
| sink (s5) | Osize | CORRECT | WRONG | DECLINED | PARTIAL | as at -O |
| two (s5) | Osize | CORRECT | WRONG | CORRECT | WRONG | G outlined calls without args, `append(", b=", in_x2/in_x3)` fabricated; S drops "a=" initial value, appends `?` |
| only (s5) | Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | G `sink(OUTLINED_FUNCTION_0())` right but opaque; S `OUTLINED_FUNCTION_0(); sink(?)` |
| escaped (s5) | Osize | CORRECT | WRONG | CORRECT | PARTIAL | G `escaped(param_1)` drops literal args; S "\n\\end" raw bits |
| nonASCII (s5) | Osize | CORRECT | WRONG | CORRECT | PARTIAL | G drops literal args; S raw bits for both segments |
| merged escaped (s5) | Osize | WRONG | WRONG | WRONG | WRONG | headers miss x1..x4; G `append((in_x3,in_x4),(in_x2,in_x3))` fabricated pairing; S omits the lead-segment initial value, both appends `?` |
| longLead (s5) | Osize | CORRECT | WRONG | CORRECT | WRONG | both drop the 31-byte lead literal (G also `grow(0x21, in_x1)` with a fabricated arg) |
| bracket (s5) | Osize | CORRECT | WRONG | CORRECT | WRONG | as at -O |

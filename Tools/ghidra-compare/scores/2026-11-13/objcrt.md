# objcrt: Ghidra 12.2 vs swiftdc, scored against the binaries

Fixtures: `abi2/objcrt/rt1..rt5.m`. Builds: rt1, rt1c, rt2, rt2c at O0/O2/Os (the `c` builds use classic `objc_msgSend` with selrefs instead of `objc_msgSend$sel` stubs); rt3 at O0/O2; rt4 at O2; rt5 at O0/O2. Truth: source comments plus `otool -tV` (stub-symbolised) disassembly, `__cfstring`/`__ustring`/`__cstring` bytes. 389 function-builds scored.

Scope: every hand-written method and block body. Synthesized property accessors are included and marked `(synth)` because the fixture comments state their lowering (objc_getProperty, objc_setProperty_atomic, weak load/store, objc_copyStruct); totals are given with and without them. Skipped: `.cxx_destruct`, `.cold` outlined parts (scored as part of their owner), block copy/destroy helpers, compiler-rt availability helpers.

Conventions applied to both tools: hidden ARC retain/release noise is not penalised; a raw register name or Ghidra `in_`/`extraout_`/`unaff_` for a value is an unresolved piece (PARTIAL), as is a raw address or constant-pool reference standing in for a literal object or value; a call shown with an argument missing or an extra argument invented is WRONG; a send whose selector is not the one in the binary is WRONG. A function that only returns a value and shows `return ?` is DECLINED.

## Totals

### All 389 (synth included)

| tool / axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|
| Ghidra interface | 382 | 0 | 5 | 2 |
| Ghidra body | 226 | 62 | 101 | 0 |
| swiftdc interface | 381 | 0 | 0 | 8 |
| swiftdc body | 177 | 171 | 25 | 16 |

### Without synthesized accessors (349)

| tool / axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|
| Ghidra interface | 342 | 0 | 5 | 2 |
| Ghidra body | 210 | 62 | 77 | 0 |
| swiftdc interface | 341 | 0 | 0 | 8 |
| swiftdc body | 153 | 159 | 21 | 16 |

## Most telling examples

### Where Ghidra beats swiftdc

1. **Fast enumeration, `-[Kid sum:]` (rt1-O2).** Truth: sums `[x integerValue]` over the array. Ghidra recovers the whole loop: `IVar2 = objc_stub::integerValue(*(ID *)(lStack_108 + IVar5 * 8)); lVar3 = IVar2 + lVar3; ... return lVar3;`. swiftdc: `[? integerValue]` inside a loop on raw registers (`if (x21 == x23)`), ending `return ?`. Same in all six rt1 builds.
2. **Struct values in FP registers, `-[T takeR4:]` and `-[Kid rect]`.** Truth: `takeR4:` returns r.w (`mov v0, v2`); `-[Kid rect]` doubles x of `[super rect]`. Ghidra: `return param_3.field2_0x10;` and `AVar2.field0_0x0 = AVar1.field0_0x0 + AVar1.field0_0x0;`. swiftdc: `return ?` and `[super rect]; return ?`. swiftdc never shows an HFA or indirect-struct value (takeL3/takeR4/pair/Base rect are DECLINED in every build).
3. **Scalar results of sends and super sends.** `-[Kid scale]` truth `[super scale] * 3.0`: Ghidra `dVar1 = Base::scale(...); return dVar1 * 3.0;`, swiftdc `[super scale]; return (? * 3.0)`. `-[Q superBigC:]`: Ghidra `P::big_(&AStack_38, &super, big:, param_3); return AStack_38.field2_0x10;`, swiftdc `[super big:arg0]; return ?`. swiftdc declines rather than errs, but leaves the answer out.

### Where swiftdc beats Ghidra

1. **Variadic sends.** `-[Q many:b:c:d:e:f:]` (rt2-O2), truth `arrayWithObjects:a,b,c,d,e,f,a,b,nil`. swiftdc: `[NSArray arrayWithObjects:arg0, arg1, arg2, arg3, arg4, arg5, arg0, arg1, 0]` (exact, from the stack stores). Ghidra: `NSArray::arrayWithObjects_((ID)PTR__OBJC_CLASS___NSArray_00004178)`, every argument silently gone. The same loss hits `+[Kid fmt:s:]`, `-[Q vfmt:n:s:]` and `-[Kid pool]` in every build, and Ghidra also drops fixed arguments (`performSelector_withObject_` without x, `numberWithFloat_` without f, `_objc_sync_enter()` without self).
2. **Weak references.** `___14-[U weakBlock]_block_invoke` (rt5-O2), truth `[objc_loadWeakRetained(&block->ws) hello]`. swiftdc: `[objc_loadWeakRetained((arg0 + 32)) hello]`. Ghidra: `objc_stub::hello(*(ID *)(param_1 + 0x20)); return 0;`: it reads the weak slot as a strong pointer and gives the void block a result. Ghidra makes the same substitution in `-[Kid weakLocal:]` at O0, the weak `delegate`/`setDelegate:` accessors (plain load/store), and the `aname` getter (plain load instead of objc_getProperty).
3. **Exceptions.** `-[Kid tryit:flag:]` truth: @try description, @catch NSException returns @"caught", @finally sets *flag. Ghidra (every build): `IVar1 = objc_stub::description(param_3); *param_4 = 1; return IVar1;`: the catch and rethrow paths are gone with no marker. swiftdc shows `objc_begin_catch`, the selector-index test `if (w21 != 2)`, the rethrow and (at O0) `mem64[x29 - 0x8] = @"caught"`, with the return value left as `?`.

## swiftdc defects found (all WRONG cells)

- `-[Kid pool]` (6 builds): the `objc_autoreleasePoolPush`/`Pop` pair is hidden as runtime noise, so the `@autoreleasepool` scope disappears.
- `objc_opt_new` rendered as `[[C alloc] init]` (`-[Kid news]`, `+[Kid shared]` block; 12 builds): the binary sends `+new`.
- `-[Kid setAname:]` at O2/Os (4 builds): the tail call `mov w3,#8; b _objc_setProperty_atomic` renders as `self->_aname = arg0`. At O0, where it is a `bl`, it renders correctly.
- UTF-16 CFStrings rendered as the ASCII prefix: `-[L addUni:]` gives `@"h"` for @"héllo", `-[S nulStr]` gives `@"a"` for @"a\0b". Other UTF-16 literals stay raw addresses, which is the safe outcome.

## Ghidra defect classes (101 WRONG body cells)

Dropped variadic and fixed send arguments; sret buffers, the classic `objc_msgSend` pointer or an FP argument placed in a receiver/selector-argument slot (`objc_msgSend(auStack_50, param_3, big:, 3)`, `objc_msgSend(param_3 * 2.0, NSNumber, sel)`); invented arguments (`_dispatch_once(_shared_once + 1, ...)`, `_objc_enumerationMutation(*local_100 - lVar2, self)`); weak/property runtime calls replaced by plain loads and stores; exception handlers omitted; `+[Q selfName]` (a lone `b _objc_msgSend$name`) missing from the output entirely in rt2-O2/Os.

## Per-function table

Codes: C correct, P partial, W wrong, D declined. G = Ghidra, S = swiftdc.

| function | level | G iface | G body | S iface | S body | note |
|---|---|---|---|---|---|---|
| `-[Base value]` | rt1-O2 | C | C | C | C |  |
| `-[Base rect]` | rt1-O2 | C | C | C | D | S: `return ?` for the {1,2,3,4} HFA |
| `-[Base scale]` | rt1-O2 | C | C | C | C |  |
| `+[Kid initialize]` | rt1-O2 | C | C | C | P | S: `if (x19 == [Kid class])`, self left as raw x19 |
| `+[Kid load]` | rt1-O2 | C | C | C | C |  |
| `-[Kid value]` | rt1-O2 | C | C | C | P | S: `[super value]` then `return (? + 1)` |
| `-[Kid rect]` | rt1-O2 | C | C | C | P | S: `[super rect]; return ?`, doubling of x lost to `?` |
| `-[Kid scale]` | rt1-O2 | C | C | C | P | S: `return (? * 3.0)` |
| `+[Kid fmt:s:]` | rt1-O2 | C | W | C | C | G: `stringWithFormat_(NSString,&cf__d___)` drops the variadic n and s |
| `-[Kid locked:]` | rt1-O2 | C | W | C | P | G: `_objc_sync_enter()` with no argument (self is passed); S: `mem32[arg0] = w8`, `return ?` |
| `-[Kid tryit:flag:]` | rt1-O2 | C | W | C | P | G: catch/finally landing pads omitted, no @"caught" path; S: handlers shown, return value `?` |
| `-[Kid thrower]` | rt1-O2 | C | C | C | C |  |
| `-[Kid weakHash]` | rt1-O2 | C | C | C | C |  |
| `-[Kid weakLocal:]` | rt1-O2 | C | C | C | C |  |
| `-[Kid pool]` | rt1-O2 | C | W | C | W | G: `arrayWithObjects_(NSArray,&cf_a)` drops @"b", nil; S: drops objc_autoreleasePoolPush/Pop (the @autoreleasepool) |
| `-[Kid allocs]` | rt1-O2 | C | C | C | C |  |
| `-[Kid news]` | rt1-O2 | C | C | C | W | S: objc_opt_new rendered `[[NSMutableDictionary alloc] init]`; binary sends +new (equivalent only if +new is not overridden) |
| `-[Kid isStr:]` | rt1-O2 | C | C | C | C |  |
| `-[Kid resp:]` | rt1-O2 | C | C | C | C |  |
| `-[Kid cls:]` | rt1-O2 | C | C | C | C |  |
| `-[Kid sum:]` | rt1-O2 | C | C | C | P | G: full sum loop; S: `[? integerValue]`, accumulator lost, `return ?` |
| `-[Kid avail]` | rt1-O2 | C | C | C | C |  |
| `-[Kid assoc:]` | rt1-O2 | C | C | C | C |  |
| `-[Kid getAssoc]` | rt1-O2 | C | C | C | C |  |
| `-[Kid perf:]` | rt1-O2 | C | C | C | C |  |
| `-[Kid arr]` | rt1-O2 | C | P | C | P | both `return 0x41a8`: constant NSArray left as a raw address |
| `-[Kid dict:]` | rt1-O2 | C | C | C | P | S: objects/keys buffers passed as `local_30`/`local_38`, @"k" and v stores not shown |
| `-[Kid boxed:]` | rt1-O2 | C | C | C | C |  |
| `+[Kid shared]` | rt1-O2 | C | C | C | P | S: `if (x8 != -1) cold.1()`, `return ?` |
| `___13+[Kid shared]_block_invoke` | rt1-O2 | W | W | D | W | G: `undefined8 ... return 0` for a void block; S: no signature, opt_new rendered alloc/init, `= x0` |
| `-[Kid fl:]` | rt1-O2 | C | P | C | C | G: `extraout_s0 + 1.0` |
| `-[Kid rectW:]` | rt1-O2 | C | P | C | P | G: `return in_d2`; S: `return ?` |
| `-[Kid aname] (synth)` | rt1-O2 | C | W | C | P | G: `return *(ID *)(param_1 + 8)` but the binary tail-calls objc_getProperty(self,_cmd,8,1); S: `objc_getProperty(self, ?, 8, 1)` |
| `-[Kid setAname:] (synth)` | rt1-O2 | C | W | C | W | binary tail-calls objc_setProperty_atomic(self,_cmd,v,8); G: `*(param_1+8) = param_3`; S: `self->_aname = arg0` |
| `-[Kid delegate] (synth)` | rt1-O2 | C | W | C | C | G: plain load, drops objc_loadWeakRetained |
| `-[Kid setDelegate:] (synth)` | rt1-O2 | C | W | C | C | G: plain store, drops objc_storeWeak |
| `-[Base value]` | rt1-Os | C | C | C | C |  |
| `-[Base rect]` | rt1-Os | C | C | C | D | S: `return ?` for the {1,2,3,4} HFA |
| `-[Base scale]` | rt1-Os | C | C | C | C |  |
| `+[Kid initialize]` | rt1-Os | C | C | C | P | S: `if (x19 == [Kid class])`, self left as raw x19 |
| `+[Kid load]` | rt1-Os | C | C | C | C |  |
| `-[Kid value]` | rt1-Os | C | C | C | P | S: `[super value]` then `return (? + 1)` |
| `-[Kid rect]` | rt1-Os | C | C | C | P | S: `[super rect]; return ?`, doubling of x lost to `?` |
| `-[Kid scale]` | rt1-Os | C | C | C | P | S: `return (? * 3.0)` |
| `+[Kid fmt:s:]` | rt1-Os | C | W | C | C | G: `stringWithFormat_(NSString,&cf__d___)` drops the variadic n and s |
| `-[Kid locked:]` | rt1-Os | C | W | C | P | G: `_objc_sync_enter()` with no argument (self is passed); S: `mem32[arg0] = w8`, `return ?` |
| `-[Kid tryit:flag:]` | rt1-Os | C | W | C | P | G: catch/finally landing pads omitted, no @"caught" path; S: handlers shown, return value `?` |
| `-[Kid thrower]` | rt1-Os | C | C | C | C |  |
| `-[Kid weakHash]` | rt1-Os | C | C | C | C |  |
| `-[Kid weakLocal:]` | rt1-Os | C | C | C | C |  |
| `-[Kid pool]` | rt1-Os | C | W | C | W | G: `arrayWithObjects_(NSArray,&cf_a)` drops @"b", nil; S: drops objc_autoreleasePoolPush/Pop (the @autoreleasepool) |
| `-[Kid allocs]` | rt1-Os | C | C | C | C |  |
| `-[Kid news]` | rt1-Os | C | C | C | W | S: objc_opt_new rendered `[[NSMutableDictionary alloc] init]`; binary sends +new (equivalent only if +new is not overridden) |
| `-[Kid isStr:]` | rt1-Os | C | C | C | C |  |
| `-[Kid resp:]` | rt1-Os | C | C | C | C |  |
| `-[Kid cls:]` | rt1-Os | C | C | C | C |  |
| `-[Kid sum:]` | rt1-Os | C | C | C | P | G: full sum loop; S: `[? integerValue]`, accumulator lost, `return ?` |
| `-[Kid avail]` | rt1-Os | C | C | C | C |  |
| `-[Kid assoc:]` | rt1-Os | C | C | C | C |  |
| `-[Kid getAssoc]` | rt1-Os | C | C | C | C |  |
| `-[Kid perf:]` | rt1-Os | C | C | C | C |  |
| `-[Kid arr]` | rt1-Os | C | P | C | P | both `return 0x41a8`: constant NSArray left as a raw address |
| `-[Kid dict:]` | rt1-Os | C | C | C | P | S: objects/keys buffers passed as `local_30`/`local_38`, @"k" and v stores not shown |
| `-[Kid boxed:]` | rt1-Os | C | C | C | C |  |
| `+[Kid shared]` | rt1-Os | C | C | C | P | S: `if (x8 != -1) cold.1()`, `return ?` |
| `___13+[Kid shared]_block_invoke` | rt1-Os | W | W | D | W | G: `undefined8 ... return 0` for a void block; S: no signature, opt_new rendered alloc/init, `= x0` |
| `-[Kid fl:]` | rt1-Os | C | P | C | C | G: `extraout_s0 + 1.0` |
| `-[Kid rectW:]` | rt1-Os | C | P | C | P | G: `return in_d2`; S: `return ?` |
| `-[Kid aname] (synth)` | rt1-Os | C | W | C | P | G: `return *(ID *)(param_1 + 8)` but the binary tail-calls objc_getProperty(self,_cmd,8,1); S: `objc_getProperty(self, ?, 8, 1)` |
| `-[Kid setAname:] (synth)` | rt1-Os | C | W | C | W | binary tail-calls objc_setProperty_atomic(self,_cmd,v,8); G: `*(param_1+8) = param_3`; S: `self->_aname = arg0` |
| `-[Kid delegate] (synth)` | rt1-Os | C | W | C | C | G: plain load, drops objc_loadWeakRetained |
| `-[Kid setDelegate:] (synth)` | rt1-Os | C | W | C | C | G: plain store, drops objc_storeWeak |
| `-[Base value]` | rt1c-O2 | C | C | C | C |  |
| `-[Base rect]` | rt1c-O2 | C | C | C | D | S: `return ?` for the {1,2,3,4} HFA |
| `-[Base scale]` | rt1c-O2 | C | C | C | C |  |
| `+[Kid initialize]` | rt1c-O2 | C | C | C | P | S: `if (x19 == [Kid class])`, self left as raw x19 |
| `+[Kid load]` | rt1c-O2 | C | C | C | C |  |
| `-[Kid value]` | rt1c-O2 | C | C | C | P | S: `[super value]` then `return (? + 1)` |
| `-[Kid rect]` | rt1c-O2 | C | C | C | P | S: `[super rect]; return ?`, doubling of x lost to `?` |
| `-[Kid scale]` | rt1c-O2 | C | C | C | P | S: `return (? * 3.0)` |
| `+[Kid fmt:s:]` | rt1c-O2 | C | W | C | C | G: `stringWithFormat_(NSString,&cf__d___)` drops the variadic n and s |
| `-[Kid locked:]` | rt1c-O2 | C | W | C | P | G: `_objc_sync_enter()` with no argument (self is passed); S: `mem32[arg0] = w8`, `return ?` |
| `-[Kid tryit:flag:]` | rt1c-O2 | C | W | C | P | G: catch/finally landing pads omitted, no @"caught" path; S: handlers shown, return value `?` |
| `-[Kid thrower]` | rt1c-O2 | C | C | C | C |  |
| `-[Kid weakHash]` | rt1c-O2 | C | C | C | C |  |
| `-[Kid weakLocal:]` | rt1c-O2 | C | C | C | C |  |
| `-[Kid pool]` | rt1c-O2 | C | W | C | W | G: `arrayWithObjects_(NSArray,&cf_a)` drops @"b", nil; S: drops objc_autoreleasePoolPush/Pop (the @autoreleasepool) |
| `-[Kid allocs]` | rt1c-O2 | C | C | C | C |  |
| `-[Kid news]` | rt1c-O2 | C | C | C | W | S: objc_opt_new rendered `[[NSMutableDictionary alloc] init]`; binary sends +new (equivalent only if +new is not overridden) |
| `-[Kid isStr:]` | rt1c-O2 | C | C | C | C |  |
| `-[Kid resp:]` | rt1c-O2 | C | C | C | C |  |
| `-[Kid cls:]` | rt1c-O2 | C | C | C | C |  |
| `-[Kid sum:]` | rt1c-O2 | C | C | C | P | G: full sum loop; S: `[? integerValue]`, accumulator lost, `return ?` |
| `-[Kid avail]` | rt1c-O2 | C | C | C | C |  |
| `-[Kid assoc:]` | rt1c-O2 | C | C | C | C |  |
| `-[Kid getAssoc]` | rt1c-O2 | C | C | C | C |  |
| `-[Kid perf:]` | rt1c-O2 | C | C | C | C |  |
| `-[Kid arr]` | rt1c-O2 | C | P | C | P | both `return 0x41a8`: constant NSArray left as a raw address |
| `-[Kid dict:]` | rt1c-O2 | C | C | C | P | S: objects/keys buffers passed as `local_30`/`local_38`, @"k" and v stores not shown |
| `-[Kid boxed:]` | rt1c-O2 | C | C | C | C |  |
| `+[Kid shared]` | rt1c-O2 | C | C | C | P | S: `if (x8 != -1) cold.1()`, `return ?` |
| `___13+[Kid shared]_block_invoke` | rt1c-O2 | W | W | D | W | G: `undefined8 ... return 0` for a void block; S: no signature, opt_new rendered alloc/init, `= x0` |
| `-[Kid fl:]` | rt1c-O2 | C | P | C | C | G: `extraout_s0 + 1.0` |
| `-[Kid rectW:]` | rt1c-O2 | C | P | C | P | G: `return in_d2`; S: `return ?` |
| `-[Kid aname] (synth)` | rt1c-O2 | C | W | C | P | G: `return *(ID *)(param_1 + 8)` but the binary tail-calls objc_getProperty(self,_cmd,8,1); S: `objc_getProperty(self, ?, 8, 1)` |
| `-[Kid setAname:] (synth)` | rt1c-O2 | C | W | C | W | binary tail-calls objc_setProperty_atomic(self,_cmd,v,8); G: `*(param_1+8) = param_3`; S: `self->_aname = arg0` |
| `-[Kid delegate] (synth)` | rt1c-O2 | C | W | C | C | G: plain load, drops objc_loadWeakRetained |
| `-[Kid setDelegate:] (synth)` | rt1c-O2 | C | W | C | C | G: plain store, drops objc_storeWeak |
| `-[Base value]` | rt1c-Os | C | C | C | C |  |
| `-[Base rect]` | rt1c-Os | C | C | C | D | S: `return ?` for the {1,2,3,4} HFA |
| `-[Base scale]` | rt1c-Os | C | C | C | C |  |
| `+[Kid initialize]` | rt1c-Os | C | C | C | P | S: `if (x19 == [Kid class])`, self left as raw x19 |
| `+[Kid load]` | rt1c-Os | C | C | C | C |  |
| `-[Kid value]` | rt1c-Os | C | C | C | P | S: `[super value]` then `return (? + 1)` |
| `-[Kid rect]` | rt1c-Os | C | C | C | P | S: `[super rect]; return ?`, doubling of x lost to `?` |
| `-[Kid scale]` | rt1c-Os | C | C | C | P | S: `return (? * 3.0)` |
| `+[Kid fmt:s:]` | rt1c-Os | C | W | C | C | G: `stringWithFormat_(NSString,&cf__d___)` drops the variadic n and s |
| `-[Kid locked:]` | rt1c-Os | C | W | C | P | G: `_objc_sync_enter()` with no argument (self is passed); S: `mem32[arg0] = w8`, `return ?` |
| `-[Kid tryit:flag:]` | rt1c-Os | C | W | C | P | G: catch/finally landing pads omitted, no @"caught" path; S: handlers shown, return value `?` |
| `-[Kid thrower]` | rt1c-Os | C | C | C | C |  |
| `-[Kid weakHash]` | rt1c-Os | C | C | C | C |  |
| `-[Kid weakLocal:]` | rt1c-Os | C | C | C | C |  |
| `-[Kid pool]` | rt1c-Os | C | W | C | W | G: `arrayWithObjects_(NSArray,&cf_a)` drops @"b", nil; S: drops objc_autoreleasePoolPush/Pop (the @autoreleasepool) |
| `-[Kid allocs]` | rt1c-Os | C | C | C | C |  |
| `-[Kid news]` | rt1c-Os | C | C | C | W | S: objc_opt_new rendered `[[NSMutableDictionary alloc] init]`; binary sends +new (equivalent only if +new is not overridden) |
| `-[Kid isStr:]` | rt1c-Os | C | C | C | C |  |
| `-[Kid resp:]` | rt1c-Os | C | C | C | C |  |
| `-[Kid cls:]` | rt1c-Os | C | C | C | C |  |
| `-[Kid sum:]` | rt1c-Os | C | C | C | P | G: full sum loop; S: `[? integerValue]`, accumulator lost, `return ?` |
| `-[Kid avail]` | rt1c-Os | C | C | C | C |  |
| `-[Kid assoc:]` | rt1c-Os | C | C | C | C |  |
| `-[Kid getAssoc]` | rt1c-Os | C | C | C | C |  |
| `-[Kid perf:]` | rt1c-Os | C | C | C | C |  |
| `-[Kid arr]` | rt1c-Os | C | P | C | P | both `return 0x41a8`: constant NSArray left as a raw address |
| `-[Kid dict:]` | rt1c-Os | C | C | C | P | S: objects/keys buffers passed as `local_30`/`local_38`, @"k" and v stores not shown |
| `-[Kid boxed:]` | rt1c-Os | C | C | C | C |  |
| `+[Kid shared]` | rt1c-Os | C | C | C | P | S: `if (x8 != -1) cold.1()`, `return ?` |
| `___13+[Kid shared]_block_invoke` | rt1c-Os | W | W | D | W | G: `undefined8 ... return 0` for a void block; S: no signature, opt_new rendered alloc/init, `= x0` |
| `-[Kid fl:]` | rt1c-Os | C | P | C | C | G: `extraout_s0 + 1.0` |
| `-[Kid rectW:]` | rt1c-Os | C | P | C | P | G: `return in_d2`; S: `return ?` |
| `-[Kid aname] (synth)` | rt1c-Os | C | W | C | P | G: `return *(ID *)(param_1 + 8)` but the binary tail-calls objc_getProperty(self,_cmd,8,1); S: `objc_getProperty(self, ?, 8, 1)` |
| `-[Kid setAname:] (synth)` | rt1c-Os | C | W | C | W | binary tail-calls objc_setProperty_atomic(self,_cmd,v,8); G: `*(param_1+8) = param_3`; S: `self->_aname = arg0` |
| `-[Kid delegate] (synth)` | rt1c-Os | C | W | C | C | G: plain load, drops objc_loadWeakRetained |
| `-[Kid setDelegate:] (synth)` | rt1c-Os | C | W | C | C | G: plain store, drops objc_storeWeak |
| `-[Base value]` | rt1-O0 | C | C | C | C |  |
| `-[Base rect]` | rt1-O0 | C | P | C | D | G: fields from `_DAT_000020b8`.. constant-pool loads, not values; S: `return ?` |
| `-[Base scale]` | rt1-O0 | C | C | C | C |  |
| `+[Kid initialize]` | rt1-O0 | C | C | C | P | S: `if (x8 == 0)` (x8 = self - [Kid class]), raw register |
| `+[Kid load]` | rt1-O0 | C | C | C | C |  |
| `-[Kid value]` | rt1-O0 | C | C | C | P | S: `[super value]` then `return (? + 1)` |
| `-[Kid rect]` | rt1-O0 | C | C | C | P | S: `[super rect]; return ?`, doubling of x lost to `?` |
| `-[Kid scale]` | rt1-O0 | C | C | C | P | S: `return (? * 3.0)` |
| `+[Kid fmt:s:]` | rt1-O0 | C | W | C | P | G: drops n, s; S: `stringWithFormat:@"%d-%@", ?, ?` |
| `-[Kid locked:]` | rt1-O0 | C | W | C | P | G: `_objc_sync_enter()` with no argument (self is passed); S: `mem32[arg0] = w8`, `return ?` |
| `-[Kid tryit:flag:]` | rt1-O0 | C | W | C | P | G: catch/finally landing pads omitted, no @"caught" path; S: handlers shown, return value `?` |
| `-[Kid thrower]` | rt1-O0 | C | C | C | C |  |
| `-[Kid weakHash]` | rt1-O0 | C | C | C | C |  |
| `-[Kid weakLocal:]` | rt1-O0 | C | W | C | P | G: `length(IStack_30)` reads the weak slot directly, drops objc_loadWeakRetained; S: `objc_initWeak(local_30, ?)` |
| `-[Kid pool]` | rt1-O0 | C | W | C | W | G: drops @"b", nil; S: drops the autorelease pool push/pop, `return ?` |
| `-[Kid allocs]` | rt1-O0 | C | C | C | C |  |
| `-[Kid news]` | rt1-O0 | C | C | C | W | S: objc_opt_new rendered `[[NSMutableDictionary alloc] init]`; binary sends +new (equivalent only if +new is not overridden) |
| `-[Kid isStr:]` | rt1-O0 | C | C | C | P | S: receiver `?` |
| `-[Kid resp:]` | rt1-O0 | C | C | C | P | S: receiver `?` |
| `-[Kid cls:]` | rt1-O0 | C | C | C | P | S: receiver `?` |
| `-[Kid sum:]` | rt1-O0 | C | W | C | P | G: `_objc_enumerationMutation(*local_100 - lVar2, self)` invents a first argument; S: `[? ...]`, `return ?` |
| `-[Kid avail]` | rt1-O0 | C | C | C | C |  |
| `-[Kid assoc:]` | rt1-O0 | C | C | C | P | S: `objc_setAssociatedObject(?, 0x83b8, ?, 1)` |
| `-[Kid getAssoc]` | rt1-O0 | C | C | C | C |  |
| `-[Kid perf:]` | rt1-O0 | C | C | C | P | S: receiver `?` |
| `-[Kid arr]` | rt1-O0 | C | P | C | P | both `return 0x41a8`: constant NSArray left as a raw address |
| `-[Kid dict:]` | rt1-O0 | C | C | C | P | S: objects/keys buffers passed as `local_30`/`local_38`, @"k" and v stores not shown |
| `-[Kid boxed:]` | rt1-O0 | C | C | C | C |  |
| `+[Kid shared]` | rt1-O0 | C | W | C | P | G: `_dispatch_once(_shared_once + 1, &_shared_once, &block)` invents a first argument; S: `dispatch_once(?, ?)`, `return ?` |
| `___13+[Kid shared]_block_invoke` | rt1-O0 | C | C | D | W | S: no signature, opt_new rendered alloc/init, `= x8` |
| `-[Kid fl:]` | rt1-O0 | C | P | C | P | G: `extraout_s0`; S: receiver `?` |
| `-[Kid rectW:]` | rt1-O0 | C | P | C | P | G: `return in_d2`; S: receiver `?`, `return ?` |
| `-[Kid aname] (synth)` | rt1-O0 | C | W | C | P | G: `return *(ID *)(param_1 + 8)` but the binary tail-calls objc_getProperty(self,_cmd,8,1); S: `objc_getProperty(self, ?, 8, 1)` |
| `-[Kid setAname:] (synth)` | rt1-O0 | C | W | C | P | G: plain store; S: `objc_setProperty_atomic(self, ?, arg0, 8)` |
| `-[Kid delegate] (synth)` | rt1-O0 | C | W | C | C | G: plain load, drops objc_loadWeakRetained |
| `-[Kid setDelegate:] (synth)` | rt1-O0 | C | W | C | C | G: plain store, drops objc_storeWeak |
| `-[Base value]` | rt1c-O0 | C | C | C | C |  |
| `-[Base rect]` | rt1c-O0 | C | P | C | D | G: fields from `_DAT_000020b8`.. constant-pool loads, not values; S: `return ?` |
| `-[Base scale]` | rt1c-O0 | C | C | C | C |  |
| `+[Kid initialize]` | rt1c-O0 | C | C | C | P | S: `if (x8 == 0)` (x8 = self - [Kid class]), raw register |
| `+[Kid load]` | rt1c-O0 | C | C | C | C |  |
| `-[Kid value]` | rt1c-O0 | C | C | C | P | S: `[super value]` then `return (? + 1)` |
| `-[Kid rect]` | rt1c-O0 | C | C | C | P | S: `[super rect]; return ?`, doubling of x lost to `?` |
| `-[Kid scale]` | rt1c-O0 | C | C | C | P | S: `return (? * 3.0)` |
| `+[Kid fmt:s:]` | rt1c-O0 | C | W | C | P | G: drops n, s; S: `stringWithFormat:@"%d-%@", ?, ?` |
| `-[Kid locked:]` | rt1c-O0 | C | W | C | P | G: `_objc_sync_enter()` with no argument (self is passed); S: `mem32[arg0] = w8`, `return ?` |
| `-[Kid tryit:flag:]` | rt1c-O0 | C | W | C | P | G: catch/finally landing pads omitted, no @"caught" path; S: handlers shown, return value `?` |
| `-[Kid thrower]` | rt1c-O0 | C | W | C | C | G: classic msgSend pointer `PTR__objc_msgSend` passed as an extra send argument |
| `-[Kid weakHash]` | rt1c-O0 | C | C | C | C |  |
| `-[Kid weakLocal:]` | rt1c-O0 | C | W | C | P | G: `length(IStack_30)` reads the weak slot directly, drops objc_loadWeakRetained; S: `objc_initWeak(local_30, ?)` |
| `-[Kid pool]` | rt1c-O0 | C | W | C | W | G: drops @"b", nil; S: drops the autorelease pool push/pop, `return ?` |
| `-[Kid allocs]` | rt1c-O0 | C | C | C | C |  |
| `-[Kid news]` | rt1c-O0 | C | C | C | W | S: objc_opt_new rendered `[[NSMutableDictionary alloc] init]`; binary sends +new (equivalent only if +new is not overridden) |
| `-[Kid isStr:]` | rt1c-O0 | C | C | C | P | S: receiver `?` |
| `-[Kid resp:]` | rt1c-O0 | C | C | C | P | S: receiver `?` |
| `-[Kid cls:]` | rt1c-O0 | C | C | C | P | S: receiver `?` |
| `-[Kid sum:]` | rt1c-O0 | C | W | C | P | G: `_objc_enumerationMutation(*local_100 - lVar2, self)` invents a first argument; S: `[? ...]`, `return ?` |
| `-[Kid avail]` | rt1c-O0 | C | C | C | C |  |
| `-[Kid assoc:]` | rt1c-O0 | C | C | C | P | S: `objc_setAssociatedObject(?, 0x83b8, ?, 1)` |
| `-[Kid getAssoc]` | rt1c-O0 | C | C | C | C |  |
| `-[Kid perf:]` | rt1c-O0 | C | C | C | P | S: receiver `?` |
| `-[Kid arr]` | rt1c-O0 | C | P | C | P | both `return 0x41a8`: constant NSArray left as a raw address |
| `-[Kid dict:]` | rt1c-O0 | C | W | C | P | G: extra `PTR__objc_msgSend` argument; S: buffers opaque |
| `-[Kid boxed:]` | rt1c-O0 | C | W | C | C | G: extra `PTR__objc_msgSend` argument |
| `+[Kid shared]` | rt1c-O0 | C | W | C | P | G: `_dispatch_once(_shared_once + 1, &_shared_once, &block)` invents a first argument; S: `dispatch_once(?, ?)`, `return ?` |
| `___13+[Kid shared]_block_invoke` | rt1c-O0 | C | C | D | W | S: no signature, opt_new rendered alloc/init, `= x8` |
| `-[Kid fl:]` | rt1c-O0 | C | C | C | P | S: receiver `?` |
| `-[Kid rectW:]` | rt1c-O0 | C | P | C | P | G: `return in_d2`; S: receiver `?`, `return ?` |
| `-[Kid aname] (synth)` | rt1c-O0 | C | W | C | P | G: `return *(ID *)(param_1 + 8)` but the binary tail-calls objc_getProperty(self,_cmd,8,1); S: `objc_getProperty(self, ?, 8, 1)` |
| `-[Kid setAname:] (synth)` | rt1c-O0 | C | W | C | P | G: plain store; S: `objc_setProperty_atomic(self, ?, arg0, 8)` |
| `-[Kid delegate] (synth)` | rt1c-O0 | C | W | C | C | G: plain load, drops objc_loadWeakRetained |
| `-[Kid setDelegate:] (synth)` | rt1c-O0 | C | W | C | C | G: plain store, drops objc_storeWeak |
| `-[P big:]` | rt2-O2 | C | P | C | P | G: k+`_DAT_00001880`.. constant-pool refs, not 1..4; S: `mem128[&result+0x8] = q1` |
| `-[P pair:]` | rt2-O2 | C | C | C | D | S: `return ?` |
| `+[P name]` | rt2-O2 | C | P | C | C | G: `return 0x4000` (cfstring address) |
| `-[P initWithN:]` | rt2-O2 | C | C | C | C |  |
| `-[P n] (synth)` | rt2-O2 | C | C | C | C |  |
| `-[P setN:] (synth)` | rt2-O2 | C | C | C | C |  |
| `+[Q name]` | rt2-O2 | C | C | C | C |  |
| `+[Q selfName]` | rt2-O2 | D | W | C | C | G: function not emitted (single `b _objc_msgSend$name`) |
| `-[Q bigE:]` | rt2-O2 | C | W | C | P | G: `big_(param_3, auStack_38, 3)`: x8 sret buffer shown as the first selector argument; S: `[arg0 big:3]; return ?` |
| `-[Q superBigC:]` | rt2-O2 | C | C | C | P | S: `[super big:arg0]; return ?` |
| `-[Q pairB:]` | rt2-O2 | C | P | C | P | G: `return extraout_x1`; S: `return ?` |
| `-[Q vfmt:n:s:]` | rt2-O2 | C | W | C | C | G: drops d, n, s |
| `-[Q many:b:c:d:e:f:]` | rt2-O2 | C | W | C | C | G: `arrayWithObjects_(NSArray)` drops all nine variadic arguments |
| `-[Q dbl:]` | rt2-O2 | C | C | C | P | S: `numberWithDouble:?` |
| `-[Q kvc:n:]` | rt2-O2 | C | C | C | C |  |
| `-[Q perf2:x:]` | rt2-O2 | C | W | C | C | G: `performSelector_withObject_(param_3, isEqual:)` drops x |
| `-[Q future]` | rt2-O2 | C | C | C | C |  |
| `-[Q resp:]` | rt2-O2 | C | C | C | C |  |
| `-[Q make:]` | rt2-O2 | C | C | C | C |  |
| `-[Q nf:]` | rt2-O2 | C | W | C | P | G: `numberWithFloat_(NSNumber)` drops f; S: `numberWithFloat:?` |
| `-[P big:]` | rt2-Os | C | P | C | P | G: k+`_DAT_00001880`.. constant-pool refs, not 1..4; S: `mem128[&result+0x8] = q1` |
| `-[P pair:]` | rt2-Os | C | C | C | D | S: `return ?` |
| `+[P name]` | rt2-Os | C | P | C | C | G: `return 0x4000` (cfstring address) |
| `-[P initWithN:]` | rt2-Os | C | C | C | C |  |
| `-[P n] (synth)` | rt2-Os | C | C | C | C |  |
| `-[P setN:] (synth)` | rt2-Os | C | C | C | C |  |
| `+[Q name]` | rt2-Os | C | C | C | C |  |
| `+[Q selfName]` | rt2-Os | D | W | C | C | G: function not emitted (single `b _objc_msgSend$name`) |
| `-[Q bigE:]` | rt2-Os | C | W | C | P | G: `big_(param_3, auStack_38, 3)`: x8 sret buffer shown as the first selector argument; S: `[arg0 big:3]; return ?` |
| `-[Q superBigC:]` | rt2-Os | C | C | C | P | S: `[super big:arg0]; return ?` |
| `-[Q pairB:]` | rt2-Os | C | P | C | P | G: `return extraout_x1`; S: `return ?` |
| `-[Q vfmt:n:s:]` | rt2-Os | C | W | C | C | G: drops d, n, s |
| `-[Q many:b:c:d:e:f:]` | rt2-Os | C | W | C | C | G: `arrayWithObjects_(NSArray)` drops all nine variadic arguments |
| `-[Q dbl:]` | rt2-Os | C | C | C | P | S: `numberWithDouble:?` |
| `-[Q kvc:n:]` | rt2-Os | C | C | C | C |  |
| `-[Q perf2:x:]` | rt2-Os | C | W | C | C | G: `performSelector_withObject_(param_3, isEqual:)` drops x |
| `-[Q future]` | rt2-Os | C | C | C | C |  |
| `-[Q resp:]` | rt2-Os | C | C | C | C |  |
| `-[Q make:]` | rt2-Os | C | C | C | C |  |
| `-[Q nf:]` | rt2-Os | C | W | C | P | G: `numberWithFloat_(NSNumber)` drops f; S: `numberWithFloat:?` |
| `-[P big:]` | rt2c-O2 | C | P | C | P | G: k+`_DAT_00001880`.. constant-pool refs, not 1..4; S: `mem128[&result+0x8] = q1` |
| `-[P pair:]` | rt2c-O2 | C | C | C | D | S: `return ?` |
| `+[P name]` | rt2c-O2 | C | P | C | C | G: `return 0x4000` (cfstring address) |
| `-[P initWithN:]` | rt2c-O2 | C | C | C | C |  |
| `-[P n] (synth)` | rt2c-O2 | C | C | C | C |  |
| `-[P setN:] (synth)` | rt2c-O2 | C | C | C | C |  |
| `+[Q name]` | rt2c-O2 | C | C | C | C |  |
| `+[Q selfName]` | rt2c-O2 | C | C | C | C |  |
| `-[Q bigE:]` | rt2c-O2 | C | W | C | P | G: `big_(param_3, auStack_38, 3)`: x8 sret buffer shown as the first selector argument; S: `[arg0 big:3]; return ?` |
| `-[Q superBigC:]` | rt2c-O2 | C | C | C | P | S: `[super big:arg0]; return ?` |
| `-[Q pairB:]` | rt2c-O2 | C | P | C | P | G: `return extraout_x1`; S: `return ?` |
| `-[Q vfmt:n:s:]` | rt2c-O2 | C | W | C | C | G: drops d, n, s |
| `-[Q many:b:c:d:e:f:]` | rt2c-O2 | C | W | C | C | G: `arrayWithObjects_(NSArray)` drops all nine variadic arguments |
| `-[Q dbl:]` | rt2c-O2 | C | C | C | P | S: `numberWithDouble:?` |
| `-[Q kvc:n:]` | rt2c-O2 | C | C | C | C |  |
| `-[Q perf2:x:]` | rt2c-O2 | C | W | C | C | G: `performSelector_withObject_(param_3, isEqual:)` drops x |
| `-[Q future]` | rt2c-O2 | C | C | C | C |  |
| `-[Q resp:]` | rt2c-O2 | C | C | C | C |  |
| `-[Q make:]` | rt2c-O2 | C | C | C | C |  |
| `-[Q nf:]` | rt2c-O2 | C | W | C | P | G: `numberWithFloat_(NSNumber)` drops f; S: `numberWithFloat:?` |
| `-[P big:]` | rt2c-Os | C | P | C | P | G: k+`_DAT_00001880`.. constant-pool refs, not 1..4; S: `mem128[&result+0x8] = q1` |
| `-[P pair:]` | rt2c-Os | C | C | C | D | S: `return ?` |
| `+[P name]` | rt2c-Os | C | P | C | C | G: `return 0x4000` (cfstring address) |
| `-[P initWithN:]` | rt2c-Os | C | C | C | C |  |
| `-[P n] (synth)` | rt2c-Os | C | C | C | C |  |
| `-[P setN:] (synth)` | rt2c-Os | C | C | C | C |  |
| `+[Q name]` | rt2c-Os | C | C | C | C |  |
| `+[Q selfName]` | rt2c-Os | C | C | C | C |  |
| `-[Q bigE:]` | rt2c-Os | C | W | C | P | G: `big_(param_3, auStack_38, 3)`: x8 sret buffer shown as the first selector argument; S: `[arg0 big:3]; return ?` |
| `-[Q superBigC:]` | rt2c-Os | C | C | C | P | S: `[super big:arg0]; return ?` |
| `-[Q pairB:]` | rt2c-Os | C | P | C | P | G: `return extraout_x1`; S: `return ?` |
| `-[Q vfmt:n:s:]` | rt2c-Os | C | W | C | C | G: drops d, n, s |
| `-[Q many:b:c:d:e:f:]` | rt2c-Os | C | W | C | C | G: `arrayWithObjects_(NSArray)` drops all nine variadic arguments |
| `-[Q dbl:]` | rt2c-Os | C | C | C | P | S: `numberWithDouble:?` |
| `-[Q kvc:n:]` | rt2c-Os | C | C | C | C |  |
| `-[Q perf2:x:]` | rt2c-Os | C | W | C | C | G: `performSelector_withObject_(param_3, isEqual:)` drops x |
| `-[Q future]` | rt2c-Os | C | C | C | C |  |
| `-[Q resp:]` | rt2c-Os | C | C | C | C |  |
| `-[Q make:]` | rt2c-Os | C | C | C | C |  |
| `-[Q nf:]` | rt2c-Os | C | W | C | P | G: `numberWithFloat_(NSNumber)` drops f; S: `numberWithFloat:?` |
| `-[P big:]` | rt2-O0 | C | C | C | P | S: stores right, `return ?` |
| `-[P pair:]` | rt2-O0 | C | C | C | D | S: `return ?` |
| `+[P name]` | rt2-O0 | C | P | C | C | G: `return 0x4000` (cfstring address) |
| `-[P initWithN:]` | rt2-O0 | C | C | C | P | S: `if (x0 != 0) mem64[x9 + 0x8] = x8`, `return ?` |
| `-[P n] (synth)` | rt2-O0 | C | C | C | C |  |
| `-[P setN:] (synth)` | rt2-O0 | C | C | C | C |  |
| `+[Q name]` | rt2-O0 | C | C | C | C |  |
| `+[Q selfName]` | rt2-O0 | C | C | C | C |  |
| `-[Q bigE:]` | rt2-O0 | C | W | C | P | G: sret buffer as first selector argument; S: `[? big:3]`, `return ?` |
| `-[Q superBigC:]` | rt2-O0 | C | C | C | P | S: `[super big:arg0]; return ?` |
| `-[Q pairB:]` | rt2-O0 | C | P | C | P | G: `extraout_x1`; S: receiver `?` |
| `-[Q vfmt:n:s:]` | rt2-O0 | C | W | C | P | G: drops d, n, s; S: `@"%f %ld %@", ?, ?, ?` |
| `-[Q many:b:c:d:e:f:]` | rt2-O0 | C | W | C | P | G: keeps only param_3; S: all nine arguments `?` |
| `-[Q dbl:]` | rt2-O0 | C | C | C | P | S: `numberWithDouble:?` |
| `-[Q kvc:n:]` | rt2-O0 | C | W | C | P | G: `setValue_forKey_(param_3)` drops value and key; S: receiver `?` |
| `-[Q perf2:x:]` | rt2-O0 | C | C | C | P | S: receiver and object `?` |
| `-[Q future]` | rt2-O0 | C | W | C | P | G: `___isPlatformVersionAtLeast(1,99,0)` drops the fourth argument; S: result via `mem32[x29 - 0x4]`, `return ?` |
| `-[Q resp:]` | rt2-O0 | C | C | C | C |  |
| `-[Q make:]` | rt2-O0 | C | C | C | C |  |
| `-[Q nf:]` | rt2-O0 | C | C | C | P | S: `numberWithFloat:?` |
| `-[P big:]` | rt2c-O0 | C | C | C | P | S: stores right, `return ?` |
| `-[P pair:]` | rt2c-O0 | C | C | C | D | S: `return ?` |
| `+[P name]` | rt2c-O0 | C | P | C | C | G: `return 0x4000` (cfstring address) |
| `-[P initWithN:]` | rt2c-O0 | C | C | C | P | S: `if (x0 != 0) mem64[x9 + 0x8] = x8`, `return ?` |
| `-[P n] (synth)` | rt2c-O0 | C | C | C | C |  |
| `-[P setN:] (synth)` | rt2c-O0 | C | C | C | C |  |
| `+[Q name]` | rt2c-O0 | C | C | C | C |  |
| `+[Q selfName]` | rt2c-O0 | C | C | C | C |  |
| `-[Q bigE:]` | rt2c-O0 | C | W | C | P | G: `objc_msgSend(auStack_50, param_3, big:, 3)`: sret buffer shown as the receiver; S: `return ?` |
| `-[Q superBigC:]` | rt2c-O0 | C | C | C | P | S: `[super big:arg0]; return ?` |
| `-[Q pairB:]` | rt2c-O0 | C | P | C | P | G: `extraout_x1`; S: receiver `?` |
| `-[Q vfmt:n:s:]` | rt2c-O0 | C | W | C | P | G: drops d, n, s; S: `@"%f %ld %@", ?, ?, ?` |
| `-[Q many:b:c:d:e:f:]` | rt2c-O0 | C | W | C | P | G: keeps only param_3; S: all nine arguments `?` |
| `-[Q dbl:]` | rt2c-O0 | C | W | C | P | G: `objc_msgSend(param_3 * 2.0, NSNumber, sel)`: the double shown as receiver; S: `numberWithDouble:?` |
| `-[Q kvc:n:]` | rt2c-O0 | C | W | C | P | G: `setValue_forKey_(param_3)` drops value and key; S: receiver `?` |
| `-[Q perf2:x:]` | rt2c-O0 | C | C | C | P | S: receiver and object `?` |
| `-[Q future]` | rt2c-O0 | C | W | C | P | G: `___isPlatformVersionAtLeast(1,99,0)` drops the fourth argument; S: result via `mem32[x29 - 0x4]`, `return ?` |
| `-[Q resp:]` | rt2c-O0 | C | C | C | C |  |
| `-[Q make:]` | rt2c-O0 | C | C | C | C |  |
| `-[Q nf:]` | rt2c-O0 | C | W | C | P | G: float shown as receiver; S: `numberWithFloat:?` |
| `-[L addInt:]` | rt3-O2 | C | P | C | P | constant object unresolved: G `&NSConstantIntegerNumber_40f0`, S `0x40f0` |
| `-[L addDbl:]` | rt3-O2 | C | P | C | P | constant object unresolved: G `&NSConstantDoubleNumber_4150`, S `0x4150` |
| `-[L addYes:]` | rt3-O2 | C | C | C | C |  |
| `-[L addChar:]` | rt3-O2 | C | P | C | P | constant object unresolved: G `&NSConstantIntegerNumber_4108`, S `0x4108` |
| `-[L addArr:]` | rt3-O2 | C | P | C | P | constant object unresolved: G `&NSConstantArray_4180`, S `0x4180` |
| `-[L addDict:]` | rt3-O2 | C | P | C | P | constant object unresolved: G `&NSConstantDictionary_4198`, S `0x4198` |
| `-[L addStr:]` | rt3-O2 | C | C | C | C |  |
| `-[L addUni:]` | rt3-O2 | C | W | C | W | UTF-16 @"héllo": G `&cf_h`, S `@"h"`, both truncated at the first UTF-16 NUL byte |
| `-[L addEmpty:]` | rt3-O2 | C | P | C | P | G `&cf___`, S `0x40c0`: empty CFString unresolved |
| `-[L addNeg:]` | rt3-O2 | C | P | C | P | constant object unresolved: G `&NSConstantIntegerNumber_4120`, S `0x4120` |
| `-[L addLL:]` | rt3-O2 | C | P | C | P | constant object unresolved: G `&NSConstantIntegerNumber_4138`, S `0x4138` |
| `-[L addF:]` | rt3-O2 | C | P | C | P | constant object unresolved: G `&NSConstantFloatNumber_41c0`, S `0x41c0` |
| `-[L addInt:]` | rt3-O0 | C | P | C | P | constant object unresolved: G `&NSConstantIntegerNumber_40f0`, S `0x40f0`; S receiver `?` |
| `-[L addDbl:]` | rt3-O0 | C | P | C | P | constant object unresolved: G `&NSConstantDoubleNumber_4150`, S `0x4150`; S receiver `?` |
| `-[L addYes:]` | rt3-O0 | C | C | C | P | S: receiver `?` |
| `-[L addChar:]` | rt3-O0 | C | P | C | P | constant object unresolved: G `&NSConstantIntegerNumber_4108`, S `0x4108`; S receiver `?` |
| `-[L addArr:]` | rt3-O0 | C | P | C | P | constant object unresolved: G `&NSConstantArray_4180`, S `0x4180`; S receiver `?` |
| `-[L addDict:]` | rt3-O0 | C | P | C | P | constant object unresolved: G `&NSConstantDictionary_4198`, S `0x4198`; S receiver `?` |
| `-[L addStr:]` | rt3-O0 | C | C | C | P | S: receiver `?` |
| `-[L addUni:]` | rt3-O0 | C | W | C | W | UTF-16 @"héllo": G `&cf_h`, S `@"h"`, both truncated at the first UTF-16 NUL byte; S receiver `?` |
| `-[L addEmpty:]` | rt3-O0 | C | P | C | P | G `&cf___`, S `0x40c0`: empty CFString unresolved; S receiver `?` |
| `-[L addNeg:]` | rt3-O0 | C | P | C | P | constant object unresolved: G `&NSConstantIntegerNumber_4120`, S `0x4120`; S receiver `?` |
| `-[L addLL:]` | rt3-O0 | C | P | C | P | constant object unresolved: G `&NSConstantIntegerNumber_4138`, S `0x4138`; S receiver `?` |
| `-[L addF:]` | rt3-O0 | C | P | C | P | constant object unresolved: G `&NSConstantFloatNumber_41c0`, S `0x41c0`; S receiver `?` |
| `-[S nulStr]` | rt4-O2 | C | P | C | W | UTF-16 @"a\0b": G `return 0x4000` (raw), S `return @"a"` (truncated, wrong string) |
| `-[S cjk]` | rt4-O2 | C | P | C | P | UTF-16 @"日本": both `return 0x4020` |
| `-[S ete]` | rt4-O2 | C | P | C | P | UTF-16 @"été": both `return 0x4040` |
| `-[S plain]` | rt4-O2 | C | P | C | C | G: `return 0x4060` |
| `-[S eq:]` | rt4-O2 | C | P | C | P | argument @"été" unresolved: G `&cf__`, S `0x4040` |
| `-[T takeL3:]` | rt5-O2 | C | C | C | D | G: `param_3->field2_0x10` through the indirect pointer; S: `return ?` |
| `-[T takeR4:]` | rt5-O2 | C | C | C | D | G: `param_3.field2_0x10` (w in d2); S: `return ?` |
| `-[T hello]` | rt5-O2 | C | C | C | C |  |
| `-[T frame] (synth)` | rt5-O2 | C | C | C | P | S: `objc_copyStruct(local_30, &self->_frame, 32, 1, 0)` then `return ?` |
| `-[T setFrame:] (synth)` | rt5-O2 | C | C | C | P | S: copies from `local_30` without showing the d0-d3 spill |
| `-[T(Cat) description]` | rt5-O2 | C | C | C | C |  |
| `-[U callL3:]` | rt5-O2 | C | P | C | P | G: {1,2} as `_DAT_00000e40`/`_UNK_00000e48` constant-pool refs; S: `takeL3:?` |
| `-[U callR4:]` | rt5-O2 | C | P | C | P | G: 1.0..4.0 as integer bit patterns `0x3ff0000000000000`.., `return extraout_d0`; S: `takeR4:?` |
| `-[U weakBlock]` | rt5-O2 | C | W | C | P | G: `return (ID)&local_50`, a stack block address: drops objc_retainBlock; S: block literal and retainBlock hidden, `return ?` |
| `___14-[U weakBlock]_block_invoke` | rt5-O2 | W | W | D | C | G: `hello(*(ID *)(param_1 + 0x20))` drops objc_loadWeakRetained, and `return 0` on a void block; S: no signature, body exact |
| `-[U byName]` | rt5-O2 | C | C | C | C |  |
| `-[U superLen]` | rt5-O2 | C | C | C | C |  |
| `-[T takeL3:]` | rt5-O0 | C | C | C | D | G: `param_3->field2_0x10` through the indirect pointer; S: `return ?` |
| `-[T takeR4:]` | rt5-O0 | C | C | C | D | G: `param_3.field2_0x10` (w in d2); S: `return ?` |
| `-[T hello]` | rt5-O0 | C | C | C | C |  |
| `-[T frame] (synth)` | rt5-O0 | C | C | C | P | S: `objc_copyStruct(local_30, &self->_frame, 32, 1, 0)` then `return ?` |
| `-[T setFrame:] (synth)` | rt5-O0 | C | C | C | P | S: copies from `local_30` without showing the d0-d3 spill |
| `-[T(Cat) description]` | rt5-O0 | C | C | C | C |  |
| `-[U callL3:]` | rt5-O0 | C | P | C | P | G: constant-pool refs; S: `[? takeL3:?]` |
| `-[U callR4:]` | rt5-O0 | C | P | C | P | G: `_DAT_00001168`.. constant-pool refs, `extraout_d0`; S: `[? takeR4:?]` |
| `-[U weakBlock]` | rt5-O0 | C | W | C | P | G: `return (ID)&local_50`, a stack block address: drops objc_retainBlock; S: block literal and retainBlock hidden, `return ?` |
| `___14-[U weakBlock]_block_invoke` | rt5-O0 | C | W | D | C | G: drops objc_loadWeakRetained; S: no signature, body exact |
| `-[U byName]` | rt5-O0 | C | C | C | C |  |
| `-[U superLen]` | rt5-O0 | C | C | C | C |  |

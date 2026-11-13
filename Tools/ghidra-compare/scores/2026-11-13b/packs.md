# packs: Ghidra 12.2 vs swiftdc, scored against the binaries

> Re-scored 2026-11-13b: swiftdc columns only, against `2026-11-13b/renders/`, by `2026-11-13b/scores/RUBRIC.md` and its addendum. Ghidra's columns are copied unchanged. A row whose swiftdc text did not change keeps its old scores. 13 rows changed score, none for the worse.

Fixtures: `abi2/packs/` g.swift (O, Onone, Osize, evo), g2.swift (O, evo), c.swift (O, Onone; client of G), s3.swift (O, Onone, Osize), t.swift (O), t2.swift (O, Onone), hc.swift (O; client of H), f.swift (evo). 206 function-builds scored. Truth: source comments plus `llvm-objdump -d` read by hand, `nm` for aliases, `dyld_info -fixups` for callees.

Scope: user-written functions, inits, methods, subscripts and computed getters. Skipped: synthesized stored-property accessors, derived `==`, protocol witness thunks, value witnesses, metadata accessors, `__allocating_init`/deinit, outlined helpers, specializations the compiler cloned, `variable initialization expression`. f.swift has only one user function (`Base.init`). No standalone `ident<Int>` specialization symbol exists in any build.

Conventions, applied identically to both tools:
- Type metadata, witness tables and the x8 indirect-result pointer are not required arguments, but anything shown must be right.
- A dropped value argument is WRONG. That includes the swiftself receiver in x20 of a witness or method call.
- A raw register (`in_xN`, `extraout_xN`, swiftdc `xN`) standing for a parameter makes the interface DECLINED. In a body it makes the body PARTIAL.
- A tail call whose value is the result is WRONG when it is rendered without returning that value. So is a Ghidra `void` prototype on a function that returns a value: that is WRONG on both axes.
- A body of only `return ?` is DECLINED.
- Several symbols aliased at one address (identical code folded): a tool that prints the function under another alias's name, or as an unnamed `sub_`, is DECLINED/DECLINED for that function. Exception (addendum): a `sub_` that ends `return // x0 = <value>` has its body judged on that value; its interface stays DECLINED.
- A zero-sized `self` shown or omitted is neutral.

## Totals (206)

| tool / axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|
| Ghidra interface | 125 | 0 | 21 | 60 |
| Ghidra body | 62 | 49 | 81 | 14 |
| swiftdc interface | 157 | 0 | 0 | 49 |
| swiftdc body | 41 | 69 | 38 | 58 |

Previous swiftdc totals (2026-11-13): interface 157 / 0 / 0 / 49, body 29 / 69 / 44 / 64.

Per build (C/P/W/D):

| build | n | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body |
|---|---|---|---|---|---|
| g O | 27 | 16/0/2/9 | 5/8/13/1 | 3/13/5/6 |
| g Onone | 27 | 16/0/2/9 | 5/7/15/0 | 26/0/0/1 | 4/14/6/3 |
| g Osize | 27 | 15/0/3/9 | 5/11/10/1 | 3/13/5/6 |
| g evo | 27 | 16/0/3/8 | 4/10/13/0 | 5/8/8/6 |
| g2 O | 25 | 12/0/2/11 | 10/5/5/5 | 6/5/3/11 |
| g2 evo | 25 | 12/0/2/11 | 10/5/5/5 | 6/5/3/11 |
| c O | 7 | 5/0/1/1 | 0/0/7/0 | 7/0/0/0 | 1/3/3/0 |
| c Onone | 7 | 5/0/2/0 | 0/0/7/0 | 7/0/0/0 | 1/3/3/0 |
| s3 O | 8 | 8/0/0/0 | 7/1/0/0 | 7/0/0/1 | 2/1/1/4 |
| s3 Onone | 8 | 8/0/0/0 | 6/1/1/0 | 8/0/0/0 | 1/1/1/5 |
| s3 Osize | 8 | 8/0/0/0 | 7/1/0/0 | 7/0/0/1 | 2/1/0/5 |
| t O | 4 | 1/0/2/1 | 1/0/2/1 | 3/1/0/0 |
| t2 O | 2 | 1/0/0/1 | 1/0/0/1 | 2/0/0/0 |
| t2 Onone | 2 | 0/0/2/0 | 0/0/2/0 | 2/0/0/0 |
| hc O | 1 | 1/0/0/0 | 0/0/1/0 | 1/0/0/0 | 0/1/0/0 |
| f evo | 1 | 1/0/0/0 | 1/0/0/0 | 0/0/0/1 | 0/0/0/1 |

Where the WRONG cells come from:
- swiftdc's 38 WRONG bodies fall into these classes:
  - 16 drop an x20 receiver. Ghidra drops the same receiver in every one of them.
  - 7 are tail calls rendered without `return`. Examples: `G.Sq.init(s:)(arg0)`, `sub_c28()`. The six runtime tail calls (`swift_getDynamicType(…)`, `swift_getObjectType(arg0)`) are now returned and left this class.
  - 5 drop an overflow trap (`adds; b.vs` -> `brk` in makeColl and packCount).
  - 6 drop a copy into a buffer: `outlined init with copy/take of Any` in Store.subscript and anyPack, and the temp-to-result copy in Pair.init at Onone.
  - The rest lose an accumulation or a returned product: sumAny's `t += x`, and Pair.area at evo.
- Ghidra's 81 WRONG bodies are mostly argument loss. It drops x20 self on witness and method calls everywhere, and it shows value-witness and runtime calls with empty argument lists: `(**(vwt+0x10))()`, `_packCount()`, `_swift_dynamicCast()`. It also has `void` on tail calls, the small string "x" rendered as `section_00000068.segname`, and metadata passed where `&a` goes in `Pair.init` calls.
- swiftdc's 49 DECLINED interfaces are aliased symbols printed as `sub_XXX`, plus bodies that read the pack count or self as a raw register. Its 58 DECLINED bodies are mostly `return ?` on one- or two-instruction leaves: `add x0,x0,#1`, `mov w0,#7`, `ldr x0,[x0,#0x10]`.

## Most telling examples

### Where swiftdc beats Ghidra

1. **someParam, c O.** Source: `x.area()`. The asm does `mov x20, x0; mov x0, x1; mov x1, x2; bl area`.
   - Ghidra: `__int64 _someParam(void) { _Var1 = G::Shape::area(); return _Var1; }`. That is no parameter and no receiver.
   - swiftdc: `return dispatch thunk of G.Shape.area(self: arg0)`. Exact.
2. **IntC.first getter, g O/Osize/evo.** Source: `"x"`. The asm is `mov w0,#0x78; mov x1,#0xe100000000000000`.
   - Ghidra: `SVar1.bridgeObject = 0xe100000000000000; SVar1.str = section_00000068.segname;`. That is a false symbol.
   - swiftdc: `return "x"`.
3. **f, t O.** Source: `g(x &+ 1)`, lowered as `add x0,x0,#1; b g`.
   - Ghidra: `void __s1T1fyS2iF(long param_1) { __s1T1gyS2iF(param_1 + 1); return; }`. The result is lost.
   - swiftdc: `return T.g((arg0 + 1))`.
   - The same pattern recurs in `h` at t2 Onone. Ghidra gives `void … { _labs(param_1); return; }`, swiftdc gives `return labs(arg0)`.

### Where Ghidra beats swiftdc

1. **makeColl, g O/Onone/Osize/evo.** Source: `[n, n + 1]`. The asm is `adds x8, x20, #0x1; b.vs -> brk #1`.
   - Ghidra: `if (SCARRY8(param_1,1)) { SoftwareBreakpoint(…) } *(lVar3 + 0x28) = param_1 + 1;`.
   - swiftdc: `mem64[x0 + 0x28] = (arg0 + 1)`. The trap is silently gone.
2. **Small leaves, s3 all levels, countDict and sizeOf.** For `K.subscript(i) -> i &+ 1`, the asm is `add x0,x0,#1; ret`.
   - Ghidra: `return param_1 + 1;`.
   - swiftdc: `return ?`.
   - The same happens with `countDict`: Ghidra gives `return *(param_1 + 0x10)`, swiftdc gives `return ?`. It also happens in both generic subscripts (7 and 8) and in `KC.init` at Onone.
3. **sumAny, g O.** Source: `for x in s { t += x }; return t`.
   - Ghidra: `do { …next(); if (local_60 == 1) { destroy; return lVar6; } bVar4 = SCARRY8(lVar6,local_68); lVar6 += local_68; } while (!bVar4); trap`. It drops makeIterator's receiver but keeps the sum, the trap and the result.
   - swiftdc: `while (true) { next(self: …); if (w8 == 1) break }; return ?`. The accumulation and the trap are missing.

## Per-function table

| function | level | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| useOpaque | c O | CORRECT | WRONG | CORRECT | WRONG | both drop area()'s self (x20 = the opaque result buffer): Ghidra `G::Shape::area()`, swiftdc `dispatch thunk of G.Shape.area()` |
| useColl | c O | CORRECT | WRONG | CORRECT | WRONG | both drop count getter's self (x20 = buffer) |
| openIt | c O | DECLINED | WRONG | CORRECT | PARTIAL | Ghidra `(void)` on in_x0, `area()` without self; swiftdc `area(self: __swift_project_boxed_opaque_existential_1(?, ?))` |
| pairEq | c O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra `Pair::init(buf, lVar3, &local_50, Int)`: passes the Pair<Int> metadata where &a goes, a dropped; swiftdc `init(a:b:)(?, ?)` x2, `==(?, ?)`, `return r0 & 1` |
| someParam | c O | WRONG | WRONG | CORRECT | CORRECT | Ghidra `(void)` though x0..x2 are read, `area()` without self; swiftdc `area(self: arg0)` |
| usePack | c O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra `_packCount()` drops the value pack, count 3 and metadata pack; swiftdc `packCount(local_38, 3, local_70)` (stack slots, contents not shown) |
| useSub | c O | CORRECT | WRONG | CORRECT | WRONG | both drop the getter's self (x20 = s): Ghidra `get_subscript(param_2, Int)`, swiftdc `subscript.getter(?, ?)`, `return ?` |
| useOpaque | c Onone | CORRECT | WRONG | CORRECT | WRONG | both drop area()'s self; Ghidra also passes chkstk's "result" to makeShape |
| useColl | c Onone | CORRECT | WRONG | CORRECT | WRONG | both drop count getter's self |
| openIt | c Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `(void)` with x0 read, `project()` and `area()` with no args; swiftdc `area(self: project(?, ?))` |
| pairEq | c Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra first `Pair::init(lVar3, &local_28)`: metadata in the &a slot, a dropped; swiftdc `?` args |
| someParam | c Onone | WRONG | WRONG | CORRECT | CORRECT | Ghidra `(void)`, `area()` without self |
| usePack | c Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra `_packCount()` with no args; swiftdc `packCount(local_28, 3, local_60)` plus a bare `"a"` statement |
| useSub | c Onone | CORRECT | WRONG | CORRECT | WRONG | both drop self (x20 = s); Ghidra also `_swift_bridgeObjectRetain()` with no arg |
| K.init | s3 O | CORRECT | PARTIAL | CORRECT | PARTIAL | empty struct: Ghidra `return in_x0`, swiftdc `return ?` |
| K.five getter | s3 O | CORRECT | CORRECT | CORRECT | CORRECT | |
| K.subscript(i) | s3 O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` for `add x0,x0,#1` |
| K.subscript<T>(t) | s3 O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` for `mov w0,#7` |
| KC.init | s3 O | CORRECT | CORRECT | DECLINED | DECLINED | aliased with KC.deinit at 0x814; Ghidra `return this`, swiftdc `sub_814` |
| KC.subscript(i) | s3 O | CORRECT | CORRECT | CORRECT | WRONG | tail call to the specialization: Ghidra inlines `return param_1 + 2`; swiftdc `specialization…getter(arg0)` with no `return` |
| KC.subscript<T>(g:) | s3 O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` for `mov w0,#8` |
| useKC | s3 O | CORRECT | CORRECT | CORRECT | CORRECT | |
| K.init | s3 Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | empty struct: Ghidra `return in_x0`, swiftdc `return ?` |
| K.five getter | s3 Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| K.subscript(i) | s3 Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` |
| K.subscript<T>(t) | s3 Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` |
| KC.init | s3 Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` for `return self` |
| KC.subscript(i) | s3 Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` for `adds x0,x0,#2` |
| KC.subscript<T>(g:) | s3 Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` |
| useKC | s3 Onone | CORRECT | WRONG | CORRECT | WRONG | both drop the receiver k (x20 = x0) of `kc[i]`: Ghidra `KC::get_subscript(param_2) * 3`, swiftdc `3 * S3.KC.subscript.getter(arg1)` |
| K.init | s3 Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | empty struct: Ghidra `return in_x0`, swiftdc `return ?` |
| K.five getter | s3 Osize | CORRECT | CORRECT | CORRECT | CORRECT | |
| K.subscript(i) | s3 Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` |
| K.subscript<T>(t) | s3 Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` |
| KC.init | s3 Osize | CORRECT | CORRECT | DECLINED | DECLINED | aliased with KC.deinit at 0x7c4; swiftdc `sub_7c4` |
| KC.subscript(i) | s3 Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` for `add x0,x0,#2` |
| KC.subscript<T>(g:) | s3 Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` |
| useKC | s3 Osize | CORRECT | CORRECT | CORRECT | CORRECT | self is dead here (x20 not set) |
| g | t O | CORRECT | CORRECT | CORRECT | CORRECT | |
| f | t O | WRONG | WRONG | CORRECT | CORRECT | tail call `b g`: Ghidra `void`, `g(param_1 + 1)` with no return; swiftdc `return T.g((arg0 + 1))` |
| dynAny | t O | WRONG | WRONG | CORRECT | PARTIAL | tail call to swift_getDynamicType: Ghidra `void`; swiftdc now returns the call (was no `return`), still `project(?, ?)` and metadata `?` |
| metaOf | t O | DECLINED | DECLINED | CORRECT | CORRECT | Ghidra: not emitted (single `b` to the stub); swiftdc now `return swift_getObjectType(arg0)` (was no `return`) |
| h | t2 O | CORRECT | CORRECT | CORRECT | CORRECT | labs inlined to `cmp; cneg`: both give the absolute value |
| metaInt | t2 O | DECLINED | DECLINED | CORRECT | CORRECT | Ghidra: not emitted; swiftdc now `return swift_getObjectType(arg0)` (was no `return`) |
| h | t2 Onone | WRONG | WRONG | CORRECT | CORRECT | Ghidra `void`, `_labs(param_1)` with result dropped; swiftdc `return labs(arg0)` |
| metaInt | t2 Onone | WRONG | WRONG | CORRECT | CORRECT | Ghidra `void (void)`, `_swift_getObjectType()` with no arg; swiftdc now `return swift_getObjectType(arg0)` (was the call then `return ?`) |
| cl | hc O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra drops area's self (x20 = buffer): `area(lVar2, uVar3)`; swiftdc `area(self: ?)`, destroy unresolved, `return r0` |
| Sq.init(s:) | g O | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc: aliased with Sq.s.getter/IntC.init at 0x978, rendered `sub_978` with no body |
| Sq.area | g O | CORRECT | CORRECT | CORRECT | CORRECT | |
| packCount | g O | DECLINED | PARTIAL | DECLINED | PARTIAL | Ghidra `(void)`, `return in_x1`; swiftdc trap structure right on raw x1, `return ?`; swiftdc interface: body reads raw x1 (pack count) for a parameter |
| packWrap | g O | DECLINED | PARTIAL | DECLINED | PARTIAL | Ghidra loop (copy, then storeEnumTag(…,0,1,T)) right on raw in_x0/in_x1/in_x8; swiftdc unresolved calls, loop on raw x19; swiftdc interface: body reads raw x1 (pack count) for a parameter |
| Box.init | g O | DECLINED | WRONG | DECLINED | PARTIAL | Ghidra empty-pack initializeWithCopy `(**(vwt+0x10))()` with no args, returns destroy()'s result as the Box; swiftdc raw-register copy loops, unresolved calls, `return ?`; swiftdc interface: body reads raw x20 (copy of the pack count) for a parameter |
| makeShape | g O | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra `*in_x8 = param_1`; swiftdc `mem64[&result] = arg0; return ?` |
| makeColl | g O | CORRECT | PARTIAL | CORRECT | WRONG | Ghidra header words as `_DAT_`/`_UNK_` globals, trap kept; swiftdc drops the `n + 1` overflow trap (`adds; b.vs` -> brk) |
| sumAny | g O | DECLINED | WRONG | CORRECT | WRONG | both drop makeIterator()'s self (x20); Ghidra keeps sum and trap; swiftdc also drops `t += x`, the trap and the result (`return ?`) |
| anySeq | g O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra `get_description()` drops self (&n) and stores the cache variable address as the witness table (`in_x8[4] = puVar4`); swiftdc `description.getter(self: local_38)`, stores via raw x0/x22 |
| firstEq | g O | CORRECT | WRONG | CORRECT | WRONG | both drop the receiver of the first makeIterator(); swiftdc also renders the tail as unresolved calls and `return ?` over the true/false/== result |
| Pair.init(a:b:) | g O | CORRECT | CORRECT | CORRECT | DECLINED | Ghidra initializeWithTake(result, a) then tail (result+offset(b), b, T) with x8 as param_1; swiftdc one unresolved call and an unresolved jump |
| Pair.area (T == Int) | g O | DECLINED | PARTIAL | CORRECT | PARTIAL | Ghidra `(void)`, a*b with trap on in_x0/in_x1; swiftdc trap test on raw x8/x0, `return ?` |
| IntC.first getter | g O | CORRECT | WRONG | CORRECT | CORRECT | Ghidra renders the small string "x" as `str = section_00000068.segname` |
| IntC.init | g O | DECLINED | DECLINED | DECLINED | DECLINED | aliased at 0x978: Ghidra names it Sq.init only, swiftdc `sub_978` |
| hashFirst | g O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra drops self (x20 = c) of the `first` witness call and of `get_hashValue()`; swiftdc first call unresolved, `hashValue(self: ?)` |
| Store.init | g O | CORRECT | WRONG | CORRECT | WRONG | tail call into Store.d's initializer: Ghidra `Dictionary::_init()` drops the empty-literal argument; swiftdc shows the call with no `return` |
| Store.subscript getter | g O | WRONG | WRONG | CORRECT | WRONG | Ghidra types x2 as `Store as`, self read as raw in_x3, `_find()`/`_swift_dynamicCast()`/storeEnumTag with no args; swiftdc drops the `outlined init with copy of Any` into local_50 and the nil zeroing |
| countDict | g O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` for `ldr x0,[x0,#0x10]` |
| ident | g O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra generic tail call `initializeWithCopy(param_1)` drops src and T; swiftdc Int path `mem64[&result] = x9` raw, `return ?` |
| sizeOf | g O | DECLINED | PARTIAL | CORRECT | DECLINED | Ghidra `(void)`, vwt size via in_x1; swiftdc `return ?` |
| dynType | g O | WRONG | WRONG | CORRECT | CORRECT | tail call to swift_getDynamicType: Ghidra `void`; swiftdc now `return swift_getDynamicType(arg0, type metadata for A, false)` (was no `return`) |
| isInt | g O | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra copy source is raw `extraout_x1`; swiftdc `(? as? Int) != nil` |
| asShape | g O | CORRECT | PARTIAL | CORRECT | PARTIAL | both: cast plus nil zeroing right; Ghidra copy source raw `extraout_x1`, swiftdc `? as? Shape`, `return ?` |
| describe | g O | DECLINED | WRONG | CORRECT | PARTIAL | Ghidra: name/area witness calls lose self, `append(SVar4, in_x2:in_x3)` with garbage operands; swiftdc witness calls unresolved, `append(self: local_50, r0)` right, `return ?` |
| compo | g O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra `(*(param_4+8))(param_2,param_4)` drops self x20 = x; swiftdc unresolved call, `return ?` |
| Base.init | g O | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc: aliased with Base.deinit at 0x1ed8, `sub_1ed8` with no body |
| clsComp | g O | DECLINED | WRONG | CORRECT | PARTIAL | Ghidra `(*(in_x1+8))(*in_x0)` drops self (x20 = &x); swiftdc unresolved call, `return ?` |
| Sq.init(s:) | g Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` for `return s` |
| Sq.area | g Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| packCount | g Onone | DECLINED | PARTIAL | CORRECT | WRONG | Ghidra loop right but over in_x1; swiftdc `while (x9 != 0) { j += 1; i += 1 }` drops the `n += 1` overflow trap, `return ?` |
| packWrap | g Onone | DECLINED | WRONG | CORRECT | PARTIAL | Ghidra's initializeWithCopy into the temp shows no arguments `(**(vwt+0x10))()`; swiftdc three unresolved calls in a loop on raw x8 |
| Box.init | g Onone | DECLINED | WRONG | DECLINED | PARTIAL | Ghidra returns `local_d0` (a stack address) as the Box though the result is indirect; swiftdc unresolved calls, raw-register loops; swiftdc interface: body reads raw x1 (pack count) for a parameter |
| makeShape | g Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra `*in_x8 = Sq.init(n).s`; swiftdc `mem64[&result] = x0` after `Sq.init(s:)(arg0)` |
| makeColl | g Onone | CORRECT | PARTIAL | CORRECT | WRONG | Ghidra full (elements, overflow trap, finalize) with in_x8; swiftdc `[…]` and silently drops the `n + 1` overflow trap |
| sumAny | g Onone | DECLINED | WRONG | CORRECT | WRONG | both drop the receiver (x20) of makeIterator() and next(); swiftdc also drops the accumulation, its overflow trap and the returned sum |
| anySeq | g Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra stores the [String] metadata into the witness-table slot (`in_x8[4] = lVar3`; binary stores the accessor's result); swiftdc `[…]`, stores via raw x0/x9 |
| firstEq | g Onone | CORRECT | WRONG | CORRECT | WRONG | both render makeIterator() and next() with no receiver; swiftdc `return ?` |
| Pair.init(a:b:) | g Onone | CORRECT | WRONG | CORRECT | WRONG | Ghidra's first initializeWithCopy has no arguments; swiftdc omits the outlined copy of the temp into the result (0x24d8) |
| Pair.area (T == Int) | g Onone | DECLINED | PARTIAL | CORRECT | PARTIAL | Ghidra `(void)`, in_x0*in_x1 with trap; swiftdc `if (x8 != 0) trap()`, `return ?` |
| IntC.first getter | g Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| IntC.init | g Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | empty struct: Ghidra `return in_x0`, swiftdc `return ?` |
| hashFirst | g Onone | CORRECT | WRONG | CORRECT | WRONG | both drop self of `hashValue` (x20 = the Item buffer); Ghidra also calls the `first` witness with no arguments |
| Store.init | g Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra passes raw in_x0 as the literal array; swiftdc `Dictionary.init(dictionaryLiteral:)([…])`, `return ?` |
| Store.subscript getter | g Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra names x2 `Store as` and reads self as in_x3; its nil-path storeEnumTag shows `(in_x8, 1)` with one argument dropped; swiftdc `Dictionary.subscript.getter(?)`, cast and tag stores right |
| countDict | g Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| ident | g Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra `(vwt+0x10)(param_1)` drops the source x; swiftdc `initializeWithCopy(&result, arg0)` right, `return ?` |
| sizeOf | g Onone | DECLINED | PARTIAL | CORRECT | DECLINED | Ghidra `(void)`, in_x1 vwt size; swiftdc `return ?` |
| dynType | g Onone | WRONG | WRONG | CORRECT | CORRECT | Ghidra `void` and drops the returned swift_getDynamicType result |
| isInt | g Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra's copy into the temp has no arguments; swiftdc `(? as? Int) != nil` |
| asShape | g Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra's copy into the temp has no arguments; swiftdc copy(?, arg0), cast and nil zeroing right |
| describe | g Onone | DECLINED | WRONG | CORRECT | PARTIAL | Ghidra drops self of both witness calls and passes garbage in_x4/in_x5 to `String.+`; swiftdc witness calls unresolved, `+ (?, String(local_30))` |
| compo | g Onone | DECLINED | WRONG | CORRECT | PARTIAL | Ghidra `(in_x3+8)()` drops self x; swiftdc unresolved call, `return ?` |
| Base.init | g Onone | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` for `return self` |
| clsComp | g Onone | DECLINED | WRONG | CORRECT | PARTIAL | Ghidra `(in_x1+8)(*in_x0)` drops self (&x); swiftdc unresolved call, `return ?` |
| Sq.init(s:) | g Osize | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc: aliased with IntC.init/Sq.s.getter at 0x978, rendered as unnamed `sub_978`, no body |
| Sq.area | g Osize | CORRECT | CORRECT | CORRECT | CORRECT | |
| packCount | g Osize | DECLINED | PARTIAL | DECLINED | PARTIAL | Ghidra `(void)`, reads `in_x1`; swiftdc `return ?` for the count in x1; swiftdc interface: body reads raw x1 (pack count) for a parameter |
| packWrap | g Osize | DECLINED | PARTIAL | DECLINED | PARTIAL | Ghidra loop on in_x0/in_x1/in_x8, right; swiftdc copy is an unresolved call, loop on raw x19; swiftdc interface: body reads raw x1 (pack count) for a parameter |
| Box.init | g Osize | DECLINED | PARTIAL | DECLINED | PARTIAL | both opaque OUTLINED calls; swiftdc metadata-copy loop shows no load/increment, raw regs; swiftdc interface: body reads raw x20 (copy of the pack count) for a parameter |
| makeShape | g Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra `*in_x8 = param_1`; swiftdc `mem64[&result] = arg0; return ?` |
| makeColl | g Osize | CORRECT | PARTIAL | CORRECT | WRONG | swiftdc silently drops the `n + 1` overflow trap (`b.vs` -> brk); Ghidra keeps it, header via _DAT globals |
| sumAny | g Osize | DECLINED | WRONG | CORRECT | WRONG | both drop the iterator receiver (x20) of makeIterator/next; swiftdc also drops the `t += x` accumulation and its overflow trap |
| anySeq | g Osize | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra `get_description()` drops self (&n); swiftdc `description.getter(self: local_38)`, stores via raw x0/x22 |
| firstEq | g Osize | CORRECT | WRONG | CORRECT | WRONG | both drop the receiver of the first makeIterator()/next(); swiftdc also `return ?` for true/false/== result |
| Pair.init(a:b:) | g Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc only an unresolved call and an unresolved indirect branch |
| Pair.area (T == Int) | g Osize | DECLINED | PARTIAL | CORRECT | PARTIAL | Ghidra `(void)` with in_x0*in_x1; swiftdc trap test on raw x8/x0, `return ?` |
| IntC.first getter | g Osize | CORRECT | WRONG | CORRECT | CORRECT | Ghidra renders the small string "x" as `section_00000068.segname` |
| IntC.init | g Osize | DECLINED | DECLINED | DECLINED | DECLINED | aliased at 0x978: not emitted by Ghidra (named Sq.init), swiftdc `sub_978` |
| hashFirst | g Osize | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra drops self (x20 = c) of the `first` witness call and of hashValue; swiftdc unresolved call, `hashValue(self: ?)` |
| Store.init | g Osize | CORRECT | PARTIAL | CORRECT | WRONG | tail call to `Store.d` initializer: swiftdc shows the call with no return; Ghidra passes raw in_x0 (the empty array) |
| Store.subscript getter | g Osize | WRONG | WRONG | CORRECT | WRONG | Ghidra names x2 `Store as` and reads self (x3) as in_x3, `_find()`/storeEnumTag with no args; swiftdc drops the bucket copy into local_50 and the nil zeroing |
| countDict | g Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` for `ldr x0,[x0,#0x10]` |
| ident | g Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | both: Int fast path right, generic path an opaque OUTLINED copy; swiftdc stores raw x9 |
| sizeOf | g Osize | DECLINED | PARTIAL | CORRECT | DECLINED | Ghidra `(void)`, reads in_x1 vwt size; swiftdc `return ?` |
| dynType | g Osize | WRONG | WRONG | CORRECT | CORRECT | tail call to swift_getDynamicType: Ghidra `void`; swiftdc now returns the call (was no `return`) |
| isInt | g Osize | WRONG | PARTIAL | CORRECT | PARTIAL | Ghidra `(void)` though x0/x1 are read; Ghidra returns opaque OUTLINED_29, swiftdc `(? as? Int) != nil` |
| asShape | g Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | both cast plus nil-zeroing right; Ghidra copy source raw extraout_x1, swiftdc `? as? Shape` |
| describe | g Osize | DECLINED | WRONG | CORRECT | PARTIAL | Ghidra drops self of the name/area/description calls and calls append with garbage in_x2/in_x3; swiftdc witness calls unresolved, append(self: local_50, r0) right, `return ?` |
| compo | g Osize | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra `(wt+8)(param_2, param_4)` drops self x20 = x; swiftdc unresolved call, `return ?` |
| Base.init | g Osize | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc: aliased with Base.deinit at 0x1b68, `sub_1b68` with no body |
| clsComp | g Osize | DECLINED | WRONG | CORRECT | PARTIAL | Ghidra `(in_x1+8)(*in_x0)` drops self (x20 = &x); swiftdc unresolved call, `return ?` |
| Sq.init(s:) | g evo | CORRECT | PARTIAL | CORRECT | CORRECT | Ghidra: `*in_x8 = s` (raw x8); swiftdc `return G.Sq(s: arg0)` |
| Sq.area | g evo | WRONG | PARTIAL | CORRECT | CORRECT | Ghidra shows `Sq param_1` but self is the indirect x20 (`*unaff_x20`) |
| packCount | g evo | DECLINED | PARTIAL | DECLINED | PARTIAL | Ghidra `return in_x1` (raw); swiftdc right trap structure but `return ?`; swiftdc interface: body reads raw x1 (pack count) for a parameter |
| packWrap | g evo | DECLINED | PARTIAL | DECLINED | PARTIAL | Ghidra loop right on raw in_x0/in_x1/in_x8; swiftdc loop with unresolved calls; swiftdc interface: body reads raw x1 (pack count) for a parameter |
| Box.init | g evo | DECLINED | WRONG | DECLINED | PARTIAL | Ghidra: empty-pack initializeWithCopy shown with no args, returns destroy()'s result as the Box; swiftdc raw-register copy loops, `return ?`; swiftdc interface: body reads raw x20 (copy of the pack count) for a parameter |
| makeShape | g evo | CORRECT | PARTIAL | CORRECT | WRONG | tail call to Sq.init(s:): Ghidra inlines `*in_x8 = param_1`; swiftdc `G.Sq.init(s:)(arg0)` with no return |
| makeColl | g evo | CORRECT | PARTIAL | CORRECT | WRONG | Ghidra header words as `_DAT_`/`_UNK_`; swiftdc drops the `n + 1` overflow trap (`adds; b.vs brk`) |
| sumAny | g evo | DECLINED | WRONG | CORRECT | WRONG | both drop makeIterator's self (x20); swiftdc also drops the sum (`return ?`, no `t += x`, no trap) |
| anySeq | g evo | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra `get_description()` has no self (x20=&n); swiftdc `description.getter(self: local_38)`, raw x0/x22 |
| firstEq | g evo | CORRECT | WRONG | CORRECT | WRONG | both drop the first makeIterator's self (x20); swiftdc also `return ?` over the 3-way result |
| Pair.init | g evo | CORRECT | CORRECT | CORRECT | DECLINED | Ghidra: initializeWithTake(result,a) then (result+offset(b), b) via T's VWT (x8 shown as param_1); swiftdc one unresolved call + unresolved jump |
| Pair.area | g evo | DECLINED | PARTIAL | DECLINED | WRONG | alias of the witness at 0x1a24; Ghidra a*b on unaff_x20; swiftdc `sub_1a24`: trap then bare `return` (product dropped) |
| IntC.first getter | g evo | CORRECT | WRONG | CORRECT | CORRECT | Ghidra renders the small string "x" as `str = section_00000068.segname`; swiftdc `return "x"` |
| IntC.init | g evo | CORRECT | CORRECT | DECLINED | DECLINED | zero-sized; swiftdc renders the alias at 0x998 as `sub_998` |
| hashFirst | g evo | CORRECT | WRONG | CORRECT | WRONG | both drop `first` getter's self (x20=c); Ghidra also `get_hashValue()` with no self |
| Store.init | g evo | CORRECT | WRONG | CORRECT | CORRECT | Ghidra `Dictionary::_init()` drops the empty-literal argument; `*in_x8` raw |
| Store.subscript getter | g evo | WRONG | WRONG | CORRECT | WRONG | Ghidra types `as` as `Store`, self via unaff_x20, dynamicCast()/storeEnumTag() with no args; swiftdc drops the copy of the found Any (and the nil fill) before the cast |
| countDict | g evo | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` on `ldr x0,[x0,#0x10]` |
| ident | g evo | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra's generic tail call `initializeWithCopy(param_1)` drops src; swiftdc `mem64[&result] = x9` raw |
| sizeOf | g evo | DECLINED | PARTIAL | CORRECT | DECLINED | Ghidra raw in_x1; swiftdc `return ?` |
| dynType | g evo | WRONG | WRONG | CORRECT | CORRECT | tail call to swift_getDynamicType: Ghidra `void`; swiftdc now returns the call (was no `return`) |
| isInt | g evo | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra copy src `extraout_x1`; swiftdc `(? as? Int) != nil` |
| asShape | g evo | CORRECT | PARTIAL | CORRECT | PARTIAL | both right shape; Ghidra copy src raw, swiftdc `?` operands and `return ?` |
| describe | g evo | DECLINED | WRONG | CORRECT | PARTIAL | Ghidra: witness calls lose self, append(SVar4, in_x2:in_x3) and returns the pre-append name; swiftdc unresolved witness calls, `append(self: local_50, r0)`, `return ?` |
| compo | g evo | CORRECT | WRONG | CORRECT | WRONG | both drop area's self (x20=x): Ghidra `(*(param_4+8))(param_2,param_4)`, swiftdc `area() witness for A()` |
| Base.init | g evo | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `sub_1ed8` (init/deinit alias) |
| clsComp | g evo | DECLINED | WRONG | CORRECT | DECLINED | Ghidra `(*(in_x1+8))(*in_x0)` drops self (x20=&x); swiftdc unresolved call, `return ?` |
| Base.init | g2 O | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `sub_9d8` (init/deinit alias) |
| m1 | g2 O | DECLINED | DECLINED | DECLINED | CORRECT | alias of E.__derived_enum_equals at 0x9f0: Ghidra emits only `E::__derived_enum_equals(E,E,E,...) { return true; }`; swiftdc `sub_9f0` now `return // x0 = 1`: right value (`mov w0,#1`), no result claim, name still sub_ (was no body) |
| m2 | g2 O | CORRECT | CORRECT | CORRECT | CORRECT | |
| pa | g2 O | DECLINED | WRONG | CORRECT | DECLINED | Ghidra `(*(wt+0x10))(&local_38,meta,wt)` drops next()'s self (x20=projected box); swiftdc unresolved call, `return ?` |
| pa2 | g2 O | DECLINED | DECLINED | DECLINED | CORRECT | alias of zipCount at 0xa74: not emitted under its name (Ghidra); swiftdc `sub_a74` now `return // x0 = 0`: right value, no result claim (was no body) |
| allEq | g2 O | DECLINED | PARTIAL | DECLINED | PARTIAL | Ghidra's loop is fully right but on in_x0..in_x4; swiftdc unresolved copies, `==(?, ?)`, raw x2; swiftdc interface: body reads raw x2 (pack count) for a parameter |
| zipCount | g2 O | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc `sub_a74` (alias with pa2) now `return // x0 = 0`: right value (`mov x0,#0`), no result claim (was no body) |
| sup | g2 O | WRONG | WRONG | CORRECT | WRONG | Ghidra `void`, calls `S2::init()` (alias of the specialization at 0xc28), then `_swift_retain()` with no arg; swiftdc `sub_c28()` with no arg and no return of x |
| obj | g2 O | WRONG | WRONG | CORRECT | WRONG | same shape as sup (tail call to swift_unknownObjectRetain) |
| Wrap.init | g2 O | CORRECT | CORRECT | CORRECT | DECLINED | Ghidra initializeWithTake(result, v) via T's VWT; swiftdc only `indirect_jump(?)` |
| Wrap.double | g2 O | DECLINED | PARTIAL | DECLINED | PARTIAL | both give the overflow test on raw x0; Ghidra returns `in_x0 << 1`, swiftdc `return ?`; swiftdc interface: body reads raw x0 (self.v) for a parameter |
| Wrap.call | g2 O | DECLINED | DECLINED | DECLINED | DECLINED | alias of Wrap.f at 0xc5c: Ghidra names it only as f; swiftdc `sub_c5c` |
| Wrap.f | g2 O | DECLINED | WRONG | DECLINED | DECLINED | Ghidra `(*(in_x1+8))(*(in_x0+0x10))` drops v.f()'s self (x20); swiftdc `sub_c5c { indirect_jump(?) }` |
| GB.init | g2 O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc unresolved call, `return ?` |
| GD.init | g2 O | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `mem64[x20 + 0x10] = arg0; return ?`; swiftdc interface: body reads raw x20 (self) for a parameter |
| opq | g2 O | DECLINED | DECLINED | DECLINED | DECLINED | alias at 0xc28 (S2.init/W.init/opq/specialized sup,obj): Ghidra emits only S2::init; swiftdc `sub_c28` |
| W.init | g2 O | DECLINED | DECLINED | DECLINED | DECLINED | same alias at 0xc28 |
| W.f | g2 O | CORRECT | CORRECT | CORRECT | CORRECT | |
| cm | g2 O | CORRECT | CORRECT | CORRECT | CORRECT | |
| tthrow | g2 O | CORRECT | WRONG | CORRECT | PARTIAL | the throw itself (`mov w21,#1`) is missing from Ghidra, which just returns; swiftdc gives the willThrow hook, then `throw ?` |
| S2.init | g2 O | CORRECT | PARTIAL | DECLINED | DECLINED | Ghidra `return in_x0` for an empty struct; swiftdc `sub_c28` |
| S2 static subscript | g2 O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` on `mov w0,#4` |
| S2.subscript(i:j:) | g2 O | CORRECT | CORRECT | CORRECT | DECLINED | Ghidra keeps the overflow trap; swiftdc `return ?` |
| PB.init | g2 O | DECLINED | PARTIAL | DECLINED | PARTIAL | Ghidra shows `this` but reads the value pack as in_x0; swiftdc raw loops, `return ?`; swiftdc interface: body reads raw x21 (copy of the pack count) for a parameter |
| anyPack | g2 O | DECLINED | PARTIAL | DECLINED | WRONG | Ghidra's append loop is right on raw in_x0..x2; swiftdc drops the element store (`outlined init with take of Any` into the buffer), `return ?`; swiftdc interface: body reads raw x1 (pack count) for a parameter |
| Base.init | g2 evo | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `sub_a28` (init/deinit alias) |
| m1 | g2 evo | DECLINED | DECLINED | DECLINED | CORRECT | alias of E.== at 0xa40: Ghidra emits only `E::==_infix(E,E,E,...) { return true; }`; swiftdc `sub_a40` now `return // x0 = 1`: right value, no result claim (was no body) |
| m2 | g2 evo | CORRECT | CORRECT | CORRECT | CORRECT | |
| pa | g2 evo | DECLINED | WRONG | CORRECT | DECLINED | Ghidra `(*(wt+0x10))(&local_38,meta,wt)` drops next()'s self (x20=projected box); swiftdc unresolved call, `return ?` |
| pa2 | g2 evo | DECLINED | DECLINED | DECLINED | CORRECT | alias of zipCount at 0xac4: not emitted under its name (Ghidra); swiftdc `sub_ac4` now `return // x0 = 0`: right value, no result claim (was no body) |
| allEq | g2 evo | DECLINED | PARTIAL | DECLINED | PARTIAL | Ghidra's loop is fully right but on in_x0..in_x4; swiftdc unresolved copies, `==(?, ?)`, raw x2; swiftdc interface: body reads raw x2 (pack count) for a parameter |
| zipCount | g2 evo | CORRECT | CORRECT | DECLINED | CORRECT | swiftdc `sub_ac4` (alias with pa2) now `return // x0 = 0`: right value, no result claim (was no body) |
| sup | g2 evo | WRONG | WRONG | CORRECT | WRONG | Ghidra `void`, calls `S2::init()` (alias of the specialization at 0xc78), then `_swift_retain()` with no arg; swiftdc `sub_c78()` with no arg and no return of x |
| obj | g2 evo | WRONG | WRONG | CORRECT | WRONG | same shape as sup (tail call to swift_unknownObjectRetain) |
| Wrap.init | g2 evo | CORRECT | CORRECT | CORRECT | DECLINED | Ghidra initializeWithTake(result, v) via T's VWT; swiftdc only `indirect_jump(?)` |
| Wrap.double | g2 evo | DECLINED | PARTIAL | CORRECT | PARTIAL | self is indirect here (x20): Ghidra `*unaff_x20 << 1`, swiftdc overflow test on raw x8, `return ?` |
| Wrap.call | g2 evo | DECLINED | DECLINED | DECLINED | DECLINED | alias of Wrap.f at 0xcb0: Ghidra names it only as f; swiftdc `sub_cb0` |
| Wrap.f | g2 evo | DECLINED | WRONG | DECLINED | DECLINED | Ghidra `(*(in_x1+8))(*(in_x0+0x10))` drops v.f()'s self (x20); swiftdc `sub_cb0 { indirect_jump(?) }` |
| GB.init | g2 evo | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc unresolved call, `return ?` |
| GD.init | g2 evo | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `mem64[x20 + 0x10] = arg0; return ?`; swiftdc interface: body reads raw x20 (self) for a parameter |
| opq | g2 evo | DECLINED | DECLINED | DECLINED | DECLINED | alias at 0xc78 (S2.init/W.init/opq/specialized sup,obj): Ghidra emits only S2::init; swiftdc `sub_c78` |
| W.init | g2 evo | DECLINED | DECLINED | DECLINED | DECLINED | same alias at 0xc78 |
| W.f | g2 evo | CORRECT | CORRECT | CORRECT | CORRECT | |
| cm | g2 evo | CORRECT | CORRECT | CORRECT | CORRECT | |
| tthrow | g2 evo | CORRECT | WRONG | CORRECT | PARTIAL | resilient E: the error buffer comes in x2. Ghidra passes the version-check bool as willThrowTypedImpl's witness table and drops the throw (`w21=1`); swiftdc `willThrowTypedImpl(?, 0x4278)`, `throw ?` |
| S2.init | g2 evo | CORRECT | PARTIAL | DECLINED | DECLINED | Ghidra `return in_x0` for an empty struct; swiftdc `sub_c78` |
| S2 static subscript | g2 evo | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc `return ?` on `mov w0,#4` |
| S2.subscript(i:j:) | g2 evo | CORRECT | CORRECT | CORRECT | DECLINED | Ghidra keeps the overflow trap; swiftdc `return ?` |
| PB.init | g2 evo | DECLINED | PARTIAL | DECLINED | PARTIAL | Ghidra shows `this` but reads the value pack as in_x0; swiftdc raw loops, `return ?`; swiftdc interface: body reads raw x21 (copy of the pack count) for a parameter |
| anyPack | g2 evo | DECLINED | PARTIAL | DECLINED | WRONG | Ghidra's append loop is right on raw in_x0..x2; swiftdc drops the element store (`outlined init with take of Any` into the buffer), `return ?`; swiftdc interface: body reads raw x1 (pack count) for a parameter |
| Base.init | f evo | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc renders the init/deinit alias at 0x8e8 as `sub_8e8` with no body |

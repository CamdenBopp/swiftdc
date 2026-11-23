# Wrappers: Ghidra 12.2 vs swiftdc

Inputs: `abi2/wrappers/{nest,obs,order,pw}` at every built level (nest -O; order -O, -Osize; obs and pw at -Onone, -O, -Osize). The scoring follows `ghidra/scores/RUBRIC.md`. Scored: user functions, explicit inits, user computed properties and coroutine accessors (`Clamped.wrappedValue`, `projectedValue`, `Store.first` read/modify), user closures and local functions that survive as their own symbol (the lazy `cached` closure and `f #1 in built` at -Onone), and `willSet`/`didSet` where they exist. `Observed.count.setter` and `Observed.cached.getter` are counted because they are where the user's observer and lazy-initializer code lives once the compiler inlines it. The `@Observable` macro's `score` getter and setter are listed separately, outside the totals, because RUBRIC.md skips stored-property accessors. Skipped: plain stored accessors, the property-wrapper backing initializer, value witnesses and `OUTLINED_FUNCTION_n`.

## How the rules were applied

- **Interface** is what the tool presents: Ghidra's decompiled parameter list; swiftdc's demangled header plus the `argN`/`self` values its body uses. Raw registers (`in_x1`, `unaff_x20`, swiftdc `x20`/`x19`) or `?` standing for a parameter count as DECLINED. A parameter shown that the code does not take is WRONG. Examples: Ghidra's `get_score(void *this, Model *param_1)`, where param_1 is never read; its by-value `Store`/`S` for an inout pointer; `SumBuilder param_2` on a static method.
- **Body:** a call shown with fewer arguments than the callee reads (the key path missing from `_access(this)`, the array missing from `reduce`, the subscript's self) or with a wrong argument (the key path passed again where the witness table goes) is WRONG. A coroutine accessor with no yield is WRONG. So is a call statement with no `return` where the binary returns its result. A value left in a raw register is PARTIAL. So is a result routed through an opaque `_OUTLINED_FUNCTION_n` epilogue.
- **Folded (ICF) addresses** (13 symbols share one bare `ret` at -O and -Osize) are scored against what the tool prints at that address. If the tool labels it with another function's name, or as `sub_<addr>`, the interface is DECLINED. The body is CORRECT only if the printed body is right for this function too.


## Totals

110 function builds scored.

| tool | axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|---|
| Ghidra | interface | 71 | 0 | 22 | 17 |
| Ghidra | body | 70 | 9 | 27 | 4 |
| swiftdc | interface | 49 | 0 | 0 | 61 |
| swiftdc | body | 26 | 45 | 14 | 25 |

Body results by build:

| build | rows | Ghidra body C | Ghidra body W | swiftdc body C | swiftdc body W |
|---|---|---|---|---|---|
| nest -O | 2 | 2 | 0 | 0 | 0 |
| order -O | 4 | 4 | 0 | 0 | 0 |
| order -Osize | 4 | 4 | 0 | 0 | 0 |
| obs -O | 3 | 1 | 2 | 0 | 0 |
| obs -Osize | 3 | 2 | 0 | 2 | 0 |
| obs -Onone | 3 | 2 | 1 | 2 | 0 |
| pw -O | 29 | 20 | 7 | 7 | 5 |
| pw -Osize | 29 | 16 | 6 | 8 | 4 |
| pw -Onone | 33 | 19 | 11 | 7 | 5 |

## Where swiftdc beats Ghidra

1. **Observation registrar calls.** `getScore` (-O): Ghidra `uVar2 = uVar1; Model::_lazy_protocol_witness_table_accessor(); Observation::ObservationRegistrar::_access(local_48,uVar1,uVar2);` passes the key path twice. swiftdc `access(self: (arg0 + ?), local_48, r0)  return arg0._score`. Truth: `bl <lazy protocol witness table accessor>; mov x2, x0; …; mov x1, x21; bl access`. x2 is the witness table. The same slip is in every -O `withMutation` call, and at -Onone the macro getter's `_access(this)` drops the key path entirely.
2. **Inout struct pointer read as a byte.** `addFirst` (-O, -Osize): Ghidra `_Var4.unknown = *(undefined **)(ulong)(byte)param_1.items;`, which dereferences the low byte of the pointer. swiftdc `if (!isKnownUniquelyReferenced(?)) { …_consumeAndCreateNew() } … mem64[arg0] = x20`. Truth: `mov x19, x0; ldr x20, [x0]`. The same truncation makes Ghidra's `readFirst` WRONG at all three levels.
3. **Key-path dynamic member.** `Wrap.subscript(dynamicMember:)` (-O): Ghidra `void _get_subscript(Wrap dynamicMember) { _swift_getAtKeyPath(); }` has no arguments, and the key path is typed `Wrap`. swiftdc `swift_getAtKeyPath(self, arg0)`. Truth: `mov x1, x0; mov x0, x20; b swift_getAtKeyPath`. Also `Store.init` (-O): Ghidra `return (Store)0x38;`, which drops the adrp page. The real value is 0x4038.

## Where Ghidra beats swiftdc

1. **Observers folded into one stp.** `bump` (-O): swiftdc `arg0.count = arg1; arg0.log = ((arg1 + (arg0.count << 1)) + arg0.log)`. Read in order, that uses the new count. Ghidra `lVar1 = *(long *)(param_1 + 0x10); … *(param_1 + 0x18) = param_2 + lVar1 * 2 + *(param_1 + 0x18);` keeps the old one. Truth: `ldr x21, [x20, #0x10]` (old count) … `add x9, x19, x21, lsl #1; add x8, x9, x8; stp x19, x8, [x20, #0x10]`. This is the only swiftdc WRONG here that is a wrong value rather than a dropped piece.
2. **Coroutine yield dropped.** `Store.first.read` (-O, -Osize): swiftdc `if (x8 == 0) { trap() } else { return }`, with no yield. Ghidra `if (*(long *)(param_2 + 0x10) == 0) SoftwareBreakpoint(…); auVar2._8_8_ = *(param_2 + 0x20); auVar2._0_8_ = 0x928; return auVar2;`. Truth: `ldr x8, [x1, #0x10]; cbz x8, brk; ldr x1, [x1, #0x20]; adr x0, resume; ret` yields items[0].
3. **Leaf clamp and difference.** `Clamped.init` (-O, -Osize): Ghidra recovers `value = min(max(wrappedValue, lo), hi)` exactly, and `readProjected` recovers `in_x2 - in_x1` with the overflow trap. swiftdc prints `return ?` for both. Truth: `cmp x1, x0; csel x8, x1, x0, gt; cmp x2, x8; csel x0, x2, x8, lt`.


## Per-function scores

| function | build | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| flat(_:) | nest -O | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` for `sub x0, x1, x0` |
| nested(_:) | nest -O | DECLINED | CORRECT | DECLINED | DECLINED | Ghidra `in_x1 - in_x2`; swiftdc `return ?` |
| C.init() | order -O | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc stores through raw x20, `return ?` |
| rot(_:) | order -O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `arg0.c = x20`: old a + 1 left as a raw register |
| shift(_:_:) | order -O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `arg0.b = x21`: old a left as a raw register |
| swapPQ(_:) | order -O | WRONG | CORRECT | CORRECT | PARTIAL | Ghidra takes inout S by value and dereferences `param_1.p` as the pointer; swiftdc `mem128[arg0] = q0` |
| C.init() | order -Osize | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc stores through raw x20, `return ?` |
| rot(_:) | order -Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `arg0.c = x20`: old a + 1 left as a raw register |
| shift(_:_:) | order -Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `arg0.b = x21`: old a left as a raw register |
| swapPQ(_:) | order -Osize | WRONG | CORRECT | CORRECT | PARTIAL | Ghidra takes inout S by value and dereferences `param_1.p` as the pointer; swiftdc `mem128[arg0] = q0` |
| Model.init() | obs -O | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc stores through raw x20, `return ?` |
| getScore(_:) | obs -O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra key path in the witness-table slot; swiftdc registrar offset `?` |
| setScore(_:_:) | obs -O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra key path in the witness-table slot; swiftdc closure argument `?` |
| Model.init() | obs -Osize | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc stores through raw x20, `return ?` |
| getScore(_:) | obs -Osize | CORRECT | PARTIAL | CORRECT | CORRECT | Ghidra discards the getter's result and returns an outlined epilogue |
| setScore(_:_:) | obs -Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Model.init() | obs -Onone | WRONG | WRONG | DECLINED | PARTIAL | Ghidra `score.init(this + 0x10, 0, *this)`: third argument the initializer does not take; swiftdc `name.init(…, ?)`, `return ?` |
| getScore(_:) | obs -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| setScore(_:_:) | obs -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Clamped.init(wrappedValue:lo:hi:) | pw -O | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` for the clamp |
| Clamped.wrappedValue.getter | pw -O | DECLINED | CORRECT | DECLINED | DECLINED | folded bare ret (13 symbols); Ghidra labels it readLevel; swiftdc sub_928 empty |
| Clamped.wrappedValue.setter | pw -O | CORRECT | CORRECT | DECLINED | PARTIAL | tail call to folded Box.level.setter; Ghidra inlines the clamp; swiftdc `Box.level.setter(?)` |
| Clamped.projectedValue.getter | pw -O | DECLINED | CORRECT | DECLINED | PARTIAL | folded with Box.$level.getter; Ghidra `in_x2 - in_x1` with overflow trap; swiftdc sub_188c `readProjected(?)` |
| Box.init() | pw -O | WRONG | WRONG | DECLINED | DECLINED | Ghidra returns one word `&MACH_HEADER.cputype + 1` for the three-word Clamped(5, 0, 10); swiftdc `return ?` |
| readLevel(_:) | pw -O | CORRECT | CORRECT | DECLINED | DECLINED | folded bare ret; swiftdc sub_928 empty |
| writeLevel(_:_:) | pw -O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `mem64[arg0] = x8` |
| readProjected(_:) | pw -O | DECLINED | CORRECT | DECLINED | DECLINED | Ghidra in_x1/in_x2; swiftdc `return ?` |
| Observed.count.setter | pw -O | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `(self.count, self.log) = (…, …)` |
| Observed.cached.getter | pw -O | WRONG | CORRECT | CORRECT | PARTIAL | Ghidra unused `Observed *param_1`; swiftdc lazy fill right, `return ?` |
| Observed.init() | pw -O | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc stores through raw x20, `return ?` |
| bump(_:_:) | pw -O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc `arg0.count = arg1; arg0.log = ((arg1 + (arg0.count << 1)) + arg0.log)`: reads as the new count; the binary uses the old one (one stp) |
| getLazy(_:) | pw -O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Store.init() | pw -O | CORRECT | WRONG | DECLINED | DECLINED | Ghidra `return (Store)0x38` drops the adrp page (0x4038); swiftdc `return ?` |
| Store.first.read | pw -O | CORRECT | CORRECT | DECLINED | WRONG | swiftdc `if (x8 == 0) trap() else return`: the yield of items[0] is missing |
| Store.first.modify | pw -O | CORRECT | WRONG | DECLINED | WRONG | Ghidra drops the index and stores the frame instead of the subscript result; swiftdc no yield, args `…` |
| addFirst(_:) | pw -O | WRONG | WRONG | CORRECT | PARTIAL | Ghidra truncates the inout pointer to a byte `(byte)param_1.items`; swiftdc stores raw x8 (the +7 not shown) |
| readFirst(_:) | pw -O | CORRECT | WRONG | DECLINED | WRONG | Ghidra `(byte)param_1.items` byte truncation; swiftdc `first.getter(self: ?)` with no return |
| Wrap.init(_:) | pw -O | WRONG | WRONG | DECLINED | DECLINED | Ghidra metadata from param_3 (x2), truth x1, and witness called with (src, meta) |
| Wrap.subscript(dynamicMember:) | pw -O | WRONG | WRONG | CORRECT | CORRECT | Ghidra `_swift_getAtKeyPath()` with no arguments, param typed Wrap |
| Pt.init(x:y:) | pw -O | DECLINED | DECLINED | DECLINED | DECLINED | folded bare ret; neither tool presents it |
| dynY(_:) | pw -O | DECLINED | CORRECT | DECLINED | DECLINED | folded `mov x0, x1`; Ghidra in_x1; swiftdc sub_944 empty |
| Summer.init() | pw -O | DECLINED | DECLINED | DECLINED | DECLINED | folded bare ret |
| Summer.dynamicallyCall(withArguments:) | pw -O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| callSum(_:) | pw -O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| SumBuilder.buildBlock(_:) | pw -O | WRONG | CORRECT | CORRECT | WRONG | Ghidra adds an unused `SumBuilder param_2`; swiftdc `merged ….dynamicallyCall(withArguments:)(arg0)` drops the return |
| built(_:_:) | pw -O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| hidden(_:) | pw -O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| inl(_:) | pw -O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Clamped.init(wrappedValue:lo:hi:) | pw -Osize | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` |
| Clamped.wrappedValue.getter | pw -Osize | DECLINED | CORRECT | DECLINED | DECLINED | folded bare ret; Ghidra labels it readLevel; swiftdc sub_928 empty |
| Clamped.wrappedValue.setter | pw -Osize | CORRECT | CORRECT | DECLINED | PARTIAL | Ghidra inlines the clamp; swiftdc `Box.level.setter(?)` |
| Clamped.projectedValue.getter | pw -Osize | DECLINED | CORRECT | DECLINED | PARTIAL | folded with Box.$level.getter; swiftdc sub_167c `readProjected(?)` |
| Box.init() | pw -Osize | WRONG | PARTIAL | DECLINED | DECLINED | Ghidra one-word result from `_OUTLINED_FUNCTION_7(5)`; swiftdc `return ?` |
| readLevel(_:) | pw -Osize | CORRECT | CORRECT | DECLINED | DECLINED | folded bare ret; swiftdc sub_928 empty |
| writeLevel(_:_:) | pw -Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `mem64[arg0] = x8` |
| readProjected(_:) | pw -Osize | DECLINED | CORRECT | DECLINED | DECLINED | Ghidra in_x1/in_x2; swiftdc `return ?` |
| Observed.count.setter | pw -Osize | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `(self.count, self.log) = (…, …)`, `self.log = …` |
| Observed.cached.getter | pw -Osize | WRONG | PARTIAL | CORRECT | PARTIAL | Ghidra unused param_1, result through outlined epilogue; swiftdc `return ?` |
| Observed.init() | pw -Osize | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc raw x20, `return ?` |
| bump(_:_:) | pw -Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| getLazy(_:) | pw -Osize | CORRECT | PARTIAL | CORRECT | CORRECT | Ghidra discards the getter result and returns an outlined epilogue |
| Store.init() | pw -Osize | CORRECT | WRONG | DECLINED | DECLINED | Ghidra `return (Store)0x38` (truth 0x4038); swiftdc `return ?` |
| Store.first.read | pw -Osize | CORRECT | CORRECT | DECLINED | WRONG | swiftdc drops the yield of items[0] |
| Store.first.modify | pw -Osize | CORRECT | WRONG | DECLINED | WRONG | Ghidra drops the index and stores the frame; swiftdc no yield |
| addFirst(_:) | pw -Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `(byte)param_1.items`; swiftdc raw x8 store |
| readFirst(_:) | pw -Osize | CORRECT | WRONG | DECLINED | WRONG | Ghidra byte truncation; swiftdc call with no return |
| Wrap.init(_:) | pw -Osize | WRONG | WRONG | DECLINED | DECLINED | Ghidra metadata from param_3 |
| Wrap.subscript(dynamicMember:) | pw -Osize | WRONG | WRONG | CORRECT | CORRECT | Ghidra `_swift_getAtKeyPath()` with no arguments |
| Pt.init(x:y:) | pw -Osize | DECLINED | DECLINED | DECLINED | DECLINED | folded bare ret |
| dynY(_:) | pw -Osize | DECLINED | CORRECT | DECLINED | PARTIAL | Ghidra in_x1; swiftdc sub_944 `OUTLINED_FUNCTION_13(?, arg1)` |
| Summer.init() | pw -Osize | DECLINED | DECLINED | DECLINED | DECLINED | folded bare ret |
| Summer.dynamicallyCall(withArguments:) | pw -Osize | CORRECT | PARTIAL | CORRECT | CORRECT | Ghidra empty-array path returns an opaque outlined call |
| callSum(_:) | pw -Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| SumBuilder.buildBlock(_:) | pw -Osize | WRONG | PARTIAL | CORRECT | WRONG | Ghidra unused param_2; swiftdc merged call with no return |
| built(_:_:) | pw -Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| hidden(_:) | pw -Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| inl(_:) | pw -Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Clamped.init(wrappedValue:lo:hi:) | pw -Onone | CORRECT | PARTIAL | DECLINED | PARTIAL | Ghidra loses the link from max's result to min's input; swiftdc `max(local_58, local_60)`, `min(local_50, local_68)`, `return ?` |
| Clamped.wrappedValue.getter | pw -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Clamped.wrappedValue.setter | pw -Onone | CORRECT | PARTIAL | DECLINED | PARTIAL | Ghidra max→min link lost; swiftdc `self.value = …` |
| Clamped.projectedValue.getter | pw -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Box.init() | pw -Onone | WRONG | PARTIAL | DECLINED | PARTIAL | Ghidra returns one word of the three-word Clamped; swiftdc `backing initializer(5)`, `return ?` |
| readLevel(_:) | pw -Onone | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `level.getter(self: (?, ?, ?))` |
| writeLevel(_:_:) | pw -Onone | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `level.setter(self: arg0, ?)` |
| readProjected(_:) | pw -Onone | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `$level.getter(self: (?, ?, ?))` |
| Observed.count.willset | pw -Onone | DECLINED | CORRECT | DECLINED | PARTIAL | Ghidra self as unaff_x20; swiftdc `mem64[x20 + 0x18] = x8` |
| Observed.count.didset | pw -Onone | DECLINED | CORRECT | DECLINED | PARTIAL | Ghidra self as unaff_x20; swiftdc `mem64[x20 + 0x18] = x8` |
| Observed.count.setter | pw -Onone | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `willset(?)`, `self.count = …`, `didset(?)` |
| Observed.cached.getter | pw -Onone | WRONG | CORRECT | CORRECT | PARTIAL | Ghidra unused param_1; swiftdc tests raw w8 |
| closure in Observed.cached.getter | pw -Onone | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` |
| Observed.init() | pw -Onone | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc stores through raw x0, `return ?` |
| bump(_:_:) | pw -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| getLazy(_:) | pw -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Store.init() | pw -Onone | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `[…]`, `return ?` |
| Store.first.read | pw -Onone | CORRECT | CORRECT | DECLINED | WRONG | swiftdc `Array.subscript.getter(0)` without the array, and no yield |
| Store.first.modify | pw -Onone | CORRECT | WRONG | DECLINED | WRONG | Ghidra stores the frame where the subscript's continuation goes, no yielded address; swiftdc no yield |
| addFirst(_:) | pw -Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `(byte)param_1.items` and calls the stack buffer as the continuation; swiftdc `mem64[x1] = x9`, unresolved continuation call |
| readFirst(_:) | pw -Onone | WRONG | WRONG | DECLINED | PARTIAL | Ghidra byte truncation, `first.read()` with no arguments; swiftdc `first.read(local_38, ?)`, `return ?` |
| Wrap.init(_:) | pw -Onone | WRONG | WRONG | DECLINED | DECLINED | Ghidra metadata from param_3; swiftdc two unresolved calls |
| Wrap.subscript(dynamicMember:) | pw -Onone | DECLINED | CORRECT | CORRECT | PARTIAL | Ghidra self as unaff_x20; swiftdc `return ?` |
| Pt.init(x:y:) | pw -Onone | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` |
| dynY(_:) | pw -Onone | CORRECT | WRONG | DECLINED | WRONG | both call the subscript without its self (x20, the stack copy); swiftdc also `return ?` |
| Summer.init() | pw -Onone | WRONG | WRONG | DECLINED | DECLINED | Ghidra returns in_x0 for an empty struct |
| Summer.dynamicallyCall(withArguments:) | pw -Onone | CORRECT | WRONG | CORRECT | WRONG | Ghidra reduce passes the type metadata where the witness table goes and omits the array (x20); swiftdc reduce omits the array |
| callSum(_:) | pw -Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra `dynamicallyCall()` drops the [1,2,3] array; swiftdc `dynamicallyCall(self: ?, [1, 2, 3])` |
| SumBuilder.buildBlock(_:) | pw -Onone | WRONG | WRONG | CORRECT | WRONG | Ghidra unused param_2, reduce args wrong; swiftdc reduce omits the array |
| built(_:_:) | pw -Onone | CORRECT | WRONG | CORRECT | CORRECT | Ghidra `f_1()` drops the captured a, b |
| f #1 in built | pw -Onone | DECLINED | WRONG | DECLINED | PARTIAL | Ghidra in_x0/in_x1, passes metadata as a second buildBlock argument; swiftdc `buildBlock([…])` |
| hidden(_:) | pw -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| inl(_:) | pw -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |

## Observable macro accessors (outside the totals)

The `@Observable` macro generates these, so RUBRIC.md skips them as stored-property accessors. They are listed because the fixture comment states their behaviour.

| function | build | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| Model.score.getter | obs -O | WRONG | WRONG | CORRECT | PARTIAL | Ghidra adds an unused `Model *param_1` and passes the key path again where `access` takes the witness table; swiftdc `access(self: (self + ?), local_48, r0)` |
| Model.score.setter | obs -O | CORRECT | WRONG | DECLINED | PARTIAL | Ghidra passes the key path as withMutation's witness-table argument; swiftdc compares against raw x19 |
| Model.score.getter | obs -Osize | WRONG | PARTIAL | CORRECT | PARTIAL | Ghidra unused `Model *param_1`, argument-less outlined calls; swiftdc `OUTLINED_FUNCTION_4(OUTLINED_FUNCTION_5(getKeyPath(…)))` |
| Model.score.setter | obs -Osize | CORRECT | PARTIAL | DECLINED | PARTIAL | both show outlined calls; swiftdc compares against raw x19 |
| Model.score.getter | obs -Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra unused param_1 and `_access(this)` drops the key path; swiftdc `getKeyPath(0x1ff8, ?)` |
| Model.score.setter | obs -Onone | CORRECT | WRONG | DECLINED | PARTIAL | Ghidra `_withMutation(this)` drops key path and closure; swiftdc `self._score = …`, closure `?`, error flag raw x21 |

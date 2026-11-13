# Linker area: Ghidra 12.2 vs swiftdc (`disasm --structured`)

Inputs: abi2/linker (14 dylibs). The variants were identified from `nm -m`, `dyld_info -function_starts` and objdump:

- `shapes_x`: shapes.s with the local `_local_helper` symbol stripped. LC_FUNCTION_STARTS still marks 0x36c.
- `shapes_nofs`: no LC_FUNCTION_STARTS, with all symbols.
- `shapes_nofs_x`: no LC_FUNCTION_STARTS, and `_local_helper` is stripped. Only the `bl` from calls_local marks 0x364.
- `alias`: regcall.s plus a second symbol `_alias_one` at `_one_arg`'s address.
- `icf`: twin_a and twin_b are folded to one body at 0x2d0, with both symbols kept. `merge` was not merged by the compiler (three distinct bodies). `merge2` was merged into one `Tm` body with three thunks.

## Rubric as applied (same for both tools)

- **Interface.** Ghidra is judged on its decompiled prototype. swiftdc is judged on its demangled Swift signature where one exists. For C and assembly code, swiftdc prints no prototype, so its interface is the `argN` it uses plus its `return` lines. If it neither shows a result nor misuses a parameter, the interface is DECLINED.
- **Bare `return` (primary rule).** A bare `return` in a value-returning function claims no result, so it counts as WRONG. Ghidra's `void` prototype on a value-returning function is treated the same way. Secondary counts below re-score swiftdc's bare `return` as a decline.
- **Calls.** A call shown with fewer arguments than it passes (`f()`) or with extra arguments (`one_arg(3,7)`, `in_x2`) is WRONG. `?`, `…`, a raw register, or an unresolved indirect call is PARTIAL.
- **Missing returned value.** A swiftdc body with no `return` line at all, where the function returns a computed value, counts as PARTIAL (unshown, not claimed void). A body that shows nothing ("no non-runtime calls", or only `return ?`) is DECLINED.
- **Scope.** Compiler-generated helpers are not scored: Swift accessors, value witnesses, `Tm` bodies, `Tg5`/`Tf` specializations and OUTLINED_FUNCTION_0. hot.cold.1 is scored because it holds user code. A function in four builds counts four times. The total is 101 function-builds.
- **MISSING** means the function is absent from that tool's output. It is excluded from the C/P/W/D totals and counted separately.

## Scores

| function | build | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| real_add | shapes, shapes_x, shapes_nofs, shapes_nofs_x | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc: leaf rendered as "no non-runtime calls", nothing recovered |
| tail_caller | shapes, shapes_x, shapes_nofs, shapes_nofs_x | WRONG | WRONG | DECLINED | PARTIAL | G: `void` + `_real_add(x<<1,7); return;` drops the tail-call result. S: `real_add((arg0 << 1), 7)`, result not shown |
| outer | shapes, shapes_x, shapes_nofs, shapes_nofs_x | CORRECT | CORRECT | DECLINED | DECLINED | G: x+3 (falls into inner) right. S: declines, notes "continues into" inner |
| inner | shapes, shapes_x, shapes_nofs, shapes_nofs_x | CORRECT | CORRECT | DECLINED | DECLINED | S declines |
| got_caller | shapes, shapes_x, shapes_nofs, shapes_nofs_x | WRONG | WRONG | DECLINED | PARTIAL | G: `void _got_caller(void)`, `(*PTR__puts)()` drops the x0 argument. S: `puts(?)` |
| got_tail | shapes, shapes_x, shapes_nofs, shapes_nofs_x | MISSING | MISSING | DECLINED | PARTIAL | G: function absent from output. S: `puts(?)` |
| leaf_noframe | shapes, shapes_x, shapes_nofs | CORRECT | CORRECT | DECLINED | DECLINED | S declines |
| local_helper | shapes, shapes_x, shapes_nofs | CORRECT | CORRECT | DECLINED | DECLINED | S declines (named sub_36c when the local symbol is stripped) |
| calls_local | shapes, shapes_x, shapes_nofs | WRONG | WRONG | DECLINED | PARTIAL | G: `long _calls_local(void)`, `_local_helper()` drops the argument. S: `local_helper(?)` |
| calls_inner | shapes, shapes_x, shapes_nofs, shapes_nofs_x | WRONG | WRONG | DECLINED | PARTIAL | G: `void _calls_inner(void)`, `_inner()`. S: `inner(?)` |
| cond_tail | shapes, shapes_x, shapes_nofs, shapes_nofs_x | WRONG | WRONG | WRONG | WRONG | G: one param, `_real_add()` with no args (truth real_add(0,x1)). S: raw `x0 == 0`, `real_add(arg0, ?)`, bare `return` on both paths (value 9 and the tail-call result lost) |
| fallthrough_a | shapes, shapes_x, shapes_nofs, shapes_nofs_x | CORRECT | CORRECT | DECLINED | DECLINED | G: x+0x65 right. S declines, notes "continues into" |
| fallthrough_b | shapes, shapes_x, shapes_nofs, shapes_nofs_x | CORRECT | CORRECT | DECLINED | DECLINED | S declines |
| leaf_noframe | shapes_nofs_x | CORRECT | CORRECT | WRONG | WRONG | S: no function starts + stripped local: local_helper merged into leaf_noframe, rendered as bare `return` (a warning line says functions may be merged) |
| local_helper | shapes_nofs_x | CORRECT | CORRECT | MISSING | MISSING | G finds FUN_00000364 from the bl target. S: merged into leaf_noframe |
| calls_local | shapes_nofs_x | WRONG | WRONG | DECLINED | PARTIAL | G: `_calls_local(void)`, `FUN_00000364()`. S: `sub_364(recovered_args: […])` |
| shared_b | shapes2 | CORRECT | CORRECT | DECLINED | DECLINED | S declines |
| shared_a | shapes2 | WRONG | WRONG | DECLINED | DECLINED | G: `void _shared_a`, `FUN_0000036c(x-1); return;` drops the result. S declines |
| call_mid | shapes2 | CORRECT | CORRECT | DECLINED | PARTIAL | S: `sub_36c(recovered_args: [5, …])`, result not shown |
| adr_tail | shapes2 | MISSING | MISSING | DECLINED | WRONG | G: absent. S: `shared_b()` claims zero arguments; truth shared_b(x0) |
| adr_call | shapes2 | WRONG | WRONG | DECLINED | PARTIAL | G: `void _adr_call(void)` drops the returned shared_b(3). S: `shared_b(3)`, result not shown |
| stub_tail | shapes2 | MISSING | MISSING | DECLINED | PARTIAL | G: absent. S: `abs(?)` |
| tail_noreturn_cmp | shapes2 | CORRECT | WRONG | WRONG | WRONG | G: condition right, `_shared_a()` drops x0. S: renders unconditional `shared_a(arg0); return`: the x>10 -> shared_b branch is gone |
| one_arg (=alias_one) | regcall, alias | CORRECT | CORRECT | DECLINED | DECLINED | S declines (alias: named sub_280, declining between two names) |
| reg_call_stale | regcall, alias | WRONG | WRONG | DECLINED | WRONG | both show the stale scratch x1: G `void`, `_one_arg(3,7)`; S `one_arg(3, 7)` |
| direct_call_stale | regcall, alias | WRONG | WRONG | DECLINED | PARTIAL | G: `void`, `_one_arg(3,7)`. S: `one_arg(3)` right, result not shown |
| reg_tail_unknown | regcall, alias | WRONG | WRONG | DECLINED | WRONG | G: `void(void)`, `_one_arg()`. S: `one_arg()`. Both claim zero args; truth one_arg(x0) |
| hot | cold | CORRECT | WRONG | WRONG | WRONG | G: `_hot_cold_1()` drops the x argument. S: `hot.cold.1(arg0)` right but bare `return` on both paths (x+1 and -1 lost) |
| hot.cold.1 | cold | CORRECT | WRONG | DECLINED | PARTIAL | G: first `_report()` has no argument (truth report(x)). S: `report(…)` x3 |
| twin_a=twin_b | icf | CORRECT | CORRECT | DECLINED | DECLINED | one folded body; G names it _twin_b, S names it sub_2d0. Neither misattributes |
| different_c | icf | CORRECT | CORRECT | DECLINED | DECLINED | S declines |
| use_a | icf | WRONG | WRONG | DECLINED | PARTIAL | G: `long _use_a(void)`, `_twin_b()`. S: `sub_2d0(?)` |
| use_b | icf | WRONG | WRONG | DECLINED | PARTIAL | same as use_a |
| use_c | icf | WRONG | WRONG | DECLINED | PARTIAL | G: `_different_c()` drops x. S: `different_c(?)` |
| f1 | outl | WRONG | WRONG | DECLINED | PARTIAL | G: `void _f1(void)`, `_OUTLINED_FUNCTION_0(); _sink();`. S: `sink(OUTLINED_FUNCTION_0(?), ?, ?, ?)` |
| f2 | outl | WRONG | WRONG | DECLINED | PARTIAL | same as f1 |
| f3 | outl | WRONG | WRONG | DECLINED | PARTIAL | G: `long _f3(void)`, `_sink()` with no args, +1 right. S: as f1, +1 not shown |
| f4 | outl | WRONG | WRONG | DECLINED | PARTIAL | as f3 |
| sink | outl | CORRECT | CORRECT | DECLINED | DECLINED | S declines |
| mA | merge | CORRECT | CORRECT | CORRECT | DECLINED | no merging happened. S: `return ?` |
| mB | merge | CORRECT | CORRECT | CORRECT | DECLINED | S: `return ?` |
| mC | merge | CORRECT | CORRECT | CORRECT | DECLINED | S: `return ?` |
| useM | merge | CORRECT | CORRECT | CORRECT | CORRECT |  |
| sumUp | merge2 | CORRECT | CORRECT | CORRECT | DECLINED | S: raw-register skeleton, empty loop bodies, `return ?` |
| k1 | merge2 | CORRECT | WRONG | CORRECT | PARTIAL | Tm thunk. G: `k1(param_1,param_2)` (Tm body demangles to the same name) and drops the constant 100. S: `merged ….k1(arg0, arg1, 100)`, result not shown |
| k2 | merge2 | CORRECT | WRONG | CORRECT | PARTIAL | G: `k1(param_1,param_2)` reads as k2 == k1, constant 200 lost. S: `merged ….k1(arg0, arg1, 200)` |
| k3 | merge2 | CORRECT | WRONG | CORRECT | PARTIAL | as k2, constant 300 |
| deadFirst | fso | CORRECT | WRONG | CORRECT | CORRECT | G: `_deadFirst(param_2,param_3,param_3)` passes a third argument the FSO body does not take. S: `return …deadFirst(arg1, arg2)` |
| callDead | fso | CORRECT | WRONG | CORRECT | CORRECT | G: `_deadFirst(param_1,param_2,in_x2)` adds a garbage third argument |
| exploded | fso | CORRECT | CORRECT | CORRECT | DECLINED | G recovers p.c + k*p.b. S: `return ?` |
| callExploded | fso | CORRECT | WRONG | CORRECT | PARTIAL | G: `return PVar2.a + PVar2.a` (doubles the second call; truth first + second). S: `exploded(?, 9)` + `exploded(?, 11)` |
| constProp | fso | CORRECT | CORRECT | CORRECT | CORRECT |  |
| callConst | fso | CORRECT | CORRECT | CORRECT | CORRECT |  |
| sumAll (generic) | spec | WRONG | WRONG | CORRECT | PARTIAL | G: `void _sumAll(4 params)`, endIndex called on the witness, not the array. S: right structure with `?`, raw x26, `return ?` |
| useInt | spec | CORRECT | CORRECT | CORRECT | CORRECT |  |
| useDouble | spec | CORRECT | CORRECT | CORRECT | CORRECT |  |
| applyTwice (generic) | spec | WRONG | WRONG | CORRECT | PARTIAL | G: one param, `(*param_1)(); return (*param_1)();` with no arguments. S: two `indirect_call(?, …)`, return chained ? |
| tripleTwice | spec | CORRECT | CORRECT | CORRECT | CORRECT |  |
| addTwice | spec | CORRECT | CORRECT | CORRECT | CORRECT |  |
| mergeA | spec | CORRECT | CORRECT | CORRECT | PARTIAL | S: stores right, `return ?` |
| mergeB | spec | CORRECT | CORRECT | CORRECT | PARTIAL | S: stores right, `return ?` |

## Totals (101 function-builds)

| tool / axis | CORRECT | PARTIAL | WRONG | DECLINED | MISSING |
|---|---|---|---|---|---|
| Ghidra interface | 58 | 0 | 37 | 0 | 6 |
| Ghidra body | 49 | 0 | 46 | 0 | 6 |
| swiftdc interface | 22 | 0 | 7 | 71 | 1 |
| swiftdc body | 9 | 41 | 12 | 38 | 1 |
| swiftdc interface, bare `return` as decline | 22 | 0 | 0 | 78 | 1 |
| swiftdc body, bare `return` as decline | 9 | 46 | 7 | 38 | 1 |

Under the shared `ghidra/scores/RUBRIC.md`, a function missing from one tool's output scores DECLINED/DECLINED. With that rule the totals become:
- Ghidra interface 58/0/37/6 and body 49/0/46/6;
- swiftdc interface 22/0/7/72 and body 9/41/12/39 (each C/P/W/D).

Phantom functions (shown, but not real functions):
- Ghidra: 1. `FUN_0000036c` in shapes2 is the interior label `Lshared` inside shared_b, made into a function because call_mid `bl`s to it.
- swiftdc: 0. It names the same interior target `sub_36c` at the call site but renders no function there.

Missing real functions:
- Ghidra: 6. got_tail is absent in all four shapes builds, and adr_tail and stub_tail are absent in shapes2. All six are pure tail-jump functions (`br x16` / `b _abs`).
- swiftdc: 1. local_helper in shapes_nofs_x is merged into leaf_noframe. swiftdc prints a warning that functions may be merged, but the body is still one merged span.

The body WRONGs that survive the secondary rule:
- swiftdc's 7: reg_call_stale ×2 (stale x1 argument), reg_tail_unknown ×2 and adr_tail (`f()` with no argument), tail_noreturn_cmp (dropped branch), and the shapes_nofs_x merge.
- Ghidra's 46 are dominated by unprototyped callees rendered with zero arguments, and by tail calls rendered as `void` with the result dropped.

## Where Ghidra beats swiftdc

1. **Leaf arithmetic: swiftdc recovers nothing.** fso `exploded`: Ghidra gives `return param_1.c + param_2 * param_1.b;`, swiftdc gives `return ?`. Truth: `p.b &* k &+ p.c` (`madd x0, x3, x1, x2`). The same holds for merge mA/mB/mC, sumUp, and all 13 hand-written leaves in shapes, which swiftdc renders as `// no non-runtime calls`.
2. **No function starts plus a stripped local: swiftdc merges two functions.** shapes_nofs_x: Ghidra finds `FUN_00000364` (`return param_1 + -5;`) from the `bl` target. swiftdc renders `_leaf_noframe { return }` over both bodies and drops local_helper. Truth: leaf_noframe = x*x+1 ends at `ret` 0x360, and local_helper = x-5 starts at 0x364.
3. **Conditional tail call: swiftdc drops a branch.** shapes2 `tail_noreturn_cmp`: Ghidra gives `if (param_1 < 0xb) { lVar1 = _shared_a(); return lVar1; } return param_1 * 4 + 9;`, which keeps the condition. swiftdc gives `shared_a(arg0)` then `return`, unconditionally. Truth: `cmp x0,#10; b.gt _shared_b; b _shared_a`.

## Where swiftdc beats Ghidra

1. **Merged-function (`Tm`) thunks.** merge2 `k2`: Ghidra gives `_Var1 = k1(param_1,param_2); return _Var1;`. The Tm body demangles to the same name as k1, so k2 reads as "returns k1" and the constant 200 in w2 is lost. swiftdc gives `merged ….k1(arg0, arg1, 200)`. Truth: `mov w2, #200; b k1Tm`.
2. **Stale and garbage registers become wrong values.** fso `callExploded`: Ghidra gives `PVar2.a = exploded(PVar1,9); … PVar2.a = exploded(PVar2,0xb); return PVar2.a + PVar2.a;`, which doubles the second call. swiftdc gives `let r0 = FSO.exploded(?, 9)` then `return (FSO.exploded(?, 11) + r0)`. Truth: exploded(…,9) + exploded(…,11). Ghidra also passes a garbage `in_x2` as a third argument to the FSO-specialized deadFirst in callDead, where swiftdc's `deadFirst(arg0, arg1)` is exact.
3. **Tail calls and unprototyped callees.** shapes `tail_caller`: Ghidra gives `void _tail_caller(long param_1) { _real_add(param_1 << 1,7); return; }`, with the result discarded. swiftdc gives `real_add((arg0 << 1), 7)`. Truth: `b _real_add`, so the function returns real_add(2x, 7). Ghidra also leaves out every pure tail-jump function (got_tail ×4, adr_tail, stub_tail). It renders most calls to unprototyped callees with zero arguments: `_twin_b()`, `_local_helper()`, `_sink()`, `_hot_cold_1()`, `_report()`. swiftdc writes `?` in the same places, apart from its own zero-argument `shared_b()` and `one_arg()` in adr_tail and reg_tail_unknown.

ICF: neither tool misattributes the folded twin_a/twin_b body. Ghidra names it `_twin_b` at both call sites, which the fixture accepts. swiftdc declines to `sub_2d0`. On the alias pair, Ghidra picks `_alias_one` and swiftdc declines to `sub_280`.

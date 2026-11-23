# Actors: Ghidra 12.2 vs swiftdc

Fixtures abi2/actors/act1..act7.swift at the builds present (act1 Onone/O/Osize, act2 Onone/O, act3-6 O, act7 Onone/O): 190 scored rows. Async functions are scored as a whole across funclets; user closure bodies emitted as their own function are separate rows. Rubric: ghidra/scores/RUBRIC.md. Per-chunk files with judgement calls: ghidra/scores/parts/actors-*.md. The function column names the chunk.

Judgement calls, applied to both tools: how a tool spells `swift_task_switch` arguments is not scored unless it names a different actor; a runtime call that omits only its receiver or a metadata argument is PARTIAL, while dropping a user value or a closure (Task operation, withTaskGroup body) is WRONG; Ghidra's `undefined X(void)` placeholder is no claim; `unaff_x22` for the async context makes the interface DECLINED. In act2_Onone a closure header that leaves out a captured value the code reads was scored interface WRONG (5 swiftdc rows); act1_Onone scored the same shape DECLINED, so the swiftdc interface WRONG count is the strict reading.

## Totals (190 rows)

| tool | axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|---|
| Ghidra | interface | 71 | - | 21 | 98 |
| Ghidra | body | 77 | 70 | 43 | 0 |
| swiftdc | interface | 133 | - | 5 | 52 |
| swiftdc | body | 30 | 114 | 18 | 28 |

By chunk (interface C/W/D, body C/P/W/D):

| chunk | rows | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body |
|---|---|---|---|---|---|
| act1 Onone | 37 | 17/1/19 | 12/17/8/0 | 26/0/11 | 7/25/2/3 |
| act1 O | 34 | 14/3/17 | 13/11/10/0 | 23/0/11 | 6/17/5/6 |
| act1 Osize | 34 | 14/1/19 | 14/18/2/0 | 22/0/12 | 7/18/9/0 |
| act2 Onone | 29 | 12/2/15 | 9/7/13/0 | 22/5/2 | 2/19/1/7 |
| act2 O | 24 | 7/4/13 | 8/8/8/0 | 17/0/7 | 2/18/1/3 |
| act3-act7 | 32 | 7/10/15 | 21/9/2/0 | 23/0/9 | 6/17/0/9 |

## Where Ghidra beats swiftdc

1. callGA, Osize (act1). Ghidra hops to `MyGA.shared` (`__s4Act14MyGAC6sharedACvpZ`) and returns `x - 4` through the continuation. swiftdc: funclet (1) `swift_task_switch((2) ..., ?, 0)`, funclet (2) only `OUTLINED_FUNCTION_32()`. Truth: funclet (2) is `ldr x8, [x22, #0x10]; subs x0, x8, #0x4; b.vs trap; b _OUTLINED_FUNCTION_32` (gaFunc inlined, x - 4 returned). The same -Osize shape drops `+1` in callBump, `+3` in passIso, `*9` in the spawnDetached closure and `i*2` in the groupSum child.
2. implicit closure #1 in asyncLetMul, Osize (act1). Ghidra: `_OUTLINED_FUNCTION_33(x + 1)`. swiftdc: `OUTLINED_FUNCTION_33()` only. Truth: `add x0, x0, #1` then the outlined continuation tail. swiftdc's body is silently missing the closure's only computation.
3. sumStream, O (act1). Ghidra keeps `t += v` in the loop funclet (iterator receivers unshown). swiftdc's loop funclet shows only the `next()` await, then `return ?`. Truth: the adds at 0x1f2c accumulate v into t. swiftdc drops the user statement (same at Onone).

## Where swiftdc beats Ghidra

1. checkCancel, Onone (act1; also O and Osize for Ghidra). Ghidra: "Removing unreachable block 0x4148" deletes the throw path, so it always returns x. swiftdc keeps the `checkCancellation()` call and the branch on the error (exits unresolved). Truth: source `try Task.checkCancellation(); return x`, and the asm branches on x21 to a throw exit.
2. callMain, O (act7; also Onone). Ghidra: `mainOnly(_Var1); (**(code **)(unaff_x22 + 8))();`: mainOnly's result is discarded and the continuation is called with no value. swiftdc: `return Act7.mainOnly(?)` with a MainActor hop. Truth: x0 from `bl mainOnly` is kept live to the continuation `br x1` at 0x6dc.
3. spawn / highTask / throwingGroup, Onone (act1/act2). Ghidra: `Task::_init()`, `Swift::_withThrowingTaskGroup()` with every argument, including the operation closure, dropped. swiftdc: `Task.init(name:priority:operation:)(0, 0, ?, 0x4e70, r0)` and `withThrowingTaskGroup(of:returning:isolation:body:)(?, ?, ?, ?)`. Truth: x0..x4 carry name, priority, metadata and the closure/context pair. On the interface axis, Ghidra shows the async context as `unaff_x22` in every async function (98 of 190 interfaces DECLINED).

## Per-function table

| function | level | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| Counter.init (act1-O) | O | CORRECT | CORRECT | DECLINED | PARTIAL | S `mem64[x20 + 0x70] = 0`, `swift_defaultActor_initialize(?)`, `return ?` (self as raw x20) |
| Counter.bump (act1-O) | O | CORRECT | PARTIAL | CORRECT | PARTIAL | G modify/getter as unnamed vtable slots 0x70/0x60; S `mem64[x1] = x9` hides `value + by` |
| Counter.fixed (act1-O) | O | CORRECT | CORRECT | CORRECT | CORRECT | |
| Counter.triple (act1-O) | O | CORRECT | CORRECT | CORRECT | CORRECT | |
| callBump (act1-O) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | G unaff_x22; bump called through ctx slot `(*(ctx+0x18))(5)` (vtable+0x80 of c, receiver unshown), returns r+1 correctly; S `indirect_call(?, [5, …])`, `return ?` (r+1 lost) |
| Model.init (act1-O) | O | CORRECT | CORRECT | DECLINED | PARTIAL | S `mem64[x20 + 0x10] = 0`, `return ?` |
| Model.inc (act1-O) | O | CORRECT | CORRECT | CORRECT | CORRECT | |
| touchModel (act1-O) | O | DECLINED | WRONG | DECLINED | PARTIAL | G hop `_swift_task_switch(0xf98, UVar2.unknown, puVar3)` passes MainActor's Actor witness table as the executor's second word (real: x1 returned by unownedExecutor getter); S inlined `count += 1` as raw `mem64[x20 + 0x10] = x8` (x20 = m) |
| mainOnly (act1-O) | O | CORRECT | CORRECT | CORRECT | CORRECT | |
| groupSum (act1-O) | O | DECLINED | WRONG | CORRECT | PARTIAL | G `Swift::_withTaskGroup()` drops every argument incl. of:/body:; S `withTaskGroup(...)(?, ?, ?, ?)`, `return ?` |
| closure #1 in groupSum (act1-O) | O | DECLINED | WRONG | DECLINED | WRONG | both pass the wrong value to `TaskPriority.rawValue` getter (G `get_rawValue(TVar4)` = getEnumTag result, S `rawValue.getter(r0)`; real self is x20 = priority buffer ctx+0x88); S also drops `s += v` from the loop funclet and shows n as raw x8 |
| closure #1 in closure #1 in groupSum (act1-O) | O | DECLINED | CORRECT | DECLINED | DECLINED | G `**(ctx+0x10) = *(ctx+0x18) << 1`; S only `mem64[x9] = x8` + indirect jump |
| asyncLetMul (act1-O) | O | DECLINED | CORRECT | CORRECT | PARTIAL | G full asyncLet_begin/get/finish args and product a*b stored and returned; S begin/get/finish named but product not shown, `return ?` |
| implicit closure #1 in asyncLetMul (act1-O) | O | DECLINED | CORRECT | DECLINED | DECLINED | G `*out = x + 1`; S `mem64[x9] = x8` only |
| implicit closure #2 in asyncLetMul (act1-O) | O | DECLINED | CORRECT | DECLINED | DECLINED | G `*out = x + 2`; S `mem64[x9] = x8` only |
| cont (act1-O) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | G `#function` "cont(_:)" left as raw bits 0x293a5f28746e6f63/0xe8…; S init/resume args `?`, x*10 hidden, `return ?` |
| ucont (act1-O) | O | DECLINED | WRONG | CORRECT | PARTIAL | G `_swift_continuation_resume()` drops its continuation argument (x0); S `swift_continuation_resume(r0)` right, stored value raw, `return ?` |
| tcont (act1-O) | O | DECLINED | WRONG | DECLINED | PARTIAL | G `_swift_allocError(&E, CVar3.unknown, 0, 0)` passes the CheckedContinuation.init result as the witness table (real: accessor's result) and the throw exit drops the error (x20); S `allocError(0x80b0, lazy wt accessor(), 0, false)` right, x shown as raw x23, exits unresolved |
| sumStream (act1-O) | O | DECLINED | PARTIAL | CORRECT | WRONG | S loop funclet drops `t += v` (asm 0x1f2c adds); G has `t += v`, receivers unshown |
| spawn (act1-O) | O | CORRECT | WRONG | CORRECT | WRONG | both give `TaskPriority.rawValue` getter the wrong argument (G retained c, S `arg0` = c; real x20 = priority buffer); S result `return ?` |
| closure #1 in spawn (act1-O) | O | DECLINED | PARTIAL | DECLINED | PARTIAL | G hop to c, bump via ctx slot `(1)`, `*out = r`; S `hop(?)`, `indirect_call(?, [1, …])`, `mem64[x9] = x8` |
| spawnDetached (act1-O) | O | CORRECT | WRONG | CORRECT | WRONG | same rawValue wrong-argument defect in both (G `get_rawValue(TVar3)`, S `rawValue.getter(r0)`, both the getEnumTag result) |
| closure #1 in spawnDetached (act1-O) | O | DECLINED | CORRECT | DECLINED | DECLINED | G `*out = x * 9`; S `mem64[x9] = x8` only |
| napper (act1-O) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | G sleep(1000000) and return x on success, error test on raw unaff_x20; S `sleep(nanoseconds:)(?)`, exit unresolved |
| cancelled (act1-O) | O | CORRECT | PARTIAL | CORRECT | CORRECT | G passes a bogus raw `in_x0` to the isCancelled getter |
| checkCancel (act1-O) | O | DECLINED | WRONG | CORRECT | PARTIAL | G removes the error path as unreachable and returns via continuation with no value (x dropped); S `checkCancellation()` + unresolved exit |
| isoRead (act1-O) | O | WRONG | PARTIAL | CORRECT | PARTIAL | G declares `isoRead(void)` but reads x0 (c) as in_x0; both leave the value getter call unresolved, `+ 1` shown |
| passIso (act1-O) | O | WRONG | WRONG | DECLINED | PARTIAL | G prototype omits isolation (reads in_x1/in_x2), `_swift_getObjectType()` drops its arg, hop passes in_x2 as the executor's second word; S isolation as raw x1, `return ?` |
| gaFunc (act1-O) | O | CORRECT | CORRECT | CORRECT | CORRECT | |
| callGA (act1-O) | O | DECLINED | CORRECT | CORRECT | PARTIAL | G hop to MyGA.shared and returns x - 4; S `hop(?)`, `return ?` |
| SerialExec.enqueue (act1-O) | O | CORRECT | WRONG | CORRECT | PARTIAL | G `_swift_job_run(job, this, &cache_variable)` (real x2: witness table returned by the accessor); S `swift_job_run(?, self)` executor's wt word unshown |
| SerialExec.asUnownedSerialExecutor (act1-O) | O | CORRECT | PARTIAL | CORRECT | DECLINED | G `return (UnownedSerialExecutor)this`, accessor result (x1) discarded; S `return ?` |
| CustomExecActor.unownedExecutor getter (act1-O) | O | WRONG | PARTIAL | CORRECT | DECLINED | G adds unread `CustomExecActor *param_1`; G returns `*(this+0x10)` with wt word discarded; S `return ?` |
| CustomExecActor.get (act1-O) | O | CORRECT | PARTIAL | CORRECT | WRONG | G returns unnamed vtable slot 0x68 call; S renders the tail call as statement `self.n.getter()` with no return |
| Counter.init (act1-Onone) | Onone | CORRECT | PARTIAL | DECLINED | PARTIAL | G `_swift_defaultActor_initialize()` drops self; S self as raw x0, `return ?`, `defaultActor_initialize(?)` |
| Counter.bump (act1-Onone) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G modify/getter via raw vtable slots 0x70/0x60; S `mem64[x10] = x9` for the store, `+by` not shown, yield continuation unresolved |
| Counter.fixed (act1-Onone) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| Counter.triple (act1-Onone) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| callBump (act1-Onone) | Onone | DECLINED | PARTIAL | CORRECT | PARTIAL | G x22 as unaff_x22, bump called through `*(ctx+0x30)`, shows r+1 and return; S callee unresolved (args [5]), `return ?`, +1 missing |
| Model.init (act1-Onone) | Onone | CORRECT | CORRECT | DECLINED | PARTIAL | S self as raw x0, `return ?` |
| Model.inc (act1-Onone) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| touchModel (act1-Onone) | Onone | DECLINED | PARTIAL | CORRECT | PARTIAL | G unaff_x22, `Actor::get_unownedExecutor()` without args, executor 2nd word shown as witness table; S `Act1.Model.inc()` without receiver m |
| mainOnly (act1-Onone) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| groupSum (act1-Onone) | Onone | DECLINED | WRONG | CORRECT | PARTIAL | G calls `Swift::_withTaskGroup()` twice (one is the default-arg fn) with all args (body closure, n) dropped; S `withTaskGroup(?, ?, ?, ?)`, `return ?` |
| closure #1 in groupSum (act1-Onone) | Onone | DECLINED | WRONG | DECLINED | WRONG | G `TaskGroup::_addTask(priority)` drops the operation closure; S drops `s += v` in the `for await` loop (funclet 3 shows only `next()`) |
| closure #1 in closure #1 in groupSum (act1-Onone) | Onone | DECLINED | CORRECT | DECLINED | PARTIAL | G unaff_x22 + unread filler params; S `mem64[x10] = x9`, i*2 not shown |
| asyncLetMul (act1-Onone) | Onone | DECLINED | PARTIAL | CORRECT | PARTIAL | G first `_swift_asyncLet_begin()` without args; a*b and return shown; S closure ptrs raw 0x62d0/0x62e0, a*b missing, `return ?` |
| implicit closure #1 in asyncLetMul (act1-Onone) | Onone | DECLINED | CORRECT | DECLINED | PARTIAL | S `mem64[x10] = x9`, x+1 not shown |
| implicit closure #2 in asyncLetMul (act1-Onone) | Onone | DECLINED | CORRECT | DECLINED | PARTIAL | S `mem64[x10] = x9`, x+2 not shown |
| cont (act1-Onone) | Onone | DECLINED | PARTIAL | CORRECT | DECLINED | G callee via `&...withCheckedContinuation...Tu + off` expression, "cont(_:)", returns ctx[0x38]; S `await indirect_call(?)`, `return ?` |
| closure #1 in cont (act1-Onone) | Onone | CORRECT | PARTIAL | DECLINED | PARTIAL | G `CheckedContinuation::resume(&x*10, meta)` without the continuation receiver; S `resume(returning:)(?)`, x*10 not shown, x as raw |
| ucont (act1-Onone) | Onone | DECLINED | PARTIAL | CORRECT | DECLINED | G callee via withUnsafeContinuation Tu expression; S `await indirect_call(?)`, `return ?` |
| closure #1 in ucont (act1-Onone) | Onone | CORRECT | CORRECT | DECLINED | PARTIAL | S `resume(returning:)(local_28, ?)`, x+100 not shown |
| tcont (act1-Onone) | Onone | DECLINED | PARTIAL | CORRECT | DECLINED | G Tu-expression callee, error test on raw unaff_x20; S `await indirect_call(?)`, both exits are unresolved indirect jumps |
| closure #1 in tcont (act1-Onone) | Onone | CORRECT | WRONG | DECLINED | PARTIAL | G `_swift_allocError(&E, EVar1.unknown, 0, 0)` passes the E.init result where the binary passes the Error witness table from the accessor; S structure right, x as raw x1 |
| sumStream (act1-Onone) | Onone | DECLINED | PARTIAL | CORRECT | WRONG | S drops `t += v` (loop shows only `next()`), `return ?`; G iterator calls miss the stream receiver, `isolation` bound to the result buffer |
| spawn (act1-Onone) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `Task::_init()` drops name/priority/operation; S `Task.init(0, 0, ?, 0x6340, r0)`, `return ?` |
| closure #1 in spawn (act1-Onone) | Onone | DECLINED | PARTIAL | DECLINED | PARTIAL | G bump via `*(ctx+0x30)` (vtable 0x80) unresolved; S unresolved call [1], result store raw |
| spawnDetached (act1-Onone) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `Task::_detached()` drops all args; S `detached(0, 0, ?, 0x6350, r0)`, `return ?` |
| closure #1 in spawnDetached (act1-Onone) | Onone | DECLINED | CORRECT | DECLINED | PARTIAL | S `mem64[x9] = x8`, x*9 not shown |
| napper (act1-Onone) | Onone | DECLINED | PARTIAL | CORRECT | PARTIAL | G `sleep(1000000)`, return x / rethrow on raw unaff_x20; S `sleep(nanoseconds:)(?)`, both exits are unresolved indirect jumps |
| cancelled (act1-Onone) | Onone | CORRECT | PARTIAL | CORRECT | CORRECT | G passes raw in_x0 to `isCancelled` |
| checkCancel (act1-Onone) | Onone | DECLINED | WRONG | CORRECT | PARTIAL | G "Removing unreachable block 0x4148" deletes the throw path, so it always returns x; S branch on error kept, exits unresolved |
| isoRead (act1-Onone) | Onone | DECLINED | PARTIAL | CORRECT | PARTIAL | G `_isoRead(void)` with c as in_x0, getter via vtable 0x60; S unresolved getter call, `? + 1` |
| passIso (act1-Onone) | Onone | DECLINED | PARTIAL | CORRECT | PARTIAL | G isolation as in_x1/in_x2; S `return ?`, x+3 missing |
| gaFunc (act1-Onone) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| callGA (act1-Onone) | Onone | DECLINED | WRONG | CORRECT | PARTIAL | G `uVar1 = *(undefined8 *)param_1` derefs x (really the addressor result) and drops the gaFunc result from the continuation call; S `return Act1.gaFunc(?)` |
| SerialExec.enqueue (act1-Onone) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G job passed as raw in_x1; S `runSynchronously(on:)(?)` without the job |
| SerialExec.asUnownedSerialExecutor (act1-Onone) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `UnownedSerialExecutor::_init()` drops `ordinary: self`; S `init(ordinary:)(self)`, `return ?` |
| CustomExecActor.unownedExecutor getter (act1-Onone) | Onone | WRONG | CORRECT | CORRECT | PARTIAL | G declares an extra `CustomExecActor *param_1` the code never reads; S `return ?` after `asUnownedSerialExecutor(self: self.ex)` |
| CustomExecActor.get (act1-Onone) | Onone | CORRECT | PARTIAL | CORRECT | CORRECT | G n getter via raw vtable slot 0x68 |
| Counter.init (act1-Osize) | Osize | CORRECT | PARTIAL | DECLINED | PARTIAL | G `_swift_defaultActor_initialize()` without its self arg; S shows `mem64[x20 + 0x70] = 0` (raw self) and `return ?` |
| Counter.bump (act1-Osize) | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | S `self.value.modify(local_40); mem64[x1] = x9`: the `+ by` is a raw x9, modify continuation unresolved |
| Counter.fixed (act1-Osize) | Osize | CORRECT | CORRECT | CORRECT | CORRECT | |
| Counter.triple (act1-Osize) | Osize | CORRECT | CORRECT | CORRECT | CORRECT | |
| callBump (act1-Osize) | Osize | DECLINED | PARTIAL | CORRECT | WRONG | G hop to c, `(**(code **)(unaff_x22 + 0x18))(5)` (vtable slot, bump not named), returns r+1; S funclet (2) is only `OUTLINED_FUNCTION_32()`: the `r + 1` (adds x0, x8, #1) is dropped, callee `indirect_call(?)` |
| Model.init (act1-Osize) | Osize | CORRECT | CORRECT | DECLINED | PARTIAL | S `mem64[x20 + 0x10] = 0` raw self, `return ?` |
| Model.inc (act1-Osize) | Osize | CORRECT | CORRECT | CORRECT | CORRECT | |
| touchModel (act1-Osize) | Osize | DECLINED | PARTIAL | DECLINED | PARTIAL | G hops through opaque `_OUTLINED_FUNCTION_1/50` (second executor word shown as a stale witness-table ptr), `Model::inc(this)` right; S main-actor hop named, `Act1.Model.inc()` without its receiver, raw x22 |
| mainOnly (act1-Osize) | Osize | CORRECT | CORRECT | CORRECT | CORRECT | |
| groupSum (act1-Osize) | Osize | DECLINED | WRONG | DECLINED | PARTIAL | G `Swift::_withTaskGroup();` drops of:/returning:/isolation:/body: (the closure); S `withTaskGroup(...)(?, ?, ?, ?)`, return hidden in `OUTLINED_FUNCTION_32()`, raw x22 |
| closure #1 in groupSum (act1-Osize) | Osize | DECLINED | PARTIAL | DECLINED | WRONG | G full loop (i stored at +0x20, `lVar11 + 1`, task_create), sum and `*plVar4 = lVar3` result, with DAT_ metadata addresses; S loop `if (x25 != x21) continue` never shows the counter increment (add x25, x25, #1), so the rendered loop never advances |
| closure #1 in closure #1 in groupSum (act1-Osize) | Osize | DECLINED | CORRECT | DECLINED | WRONG | G `_OUTLINED_FUNCTION_25(i << 1)`; S overflow check on raw x8 then bare `OUTLINED_FUNCTION_25()`: the `i * 2` (lsl x8, x8, #1) is dropped |
| asyncLetMul (act1-Osize) | Osize | DECLINED | PARTIAL | DECLINED | PARTIAL | G all eight funclets, `a * b`, returns slot 0x588; closure entries raw (&__MergedGlobals, &DAT_00003128); S product only as raw `mem64[x22 + 0x588] = x8`, final return `indirect_jump(?)` |
| implicit closure #1 in asyncLetMul (act1-Osize) | Osize | DECLINED | CORRECT | CORRECT | WRONG | G `_OUTLINED_FUNCTION_33(x + 1)`; S `OUTLINED_FUNCTION_33()` only: `x + 1` dropped |
| implicit closure #2 in asyncLetMul (act1-Osize) | Osize | DECLINED | CORRECT | CORRECT | WRONG | G `_OUTLINED_FUNCTION_33(x + 2)`; S `OUTLINED_FUNCTION_33()` only: `x + 2` dropped |
| cont (act1-Osize) | Osize | DECLINED | PARTIAL | DECLINED | PARTIAL | G `x * 10` resumed and returned, but function string "cont(_:)" only as raw bits 0x293a5f28746e6f63/0xe8..; S string `?`, product as raw x8, return `OUTLINED_FUNCTION_43(?, ?)` |
| ucont (act1-Osize) | Osize | DECLINED | CORRECT | DECLINED | PARTIAL | G stores `x + 100` into the continuation slot, resume, await, returns slot; S `mem64[x9] = x8` raw for x+100, return hidden in `OUTLINED_FUNCTION_32()` |
| tcont (act1-Osize) | Osize | DECLINED | PARTIAL | DECLINED | PARTIAL | G both branches right, string "tcont(_:)" only as raw bits; S both branches right on raw x21/x8, string `?`, returns `indirect_jump(?)` |
| sumStream (act1-Osize) | Osize | DECLINED | PARTIAL | DECLINED | PARTIAL | G t=0, `t + v`, returns t; `Iterator::_next(isolation)` passes the result buffer as "isolation"; S `t + v` as raw x8, return `OUTLINED_FUNCTION_43(?, ?)` |
| spawn (act1-Osize) | Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | both hide context setup and task_create in OUTLINED_FUNCTION_21/19; G returns OF_38(task), S `return ?` |
| closure #1 in spawn (act1-Osize) | Osize | DECLINED | PARTIAL | CORRECT | PARTIAL | G hop to c, vtable call `(1)` unnamed, returns result via OF_25; S `hop_to_executor(?)`, `indirect_call(?, [1])`, result hidden in `OUTLINED_FUNCTION_25()` |
| spawnDetached (act1-Osize) | Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | same shape as spawn |
| closure #1 in spawnDetached (act1-Osize) | Osize | DECLINED | CORRECT | CORRECT | WRONG | G `_OUTLINED_FUNCTION_25(x * 9)`; S `OUTLINED_FUNCTION_25()` only: `x &* 9` dropped |
| napper (act1-Osize) | Osize | DECLINED | PARTIAL | CORRECT | PARTIAL | G `Task::_sleep(1000000)`, returns x when `unaff_x20 == 0`; S `sleep(nanoseconds:)(?)` (constant unresolved), return `indirect_jump(?)` |
| cancelled (act1-Osize) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G passes a bogus raw `in_x0` to the static isCancelled getter |
| checkCancel (act1-Osize) | Osize | DECLINED | WRONG | CORRECT | WRONG | G removed the throw path as "unreachable" (x21 zeroed before the call) and drops the returned x; S also has no error branch, `indirect_jump(?)`, and passes a bogus `OUTLINED_FUNCTION_22()` arg to checkCancellation |
| isoRead (act1-Osize) | Osize | DECLINED | PARTIAL | CORRECT | PARTIAL | G `$isoRead(void)` reads raw `in_x0`, value getter via vtable slot unnamed; S `? + 1` from an unresolved call |
| passIso (act1-Osize) | Osize | DECLINED | PARTIAL | DECLINED | WRONG | G prototype has only x, isolation read as raw x1/`in_x2`; returns x + 3; S isolation shown as raw x1, `x + 3` dropped (`OUTLINED_FUNCTION_32()`) |
| gaFunc (act1-Osize) | Osize | CORRECT | CORRECT | CORRECT | CORRECT | |
| callGA (act1-Osize) | Osize | DECLINED | CORRECT | CORRECT | WRONG | G hop to MyGA.shared (`__s4Act14MyGAC6sharedACvpZ`), returns x - 4; S hop executor `?`, `x - 4` dropped |
| SerialExec.enqueue (act1-Osize) | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | S `swift_job_run(?, self)`: job `?` and the executor witness-table word missing |
| SerialExec.asUnownedSerialExecutor (act1-Osize) | Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | G `return (UnownedSerialExecutor)this` loses the witness-table word; S `return ?` |
| CustomExecActor.unownedExecutor (getter) (act1-Osize) | Osize | WRONG | PARTIAL | CORRECT | PARTIAL | G prototype adds an unread `CustomExecActor *param_1`; G returns `self.ex` without the witness word; S `return ?` |
| CustomExecActor.get (act1-Osize) | Osize | CORRECT | PARTIAL | CORRECT | CORRECT | G vtable slot 0x68 call unnamed; S `self.n.getter()` (tail call, single-expression body) |
| Bank.init (act2-O) | O | CORRECT | CORRECT | DECLINED | PARTIAL | S shows self as raw x20, `defaultActor_initialize(?)`, `return ?` |
| Bank.transfer (act2-O) | O | DECLINED | WRONG | CORRECT | DECLINED | G async ctx `unaff_x22`, final funclet calls continuation `(**(x22+8))()` dropping the balance-getter result; S all callees, the subtraction and the return are `?` (`mem64[x1] = x9`, indirect_call(?)) |
| Bank.deposit (act2-O) | O | CORRECT | PARTIAL | CORRECT | PARTIAL | G modify via raw vtable slot `*this+0x70` (sum right); S `self.balance.modify` then `mem64[x1] = x9`, the `+ amt` not shown |
| Bank.plain (act2-O) | O | DECLINED | CORRECT | CORRECT | CORRECT | G async ctx raw x22 |
| Bank.unownedExecutor getter (act2-O) | O | WRONG | PARTIAL | CORRECT | DECLINED | G adds `Bank *param_1` the code never reads, returns `(UnownedSerialExecutor)this` without the 0 second word; S `return ?` |
| readBalance (act2-O) | O | DECLINED | WRONG | CORRECT | DECLINED | G continuation called with no args, the balance result is lost; S hop(?), indirect_call(?), `return ?` |
| onMain (act2-O) | O | DECLINED | PARTIAL | DECLINED | PARTIAL | G hop to MainActor: second executor word shown as the witness table, x*2 return right; S x shown as raw x20, return `?` (overflow check right) |
| assume (act2-O) | O | CORRECT | WRONG | CORRECT | PARTIAL | G passes the closure as `(StaticString)0x105c`, drops file/line, returns the forwarder's address `pcVar1`; S `return assumeIsolated(?, ?, ?)` |
| withHandler (act2-O) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | G handler named by folded alias `Boom::get_code`, x+11 return right; S handler calls right, return `?` |
| yielder (act2-O) | O | DECLINED | CORRECT | CORRECT | PARTIAL | S final funclet `indirect_jump(?)`, x return not shown |
| throwingGroup (act2-O) | O | DECLINED | WRONG | CORRECT | PARTIAL | G `_withThrowingTaskGroup()` with every argument (body closure included) dropped, error funclet drops the rethrown error; S `await withThrowingTaskGroup(?, ?, ?, ?)`, return `?` |
| closure #1 in throwingGroup (act2-O) | O | DECLINED | WRONG | DECLINED | WRONG | G loop/addTask/sum/cancelAll right, but the error funclet (0x18f0) returns with no error (x20=[x22+0x58] dropped); S omits `s += v` (adds x24,[x22+0x48] at 0x1888) and `i += 1`, n as raw x8 |
| closure #1 in closure #1 in throwingGroup (act2-O) | O | WRONG | WRONG | DECLINED | PARTIAL | G declares 4 params, p2/p3 unread, `swift_allocError(Boom, param_1, …)` passes the result pointer where the Boom witness table goes; S raw x8/x9 for i and result slot, allocError args right |
| makeStream (act2-O) | O | WRONG | WRONG | CORRECT | PARTIAL | G result type `AsyncThrowingStream<__int64, Act2.makeStream()…>` garbled, `_init((BufferingPolicy)Int-metadata)` drops the closure; S `init(Int, ?, closure #1, 0)`, return `?` |
| closure #1 in makeStream (act2-O) | O | WRONG | PARTIAL | CORRECT | PARTIAL | G `void(void)` misses the continuation param; yields 1,2,3 right but no receiver, finish arg cast as Continuation; S `yield(?)` x3, values unresolved |
| withLocal (act2-O) | O | DECLINED | CORRECT | CORRECT | PARTIAL | S push/get/pop with `?` args, push shows 2 of 3 runtime args, return `?` |
| highTask (act2-O) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | G `get_high(in_x0)`, `Task::_get_value(x22+0x10)` types the result slot as the Task and drops the created task; S `await Task.value.getter(?, r3)` right, return `?` |
| closure #1 in highTask (act2-O) | O | DECLINED | CORRECT | DECLINED | PARTIAL | S result slot raw x8 (`mem64[x8] = 7`), exit `indirect_jump(?)` |
| cancelIt (act2-O) | O | CORRECT | CORRECT | CORRECT | PARTIAL | S `Swift.Task.cancel()` without t |
| mainTask (act2-O) | O | CORRECT | PARTIAL | CORRECT | PARTIAL | G executor second word as the witness table; S ctx store shows raw x23, options `?`, return `?` |
| closure #1 in mainTask (act2-O) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | G hop executor word as the witness table, `mainCounter = 1` right; S hop(?), `mem64[0x8350] = 1` raw address |
| VM.init (act2-O) | O | CORRECT | CORRECT | DECLINED | PARTIAL | S self raw x20, value raw x8, `return ?` |
| VM.load (act2-O) | O | DECLINED | WRONG | DECLINED | PARTIAL | G names the sleep error (x20) `this`, error funclet 0x2688 returns with the error dropped (append path exact); S self as raw x21, sleep(?), append as raw buffer stores, error exit declined |
| VM.nine (act2-O) | O | CORRECT | CORRECT | CORRECT | CORRECT | |
| Bank.init (act2-Onone) | Onone | CORRECT | CORRECT | DECLINED | PARTIAL | S self shown as raw `x0` (`mem64[x0 + 0x70] = 100`), `return ?` |
| Bank.transfer (act2-Onone) | Onone | DECLINED | WRONG | CORRECT | DECLINED | G `unaff_x22`; last funclet discards the balance getter result and calls the continuation with no value (return missing), deposit only a raw vtable `+0x68` call. S every call `indirect_call(?)`, subtraction not shown, `return ?` |
| Bank.deposit (act2-Onone) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G right (`*p = lVar2 + param_1`) but modify is a raw vtable `+0x70` call; S names `balance.modify` but the sum is raw `mem64[x10] = x9` |
| Bank.plain (act2-Onone) | Onone | DECLINED | CORRECT | CORRECT | DECLINED | G `unaff_x22`, body continuation(x + 1) with overflow trap; S only `hop_to_executor(generic)` and `return ?` |
| Bank.unownedExecutor getter (act2-Onone) | Onone | WRONG | WRONG | CORRECT | PARTIAL | G invents `Bank *param_1` (x0, never read) and passes it instead of self (x20) to UnownedSerialExecutor.init; S `UnownedSerialExecutor.init(?)`, `return ?` |
| readBalance (act2-Onone) | Onone | DECLINED | WRONG | CORRECT | DECLINED | G `unaff_x22`; resume calls `(*(x22+0x28))()` getter, drops its result, continuation called with no value; S `indirect_call(?)`, `return ?` |
| onMain (act2-Onone) | Onone | DECLINED | PARTIAL | CORRECT | DECLINED | G run callee only as `&$sScM3run...Tu + lVar5`, args right, returns `*(x22+0x38)`; S `await indirect_call(?)` (MainActor.run not named), `return ?` |
| closure #1 in onMain (act2-Onone) | Onone | CORRECT | CORRECT | WRONG | DECLINED | G `*param_1 = param_2 * 2` (x8, x0) with overflow trap; S header `() -> Int` omits the captured x read in x0, body `if (x8 != 0) trap()`, `mem64[&result] = x8` |
| assume (act2-Onone) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `_assumeIsolated(this,(StaticString)0x1660,auStack_60)` passes the closure forwarder as the StaticString, drops context, file and line 25; S `assumeIsolated(_:file:line:)(?, ?, ?)`, `return ?` |
| closure #1 in assume (act2-Onone) | Onone | CORRECT | WRONG | WRONG | PARTIAL | G treats x (param_2) as mainCounter's address (`*plVar2 = *plVar2 + param_2`) and reads the result from `_swift_endAccess`'s return; S omits capture x, adds shown only as raw `mem64[x9] = x8` |
| withHandler (act2-Onone) | Onone | DECLINED | PARTIAL | CORRECT | DECLINED | G withTaskCancellationHandler only as mangled `Tu` pointer arithmetic, args and result right; S `await indirect_call(?)`, `return ?` |
| closure #1 in withHandler (act2-Onone) | Onone | DECLINED | CORRECT | WRONG | DECLINED | G `unaff_x22`, `*param_1 = param_4 + 0xb`; S omits capture x (x3), body `mem64[x0] = x8` |
| closure #2 in withHandler (act2-Onone) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| yielder (act2-Onone) | Onone | DECLINED | PARTIAL | CORRECT | PARTIAL | G entry funclet models the Task.yield tail call as `return (__int64)puVar1`, resume continuation(x) right; S names `Task.yield()`, `return ?` |
| throwingGroup (act2-Onone) | Onone | DECLINED | WRONG | CORRECT | PARTIAL | G calls `Swift::_withThrowingTaskGroup()` with no arguments (body closure, of: dropped) and returns `x22+0x38` from the entry; S `withThrowingTaskGroup(of:returning:isolation:body:)(?, ?, ?, ?)`, `return ?` |
| closure #1 in throwingGroup (act2-Onone) | Onone | DECLINED | WRONG | WRONG | WRONG | G `ThrowingTaskGroup::_addTask(TVar5)` drops the operation closure, `_assertionFailure` args garbled; S header omits captured n (x2) and the `s += v` add (0x25d0) is missing from the loop funclet |
| closure #1 in closure #1 in throwingGroup (act2-Onone) | Onone | DECLINED | WRONG | WRONG | PARTIAL | G `_swift_allocError(&Boom, BVar2.code, 0, 0)` passes the code as the witness table (real x1 = lazy witness table accessor result); S omits captured i (x3), condition raw `x8 != 0`, `Boom.init(code:)(?)` |
| makeStream (act2-Onone) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `AsyncThrowingStream::_init((BufferingPolicy)local_18)` drops the closure that yields 1,2,3; S `init(Int, ?, closure #1 ..., 0)`, `return ?` |
| closure #1 in makeStream (act2-Onone) | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | G yields 1, 2, 3 and finish(nil) with the values right but no continuation receiver and the first yield missing its metadata; S `yield(?)` x3, `finish(throwing:)(?)` |
| withLocal (act2-Onone) | Onone | DECLINED | WRONG | CORRECT | PARTIAL | G withValue self is `*(undefined8 *)param_1` (dereferences x, not the `$id` addressor result); S `withValue(_:operation:file:line:)(?, ?, ?, ?)`, file literal right, `return ?` |
| closure #1 in withLocal (act2-Onone) | Onone | WRONG | PARTIAL | CORRECT | PARTIAL | G invents `Ctx param_2` (x0 never read) and passes it to `get_id`; S `Ctx.id.getter()`, result raw `x0` |
| highTask (act2-Onone) | Onone | DECLINED | WRONG | CORRECT | PARTIAL | G `Task::_init()` with no arguments (priority, operation dropped), `_get_value(TVar5)` drops the task; S `Task.init(name:priority:operation:)(0, 0, ?, 0x4e70, r0)` and `await Task.value.getter(?, r1)`, `return ?` |
| closure #1 in highTask (act2-Onone) | Onone | DECLINED | CORRECT | CORRECT | PARTIAL | G `unaff_x22`, `**(x22+0x18) = 7`; S `mem64[x9] = 7` raw result pointer |
| cancelIt (act2-Onone) | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | S `Swift.Task.cancel()` omits the task t |
| mainTask (act2-Onone) | Onone | CORRECT | WRONG | CORRECT | PARTIAL | G `Task::_init()` with no arguments drops the MainActor operation; S `Task.init(...)(0, 0, ?, 0x4e80, r0, ())` raw function pointer, `return ?` |
| closure #1 in mainTask (act2-Onone) | Onone | DECLINED | WRONG | CORRECT | PARTIAL | G stores 1 through `_swift_release`'s return value (`puVar1 = _swift_release(...); *puVar1 = 1`), not the mainCounter addressor; S addressor named, `mem64[x9] = 1` raw |
| VM.init (act2-Onone) | Onone | CORRECT | CORRECT | DECLINED | PARTIAL | S self as raw `x0`, items value as `[…]`/raw `x8`, `return ?` |
| VM.load (act2-Onone) | Onone | DECLINED | PARTIAL | CORRECT | PARTIAL | G `_sleep(10)` and append right, but the error register is spelled `this` (`if (this == 0)`) and append omits the array receiver; S `sleep(nanoseconds:)(?)`, `Array.append(?)` |
| VM.nine (act2-Onone) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| sink (act3to7) | O | DECLINED | CORRECT | CORRECT | CORRECT | G async ctx raw `unaff_x22` |
| sinkT (act3to7) | O | DECLINED | CORRECT | CORRECT | CORRECT | G async ctx raw `unaff_x22` |
| r1 (act3to7) | O | DECLINED | CORRECT | CORRECT | PARTIAL | G ctx raw x22 (resume calls continuation with saved x, right); S resume `indirect_jump(?)`, x not shown |
| r2 (act3to7) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | G returns x when raw `unaff_x20 == 0`; S `machine_return() /* unresolved Swift success/error exit */` |
| r3 (act3to7) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | resume 0x7e0 is `b` into r1's resume: G `_r1(param_1)` (ambiguous name shared with r1's entry, result not identifiable); S `(1) await resume partial function for Act3.r1()`, result not shown |
| r4 (act3to7) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | G `Task::_sleep(1)` right, resume `_r2(param_1)`; S `sleep(nanoseconds:)(?)`, resume tail into r2's funclet, result not shown |
| r5 (act3to7) | O | DECLINED | CORRECT | CORRECT | PARTIAL | G continuation `(lVar4 + lVar1)` = x+y; S resume `return ?` |
| K.init (act4) (act3to7) | O | CORRECT | CORRECT | DECLINED | PARTIAL | S self raw `mem64[x20 + 0x10] = 1`, `return ?` |
| A4.init (act3to7) | O | CORRECT | CORRECT | DECLINED | PARTIAL | S `swift_defaultActor_initialize(?)`, raw x20 self, `return ?` |
| plainK (act3to7) | O | CORRECT | CORRECT | CORRECT | CORRECT | |
| isoA (act3to7) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | G `(void)` prototype, a as raw `in_x0`, getter as raw vtable slot `*in_x0 + 0x60` without x20 receiver; S `indirect_call(?)` and `? + 1` |
| optAny (act3to7) | O | WRONG | CORRECT | CORRECT | CORRECT | G prototype has 1 param, binary ABI takes x and `AnyObject?` (x1) |
| isoAny (act3to7) | O | WRONG | CORRECT | CORRECT | DECLINED | G 1 param, misses the 2-word `(any Actor)?` (x1,x2); S body only `return ?` |
| nonIsoAny (act3to7) | O | WRONG | CORRECT | CORRECT | PARTIAL | G 1 param, misses `(any Actor)?`; S tail `Act4.isoAny(?, ?)` (right folded target, args unresolved) |
| K.init (act5) (act3to7) | O | CORRECT | CORRECT | DECLINED | PARTIAL | S self raw x20, `return ?` |
| sendK (act3to7) | O | CORRECT | CORRECT | CORRECT | DECLINED | S body only `return ?` (true: k.v + 1, release k) |
| optActor (act3to7) | O | WRONG | CORRECT | DECLINED | DECLINED | ICF 0xab0: G shows it as `_anyActor(param_1)`, 1 param vs x + 2-word `(any Actor)?`; S `sub_ab0` with no header and an empty "leaf" body (x+3 not shown) |
| anyActor (act3to7) | O | WRONG | CORRECT | DECLINED | DECLINED | ICF 0xab0: G 1 param, misses the 2-word `any Actor`; S `sub_ab0`, no header, empty body |
| isoAnyClosure (act3to7) | O | WRONG | PARTIAL | CORRECT | DECLINED | G 1 param plus raw `in_x1`, misses the closure context x2 it reads (0xacc `mov x20, x2`) and the isolation words; G calls f via `iVar1 + in_x1` without its context, returns x+2 right; S `await indirect_call(?)`, `return ?` |
| a1 (act3to7) | O | WRONG | CORRECT | DECLINED | DECLINED | ICF 0x408: G `_a1(param_1)` 1 param vs x + 2-word `(any Actor)?`; S `sub_408`, no header, empty body |
| a2 (act3to7) | O | WRONG | CORRECT | DECLINED | DECLINED | ICF 0x408: G 1 param vs x + 2-word `any Actor`; S `sub_408` |
| a3 (act3to7) | O | WRONG | CORRECT | DECLINED | DECLINED | ICF 0x408: G 1 param vs x + `AnyObject?`; S `sub_408` |
| a4 (act3to7) | O | DECLINED | CORRECT | CORRECT | PARTIAL | G ctx raw x22 (follows `b 0x408`, continuation(x+3)); S `sub_408(arg0)`, callee unnamed and its result not shown |
| a5 (act3to7) | O | WRONG | CORRECT | DECLINED | DECLINED | ICF 0x408: G 1 param vs x + indirect `any Sendable`; S `sub_408` |
| mainOnly (act3to7) | O | CORRECT | CORRECT | CORRECT | CORRECT | |
| callMain (act3to7) | O | DECLINED | WRONG | CORRECT | PARTIAL | G resume #2 `mainOnly(_Var1); (**(code **)(unaff_x22 + 8))();` drops mainOnly's result (x0 is passed to the continuation at 0x6dc); S `return Act7.mainOnly(?)`, MainActor hop `hop_to_executor(?)` |
| mainAsync (act3to7) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | G MainActor hop with witness table as second executor word, getter without receiver, returns x+1 right; S shared getter + `hop_to_executor(?)`, `return ?` |
| mainAsync2 (act3to7) | O | DECLINED | PARTIAL | CORRECT | PARTIAL | G shared, yield, hop (witness-table word), x+1 right; S shared, yield, `hop_to_executor(?)`, `return ?` |
| mainOnly (act3to7) | Onone | CORRECT | CORRECT | CORRECT | CORRECT | |
| callMain (act3to7) | Onone | DECLINED | WRONG | CORRECT | PARTIAL | G resume #2 calls mainOnly then the continuation with no args, result lost (0x6c4 `bl mainOnly`, x0 kept to `br x1`); S `return Act7.mainOnly(?)`, hop(?) |
| mainAsync (act3to7) | Onone | DECLINED | PARTIAL | CORRECT | PARTIAL | G hop plumbing (witness-table word), x+1 right; S hop(?), `return ?` |
| mainAsync2 (act3to7) | Onone | DECLINED | PARTIAL | CORRECT | PARTIAL | G hop plumbing, x+1 right; S shared, yield, hop(?), `return ?` |

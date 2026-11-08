# Async functions and coroutine accessors — ABI ground truth for swiftdc

Mined from `/Users/camden/swift` (read-only, HEAD `1b7bd8eaf460396047c2644d1d69afb4a404b13d`,
2026-09-07) to ground swiftdc's recognition of `async` functions and `read`/`modify`
(and the newer `yielding borrow`/`yielding mutate`) coroutine accessors in the actual
ABI, not heuristics. Every ABI claim below carries a `file:line` citation into that
checkout, or is explicitly marked as empirically observed against a compiled fixture
(§8) where the checkout doesn't settle the question (most of the physical-function
splitting is done by LLVM's CoroSplit pass, which lives in the LLVM monorepo and is
**not** vendored here — that boundary is called out everywhere it matters).

Per the authority hierarchy in the project's `CLAUDE.md`: this document is research
documentation (rank 4). It is a record of what the swiftlang/swift checkout said on
2026-09-08. Verify against swiftdc's own tests (rank 1) and `git log -S` in the swift
checkout (rank 2) before trusting a claim here in a dispute.

This document is a sibling of `calling-convention.md` and `mangling-grammar.md` in this
same directory and cross-references both rather than repeating them: register roles
(x20 self, x21 swifterror, x22 async context) and the coroutine-yield register
convention (continuation pointer in x0, first yielded value in x1) are established
there (`calling-convention.md:50`, `:379-383`) and are not re-derived here except where
this pass adds a correction or resolves a flagged-open question (§5.2, §6).

## 0. Scope

Source consulted: `docs/ABI/CallingConventionSummary.rst`, `docs/ABI/Mangling.rst`,
`include/swift/ABI/Coro.h`, `include/swift/ABI/Task.h`, `include/swift/ABI/MetadataValues.h`,
`include/swift/AST/AccessorKinds.def`, `include/swift/AST/Types.h` (`SILCoroutineKind`),
`include/swift/RemoteInspection/RuntimeInternals.h`, `include/swift/Runtime/Concurrency.h`,
`include/swift/Runtime/RuntimeFunctions.def`, `lib/IRGen/GenCall.cpp`,
`GenConcurrency.cpp`, `GenCoro.cpp`, `GenFunc.cpp`, `IRGenModule.cpp`, `IRGenSIL.cpp`,
`lib/LLVMPasses/LLVMEmitAsyncEntryReturnMetadata.cpp`, `lib/AST/ASTMangler.cpp`,
`lib/Demangling/{Demangler,NodePrinter,Remangler}.cpp`,
`stdlib/public/Concurrency/{Task,Actor,AsyncLet}.cpp`, and `test/{IRGen,DebugInfo,Backtracing}/*`
for real compiled examples.

**Not in this checkout**: LLVM's coroutine-splitting pass (`CoroSplit.cpp`, in
`llvm/lib/Transforms/Coroutines` in the LLVM monorepo) is what physically turns one
logical `async`/coroutine SIL function into the multiple machine functions ("funclets")
a decompiler actually sees. Swift's IRGen only emits `llvm.coro.*` intrinsic calls with
`swifttailcc`/`swiftcorocc` and a small number of function attributes (`async_entry`,
and — inferred, not found as a producer in this repo — `async_ret`/`async_continuation`,
see §5.3); the splitting algorithm, the exact rule for which physical function gets
`async_ret` vs `async_continuation`, and the `.resume.N` naming scheme for classic
coroutine continuations are LLVM's, not Swift's, and are **not searched here**. Where
this document states something about split-function shape that can only be confirmed by
running the compiler, it is labeled "empirically observed" with the exact reproduction
command (§8), per the project's "measure, don't assert" rule — never asserted as if it
were a checked-in source fact.

**Historical note, corrects the task's premise**: `stdlib/public/runtime/` does **not**
contain the concurrency runtime. It lives in `stdlib/public/Concurrency/` (`Task.cpp`,
`Actor.cpp`, `AsyncLet.cpp`, `TaskGroup.cpp`, `TaskStatus.cpp`, …). All runtime citations
below point there.

---

## 1. The async function ABI

### 1.1 The async context object

The async context is **not** a rich argument/result-passing struct. Current IRGen's own
comment is explicit that this used to be true and no longer is:

> "FIXME: everything about this type is way more complicated than it needs to be now
> that we no longer pass and return things in memory in the async context and therefore
> the layout is totally static." — `lib/IRGen/GenCall.cpp:121-123`

The context's fixed header is exactly two pointers:

```cpp
AsyncContextLayout irgen::getAsyncContextLayout(...) {
  // AsyncContext * __ptrauth_swift_async_context_parent Parent;
  ...
  // TaskContinuationFunction * __ptrauth_swift_async_context_resume
  //     ResumeParent;
  ...
}
```
— `GenCall.cpp:118-147`, header size fixed at `2 * IGM.getPointerSize()`
(`GenCall.cpp:114-116`, asserted at `:160`). The runtime-facing mirror of the same
layout: `template<Runtime> struct AsyncContext { StoredSignedPointer Parent;
StoredSignedPointer ResumeParent; };` — `include/swift/RemoteInspection/RuntimeInternals.h:141-144`.
IRGen's LLVM type for it is literally two pointers:

```cpp
SwiftContextTy->setBody({
  SwiftContextPtrTy,             // Parent
  TaskContinuationFunctionPtrTy, // ResumeParent
});
```
— `lib/IRGen/IRGenModule.cpp:721-724`. `TaskContinuationFunction` is
`SWIFT_CC(swift) void (SWIFT_ASYNC_CONTEXT AsyncContext *)` — `IRGenModule.cpp:716-719`.

**Arguments and results are not boxed into this struct.** They travel through the
ordinary Swift native calling convention (the same x0-x7 / indirect-result rules
`calling-convention.md` documents), *plus* one extra register that carries the async
context pointer itself. A per-call **child** context (the callee's private stack frame
substitute) is a separate, dynamically-sized allocation on top of this 2-word header —
see §1.3.

One exception: for a plain `async throws` function (untyped `Error`, not `throws(E)`),
the thrown error is **not** in a register and not an ordinary indirect pointer argument.
It rides as an extra parameter on the **resume function's own signature**
(`expandAsyncAwaitType`, `GenCall.cpp:2382-2399`), with the comment "For now we continue
to store the error result in the context to be able to reuse non throwing functions."
(`GenCall.cpp:2372-2373`). This is a corner of the ABI I did not trace to a specific
machine register — see §5.2's note on error delivery, and the correction to
`calling-convention.md`'s flagged-open item in §6.

### 1.2 The `swiftasync` register and `swifttailcc`

Async functions use a dedicated calling convention, not `swiftcc`:

```cpp
if (isAsyncCCSupported) {
  SwiftAsyncCC = llvm::CallingConv::SwiftTail;
  AsyncTailCallKind = llvm::CallInst::TCK_MustTail;
} else {
  SwiftAsyncCC = SwiftCC;
  AsyncTailCallKind = llvm::CallInst::TCK_Tail;
}
```
— `lib/IRGen/IRGenModule.cpp:572-581`. In LLVM terms this is `swifttailcc` with the
async context argument marked `swiftasync`, and every resumption is a **musttail call**,
never an ordinary `ret`. The register that carries the `swiftasync` context is
architecture-specific and is a genuine callee-saved GPR, not a stack slot:

```
| r14 | Callee-saved register | ... | Async |     (x86-64)
| x22 | Callee-saved register | ... | Async |     (arm64)
```
— `docs/ABI/CallingConventionSummary.rst:53`, `:156` (already the load-bearing citation
in `calling-convention.md:39-50`; repeated here because it is the single register a
decompiler must track to follow an async call chain). `IRGenFunction::getAsyncContext()`
/ `setupAsync()` read and write this value from a spilled stack slot inside a function
body (`GenCall.cpp:203-212, 244-247`), but at a **call boundary** it is the live value
in x22/r14.

Async functions get a `void` LLVM return type unconditionally:
`SignatureExpansion::expandAsyncEntryType()` sets `ResultIRType = IGM.VoidTy`
(`GenCall.cpp:2283`) — there is no return value at the machine level at all; results
are delivered by the callee eventually tail-calling back into one of the caller's resume
funclets (§1.3, §4). This matches `calling-convention.md:404-406`'s claim exactly and
is reconfirmed empirically in §8.1: a real compiled async function's entry funclet ends
in `br <reg>`, never `ret`.

### 1.3 Split-funclet shape

An `async` function is IRGen'd as **one logical function** containing
`@llvm.coro.id.async` / `@llvm.coro.suspend.async` intrinsic markers at each suspension
point (`emitSuspendAsyncCall`, `GenCall.cpp:254-281`; `hop_to_executor` SIL lowers to
`llvm.coro.async.resume` + the same suspension helper, `IRGenSIL.cpp:8102-8112`). LLVM's
CoroSplit pass (not in this checkout, see §0) then physically splits that one function
into **N+1 machine functions** for a function with N suspension points: one **entry**
function (the original mangled symbol) plus N **resume funclets**, each beginning
execution right after one suspension point. This is the literal meaning of "split
funclets" for async code — it is not a Swift-level transform at all, only a
Swift-emitted marker consumed by an LLVM pass.

Each suspension point allocates a **child async context** — a heap allocation sized to
that specific call's needs, obtained via `swift_task_alloc` (not malloc — see §2) and
freed via `swift_task_dealloc`:

```cpp
Address irgen::emitAllocAsyncContext(IRGenFunction &IGF, llvm::Value *sizeValue) {
  auto alignment = IGF.IGM.getAsyncContextAlignment();
  auto address = IGF.emitTaskAlloc(sizeValue, alignment);
  ...
}
```
— `GenCall.cpp:5302-5308`, alignment is `MaximumAlignment` (`GenCall.cpp:163-165`,
i.e. 16 bytes on Apple platforms). The size for a **direct call to a known async
function** comes from that function's `AsyncFunctionPointer` record (§4.1); a handful of
built-in "special" runtime entry points (`TaskFutureWait[Throwing]`, `AsyncLetWait[Throwing]`,
`AsyncLetGet[Throwing]`, `AsyncLetFinish`, `TaskGroupWaitNext/WaitAll`,
`DistributedExecuteTarget`) instead get a fixed static size, header + 3 pointers
(`FunctionPointerKind::getStaticAsyncContextSize`, `GenCall.cpp:171-201`) — the comment
there ("This is very arguably a mistake") is a useful signal that this static-size
family is a distinguishable, closed set worth special-casing in a recognizer (§7).

**Empirically** (§8.1), the child context's first two words are always written to
`{Parent = caller's context, ResumeParent = <address of the specific resume funclet that
should run next>}` immediately before the call, and the call itself ends in an indirect
branch to the callee's entry address loaded from the callee's `AsyncFunctionPointer` —
never a `bl`/`call` with a return address, and never a plain `ret` afterward. This is the
mechanical reason async control flow cannot be read as an ordinary call graph: the
"return" from a suspended async call is a *tail branch into a different physical
function* chosen by the ResumeParent pointer stored at the *call site*, not by the
architecture's link register.

---

## 2. Runtime calls a decompiler will see, and what they mean

All signatures from `include/swift/Runtime/Concurrency.h` and
`include/swift/Runtime/RuntimeFunctions.def`; semantics cross-checked against
`stdlib/public/Concurrency/{Task,Actor,AsyncLet}.cpp`.

| Symbol | Signature (informal) | Calling convention | Meaning |
|---|---|---|---|
| `swift_task_switch` | `(AsyncContext *resumeCtx, TaskContinuationFunction *resumeFn, SerialExecutorRef newExecutor)` | `swiftasync` (`RuntimeFunctions.def:2515-2525`) | Hop to a different executor before resuming `resumeFn`. Emitted for `hop_to_executor` (actor isolation changes) and internally whenever a continuation/task-switch needs to change who's running. If the current executor is already compatible it tail-calls `resumeFn` immediately without ever hitting the scheduler (`Actor.cpp:2593-2623`) — so seeing a call to this symbol does **not** by itself prove a thread hop happened. |
| `swift_task_create` | `(size_t flags, TaskOptionRecord *options, const Metadata *futureResultType, void *closureEntry, HeapObject *closureContext) -> AsyncTaskAndContext` | `swiftcc` (`RuntimeFunctions.def:2497-2513`) | Spawns a new `Task` (`Task { ... }`, `Task.detached { ... }`, structured-concurrency child tasks). `closureEntry`/`closureContext` are the async-function-pointer/context pair for the task body. `flags` is a `TaskCreateFlags` bitset: bit 0-7 priority, bit 8 `isChildTask`, bit 9 `isInlineTask`, bit 10 `copyTaskLocals`, bit 11 `inheritContext`, bit 12 `enqueueJob`, bit 14 `isDiscardingTask` (`TaskGroup`/discarding task group), bit 15 `isTaskFunctionConsumed` — `include/swift/ABI/MetadataValues.h:2782-2805`. |
| `swift_task_alloc` / `swift_task_dealloc` / `swift_task_dealloc_through` | `(size_t) -> void*` / `(void*) -> void` | `swiftcc` (`RuntimeFunctions.def:2437-2465`) | Per-task bump-allocator used for async child contexts (§1.3) and, for the classic `Async` `CoroAllocatorKind`, for coroutine buffers too. **Not `malloc`.** Seeing this symbol is strong, near-unambiguous evidence of async-context or async-coroutine-frame allocation. |
| `swift_task_future_wait` / `swift_task_future_wait_throwing` | `(OpaqueValue*, AsyncContext*, AsyncTask*, TaskContinuationFunction*, AsyncContext*) async -> Success` | `swiftasync` (`Concurrency.h:174-202`) | Await a **`Task`'s `.value`/`.result`** (or a child task's future). **Not** used for a plain `await someAsyncFunc()` call within a function body — that's a direct async call through the callee's own `AsyncFunctionPointer` (§4.1), no runtime call needed. Seeing `swift_task_future_wait[_throwing]` specifically marks `Task<Success,Failure>.value` / `.result`. |
| `swift_taskGroup_wait_next_throwing` / `swift_taskGroup_waitAll` | similar shape, `TaskGroup*` instead of `AsyncTask*` | `swiftasync` (`Concurrency.h:204-221`, `:343-363`) | `TaskGroup.next()` / `withTaskGroup`'s implicit `waitForAll`. |
| `swift_continuation_init` | `(ContinuationAsyncContext*, AsyncContinuationFlags) -> AsyncTask*` | `swiftcc` (`RuntimeFunctions.def:2553-2562`) | Entry to `withCheckedContinuation`/`withUnsafeContinuation` family: initializes the continuation's context and (for the "preawaited" flag) immediately suspends the current task (`Task.cpp:1610-1653`). |
| `swift_continuation_await` | `(ContinuationAsyncContext*)` | `swiftasync` (`RuntimeFunctions.def:2564-2572`) | Suspends until the continuation is resumed; if it was already resumed by the time this runs, tail-calls the resume funclet immediately (`Task.cpp:1655-1759`). |
| `swift_continuation_resume` / `swift_continuation_throwingResume` / `swift_continuation_throwingResumeWithError` | `(AsyncTask*)` / `(AsyncTask*, SwiftError*)` | `swiftcc` (`RuntimeFunctions.def:2574-2603`) | The `continuation.resume(...)`/`resume(throwing:)` call a callback-based API makes to hand a result back into Swift concurrency. This is the symbol to look for at the boundary of a bridged completion-handler API. |
| `swift_asyncLet_begin` | `(AsyncLet*, TaskOptionRecord*, const Metadata*, void *closureEntry, HeapObject *closureContext, void *resultBuffer)` | `swiftcc` (`RuntimeFunctions.def:2687-2708`) | `async let x = ...`: starts the child task. The `AsyncLet` struct is stack-allocated by the parent (`NumWords_AsyncLet` words, `emitBuiltinStartAsyncLet`, `GenConcurrency.cpp:229-244`) — recognizable by a fixed-size stack `alloca` immediately preceding this call. |
| `swift_asyncLet_finish` | `(AsyncContext *current, AsyncLet*, void *resultBuffer, TaskContinuationFunction*, AsyncContext *temp)` | `swiftasync` (`RuntimeFunctions.def:2710-2730`) | Where control resumes after `async let`'s implicit final await (end of scope, or first explicit read that must wait). |

`swift_task_switch`'s doc comment in `Actor.cpp:1881-1909` is worth quoting directly for
anyone tracing actor-hop control flow by hand: it explains that a thread "following an
actor" and a thread "following a task" are the same mechanism viewed from two directions,
and that after a `swift_task_switch` call returns/tail-calls, the *current* actor may not
be the one the calling code started with — i.e. don't assume symmetry across this call.

---

## 3. Coroutine accessors: `read`/`modify` and `yielding borrow`/`yielding mutate`

### 3.1 Three coroutine kinds, one enum

```cpp
enum class SILCoroutineKind : uint8_t {
  None,
  /// yield-once coroutine (used by legacy `_read` and `_modify` accessors).
  YieldOnce,
  /// yield-once coroutine (used by `yielding borrow` and `yielding mutate`
  /// accessors). Unlike YieldOnce, the second half of the coroutine is
  /// _always_ run, even if an error is thrown within the access scope.
  /// It also uses a more efficient callee-allocated ABI.
  YieldOnce2,
  /// yield-many coroutine (used by e.g. generators).
  YieldMany,
};
```
— `include/swift/AST/Types.h:5294-5315`, comments verbatim. `YieldOnce2` backs
`yielding borrow`/`yielding mutate` (mangled `y`/`x`, `AccessorKinds.def:162-186`,
gated behind `Feature::CoroutineAccessors`), a source-level feature layered on top of
the same `_read`/`_modify` semantics but with a materially different ABI (below) and a
correctness improvement: the classic `YieldOnce` ABI can skip the accessor's
post-yield cleanup code if an error is thrown out of the caller's access scope;
`YieldOnce2` guarantees it always runs.

### 3.2 Buffer sizes and allocation

`YieldOnce` and `YieldMany` use a **fixed-size caller-allocated buffer**, not a
dynamically-sized heap frame:

```
NumWords_YieldOnceBuffer = 4,   // include/swift/ABI/MetadataValues.h:52
NumWords_YieldManyBuffer = 8,   // include/swift/ABI/MetadataValues.h:55
```

i.e. 32 bytes / 64 bytes on a 64-bit target
(`getYieldOnceCoroutineBufferSize`/`getYieldManyCoroutineBufferSize`, `GenCall.cpp:72-84`).
This buffer is what the ramp function's first argument points to (confirmed empirically,
§8.2). `YieldOnce2` instead uses a dynamically-sized frame through a pluggable
`CoroAllocator` (`include/swift/ABI/Coro.h:26-89`) with four kinds:

```cpp
enum class CoroAllocatorKind : uint8_t {
  Stack = 0,   // stacksave/stackrestore
  Async = 1,   // swift_task_alloc / swift_task_dealloc_through
  Malloc = 2,  // malloc/free
  TypedMalloc = 3, // swift_coroFrameAlloc / swift_coroFrameAllocTyped+DeallocTyped
};
```
— `Coro.h:26-35`. Classic `YieldOnce`/`YieldMany` allocation is simpler and
hard-coded per kind: `YieldOnce` uses `malloc`, or (with
`-enable-type-layout-for-coro-frame`/malloc-type-tagging enabled)
`swift_coroFrameAllocTyped`/`swift_coroFrameDeallocTyped`
(`emitYieldOnceCoroutineEntry`, `GenCall.cpp:5188-5217`); `YieldMany` always uses plain
`malloc`/`free` (`emitYieldManyCoroutineEntry`, `GenCall.cpp:5219-5230`).
`swift_coroFrameAlloc`/`swift_coroFrameAllocTyped` take `(size_t, int64_t typeId)` and
are declared `RuntimeFunctions.def:2197-2217`, implemented `stdlib/public/runtime/Heap.cpp:136-139`
(this one file genuinely is under `stdlib/public/runtime/`, unlike the task/actor
runtime — see §0's correction). A `swift_task_dealloc_through` call
(`RuntimeFunctions.def:2457-2465`, gated on `CoroutineAccessorsAvailability`) inside a
coroutine's cleanup path is specific to the `YieldOnce2` `Async` allocator kind
(`GenCoro.cpp:33-140` builds the fallback/weak-symbol dispatch for it) — seeing it is a
strong signal of a `yielding borrow`/`yielding mutate` accessor, not a legacy
`_read`/`_modify` one.

### 3.3 The yield vs. return distinction, at the machine level

This is the answer to "how does a decompiler tell a yield from a return": **a coroutine
ramp function's `ret` instruction is not the accessor returning a value — the value in
x0 at that `ret` is a code pointer to the continuation funclet.** This is structurally
different from — and easy to conflate with — an ordinary function return, and it is also
different from how an *async* function ends (§1.2: async never executes a plain `ret` at
a suspension point at all; it tail-branches). Three distinct shapes, confirmed
empirically (§8.2, §8.1):

- **Ordinary function / getter/setter**: ends in `ret`, x0 (or v0) holds the actual
  result. (`calling-convention.md`'s existing return-value handling.)
- **`YieldOnce`/`YieldMany` coroutine ramp** (`_read`/`_modify`, mangled `vr`/`vM`):
  ends in `ret`, but x0 holds the **address of the continuation function**
  (`SignatureExpansion::expandCoroutineResult`, `GenCall.cpp:818-889`, already documented
  in `calling-convention.md:166-192, 379-383` — continuation pointer first, then any
  yielded scalar components). The continuation function itself, when the yield carries
  no further work (the common case for a trivial stored-property accessor), is a
  one-instruction `ret` — LLVM may even fold identical continuations for `_read` and
  `_modify` of the same property into one shared address (observed in §8.2's `-O` build).
- **Async suspension point**: never a `ret`; a tail `br`/musttail call (§1.2, §1.3, §8.1).

A decompiler that sees a `ret` and unconditionally renders "return \<x0\>" will render a
**function pointer as if it were a returned value** for every `_read`/`_modify` accessor
— exactly the class of bug this project's `CLAUDE.md` calls out as unacceptable
("decline rather than guess"). The mangled accessor suffix (`vr`/`vM`/`vy`/`vx`,
`mangling-grammar.md:137-186`) or the `SILCoroutineKind` recovered from a demangled
`COROUTINE-KIND` marker (`'A'`=YieldOnce, `'I'`=YieldOnce2, `'G'`=YieldMany,
`docs/ABI/Mangling.rst:912-914`) is the only reliable gate for choosing which rendering
path to use — register shape alone (a `ret` with a value in x0) cannot distinguish a
coroutine ramp from an ordinary function.

---

## 4. Naming and mangling: relating funclets back to their origin

### 4.1 The lookup tables: `AsyncFunctionPointer` / `CoroFunctionPointer`

Every async function and every `YieldOnce2` coroutine has a small data-only companion
global — a fixed 8-byte (async) or ~16-byte (coro) struct, **not code**:

```cpp
AsyncFunctionPointerTy = createStructType(*this, "swift.async_func_pointer",
                                          {RelativeAddressTy, Int32Ty}, true);
// { i32 relative-offset-to-entry-function, i32 expected-context-size }
```
— `IRGenModule.cpp:646-647`; consumed by `getAsyncFunctionAndSize`, `GenCall.cpp:2649-2725`
(field 0 = compact/relative function pointer to the entry funclet, field 1 = the async
context size to allocate for a call to it — this is the size a caller's
`swift_task_alloc` call at the call site uses, §1.3).

```cpp
CoroFunctionPointerTy = createStructType(*this, "swift.coro_func_pointer",
                                         {RelativeAddressTy, Int32Ty, Int64Ty}, true);
// { i32 relative-offset-to-ramp, i32 frame-size-in-words, i64 malloc-type-id }
```
— `IRGenModule.cpp:763-765`; consumed by `getCoroFunctionValues`, `GenCall.cpp:2727-2796`.
Both are marked in the demangler as `AsyncFunctionPointer` ("async function pointer to
...") and `CoroFunctionPointer` ("coro function pointer to ...")
(`NodePrinter.cpp:3468-3470, 3565-3567`). **These records are the authoritative,
independent-of-symbol-table way to find a callee's entry point and its required context
size from a call site that only has the `AsyncFunctionPointer`/`CoroFunctionPointer`
global's address** — useful when the entry function itself lacks a usable symbol.

### 4.2 Symbol-name suffixes

From `docs/ABI/Mangling.rst`:

```
global ::= global 'Tu'                 // async function pointer of a function      (:254)
global ::= global 'Twc'                // coro function pointer of a function       (:258)
global ::= mangled-name 'TQ' index     // Async await continuation partial function (:185)
global ::= mangled-name 'TY' index     // Async suspend continuation partial function (:186)
```

Demangled forms (`lib/Demangling/NodePrinter.cpp:3468-3489, 3565-3567`):

| Suffix | `Node::Kind` | Printed as | What it is |
|---|---|---|---|
| `Tu` | `AsyncFunctionPointer` | "async function pointer to \<name\>" | The `swift.async_func_pointer` data global for `<name>` (§4.1). **Data, not code.** |
| `Twc` | `CoroFunctionPointer` | "coro function pointer to \<name\>" | The `swift.coro_func_pointer` data global for `<name>` (`YieldOnce2` only). |
| `TQ<n>` | `AsyncAwaitResumePartialFunction` | "(n) await resume partial function for \<name\>" | A resume funclet re-entered *with a value* — after awaiting the result of a call. |
| `TY<n>` | `AsyncSuspendResumePartialFunction` | "(n) suspend resume partial function for \<name\>" | A resume funclet re-entered after a *bare* suspension (no value carried back), e.g. `hop_to_executor`/an actor switch. |

**Correction to the task's premise**: `Ta` is not the async-funclet mangling. Lowercase
`Ta` is "ObjC partial application forwarder" as a suffix (`Mangling.rst:184`) and,
in the unrelated `specialization` grammar, "Non-async specialization" — the suffix a
generic specialization pass appends when it strips the `async` effect off a
specialized clone (`Mangling.rst:1355, 1396`, `SPEC-INFO ::= ... ASYNC-REMOVED? ...`).
Neither sense names a suspend/resume funclet. The real funclet-suffix family is
`Tu`/`Twc`/`TQ<n>`/`TY<n>` above.

**No producer for `TQ`/`TY` in this checkout.** `AsyncAwaitResumePartialFunction` and
`AsyncSuspendResumePartialFunction` appear only in the demangler/remangler/printer
(`Demangler.cpp:150-152, 3054-3055`, `NodePrinter.cpp`, `Remangler.cpp:2769-2777`,
`OldRemangler.cpp:791-800`) — never constructed by `ASTMangler`, `IRGenMangler`, or any
SIL/IRGen pass in this repo. The names are produced by LLVM's `CoroSplit`
transform, using the original mangled name as a base and appending the funclet suffix —
i.e. this is one of the very few places the LLVM fork (not this checkout) directly
emits Swift-ABI-shaped symbol names. It's directly confirmed by real compiler output in
this repo's own tests, e.g. `test/DebugInfo/move_function_dbginfo_async.swift:55`:

```
define internal swifttailcc void @"$s...13letSimpleTestyyxnYalFTQ0_"(ptr swiftasync %0)
```

and by a **crash backtrace test symbolicating a real suspend funclet**,
`test/Backtracing/JSONAsync.swift:92`: `"symbol": "{{_?}}$s9JSONAsync5levelyySiYaFTY0_"`
— i.e. `TY0_` funclets are exactly what a real crash report's stack trace contains, so a
decompiler that fails to recognize this suffix will fail to relate a crashing frame back
to its source function.

Classic coroutine (`YieldOnce`/`YieldMany`) continuations do **not** use this Swift-level
suffix scheme at all — see §4.3.

### 4.3 Classic coroutine continuations: LLVM-named, not Swift-mangled

`YieldOnce`/`YieldMany` ramp functions keep the accessor's own mangled name (`vr`/`vM`)
unchanged — no funclet suffix. Their **continuation** function (the code that resumes
after the caller is done with the yielded value) is named by LLVM's `retcon` coroutine
splitting with a plain `.resume.0` suffix, confirmed empirically for both `_read` and
`_modify` (§8.2):

```
$s...6HolderV5valueSivr            <- ramp (keeps the 'vr' mangled name)
$s...6HolderV5valueSivr.resume.0   <- continuation, LLVM-appended suffix
$s...6HolderV5valueSivM            <- ramp
$s...6HolderV5valueSivM.resume.0   <- continuation
```
The `'TC'` production in the mangling grammar (`global ::= type 'TC' // continuation
prototype (not actually used for real symbols)`, `Mangling.rst:262`) is a red herring
for this purpose: it names a **ptrauth type-discriminator placeholder** global (observed
as e.g. `$s...HolderVIetMg_TC` holding a signed function-pointer *prototype*, in
`test/IRGen/ptrauth_generalized_accessors.swift:12-13, 22-23`), used only to give the
real continuation function's signature a stable pointer-authentication discriminator —
it is not the continuation function's own name and the doc comment says so directly.

### 4.4 `__swift_as_entry`/`__swift_as_ret`/`__swift_as_cont`: a section-based oracle

This is not covered by the mangling grammar and is worth its own subsection: Swift's
IRGen tags every async entry function with an LLVM function attribute, and — per
empirical observation (§8.3) — LLVM's async funclet splitting tags every `TQ`-family
funclet `async_ret` and every `TY`-family funclet `async_continuation`. A dedicated,
Mach-O-specific pass then collects each group into a coalesced section as an array of
**self-relative i32 offsets** (offset from each array slot's own address to the target
function):

```cpp
// lib/LLVMPasses/LLVMEmitAsyncEntryReturnMetadata.cpp:15-96
addSection("__TEXT,__swift_as_entry, coalesced, no_dead_strip",
           "__swift_async_entry_functlets", asyncEntries);
addSection("__TEXT,__swift_as_ret, coalesced, no_dead_strip",
           "__swift_async_ret_functlets", asyncReturns);
addSection("__TEXT,__swift_as_cont, coalesced, no_dead_strip",
           "__swift_async_cont_functlets", asyncContinuations);
```

The Swift-side trigger for tagging the *entry* function is explicit and Mach-O-gated:

```cpp
if (IGM.getOptions().EmitAsyncFramePushPopMetadata &&
    IGM.TargetInfo.OutputObjectFormat == llvm::Triple::MachO) {
  CurFn->addFnAttr("async_entry");
  CurFn->addFnAttr(llvm::Attribute::NoInline);
}
```
— `lib/IRGen/IRGenSIL.cpp:2686-2690`, right after `emitAsyncFunctionPointer` is called
for that function (`IRGenSIL.cpp:2680-2684`). The `async_ret`/`async_continuation`
attribute assignment on the *funclets themselves* is not found as a producer anywhere in
this checkout (consistent with §4.2: funclet creation is LLVM's `CoroSplit`, not
Swift's) — but it is empirically, exactly reproducible: on a 3-async-function fixture
with 4 `TQ`-suffixed funclets and 3 `TY`-suffixed funclets total, `__swift_as_ret` held
exactly the 4 `TQ` addresses and `__swift_as_cont` held exactly the 3 `TY` addresses,
byte-for-byte (§8.3). Treat the `TQ`↔`async_ret` and `TY`↔`async_continuation`
correspondence as a measured fact about this compiler version, not a guaranteed-stable
ABI contract, and re-verify it if swiftdc comes to depend on it (§7.1, §8.3).

**Why this matters for swiftdc**: these three sections are an **oracle independent of
the symbol table** for "which addresses in this binary are async entry points / await-
resume funclets / suspend-resume funclets" — exactly the kind of independent binary
evidence this project's `CLAUDE.md` requires before trusting an empty or heuristic
result. On a stripped binary where local symbols (and therefore `TQ`/`TY`-suffixed
names) are gone, `__swift_as_entry`/`__swift_as_ret`/`__swift_as_cont` still let swiftdc
(a) enumerate every async function's true entry address independent of
`LC_FUNCTION_STARTS` noise, and (b) classify an anonymous `sub_XXXXXX` as "async
await-resume funclet" or "async suspend-resume funclet" even with no name at all — which
directly bears on this project's `sub_`-naming gap (see `git log` for the
`sub_-naming-measurement` commit; this section-based oracle is a candidate source of
ground truth for that problem, distinct from the local-symbol-table question that
measurement was about).

---

## 5. Recoverable vs. must-decline

### 5.1 Recoverable with source-grade confidence

- **"Is this function `async`?"** — from the mangling: `async ::= 'Ya'` at the
  surface function-type grammar (`Mangling.rst:782`) or the separate SIL-level
  `ASYNC ::= 'H'` marker in `FUNC-ATTRIBUTES`/`impl-function-type` mangling
  (`Mangling.rst:918`) — or from the presence of a `Tu`-suffixed `AsyncFunctionPointer`
  global whose relative offset points at it. Independent of optimization level.
- **"Is this a `read`/`modify`/`yielding borrow`/`yielding mutate` coroutine, and which
  buffer/allocator convention does it use?"** — from the accessor mangling code
  (`r`/`M`/`y`/`x`, `mangling-grammar.md:153-159`) directly, no disassembly needed.
- **"What is this callee's async entry address and required context size?"** — from its
  `AsyncFunctionPointer`/`CoroFunctionPointer` record (§4.1), a fixed-layout data
  structure, not a heuristic.
- **"Is this address an async entry / await-resume / suspend-resume funclet?"** — from
  `__swift_as_entry`/`__swift_as_ret`/`__swift_as_cont` (§4.4) when
  `EmitAsyncFramePushPopMetadata` was on for the build (verify per-binary — it is not
  guaranteed present, see §7.1).
- **"Which original function does a `TQ<n>`/`TY<n>` funclet belong to?"** — strip the
  suffix and demangle the prefix (§4.2); for a classic coroutine's `.resume.0`, strip
  that literal suffix.
- **A coroutine ramp's `ret`-with-x0 is a continuation address, not a value** (§3.3) —
  this is a hard ABI fact tied to `SILCoroutineKind`, safe to act on unconditionally once
  the accessor mangling is recognized.

### 5.2 Must decline (or flag "unrecovered", never fabricate)

- **Reconstructing suspend/resume control flow as a single readable function body.**
  A source-level `async` function with N awaits is N+1 separate machine functions with
  no shared frame; recovering the original straight-line-looking Swift source (matching
  what the programmer wrote) requires re-threading N+1 disjoint functions' worth of
  spilled locals (kept alive across suspensions in the heap-allocated child context, not
  on any conventional stack) back into one control-flow graph. This is a strictly harder
  problem than ordinary CFG structuring and is out of scope for a per-funclet
  disassembly pass; at most, swiftdc should render each funclet as its own unit and
  **label** the suspend/resume edges (via the `TQ`/`TY` relationship, §4.2) rather than
  attempting to merge them into one reconstructed function.
- **The exact register/stack location of an untyped `async throws` error at a specific
  call site.** §1.1 establishes *that* the error rides on the resume function's
  parameter list rather than a register or an indirect argument
  (`GenCall.cpp:2372-2373, 2390-2399`), but this pass did not trace
  `expandAsyncAwaitType`'s parameter-to-register assignment through to a concrete
  x0-x7/stack slot the way `calling-convention.md` did for the synchronous case. Treat
  "does this async function throw, and where does the error land" as **unresolved**
  pending a dedicated fixture-driven pass (see §7.2) — do not guess a register.
- **Whether a given `swift_task_switch` call actually changed executors at runtime.**
  It is emitted unconditionally at every actor-isolation boundary but is a no-op fast
  path when the executor is already compatible (`Actor.cpp:2593-2623`). A decompiler can
  say "this is an isolation-boundary check", not "this hops threads."
  Same caution applies to `swift_continuation_await`: it may resume immediately
  in-line if the continuation was already resumed (`Task.cpp:1673-1679`).
- **The precise rule for `async_ret` vs. `async_continuation` funclet classification**
  (§4.4) beyond the empirically-observed `TQ`/`TY` correspondence — the assigning code is
  in LLVM, not this checkout, and was not independently confirmed from source.
- **Whether `EmitAsyncFramePushPopMetadata`/the `__swift_as_*` sections are present in
  an arbitrary target binary.** It is a compiler option
  (`IRGenSIL.cpp:2686`), not an ABI guarantee — always check for the section before
  depending on it; degrade gracefully (fall back to symbol-table/mangling recognition)
  when it's absent, per this project's empty-result rule.

---

## 6. Cross-references and corrections to sibling research docs

- `calling-convention.md:401-423` flags as **unresolved** whether swifterror (x21) is
  used at an async entry point, and recommends detecting async via "a `Yields`/`TY`-style
  suffix — verify the exact grammar before coding." §4.2 above verifies that grammar
  (`Tu`/`Twc`/`TQ<n>`/`TY<n>`, `Mangling.rst:183-186, 254-258`) and §1.1/§5.2 confirm from
  `expandAsyncEntryType` (`GenCall.cpp:2282-2380`) that async entry points never add a
  `swifterror` parameter — indirect results (including typed-error results) are ordinary
  indirect pointer arguments instead, and untyped-error delivery goes through the resume
  function's own parameter list, not a register. This resolves the "is x21 used" half of
  that flagged item; the "what register/slot exactly" half remains open (§5.2). Worth
  folding into `calling-convention.md` in a follow-up pass rather than duplicating it
  there.
- `mangling-grammar.md:137-186` already covers the accessor-suffix mangling (`r`/`M`/`x`/`y`/`b`/`z`)
  thoroughly; this document does not repeat it and instead covers what those accessors
  *compile to* (buffer/allocator shape, ramp/continuation split, §3) and the separate
  async-funclet suffix family (`Tu`/`Twc`/`TQ`/`TY`, §4.2) that document only mentions in
  passing (`mangling-grammar.md:69-70, 476-477`).

---

## 7. Ranked recommendations for swiftdc

1. **Recognize coroutine-ramp `ret` semantics before rendering any `_read`/`_modify`/
   `yielding borrow`/`yielding mutate` accessor's exit.** This is the single highest-value
   fix: today a naive "return x0" renderer would print a raw code address as if it were
   the accessor's result. Gate it on the accessor mangling suffix (`vr`/`vM`/`vy`/`vx`),
   which swiftdc's `MetadataSymbolizer.swift:126-127` / `SelfTypeIndex.swift:101-102`
   already decode for `.readCoroutine`/`.modifyCoroutine` — this is a small, targeted
   extension of an existing recognizer, not new infrastructure. Directly serves the
   project's soundness priority (rule 1 in `CLAUDE.md`'s priority ordering).
2. **Add `Tu`/`Twc`/`TQ<n>`/`TY<n>` suffix recognition to whatever component currently
   classifies symbols by mangling** (the same layer `mangling-grammar.md §5.1` recommends
   dispatching on `Node.Kind`, not printed English). Concretely: strip a trailing
   `TQ<digits>_`/`TY<digits>_` before looking up a function's "real" name for grouping/
   call-graph purposes, and demangle-print the parent's name from the child node
   (§4.2) rather than fabricating a name for what would otherwise render as an
   unresolved `sub_`. This directly extends the `sub_`-naming-gap work referenced in
   this repo's own git history.
3. **Probe every target binary for `__TEXT,__swift_as_entry`/`__swift_as_ret`/
   `__swift_as_cont` (§4.4) and use them as a cross-check oracle** for async-function
   enumeration, parallel to how `LC_FUNCTION_STARTS`/the symbol table/the export trie are
   already treated as independent oracles per this project's empty-result rule. A
   mismatch between "functions found via symbol table" and "functions found via
   `__swift_as_entry`" is exactly the kind of surprising-result signal `CLAUDE.md` says
   to treat as a hypothesis to test, not a result to report. Low implementation cost
   (three flat integer arrays, self-relative offsets, format fully specified in §4.4) for
   real production-readiness payoff on stripped binaries.
4. **When rendering an async function, never synthesize a single merged function body
   across its `TQ`/`TY` funclets.** Render each funclet as its own unit (labeled with its
   relationship to the parent, §4.2), or decline to merge with an explicit note, per
   §5.2. Silently gluing funclets together on a plausible-looking heuristic is exactly
   the "guess instead of decline" failure mode `CLAUDE.md` prohibits.
5. **Treat `swift_task_alloc`/`swift_task_dealloc[_through]` calls as first-class
   evidence of async-context or coroutine-frame lifetime**, distinct from generic heap
   traffic — §2's table and §3.2's allocator-kind breakdown give a decompiler enough to
   label *which* allocation regime (async task allocator vs. malloc vs.
   `swift_coroFrameAlloc`) a given call site belongs to, which in turn indicates
   `YieldOnce` vs. `YieldOnce2` vs. plain async without re-deriving it from the mangling.
6. **File the open question in §5.2/§6 (untyped `async throws` error register/slot) as
   its own follow-up** rather than guessing a register now — build a small
   `async throws` fixture (extending §8's fixture is enough) and trace
   `expandAsyncAwaitType`'s parameter assignment to a concrete slot before implementing
   error-path recovery for async functions.

---

## 8. Verification notes — reproducible commands

All of §1.2, §1.3, §3.3, §4.3, and §4.4's empirical claims were produced against a
throwaway fixture compiled with the toolchain already on this machine
(`xcrun swiftc`, Swift 6.4 / `swiftlang-6.4.0.30.4`, target `arm64-apple-macosx27.0.0` —
**newer than swiftdc's usual Swift-6.3 fixtures**; re-verify against the project's
pinned toolchain if these details ever matter at the byte level). Fixture:

```swift
// fixture.swift
struct Holder {
    var _value: Int = 0
    var value: Int {
        _read { yield _value }
        _modify { yield &_value }
    }
}
func fetchRemote(_ n: Int) async -> Int {
    if n < 2 { return n }
    let a = await fetchRemote(n - 1)
    let b = await fetchRemote(n - 2)
    return a + b
}
@MainActor
func mainActorWork() async -> Int {
    var h = Holder()
    h.value = 42
    let r = await fetchRemote(h.value)
    return r
}
public func publicEntry() async -> Int {
    return await mainActorWork()
}
```

### 8.1 Async split-funclet shape and register conventions

```
xcrun swiftc -parse-as-library -emit-library -o libfixture.dylib fixture.swift -O
nm libfixture.dylib | grep fetchRemote
otool -tv libfixture.dylib   # disassemble the entry funclet
```
Produced (symbol table): `..fetchRemoteyS2iYaF` (entry), `...TQ0_`, `...TQ1_` (two
await-resume funclets, matching the two `await` expressions), `...TY2_` (one
suspend-resume funclet), and `...Tu` typed as a **data** symbol (`s`, not `t`/`T`) — the
`AsyncFunctionPointer` record. Disassembly of the entry funclet: `orr x29, x29,
#0x1000000000000000` (the async-frame tag bit on the frame pointer, tied to
`SwiftAsyncFramePointerKind`, `include/swift/AST/IRGenOptions.h:88-92`,
`lib/IRGen/IRGenModule.cpp:2555-2579`), a `bl _swift_task_alloc` for the child context,
stores to `[x22...]`/a fresh context (`Parent`/`ResumeParent` header, §1.1), and a
terminal `br x1` — **never a `ret`** — confirming §1.2/§1.3.

### 8.2 Coroutine ramp/continuation split

```
xcrun swiftc -parse-as-library -emit-library -o libfixture_onone.dylib fixture.swift -Onone
nm libfixture_onone.dylib | grep HolderV5value
otool -tv libfixture_onone.dylib   # disassemble Sivr / Sivr.resume.0 / SivM / SivM.resume.0
```
Produced exactly `..._Sivr`, `..._Sivr.resume.0`, `..._SivM`, `..._SivM.resume.0` — the
plain LLVM `.resume.0` suffix (§4.3), no `TQ`/`TY`. Both ramps end in `ret` with x0 set
to the continuation's address (§3.3); both continuations are themselves a bare `ret`
(this trivial accessor yields nothing beyond what the caller can already compute from
`self`). At `-O`, the two continuations were folded to the same address (identical-code
folding) — a reminder that address identity is not proof of "the same accessor,"
mangled-name identity is.

### 8.3 The `__swift_as_*` section oracle

```
otool -l libfixture.dylib | grep -A5 swift_as
otool -s __TEXT __swift_as_entry libfixture.dylib
otool -s __TEXT __swift_as_ret   libfixture.dylib
otool -s __TEXT __swift_as_cont  libfixture.dylib
```
Three sections present: `__TEXT,__swift_as_entry` (3 x i32), `__TEXT,__swift_as_ret`
(4 x i32), `__TEXT,__swift_as_cont` (3 x i32). Manually decoding each self-relative
offset (`slot_address + sign_extend(i32) = target_address`) and cross-checking against
the `nm` symbol table (§8.1) confirmed byte-for-byte: `__swift_as_entry`'s 3 entries are
exactly the 3 async functions' base symbols; `__swift_as_ret`'s 4 entries are exactly
the 4 `TQ`-suffixed funclets; `__swift_as_cont`'s 3 entries are exactly the 3
`TY`-suffixed funclets. This is the measurement behind §4.4's `TQ`↔`async_ret` /
`TY`↔`async_continuation` correspondence claim — re-run this on a larger, more
realistic fixture (multiple `throws`, task groups, `async let`) before hard-coding the
correspondence into swiftdc, since it was only checked against one small fixture here.

### 8.4 What was *not* independently re-verified in this pass

- The exact register(s)/slot for an untyped `async throws` error (§5.2, §6) — flagged
  open, not measured.
- LLVM's `CoroSplit` source itself (§0) — all funclet-splitting claims here are either
  cited to Swift's own emission of the intrinsic markers/attributes that *drive* that
  pass, or measured against its *output*, never read from its implementation.
- Whether the `TQ`/`TY` index numbering (`0`, `1`, `2`, ...) follows source order,
  reverse order, or some other assignment rule — observed inconsistent-looking orderings
  between the `-O` and `-Onone` builds of the same source (§8.1 vs. the `-Onone` build
  used for §8.2 also produced `mainActorWork`'s funclets as `TY0_`/`TQ1_`/`TY2_`, index 0
  going to a suspend-resume rather than an await-resume funclet) strongly suggest the
  index is assignment-order-in-the-split, not something a decompiler should try to
  interpret positionally. Treat funclet indices as opaque disambiguators, not as
  ordered/meaningful sequence numbers.

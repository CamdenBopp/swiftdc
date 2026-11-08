# What `-O` erases and transforms: ground truth for swiftdc's optimized-binary path

> Research artifact. Not production code. Every claim below cites a `file:line` in the
> canonical `swiftlang/swift` checkout at `/Users/camden/swift` (read-only; not modified by
> this pass), or a `file:line` in swiftdc itself (also read-only in this pass — the only
> file this pass writes is this one). Per the project's authority hierarchy in `CLAUDE.md`,
> this document is rank 4 (research documentation): verify against current source before
> acting on a claim, and fix this file in the same change if it drifts.

## 0. Scope and pinned revisions

| Repo | Revision | Scope studied |
|---|---|---|
| `swiftlang/swift` (canonical, read-only) | `1b7bd8eaf460396047c2644d1d69afb4a404b13d` (`main`, 2026-09-07) | `lib/SILOptimizer/{Utils,FunctionSignatureTransforms,IPO,Transforms,ARC,Mandatory,PassManager}`, `lib/IRGen/{Outlining,GenDecl,GenFunc}.{cpp,h}`, `lib/SILGen/SILGenThunk.cpp`, `lib/Demangling/{Remangler,OldRemangler,NodePrinter,Demangler}.cpp`, `docs/ABI/Mangling.rst`, `SwiftCompilerSources/Sources/Optimizer/FunctionPasses/ClosureSpecialization.swift` |
| swiftdc (this repo) | `a711f4e729fb814ea33b32eb66bd42dacc464305` (`master`) | `Sources/SwiftDecompilerCore/{Disassembler,MetadataSymbolizer,CallGraph,Structurer}.swift`, `docs/PRODUCTION-READINESS.md` |

This document complements, not duplicates,
`docs/research/swift-source/mangling-grammar.md` (grammar/printing of mangled names in
general). That doc covers what a mangling *means*; this one covers what *compiler pass*
produced it, what it replaced, and — critically — what got thrown away in the process, so
swiftdc knows where "decline rather than guess" applies on an `-O` binary specifically.

Real evidence used below comes from swiftdc's own fixtures,
`Fixtures/Sample/sample.release` (`-O`, unstripped) and
`Fixtures/Sample/libReconstruction.opt{,.stripped}.dylib`, built by
`Fixtures/Sample/build.sh:14-16,25-29`. Every `nm`/`otool` command quoted is re-runnable
against those files.

---

## 1. What `-O` changes vs `-Onone`, transformation by transformation

### 1.1 Generic specialization (`Tg5`, `Ts`)

- Grammar: `specialization ::= type '_' type* 'T' dropped-arg* 'g' SPEC-INFO` (re-abstracted
  specialization) and `'Ts' SPEC-INFO` (re-abstracted *prespecialization*) —
  `docs/ABI/Mangling.rst:1349,1353`. `SPEC-INFO` ends in a `PASSID` digit; `'5'` is
  `GenericSpecializer` — `docs/ABI/Mangling.rst:1388`. That is the literal origin of the
  `Tg5` suffix the task names.
- Producer: `swift::trySpecializeApplyOfGeneric` in
  `lib/SILOptimizer/Utils/Generics.cpp:3499-3552`. It clones the generic callee's SIL body
  wholesale with concrete types substituted in (`GenericCloner`,
  `lib/SILOptimizer/Utils/GenericCloner.cpp`), so **the specialized body is a full copy of
  the generic logic**, not a stub — a decompiler reading `Tg5` code is reading real,
  type-concrete logic, just under an ugly name.
- Linkage: "Specializations have shared linkage, which means they do not have an external
  entry point" — comment at `lib/SILOptimizer/Utils/Generics.cpp:3514-3517`, and SIL
  `Shared` linkage lowers to `linkonce_odr` at the LLVM level. This is the load-bearing fact
  for §2 below: an ordinary app-level `Tg5` specialization is not a unique, pinned symbol —
  it's an ODR-merged, linker-foldable one.
- Confirmed live in a real binary: `Fixtures/Sample/sample.release` contains
  `_$ss12_ArrayBufferV20_consumeAndCreateNew...Si_Tg5` (`nm -j sample.release | grep Tg5`).
  The standard library itself ships hundreds of pre-baked `_Tg5` instances for common
  element types — see the literal symbol list in
  `lib/SILOptimizer/Utils/OnonePrespecializations.def:3-6` (e.g.
  `$sS2ayxGycfCSi_Tg5` = `Array<Int>.init()`).
- **Not `-O`-only, half of it.** `getOnonePassPipeline` (`-Onone`) also runs
  `P.addOnonePrespecializations()` and `P.addUsePrespecialized()` —
  `lib/SILOptimizer/PassManager/PassPipeline.cpp:1096,1126`. A generic stdlib call in a
  **debug** binary can already be redirected to a `Ts5`/`Tg5`-suffixed symbol defined in
  `libswiftCore`, not in the app binary at all. `trySpecializeApplyOfGeneric` itself
  (app-code, non-stdlib specialization) is gated by the full performance pipeline via
  `PassPipeline.cpp` — the pass that calls it is not present in
  `getOnonePassPipeline` — so *app-level* `Tg5` cloning is `-O`-only; stdlib prespecialized
  call redirection is not.
- What a decompiler sees: a call to a monomorphic-looking function whose mangled name
  encodes the concrete type arguments. What's gone: the fact that the caller's own source
  called a *generic* function — the generic signature is only recoverable by demangling the
  `Tg5` name's substitution list, never from the call site itself (it's an ordinary direct
  call after specialization, see also devirtualization in §1.7 for the analogous erasure of
  *dynamic dispatch* evidence).

### 1.2 Function signature optimization (`Tf`)

- Grammar: `specialization ::= spec-arg* 'Tf' SPEC-INFO ARG-SPEC-KIND* '_' ARG-SPEC-KIND` —
  `docs/ABI/Mangling.rst:1371`. `PASSID '4'` = `FunctionSignatureOpts` —
  `docs/ABI/Mangling.rst:1392`. Per-argument `ARG-SPEC-KIND` letters
  (`docs/ABI/Mangling.rst:1394-1406`): `n` unmodified, `c`/`E`/`C` closure-propagated
  (consumes closed-over types + the closure's own symbol as a mangled identifier), `p`
  constant-propagated (payload kind follows: `f` function symbol, `g` global symbol, `i`
  64-bit int, `d` float, `s` string, `k` key path SHA1, `S` struct-of-operands), `e`
  existential-to-generic, `d`/`g`/`x`/`i`/`s` dead/owned-to-guaranteed/exploded/box-to-value/
  box-to-stack.
- **The mechanism is a thunk swap, and it is the single most important fact for a
  decompiler to model.** Doc comment at
  `lib/SILOptimizer/FunctionSignatureTransforms/FunctionSignatureOpts.cpp:14-19`: "When a
  function signature optimization is performed, changes are made to the original function
  and after all function signature optimizations are finished, a new function is created
  and the old function is turned into a thunk." Concretely, in
  `createFunctionSignatureOptimizedFunction`
  (`lib/SILOptimizer/FunctionSignatureTransforms/FunctionSignatureOpts.cpp:558-560,585-586,596-599,626-628`):
  - A **new** `SILFunction` is created under the `Tf`-suffixed name
    (`createOptimizedSILFunctionName`, `FunctionSignatureOpts.cpp:187-223`) and
    `NewF->moveAllBlocksFromOtherFunction(F)` — the new function inherits the **entire real
    body**.
  - The **original**, plain-mangled `F` is gutted and rebuilt as a forwarding thunk:
    `F->setThunk(IsSignatureOptimizedThunk)`, `F->setInlineStrategy(HeuristicAlwaysInline)`,
    then a fresh entry block is built that reconstructs each dropped/exploded argument
    (`addThunkArgument`, `FunctionSignatureOpts.cpp:166-184`) and tail-calls `NewF`
    (`FunctionSignatureOpts.cpp:641-649`).
  - Because the thunk is `HeuristicAlwaysInline`, the *unconditional*-inline check at
    `lib/SILOptimizer/Transforms/PerformanceInliner.cpp:1046-1057`
    (`isInlineAlwaysCallSite`) inlines it at essentially every call site within the module.
    **The original mangled symbol can vanish from the binary entirely** — no separate thunk
    function, no call instruction — if it's not independently ABI-exposed. If it does
    survive (e.g. it's a public/exported entry point, or too large to inline everywhere),
    it survives as a *tiny* stub: marshal args, `bl` to `Tf...`, `ret`.
  - Confirmed live: `Fixtures/Sample/sample.release` contains
    `_$s6sample9DirectionO8rawValueACSgSi_tcfCTf4nd_n` — an FSO'd `Direction(rawValue:)`
    failable initializer (`Tf4` = pass id 4 = `FunctionSignatureOpts`, followed by `nd_n` —
    argument unmodified, dead, then `_n` on the return side).
- What a decompiler sees: either (a) the original name is simply absent and only the
  `Tf...`-suffixed function exists, with an argument list/ABI that no longer matches the
  Swift-level declaration (dropped args gone, aggregates exploded into scalars, `@owned`
  params turned `@guaranteed`), or (b) a trivial marshalling stub under the original name
  that tail-calls (a) — recognizable by: `isThunk`-style shape (a handful of instructions,
  no branches, ends in `b`/`bl`+`ret` to a `Tf`-suffixed callee), never by name alone. What's
  gone: the original argument arity/ownership convention at the `Tf` function itself — it
  is only recoverable by parsing the mangled `ARG-SPEC-KIND` string, not by reading the IR.

### 1.3 Closure specialization

- The pass has migrated to Swift itself:
  `SwiftCompilerSources/Sources/Optimizer/FunctionPasses/ClosureSpecialization.swift`
  (1574 lines). `PASSID '1'` = `ClosureSpecializer` —
  `docs/ABI/Mangling.rst:1384`. `ARG-SPEC-KIND ::= 'c'`/`'E'`/`'C'` (closure-prop,
  escaping-closure-prop, same-closure-as-arg-N) are its mangling vocabulary —
  `docs/ABI/Mangling.rst:1398-1400`.
- What it does: `getOrCreateSpecializedFunction`
  (`ClosureSpecialization.swift:250,530-558`) clones a higher-order function's callee with
  a statically-known closure argument's *body* inlined directly into the specialization,
  and the mangled name embeds the closed-over types plus the closure's own symbol name as
  an identifier component (`context.mangle(withClosureArguments:...)`,
  `ClosureSpecialization.swift:591`). `rewriteApply` (`ClosureSpecialization.swift:729-735`)
  then redirects the call site to the specialized function, passing the closure's *captures*
  directly instead of a closure context object.
- `-O`-only: `addClosureSpecializePassPipeline` and `P.addAutodiffClosureSpecialization()`
  are called only from `getPerformancePassPipeline`
  (`lib/SILOptimizer/PassManager/PassPipeline.cpp:1037,1043,1046`, inside the function that
  starts at `:982`); neither appears in `getOnonePassPipeline` (`:1079-1130`).
- What's gone: the higher-order call structure. A `map`/`filter`/completion-handler style
  call that took an indirect closure argument at `-Onone` can, at `-O`, become a direct call
  to a specialized function with the closure's body **inlined at the specialization site**
  and the original closure never separately materialized (no `partial_apply`, no closure
  context allocation) — the decompiler cannot recover "this used to take a closure
  parameter" from the specialized callee's signature alone; that fact lives only in the
  mangled closure-argument component of the `Tf1...`/`c`-tagged name.

### 1.4 Outlining (`WOy`/`WOe`/... — correcting the task's `Wy`/`We` assumption)

- **The task's `Wy`/`We` notation is the *obsolete* mangling.** `Wy` (outlined copy) and
  `We` (outlined consume) are emitted only by `OldRemangler.cpp:2657-2664`, the legacy
  mangler kept for round-tripping pre-existing names. The **current** mangler
  (`lib/Demangling/Remangler.cpp:3702-3847`) and the current grammar
  (`docs/ABI/Mangling.rst:346-362`) use a `WO`-prefixed family instead: `WOy` copy, `WOe`
  consume, `WOr`/`WOs` retain/release, `WOb`/`WOc` initializeWithTake/Copy (`WOB`/`WOC` "not
  using value witness" variants), `WOd`/`WOf` assignWithTake/Copy (`WOD`/`WOF` variants),
  `WOh` destroy (`WOH` variant), `WOi`/`WOj`/`WOg` enum tag store/project/get. Any swiftdc
  code that pattern-matches on the literal string `"Wy"`/`"We"` will miss every outlined
  helper in a binary built by the current compiler; it must match `"WO"` + one of the
  letters above (or, better, match the demangler's `Node::Kind::Outlined*` — see §5).
- Producer: `lib/IRGen/Outlining.cpp`. The doc comment at
  `lib/IRGen/Outlining.h:59-79` names the actual mechanism: `OutliningMetadataCollector`
  hoists a type's copy/destroy/retain/release/assign logic for a value that may involve
  runtime type metadata (generics, resilient types, enums with payloads) into a standalone
  helper so the call site doesn't have to re-derive metadata inline.
  `getOrCreateOutlinedDestroyFunction` (`Outlining.cpp:590-620`) and
  `getOrCreateOutlinedCopyAddrHelperFunction` (`Outlining.cpp:497-543`) key the function on
  a **mangled type name**, not on the call site — every caller that needs to copy/destroy
  the same concrete type gets routed to the *same* outlined symbol.
- Linkage: default is `InternalLinkOnceODR` (`lib/IRGen/GenDecl.cpp:6515-6516`, inside
  `shouldDefineHelper`) — hidden `linkonce_odr`, cross-TU mergeable by construction — unless
  the type is expansion-sensitive (opaque result types) or depends on a file-private
  nominal's metadata, in which case it falls back to `PrivateLinkage`
  (`Outlining.cpp:510-533,590-613`, with the reasoning spelled out in the comment at
  `Outlining.cpp:97-101,517-529`: two different files could otherwise "merge under one
  mangled name" with *different bodies*, which would be a correctness bug, not an
  optimization).
- Confirmed live: `Fixtures/Sample/sample.release` has
  `_$s6sample4TreeOWOe` / `_$s6sample4TreeOWOy` (outlined consume/copy for the sample's
  `Tree` enum) and the same pair for `Foundation.Data._Representation` and
  `sample.NetworkResult` — three unrelated nominal types, three independent `WOy`/`WOe`
  pairs, exactly the shape described above.
- What's gone: at the call site, a copy/destroy of a nontrivial value becomes a plain call
  to a `WOy`/`WOh`-suffixed helper with no inline evidence of *which* value witness
  operations it performs — that has to be read out of the callee, and the callee's identity
  (which concrete type it's for) is only recoverable from its mangled name, which in turn
  is only present if the symbol table entry survived stripping (see §4).

### 1.5 Dead-function and unused-witness elimination

- Driver: `DeadFunctionAndGlobalElimination` in `lib/SILOptimizer/IPO/DeadFunctionElimination.cpp`,
  a mark-and-sweep from public/exported roots (`isAlive`/`makeAlive`,
  `DeadFunctionElimination.cpp:171-231`).
- **Vtables and witness tables are treated differently**, and the difference matters for
  what a decompiler should expect to find at a table slot:
  - Vtable entries for a dead override are *physically removed*:
    `vTable->removeEntries_if(...)` — `DeadFunctionElimination.cpp:683-693`. The slot
    disappears; table layout shrinks.
  - Witness table entries are *nulled in place*, not removed:
    `WT->clearMethods_if(...)` — `DeadFunctionElimination.cpp:697-719`. The protocol
    requirement order is part of the ABI (default witness tables, resilient conformance
    lookup), so the slot must stay; only the function pointer it holds is zeroed. There is
    an explicit safety carve-out that never nulls a distributed-actor witness even if it
    looks dead (`DeadFunctionElimination.cpp:704-711`), because the distributed runtime
    dispatches through that witness dynamically and static reachability analysis can't see
    that use.
  - Consequence for swiftdc: a witness table slot with a **null function pointer** is a
    legitimate, fully-specified state — "this requirement is unreachable in this binary" —
    not a parse error or a `?`. Rendering it as `?` (a *declined* value) would be wrong; the
    correct read is "eliminated" (a *known* fact), a different diagnostic than "unrecovered."
- What's gone: an entire method implementation, plus (for vtables) the very existence of
  its table slot. There is no residue to decline on — the function is not merely stripped of
  its name, it is not present in the binary's control flow graph at all. A binary-wide
  method-count derived from vtable/witness-table shape will systematically undercount
  relative to the Swift-level protocol/class declaration once a library is `-O`'d with dead
  code stripping — that undercount is correct, not a bug in the reader.

### 1.6 Exclusivity and retain/release optimization

- **Both are gated on the performance pipeline, and neither runs at `-Onone` in its full
  form** — a direct, checkable answer to "what does `-Onone` still show you":
  - `P.addARCSequenceOpts()` (the real, iterative, alias-analysis-driven redundant
    retain/release pair cancellation in `lib/SILOptimizer/ARC/ARCSequenceOpts.cpp`) is
    called at `lib/SILOptimizer/PassManager/PassPipeline.cpp:536,612,629` — all inside
    helper functions reachable only from `getPerformancePassPipeline` (`:982`).
    `getOnonePassPipeline` (`:1079-1130`) calls only `P.addMandatoryARCOpts()`
    (`PassPipeline.cpp:1091`), explicitly flagged in its own adjoining comment as a lesser,
    peephole pass ("TODO: MandatoryARCOpts should be subsumed by CopyPropagation").
  - `P.addAccessEnforcementOpts()` / `P.addAccessEnforcementReleaseSinking()` (which fold
    `begin_access`/`end_access` exclusivity markers to `[no_nested_conflict]` and delete the
    runtime-visible half of the check once no aliasing access can be proven) appear only at
    `PassPipeline.cpp:421-433,864-906`, again only reachable from
    `getPerformancePassPipeline`. `getOnonePassPipeline` never calls them.
  - Doc comment on the pass itself: "Find begin/end access scopes that are uninterrupted by
    a potential conflicting access. Flag those as `[nontracking]` access. ... If successful,
    folding simply sets the `[no_nested_conflict]` attribute ... and removes all
    corresponding end_access instructions" —
    `lib/SILOptimizer/Transforms/AccessEnforcementOpts.cpp:21-32`.
- What a decompiler sees: at `-Onone`, retain/release traffic and (for `-enforce-exclusivity
  =checked`, the default for non-inlinable code) exclusivity-check calls appear roughly at
  the density and position the source implies. At `-O`, both populations are pruned — a
  retain immediately followed (on every path) by a matching release with no intervening use
  that could observe the extra retain is provably redundant and removed; a `begin_access`
  proven non-conflicting drops the corresponding runtime call entirely. **A decompiler must
  not use retain/release call density, or the presence/absence of exclusivity calls, as
  evidence of anything about the source** at `-O` — both are artifacts of how much the
  optimizer proved, not of what the source wrote.

### 1.7 Devirtualization

- Driver: `Devirtualizer` pass, `lib/SILOptimizer/Transforms/Devirtualizer.cpp:32-56`,
  using `ClassHierarchyAnalysis` (whole-module class-hierarchy reasoning) to replace an
  indirect `class_method`/`witness_method` dispatch with a direct `function_ref` when the
  concrete implementing type is provably the only possibility.
- What's gone, precisely: **the dynamic-dispatch instruction itself disappears.** Before:
  a vtable-slot load (`class_method`) or witness-table-slot load (`witness_method`)
  followed by an indirect call. After: a plain direct call, syntactically indistinguishable
  from a call that was *never* virtual. There is no marker left behind saying "this call
  used to be virtual." A decompiler's xref/call-graph builder that infers "is this call
  site dynamic dispatch" from the instruction shape at the call site will get a **false
  negative** for every devirtualized call in an `-O` binary — the only way to recover "this
  was originally an overridable method" is from the *declaration side* (the vtable/witness
  table still lists the method, per §1.5, unless it was also DCE'd) or Swift-level metadata,
  never from the call-site instruction sequence.

---

## 2. Identical Code Folding and symbol-address collapse

**This is not a Swift-compiler behavior — grep across the entire `swift` monorepo for
`"identical code folding"`, `"ICF"`, `"-icf"`, `"deduplicat"` inside `lib/IRGen` and
`lib/SILOptimizer` turns up nothing.** Swift's compiler does not perform, name, or document
ICF. What it does is manufacture, in enormous volume, exactly the kind of symbol the
**linker's** ICF pass (`ld64 -icf`, on by default for release/Mach-O builds) is designed to
fold:

- Outlined value-witness helpers (§1.4) are keyed by *type identity*, not call site, default
  to hidden `linkonce_odr` (`lib/IRGen/GenDecl.cpp:6515-6516`), are marked `noinline`
  (`Outlining.cpp:543` `setIsNoInline`), and are frequently *tiny* (a copy of a single
  scalar field, a no-op `ret` for a trivial value). Two structurally-unrelated types whose
  outlined destructor both reduce to "nothing to do, return" compile to byte-identical
  machine code under different mangled names.
- Ordinary app-level generic specializations (§1.1) are `Shared`/`linkonce_odr` by
  construction (`Generics.cpp:3514-3517`) — the same ODR pool.
- Reabstraction thunks (§3) are `Shared` + `IsTransparent`
  (`lib/SILGen/SILGenThunk.cpp:675-678`).

**The mangling grammar has a reserved slot for a compiler-driven merge — `Tm`, "merged
function" (`docs/ABI/Mangling.rst:268`, `Node::Kind::MergedFunction`,
`include/swift/Demangling/DemangleNodes.def:183`) — and nothing in the current tree
produces it.** `grep -rl MergedFunction .` inside `/Users/camden/swift` (excluding
`.git`) returns only the four demangling files
(`Demangler.cpp:144,3046`, `Remangler.cpp:1905,2733-2734`, `OldRemangler.cpp`,
`NodePrinter.cpp`) — parse/print support with **no producer** anywhere in
`lib/SILOptimizer` or `lib/IRGen`. This is the crux of why the task's premise is exactly
right: **when the linker folds two differently-named, differently-mangled Swift functions
onto one address, nothing about either symbol's mangled name changes to say so.** The
demangler will print a perfectly specific, confident, individually-plausible name for each
symbol sharing that address, with no in-band signal that they're aliases of one physical
instruction stream.

**Directly confirmed against `Fixtures/Sample/sample.release`** (`-O`, unstripped — so this
is address-collapse visible even before dyld-cache-style local-symbol stripping compounds
it further, per `docs/PRODUCTION-READINESS.md:265-278`):

```
nm sample.release | grep ' T \| t ' | awk '{print $1}' | sort | uniq -d | wc -l   # 9
nm sample.release | grep ' T \| t ' | awk '{print $1}' | sort | uniq -c \
  | awk '$1>1{s+=$1} END{print s}'                                               # 33 of 196
```

9 addresses are each claimed by 2+ distinct mangled symbols; 33 of 196 `__TEXT` function
symbols (17%) sit in one of those groups — in a single small fixture. One group,
`0x100001100` → `0x100010f8` (verified with `otool -tv`, a bare `ret` — one instruction),
is shared by **at least 14** semantically unrelated declarations spanning five different
types:

```
_$s6sample10SampleMainVACycfC                          init
_$s6sample13NetworkResultOwup                           unsafeMutableAddressor
_$s6sample4TreeOwup                                     unsafeMutableAddressor
_$s6sample5PointV1x1yACSd_SdtcfC                        memberwise init
_$s6sample5PointV1xSdvM.resume.0                        _modify resume continuation
_$s6sample5PointV1xSdvg                                 getter
_$s6sample5PointV1ySdvM.resume.0                        _modify resume continuation
_$s6sample6CircleV4nameSSvM.resume.0                    _modify resume continuation
_$s6sample6CircleV6centerAA5PointVvM.resume.0            _modify resume continuation
_$s6sample6CircleV6radiusSdvM.resume.0                   _modify resume continuation
_$s6sample9DirectionOwup                                unsafeMutableAddressor
_$s6sample9RectangleV5widthSdvM.resume.0                 _modify resume continuation
_$s6sample9RectangleV6heightSdvM.resume.0                _modify resume continuation
_$s6sample9RectangleV6originAA5PointVvg                  getter
```

Picking *any one* of these to label address `0x10f8` — the obvious strategy for a "find the
nearest symbol" naming heuristic — misattributes the other 13. **This is the concrete,
reproducible case for why swiftdc's `sub_`-naming problem (`docs/PRODUCTION-READINESS.md:274-286`)
cannot be closed by a smarter nearest-symbol search**: for a meaningful fraction of `-O`
addresses, there is no single correct symbol, because there is no single function there —
there are N declarations whose *bodies happened to compile identically*, and the ABI-level
"body" is a fiction shared by all of them.

---

## 3. Specialization thunks and re-abstraction thunks

- Grammar: `global ::= type type generic-signature? 'TR'` (current reabstraction thunk) /
  `'Tr'` (obsolete mangling, still demangled) — `docs/ABI/Mangling.rst:270,274`. Printed
  form: `"reabstraction thunk from <A> to <B>"` (or, with `ShortenThunk`, `"thunk for
  <B>"`) — `lib/Demangling/NodePrinter.cpp:2199-2218`. Always non-polymorphic
  `impl-function-type`s, "from" and "to" always in that order —
  `docs/ABI/Mangling.rst:301`.
- **Reabstraction thunks are not an `-O` phenomenon — correcting a framing the task
  implicitly invites.** They're produced by SILGen (`getOrCreateReabstractionThunk`,
  `lib/SILGen/SILGenThunk.cpp:623-678`) whenever a function value crosses an *abstraction
  pattern* boundary — e.g. a concretely-typed function assigned where a generic
  `<T>(T) -> T`-shaped slot is expected, or vice versa — which is a structural fact about
  the type system, not an optimization. They are created with `IsTransparent = true` and
  `Shared` linkage (`SILGenThunk.cpp:675-678`), which means the **Mandatory** inliner
  inlines them unconditionally at every call site it can reach — `MandatoryInlining.cpp`
  lives under `lib/SILOptimizer/Mandatory/`, which runs at `-Onone` too. So a reabstraction
  thunk can already be invisible (fully inlined away) in a *debug* build; what `-O` changes
  is only the *volume* of code that ends up needing one (aggressive specialization and
  closure propagation create more abstraction-boundary crossings than the source had), and
  whether the performance inliner additionally inlines the ones Mandatory inlining left
  behind.
- Recognizing one in a stripped `-O` binary, given the above (no name, no thunk marker):
  structural shape is the only signal — a short, branchless function whose only real work
  is repacking arguments (loading through one indirection level, or converting a direct
  return into an indirect `sret`-style write, or vice versa) before an unconditional
  tail-call. This is the same shape as an FSO thunk (§1.2) and a `partial_apply` forwarder
  (below); distinguishing them without a surviving mangled name is not reliably possible —
  §5 recommends declining to disambiguate rather than guessing which kind of thunk it is.
- `partial_apply` forwarders: printed as `"partial apply forwarder for <callee>"` /
  `"partial apply ObjC forwarder for <callee>"` —
  `lib/Demangling/NodePrinter.cpp:2114-2130`, grammar nodes
  `Node::Kind::PartialApplyForwarder`/`PartialApplyObjCForwarder`
  (`include/swift/Demangling/DemangleNodes.def:210-211`). These are the closure-context
  trampolines `partial_apply` produces: given a captured-context pointer plus the
  remaining arguments, forward to the original function. Same SILGen-level, not
  `-O`-specific, origin as reabstraction thunks; same recognizability caveat.
- Mapping a thunk back to its generic origin: the mangled name (when present) carries the
  concrete "from"/"to" types directly — no search needed, just demangling. When the name is
  gone, there is no back-mapping; the thunk's *shape* only proves "this repackages
  arguments for a tail call," never which original generic declaration it repackages for.

---

## 4. Recoverable vs. gone at `-O` — where to decline

| Recoverable (from the binary alone) | Gone (must decline, not infer) |
|---|---|
| A `Tg5`/`Ts`-suffixed function's **concrete type arguments** — literally encoded in the mangled name, when the symbol survives (§1.1). | Which call sites originally called the *generic* form — after specialization every call is direct to the concrete instance (§1.1). |
| A `Tf`-suffixed function's **argument-modification kinds** (dead/const/exploded/etc.) — encoded letter-by-letter in the mangled name (§1.2). | The original argument count/types at the `Tf` function itself if the name is stripped — no ABI-level marker distinguishes an FSO'd signature from a hand-written one of the same shape. |
| That a `WOy`/`WOe`/... symbol performs *some* value-witness operation — the letter says which one (§1.4). | *Which* concrete type it's for, once the symbol name is gone — and whether the address is even uniquely "for" one type, given §2. |
| A witness-table slot's **liveness** — a null function pointer is a fully-specified "eliminated," not a `?` (§1.5). | The eliminated implementation's body — it is not merely unnamed, it does not exist in the binary. |
| — | Whether a direct call was originally dynamic dispatch — devirtualization leaves zero trace at the call site (§1.7). |
| — | Retain/release call density or exclusivity-check presence as evidence about source structure — both are pruned by provability, not by what the source wrote (§1.6). |
| — | Which of N same-address symbols is "the" name for that address, once ICF has folded them — there may be no correct answer (§2). |
| — | Which thunk kind (FSO/reabstraction/partial-apply-forwarder) an unnamed marshal-and-tail-call stub is — all three converge on the same shape (§3). |

The general shape: **the mangled name is where the erased information actually lives.**
Everything in the left column requires the symbol table entry to have survived. Once it's
stripped (the dominant real-output gap already measured in
`docs/PRODUCTION-READINESS.md:274-286` — ~49% of recovered functions on CoreLocation), most
of the left column collapses into the right column too. `-O` doesn't just make names
uglier; it makes the *decompiled-without-a-name* case strictly harder, because the
address-level evidence (call shape, retain traffic, dispatch shape) that would otherwise
hint at what a function is has itself been optimized away.

---

## 5. Recommendations for swiftdc, ranked

Checked against current swiftdc source: none of `Tg5`/`Ts`/`Tf`/`TR`/`WOy`/`Merged`/
`PartialApplyForwarder` is special-cased anywhere in
`Sources/SwiftDecompilerCore/{MetadataSymbolizer,SwiftDeclarationDumper}.swift` (grep for
`Tg5|specializ|Reabstraction|Outlined|GenericSpecialization|FunctionSignatureSpecialization|
Merged|PartialApplyForwarder` in those two files: no hits). The demangler swiftdc calls at
`Disassembler.swift:3232-3244` (`demangleAsNode` → `node.print(...)`) will already render
*a* string for all of these if a symbol exists at all — the gap is entirely in **not using
the demangled node's structure to drive decompiler behavior**, i.e. this is close to
greenfield.

1. **(Highest value, cheapest) Stop trusting any single symbol at an address once it's
   known to be shared.** Before naming a `sub_<addr>` or attributing a demangled name to an
   address, check whether the symbol table has other entries at the *same* address (§2's
   `uniq -d` check is a one-line implementation). If so, render something honest — "N
   candidate names at this address (ICF-folded): A, B, C, ..." — never silently pick one.
   This is a direct, mechanical instance of the project's core "decline rather than guess"
   rule (`CLAUDE.md`), and the sample fixture proves it is not a rare edge case (17% of
   `__TEXT` symbols in one small binary). Add a regression test pinned to the exact
   `sample.release` address/symbol-count numbers quoted in §2 so a future symbolizer change
   can't silently regress this back to "assume unique."

2. **Detect the FSO thunk-swap pattern (§1.2) structurally, not by name.** A function whose
   body is a handful of arg-marshalling instructions terminating in an unconditional call
   to a `Tf`-suffixed sibling should be rendered as "thunk; real implementation is
   `<demangled Tf name>`, with the following argument transform: ..." — parse the `Tf`
   mangling's `ARG-SPEC-KIND` letters (`docs/ABI/Mangling.rst:1394-1406`) to state the
   transform precisely (which original argument index was dropped/exploded/constant-folded,
   and to what) rather than just showing the `Tf` function's post-transform signature raw.
   This directly improves the "unrecognisable signature" bucket in
   `docs/PRODUCTION-READINESS.md:166` — an FSO'd function currently falls into "decline
   entirely" territory; it doesn't have to, since the transform is fully specified in the
   name.

3. **Match on demangled `Node.Kind`, not printed-string substrings, and definitely not on
   `"Wy"`/`"We"`.** The obsolete-vs-current outlining prefix confusion in §1.4 is exactly
   the kind of bug that string-matching invites. swiftdc's vendored demangler package
   mirrors the canonical `Node::Kind` enum (per
   `docs/research/swift-source/mangling-grammar.md`'s own finding that it's a structural
   port, not a wrapper around the C++ library) — match on the equivalent of
   `Node.Kind.outlinedCopy` / `.outlinedConsume` / `.outlinedRetain` / `.outlinedRelease` /
   `.outlinedInitializeWithCopy` / `.outlinedAssignWithTake` / `.outlinedAssignWithCopy` /
   `.outlinedDestroy` / `.outlinedVariable` / `.outlinedBridgedMethod` (the full producer
   list is `lib/Demangling/Remangler.cpp:3702-3860`), `.genericSpecialization`/
   `.genericSpecializationNotReAbstracted`/`.genericSpecializationPrespecialized`,
   `.functionSignatureSpecialization`, `.reabstractionThunk`/`.reabstractionThunkHelper`,
   `.partialApplyForwarder`/`.partialApplyObjCForwarder`, and `.mergedFunction` (present in
   the grammar for round-tripping; per §2, nothing currently produces it, so treat a match
   as a signal to re-verify against a newer compiler rather than as dead code to delete).

4. **Tag every specialization/outlining/thunk symbol as compiler-synthesized in whatever
   "is this user code" classification swiftdc has**, and exclude that population from
   naming heuristics that assume one function = one declaration (nearest-symbol search,
   "most specific enclosing symbol," etc.) — they are exactly the population §2 shows is
   least trustworthy for that purpose. This is a prerequisite for recommendation 1, not an
   alternative to it: recommendation 1 handles "what to render," this handles "what pool of
   symbols even gets to compete for an address" in the first place.

5. **When emitting call-graph/xref edges, do not infer "was this call originally dynamic
   dispatch" from call-site shape (§1.7 — devirtualization erases it completely).** If
   swiftdc's xrefs analysis (`docs/PRODUCTION-READINESS.md` mentions unresolved indirect
   call edges as a separate open item) ever adds a "static vs. dynamic" classification for
   *resolved* direct calls, it must derive that from the declaration side (is the target
   still listed in a vtable/witness table, per §1.5) or decline, never from the call
   instruction.

6. **Do not use retain/release density or exclusivity-check presence as a `-O` vs
   `-Onone` detection heuristic, or as evidence for any source-level claim, in `-O`
   binaries** (§1.6) — if swiftdc has (or plans) any optimization-level auto-detection, base
   it on something the optimizer doesn't selectively prune (e.g. presence of `Tg5`/`Tf`/
   `WOy`-family symbols at all, or `HeuristicAlwaysInline` thunk shapes, is a much sturdier
   -O fingerprint than instruction-density metrics).

7. **Lower priority — closure specialization (§1.3) reconstruction.** Recovering "this was
   originally a higher-order call with closure argument X" from a `Tf1`/closure-mangled
   specialized callee is a real gap but a narrower one (needs both the `Tf1...c...`-style
   mangled name to survive *and* the caller's `partial_apply` to still be visible, which it
   frequently won't be after the specializer removes it). Worth a `?`-rendered placeholder
   ("originally took a closure parameter, specialized away") gated on mangled-name evidence
   only, not worth building general closure-recovery machinery until the higher-priority
   items above are shipped.

---

## 6. Open questions / what to verify against a real `-O` fixture

- **How much of §2's ICF collapse survives into `libReconstruction.opt.stripped.dylib`
  specifically (vs. the unstripped `sample.release` used for the §2 measurement)?**
  Stripping removes local symbols first, which could either *reduce* the visible collapse
  (fewer competing names left to prove the point) or *increase* the practical harm (fewer
  alternative names left to cross-check against). Worth the same `uniq -d` measurement
  against the stripped fixture and against a real system framework (CoreLocation is already
  swiftdc's standard `--image` target per `docs/PRODUCTION-READINESS.md:274`).
- **Does `ld64`'s ICF pass fold across *different* `-O` compilation units the same way it
  folds within one `swiftc` invocation's output?** The `sample.release` fixture is a single
  `swiftc` invocation (`Fixtures/Sample/build.sh:15`); the linker's cross-object folding
  behavior on a multi-TU app or a large framework (where `linkonce_odr` dedup across TUs
  interacts with ICF across *different* mangled names) is not verified here and would need
  a multi-file fixture.
- **Whether swiftdc's vendored `swift-demangling` package actually implements every
  `Node.Kind` cited in §5's recommendation 3** — `mangling-grammar.md` already flags this as
  spot-checked, not exhaustively verified, for the general case; the specific kinds needed
  for this doc's recommendations (`outlinedCopy`, `functionSignatureSpecialization`, etc.)
  should be checked directly (e.g. `swift package resolve` the pinned checkout and grep it)
  before code is written against them.
- **The exact FSO argument-transform parser (recommendation 2) has not been prototyped.**
  `docs/ABI/Mangling.rst:1394-1406`'s `ARG-SPEC-KIND` grammar looks straightforward to parse
  but was only read, not implemented or round-tripped against a real `Tf`-mangled name here
  (the one confirmed live example, `sample.release`'s
  `..._$s6sample9DirectionO...Tf4nd_n`, was demangled by inspection, not by running
  swiftdc's own demangler against it — worth doing before committing to the parser design).
- **Whether `getOnonePassPipeline`'s reach into `UsePrespecialized`/`OnonePrespecializations`
  (§1.1) is visible on a real `-Onone -g` fixture — checked, and it's negative for this
  fixture.** `nm -j sample.debug | grep -E "_Tg5|_Ts5"` and the same for undefined symbols
  (`nm -u`) both return zero matches, on both `sample.debug` (`-Onone -g`) and
  `sample.release` (`-O`) — `OnonePrespecializations.def` is a curated, finite list of
  specific stdlib generic instantiations (`Array<Int>.init()` and friends,
  `lib/SILOptimizer/Utils/OnonePrespecializations.def:3-16`), and this small sample program
  doesn't happen to call any of them. The pass-pipeline reading in §1.1 (the pipeline *can*
  redirect to prespecialized names at `-Onone`) stands on its own citations
  (`PassPipeline.cpp:1088-1101,1119`); what's unverified is only whether it fires
  *routinely* in ordinary code or only for the specific enumerated stdlib entry points. A
  fixture that explicitly does `Array<Int>()` or another `OnonePrespecializations.def`
  entry at `-Onone` would settle it either way — worth adding if this question matters for
  swiftdc's `-Onone` naming path.

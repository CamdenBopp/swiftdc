# Async and error ABI sprints

Read-only source assessment, 2026-11-23. No compiler, build, test, decompiler, native fixture or performance command was run. The requested file is the only deliverable created. Nothing under `the repository` was edited.

## Revisions, evidence and limits

- `the repository` HEAD is `ca9eef5ce2909f5f584d8270026f606c3f1b1e0e`, on `dev`. The async WIP is not part of that commit. There is also unrelated flag-width/OptionSet WIP, which this plan does not absorb.
- `git -C <swift checkout> rev-parse HEAD` returned **`1b7bd8eaf460396047c2644d1d69afb4a404b13d`**, titled `Merge pull request #91963 from xedin/called_once+dependent-types`. Its working tree was clean. It **does not match** the plan's `83eb12448e4323abbf81b0153dced2faff02d22f` pin. That pin is not an available object in this checkout.
- The separate retained release checkout `work/abi-gap-audit/swift-6.4.2` does resolve to `83eb12448e4323abbf81b0153dced2faff02d22f`. The retained LLVM checkout `work/abi-gap-audit/llvm-6.4.2` resolves to `fb5f84d903a3b4e7aea15cd5666598a46f56c833`. These were inspected read-only. They are not substitutes for reporting the requested `<swift checkout>` revision.
- LLVM coroutine splitting is **not materialized in either source tree I searched**. The retained LLVM Git tree contains `llvm/lib/Transforms/Coroutines/CoroSplit.cpp`, but its checkout lacks that directory. I did not materialize/fetch/read that blob. I inspected the available AArch64 convention and call-lowering files. No claim below derives a final split-frame layout from an uninspected LLVM pass.
- **R** means verified by reading current source or Git state. **H** means a historical measurement recorded in a document/test, not repeated here. **I** means an inference or proposed output/test. Every before/after below is an **I target**, unless explicitly identified as an existing test assertion. No suspected defect is newly reproduced by this research.

### Citation convention

To keep the sprint list readable, filenames in citations resolve to these absolute roots:

| Prefix | Absolute root |
|---|---|
| `DC/` | `Sources/SwiftDecompilerCore/` |
| `T/` | `Tests/SwiftDecompilerCoreTests/` |
| `F/` | `Fixtures/Sample/` |
| `C/` | `<swift checkout>/` |
| `LLVM/` | `work/abi-gap-audit/llvm-6.4.2/` |
| `DOC/` | `docs/` |

For example, `DC/Disassembler.swift:12958` is `Sources/SwiftDecompilerCore/Disassembler.swift:12958`. Line numbers refer to the observed working files. The async WIP adds 87 lines before the error-enrichment section. For important HEAD anchors: working lines 12885, 12958, 12991 and 13767 correspond to committed lines 12798, 12871, 12904 and 13680. `git diff` confirms the cited error logic is unchanged by WIP. The WIP-specific sites are explicitly marked.

### Where the audit's compiler links differ

The audit is not simply about this local compiler revision with outdated line numbers. A direct comparison of the two available `GenCall.cpp` files establishes these distinctions:

- The two-word ordinary async header remains at `C/lib/IRGen/GenCall.cpp:114-160`. Direct typed-error combination is now at `:430-499`, rather than the audit's `:432-499` start.
- `addAsyncParameters` and coroutine no-alias attributes are now at `:929-949`, not the audit's `:901-950` placement. SwiftAsync still lacks the explicit NoAlias attached to the coroutine context. Missing NoAlias is not a license to mutate an ancestor.
- Ordinary async return now begins at `:6664`, not `:6656`. Await projection moved from release `GenFunc.cpp:2875` to local `C/lib/IRGen/GenFunc.cpp:2967`.
- Local `C/lib/IRGen/IRGenSIL.cpp` has `try_apply` outcome lowering at `:4084-4197`, throw at `:4697-4810`, throw_addr at `:4813-4850`, and hop at `:8102-8111`. The audit's corresponding ranges are earlier.
- Local `C/lib/SIL/IR/SILFunctionType.cpp:1969-1991` inserts nonsending isolation, and `:5831-5835` classifies typed errors. The release audit cites `:1934-1980` and `:5709-5714`.
- Local `C/include/swift/ABI/Task.h:1036-1070` and `C/stdlib/public/Concurrency/Actor.cpp:2593-2670` contain the header/switch rules. Release locations were `Task.h:855` and `Actor.cpp:2481`. Current TaskStatus also contains cancellation shields and cancellation reasons, which must not be silently attributed to the older runtime family.
- The GenCall comparison shows substantive changes outside line drift: ordinary non-aliasable inout parameters now receive NoAlias without the release's pointer-element restriction (`:354-358`), direct-formal-result queries explicitly request lowered addresses (`:3898-3910`), and typed coroutine allocation selects available typed runtime functions (`:5196-5210`). Do not backport those assumptions into a 6.4.2 runtime contract by default. The inspected async header, result/error combination and return mechanisms remain structurally consistent.
- The retained LLVM AArch64 source supplies independent register placement: `LLVM/llvm/lib/Target/AArch64/AArch64CallingConvention.td:65-82` assigns sret X8, SwiftSelf X20, SwiftError X21, SwiftAsync X22 and SwiftCoro X23. Its Darwin SwiftTail mask removes X20/X22 at `:750-754`. This is release LLVM evidence, not evidence that local Swift and the installed Apple backend are identical.

The audit's A01-A08 IDs are defined in `DOC/ABI-CLOSURE-PLAN.md:149-164`; its async report has topic rows rather than eight explicit ID rows. This report uses the plan's mapping.

## Every audit item at current HEAD

An entire item is classified once. A closed subcase does not close its containing item. Totals are **0 already closed, 10 partially closed, 4 safely declined, 6 possibly wrong**. "Possibly wrong" identifies a source-backed risk, not a newly observed bad render.

| Item | Current classification | swiftdc evidence at HEAD, unless marked WIP | Local compiler/runtime rule and remaining scope |
|---|---|---|---|
| A01 region dependencies | Partially closed | R: streaming decodes on demand, `DC/Disassembler.swift:1151-1174`. Grouped-array indexing can decode dependencies at `:1833-1838`, but chain analysis receives only `groupedByStart` at `:1862-1866`. | `C/lib/IRGen/GenCall.cpp:3185-3214` and `C/lib/IRGen/GenFunc.cpp:2967-3006` explain why dependencies span caller/callee/resume. Loader parity itself is a swiftdc invariant, not a compiler ABI rule. Missing dependency currently loses proof rather than adding it. |
| A02 identity, capture and lifetime | Possibly wrong | R: existing chain seeds are based on entry branch witnesses and a unique chain-wide store, `DC/Disassembler.swift:2707-2782`. `DC/AsyncContextEscapes.swift:45-52` exempts recognized terminal transfers from unknown-flow rejection and does not inspect their callee bodies. WIP solver is not production admission. | `C/include/swift/ABI/Task.h:1036-1054` allows caller-frame contexts. `C/lib/IRGen/GenCall.cpp:128-142,929-949` establishes Parent/Resume, not ancestor non-aliasing. I: a child following Parent can defeat entry-slot invariance. Test this before calling any current value wrong. |
| A03 first closed awaited scalar across hop | Safely declined | R: all three production `asyncChainSlots` calls omit the new admission arguments (`DC/Disassembler.swift:1162,1566,1863`). WIP `DC/AsyncCheckedImage.swift:39-55` and `DC/AsyncPhysicalReplay.swift:44-85` have no production admission issuer. | `C/lib/IRGen/GenCall.cpp:3185-3214,6664-6713`, `C/lib/IRGen/GenFunc.cpp:2967-2990`, and `C/stdlib/public/Concurrency/Actor.cpp:2616-2670` require exact child return and both inline/queued routes. No authentic end-to-end scalar positive exists in the inspected code. |
| A04 ordinary-await transport | Safely declined | R: chain slots require entry-established values, `DC/Disassembler.swift:2665-2670,2770-2782`. Existing exact oracle ends two awaits with `return ?`, `T/AsyncFuncletTests.swift:285-305`. | `C/lib/IRGen/GenCall.cpp:3190-3214,3321-3330,6668-6694` distinguishes child setup, return operands and lifetime. Each awaited body needs its own effects; a hop contract is insufficient. |
| A05 formals, isolation and results/errors | Partially closed | R: FP/self survive conservative entry projection; direct scalar await X0/V0 is supported, `DC/Disassembler.swift:2576-2635`. Typed/closure results decline. `T/AsyncIsolationArgumentTests.swift:20-54,80-105` and `T/AsyncFPResultPrecisionTests.swift:9,95` preserve these bounds. | `C/lib/SIL/IR/SILFunctionType.cpp:1969-1991`; `C/lib/IRGen/GenCall.cpp:2180-2443`. Prefix selection, ordered multiword/mixed results, by-address results and outcome-specific typed errors remain open. Ordinary scalar result seeding is already implemented, not a new sprint. |
| A06 dynamic descriptors | Partially closed | R: `DC/AsyncFunctionDescriptor.swift:17-81` reads a bounded static code/size record. `DC/AsyncDescriptorHandoff.swift:20-100` links an outgoing operand, but its extra register parameter is WIP. HEAD emits descriptor observations only under Probe, `DC/Disassembler.swift:2136-2161`. | `C/lib/IRGen/GenMeta.cpp:8213-8229` emits compact code plus Int32 size. `C/lib/IRGen/GenCall.cpp:2650-2724` separately handles direct, dynamic, indirect and authenticated pointers. Selected witness/class implementation and size still need proof. |
| A07 structured concurrency, continuations and allocation | Partially closed | R: runtime-wait resume registers and continuation-init ownership are indexed, `DC/AsyncFuncletIndex.swift:313-333,700-707,860-867`. `T/AsyncTransferEdgeTests.swift:62,80` tests indexing, not result lifecycle. `F/awaitresults.swift:35-45` includes declined task/async-let consumers. | `C/stdlib/public/Concurrency/Task.cpp:1434-1528,1611-1834`; `AsyncLet.cpp:182-292,302-501`; `TaskGroup.cpp:1267-1295,1791-1838,2013-2095`; `TaskAlloc.cpp:54-71`. Buffer initialization, completion order, consume/finish and capture effects are separate gaps. |
| A08 runtime/provider/scheduler contracts | Possibly wrong | R: allocator provider qualification exists for outgoing observations, `DC/AsyncDescriptorHandoff.swift:104-107`. Production grouping still recognizes switch/alloc/waits by names, `DC/AsyncFuncletIndex.swift:317-333,650-653,1041-1048`; those choices feed rendered hop facts, `DC/Disassembler.swift:2644-2654`. | `C/stdlib/public/Concurrency/Actor.cpp:2593-2670` considers preferred TaskExecutor as well as serial executor. `C/stdlib/public/Concurrency/Task.swift:680-695` enqueues a continuation job. I: same-named unrelated providers can receive false hop/continuation semantics. Existing scalar corruption is not established. |
| E01 error-channel CFG proofs | Partially closed | R: full-width CBZ/CBNZ, zeroing, CFG must meet and entry spills are implemented, `DC/SwiftErrorExitProof.swift:28-110,137-144`; `DC/Disassembler.swift:13049-13093`. `T/ErrorExitProofTests.swift:36-74,115-125` covers narrow/opaque controls. | `C/lib/IRGen/GenCall.cpp:5497-5522`; `C/lib/IRGen/IRGenSIL.cpp:4098-4114,4190-4195`. Compare-plus-branch, copied discriminator versions and broader edge facts remain. |
| E02 call effects | Partially closed | R: provider-backed and exact-body nonthrowing facts already ship, `DC/ValueTracking.swift:1898-1932`; unknown armed-zero calls invalidate X21, `:2311-2331`; structurer stops its X21 walk at `DC/Structurer.swift:1285-1298`. `T/PlainNameErrorABITests.swift:108-184,212-291` is newer coverage the audit must retain. | `C/lib/IRGen/GenCall.cpp:2098-2130` and `C/lib/IRGen/IRGenSIL.cpp:4084-4197` define separate channel outputs and outcomes. Shared owner/version effects are incomplete, but dotless-name immunity is no longer the current behavior. Git `-S nonThrowingABIContract` identifies `e0b608c`. |
| E03 direct typed-error projection | Possibly wrong | R: the published five-UInt64-result guard blocks one reproduced inactive-X0 case (`DC/Disassembler.swift:12885-12886`; HEAD `:12798`). General enum naming still reads `analysis.exitValues` X0 at `:13767-13771`, including async throw exits. `T/TypedErrorInactiveRegisterTests.swift:110-189,193-254` proves the guard is narrow. | `C/lib/IRGen/GenCall.cpp:430-499,2107-2122,2207-2230` and `C/lib/IRGen/IRGenSIL.cpp:4724-4751,4776-4796`. Some success/error shapes have indirect errors or different active pieces. The audit's original reproduced five-word case is fixed in `6959523`/`65a627b`; residual generalization is not closed. |
| E04 typed error buffers | Safely declined | R: `DC/IndirectResults.swift:21-38` qualifies ordinary X8 ownership and explicitly excludes async. It is not an indirect error-buffer model. `T/ResilientTypedErrorSpecializationTests.swift:18-30,90` rejects unsupported typed layouts. | `C/lib/IRGen/GenCall.cpp:707-760,2107-2130,2253-2329`; `C/lib/IRGen/IRGenSIL.cpp:4159-4168,4813-4850`. Separate payload pointer, abstraction and initialization remain absent. Residual false X0 naming is counted under E03, not called a safe buffer reconstruction. |
| E05 merged outcomes and cleanup | Possibly wrong | R: `DC/Disassembler.swift:12986-13013` moves a throw to predecessor ends. `:13759-13761` sets thenThrows; `DC/Pseudo.swift:114-129` emits it immediately. No check there proves the shared epilogue has no observable effects. | `C/lib/IRGen/IRGenSIL.cpp:4130-4146` keeps correlated edges; `C/lib/SILGen/SILGenStmt.cpp:1418-1436` gives catches owned error/cleanup scope. I: moving a terminal throw before shared cleanup can omit its execution. CSEL outcomes otherwise safely stay unresolved (`T/ErrorExitProofTests.swift:145-159`). |
| E06 handlers and try forms | Partially closed | R: explicit error CFG, catcher ordinary returns and unresolved throwing exits are supported (`DC/Structurer.swift:186-209,1990-1999`; `T/ErrorExitProofTests.swift:128-142`). This does not reconstruct all try?/try!/catch/rethrows semantics. | `C/lib/SILGen/SILGenExpr.cpp:1303-1386`; `C/lib/SILGen/SILGenStmt.cpp:1371-1436`. Optional injection, discarded errors, trap and owned catch dispatch need separate proofs. |
| E07 Never and terminal exits | Possibly wrong | R: a function's own Never result is excluded from normal machine-value claims (`DC/Structurer.swift:111-118`), and `throws(Never)` specialization is handled (`DC/NeverThrowingSpecialization.swift:35-45,123-131`). Callee no-success does not propagate to CFG. Tail fallback still appends an ordinary return (`DC/Structurer.swift:730-743`). | `C/lib/SIL/IR/SILType.cpp:735-742`; `C/lib/IRGen/IRGenSIL.cpp:4496-4522`; `C/lib/IRGen/GenCall.cpp:4119-4123`. Never success, Never error, trap and no machine continuation differ. A merged trapping tail also lacks a terminal-outcome premise at `DC/Disassembler.swift:9549-9558`. |
| E08 throwing tails | Safely declined | R: `DC/Disassembler.swift:13104-13128` handles a bounded call+RET untyped forwarding case, with typed errors explicitly excluded. Broader branch/authenticated/schema-changing tails are unproven. `T/SwiftErrorCalleeTests.swift:206-226` retains typed controls. | `C/lib/IRGen/GenThunk.cpp:435-564`; `LLVM/llvm/lib/Target/AArch64/AArch64ISelLowering.cpp:9011-9044`. Reabstraction can box/change error transport. A physical tail alone is insufficient. |
| E09 async errors | Partially closed | R: scalar typed await result seeding declines, `DC/Disassembler.swift:2614-2621`; async normal/nonzero guards are bounded at `:12895-12946,13078-13089`. `T/ErrorExitProofTests.swift:163-215` covers merged and escaped parent exits. | `C/lib/IRGen/GenCall.cpp:2180-2245,2382-2443,6741-6814`; `C/lib/IRGen/IRGenSIL.cpp:4755-4810`. X20 continuation discriminator must not become entry self or sync X21. Direct/indirect success/error projection remains open. |
| E10 helper identity and thrown values | Possibly wrong | R: `DC/Disassembler.swift:12958-12982` still recognizes prefixes and uses a function-wide list of willThrow operands. `:13772-13779` restricts untyped value spelling to that list and keeps fresh boxes unknown. `T/ThrowValueTests.swift:10-32` already covers throwing an existing parameter. | `C/stdlib/public/runtime/ErrorObjectCommon.cpp:48-58,73-98` shows hooks, including typed hook boxing/callbacks. `C/lib/SILGen/SILGenStmt.cpp:1714-1726` emits the hook on the actual throw path. `C/stdlib/public/runtime/ErrorObject.mm:245-293` returns distinct box/payload pointers. Identity and path provenance cannot be inferred from a prefix or another branch. |
| E11 foreign errors | Partially closed | R: NSError-out-pointer invalidation is present (`DC/ValueTracking.swift:2137-2139`), and `T/SwiftErrorCalleeTests.swift:129-155` protects the ObjC bridge's real error path. System C controls at `T/PlainNameErrorABITests.swift:117-184` are not a complete foreign-error oracle. | `C/include/swift/AST/ForeignErrorConvention.h:29-78`; `C/lib/SILGen/SILGenForeignError.cpp:432-466`. Five distinct sentinel/result policies, error parameter index and ownership remain to be reconstructed. |
| E12 runtime signatures and terminals | Partially closed | R: `DC/SwiftRuntimeSignatures.swift:1-23` stores scalar result/argument strings. `Tools/runtime-signatures.py:20-62` filters out special registers/stack/unsupported conventions and does not preserve terminal attributes. `DC/FunctionCFG.swift:74-97,144-157` terminates traps, not declaration-proven noreturn calls. | `C/include/swift/Runtime/RuntimeFunctions.def:251-272` distinguishes ordinary void hooks from NoReturn unexpectedError. `C/lib/IRGen/IRGenModule.cpp:800-810` distinguishes NoReturn, NoUnwind and WillReturn. Historical generated-row counts are not a current completeness measurement. |

## Assessment of the uncommitted async work

### What is useful and what it has not proved

R: the WIP has a sensible separation between linked facts, physical operations, admitted effects and solver output. The sealed constructors prevent a test-supplied effect graph from silently becoming production truth. Keep that boundary.

- `DC/AsyncCheckedImage.swift:88-179,195-245` checks a small thin executable, LC_MAIN, readable executable spans and explicit ingress frontiers. It does not establish complete executable ingress.
- `DC/AsyncDetachedIngress.swift:100-110,152-195` follows an observed detached wrapper/adapter chain. Fixed counts and instruction fingerprints select one family of emitted code, not general Swift source constructs.
- `DC/AsyncPhysicalRegion.swift:115-167,193-201,353-360` fixes a prologue, offsets, four direct handoffs and particular register dataflows. Those are safely restrictive recognizers, but they make the breadth of the positive very narrow.
- `DC/AsyncClosedCallerSolver.swift:163-179,234-239,393-429,433-492` intersects definite values, unions publication, requires exact top allocation release and rejects cyclic/incomplete graphs. Its allocation identity is a site in an acyclic scoped activation, not a general generation model for recursion or repeated simultaneous instances.
- `DC/AsyncPhysicalReplay.swift:44-85` deliberately has no production minting API. `:88-100` pins one runtime UUID and yield size. `:178-185,235-264` validates supplied preservation routes; it does not independently derive those routes from the selected runtime/configuration.
- R: `DC/AsyncPhysicalReplay.swift:155-159` rejects reached shared-return addresses. The real fixture extraction explicitly inventories folded suppliers (`T/AsyncCheckedImageTests.swift:131-142`). Context-sensitive activation/return association, or an independently justified bounded exclusion, is still needed. An address-only state is insufficient when generations differ.
- R: the synthetic consumer test explicitly separates its supplied graph from actual admission (`T/AsyncClosedCallerSolverTests.swift:118-169`). It shows a model can seed a tracer expression. It does not show a linked executable renders the scalar.
- H: the handoff reports 17 ABI focused tests and 20 merged focused tests. Its 2,108-test gate was the committed folded-symbol change, not this WIP (`work/abi-gap-audit/claude-handoff-2026-11-22/HANDOFF.md:43-63`). Do not advertise a full-suite-qualified async recovery.

### What finishing would require

1. Prove actual capture/box allocation origins, extents, disjointness, initialization and lifetime. The unapplied capture proposal identifies allocation operands, not selected provider/body effects for the preceding TaskPriority witnesses. Do not apply it as an admission shortcut.
2. Close every executable activation reaching the address-keyed resume seed, including materialized pointers, exported/rebased ingress, folded resumes and prior runtime frontiers. A single successful execution or a manifest of expected sites is not this proof.
3. Bind a documented supported runtime/deployment/configuration contract to the imported operations. Derive allocation, release, yield and switch effects, including both completion orderings, inline and queued paths and applicable scheduler callbacks. Preserve historical publication across repair and deallocation. A UUID or runtime-profile Boolean cannot mint these effects.
4. Independently match descriptor size, allocation argument/result, child saved pointer, Parent/Resume reload, exact live deallocation and success result carrier. Keep an unknown standalone entry and a saved-child publication case declined.
5. Wire the admitted result through filtered/array/streaming consumers and prove the authentic `sink((awaited1 + 2))` in both source views at -Onone/-O/-Osize. Qualify changes with isolated compiled mutations, enforcing suite and frozen-release blast/cost gates after host measurements finish.

Recommendation: **park the fixture-specific detached-startup/admission chain, without deleting or overwriting it**. Finish the first closed hop only after ordinary result/outcome and runtime contracts exist. The chain is currently a large proof project for one scalar, with zero production admissions.

Useful pieces can become landable behavior when attached to a real consumer: one shared region loader (A01-a), exact outgoing descriptor operands (already published, do not land again), byte-overlap/top-release/publication rules in the shared transport solver (A02-b), and exact physical carrier checks. Do not land another disconnected certificate framework merely because its synthetic tests pass. Any extraction-only commit needs a concrete diagnostic/probe contract and its own test, labeled as such rather than as recovered values.

### Cheaper async coverage

The least expensive useful async work does not start by proving the whole detached executable. Recover suspension-free scalar exits and native result locations, retain the actual nonsending prefix only when independently available, and name successful task/async-let result-buffer loads from operation-specific contracts. Then handle typed outcomes and bounded ordinary-await effects. These changes touch common code without asserting that every async-context byte is private. Continuations and groups can first expose a typed operation-result token, preserving unknown child values and concurrent effects. They do not require inventing the child's numerical result.

## Sprint rules shared by every entry

Each entry below is one proposed commit and one behavior. The order is recommended, not an instruction to edit shared files concurrently. If a sprint discovers two independently necessary behaviors, split it again.

- Fixture sketches are authored reductions, not code copied from apps. Shared helpers below mean ordinary separately compiled noinline Swift functions: `sink(Int)`, `mark(Int)`, and providers whose bodies are supplied by the sketch. `E` is a small Error enum, and `Big` has five distinct UInt64 fields unless stated otherwise. Assembly or valid SIL is added only where source cannot force the precise boundary. A mutation image is decoded, never executed when ABI-invalid.
- **Every sprint uses -Onone, -O and -Osize.** Record each lowering separately, plus resolved compiler/frontend/SDK/deployment/feature modes. Do not require all three to emit one exact machine shape. Use a source/native harness for true results and ordered side effects. Terminal tests run in subprocesses. Include symbol-rich/stripped inputs and arm64e static/executable coverage when the admitted rule claims it.
- Before/after means a minimal semantic fragment, not a promised exact global pretty-print. An unchanged render with a new typed internal fact is stated explicitly. Assert producer calls once, their order, exit kind, and operand identity. Do not count fewer question marks without checking the newly asserted value.
- Test all relevant grouped APIs and listing/JSON/pseudo/structured consumers. `analyzeEachFunction` may retain a documented no-grouping decline. Census is hints-only unless separately changed.
- Each negative independently removes one premise. Each listed mutation must compile, be rebuilt, and fail its targeted assertion. Restore and rebuild before green. No tests or fixtures were executed during this planning task.
- Use the original integration gate and existing validation checkout only. Update readiness/status with measured scope when implementation lands. No readiness percentage follows from these sprint counts.

## Recommended sprints

### 1. E10-a: qualify error-runtime helpers

- Axis: soundness. Size S. Confidence high in the source risk, medium in emitted reproducer shape. Dependencies: none.
- Compiler rule: willThrow reads the untyped error channel; typed hooks take value/type/witness and may invoke callbacks (`C/stdlib/public/runtime/ErrorObjectCommon.cpp:48-98`). allocError returns a box/payload pair (`ErrorObject.mm:245-293`).
- Change site: replace helper prefixes at `DC/Disassembler.swift:12939-12942,12958-12982` with exact provider/body facts using `RuntimeFunctionReference` and decoded stub/fixup evidence.
- Fixture: `func forward(_ e: any Error) throws { throw e }`, paired with an authored veneer calling a returning same-prefix local/imported helper before returning normally. True behavior differs despite spelling.
- Expected: genuine `throw arg0` stays. Spoof-derived throw becomes unresolved, never a fabricated source throw.
- Negatives: wrong provider, weak/flat lookup, mismatched stub/fixup, local `swift_willThrowLookalike` and allocError-like names.
- Mutations: re-enable prefix match; skip provider check; skip decoded-stub match, independently.

### 2. E10-b: make willThrow evidence path-local

- Axis soundness. Size S/M. Confidence high. Dependencies E10-a.
- Compiler rule: hook emission belongs to the throwing edge (`C/lib/SILGen/SILGenStmt.cpp:1714-1726`); the normal/error PHIs are separate (`C/lib/IRGen/IRGenSIL.cpp:4130-4146`).
- Change site: `willThrowErrors` and `isThrownError` in `DC/Disassembler.swift:12958-12982`; consume channel-version/dominance evidence, not a function-wide value list.
- Fixture: `func choose(_ b: Bool, _ e: any Error) throws -> Int { if b { throw e }; return 7 }`, with an ABI-authored join control where only one path observes a possibly-null physical value at the hook.
- Expected: throw only on the proven edge; the other edge returns 7 or stays unresolved if physical evidence is opaque.
- Negatives: hook on sibling path, overwritten channel, unknown incoming edge, equal-looking unknown values.
- Mutations: union hook values at joins; ignore intervening overwrite; ignore dominance separately.

### 3. E05-a: keep shared cleanup before throw

- Axis soundness. Size M. Confidence high. Dependencies E10-a/b where hook evidence is used.
- Compiler rule: catch/throw paths carry owned values and cleanup scope (`C/lib/SILGen/SILGenStmt.cpp:1418-1436`); outcome PHIs do not authorize deleting shared work (`C/lib/IRGen/IRGenSIL.cpp:4130-4146`).
- Change site: `mergedThrowEnds` at `DC/Disassembler.swift:12986-13013` and `thenThrows` rendering in `DC/Pseudo.swift:114-129`/`DC/Structurer.swift:554-571`.
- Fixture: `func f(_ b: Bool) throws -> Int { defer { mark(9) }; if b { throw E.bad }; return 3 }`. Add an observable shared-call/store epilogue reduction if optimization does not merge this source.
- Expected: no `throw ?` before `mark(9)` or its actual cleanup. Duplicate the proven cleanup per outcome if necessary, or decline outcome restructuring.
- Negatives: effectful deinit, unknown epilogue call, predecessor with another successor, opaque incoming edge.
- Mutations: remove cleanup-order gate; treat unknown call as pure; end predecessor unconditionally.

### 4. E03-a: require a proven direct typed-error carrier

- Axis soundness. Size S/M. Confidence high. Dependencies none; preserve the published five-word guard.
- Compiler rule: either indirect SIL result, indirect native success or indirect error schema forces error storage (`C/lib/IRGen/GenCall.cpp:2107-2122`). Inactive results can be undef (`C/lib/IRGen/IRGenSIL.cpp:4724-4751`).
- Change site: enum naming at `DC/Disassembler.swift:13767-13771`, using positive carrier eligibility rather than only `typedErrorX0IsInactive`.
- Fixture: `func f(_ b: Bool) throws(E) -> Big { if b { throw .bad }; return Big(...) }`, plus a different indirect success shape and an async equivalent. Poison inactive X0 with another valid case tag in matched authored veneers.
- Expected: unsupported carriers render `throw ?` regardless of X0 poison; known direct controls retain their names.
- Negatives: resilient/generic results, indirect error, empty payload, async roles and unsupported specialization.
- Mutations: admit unproved X0; remove indirect-success exclusion; accidentally reuse sync eligibility for async.

### 5. E07-b: retain trapping-tail outcome uncertainty

- Axis soundness. Size S/M. Confidence high in missing premise. Dependencies none.
- Compiler rule: unreachable and normal return are different (`C/lib/IRGen/IRGenSIL.cpp:4496-4522`). A machine tail transfers execution, not a promise of success.
- Change site: passthrough-tail admission `DC/Disassembler.swift:9549-9558` and `DC/Structurer.swift:730-743`. Add an explicit return-outcome requirement; preservation of X0 and stack-only writes is insufficient.
- Fixture: `func guardValue(_ x: Int) -> Int { precondition(x != 0); return x }`, with wrappers/merged tail body, plus a pure passthrough control.
- Expected: a possibly trapping body remains a call/tail transfer or exposes its guard, not unconditional `return arg0` with the trap erased.
- Negatives: BRK path, infinite loop, unknown terminal, mixed return/trap, interior branch. Pure RET control remains valid.
- Mutations: drop terminal-outcome check; classify all no-result-write bodies as returns; discard trap edge.

### 6. E07-a: propagate a callee's no-success result

- Axis soundness. Size M. Confidence medium until reduction is compiled. Dependencies E07-b.
- Compiler rule: uninhabited success eliminates normal values (`C/lib/SIL/IR/SILType.cpp:735-742`), but a throwing Never function can still exit through error.
- Change site: shared call outcome facts, `DC/FunctionCFG.swift:74-97,144-157`, return binding and structurer sink handling. Keep `NeverThrowingSpecialization` separate.
- Fixture: `func stop(_ b: Bool) throws -> Never { if b { throw E.bad }; fatalError() }`; callers with do/catch. Add `func ordinary() throws(Never) -> Int { 17 }` as the opposite control.
- Expected: no success result or normal successor from `stop`; catch remains reachable. `ordinary` still returns 17.
- Negatives: unknown/imported declaration, spoofed symbol, returning target, throws(Never) mistaken for result Never.
- Mutations: conflate the two Never roles; leave a normal successor; remove the error successor.

### 7. A02-a: stop entry-slot seeds at unproved child effects

- Axis soundness. Size S/M. Confidence medium/high. Dependencies none.
- Compiler rule: Parent is a real pointer, and contexts may reside in caller frames (`C/include/swift/ABI/Task.h:1036-1054`; `C/lib/IRGen/GenCall.cpp:128-142`).
- Change site: `DC/Disassembler.swift:2707-2782` and terminal exclusions in `DC/AsyncContextEscapes.swift:45-52`. Before broadcasting existing entry facts, require the relevant child/transfer write-effect proof or decline the affected slot.
- Fixture: Swift parent stores 7, awaits an authored native child that follows Parent and writes 11, then consumes the slot. Native valid-boundary harness proves 11. Pair a child that cannot reach the word.
- Expected: never stale 7. Unknown child effects decline; independently proved harmless body may retain the existing seed.
- Negatives: saved ancestor pointer published earlier, partial/overlapping write, repaired header, retired child with durable alias, unresolved child.
- Mutations: bypass terminal-effect check; clear historical reach on child death; ignore byte overlap.

### 8. A08-a: qualify rendered runtime-hop roles

- Axis soundness. Size S/M. Confidence high. Dependencies exact reference machinery already exists.
- Compiler rule: actual switch receives context, resume and executor (`C/stdlib/public/Concurrency/Actor.cpp:2593-2628`); names do not establish that protocol.
- Change site: `DC/AsyncFuncletIndex.swift:317-333,650-653,1041-1048` and `DC/Disassembler.swift:2644-2654`. Keep structural candidates but require qualified identity before semantic hop/wait/context-role facts.
- Fixture: ordinary `await Task.yield()` and `@MainActor` await; same instruction-shaped transfer to a returning foreign/local `swift_task_switch` lookalike.
- Expected: real supported import retains hop syntax; spoof remains raw/unresolved, without claimed continuation ABI.
- Negatives: weak/flat imports, different provider, unproved forwarder, wrong continuation or context role. No scalar seeding is added.
- Mutations: name-only admission; ignore terminal forwarding effects; apply wait resume register to wrong runtime.

### 9. E12-a: retain exact runtime terminal attributes

- Axis soundness. Size S. Confidence high. Dependencies provider identity already available.
- Compiler rule: unexpectedError is NoReturn+NoUnwind, willThrow is returning Void (`C/include/swift/Runtime/RuntimeFunctions.def:251-272`); WillReturn is independent (`C/lib/IRGen/IRGenModule.cpp:800-810`).
- Change site: `Tools/runtime-signatures.py:20-62`, generated signature representation and bound call fact. One behavior: a selected declaration retains its outcome attributes, not just `v`.
- Fixture: `func forced() { let _ = try! fail() }`, with known returning-void hook/control and a returning same-spelled shadow provider.
- Expected: rendering unchanged in this fact-producing commit; exact terminal metadata distinguishes the three calls and remains absent for shadow provider.
- Negatives: unavailable provider/runtime family, unknown attributes/convention, nonreturning-but-unwinding contract.
- Mutations: derive NoReturn from Void; omit provider; collapse NoUnwind and NoReturn.

### 10. E12-b: cut only proven normal continuations

- Axis soundness. Size M. Confidence high. Dependencies E12-a.
- Compiler rule: compiler unreachable is not a normal return (`C/lib/IRGen/IRGenSIL.cpp:4496-4522`); runtime terminal attributes have separate meanings.
- Change site: `DC/FunctionCFG.swift:74-97,144-157`, tracer reachability and both renderers. Feed the same typed terminal fact to all consumers.
- Fixture: failing try! and imported noreturn call followed by authored unreachable marker bytes; returning-void control executes `mark(2)`.
- Expected: terminal call has no fabricated subsequent success result/effect. Returning control preserves mark(2). Preserve possible unwind when contract allows it.
- Negatives: returning shadow, void callback, foreign unwind, unknown target.
- Mutations: retain fallthrough after terminal; cut returning void; erase unwind independently.

### 11. E10-c: render a proved untyped error value without requiring its hook

- Axis completeness. Size S/M. Confidence high. Dependencies E10-a/b. Existing full-width CBZ/CBNZ proof covers the first slice. Compare-based rethrows wait for E01-a, and fresh call-error tokens wait for E02-a.
- Compiler rule: untyped throw stores its object in the error slot (`C/lib/IRGen/IRGenSIL.cpp:4742-4751`), independently of whether a debugger hook is present.
- Change site: `DC/Disassembler.swift:13772-13779` and exit-error value provenance. Existing direct parameter case is already implemented.
- Fixture: `func stored(_ e: any Error) throws { let saved = e; throw saved }`; `func relay() throws -> Int { try provider() }` with split error exit and no hook on relay.
- Expected: `throw ?` becomes `throw savedError` or the proven error token on that edge. Do not label an allocation box itself as the source error payload.
- Negatives: merged success/error, unknown spill, escaped slot, box/payload confusion.
- Mutations: remove provenance; select success X0; require a hook again.

### 12. A05-a: recover a suspension-free async scalar return

- Axis completeness. Size S/M. Confidence medium/high. Dependencies A08-a only if a runtime transfer participates; no hop-memory proof.
- Compiler rule: ordinary emitAsyncReturn loads ResumeParent and passes the current context plus native results (`C/lib/IRGen/GenCall.cpp:6664-6694`), unlike the runtime base helper's Parent projection.
- Change site: `DC/Disassembler.swift:9535-9575`, tracer context/spill proof. Reuse `AsyncIsolation.constant` evidence instead of adding a second near-identical oracle.
- Fixture: `@inline(never) func constant() async -> Int { 17 }`. True result 17. `T/AsyncIsolationArgumentTests.swift:46-53` already observes raw exit 17 while source return declines.
- Expected: `return ?` becomes `return 17` only after exact context/ResumeParent proof.
- Negatives: wrong header word, unproved context reload, changed continuation, indirect/multiword result.
- Mutations: remove spill association; swap Parent/Resume; bypass result-bank eligibility.

### 13. E01-a: prove compare-plus-branch error outcomes

- Axis completeness. Size S/M. Confidence high. Dependencies E10-a for helper-derived nonzero facts.
- Compiler rule: try_apply compares the full error carrier to null and creates separate destinations (`C/lib/IRGen/IRGenSIL.cpp:4098-4133`).
- Change site: `DC/SwiftErrorExitProof.swift:47-85`; add exact CMP/SUBS-to-zero plus EQ/NE edges, keyed to the current channel definition.
- Fixture: `func wrapper(_ x: Int) throws -> Int { let y = try provider(x); return y &+ 1 }`, plus authored full-width compare, copy and restore shapes.
- Expected: unresolved success exit becomes `return (result + 1)` on the proven zero edge. Payload can remain unknown on throw.
- Negatives: W-width check with nonzero high bits, intervening flag setter/channel write, unknown predecessor or indirect ingress.
- Mutations: ignore comparison width; read stale flags; refine both successors as zero.

### 14. E02-a: attach a versioned untyped error token to a call

- Axis completeness. Size M. Confidence medium/high. Dependencies E01-a.
- Compiler rule: each try_apply load belongs to one call and is reset after observation (`C/lib/IRGen/IRGenSIL.cpp:4086-4114,4190-4195`).
- Change site: `DC/ValueTracking.swift:2311-2331`, shared call facts and structurer X21 walk. Unknown throwing-call output becomes a fresh error-channel token, never an inherited literal.
- Fixture: two sequential do/catch calls to separately compiled plain-named Swift providers with distinct error objects. True second catch observes only provider two.
- Expected: raw/unknown catch operand can name `error(call2)`, with correct branch and release. Do not infer an exact error payload.
- Negatives: unknown ABI (not merely unknown body), callee-saved scratch X21, system C call, unresolved channel owner.
- Mutations: reuse first token; preserve armed zero; omit invalidation in only the structurer.

### 15. A01-a: share bounded region dependency loading

- Axis completeness. Size M. Confidence high. Dependencies none; required before production multi-funclet recovery.
- Compiler rule: await analysis needs the callee/resume projection (`C/lib/IRGen/GenCall.cpp:3185-3214`; `C/lib/IRGen/GenFunc.cpp:2967-3006`). This commit closes API dependency parity, not a new ABI convention.
- Change site: streaming `DC/Disassembler.swift:1151-1174`, array/filter `:1833-1866`, and third chain caller at `:1566`.
- Fixture: ordinary two-function await with a header helper outside a resume-only filter. Reuse reduced existing async fixture.
- Expected: same recovered ownership/declines across entry-filter, resume-filter, full array and stream. Dependency bodies are not emitted as unrelated functions.
- Negatives: missing/truncated helper, dependency-budget exhaustion, unsupported dyld provider and hints-only census.
- Mutations: feed filtered-only map; emit dependencies; use incomplete load as complete proof.

### 16. A05-b: recover nonsending formal locations only from an independent prefix proof

- Axis completeness. Size M. Confidence medium. Dependencies bounded callable/boundary evidence; no name-only fallback.
- Compiler rule: nonsending inserts an implicit leading actor, including some closures (`C/lib/SIL/IR/SILFunctionType.cpp:1969-1991`); IRGen locates/masks the applied implicit argument (`IRGenSIL.cpp:3954-3964`).
- Change site: async entry projection `DC/Disassembler.swift:2576-2584`, outgoing async consensus layout, existing isolation oracle.
- Fixture: `nonisolated(nonsending) func order(_ a: Int, _ b: Int) async -> Int { a &* 10 &+ b }`, paired @concurrent compilation under the same source name. Add a closed call whose lowered actor/formal origins independently establish prefix.
- Expected: qualified call/entry maps correct GP words; ambiguous public entries remain `?`. FP/self controls stay unchanged.
- Negatives: same symbol from other mode, open callers, closure abstraction, nine-word stack shift.
- Mutations: choose prefix from name; ignore actor words; inherit parent parameters into resume.

### 17. E03-b: map one direct typed-error payload from the combined schema

- Axis completeness. Size M. Confidence high in rule, medium in implementation scope. Dependencies E03-a and ordered boundary pieces.
- Compiler rule: combined schema skips FP success pieces while pairing integer/error pieces, widening only paired pieces (`C/lib/IRGen/GenCall.cpp:430-499`).
- Change site: typed throw projection `DC/Disassembler.swift:13767-13771`, call/exit lane facts. Start with nongeneric fixed-layout error and known success schema.
- Fixture: `enum E: Error { case a, b, c }; func f(_ b: Bool) throws(E) -> (Double, UInt64) { if b { throw .c }; return (2.5, 7003) }`. Include empty error payload and a two-GP success control.
- Expected: prove `.c` from its actual mapped error piece, never the FP aggregate index or inactive success bits.
- Negatives: indirect success/error, resilient enum, missing shape, conflicting type evidence.
- Mutations: assume aggregate index equals GP number; consume inactive lane; ignore empty schema.

### 18. E04-a: recover a fixed typed-error buffer on its throw edge

- Axis completeness. Size M. Confidence medium. Dependencies E03-a, ordered hidden-buffer roles and byte initialization.
- Compiler rule: error payload pointer follows the error flag in IR signature, before witness trailers; native-indirect success also forces it (`C/lib/IRGen/GenCall.cpp:2107-2130`). Load/take is error-edge-only (`IRGenSIL.cpp:4159-4168`).
- Change site: argument/result layout and typed exit projection in `DC/Disassembler.swift`; reuse qualified memory rather than `IndirectResults` X8 ownership.
- Fixture: five-word `Big` result with tiny E error, separate caller/provider and distinct success/error storage. Native failure cases vary error tags while X0 is poisoned.
- Expected: `throw ?` becomes the buffer's proved `E.case`; success remains from its own buffer.
- Negatives: swapped/interior pointer, escape, partial initialization, success-only write, resilient layout.
- Mutations: use X8 as error; drop buffer identity; admit initialization from wrong edge.

### 19. E05-b: retain correlated outcome through a merged select

- Axis completeness. Size M. Confidence medium. Dependencies E03-b/E04-a as applicable, E05-a.
- Compiler rule: result/error interpretations are exclusive and inactive lanes are undef (`C/lib/IRGen/IRGenSIL.cpp:4724-4751`; `C/lib/IRGen/GenCall.cpp:6788-6798`).
- Change site: `DC/ValueTracking.swift` exit predecessor/select facts; `DC/Disassembler.swift:12994-13013`. Publish a conditional exit fact, not separate independent flag/value joins.
- Fixture: `func forward(_ x: Int) throws(E) -> Int { try pick(x) &+ 1 }` with optimized CSEL; existing `typedForward` is the baseline decline.
- Expected: `machine_return()` can become equivalent conditional success/throw with cleanup ordered. Keep payload unknown if its correlation is unproved.
- Negatives: mismatched select conditions, intervening flag setter, extra predecessor, two call origins.
- Mutations: join flag/value independently; invert selected edge; bypass cleanup order.

### 20. A05-c: project a two-GP awaited result

- Axis completeness. Size M. Confidence medium/high. Dependencies ordered native result pieces, A01-a.
- Compiler rule: direct native components become continuation parameters (`C/lib/IRGen/GenCall.cpp:2239-2245,2439-2443`).
- Change site: replace one-register-only `awaitedResultRegister` with an additional typed result-piece query (`DC/Disassembler.swift:2610-2635`); do not broaden the old scalar query.
- Fixture: `struct Pair { var a, b: UInt64 }; func pair() async -> Pair { Pair(a: 19, b: 71) }; func use() async { let p = await pair(); sink(Int(p.b)) }`. Keep consumer before any unproved hop or carry.
- Expected: `sink(?)` becomes `sink(awaited1.b)` in the qualified resume, without claiming Pair from X0 alone.
- Negatives: Int? tag, three/five pieces, generic closure/by-address result, shared producer mismatch.
- Mutations: swap X0/X1 projections; reconstruct whole pair from X0; omit origin check.

### 21. A05-d: project a mixed-bank awaited result

- Axis completeness. Size M. Confidence medium. Dependencies A05-c and ordered GP/FP layout.
- Compiler rule: native component enumeration preserves type order (`C/lib/IRGen/GenCall.cpp:2239-2245,2439-2443`), while banks allocate independently.
- Change site: await result-piece facts, FP precision metadata and consumer rendering.
- Fixture: `struct Mixed { var n: UInt64; var d: Double }; func mixed() async -> Mixed { Mixed(n: 71, d: 2.5) }`; consume n and d independently before an unsupported carry.
- Expected: correct `awaited1.n`/`.d` pieces instead of unknown or a fabricated one-register whole value.
- Negatives: Float16 dirty upper bits, reordered fields, indirect threshold, typed-error overlap.
- Mutations: use one shared register counter; erase FP width; swap source field mapping.

### 22. A05-e: name a by-address awaited result after proven initialization

- Axis completeness. Size M. Confidence medium. Dependencies ordered result-buffer roles, initialized-byte facts, A01-a.
- Compiler rule: async indirect success buffers precede formals and sret is disabled (`C/lib/IRGen/GenCall.cpp:2282-2302`); a generic closure can retain indirect abstraction.
- Change site: async entry/call layout, result-buffer load projection, `DC/IndirectResults.swift:26-38` stays ordinary-X8-only.
- Fixture: `func big() async -> Big { ... }; func use() async { sink(Int(await big().b)) }`; separate generic identity provider as a negative first.
- Expected: the actual initialized buffer load names `awaited1.b`. Never seed X0 as Big or assume X8.
- Negatives: wrong buffer, incomplete write, escaped output, closure abstraction, unsupported generic/resilient schema.
- Mutations: use sync sret placement; omit byte coverage; read buffer before success completion.

### 23. E09-a: separate direct typed outcomes across an await

- Axis completeness. Size M. Confidence medium/high. Dependencies E03-b, E01-a, A01-a; no cross-hop value proof implied.
- Compiler rule: continuation error/flag uses SwiftSelf, with combined direct pieces (`C/lib/IRGen/GenCall.cpp:2188-2230,2382-2429`; `IRGenSIL.cpp:4764-4796`).
- Change site: `DC/Disassembler.swift:2614-2621,12895-12946`; introduce success-only/error-only seeds after guard, not at merged entry.
- Fixture: reuse `F/typedthrowsawait.swift:4-21`, where success is x+100 and error.raw is x*7, then catch adds 1000.
- Expected: correct distinct `onValue(success)` and `onError(error.raw + 1000)` tokens; never awaited-success on the error edge.
- Negatives: entry X20=self, shared resume from two callees, narrow guard, changed producer/header.
- Mutations: seed X0 before guard; read X21 instead of X20; merge producer origins.

### 24. E09-b: carry an indirect typed error through await

- Axis completeness. Size M/L. Confidence medium. Dependencies E04-a, A05-e, E09-a.
- Compiler rule: async typed-error pointer appears before closure context and witness trailers (`C/lib/IRGen/GenCall.cpp:2253-2329,3231-3286`); throw_addr returns only the flag (`IRGenSIL.cpp:4813-4850`).
- Change site: async ordered signature roles and error-buffer outcome facts.
- Fixture: `func f() async throws(LargeError) -> Big`, caller catches and consumes one field. Use fixed layout first, then a separate resilient negative.
- Expected: buffer-derived error field is available only on error resume. No change from reading X0 poison.
- Negatives: swapped success/error buffer, thick context slot, witness trailer, incomplete write, escape.
- Mutations: place error after context; seed success buffer on error; drop storage identity.

### 25. A07-a: read a successful Task.value result buffer

- Axis completeness. Size M. Confidence medium/high. Dependencies A08-a, initialized-byte/result-buffer roles, A01-a.
- Compiler rule: future_wait copies the result into the explicit buffer before resume; throwing wait success/error are separate (`C/stdlib/public/Concurrency/Task.cpp:1434-1528`).
- Change site: runtime operation effects and buffer-result projection; keep `DC/AsyncFuncletIndex.swift:317-323` as indexing only.
- Fixture: `func use(_ t: Task<Int, Never>) async { sink(await t.value &+ 6) }`, from `F/awaitresults.swift:35`. Native drivers exercise completed and pending futures.
- Expected: `sink(?)` becomes `sink((taskValue1 + 6))`, where the token denotes the completed task result, not a guessed child constant.
- Negatives: wrong task/buffer, throwing error edge, concurrent external buffer alias, unsupported provider.
- Mutations: use X0 return; seed before completion; conflate two task handles.

### 26. A07-b: read an async-let get result

- Axis completeness. Size M. Confidence medium/high. Dependencies A07-a and exact async-let binding/result storage association.
- Compiler rule: begin supplies result storage, get fills it before resuming; throwing get marks populated only on success (`C/lib/IRGen/GenConcurrency.cpp:303-308`; `C/stdlib/public/Concurrency/AsyncLet.cpp:182-235,247-292`).
- Change site: runtime get effect and buffer token, not closure-name X0 seeding.
- Fixture: `async let v = intResult(x); sink(await v &+ 7)` (`F/awaitresults.swift:37-45`), with both immediate and delayed child completion.
- Expected: consumer names async-let result token plus 7; child closure remains indirect where emitted.
- Negatives: two bindings with swapped buffers, child error, get before matching begin, escaped shared storage.
- Mutations: identify binding by type/name only; use X0; mark initialized on error.

### 27. A04-a: preserve one owner slot across an exact ordinary awaited body

- Axis completeness. Size M. Confidence medium. Dependencies A02-a, A01-a, exact relevant memory effects and context/return association.
- Compiler rule: ordinary await allocates a child, returns through its ResumeParent and then deallocates that child (`C/lib/IRGen/GenCall.cpp:3185-3214,6664-6694`).
- Change site: shared edge-state solver, `DC/Disassembler.swift:2665-2782`; reusable portions of WIP solver may help after review.
- Fixture: `let k = await first(); let v = await identity(4); sink(k &+ v)`, initially with a same-module, non-suspending second callee whose full body proves no access to k. Use closed ownership evidence, not arbitrary public-entry privacy.
- Expected: the first awaited token survives to the second resume instead of `?`.
- Negatives: second callee follows Parent, captures/publishes owner, opaque target, partial write, wrong child dealloc.
- Mutations: omit exact-body effect; forget Parent reach; accept wrong return/header.

### 28. A04-b: join two ordinary-await results in order

- Axis completeness. Size M. Confidence medium. Dependencies A04-a and bounded must-state fixed point.
- Compiler rule: each continuation is associated with its own callee/result operands (`C/lib/IRGen/GenCall.cpp:3290-3303,6668-6694`).
- Change site: transfer-graph solve, await origin IDs and per-edge slot seeds.
- Fixture: `let a = await first(); let b = await second(); return a &+ b`, with distinguishable results and diamond paths. Existing twoAwaits/sequence decline is the baseline.
- Expected: `return ?` becomes `return (awaited1 + awaited2)` only for proved effects and order.
- Negatives: shared continuation with different producers, incomplete predecessor, cyclic solve cap, arbitrary second callee effects.
- Mutations: replace must intersection with union; reuse first origin; publish last state on cap.

### 29. A07-c: consume an async-let result exactly once

- Axis completeness. Size M. Confidence medium. Dependencies A07-b and lifetime/initialization facts.
- Compiler rule: consume waits if necessary, then destroys the child task and removes its status record while retaining the consumed result (`C/stdlib/public/Concurrency/AsyncLet.cpp:302-329,408-451`).
- Change site: async-let runtime consume effect and storage lifetime.
- Fixture: `func f() async -> Int { async let x = child(); return await x }`, with a child-owned reference whose deinit logs a marker.
- Expected: retain result token after consume and preserve cleanup once. No fabricated task-private frame alias.
- Negatives: consume wrong binding, double consume, outstanding child, throwing consume error.
- Mutations: destroy result as finish would; leave child live forever; permit duplicate consumption.

### 30. A07-d: preserve async-let finish cancellation and destruction

- Axis completeness. Size M. Confidence medium. Dependencies A07-b, scoped callback/capture reach.
- Compiler rule: finish destroys a populated value, or cancels then waits and destroys the resulting copy (`C/stdlib/public/Concurrency/AsyncLet.cpp:334-401`).
- Change site: operation-specific finish effect; do not treat it as a harmless resume wrapper.
- Fixture: `func f() async { async let x = childWithDeinit(); mark(1) }`, with unused x and deterministic child/cancellation markers.
- Expected: visible cleanup/effect order survives; storage becomes unavailable only at matching finish completion.
- Negatives: child still writes captured user buffer, error result, finish without begin, already consumed binding.
- Mutations: omit cancel/wait; omit destruction; retire capture reach at finish entry rather than completion.

### 31. A07-e: recover immediate continuation completion

- Axis completeness. Size M. Confidence medium/high. Dependencies A08-a, result-buffer/continuation identity.
- Compiler rule: init initializes synchronization and task resume pair; completion before await marks Resumed and await resumes inline (`C/stdlib/public/Concurrency/Task.cpp:1611-1678,1773-1790`; `C/lib/IRGen/IRGenSIL.cpp:9015-9038`).
- Change site: continuation init/await/resume effect consumer. Existing ownershipOnly edge is not the completion event.
- Fixture: `let x: Int = await withCheckedContinuation { c in c.resume(returning: 23) }; sink(x)`.
- Expected: initialized result token feeds sink; init alone never seeds a result or claims a suspension.
- Negatives: wrong continuation, no resume, duplicate resume, error alternative, forced executor switch without contract.
- Mutations: seed at init; skip result store; confuse caller context and continuation context.

### 32. A07-f: join delayed continuation completion with the inline case

- Axis completeness. Size M. Confidence medium. Dependencies A07-e, callback capture and initialization order.
- Compiler rule: Pending/Awaited synchronization establishes resume publication; late completion enqueues on ResumeToExecutor (`C/stdlib/public/Concurrency/Task.cpp:1712-1758,1761-1806`).
- Change site: continuation protocol state and resume joins.
- Fixture: same continuation source with a gated callback, run once completion-first and once await-first. Synchronization is deterministic, not a sleep.
- Expected: both paths expose the same result identity only after initialization, with callback effects retained.
- Negatives: externally writable buffer, unaccounted callback, different continuation, incomplete alternative.
- Mutations: ignore one ordering; drop captured-writer facts; seed before release/acquire completion.

### 33. A07-g: distinguish group-next nil, value and error

- Axis completeness. Size M. Confidence medium. Dependencies A07-a, Optional layout and outcome facts.
- Compiler rule: next fills Optional success with tag zero, empty with tag one, or an error (`C/stdlib/public/Concurrency/TaskGroup.cpp:1267-1295,1791-1838`).
- Change site: group wait-next operation/result fact and buffer loads.
- Fixture: `withTaskGroup(of: Int.self) { g in g.addTask { 31 }; sink(await g.next() ?? 7); sink(await g.next() ?? 7) }`; throwing-group error control.
- Expected: first result is a group-result token, second nil only if complete local group state proves drained. Otherwise preserve the three-way unknown, never assume nonempty.
- Negatives: concurrent offered child, open group mutation, wrong group/buffer, throwing error, cancellation.
- Mutations: drop nil tag; treat error as success; associate result with submission order.

### 34. A07-h: model group wait-all completion without an invented value

- Axis completeness. Size M. Confidence medium. Dependencies A07-g, child lifetime/capture facts.
- Compiler rule: waitAll takes bodyError and has special stored-error behavior for discarding groups (`C/stdlib/public/Concurrency/TaskGroup.cpp:2013-2095`).
- Change site: group wait-all operation and completion effects; resume operand is not next's layout.
- Fixture: `withThrowingDiscardingTaskGroup { g in g.addTask { ... }; ... }`, with success, child error and body error markers. Gate availability against actual toolchains.
- Expected: drain completion retires child writers only after completion, retains error alternative and creates no scalar result.
- Negatives: pending child, wrong group kind, body/child error precedence unknown for provider family, wrong resume operand.
- Mutations: reuse wait-next contract; retire children early; drop saved error.

### 35. E06-a: recover try? optional outcomes

- Axis completeness. Size M. Confidence medium. Dependencies E01-a, Optional/tag rules; E05-a for cleanup.
- Compiler rule: optional try redirects error to discard and emits appropriate optional/value initialization (`C/lib/SILGen/SILGenExpr.cpp:1310-1386`).
- Change site: error/outcome facts, Optional projection and structurer idiom layer.
- Fixture: `func f(_ x: Int) -> Int? { try? provider(x) }`, plus provider returning Int? to test optional flattening.
- Expected: equivalent conditional Some/None first; `try?` source spelling only if complete pattern proves it. No additional Optional nesting in modern mode.
- Negatives: ordinary sentinel branch, unrelated nil, mixed cleanup, nested Optional ambiguity.
- Mutations: flip nil tag; wrap an already-optional result again; discard success cleanup.

### 36. E06-b: preserve catch dispatch and error cleanup

- Axis completeness. Size M. Confidence medium. Dependencies E01-a, E03-b/E04-a where typed payload is used, E05-a.
- Compiler rule: do/catch creates an owned exception value and catch dispatch under cleanup scope (`C/lib/SILGen/SILGenStmt.cpp:1371-1436`).
- Change site: structurer explicit CFG/catch-region reconstruction, shared typed outcome facts.
- Fixture: `do { try provider() } catch E.a { mark(1) } catch { mark(2) }`, with a reference error lifetime log.
- Expected: retain correct dispatch, handled return versus forwarded throw, and exactly-once cleanup. Explicit equivalent CFG is sufficient before catch sugar.
- Negatives: nonexhaustive catch, foreign exception, unknown type test, shared cleanup/landing pad.
- Mutations: invert dispatch; erase final forwarding throw; duplicate release.

### 37. E06-c: distinguish forced-try trap from catch

- Axis completeness. Size S/M. Confidence high. Dependencies E12-a/b.
- Compiler rule: force-try failure ends unreachable, not return (`C/lib/SILGen/SILGenExpr.cpp:1288-1307`; `C/include/swift/Runtime/RuntimeFunctions.def:267-272`).
- Change site: outcome/terminal idiom rendering.
- Fixture: `func forced() -> Int { try! provider() }` with success/error subprocess driver.
- Expected: success result stays, failure becomes proven terminal/trap syntax without a normal return. `try!` sugar needs the complete contract.
- Negatives: ordinary fatalError call outside force-try, returning shadow helper, catch that recovers.
- Mutations: turn failure into return; classify every Void helper terminal; remove provider identity.

### 38. E08-a: forward an untyped throwing branch tail

- Axis completeness. Size M. Confidence medium. Dependencies E01-a, E02-a, E07-b and compatible success schema.
- Compiler rule: tail eligibility is checked separately from ordinary call lowering (`LLVM/llvm/lib/Target/AArch64/AArch64ISelLowering.cpp:9014-9044`), and error forwarding remains a channel contract.
- Change site: extend the bounded call+RET rule `DC/Disassembler.swift:13104-13128` to independently proved B/BR/authenticated target transfers.
- Fixture: `func forward(_ x: Int) throws -> Int { try provider(x) }`, with actual compiler-emitted tail and hand-authored valid physical control.
- Expected: raw call/unknown exit becomes `return try provider(...)` only for matched armed channel, result and frame/context roles.
- Negatives: stale nonzero error, cleanup handler, target/schema mismatch, unsupported auth.
- Mutations: ignore arming; ignore target type; use branch argument as returned value.

### 39. E08-b: forward typed errors without losing reabstraction

- Axis completeness. Size M. Confidence medium. Dependencies E03-b/E04-a, E08-a, shared boundary schema.
- Compiler rule: thunks test error separately and rebuild native direct/indirect error representation (`C/lib/IRGen/GenThunk.cpp:435-564`).
- Change site: typed tail/return forwarding with separate success/error mapping.
- Fixture: `func same(_ x: Int) throws(E) -> Int { try typed(x) }` and `func erased(_ x: Int) throws -> Int { try typed(x) }`.
- Expected: same-schema typed tail forwards conditional outcome; erased-error thunk keeps its boxing/conversion, not a fake direct X21 object.
- Negatives: buffer identity mismatch, generic abstraction change, context change, intervening cleanup.
- Mutations: erase schema compatibility; skip boxing effect; forward error flag as object.

### 40. E11-a: recover foreign integer-sentinel error policy

- Axis completeness. Size M. Confidence medium. Dependencies exact imported declaration/provider and E01/E05 outcomes.
- Compiler rule: ZeroResult and NonZeroResult consume the machine result; ZeroPreservedResult retains it (`C/include/swift/AST/ForeignErrorConvention.h:29-46`; `C/lib/SILGen/SILGenForeignError.cpp:440-455`).
- Change site: imported foreign-error boundary fact, NSError slot and result mapping.
- Fixture: separately compiled authored ObjC/C provider with NSError** and applicable importer annotations, called by Swift do/catch. Supply distinct zero/nonzero successful outputs. Verify which conventions actually emit; unsupported importer forms use authored SIL, not an invented annotation.
- Expected: equivalent sentinel CFG with correct preserved/discarded result. No assumption that every NSError parameter makes zero an error.
- Negatives: wrong parameter index, ownership, polarity, returning shadow provider.
- Mutations: invert polarity; keep a discarded result; discard ZeroPreservedResult.

### 41. E11-b: recover foreign nil-result error policy

- Axis completeness. Size S/M. Confidence medium. Dependencies E11-a infrastructure.
- Compiler rule: NilResult unwraps the imported nonoptional result and tests nil (`C/include/swift/AST/ForeignErrorConvention.h:48-51`; `C/lib/SILGen/SILGenForeignError.cpp:456-461`).
- Change site: foreign result/NSError conversion fact.
- Fixture: authored ObjC factory returning nullable object plus NSError**, imported as throwing nonoptional. Native success returns a distinct object, failure nil and error.
- Expected: success object and error branch remain separate, not an Optional result mistaken for native Swift throw.
- Negatives: legitimately nullable nonthrowing factory, wrong declaration/provider, ownership mismatch.
- Mutations: treat nil as normal object; infer throwing from selector spelling; lose error ownership.

### 42. E11-c: recover foreign nonnil-error policy

- Axis completeness. Size S/M. Confidence medium. Dependencies E11-a infrastructure.
- Compiler rule: NonNilError leaves direct results alone and tests the error slot (`C/lib/SILGen/SILGenForeignError.cpp:463-466`; `C/include/swift/AST/ForeignErrorConvention.h:53-55`).
- Change site: foreign outcome/result validity fact.
- Fixture: authored provider writes NSError on failure while returning a meaningful integer even on success. Compile Swift wrapper against the imported convention.
- Expected: branch follows the correct error out-parameter, not result-zero polarity; successful direct result remains.
- Negatives: uninitialized slot, wrong pointer, nonthrowing NSError observer, foreign EH.
- Mutations: use integer sentinel; retain pre-call zero slot after write; discard direct result.

### 43. A06-a: bind witness async code and context size to one descriptor

- Axis completeness. Size M. Confidence medium. Dependencies ordered callable representation and A08-a; no memory-preservation claim.
- Compiler rule: descriptor decoding separately authenticates/loads code and size (`C/lib/IRGen/GenCall.cpp:2650-2724`), emitted record is compact code+Int32 size (`C/lib/IRGen/GenMeta.cpp:8213-8229`).
- Change site: descriptor resolver, witness-slot lookup and `AsyncFuncletIndex` target evidence. Initial scope is a closed concrete conformance.
- Fixture: `protocol P { func f() async -> Int }; struct A: P { ... }; struct B: P { ... }; func use<T: P>(_ x: T) async { sink(await x.f()) }` with separately distinguishable implementations/sizes.
- Expected: selected closed slot names its descriptor/code/size pair; an open existential still declines exact body effects.
- Negatives: alternate witness, descriptor target mismatch, indirect flag unsupported, auth discriminator mismatch.
- Mutations: combine A code with B size; select declaration as implementation; ignore fixup association.

### 44. A06-b: bind an async class override descriptor

- Axis completeness. Size M. Confidence medium. Dependencies A06-a machinery and class/vtable identity.
- Compiler rule: dynamic async pointer consumption uses selected descriptor and corresponding code authentication (`C/lib/IRGen/GenCall.cpp:2660-2722`), not a base declaration's body.
- Change site: class/vtable target resolver and async descriptor fact.
- Fixture: class Base async method plus override in Child with different result/context needs; call through Base reference.
- Expected: exact Child target only when dynamic receiver is proved. Otherwise retain common ABI without pretending Base memory effects apply.
- Negatives: open subclassing, replacement, unknown receiver, mismatched slot/auth.
- Mutations: use base vtable label as target; reuse base size; ignore receiver uncertainty.

### 45. A02-b: admit byte-accurate scoped transport state

- Axis completeness. Size M. Confidence medium. Dependencies A02-a and a real effect consumer such as A04-a. Reuse WIP only after review.
- Compiler rule: task alloc/dealloc and through-dealloc are distinct (`C/stdlib/public/Concurrency/TaskAlloc.cpp:54-71`); header words are ordinary full-width storage (`C/lib/IRGen/GenCall.cpp:128-142`).
- Change site: shared raw edge-state/lifetime domain, potentially extracting WIP `AsyncClosedCallerSolver` must/may rules rather than production-enabling its supplied model.
- Fixture: ordinary caller saving child, reloading same live pointer and consuming a scalar; authored byte-overlap and non-top-release controls.
- Expected: one additional proved local transport, with explicit decline reason on overlap/publication/lifetime mismatch. No global certificate bypass.
- Negatives: stale generation, interior release, second live allocation at site, missing CFG edge, loop cap.
- Mutations: release any known pointer; intersect publication instead of union; preserve overlapping word.

### 46. A08-b: establish one versioned switch-effect contract

- Axis completeness. Size M/L. Confidence medium/low until input admission is specified. Dependencies A08-a and exact owner/capture state.
- Compiler rule: switch may resume inline, park then assume a thread, or enqueue; preferred TaskExecutor participates (`C/stdlib/public/Concurrency/Actor.cpp:2599-2670`). Yield uses a job/executor route (`C/stdlib/public/Concurrency/Task.swift:680-695`).
- Change site: versioned runtime effect layer, separate from function-name tables and WIP UUID checks.
- Fixture: closed private scalar plus generic hop, with stock inline and deterministic queued routes. A conforming custom executor mutates an already-captured user object as a control.
- Expected: emit a scoped preservation fact only for supported provider/configuration and accounted writers; no new numeric render in this contract commit.
- Negatives: unknown/backdeployed provider, raw hook representation access, earlier published ancestor, unaccounted scheduler callback reach.
- Mutations: omit queued route; equate null serial executor with no custom scheduler; clear historical capture.

### 47. A03-a: admit one complete local caller activation

- Axis completeness. Size L. Confidence low until all executable ingress is enumerated. Dependencies A01-a, A02-b, A08-b, actual capture allocation/initialization and exact preceding call effects.
- Compiler rule: contexts may be caller-frame allocations (`C/include/swift/ABI/Task.h:1036-1039`), and native dispatch takes the actual context operand (`C/lib/IRGen/GenCall.cpp:3324-3330`). An address alone does not identify its active owner.
- Change site: a real issuer for `DC/AsyncPhysicalReplay.swift:44-85`, consuming independently derived physical/runtime facts. Either handle folded suppliers with context-sensitive activation identity or decline them. A name/UUID/expected-site list cannot issue admission.
- Fixture: closed private async caller, with a distinct captured integer and explicit task-creation path. Reuse the existing driver only if every prior imported operation is accounted for. Also inspect another valid activation of the same resume address.
- Expected: rendering remains unchanged. The complete positive receives a scoped admission fact tied to image, owner lifetime and every eligible activation; the open-entry variant does not.
- Negatives: alternate exported/rebased/materialized ingress, unresolved preceding call, wrong capture extent, reused site generation and folded return from another owner.
- Mutations: omit one ingress source; substitute the fixture's expected capture origin; key coverage only by resume address. Each must admit a counterexample and fail a targeted negative.

### 48. A03-b: recover the first authentic closed scalar across a hop

- Axis completeness. Size M once dependencies exist. Confidence medium/low. Dependencies A01-a, A02-b, A08-b, A03-a and exact nested await return/effects.
- Compiler rule: combine ordinary child return/projection with switch resumption (`C/lib/IRGen/GenCall.cpp:6664-6694`; `C/lib/IRGen/GenFunc.cpp:2967-2990`; `C/stdlib/public/Concurrency/Actor.cpp:2616-2670`).
- Change site: actual admission issuer and all three `asyncChainSlots` consumers. Do not enable the present fixture-shaped chain by supplying expected effects.
- Fixture: reuse `F/closed_await_hop.swift:7-43` only if its full activation/capture obligations can be closed. Otherwise use a smaller independently admitted native-leaf caller with the same await-plus-two consumer.
- Expected: authentic linked `sink(?)` becomes `sink((awaited1 + 2))` in both views/all claimed APIs. Standalone unknown-entry useInt remains declined.
- Negatives: saved-child publication, alternate activation, folded resume owner mismatch, byte writer, wrong dealloc/context/continuation/executor.
- Mutations: each gate separately, including dropping either inline or queued proof. A synthetic model seed is not acceptance.

### 49. A07-i: preserve cancellation callback write reach

- Axis completeness. Size M. Confidence medium. Dependencies scoped capture/lifetime effects and operation identities.
- Compiler rule: cancellation walks records and can run registered notifications (`C/stdlib/public/Concurrency/TaskStatus.cpp:1386-1407,1450-1500`). Local main also has shield/reason behavior, so version this rule.
- Change site: task/group/async-let cancellation effect summaries and MAY writer reach.
- Fixture: `withTaskCancellationHandler(operation: { ... }, onCancel: { captured.write() })`, synchronized cancellation before/after scalar store.
- Expected: preserve callback/store effects and invalidate only reachable user storage; opaque handles do not automatically expose private ancestor bytes.
- Negatives: unknown callback, already-published pointer, unsupported shielding/runtime family, incomplete record state.
- Mutations: treat cancel as no-effect; retire callback reach early; grant opaque-token ancestor projection.

### 50. A07-j: retire task-backed coroutine storage with through-dealloc

- Axis completeness. Size M. Confidence medium. Dependencies exact allocation/lifetime state and ownership-domain coroutine protocol.
- Compiler rule: Coro Async allocator uses task_alloc/task_dealloc_through and can defer reclamation (`C/include/swift/ABI/Coro.h:26-34,76-87`; `C/stdlib/public/Concurrency/TaskAlloc.cpp:54-71`).
- Change site: coroutine frame allocator effects, separate from ordinary one-object async dealloc.
- Fixture: Swift `_modify` accessor called in an async function, with a value/reference held over yield and ordered normal/throwing cleanup. Use valid SIL for a lowering source cannot force.
- Expected: storage/aliases retire at the proven suffix event, not merely when an accessor yields or one top child is deallocated.
- Negatives: unknown allocation suffix, mismatched task, nested activation, escaping yielded address.
- Mutations: substitute ordinary top-pop semantics; retain retired alias; retire ancestor outside suffix.

### 51. A05-f: select the SwiftTail call-preservation contract

- Axis completeness, with soundness gate required before positive use. Size M. Confidence high in source rule, medium in recoverable binary evidence. Dependencies machine-domain convention identity, A08-a.
- Compiler rule: local IRGen selects SwiftTail for supported async calls (`C/lib/IRGen/IRGenModule.cpp:572-580`). Release Darwin mask removes X20/X22 (`LLVM/llvm/lib/Target/AArch64/AArch64CallingConvention.td:750-754`).
- Change site: call clobber/result roles in `DC/ValueTracking.swift` and shared `CalleeRegisterSummary`, scoped to independently identified async transfers.
- Fixture: authored Swift async call chain with live self/context plus explicit physical carrier capture; matched ordinary BL control. Native oracle checks carriers, not just result text.
- Expected: unsupported convention remains declined; qualified async transfer does not inherit ordinary X20/X22 preservation.
- Negatives: source name without convention proof, ordinary Swift call, outlined helper, unsupported target/backend.
- Mutations: use ordinary mask; preserve X20 only; preserve X22 only.

### 52. A07-k: recognize one SwiftCoro activation boundary

- Axis completeness. Size M/L. Confidence medium. Dependencies ownership-domain yield/activation schema and machine convention identity.
- Compiler rule: SwiftCoro uses X23 (`LLVM/llvm/lib/Target/AArch64/AArch64CallingConvention.td:81-82`), may have a popless call (`AArch64ISelLowering.cpp:9011-9012`), and local allocator can return stack storage without popping (`C/lib/IRGen/GenCoro.cpp:899-942`).
- Change site: coroutine entry/continuation convention and frame lifetime; do not reuse async X22 rules or assume universal yield X1.
- Fixture: one fixed-layout `_modify` accessor and caller, with valid compiler SIL for YieldOnce2 if needed. First commit handles one activation/end pair, not every coroutine kind.
- Expected: distinguish partial yield/resume from semantic return, preserve yielded storage identity and exactly-once normal end.
- Negatives: unwind, repeated activation, unknown allocator, task-backed frame without suffix proof, wrong X23/auth.
- Mutations: treat yield as final return; use X22; pop stack at popless return. General unwind/multi-yield stays a later ownership sprint.

## Dependency and stopping decisions

The first ten sprints remove or isolate unsupported semantic claims. The rest recover one bounded value/outcome/protocol each. Do not hold E10/E05/E03 guards for a complete boundary rewrite. A typed fact with explicit unknown roles is enough to guard them now.

For ordinary code, I would implement E10-c, A05-a, E01-a and A01-a early, then the proven-prefix and result-piece work. Task.value and async-let get use operation-defined output buffers and can be useful before the detached-startup experiment is admitted. Two-await transport still needs exact memory effects. It is cheaper only when limited to fully analyzed bodies, not when generalized to arbitrary callees.

A03-a and A03-b are deliberately near the end. Their current missing work is not a parser tweak. If A08-b cannot state a checkable admission contract without a supplied preservation assertion, keep both parked. Do not revive the rejected runtime-oracle approach mentioned in the handoff or replace it with another bypass.

Rethrows does not require a standalone new runtime convention. Once E02/E05/E08 provide explicit forwarded outcomes, add a reduced `func apply<T>(_ body: () throws -> T) rethrows -> T { try body() }` to the forwarding oracle and only print rethrows source sugar when declaration evidence survives. Generic indirect return and closure reabstraction still need their independent boundary facts. No promise is made that machine code can recover erased source syntax.

Foreign error sprints share one descriptor but retain separate acceptance cases for all five compiler kinds. SwiftCoro here covers one activation only. Remaining yield-many/unwind and general closure/thunk result schemas belong in their owning audits; this report does not close them by naming a dependency.

## Suspected currently wrong output, not mere declines

**No new wrong-output execution was performed.** These are the candidates I believe deserve immediate reproduction or a narrowly justified guard. R establishes the faulty/missing premise; I describes the possible render.

1. **E10, helper identity.** R: prefix matching at `DC/Disassembler.swift:12960,12968,12982` can turn a returning lookalike into evidence of throwing. I: a normal RET becomes a throw, or an unrelated value becomes the thrown error. Exact provider/body evidence is missing at the semantic consumer. This is stronger than a missing payload.
2. **E10, path provenance.** R: `willThrowErrors` is function-wide (`:12958-12964`), and membership proves throw without dominance (`:12975-12976`). I: hook evidence on one branch leaks across a join. Need an ABI-authored reduction because valid source error objects are nonnull and some simple Swift sketches will not isolate this failure.
3. **E05, premature throw.** R: predecessor-end throw relocation (`:12994-13000`) plus immediate `thenThrows` rendering (`DC/Pseudo.swift:114-129`) has no epilogue-effect gate. I: deinit/defer/store effects occur after a rendered terminal throw or are lost. This matches the readiness lead at `DOC/PRODUCTION-READINESS.md:832-838`, but still needs a current emitted reproducer.
4. **E03, residual inactive-X0 enum naming.** R: the current guard is specifically five contiguous UInt64 success fields and sync ordinary entry; tests explicitly exclude async/specialized forms (`T/TypedErrorInactiveRegisterTests.swift:193-254`). Generic naming at `DC/Disassembler.swift:13767-13771` still consults X0 without a general direct error-carrier map. I: other indirect success/error shapes or async exits can name a false enum case. The published five-word authored-veneer defect itself is fixed and is not listed as currently wrong.
5. **E07, trapping tails.** R: passthrough admission asks about result writes, stack stores and X21 preservation (`DC/Disassembler.swift:9549-9558`), not possible trap/nonreturn outcomes. The summary scan records writes/callees, not a no-trap guarantee (`DC/CalleeRegisterSummary.swift:663-705,808-850`). Structured sync branch fallback also emits a return (`DC/Structurer.swift:730-743`). I: a branch into a merged trapping body becomes an unconditional plain return. General `-> Never` callees also lack propagated no-success facts. Both are source-backed, not newly reproduced here.
6. **A02, stale entry-slot value after an awaited child reaches Parent.** R: entry-proven slots are broadcast to later funclets (`DC/Disassembler.swift:2770-2782`), while recognized terminal transfer effects escape the local unknown-flow veto (`DC/AsyncContextEscapes.swift:45-52`). I: a native child or retained ancestor alias writes a different value, yet a prior scalar is rendered. Other conservative gates may already decline the simplest fixture, so do not claim an existing numeric corruption without the reduction.
7. **A08, false runtime operation semantics.** R: switch/wait/init roles remain selected by names (`DC/AsyncFuncletIndex.swift:317-333,650-653,1041-1048`), then become source hop/await facts (`DC/Disassembler.swift:2644-2654`). I: a bound foreign/local lookalike renders a hop or gets the wrong resume ABI. A false operation statement is a soundness problem even if all carried scalar values remain unknown.

Explicitly excluded from the wrong-output list: `sink(?)` after an unproved hop; two-await `return ?`; unknown nonsending GP prefixes; indirect typed errors remaining `throw ?`; raw `machine_return()` for merged outcomes; unsupported swifttail/swiftcoro; and the sealed WIP's lack of production admission. Those are completeness gaps, not evidence of false values.

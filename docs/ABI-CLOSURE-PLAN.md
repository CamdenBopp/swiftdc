# Swift ABI closure plan

Close incorrect ABI claims first, then recover the legal conventions that swiftdc currently declines. Use the compiler's ordered lowering rules throughout entry analysis, calls, results and rendering. Preserve the main `dev` checkout workflow and the existing tests. The eight audits provide the detailed inventory; the implementation batches below resolve their shared dependencies instead of adding another independent type list to each consumer.

## Scope and source versions

The target is Swift native ABI on Darwin arm64 and arm64e Mach-O, including the C, Objective-C and C++ interoperability used by Swift. The plan includes metadata, runtime calls, compiler-generated entry points, ownership, coroutines, concurrency and the machine rules those conventions require. Other architectures and non-Darwin conventions need separate target implementations.

The compiler source is [Swift 6.4.2 at 83eb1244](https://github.com/swiftlang/swift/tree/83eb12448e4323abbf81b0153dced2faff02d22f) and [LLVM and Clang at fb5f84d9](https://github.com/swiftlang/llvm-project/tree/fb5f84d903a3b4e7aea15cd5666598a46f56c833). These public releases establish mechanisms; they do not establish that every Apple internal build emits identical code. Test both installed compiler families explicitly: command-line Swift 6.4.2 (`swiftlang-6.4.2.1.9`) and Xcode Swift 6.4.0 (`swiftlang-6.4.0.34.1`). Record the resolved compiler, frontend, target, deployment target, SDK and feature flags with each oracle.

The decompiler baseline is committed `b404252`, including witness code `e639a66cc91af43e131ec4bcbbe3e53c0f808e7c`. Runtime identity, resolved transfer endpoints and the failing `useInt` acceptance test remain uncommitted work. Their successful build and focused negatives do not qualify a value-transfer implementation.

## What the evidence establishes

| Finding | Evidence status | Immediate consequence |
| --- | --- | --- |
| An ordinary super message inside an ObjC initializer becomes `self = [super description]` | Reproduced wrong statement. An own-source ARC fixture and independent linked disassembly distinguish the description and init selectors using one Super2 stub. | Fix the shared initialization predicate first; preserve the ordinary message result. |
| Generic class pack arguments prepend shape information | Compiler source and compiler IR establish the layout. The simple `typeOfA` probe currently declines. | Reject unsupported metadata layouts in every offset consumer, then implement their actual schema. Do not report a wrong rendered value from this probe. |
| Integer fields separated by `Float16` remain distinct native pieces | Swift 6.4.2 IR for `{Int16, Float16, Int16}` has `(i16, half, i16)`. The chunk-set approximation loses this ordering; the tested render currently declines. | Replace unordered register counts with ordered pieces and test the four-component direct/indirect boundary. |
| Awaited Int is lost across the following executor hop | The rebuilt acceptance test fails six expected assertions across filtered, array and streaming paths and both renderers. | Keep it red until context, lifetime, capture and runtime effects are proved; then use it as the first real transfer acceptance. |
| The existing interface oracle compares entry-register sets | It excludes several aggregate, overflow and variadic forms and does not score ordered identity, results, error outcomes or async transport. | Extend the independent oracle before declaring ABI closure. |

A source mismatch is a reproduction target, not automatically an observed wrong output. Existing fixture names identify coverage to inspect, not a new passing result. A guarded `?` is a completeness gap. A wrong value, receiver, argument, type or exit is a soundness defect.

## Coverage inventory

Each detailed audit links the pinned compiler rule, current consumer and tests, concrete implementation, negative controls and closure criteria. The IDs remain stable so a fix can close a specific item without claiming an entire area is done.

| Area | Inventory | Required coverage |
| --- | --- | --- |
| Value lowering | L01–L12 | Scalar width/view; zero-sized values; ordered aggregate pieces; tuple versus struct abstraction; resilience; enum tags and extra inhabitants; grouped results; register exhaustion and byte-accurate stack slots; SIMD/HFA/HVA; C layouts; Darwin varargs; hidden roles. |
| Generics and metadata | G01–G08 | Canonical polymorphic roles and fulfillment; archetypes and indirect results; value/protocol witnesses; existentials; resilient/opaque values; packs and value parameters; accessor responses and dynamic offsets. |
| Async | A01–A08 in this plan | Region dependencies; edge and allocation identity; inherited capture; first hop and ordinary-await transport; isolation and result/error schemas; dynamic descriptors; operation-specific waits, tasks and continuations; supported runtime paths. |
| Errors and exits | E01–E12 | Sync/async object or typed error channels; edge-correlated outputs; payload lanes and buffers; handlers; throwing tails; Never versus no-return; foreign error bridges; versioned runtime terminal contracts. |
| Closures and specialization | C01–C10 | Storage versus invocation; every SIL function representation; captures and partial apply; reabstraction; Dead and transformed formals; specialized receiver/context; key paths; differentiation and distributed entries. |
| Receivers and foreign dispatch | F01–F13 | Swift self/metatype/absent context; ownership and constructors; vtable/super/witness dispatch; ObjC declaration/selector/provider; direct IMP; super initialization; returns; C prototypes; foreign ownership and reference storage; blocks/callbacks; C++ this and nontrivial calls. |
| Ownership and coroutines | O01–O09 | Exact runtime effects; ARC/bridge handshakes; weak/unowned; borrow/consume/dependent storage; initialized/copy/take/destroy state; exclusivity; every coroutine kind, ramp/yield/continuation and cleanup; C++ lifetime. |
| Machine ABI and target | M01–M10 | Per-convention call masks and hidden registers; SIMD slices; stack/frame coordinates and outlining; exits; pointer authentication; aliases and runtime endpoint choices; bit-width semantics; ABI/deployment selection. |
| Cross-domain completion | U01–U02 | Dynamic replacement/previous implementation; foreign async completion block, error convention and Swift continuation association. |

All eight reports are complete. They identify partial implementations, safe declines and source risks; they do not establish that the listed future mechanisms already work. The separate merge review checked 269 pinned source links across 95 paths and corrected the coroutine header citation endpoint.

## Shared implementation model

Use one typed boundary description, populated only from available evidence. Keep these facts separate:

1. **Callable identity and representation:** exact symbol/descriptor/slot/provider, entry kind, native/foreign/thick/thin/block/method/witness/closure/key-path representation, target ABI and availability.
2. **Source and abstraction identity:** source parameter/result group, SIL formal and substitution level. A source argument, SIL formal and native piece can have different cardinalities.
3. **Ordered physical pieces:** role, projection path, byte offset, width, signed or FP view, bank/lane/register or stack interval, indirect address and alignment. Preserve zero-sized source positions and unknown pieces without shifting later roles.
4. **Outcome validity:** normal, error, yield, resume, unwind or no continuation. Inactive lanes are undefined; one field is not the whole multiword result.
5. **Memory and lifetime:** initialized byte ranges, allocation/owner/generation, borrow or owned scope, copies versus takes, possible aliases and historical capture. Definite values intersect at joins; possible writers and captures accumulate.
6. **Evidence and failure reason:** which declaration, compiler rule, descriptor, body or bind establishes a fact, and which missing/conflicting premise causes decline.

Implement this incrementally behind existing consumers. It is not a replacement of the entire tracer or renderer. Migrate one proved behavior at a time and keep result placement, value identity and display policy distinct. The compiler separates SIL abstraction, native expansion and target placement; follow the same separation. The [native schema and indirect-result expansion](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenCall.cpp#L677-L986), [generic fulfillment](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenProto.cpp#L215-L481), and [Clang aggregate lowering](https://github.com/swiftlang/llvm-project/blob/fb5f84d903a3b4e7aea15cd5666598a46f56c833/clang/lib/CodeGen/SwiftCallingConv.cpp#L429-L509) are the starting authority.

## Implementation batches

### 0 Pin the oracle and stop reproduced wrong output

- **V01:** Extend the compiler oracle to compare ordered source/SIL/native role mappings, not register sets. Include success/error/yield results, x8 versus ordinary output buffers, mixed banks, register overflow and exact stack bytes. Preserve each compiler/optimization/resilience configuration independently instead of dropping disagreements into one unchecked case. Report unchecked and unsupported cases with reasons.
- **S01:** Fix F07 independently. Require a proven initializer-family message and applicable receiver before initializing self. Share the predicate between tracing and rendered statements. Test ordinary super messages inside an initializer, the actual super initializer, alternate search class/metaclass, same-name foreign messenger and unknown selector. Removing the selector, receiver or provider premise must each fail a targeted test.
- **S02:** Guard the source-confirmed L02/L03/G07 mismatches before generalizing their consumers. Independently reproduce L06 nested Optional direct claims, E03 typed error projection, E10 helper identity/path provenance and F06 objc_direct inferred from absent metadata before promoting them to observed wrong-output bugs. If a current assertion cannot be justified, narrowly decline that fact while its general implementation is developed. A source-confirmed faulty premise can be guarded without first producing a wrong render. Preserve all existing tests.

### 1 Share boundary identity and ordered layout

- **B01:** Introduce the typed boundary and source-group identities, including L12 special register roles. Decode representation, entry kind, abstraction and specialization before assigning physical locations. Every consumer queries the same evidence without reparsing annotation text.
- **B02:** Implement direction-specific ordered parameter and result schemas and Darwin target allocation. Keep special roles, GP and FP banks, byte-accurate stack allocation and undefined bits explicit. Use target/feature keys so arm64e or foreign conventions cannot silently inherit unsupported defaults.
- **B03:** Unify exact declaration and provider provenance for runtime, SDK and imported foreign facts. A known name, a nonthrowing contract, a body-read mask and a memory effect prove different things. Preserve their separation. Require applicable stub/fixup/export evidence, reject conflicts and unknown variants, and state normal-loader and conforming-runtime assumptions.

These three are shared foundations, not permission to delay S01 behind a broad rewrite. A small typed fact can bridge an existing path until the complete model is ready.

### 2 Complete ordinary values and physical placement

- **P01, L01–L03:** Make zero components first-class at entry and call sites. Propagate scalar width and bank consistently. Preserve aggregate FP/vector barriers and adjacent integer coalescing. Cover following source arguments and the direct/indirect threshold with paired field orders.
- **P02, L04–L06:** Recover structured tuples and distinguish their formal abstraction from struct storage. Add enum and Optional layout with exact extra-inhabitant/tag rules. Separate layout visibility from formal transport at resilient boundaries. An uncertain direct shape must not disqualify a real result buffer.
- **P03, L08–L11:** Complete independent bank exhaustion, split pieces and natural-width stack packing. Add Swift SIMD versus C vector/HFA/HVA rules. Generate structured C/ObjC prototype layouts. Compute named stack extent before Darwin varargs, apply promotions and distinguish Swift Array varargs from C variadics and va_list.
- **P04, L05/L07 and G02:** Preserve grouped direct-result components and every indirect output role. Reconstruct a complete value only from matching producer/projection evidence. Support simultaneous direct and ordinary leading indirect results, multiple SIL outputs, x8 sret and outcome-specific buffers without confusing them with formals.

### 3 Complete generic and dynamic type evidence

- **T01, G01/G02:** Derive canonical ordered metadata, values, shape lengths and witnesses, including fulfilled requirements and indirect archetype formals/results. Feed both call and entry placement, including stack overflow and original abstraction.
- **T02, G03–G05:** Resolve witness tables and slots by descriptor/requirement identity; add value-witness invocation schemas and distinct existential container, payload, box, metadata and conformance identities. Separate a dispatch declaration from an exact implementation/body effect.
- **T03, G06/G08:** Track metadata requests/responses and state, dynamic field offsets, resilient superclass bounds and opaque result substitution. Validate separately built provider/client compatibility as private layouts change.
- **T04, G07:** Add packs and generic value parameters only after shape and dynamic-array identities are explicit. Cover empty and heterogeneous packs, same/different shapes, metadata and witness packs, nested contexts and indirect pack results. Keep unavailable feature modes version-gated and explicit.

### 4 Complete callable representations and receivers

- **R01, F01–F04:** Share receiver placement for class/value/metatype, absent or reserved context, indirect/read-only/mutating/consuming Self, specialized methods and constructor/destructor entries. A callee-saved x20 value or a body read alone does not prove nominal Self.
- **R02, C01–C08:** Distinguish callable storage from invocation ABI; track native captures, address captures, closure context, partial application, generic bindings and reabstraction through their actual entry. Apply specialization transformations to source/SIL roles, including Dead and transformed Self, before placement. Unsupported modifier trees decline the affected ABI rather than falling back to an original printed signature. C08 generic async descriptors also feed A06. A mangling hook for async removal does not establish that the pinned compiler emits that transformation; require an emitted entry oracle first.
- **R03, F05–F11:** Share one ObjC call fact through receiver/search provenance, selector, applicable declaration, target messenger, argument/result layout and ownership. Close ordinary IMP versus objc_direct, super search, nil/indirect results, C callbacks, block invoke and bridge thunks. A selector bucket or encoding alone cannot establish ARC ownership.
- **R04, F13 and C09–C10:** Add C++ member/constructor/free-call representation with this adjustment and nontrivial argument/result lifetime rules. Cover all four serialized-generic key-path accessor conventions and available autodiff/distributed generated entries. Explicitly gate compiler features and unavailable declarations instead of treating them as an ordinary thin C or Swift call.
- **U01:** Model dynamic replacement and previous implementation separately from ordinary direct body identity. A known declared ABI can survive replacement while clobber, capture and memory summaries of the original body cannot. Test separately linked replacement and prior-implementation paths with distinct results/effects, including emitted sync/async/coroutine variants and authentication schemas. Mutating the chain must expire the original exact-body refinement. The [compiler replacement emission](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenDecl.cpp#L1891-L1978) supplies the source mechanism.
- **U02:** Treat the ObjC declaration's completion-block slot, block invocation/ownership, error argument and polarity, and Swift continuation as separate contracts. Prove immediate and delayed completion, normal/error outcomes and import/export bridge direction; mutate the completion slot and sentinel polarity independently. This joins R03, X02 and A07, using [ForeignAsyncConvention](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/AST/ForeignAsyncConvention.h#L25-L80).

### 5 Complete errors and semantic exits

- **X01, E01/E02/E05/E10:** Track the error channel owner and version, full-width discriminator provenance and mutually exclusive edge outcomes. Share call preserve/define/unknown effects across tracer, CFG and renderer. Keep cleanup and shared epilogue effects in their actual order.
- **X02, E03/E04/E09:** Compute typed success/error lane maps and buffers from the real boundary schema. Separate sync x21 and async continuation x20 roles. Permit a proven throw with unknown payload; never substitute an unrelated x0 enum tag. Keep initialization valid only on the producing outcome.
- **X03, E06–E08/E11/E12:** Compose try?/catch/try!/rethrows, throwing tails, foreign NSError conventions and exact no-return runtime calls. Distinguish a Never success type, throws(Never), trap, unwind and no machine continuation. Audit `SwiftRuntimeSignatures.swift` and `Tools/runtime-signatures.py` against the selected runtime declarations, recording omissions, roles and arity separately from CFG terminal propagation. NoReturn, NoUnwind, WillReturn and ordinary returning-void are distinct. Apply versioned contracts only to the actual provider/body; historical table counts are not current measurements.

### 6 Complete ownership and machine-state prerequisites

These are prerequisites for positive value/lifetime proofs, even though they are grouped here for ownership. Physical schemas and evidence can land first. P04, R02/R03, X01/X02 and A02/A03 must consume the necessary byte-state, initialization and lifetime premises before publishing values.

- **K01, M01/M02/M10:** Select per-convention read/define/preserve contracts and target/deployment envelope. Include x8 result, x15 nest, x20 self/context, x21 error, x22 async and x23 coroutine roles. Address reach, nominal role and preserved register contents are distinct. Test ordinary, SwiftTail/SwiftError, stronger/weaker preserve and unsupported convention controls.
- **K02, M03/M04/M09:** Track exact register bit/lane and memory byte intervals, architectural zeroing, FP views/conversions and undefined high bits. Replace bounded contiguous stack-word assumptions with proved typed intervals and conservative unknown ranges. Test holes, packed narrow stack arguments, more than sixteen stack words, SIMD upper halves, W/X writes, half precision and aliased partial stores.
- **K03, M05/M06:** Share frame coordinates, call-time stack ownership, red-zone eligibility, probes, outlined inputs and LR origin. Distinguish real return, sibling/conditional tail, trap, suspend/resume and coroutine partial return. Unresolved or incomplete helper bodies cannot inherit ordinary preservation by spelling or symbol boundaries.
- **K04, M07/M08:** Preserve address identity separately from authenticated call eligibility. Prove pointer category, storage, key/modifier/discriminator and fixup association for function, witness, async/coroutine and return uses. Resolve aliases, reexports, availability-selected fallback and replacement alternatives before applying exact body/runtime effects. Use arm64e static or executable evidence with key/modifier/fixup mutations; a known slot symbol can remain visible while invocation proof declines.

- **J01, O01/O02:** Use B03 and K01 for exact symbol/provider, signature, result identity, convention and scoped effects. Gate runtime-noise removal and field-preservation on their own applicable proof. Retain/bridge identity, uniqueness Bool, block heap-copy and last release with deinit/callback effects are distinct. Do not hide observable release or autorelease ordering.
- **J02, O03/O05 and F12:** Add storage identity, extent/generation and initialized, uninitialized, moved/destroyed or unknown state. Distinguish initialize/assign/copy/take/destroy and each witness destination/source/result role. Weak/unowned native, unknown/ObjC and unsafe storage have distinct load/take/zero/trap protocols; address returns are not object returns. Test ownership and buffer state on normal/error edges, aliases, overlapping ranges and destruction callbacks.
- **J03, O04/O06:** Track borrow/consume, dependent base and scope where recoverable, including every direct/indirect/aliasable/pack/C++ parameter convention. Pair dynamic access tokens, address, flags and scratch generation with actual ends/writeback/cleanup. An access marker does not prove that the user body cannot escape memory. Source ownership erased by lowering remains unknown; compare distinct SIL with identical machine transport as a negative.
- **J04, O07/O08:** Implement the ordered ramp, yield/overflow, continuation, frame/allocator and activation protocol for legacy YieldOnce, callee-allocated YieldOnce2 and YieldMany. Distinguish yielding parameter ownership from accessor results GuaranteedAddress, Guaranteed and Inout. Cover continuation replacement, repeated/nested activation, normal end, legacy abort, new-accessor completion on throw, authentication and exactly-once cleanup. Use valid compiler SIL where source syntax is unavailable. Do not infer a universal x1 yield or apply async x22 rules to coroutine x23.
- **J05, O09:** Combine F13 foreign carrier and declaration with construction/copy/move, initialized destination, complete destructor, caller/callee cleanup and result-buffer lifetime. Native logs must distinguish trivial, nontrivial, deleted-copy and return-in-place forms and preserve arbitrary constructor/destructor effects.

### 7 Recover async values and operation-specific protocols

- **A01:** Share bounded region dependency loading across filtered, array and streaming analyses. Decode required bodies without emitting unrelated functions. Keep the hints-only census and unqualified dyld-cache effects explicit.
- **A02:** Track scoped owner/child allocation, generation, extents, live state, Parent/Resume words, exact pointer copies and inherited external capture. Byte-overlap invalidation and may-capture history survive header repair, child death and x22 reload. Prove complete relevant predecessors and reject incomplete solve/CFG/unknown target. Use raw converged witnesses, not render-enriched values.
- **A03:** Before publishing a first value, qualify the exact switch/yield/alloc/dealloc identities, resolved forwarding endpoint and scoped effects under the supported scheduler contract; broader families remain A08. Finish the real `useInt` acceptance by qualifying its nested `intResult`/yield path, exact child pointer store/reload, matching deallocation, owner restoration and local awaited-value store. At the hop prove the bound switch, same owner, exact continuation, admitted executor route and absence of an accessible writer. Independently mutate complete incoming edges, historical publication, overlapping writes, exact live deallocation and each context/continuation/executor operand. Recover `sink((awaited1 + 2))` in both renderers and every claimed API. Then support distinct -Onone/-O/-Osize dataflows without hardcoded names, offsets or instruction addresses. Keep `sequence` declining until A04 independently proves its ordinary await.
- **A04:** Extend the same per-edge proof to the second ordinary await in `sequence`. Use ordered must-state joins and bounded fixed points, separate awaited producer identities and prove each callee's relevant effect. Do not generalize a harmless runtime hop to an arbitrary awaited body.
- **A05:** Add exact ordinary/isolated/implicit-isolation formal roles, hidden generics, multiword/mixed results, direct/by-address generic returns and typed throws with separate outcomes. A source name alone cannot select a closure/thunk abstraction or isolation prefix.
- **A06:** Prove dynamic async function descriptor, code/context-size pair, class/witness slot and authenticated target association. An open target set may share a calling convention without sharing a memory-preservation contract.
- **A07:** Implement operation-specific async-let, task/group future waits, continuation init/await/resume and cancellation protocols. Cover immediate versus delayed completion, result initialization, error alternatives, joins, destruction, cancellation callbacks and concurrent captured writers. Add coroutine/task-backed allocation protocols using their own lifetime rules.
- **A08:** Version the runtime and scheduler effects. Generic serial executor operands do not exclude a preferred TaskExecutor callback. Under the documented conforming scheduler contract, opaque task/job tokens provide resumption authority, not an ancestor payload pointer; explicit native publication, raw hooks and already-captured user memory still supply writable reach. Unknown providers or unsupported paths decline only the affected effects.

## Oracle and release gates

For every new rule, keep separately compiled caller and callee fixtures with distinguishable values. Capture compiler SIL, LLVM signature and call operands, linked disassembly/bindings/metadata, and native return/side-effect observations where executable. Use Swift -Onone/-O/-Osize; C/ObjC/C++ -O0/-O2/-Os; separate library-evolution provider/client builds; stripped and symbol-rich inputs; and arm64e static/executable evidence where supported. Keep optimization-created thunks and specialization visible in the oracle instead of matching solely by source name.

Cross the representation, parameter/result convention, ownership, outcome, value shape, target, visibility and optimization axes. Use generated small shape combinations for ordered aggregates, enums, overflow and pack counts, with boundary cases and pairwise interactions. Every admitted compiler enum/flag branch needs a matrix row linked to an independent fixture or an explicit unsupported reason. Unknown future tags and malformed descriptors remain negative controls.

The finite source checklist includes every `SILFunctionTypeRepresentation` in `ExtInfo.h`, every `ParameterConvention`, `ResultConvention` and `SILCoroutineKind` in `Types.h`, metadata kinds and relevant descriptor/requirement/flag variants, target call masks and selected runtime contracts. Explicit unsupported/gated/erased rows are not supported rows. Version updates require reconciling this checklist with the new source, not silently carrying forward a coverage claim.

A change closes its item only when:

1. The independent oracle identifies the expected physical roles and observable behavior; a previously wrong or missing behavior has a reproducible baseline failure.
2. Positive tests and unsupported/conflicting/malformed negatives exercise the exact premise. Removing each independent gate produces the expected failure after a rebuild.
3. Entry, ordinary/indirect/tail call, result/projection and all applicable render/API paths agree; undefined pieces remain unknown and side effects remain present.
4. The fixture-enforced full suite passes with all previous tests retained. Absence of a required fixture fails instead of silently skipping.
5. Frozen-release corpus views, CLI matrix, SDK workloads and original five-app checks explain every output change, retain function counts/order and pass default instruction/footprint budgets.
6. The code and readiness/status record name the measured commit. One behavior lands per `(axis)` commit in main `dev`; only the original integration gate publishes it. Do not push while the preceding hosted run is live; record the new hosted result separately.

Do not mark a mechanism implemented merely because its unsafe guess was replaced with `?`. A binary that has erased its declaration, abstraction or dynamic target may not contain enough information to recover it. Such a case needs a bounded decline and a recorded reason; it remains outside demonstrated completeness. ABI closure is the explicit compiler-rule/fixture matrix, not a readiness percentage or a count of passing tests.

## Work allocation

The batch numbers group work; they are not a strictly serial dependency order. V01 and S01 can start immediately. B01/B03, target contracts K01 and bounded ownership evidence can proceed in parallel. B02 then supplies physical placement. Positive aggregate-result, closure/bridge, typed-error and async transport require their relevant K and J proofs as well as schema. J02/J03 feed storage, lifetime and capture; J04 also requires descriptor, exit and authentication evidence. A03 specifically depends on A01/A02, the relevant J/K premises and its narrow runtime effects; A04–A08 extend only after their own gates are proved.

Use the eight audit domains as owners of bounded implementation and oracle chunks. Physical layout, metadata, callable representation, foreign ABI, errors, ownership, concurrency and machine-state changes share interfaces; designate one integrator for shared Disassembler and ValueTracking hunks. Other agents prepare reviewed patches and oracle artifacts without simultaneous writes to those files. Develop in the main checkout, preserve all WIP, serialize measurements and use only the existing integration-gate checkout for validation. The initial critical path is V01 plus S01, shared boundary identity/layout and exact effect provenance, then lifetime/outcome proofs, then first async recovery and broader protocols. Independent source/oracle work can proceed alongside it.

## Detailed audits

1. [Value lowering and physical placement](research/abi-audit-2026-11-22/01-lowering.md).
2. [Generics, witnesses and metadata](research/abi-audit-2026-11-22/02-generics.md).
3. [Async ABI and runtime protocols](research/abi-audit-2026-11-22/03-async.md).
4. [Error channels and semantic exits](research/abi-audit-2026-11-22/04-errors.md).
5. [Closures, specialization and generated entries](research/abi-audit-2026-11-22/05-closures.md).
6. [Receivers and foreign dispatch](research/abi-audit-2026-11-22/06-foreign.md).
7. [Ownership and synchronous coroutines](research/abi-audit-2026-11-22/07-ownership.md).
8. [Darwin arm64 and arm64e machine ABI](research/abi-audit-2026-11-22/08-machine.md).

The [audit evidence and compiler spot checks](research/abi-audit-2026-11-22/scope-and-evidence.md), [merge review](research/abi-audit-2026-11-22/merge-review.md) and [source citation check](research/abi-audit-2026-11-22/source-citation-receipt.md) retain the distinction between executed probes and source-only findings. No readiness percentage is assigned.

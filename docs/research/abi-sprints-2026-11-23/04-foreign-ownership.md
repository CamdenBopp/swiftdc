# Foreign dispatch and ownership sprints

## Scope and evidence

Research date: 2026-11-23. Prose genre: engineering reference.

The decompiler HEAD is `ca9eef5ce2909f5f584d8270026f606c3f1b1e0e` on `dev`. The checkout contains unrelated, uncommitted async and flag work. I did not change it. I read the live files and checked the relevant changed-file passages against `git show HEAD`. All `D` and `V` line numbers below refer to committed HEAD, not the shifted working-tree lines.

The official Swift checkout is `<swift checkout>`, HEAD `1b7bd8eaf460396047c2644d1d69afb4a404b13d`, dated 2026-09-07, subject `Merge pull request #91963 from xedin/called_once+dependent-types`. It does **not** match the plan's `83eb12448e4323abbf81b0153dced2faff02d22f` pin. The pinned object is absent locally: `git diff 83eb1244... HEAD` reports `fatal: bad object`. Its working tree was clean when inspected. No fetch, checkout, compilation, test execution, decompilation, or measurement ran.

`[R]` means verified by reading current code or tests. `[I]` means an inference or proposed experiment. A test's presence is not a passing result. Every before/after below is a proposed acceptance expectation unless explicitly identified as a historical documented observation. No new wrong render was reproduced in this read-only investigation.

The classifications cover whole audit items, not just their working subsets. Counts: **0 already closed, 11 partially closed, 5 safely declined, 8 possibly wrong**. F07's original wrong-super-assignment slice is already closed, but F07 as a whole is partial. These are research classifications, not measured ABI coverage.

### Citation keys

Every key below expands to an absolute local path. `key:line` is a local file:line citation.

| Key | Absolute path |
| --- | --- |
| D | `Sources/SwiftDecompilerCore/Disassembler.swift` at decompiler HEAD |
| V | `Sources/SwiftDecompilerCore/ValueTracking.swift` at decompiler HEAD |
| P | `Sources/SwiftDecompilerCore/Pseudo.swift` |
| OM | `Sources/SwiftDecompilerCore/ObjCMetadataIndex.swift` |
| OS | `Sources/SwiftDecompilerCore/ObjCSelectors.swift` |
| OA | `Sources/SwiftDecompilerCore/ObjCArgumentABI.swift` |
| RR | `Sources/SwiftDecompilerCore/RuntimeFunctionReference.swift` |
| IR | `Sources/SwiftDecompilerCore/IndirectResults.swift` |
| CR | `Sources/SwiftDecompilerCore/CalleeRegisterSummary.swift` |
| SL | `Sources/SwiftDecompilerCore/SwiftLowering.swift` |
| RS | `Sources/SwiftDecompilerCore/SwiftRuntimeSignatures.swift` |
| VT | `Sources/SwiftDecompilerCore/VTableIndex.swift` |
| CG | `Sources/SwiftDecompilerCore/CallGraph.swift` |
| XC | `Sources/swiftdc/XrefsCommand.swift` |
| T/ | `Tests/SwiftDecompilerCoreTests/` |
| C/ | `<swift checkout>/` at the compiler HEAD above |

The source paths in the sprint entries use these keys. Implementation sites identify existing functions to extend, not permission to edit during this investigation.

### Audit-link reconciliation

The mechanisms below were re-read locally. Do not reuse the audit's numeric anchors without translation.

| Audit anchor | Current local anchor and finding |
| --- | --- |
| `GenCall.cpp:1891–1917` | `C/lib/IRGen/GenCall.cpp:1890–1919`, `hasSelfContextParameter`. Same relevant indirect/metatype/class distinction. |
| `GenCall.cpp:2020–2107` | `C/lib/IRGen/GenCall.cpp:1984–2131`. Coroutine prefix handling is at 1994–2017, normal Self/generic/context order at 2020–2095. |
| `SILFunctionType.cpp:3880–4022` | Ownership logic is now `C/lib/SIL/IR/SILFunctionType.cpp:3985–4145`. Consumed attributes, family overrides, retained/autoreleased and inner-pointer results remain distinct. |
| `Types.h:4450–4512`, `4918–4967`, `5237–5259` | Current parameter, result and coroutine enums are `C/include/swift/AST/Types.h:4520–4579`, `4977–5022`, `5293–5315`. |
| `IRGenSIL.cpp:8494–8568` | Address copy selection is `C/lib/IRGen/IRGenSIL.cpp:8700–8721`. |
| `IRGenSIL.cpp:7097–7155`, `7276–7355` | Begin/end access are `C/lib/IRGen/IRGenSIL.cpp:7180–7273`, `7334–7412`. |
| `IRGenSIL.cpp:4863–4930` | Continuation invocation is `C/lib/IRGen/IRGenSIL.cpp:4906–4960`. |
| `HeapObject.cpp:474–588`, `762–811`, `1068–1125` | Native strong operations are `C/stdlib/public/runtime/HeapObject.cpp:511–627`, checked unowned at 821–891, weak entrypoints at 1144–1187. |
| `SwiftObject.mm:676–808`, `1125–1164` | Bridge retain/release is `C/stdlib/public/runtime/SwiftObject.mm:692–779`, unknown weak at 1151–1193. |
| `RuntimeFunctions.def:215–492`, `1946–1961` | Relevant retain/release declarations are now `C/include/swift/Runtime/RuntimeFunctions.def:283–423`, access declarations at 2031–2045. The stale three-argument begin-access comment remains, but the actual declaration has four operands. |
| `IRGenModule.cpp:548` | PreserveMost mapping is `C/lib/IRGen/IRGenModule.cpp:559`. |
| `GenDecl.cpp:1891–1978` | Chain construction spans `C/lib/IRGen/GenDecl.cpp:1887–1930`; runtime replacement dispatch is 3101–3155, previous-implementation thunk 3433–3503. |
| `SILGenDestructor.cpp:103–114,226–304,733–745` | Current destroying return is `C/lib/SILGen/SILGenDestructor.cpp:214–228`, deallocating flow at 240–293, ObjC entry at 738–771. The destroying object result is not the deallocating entry's source result. |
| Clang and AArch64 target links | No Clang implementation or Objective-C runtime implementation was found inside `<swift checkout>`. The ordinary likely sibling checkout locations checked were absent. The audit's LLVM pin was not locally verified. Swift's calls into Clang establish delegation, not Clang's complete classifier. |

I cannot establish the exact textual diff from the unavailable pin. These translations report what is present locally, not a claim that the compiler releases are behaviorally identical. In particular, the current outlined-copy implementation has file-private signature/linkage handling at `C/lib/IRGen/Outlining.cpp:517–529`. That is another reason not to assume an outlined helper's name fixes its complete signature.

`Exclusivity.cpp` is only 141 lines in this checkout. It contains conflict reporting and TLS hooks, including a fatal conflict at `C/stdlib/public/runtime/Exclusivity.cpp:65–117`. I did not invent a begin/end implementation at the audit's old offsets. The public scratch contract and IRGen's actual calls are the local authority used here.

## Every audit item at current HEAD

| Item | Classification | Current swiftdc evidence | Compiler/runtime rule re-read locally | Remaining scope |
| --- | --- | --- | --- | --- |
| F01 | Possibly wrong | [R] D:9810–9888 accepts address-shaped x20 for some external value members. The in-image positive-read veto is conditional on a body summary at D:9840–9842. T/ImportedReceiverTests.swift:30–65 and 69–138 cover several imported and whole-value controls. | [R] C/lib/IRGen/GenCall.cpp:1890–1919,2020–2095 selects context Self from convention and representation, not address shape. C/docs/ABI/CallingConvention.rst:574–596 distinguishes class/value/metatype roles. | [I] Address-shaped parked x20 can still receive a nominal Self label without sufficient external ABI evidence. General mixed-bank, absent and reserved contexts remain partial. |
| F02 | Partially closed | [R] SL:164–223 distinguishes complete direct footprints from indirect carriers. D's `signatureSpecializationRewritesSelf` guards some changed Self entries. T/ImportedReceiverTests.swift:141–149 preserves the four-word boundary. | [R] C/include/swift/AST/Types.h:4520–4579 and C/lib/SIL/IR/SILFunctionType.cpp:1475–1545 separate ownership and carrier selection. | Recover read-only indirect Self and entry-specific specialization without treating every pointer as inout. Erased ownership must remain unknown. |
| F03 | Partially closed | [R] D:6122–6157 and P:600–627 distinguish several instance and thin-metatype cases. T/SelfRegisterTests.swift:10–26 covers calls/tails, not the full constructor lifecycle. | [R] C/lib/SILGen/SILGenConstructor.cpp:975–1091 separates metatype allocator, allocated object, initializer call and returned initialized object. | Nonallocating initializer entries, allocator metatype facts, destruction kinds and self-returning call results need separate qualification. |
| F04 | Possibly wrong | [R] VT:89–96,144–166 names own slots. D:4597–4608 turns virtual slots into an address. D:9462–9473 uses a target body's unwritten-result summary for tail passthrough without excluding virtual dispatch. CG:14–17 already calls such an edge only possible. | [R] C/lib/IRGen/GenClass.cpp:3122–3204 and C/lib/IRGen/IRGenSIL.cpp:8807–8897 distinguish metadata dispatch, direct implementation and resilient super lookup. | [I] A subclass override can invalidate base-body tail passthrough. Declared ABI may survive dynamic selection, exact-body effects do not. |
| F05 | Possibly wrong | [R] OS:124–135 names a selector stub after decoding only its first two instructions. P:357–377 interprets messenger spelling. OM:710–720 requires own-class declaration and selector-wide parameter agreement. T/ObjCOutgoingABITests.swift:26–53 covers conflicts. | [R] C/lib/IRGen/GenObjC.cpp:1281–1382 delegates encoding to Clang and includes self/_cmd. C/lib/IRGen/GenCall.cpp:1548–1666 separately arranges physical foreign signatures. | [I] Selector-load shape or same-name foreign messenger can acquire send semantics without a complete dispatcher proof. Declaration ancestry/protocol evidence remains incomplete. |
| F06 | Possibly wrong | [R] D:6444–6447 classifies a symbol as objc_direct from a missing method binding and a matching local class name. T/ObjCDirectTests.swift:5–28 exercises positives only. | [R] C/lib/IRGen/GenCall.cpp:1575–1584 and C/lib/IRGen/GenObjC.cpp:865–868 omit _cmd only for a known direct method. | Missing or unavailable metadata is not direct-method evidence. A normal IMP keeps self and SEL even when called by address. |
| F07 | Partially closed | [R] D:6482–6533 proves complete post-call adoption. T/ObjCSuperInitializerTests.swift:12–96 explicitly keeps O0 spilled adoption declined. The original bug shipped fixed in `d8a00e0`/`72c9879`. | [R] C/lib/IRGen/GenObjC.cpp:714–766,796–849 constructs receiver/search pairs and selects peer/Super2 entrypoints. | O0 ARC locals, storeStrong-mediated adoption, legacy Super and class/metaclass transport. Do not reimplement the fixed selector/provider/owner proof. |
| F08 | Partially closed | [R] OA:185–193 classifies bounded aggregates. OM:736–761 handles scalar FP agreement and aggregate vetoes. T/ObjCReturnBankTests.swift:17–38 keeps rect results `?`. T/ObjCTailReturnTests.swift:74–108 covers known ARC tails. | [R] C/lib/IRGen/SwiftTargetInfo.cpp:60–65 says arm64 has no special messenger variants. C/lib/IRGen/GenObjC.cpp:798–830 selects stret only if the target asks. | Whole GP/HFA/x8 results, target-specific variants and machine-proved nil-buffer behavior. Clang's complete nil-result rule is unavailable locally. |
| F09 | Partially closed | [R] RR:61–81 and P:1192–1215 gate catalog access by binding. CPrototype keeps a single result character. IR:206–233 still has a broad Swift/ObjC runtime direct-return assumption. T/NamedABIContractTests.swift:114–121,148–162 separates ordinary and ARC contracts. | [R] C/lib/IRGen/GenCall.cpp:1548–1666 asks Clang for result classification and extensions. C/lib/IRGen/GenClangType.cpp:38–58 distinguishes indirect mutation from indirect const transport. | Exact declaration/provider pairing, narrow result widths, structured aggregate results and typed callback prototypes. Prefix-direct risk is owned by O01-b below. |
| F10 | Possibly wrong | [R] V:1164–1166 treats three runtime spellings as void without requiring provider evidence. V:2352–2360 discards their result. P:1274–1318 has exact ARC identity membership, not ownership attributes. | [R] C/lib/SIL/IR/SILFunctionType.cpp:3985–4145 derives consumed/retained/autoreleased/inner-pointer contracts from attributes and method families. | [I] A foreign value-returning twin of a bare void-runtime name loses its result. General imported/exported NSError and ownership-attribute recovery remain partial. |
| F11 | Partially closed | [R] D:4597–4608 has generic indirect-target recovery. OA:254–256 accepts @? as a token. CG:22–27 explicitly leaves dynamic block dispatch unresolved. No block-literal model was found in the scoped source search. | [R] C/lib/IRGen/GenFunc.cpp:2847–2951 emits header/flags/invoke/descriptor. C/lib/IRGen/GenCall.cpp:1588–1591,6431–6455 makes the block the first invocation operand. | Blocks, captures, heap copies, complete invocation signatures, C callbacks and representation-changing thunks. @? alone is not an invoke prototype. |
| F12 | Partially closed | [R] RS:591–631 records basic carriers. P:1035–1068 supplies arity. ObjCAccessorRewriter.swift:449–459 recognizes storage-helper spellings without a lifetime model. | [R] C/lib/IRGen/GenHeap.cpp:222–229,1023–1085 distinguishes native/unknown reference storage. C/stdlib/public/runtime/SwiftObject.mm:1151–1193 implements unknown weak operations. | Exact slot operations, weak address result versus object result, unknown/native routing, checked versus unsafe unowned. Shared with O03. |
| F13 | Safely declined | [R] No dedicated CXXMethod/lifetime model was identified. Generic indirect results exist at IR:26–38,184–233. An Itanium spelling is not a declaration. | [R] C/lib/IRGen/GenCall.cpp:1593–1644 puts C++ this first and delegates arrangement. C/include/swift/AST/Types.h:4547–4551 defines Indirect_In_CXX. | No positive C++ ABI completeness claim. Unknown calls remain raw/unknown. Clang classification and this-adjustment oracle unavailable in this checkout. Rank last. |
| O01 | Possibly wrong | [R] RR:13–43 proves bounded import islands/exports and RR:73–81 gates ARC identity. IR:213 grants direct return by prefix after named-contract qualification. P:1236–1264 hides non-identity runtime-prefix matches without a provider gate. | [R] C/include/swift/Runtime/RuntimeFunctions.def:283–423 separates results/effects/conventions. C/lib/IRGen/IRGenModule.cpp:559 maps SwiftDirectRR to PreserveMost. | [I] Noise hiding and direct-result decisions outgrow the exact evidence model. Exact contract roles and aliases/reexports still need their own qualification. |
| O02 | Possibly wrong | [R] V:1161–1162,2500–2507 grants field preservation to several names outside the exact ARC set. P:1267–1269 correctly keeps pools and retainBlock visible. T/RuntimeResultIdentityTests.swift:61–96 guards producer single evaluation, but not the old tail-retain shape. | [R] C/stdlib/public/runtime/HeapObject.cpp:511–627 preserves retain identity but release can deinit. C/stdlib/public/runtime/SwiftObject.mm:714–779 preserves bridge bits and routes release. | Provider-safe effects, release order and the historical duplicate tail-call lead. Retain identity is not producer replay or block-copy identity. |
| O03 | Partially closed | [R] RS:591–631 and T/RuntimeArityTests.swift:152–175 cover signatures/arity. No complete weak/unowned slot-generation state was found. | [R] C/stdlib/public/runtime/HeapObject.cpp:821–891,1144–1187. C/stdlib/public/runtime/WeakReference.h:127–151,170–212 separates side-table storage, strong load and consuming take. | Each storage transition, owned-or-nil load, checked trap and slot result role. Never equate a side-table pointer with object identity. |
| O04 | Partially closed | [R] SL:164–223 and D's receiver logic carry some physical roles. No general cross-call borrow/consume/dependent-base model was found. | [R] C/include/swift/AST/Types.h:4520–4579,4977–5022. C/lib/IRGen/IRGenSIL.cpp:1311–1314,6320–6336 forwards move/dependence without preserving source distinctions. | Record only recoverable contracts. Preserve the decline where distinct ownership SIL produces identical machine transport. |
| O05 | Partially closed | [R] D:4823–4912 names value-witness operations with metadata correlation. P:1349–1354 keeps outlined stores visible. T/ValueWitnessArgumentTests.swift:14–38 asserts calls, not initialized/moved storage states. | [R] C/include/swift/ABI/ValueWitness.def:114–161. C/lib/IRGen/GenOpaque.cpp:1315–1378 and Outlining.cpp:352–381,533–541 distinguish witness `(dest,src,T)` from outlined `(src,dest,metadata...)`. | Storage generations and initialize/copy/take/assign/destroy effects. Outlined assignment rendering and outcome-specific buffer validity remain open. |
| O06 | Possibly wrong | [R] V:2500–2507 accepts access-marker spellings as field-preserving. CR:1014–1019 propagates that through helpers. T/FieldAliasTests.swift:36–45,94–99 intentionally accepts unbound access markers. | [R] C/lib/IRGen/IRGenSIL.cpp:7180–7208,7334–7355. C/include/swift/Runtime/Exclusivity.h:31–50 gives scratch lifetime and no-track behavior. | [I] Foreign access-marker twins can preserve stale fields. Later positive scope modeling needs scratch generation, flags, CFG cleanup and escape state. |
| O07 | Partially closed | [R] D:13441–13456,13810–13821 implements only a matching stored-property modify ramp. T/ReconstructionTests.swift:646–664 tests that subset and a declined backing-field mismatch. | [R] C/lib/IRGen/GenCall.cpp:818–954 orders continuation/yields/overflow and distinguishes continuation forms. C/include/swift/AST/Types.h:5248–5315 distinguishes yield conventions and kinds. | _read, ordered direct/indirect/mixed yields, overflow, callee-allocated frames and descriptor identities. Do not call existing x1 support universal. |
| O08 | Safely declined | [R] No synchronous activation/end/abort model was identified beyond O07's ramp display. Raw continuation calls are not a proved lifecycle. | [R] C/lib/IRGen/IRGenSIL.cpp:4906–4960 passes frame plus abort bit or allocator. C/lib/SILGen/SILGenApply.cpp:8191–8204 says new yielding accessors always complete on throw. | Activation identity, nested/repeated yields, normal end, legacy abort and frame lifetime. Async context analysis does not close this ABI. |
| O09 | Safely declined | [R] Generic buffer support in IR is not a C++ construction/destruction contract. No C++ ownership suite was found in the scoped tests. | [R] C/lib/IRGen/GenStruct.cpp:682–719,722–805,835–886 distinguishes complete construction and complete destruction. | Copy/move/this/result storage and caller/callee cleanup. Rank after Swift/ObjC work. |
| U01 | Safely declined | [R] RS:337,367 names replacement runtime entry signatures. Scoped source/test search found no replacement-chain semantic model. Opaque indirect calls do not establish original-body effects. | [R] C/lib/IRGen/GenDecl.cpp:3101–3155,3433–3503 distinguishes replacement selection and previous implementation, including async/coroutine pointer categories. | Decode chain/declaration separately from exact body. Audit any future original-body refinement before enabling replacement value recovery. No current wrong output established. |
| U02 | Safely declined | [R] @? tokens and async runtime signatures exist, but no declaration/completion/error/continuation association was found. Selector names containing completionHandler are only catalog entries. | [R] C/include/swift/AST/ForeignAsyncConvention.h:25–107. C/lib/SILGen/SILGenThunk.cpp:423–510,575–605 and SILGenBridging.cpp:1802–1843. | Completion slot, hidden block operand, error/flag polarity, continuation association and export direction require separate proofs. |

### Corrections to stale readiness leads

- The blanket untyped-struct wrong-layout defect is not new work. `ffd5fdb` introduced the positional-prefix decline. OM:769–793 now guards it, including SDK vetoes. Positive aggregate reconstruction remains open.
- Super-result adoption is not still broken in its original form. `git log -SforwardsObjCSuperResultAsSelf` identifies `d8a00e0`. Preserve its provider, selector, search-class and old-self controls.
- `git log -SisDirectObjCMethod` identifies `9bd88bb`. It implemented the positive direct-method path, but the metadata-absence inference remains in HEAD.
- `git log -SfieldPreservingRuntimeCalls` identifies `e4ceb7b`. Later exact-ARC tests do not qualify the still-unbound access-marker branch.
- Tail-retain duplication is a historical lead in PRODUCTION-READINESS.md:832–838. Current ObjC tail-handshake tests and producer-identity tests cover related, narrower behavior. Do not declare the old lead reproduced or fixed without its own probe.
- Selector xrefs are not completely absent. CG:191–199 already lets `-f objc_msgSend$foo` find stub-named calls. It does not collect generic selref-based sends, string references or data accesses as their own reference kinds.
- P:61–64 distinguishes no decoded instructions from an empty rendered statement list. It still labels every nonempty but statement-free body `leaf / pure computation`, including hidden or unmodeled code.

## Landing contract for every sprint

A sprint is one observable behavior, not permission to replace the tracer. Existing facts can carry its evidence until the shared boundary schema exists. B01/B02/B03, K01/K02/K04, X01/X02 and A07 below mean the named external plan dependencies in `docs/ABI-CLOSURE-PLAN.md`.

All fixtures are proposed clean-room source. Swift sketches run at `-Onone/-O/-Osize` (SW). Objective-C sketches run with ARC at `-O0/-O2/-Os` (OB). Use separately linked callers/providers when provider, resilience or dynamic dispatch matters. Counterexamples that patch metadata or instructions are analysis-only, never executed. A syntax or feature the pinned toolchain cannot emit is an explicitly unavailable oracle, not a passing case.

For every sprint, first capture the baseline failure, then the compiler SIL/IR and linked assembly/metadata/bindings that establish its premise. Add native sentinels and side-effect logs where executable. Mutate each independent proof gate separately, rebuild, observe the named test fail, restore, rebuild and rerun. No such proof was performed in this research.

Acceptance covers pseudo and structured output plus typed facts, filtered, array, streaming and selected-function paths where claimed. Listing/JSON and all CLI entry points need preservation checks. The existing enforcing suite, frozen-release blast radius, cost budgets and gate remain required. Missing fixtures must fail under enforcement. Negative cases must retain calls/effects when their value or signature declines.

Before/after strings are semantic sketches, not promised exact naming. An after state containing `?` may close a soundness sprint but does not close its parent completeness item.

## Recommended sprint order

This is a priority queue, not a claim that every dependency has already landed. Sprints 1–8 can begin as narrow guards without the broad schema work. Thereafter, select the highest-priority ready sprint. If a card names a later card as a prerequisite, complete that prerequisite first. External plan dependencies remain explicit. A newly reproduced wrong value moves ahead of completeness cards regardless of its number.

The numbered cards cover the bounded first landings for each audit item. The scope ledger names additional variants that still require individual acceptance rows. It is not a claim that these 90 commits alone establish ABI closure.

### 1. O01-a: hide runtime calls only under an exact effect contract

Axis: soundness. Size S. Confidence high in the missing gate, medium in reachability of a concrete wrong render.

- Rule: runtime names have distinct effects, C/include/swift/Runtime/RuntimeFunctions.def:283–423,2031–2045. A name does not establish provider identity.
- Change site: P:1236–1264 `isRuntimeNoise(Instruction)`. Keep presentation eligibility separate from ARC result identity.
- Fixture SW: an exported `@_cdecl("swift_release_probe") func probe(_ p: UnsafeRawPointer?) { counter += 1 }`, called from another image. True behavior increments once.
- Before/after [I]: potentially hidden prefix call -> visible opaque `swift_release_probe(...)`. Actual qualified ARC control remains hidden under its documented display policy.
- Negatives: unknown/addended/weak/conflicting binding, local and foreign twins. Mutations: bypass provider gate, broaden exact membership to prefix independently.
- Dependencies: existing RR suffices for the negative guard. B03 is needed for new positive contracts.

### 2. O06-a: require provider proof before preserving fields across access markers

Axis: soundness. Size S. Confidence high in the source defect.

- Rule: real begin/end access operate on tracking scratch, C/lib/IRGen/IRGenSIL.cpp:7192–7207,7345–7355. That contract belongs to those runtime definitions.
- Change sites: V:1161–1162,2500–2507 and CR:1003–1026. Extend the evidence parameter rather than reusing ARC identity for unrelated operations.
- Fixture SW: `let old = box.n; foreignBegin(box); sink(old)`, with a foreign export named `swift_beginAccess` that changes `n` to 19. True sink receives the old value.
- Before/after [I]: stale `sink(box.n)` -> saved value or `sink(?)`, with mutator visible.
- Negatives: unbound endAccess, retainBlock and nonatomic variants without exact contracts. Mutations: remove direct-call gate and helper-closure gate separately.
- Dependencies: none for a conservative fix. Preserve T/FieldAliasTests.swift:195–246 exact ARC positives.

### 3. F05-a: prove the dispatcher before interpreting an Objective-C send

Axis: soundness. Size M. Confidence high in incomplete stub proof, medium in end-to-end manifestation.

- Rule: C/lib/IRGen/GenObjC.cpp:798–862 selects a particular messenger and separate selector operand.
- Change sites: OS:124–135, D selector/call enrichment, P:357–377 `MessageSend`. Attach one typed dispatcher fact to all consumers.
- Fixture OB: normal `[obj take:7]` plus a foreign function exported as `objc_msgSend` that records both inputs. Add a selector-load-shaped stub whose final branch targets that foreign function.
- Before/after [I]: bracket syntax/ObjC layout for fake dispatcher -> opaque call retaining recovered inputs. Real sends remain bracketed.
- Negatives: wrong branch register, target ordinal, addend, malformed island or selref. Mutations: accept first two stub instructions only, drop provider check independently.
- Dependencies: RR and B03, not the full foreign layout rewrite.

### 4. F06-a: stop deriving objc_direct from missing metadata

Axis: soundness. Size S. Confidence high in faulty premise.

- Rule: C/lib/IRGen/GenCall.cpp:1575–1584 removes SEL only when `forStaticCall` establishes direct ABI.
- Change site: D:6444–6447 `isDirectObjCMethod`, shared entry and call consumers. Missing metadata yields unknown placement.
- Fixture OB: `- (long)mix:(long)a with:(long)b { return a*100+b; }`, invoked through an ordinary IMP pointer including SEL. Keep its symbol while removing its method-list record in an analysis-only copy.
- Before/after [I]: potential x1-as-arg0 -> unknown argument layout, never shifted claimed values.
- Negatives: truncated/category/external metadata and unresolved owner. Mutation: restore the absence-plus-local-class rule.
- Dependencies: none for the guard. Positive direct recovery is F06-b.

### 5. F01-a: reject address-shaped x20 as external nominal Self proof

Axis: soundness. Size S. Confidence medium.

- Rule: C/lib/IRGen/GenCall.cpp:1890–1919,2051–2095 chooses Self/context from lowered convention, not pointer shape.
- Change site: D:9810–9888 receiver collection in `enrichCallArguments`.
- Fixture SW: `struct P { var n: Int; @inline(never) func f(_ x: Int)->Int { n+x } }` in a provider. A controlled ABI veneer parks an unrelated address in x20 while passing value Self in its actual ordinary-bank lane.
- Before/after [I]: spurious `self: parkedAddress` -> correct ordinary Self if proven, otherwise explicit unknown receiver.
- Negatives: closure/reserved throwing context, unrelated callee-saved pointer. Mutations: admit any address, or remove entry-role requirement independently.
- Dependencies: none for decline. F01-b/B02 supplies general positive recovery. Preserve existing imported-receiver controls.

### 6. F04-a: never fold a virtual tail through a base implementation's body

Axis: soundness. Size S. Confidence high in missing virtual exclusion, medium until reproduced.

- Rule: C/lib/IRGen/GenClass.cpp:3130–3148 loads the runtime metadata slot. A subclass may replace the implementation.
- Change sites: D:4597–4608 dispatch identity, D:9462–9473 `passthroughTailBranches`. Track virtuality for field/argument dispatch too, not only `isSelfDispatch`.
- Fixture SW: `class B { @inline(never) func f(_ x:Int)->Int { x }; @inline(never) func g(_ x:Int)->Int { f(x) } }; class S:B { override func f(_ x:Int)->Int { x+9 } }`. True `S().g(3)` is 12.
- Before/after [I]: possible `return arg0` -> `return self.f(arg0)` or an opaque tail result.
- Negatives: unknown dynamic receiver, sibling class, same slot offset. Mutations: drop virtual veto, misclassify field dispatch as exact independently.
- Dependencies: none for the guard.

### 7. O01-b: derive direct runtime result ABI from an exact declaration

Axis: soundness. Size S. Confidence high in overbroad premise, medium in a concrete refutation.

- Rule: C/lib/IRGen/GenCall.cpp:1650–1666 uses the declaration's return classification. C/include/swift/Runtime/RuntimeFunctions.def:283–423 has different result roles.
- Change site: IR:206–233 `isKnownDirectReturnCallee`/`hasNamedDirectReturnContract`. Replace broad swift_/objc_ membership with exact result-role records.
- Fixture SW: separately linked custom `swift_opaqueResult` returning a five-UInt64 struct. True result initializes five words through the compiler-selected result buffer. Add an exact system-provider contract unit input with an unknown future name to test membership independently.
- Before/after [I]: prefix-derived direct result -> unknown convention unless exact declaration proves direct.
- Negatives: unknown runtime member, messenger, unsupported alias/reexport. Mutations: restore prefix fallback, confuse provider membership with result declaration.
- Dependencies: B03 for new positives. Retain existing result-buffer exception controls.

### 8. F10-a: provider-qualify the void-runtime result discard

Axis: soundness. Size S. Confidence high in missing gate. A wrong value is not yet reproduced.

- Rule: C/include/swift/Runtime/RuntimeFunctions.def declares exact runtime operations. Imported ownership/result conventions are declaration-specific, C/lib/SIL/IR/SILFunctionType.cpp:3985–4145.
- Change sites: V:1164–1166,1191,2352–2360 `returnsVoidByName` and result transfer.
- Fixture SW: foreign `@_cdecl("swift_job_run") func fake(_ p:UnsafeRawPointer?)->Int { 37 }`, with a C-declared caller that returns the result. True result is 37.
- Before/after [I]: result silently discarded -> opaque result or proved 37, preserving the call. Genuine runtime void entry still produces no value.
- Negatives: local/foreign twins for all three names. Mutations: remove provider check, let cache merge trusted and foreign facts independently.
- Dependencies: existing provenance facts. Extend T/NamedABIContractTests.swift rather than adding another spelling-only set.

### 9. O02-a: render the producer once through a tail-called retain

Axis: soundness. Size S. Confidence medium. Historical lead, not a current reproduction.

- Rule: retain returns the transported pointer, C/stdlib/public/runtime/HeapObject.cpp:511–538. It does not call its producer again.
- Change sites: D consumed/bound result collection and tail-exit construction, P:131–144, V:2333–2345.
- Fixture SW: `@inline(never) func make()->Box { made += 1; return Box() }; @inline(never) func forward()->Box { make() }`. Also use a reduced ABI veneer ending in the exact bound retain tail if the compiler does not emit it.
- Before/after [I]: if baseline repeats `make()`, replace with one evaluation and forwarded value. If already correct, land only a validation regression, not a speculative fix.
- Negatives: retainBlock is not identity, foreign twin stays opaque. Mutations: omit consumed-producer marking and remove binding independently.
- Dependencies: O01-a. Preserve T/RuntimeResultIdentityTests.swift:61–96 and ObjC tail controls.

### 10. F09-b: recover the declared width of one scalar C result

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenCall.cpp:1660–1666 derives sign/zero extension from the exact Clang result type.
- Change sites: P:1177–1215 `CPrototype`, declaration generator and V result-bank transfer. Start with Int32, not every aggregate.
- Fixture OB: `int result32(void) { return -7; }` with Swift `Int(result32())`. True returned Swift value is -7 at SW levels.
- Before/after [I]: current unproved C result view `?` -> explicit sign-correct `result32()` result view.
- Negatives: absent declaration, provider twin, undefined upper bits. Mutations: remove width, use requested consumer width as producer proof, drop provider gate separately.
- Dependencies: B03/K02 and O01-b. Wider C/ObjC result schemas remain separate.

### 11. F01-b: place an ordinary direct value receiver from ordered pieces

Axis: completeness. Size M. Confidence high in rule, medium in shape recovery.

- Rule: C/lib/IRGen/GenCall.cpp:2020–2057 places direct Self among ordinary parameters before polymorphic/context roles.
- Change sites: SL:164–223 and D value-receiver extraction. Consume B02's ordered pieces rather than add another GP/FP count heuristic.
- Fixture SW: `struct P { var a:Int16; var b:Float16; var c:Int16; @inline(never) func f(_ x:Int)->Int { Int(a)+Int(c)+x } }`. Use distinct field sentinels.
- Before/after [I]: incomplete/unknown receiver -> proved ordered projections, without moving the following formal.
- Negatives: incomplete/resilient layout, fifth direct component, wrong producer projection. Mutations: merge integers across FP barrier, swap receiver/formal pieces separately.
- Dependencies: B02 and F01-a. Preserve SwiftReceiverTypeList/ImportedReceiver tests.

### 12. F01-c: distinguish thin value metatype from class metatype context

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenCall.cpp:1904–1907 and C/docs/ABI/CallingConvention.rst:580–596 distinguish zero-sized thin metatype and dynamic class metadata.
- Change sites: P:608–627 `receivesThinMetatype`, D entry/outgoing receiver facts.
- Fixture SW: `struct V { static func tag()->Int { 1 } }; class B { class func tag()->Int { 2 } }; class S:B { override class func tag()->Int { 3 } }`. Call both through their applicable metatypes.
- Before/after [I]: absent/ambiguous context -> no carrier for thin V, class-metadata receiver for B.Type, never an instance label.
- Negatives: existential metatype with witnesses, unknown representation. Mutations: allocate a word to thin Self, tag metatype as object independently.
- Dependencies: F01-b/B02.

### 13. F02-a: recover read-only indirect Self without inventing mutation

Axis: completeness. Size M. Confidence high.

- Rule: C/include/swift/AST/Types.h:4528–4545 distinguishes guaranteed indirect, inout and aliasable inout. C/lib/IRGen/GenClangType.cpp:38–58 preserves that distinction.
- Change sites: D entry receiver plan, SL, V memory-effect inputs.
- Fixture SW: a five-word struct with `borrowing func sum()->Int` and `mutating func bump()`. True sum leaves storage unchanged, bump changes one field.
- Before/after [I]: unknown or undifferentiated pointer Self -> separate proved read-only and mutating receiver facts, with corresponding rendering.
- Negatives: ownership erased from machine evidence, imported declaration unavailable. Mutations: classify every indirect receiver as inout, grant noncapture from read-only alone.
- Dependencies: F01-b and B01/B02. No general lifetime inference from physical pointer transport.

### 14. F02-b: apply a specialized Self transformation before placement

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/SIL/IR/SILFunctionType.cpp:1475–1545 defines convention-based lowering. The emitted specialized entry, not its original printed method, is the oracle.
- Change sites: `SpecializedSignature.swift`, D `signatureSpecializationRewritesSelf` and outgoing layout.
- Fixture SW: generic `struct W<T> { var x:T; @inline(never) func ignore(_ n:Int)->Int { n+1 } }`, with an internal specialized caller. Pin a compiler-emitted Dead-Self or exploded-Self entry before admitting it.
- Before/after [I]: whole affected receiver declined -> accurate transformed formals with no resurrected dead Self.
- Negatives: unsupported modifier tree, non-emitted transformation, ambiguous folded symbols. Mutations: use original signature, retain dead Self independently.
- Dependencies: F02-a, closure-specialization owner C08 and B02.

### 15. F03-a: seed a nonallocating class initializer's instance receiver

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/SILGen/SILGenConstructor.cpp:1074–1091 passes the allocated object to the initializer and returns its initialized result.
- Change sites: D entry classification and self-type selection, `SelfTypeIndex` entry-kind evidence.
- Fixture SW: `class C { var n:Int; @inline(never) init(_ n:Int) { self.n=n } }`, inspecting both allocating and initializing symbols.
- Before/after [I]: initializer store through unknown/raw x20 -> `self.n = arg0` only at the nonallocating entry.
- Negatives: value init, allocator metatype, convenience/failable/throwing variants outside the supported slice. Mutations: swap allocator/initializer kind, permit name-only nominal proof.
- Dependencies: F01-c. Keep parameter layout and result identity separate.

### 16. F03-b: carry allocator metatype without labeling it instance self

Axis: completeness. Size S. Confidence high.

- Rule: C/lib/SILGen/SILGenConstructor.cpp:1016–1066 obtains metatype and allocates the object before initializer invocation.
- Change sites: D:6122–6157 and allocator call enrichment.
- Fixture SW: `class B { required init(_ n:Int) {} }; class S:B {}; func make(_ t:B.Type)->B { t.init(7) }`. True dynamic class of result is S when t is S.self.
- Before/after [I]: unknown metatype operand -> qualified metatype argument and separate new-object identity.
- Negatives: unknown constructor entry, value thin metatype. Mutations: reuse instance self fact, replace dynamic metatype with declaring class.
- Dependencies: F03-a. Do not generalize to failable/throwing allocation outcomes.

### 17. F03-c: distinguish destroying from deallocating entries

Axis: completeness. Size M. Confidence medium pending destructor-specific oracle.

- Rule: C/lib/SILGen/SILGenDestructor.cpp:214–228 returns the destroying destructor's object. At 267–293 the deallocating entry calls that destroyer, balances lifetime and deallocates. ObjC destruction is a separate entry at 738–771.
- Change sites: D entry-kind/return schema, `SelfTypeIndex` metadata.
- Fixture SW: `class C { var b:Box; deinit { log(7) } }`. Capture emitted destroying/deallocating signatures and native destruction log.
- Before/after [I]: generic/unseeded entries -> explicit instance receiver and only the result role that the emitted signature proves.
- Negatives: ObjC dealloc thunk, isolated deinit, move-only destructor not yet qualified. Mutations: exchange destroying/deallocating result roles, fabricate x0 output for void.
- Dependencies: F03-a, O01-b/K01. The receiver/result contract can land without claiming complete isolated or ObjC destructor cleanup.

### 18. F03-d: preserve a self-returning callee's result at a later store

Axis: completeness. Size S. Confidence high in the tracked readiness gap.

- Rule: result identity is distinct from receiver transport, C/lib/SILGen/SILGenConstructor.cpp:1087–1091 and C/lib/IRGen/GenCall.cpp:2020–2057.
- Change sites: V:2377–2388, D call-result class/type rendering. Extend T/SelfRegisterTests.swift.
- Fixture SW: `class C { @inline(never) func me()->C { self } }; func use(_ c:C,_ out:UnsafeMutablePointer<C>) { out.pointee=c.me() }`.
- Before/after [I]: readiness's raw `x0` store -> one named `c.me()` result at the store. Do not rewrite an arbitrary self-returning signature to the old receiver.
- Negatives: method returns another instance, replacement initializer, indirect generic result. Mutations: discard result bank, replace result with incoming self independently.
- Dependencies: F03-a and current producer single-evaluation proof.

### 19. F05-b: recover a selector declaration through proved receiver ancestry

Axis: completeness. Size M. Confidence high in missing mechanism.

- Rule: C/lib/IRGen/GenObjC.cpp:1334–1382 uses the declaration's encoding. Signature arrangement remains separate at GenCall.cpp:1548–1666.
- Change site: OM:710–720 `outgoingSignature`, receiver class/metaclass evidence.
- Fixture OB: Base declares `- (void)take:(double)x tail:(long)n`, Sub inherits it, a typed Sub caller passes 2.5 and 17. True arguments preserve that order.
- Before/after [I]: unavailable own-class declaration -> inherited applicable signature and correct FP/GP operands.
- Negatives: incompatible category/override, unknown ancestry, class-versus-instance collision. Mutations: skip ancestry check, accept selector-wide agreement as positive proof.
- Dependencies: F05-a/B03. Protocol-only declarations get the same applicability requirement, not universal selector authority.

### 20. F06-b: recover positively proved objc_direct layout

Axis: completeness. Size M. Confidence medium because complete Clang direct-method authority is unavailable locally.

- Rule: C/lib/IRGen/GenCall.cpp:1575–1584 and GenObjC.cpp:865–868 omit _cmd for a known direct method.
- Change sites: D `isDirectObjCMethod` replacement fact and entry/outgoing consumers.
- Fixture OB: `- (long)mix:(long)a with:(long)b __attribute__((objc_direct));`, paired with a conventional IMP of the same arithmetic. True direct call passes a in x1, conventional call passes SEL in x1.
- Before/after [I]: F06-a decline -> recovered direct arguments only with independently retained declaration or equivalent complete entry evidence.
- Negatives: missing metadata alone, normal IMP pointer, unknown owner. Mutations: insert SEL into direct layout, accept a missing record as declaration.
- Dependencies: F06-a/F05-b and an independent Clang declaration/IR oracle.

### 21. F08-a: reconstruct one complete GP aggregate message result

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/IRGen/GenCall.cpp:1650–1666 delegates foreign return classification. Swift arm64 still uses ordinary messenger, SwiftTargetInfo.cpp:60–61.
- Change sites: OA aggregate result schema, OM return agreement, D result projection/rendering.
- Fixture OB: `typedef struct { long a,b; } Pair; - (Pair)pair { return (Pair){11,29}; }`, caller sums both fields. True sum is 40.
- Before/after [I]: aggregate `?` -> one result binding with `.a/.b`, not whole Pair from x0 alone.
- Negatives: unknown declaration, conflicting return layout, only one lane proved. Mutations: treat first lane as whole, swap lanes.
- Dependencies: F05-b/B02 and foreign classifier oracle.

### 22. F08-b: reconstruct one HFA message result

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/IRGen/GenCall.cpp:1548–1666 delegates result coercion. OA:185–193 already distinguishes bounded HFA argument shapes.
- Change sites: shared foreign result pieces, D FP projections, OM:736–761.
- Fixture OB: `typedef struct { double x,y; } H; - (H)h { return (H){2.5,8.0}; }`. True caller `h.x+h.y` is 10.5.
- Before/after [I]: `return ?`/unknown projection -> two proved FP projections from one send.
- Negatives: mixed struct, same selector scalar-double conflict, missing d1. Mutations: equate d0 with whole HFA, interchange GP/FP bank.
- Dependencies: F08-a/B02. Preserve ObjCReturnBankTests single-evaluation controls.

### 23. F08-c: preserve machine-proved nil-path indirect result initialization

Axis: completeness. Size M. Confidence medium-low until Clang oracle is available.

- Rule: C/lib/IRGen/GenObjC.cpp:798–830 and SwiftTargetInfo.cpp:60–61 use normal messenger on arm64 even for indirect results. The caller's actual zeroing/branch instructions establish buffer effects.
- Change sites: OA result schema, IR convention selection, V result-buffer edge validity.
- Fixture OB: a method returning five longs, called through a runtime-selected nil/non-nil receiver. Native caller records all bytes and any consumed-argument cleanup.
- Before/after [I]: unknown buffer -> complete value only on independently proved initializing edges.
- Negatives: no observed zeroing, incomplete buffer writes, unsupported suffix messenger. Mutations: use x0 instead of x8, initialize nil edge from non-nil fact.
- Dependencies: F08-a, O05-f and Clang nil-result oracle. Zero initialization must not be assumed from selector spelling.

### 24. F05-c: recover struct-taking sends only when a call-site declaration becomes applicable

Axis: completeness. Size M. Confidence high in decline policy, medium in new positives.

- Rule: C/lib/IRGen/GenCall.cpp:1548–1666 classifies a complete foreign signature. OM:769–793's untyped prefix veto is already correct.
- Change sites: OM outgoing evidence, OA placements and D argument grouping.
- Fixture OB: `typedef struct { long a,b; } Pair; [typed take:(Pair){3,4} tail:9]`, paired with an id-typed receiver whose applicable declaration cannot be proved. True typed arguments are Pair(3,4) then 9.
- Before/after [I]: typed-but-unrecovered aggregate `?` -> complete aggregate plus correct tail. Truly untyped case stays `take:? tail:?` from the uncertain prefix onward.
- Negatives: incompatible category, unknown receiver or HFA declaration. Mutations: remove prefix veto, consume one word per selector colon.
- Dependencies: F05-b/F08-a/B02.

### 25. O05-a: initialize destination storage through a proved copy witness

Axis: completeness. Size M. Confidence high.

- Rule: C/include/swift/ABI/ValueWitness.def:125–132 and GenOpaque.cpp:1315–1338 preserve source and initialize invalid destination.
- Change sites: V storage effects, D `valueWitnessCall`, `FrameMemoryEffect` generation facts.
- Fixture SW: `@inline(never) func duplicate<T>(_ x:T)->T { x }`, plus a reference-containing T and independent source/result destruction counters.
- Before/after [I]: opaque witness call and unknown initialized buffer -> destination initialized in a fresh generation, source still valid.
- Negatives: wrong metadata/extent, unknown destination state, overlapping invalid ranges. Mutations: reverse source/dest, invalidate source as if take.
- Dependencies: B01/B03/K02. Keep storage state separate from value equality.

### 26. O05-b: expire source storage after a proved take

Axis: completeness. Size M. Confidence high.

- Rule: C/include/swift/ABI/ValueWitness.def:143–151 invalidates taken source. IRGenSIL.cpp:8707–8712 selects take independently from initialization.
- Change sites: V storage generations and witness transfer.
- Fixture SW: `struct Token:~Copyable { var n:Int; deinit { log(n) } }; @inline(never) func move(_ x:consuming Token)->Token { x }`. Use valid SIL if optimized machine code erases the selected witness.
- Before/after [I]: no lifetime interpretation -> destination initialized and source generation unavailable after take, with one destruction.
- Negatives: unknown take identity/extent and ambiguous source aliases. Mutations: preserve old source, model take as copy.
- Dependencies: O05-a. Machine transport alone cannot reconstruct the consuming source declaration.

### 27. O05-c: replace live destination state through assign-with-copy

Axis: completeness. Size M. Confidence high.

- Rule: C/include/swift/ABI/ValueWitness.def:134–141 requires a valid destination. IRGenSIL.cpp:8714–8719 separates assignment from initialization.
- Change sites: V witness effects and initialized-range state.
- Fixture SW: `@inline(never) func replace<T>(_ a:inout T,_ b:T) { a=b }`, T holding an object whose deinit logs replacement order.
- Before/after [I]: opaque assign -> destination generation replaced, old content unavailable, source valid. Keep possible destructor effects on aliases.
- Negatives: uninitialized destination, unknown custom witness, alias overlap. Mutations: treat assign as pure initialization, preserve old destination value.
- Dependencies: O05-a and O02 effect separation. Assign-with-take adds O05-b's source invalidation in a separate follow-up test/commit.

### 28. O05-d: expire storage and aliases after destroy

Axis: completeness. Size M. Confidence high.

- Rule: C/include/swift/ABI/ValueWitness.def:114–123 destroys a valid object. GenOpaque.cpp:1367–1378 invokes destruction, not a value-producing copy.
- Change sites: V witness effects, storage/alias invalidation, D void witness facts.
- Fixture SW: a generic local with a deinit that changes another object, followed by reading that other object's field. True read sees the mutation.
- Before/after [I]: named destroy call without lifecycle state -> destroyed generation unavailable and potentially affected aliases invalidated.
- Negatives: wrong metadata, unknown extent, callback-capable destroy. Mutations: retain destroyed contents, mark destroy as field-preserving.
- Dependencies: O05-a/O06-a. Do not infer absence of callbacks from void result.

### 29. O05-e: render a proved outlined copy as destination assignment

Axis: completeness. Size S. Confidence high.

- Rule: C/lib/IRGen/Outlining.cpp:357–381,533–541 uses source then destination and returns destination. GenOpaque.cpp:1323–1325 uses the opposite explicit witness order.
- Change sites: P:1349–1354 `isStoreHelper`, D typed statement generation after effect qualification.
- Fixture SW: `func put<T>(_ x:T,_ out:inout T) { out=x }` at Osize with a compiler-emitted outlined assign/copy helper. True output equals x and old destination cleanup remains ordered.
- Before/after [I]: `outlined assign with copy...(src,dest,...)` -> `dest = src` using the proved operation fact.
- Negatives: same-name user function, incomplete helper, unknown metadata or aliases. Mutations: reverse operands, infer operation from printed name alone.
- Dependencies: O05-a/O05-c. Take/destroy forms remain distinct facts, never hidden wholesale.

### 30. O05-f: mark indirect result initialized only on its producing outcome

Axis: completeness. Size M. Confidence high.

- Rule: C/include/swift/AST/Types.h:4979–4983 requires initialized indirect result on the result outcome. Error paths do not inherit success storage facts.
- Change sites: IR result roles, V per-edge storage state and D indirect return reconstruction.
- Fixture SW: `func make(_ fail:Bool) throws -> Big { if fail { throw E.bad }; return Big(...) }`, Big five distinct words.
- Before/after [I]: result buffer unavailable -> complete normal result only on success, error buffer and success buffer remain distinct.
- Negatives: untouched error-path buffer, escaped output, partial write. Mutations: initialize both edges, alias error and success storage.
- Dependencies: O05-a and external X01/X02/B02. This is not general typed-error recovery.

### 31. F07-a: prove initializer adoption through a private O0 ARC local

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenObjC.cpp:714–766 establishes the actual receiver/search pair. A returned replacement object remains a result until its use proves adoption.
- Change sites: D:6482–6533 `forwardsObjCSuperResultAsSelf`, V ObjC old-self/frame provenance.
- Fixture OB: `-initWithN:(long)n { self=[super init]; if(self) _n=n; return self; }`, emphasizing O0's spilled self local.
- Before/after [R/I]: T/ObjCSuperInitializerTests.swift:69–75 currently expects no O0 adoption -> proved `self = [super init]` and own-ivar write.
- Negatives: escaped local, old-self read, reused stack generation, ordinary super result. Mutations: omit frame-privacy proof, ignore old receiver read.
- Dependencies: O05-a and existing F07 proof. Do not weaken its 21 historical mutation gates.

### 32. F07-b: prove adoption through an exact objc_storeStrong helper

Axis: completeness. Size M. Confidence medium.

- Rule: imported consumed/ownership contracts are declaration-specific, C/lib/SIL/IR/SILFunctionType.cpp:3985–4145. Replacement receiver and strong-slot write are separate operations.
- Change sites: D adoption proof, V bounded strong-slot effect, ObjCAccessorRewriter helper qualification.
- Fixture OB: initializer stores the super result into its strong self local via ARC's emitted storeStrong sequence, then initializes an own ivar and returns that local.
- Before/after [I]: helper-mediated adoption declines -> self adoption only after exact slot/result propagation.
- Negatives: fake storeStrong, aliasing/exposed local, old receiver retained elsewhere. Mutations: gate helper by spelling only, use source object as helper return.
- Dependencies: F07-a, F05-a, O05-c. Requires an SDK/runtime oracle for objc_storeStrong, absent from Swift's implementation checkout.

### 33. F07-c: preserve legacy Super's search-start distinction

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/IRGen/GenObjC.cpp:813–829 chooses peer Super versus Super2 separately and passes the supplied search pair.
- Change sites: D typed super-call fact, V pair provenance, P message receiver display.
- Fixture OB: clean-room ABI veneer builds `(receiver,searchClass)` and calls the exact bound legacy Super entry. Use superclass methods returning 11 and 29 to distinguish search starts.
- Before/after [I]: generic super display/declined pair -> correct qualified search semantics, not automatic initializer adoption.
- Negatives: swapped fields, wrong class, Super2 with legacy search assumption. Mutations: conflate Super/Super2, omit pair provenance.
- Dependencies: F05-a and F07-a. Confirm exact legacy runtime behavior with an independent runtime/header oracle before claiming it.

### 34. F07-d: track class-method super search through metaclasses

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/IRGen/GenObjC.cpp:733–752 obtains a metaclass for class-method super calls.
- Change sites: D/V super-pair identity and P presentation.
- Fixture OB: Base and Sub override `+tag` with distinct values, Sub's `+viaSuper` returns `[super tag]`. True result is Base's sentinel.
- Before/after [I]: unknown/instance-shaped pair -> metaclass-qualified super call and correct result association.
- Negatives: class versus metaclass swap, instance method, duplicate class names. Mutations: use class object directly as search metaclass, reuse instance self fact.
- Dependencies: F07-c and F01-c. No class-message init adoption from an init-like selector alone.

### 35. F04-b: recover resilient super dispatch by method descriptor

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/IRGenSIL.cpp:8820–8887 looks up resilient super by superclass metadata and method descriptor, not local slot offset.
- Change sites: VT and D indirect dispatch facts, metadata descriptor lookup.
- Fixture SW: separately built library-evolution Base and client Derived, `override func f()->Int { super.f()+1 }`, with provider layout/method ordering changed compatibly.
- Before/after [I]: unresolved lookup call -> declared super method and proven arguments, retaining dynamic implementation uncertainty.
- Negatives: sibling descriptor, unresolved superclass, unsupported authentication. Mutations: identify by equal offset, omit descriptor-owner correlation.
- Dependencies: F04-a, B02 and metadata owner G03/G06. Exact body effects require additional exact target proof.

### 36. F04-c: keep witness declaration ABI independent of implementation identity

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/IRGenSIL.cpp:8644–8697 performs witness lookup independently of class dispatch.
- Change sites: D:4715–4770 witness-name/signature association and CR consumers.
- Fixture SW: `protocol P { func f(_ x:Int)->Int }; struct A:P { func f(_ x:Int)->Int{x+3} }; struct B:P { func f(_ x:Int)->Int{x+9} }; func run(_ p:any P)->Int { p.f(7) }`.
- Before/after [I]: named but incomplete witness arguments -> full declared ABI, never A's exact return/effect for an open existential.
- Negatives: wrong metadata/table pair, different requirement kind, adapter with unknown representation. Mutations: use implementation body to trim formals, accept mismatched table.
- Dependencies: F04-a/B02/G03. Preserve existing witness count and descriptor controls.

### 37. O02-b: keep observable last-release ordering

Axis: soundness. Size M. Confidence medium, requiring a reproduced ordering loss.

- Rule: C/stdlib/public/runtime/HeapObject.cpp:595–627 may deinit at release. Bridge release may route to ObjC, SwiftObject.mm:762–775.
- Change sites: P runtime-noise eligibility, D typed lifetime/effect statements, V field invalidation.
- Fixture SW: `class C { deinit { log(2) } }; func use(){ log(1); do { let x=C(); consume(x) }; log(3) }`. Native log includes destruction between observable events.
- Before/after [I]: if a hidden release makes effect order misleading, show an explicit lifetime end/release at its original point. Do not synthesize a source scope without proof.
- Negatives: unknown deinit/callback, foreign release, autorelease pool boundary. Mutations: mark release pure, move release past later observation.
- Dependencies: O01-a/O05-d. Existing scope-preserving ARC abstraction remains a control.

### 38–43. O03-a through O03-f: one native weak-slot transition per commit

All six use V's storage-generation effects and D's exact runtime call fact. Rule authority is C/stdlib/public/runtime/HeapObject.cpp:1144–1187 and WeakReference.h:170–212. Each is axis completeness, size M, confidence high, and depends on O05-a plus exact O01 contracts. Use SW weak properties and, when the compiler does not emit a specific helper, a reduced runtime-declared driver or valid SIL. The true slot/result role below must be checked independently. Do not combine these rows into one commit.

| Order / ID | One behavior and fixture sketch | Expected before -> after [I] | Negative controls | Independent mutations |
| --- | --- | --- | --- | --- |
| 38 / O03-a | Initialize weak slot. `class W { weak var x:C?; init(_ x:C){self.x=x} }`. The slot becomes initialized without owning C. | Ordinary helper call -> typed weak initialization; `swift_weakInit` result is the slot address, never C. | Unknown provider, slot extent/generation, weak side-table bits masquerading as C. | Swap slot/object result role; initialize wrong slot. |
| 39 / O03-b | Load weak strongly. `func read(_ w:W)->C? { w.x }`. Live target returns an owned temporary, dead target returns nil. | Unclassified pointer result -> weak-load result with owned-or-nil contract, not a compile-time assertion of liveness. | Concurrent zeroing, unknown slot, escaped target. | Substitute slot address for object; make load non-owning. |
| 40 / O03-c | Take weak strongly. Authored weak take driver with valid initialized slot. It consumes storage and returns retained object or nil. | Load-shaped call -> distinct take with source generation expired. | Subsequent slot use, unknown generation, source/destination alias. | Treat take as load; retain slot validity. |
| 41 / O03-d | Copy-initialize weak slot. Two weak fields initialized from the same live target, or emitted copy-init SIL. Both slots remain valid. | Opaque copy -> new initialized weak destination and intact source. | Initialized destination, unknown source representation. | Treat copy-init as take; reverse addresses. |
| 42 / O03-e | Assign weak slot. `w.x=a; w.x=b`. Destination's old weak bookkeeping is replaced, not strongly retained. | Opaque assign -> new destination generation associated with b. | Uninitialized destination, aliasing storage. | Treat assign as initialization; preserve old target association. |
| 43 / O03-f | Destroy weak slot. Scope containing W ends, followed by independent side-effect log. Slot becomes invalid. | Opaque destroy -> expired weak generation, no stored object return. | Unknown helper, reused slot generation, unknown destructor effects. | Keep destroyed slot live; invent x0 object result. |

Weak take-init, copy-assign and take-assign must reuse these operation distinctions, but each new transition is a separate follow-up acceptance row before admission. They are not claimed covered by six rows that exercise different helpers.

### 44. F12-a: route unknown-object weak storage without interpreting its bits as native

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenHeap.cpp:222–229 distinguishes native/unknown weak type info. C/stdlib/public/runtime/SwiftObject.mm:1151–1193 dispatches unknown operations. WeakReference.h:36–47 warns stored bits need not be the object.
- Change sites: RS named operation contracts, V reference-storage kind.
- Fixture SW: native Swift C weak field beside `weak var x:AnyObject?` assigned an imported ObjC instance. Both loads return the corresponding object while live and nil after deinit.
- Before/after [I]: undifferentiated helper carriers -> correct native/unknown slot family, preserving uncertainty about runtime storage bits.
- Negatives: tagged ObjC object, protocol-unknown reference, side-table pointer. Mutations: force native routing, return raw slot bits as object.
- Dependencies: O03-a/O03-b. Other operations require their own O03 transition rows.

### 45. O03-g: preserve checked-unowned upgrade's possible trap

Axis: completeness. Size M. Confidence high.

- Rule: C/stdlib/public/runtime/HeapObject.cpp:821–891 upgrades only if strong retain succeeds, otherwise aborts. The consume-storage form additionally releases unowned bookkeeping.
- Change sites: exact runtime operation facts, V normal/trap outcome effects, D result rendering.
- Fixture SW: `class W { unowned let x:C; init(_ x:C){self.x=x}; func read()->C{x} }`. Run live and dead-target subprocesses separately.
- Before/after [I]: scalar helper call with no lifecycle -> checked upgrade with possible trap, no normal result on the failing outcome.
- Negatives: unknown target liveness, foreign twin, unchecked storage. Mutations: treat upgrade as retain identity, propagate result through trap outcome.
- Dependencies: O05-d/O01-b and external exit contracts. Do not infer target alive from an unowned pointer value.

### 46. F12-b: keep unsafe unowned transport separate from checked storage

Axis: soundness. Size S. Confidence high in the required distinction.

- Rule: C/lib/IRGen/GenHeap.cpp:222–234 separates checked reference storage from unchecked storage. C/include/swift/AST/Types.h:4557–4564 does not guarantee lifetime beyond the relevant convention.
- Change sites: V reference-storage kind and D field type evidence.
- Fixture SW: checked `unowned var a:C` beside `unowned(unsafe) var b:C`; only execute while C is alive. True lowering differs in checking/bookkeeping.
- Before/after [I]: unclassified pointer -> checked/unsafe facts when proven, no invented checked trap or ownership for unsafe b.
- Negatives: erased field type, unknown runtime family. Mutations: conflate storage kinds, give unsafe storage a strong lifetime.
- Dependencies: O03-g/F12-a. Dead unsafe access is not a native correctness oracle.

### 47. O04-a: preserve the decline for ownership distinctions erased before IRGen

Axis: soundness. Size S. Confidence high.

- Rule: C/lib/IRGen/IRGenSIL.cpp:1311–1314 forwards move transport, 6320–6336 erases dependence markers. Borrow instructions are not a surviving IRGen protocol at 1448–1455.
- Change sites: B01 boundary ownership field and any D/V consumers that might infer borrow/consume from carrier shape.
- Fixture SW: borrowing versus consuming access to a trivial wrapper, with compiler SIL and machine transport compared. Use two valid SIL variants with identical transport when source optimization does not preserve the comparison.
- Before/after [I]: both already unknown -> explicit, tested unknown ownership with distinct physical facts retained. This is a guard/validation commit, not positive lifetime recovery.
- Negatives: identical bytes with distinct ownership, absent declaration. Mutations: derive guaranteed from x20, derive consume from direct transport.
- Dependencies: B01 and F02-a.

### 48. O04-b: retain a dependent address's proved base lifetime

Axis: completeness. Size M. Confidence medium.

- Rule: C/include/swift/AST/Types.h:4995–4998 makes inner-pointer validity depend on self. C/lib/SILGen/SILGenApply.cpp:8183–8186 marks addressor dependence before lowering erases it.
- Change sites: V pointer provenance and allocation generations, D result facts.
- Fixture SW/OB: a declared inner-pointer/addressor result with a held owner, then an aliasing operation and owner release. True pointer use is valid only within the proved owner lifetime.
- Before/after [I]: unknown dependent storage -> base-correlated address where declaration/body establishes dependence, expired when owner generation ends.
- Negatives: missing declaration, arbitrary pointer-returning helper, escaped base. Mutations: substitute another base, retain address after base destruction.
- Dependencies: O04-a/O05-d and F10-b for foreign inner-pointer attributes.

### 49. O06-b: pair a dynamic access token with its actual end

Axis: completeness. Size M. Confidence high.

- Rule: C/include/swift/Runtime/Exclusivity.h:31–50 and C/lib/IRGen/IRGenSIL.cpp:7192–7207,7345–7355 establish scratch lifetime, flags and omitted end for no-nested-conflict.
- Change sites: V scope-token generation/CFG joins and D access statements, reusing frame effects.
- Fixture SW: class property modified through inout across an ordinary and a throwing call. True cleanup ends the applicable tracked access once on each emitted exit.
- Before/after [I]: hidden independent marker calls -> scoped access fact only when checked address, flags and scratch generation agree.
- Negatives: no-track, static/unsafe erased access, missing end, nested same scratch reused, captured inout. Mutations: match by scratch address without generation, ignore throwing exit.
- Dependencies: O06-a/O05-a and external exit model. An access marker never proves noncapture of the user body.

### 50. O06-c: preserve signed-access temporary writeback

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/IRGen/IRGenSIL.cpp:7210–7268,7359–7408 creates a shadow temporary and authenticates/signs/writebacks pointer values.
- Change sites: V scoped memory effects and authentication facts, D field assignment reconstruction.
- Fixture OB/SW: controlled imported pointer-auth-qualified function-pointer field mutated through a Swift access, with null/non-null controls. Static arm64e oracle is acceptable when executable hardware is unavailable, labeled accordingly.
- Before/after [I]: unmodeled temporary -> writeback to the real field only after the matching signed scope completes.
- Negatives: key/modifier mismatch, null path, missing end/writeback. Mutations: skip resign/writeback, treat temporary as original storage.
- Dependencies: O06-b/K04. Do not call static assembly evidence a native execution result.

### 51. F11-a: identify a global block literal and its invoke target

Axis: completeness. Size M. Confidence medium pending Clang global-block oracle.

- Rule: Swift emits descriptor/invoke header fields at C/lib/IRGen/GenFunc.cpp:2895–2951 and invokes header field 3 at GenCall.cpp:6438–6455. Swift's stack emitter does not prove every Clang global-block variant.
- Change sites: new bounded literal fact consumed by D indirect-call resolution and CG, without inferring capture layout yet.
- Fixture OB: `long (^g)(long)=^long(long x){ return x+3; }; long run(void){ return g(7); }`. True result 10.
- Before/after [I]: unresolved indirect call -> invoke target associated with this exact block literal, hidden block operand retained internally.
- Negatives: fake isa provider, wrong descriptor size/flags/invoke section. Mutations: ignore isa binding, take descriptor field as invoke.
- Dependencies: F05-a/B03 and independent Clang block-layout oracle.

### 52. F11-b: identify a stack block from reaching header stores

Axis: completeness. Size M. Confidence high for Swift-emitted header shape.

- Rule: C/lib/IRGen/GenFunc.cpp:2860–2868,2931–2951 initializes stack-block isa, flags, invoke and descriptor.
- Change sites: V bounded frame-memory generation and D block-literal fact extraction.
- Fixture OB: `long run(long k){ long (^b)(long)=^long(long x){return k+x;}; return b(7); }`. True result k+7.
- Before/after [I]: stack address/unresolved invoke -> proved stack-block identity and invoke link, captures still unknown.
- Negatives: incomplete header, overlapping write, escaped or reused stack range. Mutations: accept partial store set, carry header across overwrite.
- Dependencies: F11-a/O05-a. Header recognition alone is not invocation ABI proof.

### 53. F11-c: recover one scalar block capture at its proved field offset

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenFunc.cpp:555–606 builds header plus capture storage; header generation uses its actual storage type. Do not guess all captures from a generic offset.
- Change sites: V block-relative load provenance and D capture naming.
- Fixture OB: block capturing `long k=11`, invoked twice with 3 and 7. True results 14 and 18, capture is not a formal argument.
- Before/after [I]: capture load `?` -> literal or named captured k tied to the same block generation.
- Negatives: byref mutable capture, object capture, unknown descriptor/extent. Mutations: read capture from another block, classify capture as user arg0.
- Dependencies: F11-b/B02. Object/byref captures require their own lifetime acceptance rows.

### 54. F11-d: model block heap copy as a new storage identity

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/IRGenSIL.cpp:6338–6343 explicitly calls block copy and uses its returned value. It is not retain identity.
- Change sites: exact objc_retainBlock/Block_copy operation fact, V block generation/lifetime, D rendering.
- Fixture OB: return an escaping capturing block from a function, invoke it after the creating stack frame has ended. True capture survives and computes its original value.
- Before/after [I]: visible copy call with no association -> heap-block result linked to copied captures, never the dead stack address.
- Negatives: unknown copy provider/helpers, byref capture not modeled. Mutations: treat copy as identity, let captures depend on the expired frame.
- Dependencies: F11-c/O05-a/O05-d. Preserve RuntimeStatementTests.swift:17–20 visibility controls.

### 55. F11-e: apply block invocation's hidden first operand and result schema

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenCall.cpp:1588–1591,6431–6455 prepends the block object and loads its invoke pointer.
- Change sites: B02 foreign block invocation layout, D arguments/results, P display.
- Fixture OB: `double (^b)(long,double)=^double(long n,double x){return n+x;};` plus a two-word struct-return block. True scalar result for 7,2.5 is 9.5.
- Before/after [I]: unresolved/shifted user operands -> `b(7,2.5)` with internal block operand, complete result only for the qualified schema.
- Negatives: @? without prototype, foreign callback pointer, unknown auth. Mutations: omit hidden block operand, use Swift x20 context.
- Dependencies: F11-a/F11-b/B02. Admit scalar first, aggregate result as a separate extension using F08-a.

### 56. F11-f: keep C callback arguments independent of Swift closure context

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenCall.cpp:1575–1619 distinguishes CFunctionPointer, Block and Swift representations.
- Change sites: D typed indirect callable identity, B02 callback layout and result projection.
- Fixture SW/OB: `typealias Callback = @convention(c) (Int64,Double)->Double`, implemented by a noncapturing Swift function and passed to a C driver calling `(7,2.5)`. True result 9.5.
- Before/after [I]: opaque callback -> declared foreign argument/result schema with no x20 Self/context operand.
- Negatives: unknown prototype, thick Swift closure, same-code-address different representation. Mutations: append x20, use ObjC block's hidden argument.
- Dependencies: F09-b/B02 and callable-representation owner C01.

### 57. F11-g: preserve argument/result conversion across a representation-changing thunk

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/IRGen/GenCall.cpp:6431–6455 has block invocation distinct from native callable emission. C/lib/IRGen/IRGenSIL.cpp:6338–6343 retains block-copy semantics.
- Change sites: callable thunk identity and D/V result association, not renderer string substitution.
- Fixture SW: `let b: @convention(block) (NSString)->NSString = { s in s.appending("x") as NSString }`, then convert/use through the supported native boundary. True result includes one appended x.
- Before/after [I]: explicit opaque adapters -> proven adapter call with correct boundary values, conversions retained when their effects are unknown.
- Negatives: reabstraction with unknown substitutions, escaping capture, unknown ownership. Mutations: skip conversion, reuse underlying function ABI at adapter entry.
- Dependencies: F11-e/F11-f, closure reabstraction owner C05, F10-b.

### 58. F10-b: retain foreign ownership attributes in the boundary fact

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/SIL/IR/SILFunctionType.cpp:3985–3993,4089–4145 distinguishes consumed arguments/self, owned/autoreleased results and inner-pointer results. Explicit family overrides matter at 4040–4060.
- Change sites: SDK declaration extraction, B03 provenance, D/V boundary result/argument facts. Encodings remain insufficient.
- Fixture OB: one `ns_returns_retained` result, one autoreleased result, a consumed parameter and `objc_method_family(none)` on an init-like name. Native counters establish independent lifetime behavior.
- Before/after [I]: carrier-only calls -> exact recorded ownership roles without inventing a stronger source lifetime.
- Negatives: encoding-only declaration, unavailable attributes, foreign twin. Mutations: infer owned from selector alone, ignore family override.
- Dependencies: F05-b/F09-b/O05-a. Attribute preservation is one behavior, not full ARC reduction.

### 59. F10-c: correlate an imported NSError outcome with its actual out parameter

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/SILGen/SILGenApply.cpp:6452–6461 selects the declaration's error parameter. C/lib/SILGen/SILGenForeignError.cpp:432–466 checks zero/nonzero, nil-result and nonnil-error conventions separately.
- Change sites: typed foreign-error convention, V edge-specific storage and D throw/result rendering.
- Fixture OB/SW: `BOOL perform:(NSError**)error` with success sentinel and deliberate failure, imported as Swift throws. True failure uses the selected error slot and success polarity.
- Before/after [I]: opaque bridge or unknown throw -> correlated result/error outcome with no stale success value on failure.
- Negatives: null out pointer, different BOOL polarity/attribute, ordinary NSError** data parameter. Mutations: swap out slot, invert success sentinel.
- Dependencies: F10-b/O05-f and external E09/X02. Verify exact Clang-imported declaration convention before admission.

### 60. F10-d: preserve exported Swift throws to Objective-C error translation

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/SILGen/SILGenForeignError.cpp:164–247 stores the bridged error and chooses the declaration's foreign success/failure sentinel. SILGenBridging.cpp:2112–2130 separates the synchronous result from completion invocation.
- Change sites: exported thunk boundary schema, V result/error output initialization and D rendering.
- Fixture SW: `@objc class C:NSObject { @objc func work(_ fail:Bool) throws -> NSNumber { ... } }`, invoked by ObjC while recording return and NSError contents.
- Before/after [I]: bridge helper calls/unknown outputs -> correct foreign result plus error-out effect on its actual failure edge.
- Negatives: nullable result without error convention, unknown thunk, untouched error slot. Mutations: write error on success, conflate native error register with foreign pointer.
- Dependencies: F10-c/O05-f. Completion-block exports are U02-d, not this sprint.

### 61. O07-a: recover a scalar _read yield without treating the continuation as value

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenCall.cpp:849–868 places continuation before ordered yields, while each yield has its own convention. Types.h:5248–5288 preserves YieldConvention.
- Change sites: D:13441–13456,13810–13821 narrow modify machinery, V yield-result facts.
- Fixture SW: `struct S { var n:Int; var read:Int { _read { yield n } } }`. True borrowed yielded value is n, not continuation x0.
- Before/after [I]: missing yield -> `yield self.n` only from a proved ramp and yield schema.
- Negatives: ordinary getter, final once continuation, name-only `.read` label. Mutations: use x0, use suffix alone as coroutine identity.
- Dependencies: B02/O04-a and descriptor identity. Existing stored modify/backing-field controls stay intact.

### 62. O07-b: recover one ordered multi-piece yield and its overflow

Axis: completeness. Size M. Confidence high in rule, medium in fixture emission.

- Rule: C/lib/IRGen/GenCall.cpp:854–907 expands each yield, then moves excess components to ordered overflow storage.
- Change sites: B02 coroutine result schema, V yield projections and D render facts.
- Fixture SW: generic `_read` yielding a mixed Int/Double aggregate. Add valid SIL with distinguishable multiple yields when source syntax cannot produce the overflow boundary.
- Before/after [I]: fixed x1 assumption/unknown yields -> ordered projections from proved direct and overflow pieces.
- Negatives: incomplete overflow extent, unknown convention, mismatched continuation schema. Mutations: shift by continuation word incorrectly, reverse overflow order.
- Dependencies: O07-a/O05-a/B02. Keep each unsupported yield piece unknown without shifting later roles.

### 63. O07-c: decode a callee-allocated coroutine's entry descriptor and allocator role

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/IRGen/GenCall.cpp:914–954,1994–2005 distinguishes context and SwiftCoro allocator for YieldOnce2. Types.h:5305–5310 distinguishes its lifecycle.
- Change sites: `MethodImplementation`, VT:152–160 and shared coroutine boundary facts.
- Fixture SW: toolchain-supported `yielding mutate` accessor beside legacy `_modify`, recording descriptor, code pointer, frame and allocator operands. Feature unavailable means unavailable oracle.
- Before/after [I]: descriptor slot declined as code -> qualified code/descriptor pair and distinct allocator role. Never borrow async x22 rules.
- Negatives: wrong descriptor indirection/flag, ordinary getter, unsupported authentication. Mutations: call record as code, conflate allocator and frame.
- Dependencies: O07-b/K01/K04 and compiler feature oracle. Exact x23 assignment needs separately available target backend evidence.

### 64. O08-a: match a legacy coroutine activation's normal completion

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/IRGenSIL.cpp:4906–4946 calls the captured continuation with its frame and false abort bit, then destroys temporaries.
- Change sites: V activation identity/scope and D typed continuation effects.
- Fixture SW: `_modify { log(1); yield &n; log(2) }`, caller increments n, then logs 3. True normal log order is 1,2,3.
- Before/after [I]: raw continuation call -> matched normal end of the same activation and expired yield scope.
- Negatives: nested same-callee frames, different continuation, stale allocator/frame. Mutations: match by callee only, retain yielded address after end.
- Dependencies: O07-a/O05-d/O06-b and exit/authentication facts.

### 65. O08-b: distinguish legacy abort from normal completion

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/IRGenSIL.cpp:4902–4935 derives the abort bit from abort_apply. SILGenApply.cpp:8197–8200 allows legacy unwind to skip its second half.
- Change sites: activation outcome edges in V/D.
- Fixture SW: throwing consumer inside `_modify` access with logs before yield, after yield and defer. True unwind follows the compiler-emitted abort cleanup, not the normal continuation path.
- Before/after [I]: undifferentiated continuation -> explicit abort outcome with correct scope expiration and cleanup order.
- Negatives: unrelated error edge, unknown abort bit, wrong frame. Mutations: force abort false, route throw through normal cleanup.
- Dependencies: O08-a and external exit model. Do not infer source defer order without emitted-path evidence.

### 66. O08-c: complete a new yielding accessor even when its caller throws

Axis: completeness. Size M. Confidence high in rule, medium in local executable oracle.

- Rule: C/include/swift/AST/Types.h:5305–5310 and SILGenApply.cpp:8202–8204 require completion rather than legacy unwind. IRGenSIL.cpp:4929–4943 passes allocator instead of abort bit.
- Change sites: V activation kind and D cleanup effects.
- Fixture SW: enabled `yielding mutate` accessor with post-yield log, paired with the same throwing consumer as O08-b. True post-yield work still runs.
- Before/after [I]: opaque new continuation -> matched completion on throw, using frame plus allocator.
- Negatives: legacy accessor, unavailable feature, unknown allocator/authentication. Mutations: apply legacy abort rule, omit throw-edge completion.
- Dependencies: O07-c/O08-b. Callee-allocated frame death is a separate proved cleanup point.

### 67. O08-d: replace the continuation across repeated YieldMany activations

Axis: completeness. Size M. Confidence medium until valid SIL oracle is captured.

- Rule: C/lib/IRGen/GenCall.cpp:840–845 repeats the ramp yield schema for YieldMany continuations. Types.h:5312–5314 permits multiple yields.
- Change sites: V activation generation/continuation state and D yield facts.
- Fixture: authored valid SIL yields 11 then 29 from one activation, with two calls and matched final cleanup. Source syntax is not assumed available.
- Before/after [I]: unmodeled repeated continuation -> each yield uses its current continuation and same live activation, with exactly one final cleanup.
- Negatives: nested activation of same function, repeated stale continuation, incomplete CFG. Mutations: reuse first continuation, merge activations by callee.
- Dependencies: O07-b/O08-a/O08-b. Keep task/async resume analysis separate.

### 68. U01-a: retain declared ABI while keeping replacement target effects open

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenDecl.cpp:3101–3155 chooses original versus runtime replacement through a chain/key.
- Change sites: metadata/callable identity, D indirect resolution and CR exact-body effect admission.
- Fixture SW: separately linked `dynamic func value(_ x:Int)->Int { x+1 }` and `@_dynamicReplacement(for:value(_:))` returning x+9 and mutating a sentinel.
- Before/after [I]: runtime calls and opaque indirect dispatch -> replacement-aware declared ABI with open target/effects. Do not recover the original body's constant or field-preservation summary.
- Negatives: mutable chain, unknown key, replacement provider unresolved. Mutations: freeze chain at original pointer, reuse original body effect.
- Dependencies: B01/B03/K04. Existing unresolved behavior is safe, not an observed current wrong render.

### 69. U01-b: identify previous implementation separately from original definition

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenDecl.cpp:3433–3503 calls `swift_getOrigOfReplaceable`, forwards arguments and may tail-call the selected previous implementation.
- Change sites: replacement-chain fact, D callee display and CR target/effect proof.
- Fixture SW: two separately linked replacements with distinct sentinels, newest explicitly calling the replaced declaration according to compiler-supported chaining syntax. True result/log identifies previous link, not necessarily the source original.
- Before/after [I]: opaque runtime pointer -> `previous implementation` relation with exact ABI, target effects open unless link is independently immutable/proved.
- Negatives: reordered/unknown chain, disabled chaining, wrong key. Mutations: call source original directly, ignore previous-link identity.
- Dependencies: U01-a.

### 70. U01-c: preserve async replacement descriptor association

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/IRGen/GenDecl.cpp:3103–3108,3128–3132,3157–3188 distinguishes async function record, authentication and dynamic context size.
- Change sites: async descriptor owner and replacement fact in D, no cross-await scalar inference.
- Fixture SW: emitted dynamic async method with separately linked replacement and distinct result/effect, plus one real suspension.
- Before/after [I]: opaque replacement async call -> declared async boundary and linked selected code/context-size record, values still unknown unless async owner/effect proof closes independently.
- Negatives: code/size pair mismatch, wrong auth category, unknown replacement. Mutations: use sync pointer schema, retain original context size.
- Dependencies: U01-a and external A06/K04.

### 71. U01-d: preserve coroutine replacement's distinct descriptor category

Axis: completeness. Size M. Confidence medium-low until emission is established.

- Rule: C/lib/IRGen/GenDecl.cpp:3106–3108,3128–3132,3483–3487 has a callee-allocated coroutine replacement category distinct from sync and async.
- Change sites: shared replacement/coroutine descriptor facts, VT consumer.
- Fixture SW: compiler-supported dynamically replaceable yielding accessor with different yielded storage. If toolchain cannot emit it, retain an unavailable matrix row and no positive implementation.
- Before/after [I]: opaque descriptor -> correct coroutine boundary, never async code/context interpretation.
- Negatives: legacy/ordinary accessor, unsupported feature, wrong descriptor flag. Mutations: select async auth schema, treat descriptor as code.
- Dependencies: U01-a/O07-c/K04.

### 72. U02-a: identify the declaration's completion-block slot

Axis: completeness. Size S. Confidence high.

- Rule: C/include/swift/AST/ForeignAsyncConvention.h:30–40,63–107 stores completion, error and flag indices separately. The completion formal disappears from imported Swift async signature at 142–145.
- Change sites: imported foreign boundary facts, SDK/interface evidence and D call layout.
- Fixture OB/SW: `-fetch:(long)n completion:(void (^)(long,NSError*))done`, imported async. True n is ordinary formal, done is the selected block slot.
- Before/after [I]: ordinary @? argument -> declaration-qualified completion role with no assumed continuation relationship yet.
- Negatives: second unrelated block, selector-only evidence, unknown import convention. Mutations: use last block by heuristic, shift slot around erased parameter incorrectly.
- Dependencies: F05-b/F11-e/F10-b.

### 73. U02-b: associate a successful completion invocation with its Swift continuation

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/SILGen/SILGenThunk.cpp:575–605 prepares the result and resumes the captured continuation. Error/flag indices account for hidden block storage at 423–429.
- Change sites: block capture provenance, async continuation operation fact and D render association.
- Fixture OB/SW: fetch completes with 37 immediately in one provider and later on a queue in another. True awaited result is 37 in both, completion occurs once.
- Before/after [I]: disconnected block/continuation calls -> bounded association of this block invocation, captured continuation and result buffer.
- Negatives: foreign/unknown continuation, capture overwritten, possible double completion. Mutations: associate wrong continuation, ignore hidden block offset.
- Dependencies: U02-a/O05-f and external A07. Delayed writers require their own admitted lifetime/effect proof.

### 74. U02-c: choose foreign-async failure from the declared sentinel polarity

Axis: completeness. Size M. Confidence high.

- Rule: C/include/swift/AST/ForeignAsyncConvention.h:69–107 and SILGenThunk.cpp:423–510 let a flag override nullable-error presence, with explicit zero/nonzero polarity.
- Change sites: typed foreign-async convention, V outcome facts and D throw/result rendering.
- Fixture OB/SW: paired APIs with documented success flags of opposite polarity and distinguishable values/errors. True outcome follows each declaration's flag, not the error object's name or non-nullness alone.
- Before/after [I]: unknown outcome -> correct completion success/error edge, inactive result pieces unavailable.
- Negatives: missing flag contract, mismatched index, contradictory malformed completion. Mutations: invert polarity, test NSError presence despite flag independently.
- Dependencies: U02-b/F10-c and external X02/A07.

### 75. U02-d: preserve exported async-to-completion direction and optional handler

Axis: completeness. Size M. Confidence high in rule, medium in emitted evidence.

- Rule: C/lib/SILGen/SILGenBridging.cpp:1802–1843 consumes/unwraps the optional completion and computes its error flag. Later result/error invocation is separate from immediate foreign return.
- Change sites: exported thunk boundary, D block-call facts and V handler/capture lifetime.
- Fixture SW/OB: @objc async throwing method with ObjC completion caller, testing non-null handler, null handler where allowed, success and failure. True nil-handler path discards completion result without invoking a block.
- Before/after [I]: raw bridge calls -> direction-correct completion invocation or no invocation, preserving immediate return separately.
- Negatives: import bridge, unknown handler nullability, erased convention. Mutations: invoke nullable nil handler, confuse async result with immediate return.
- Dependencies: U02-c/F10-d/O05-f.

### 76. X01: name a defined global data symbol without claiming its value

Axis: completeness. Size S. Confidence high.

- Readiness owner: globals named by symbol, PRODUCTION-READINESS.md:839–842,861–869.
- Rule: C/lib/IRGen/GenDecl.cpp:2759–2788 builds a global address from its linkage entity, distinct from contents.
- Change sites: D:5516–5530 `ReferenceResolver.name`, symbol-index initialization and V address rendering.
- Fixture OB/SW: `long gCounter; long read(void){return gCounter;}` plus a Swift global. True load is current storage, not initial bytes.
- Before/after [I]: raw address memory load -> `gCounter`/`&gCounter`, value still mutable.
- Negatives: colliding/aliased symbols, interior pointer, stripped symbol, writable rebased slot. Mutations: choose arbitrary first name, substitute initial contents.
- Dependencies: none for address naming. Preserve fixed-pointer and mutable-global distinctions.

### 77. X02: index selector references independently of function names

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenObjC.cpp:854–856 emits a selector reference independently of chosen messenger. OS:37–60 already recovers those identities.
- Change sites: CG:129–145 slim site facts, XC:43–44,136–139 query/diagnostics.
- Fixture OB: one selector invoked through modern stub and old selref path, plus an unused selector reference. True sends are two sites, not every matching string.
- Before/after [R/I]: `-f objc_msgSend$foo` already handles named stubs -> dedicated selector query also reports proved generic sends and distinguishes reference from invocation.
- Negatives: unrelated string, unknown dispatcher, unused selref. Mutations: query callee text only, count every selref as a send.
- Dependencies: F05-a. Keep streaming memory bounded and consult metadata oracle before a no-result diagnostic.

### 78. X03: index exact string references as data references

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenObjC.cpp:1327–1331 emits a distinct global string entity. A reference is not necessarily an executed call argument.
- Change sites: D literal/address facts, slim cross-reference records, XC query mode.
- Fixture OB: `puts("audit unique"); const char *p="audit unique";`, with an unused identical-looking byte sequence. True references distinguish address formation, load and call use.
- Before/after [I]: no string query -> exact reference sites and owners, no invented call edge.
- Negatives: pooled suffix, same text at different addresses, raw bytes outside valid string extent. Mutations: substring-address conflation, omit non-call reference.
- Dependencies: X01. No full decoded-image retention.

### 79. X04: cross-reference data-symbol reads and writes

Axis: completeness. Size M. Confidence high.

- Rule: C/lib/IRGen/GenDecl.cpp:2759–2788 separates global storage address from function linkage. Symbol-table evidence is the independent existence oracle.
- Change sites: slim reference records and XC:136–139, not the call-edge type.
- Fixture OB: `long g; long read(void){return g;} void write(long n){g=n;}`. True graph has a read and write reference, no call to g.
- Before/after [R/I]: `xrefs -f _g` can say no function matched -> explicit data query reports existing symbol and its accesses, or existing-with-no-proved-references.
- Negatives: symbol absent, alias/interior access, stripped name. Mutations: only collect calls, collapse absent-symbol and zero-reference diagnostics.
- Dependencies: X01/X03 record infrastructure.

### 80. X05: recover a proved native Array storage count

Axis: completeness. Size M. Confidence medium.

- Rule: C/stdlib/public/core/ArrayBody.swift:22–64 separates count from shifted capacity/flags. ContiguousArrayBuffer.swift:644–646 reads count through storage. SL:99–104 proves only collection value carrier, not header layout.
- Change sites: typed storage projection facts in V/D, `FieldMap` trusted-layout policy.
- Fixture SW: `@inline(never) func count(_ a:[Int])->Int { a.count }`, with empty, nonempty and reserved-capacity arrays. True count ignores capacity.
- Before/after [I]: raw header/unknown return -> `arg0.count` only after native storage kind and layout/version are proved.
- Negatives: bridged NSArray, unknown storage kind, arbitrary one-pointer wrapper. Mutations: read capacity word as count, omit native-kind check.
- Dependencies: F01-b/O05-a and versioned runtime/layout evidence. Hardcoded guessed offsets are forbidden.

### 81–82. X06 and X07: recover Dictionary and Set counts separately

Axis: completeness for each. Size M for each. Confidence medium. These use their own storage rules, not Array's layout.

- Compiler/stdlib rules: C/stdlib/public/core/DictionaryStorage.swift:26–46 and SetStorage.swift:26–46 declare distinct count, capacity and scale fields. NativeDictionary.swift:359–363 and NativeSet.swift:349–353 read `_storage._count`. SL:99–104 proves only one-pointer value transport. A versioned nominal storage/layout proof is still required before naming a load.
- Change sites: V/D typed collection projection, never a shared universal collection header offset.
- X06 fixture SW: `func f(_ d:[Int:Int])->Int { d.count }`, including empty/tombstone-heavy/native and bridged controls. Before `?` -> `d.count` only for the proved dictionary kind. Mutation: use Array count offset, ignore deleted bucket state.
- X07 fixture SW: `func f(_ s:Set<Int>)->Int { s.count }`, with empty/removal/reserved-capacity controls. Before `?` -> `s.count` only for the proved set kind. Mutation: use dictionary layout, confuse count with capacity.
- Negatives for both: unknown/bridged storage, runtime-version mismatch, unrelated pointer wrapper.
- Dependencies: X05 infrastructure only. Neither inherits X05's storage rule. Land these as two commits after qualifying native versus bridged storage and their target/version layouts.

### 83. X08: distinguish empty render causes without claiming purity

Axis: soundness. Size S. Confidence high in misleading diagnostic.

- Rule: nonempty machine code can contain scoped runtime effects or yields, C/lib/IRGen/IRGenSIL.cpp:4859–4891,7192–7207. Missing source statements do not prove a pure leaf.
- Change sites: P:60–64 and Structurer.swift:24–26 fallback, using typed suppression/unmodeled counts.
- Fixture SW: `func empty(){}`, `func compute(_ x:Int)->Int{x+1}`, runtime-only cleanup body and `_read` with an unsupported yield. True categories differ.
- Before/after [R/I]: shared `leaf / pure computation` for every nonempty statement-free body -> distinct no-decoded-code, hidden-runtime-only, and no-recovered-source-statements messages. Do not label unmodeled instructions pure.
- Negatives: fallthrough, unresolved branch/call, all-hidden side effect. Mutations: always select leaf message, count filtered instructions as absent.
- Dependencies: none. This diagnostic can land early if it blocks evidence collection. It does not recover missing code.

## C++ interop, deliberately last

The following sprints list the required work without claiming Swift source alone establishes Clang's complete Darwin C++ ABI. Each requires the missing Clang/target oracle first. Swift and Objective-C usefulness outranks them.

### 84. F13-a: represent a C++ member receiver separately from Swift Self

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/IRGen/GenCall.cpp:1593–1644 moves C++ receiver first and calls arrangeCXXMethodCall. Types.h:4547–4551 has Indirect_In_CXX.
- Change sites: B01 callable representation, B02 foreign layout, D/V receiver roles.
- Fixture: `struct C { long n; long f(long x) const {return n+x;} };`, imported into Swift with C++ interop, paired with a static/free function. True f result uses this, free call has no this.
- Before/after [I]: opaque call -> declaration-qualified C++ member call, no Swift x20 inference.
- Negatives: unavailable declaration, Itanium name without result type, unknown reference indirection. Mutations: put this in x20, add this to free function.
- Dependencies: F09/B02 and independently pinned Clang oracle.

### 85. F13-b: identify constructor destination independently of ordinary result

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/IRGen/GenCall.cpp:1562–1567,1602–1607 inserts constructor object pointer even for CFunctionPointer representation. GenStruct.cpp:682–719 sketches the complete constructor signature.
- Change sites: foreign constructor boundary/result-storage role in D/V.
- Fixture: `struct C { long n; C(long x):n(x){} };` constructed from Swift, with native destination sentinel. True construction initializes this storage, not an unrelated x0 source result.
- Before/after [I]: opaque ctor/result -> initialized constructor destination only under complete variant/signature proof.
- Negatives: placement constructor, unknown constructor variant, aliasing storage. Mutations: treat ctor as ordinary return, reverse this/source.
- Dependencies: F13-a/O05-a and Clang oracle.

### 86. F13-c: distinguish nontrivial indirect C++ result from register aggregate

Axis: completeness. Size M. Confidence medium-low.

- Rule: C/lib/IRGen/GenCall.cpp:1636–1657 delegates C++ return arrangement and checks formal indirect agreement. Nontrivial cleanup is separate from carrier placement.
- Change sites: B02 foreign result schema and IR eligibility, V result storage.
- Fixture: C++ type with nontrivial destructor returned by value from a free function, plus trivial two-long control. True native result fields and destination address must match Swift/Clang callers.
- Before/after [I]: unknown result -> correct declared direct/indirect role, no first-word-as-whole interpretation.
- Negatives: unavailable declaration, trivial_abi variation, return-in-place ambiguity. Mutations: force GP return, swap this/sret ordering.
- Dependencies: F13-b/O05-f and Clang target classifier.

### 87. O09-a: preserve nontrivial C++ copy-construction effects

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/IRGen/GenStruct.cpp:722–805 selects and invokes complete copy/move construction with a destination and source.
- Change sites: V initialized storage effects and foreign constructor operation fact.
- Fixture: `struct C { C(const C&){log(1);} ~C(){log(2);} };` copied through a Swift boundary. True copy/destroy counts and order come from native logs.
- Before/after [I]: opaque constructor -> copy-initialized destination and live source, arbitrary constructor effects retained.
- Negatives: deleted copy, unknown complete variant, custom mutation in ctor. Mutations: model as POD memcpy, invalidate source as move.
- Dependencies: F13-b/O05-a and Clang lifetime oracle.

### 88. O09-b: preserve nontrivial C++ move-construction source state

Axis: completeness. Size M. Confidence medium-low.

- Rule: C/lib/IRGen/GenStruct.cpp:954–968 selects move constructor or copy fallback, then explicitly destroys source storage. Assignment additionally destroys the old destination at 976–991.
- Change sites: foreign lifetime fact and V storage generations.
- Fixture: C++ `C(C&& other){...; other.n=-1;}` with a logging destructor and a Swift-supported take path. True lowering constructs the destination, then destroys the moved-from source once.
- Before/after [I]: opaque helper -> ordered constructor effects followed by source destruction. Source is not kept live after the complete Swift take helper.
- Negatives: copy fallback, deleted move, unknown constructor body. Mutations: omit source destruction, invalidate source before the constructor can read or mutate it.
- Dependencies: O09-a and actual compiler-emitted move oracle.

### 89. O09-c: preserve complete destructor and cleanup responsibility

Axis: completeness. Size M. Confidence medium.

- Rule: C/lib/IRGen/GenStruct.cpp:835–886 selects Dtor_Complete, handles implicit operands and possible foreign exception handling.
- Change sites: exact destructor variant, V cleanup ownership and outcome facts.
- Fixture: nontrivial C++ by-value parameter and return, logging copy/move/destruction across Swift caller and callee. True cleanup runs exactly once at the responsible side.
- Before/after [I]: opaque destructor -> precise cleanup point without treating custom destruction as pure.
- Negatives: deleting/base variant, unknown ABI ownership, foreign throwing destructor. Mutations: swap caller/callee destruction, hide destructor effect.
- Dependencies: O09-a/O09-b/F13-c and external exception model. Never assume all C++ parameters are callee-destroyed.

### 90. F13-d: retain a proved virtual this adjustment

Axis: completeness. Size M. Confidence low until Clang/target implementation and oracle are available.

- Rule boundary: C/lib/IRGen/GenCall.cpp:1593–1644 delegates C++ member arrangement. That does not establish multiple-inheritance thunks or vtable adjustment rules.
- Change sites: foreign dispatch identity and adjusted-receiver provenance in D/V, not Swift VT offsets.
- Fixture: C++ multiple inheritance with a virtual method called through a non-primary base and distinct field sentinels. True result identifies the adjusted subobject.
- Before/after [I]: unresolved call -> declared virtual member with proved adjusted this, exact target effects still open.
- Negatives: unknown thunk, virtual base, runtime override, missing declaration. Mutations: omit adjustment, treat declared slot as exact implementation.
- Dependencies: F13-a/O09-c and missing Clang ABI source/oracle. This remains last even if its positive sample is easy.

## Scope ledger and intentionally unclosed variants

The ordered queue gives each broad audit domain an implementation route, but does not pretend a finite list of sample shapes proves all variants. The following require additional one-operation rows when first admitted:

- F01/F02 need class-bound generic/existential Self, closure/reserved context and pack formals from B01/B02/T01. The first guard does not close these placements.
- F03 needs failable and throwing initializer outcomes, convenience/delegating and isolated destructor variants after the ordinary entry slice. F03-c's source rule distinguishes the destroying return from subsequent deallocation.
- F05 needs separately applicable protocol and category declarations after ancestry recovery. Extended/quoted/unsupported encoding tokens remain reasoned declines until OA has an independent classifier row.
- F08's GP, HFA and x8 slices do not imply unions, vectors, varargs, other architectures or every nil/consumed-argument cleanup rule.
- F09 needs narrow unsigned and Bool results, variadic boundaries, structured C prototypes and reexports/availability selection from B02/B03. One scalar result does not close C ABI.
- F10's contract fields do not justify removing ownership operations. CF attributes, return-handshake marker variants and consumed-self outcomes each need their own acceptance row.
- F11's scalar capture does not cover object/byref captures or arbitrary copy/dispose helpers. Those need lifetime effects and independent literal/invoke linkage.
- O01 needs exact convention masks, runtime aliases and reexports qualified separately. The local compiler's release_n result declaration differs from several void release families. Do not classify the entire release prefix as void or identity.
- O03/F12 still need weak take-init, copy-assign, take-assign and corresponding unknown/unowned operations as individual transitions. The shared schema reduces implementation cost, not evidence obligations.
- O05 needs assign-with-take, initialized indirect packs and custom witness destruction effects. Builtin array copy/take/assign selection at C/lib/IRGen/GenBuiltin.cpp:1384–1402 is a separate operation family with overlap-direction rules.
- O06 needs no-track flags, unpaired accesses, no-nested-conflict, disjoint fields and historical pointer escape checks. Missing dynamic markers cannot prove absent exclusivity or noncapture.
- O07/O08 need normal accessor result conventions GuaranteedAddress/Guaranteed/Inout separately from yielded parameter conventions. C/include/swift/AST/Types.h:5012–5022 establishes that separation. New-frame deallocation at dealloc_stacks needs its own lifetime proof beyond continuation invocation.
- U01/U02 and C++ variants with unavailable emission/source oracles stay explicitly unavailable. No guessed target, lifetime or outcome is an acceptable replacement.

If the integrator wants only the first executable milestone, land sprints 1–8 as narrow guards after reproducing their source risks. Then qualify one complete class/ObjC scalar call path before broadening layouts. The storage and block work is valuable because ordinary completions and ownership flows depend on it, not because passing its tests would imply general ABI closure.

## Currently suspected wrong output, not guarded declines

No item below is newly reproduced. The distinction matters because this session was prohibited from running the decompiler or compiler.

1. **Foreign runtime-prefix calls can disappear. [R premise, I render]** P:1236–1264 uses exact provider gating only for `isARCReferenceHelper`, whose membership at P:1316–1318 excludes releases and access markers. A foreign prefix twin can therefore be hidden even when it performs an observable action. O01-a is the first probe/fix.
2. **Foreign access-marker or other ungated helper twins can preserve stale field names. [R premise, I wrong value]** V:1161–1162,2500–2507 and CR:1014–1019 accept several non-identity spellings without provider proof. T/FieldAliasTests.swift:36–45,94–99 confirms that behavior intentionally. If the actual callee mutates a field, a pre-call snapshot printed as that field denotes the post-call value. O06-a covers direct and outlined recurrence.
3. **An incomplete selector stub or fake messenger can become an Objective-C send. [R premise, I render]** OS:124–135 checks two selector-load instructions but not the final dispatcher. P:357–377 chooses message syntax from the name. Wrong receiver/argument/result interpretation is possible. F05-a must distinguish benign selector naming from ABI authority.
4. **Missing method metadata can shift an ordinary IMP's arguments. [R premise, I wrong value]** D:6444–6447 declares direct ABI from absence plus local class name. Ordinary IMP x1 is SEL, while direct x1 is first explicit formal. The erroneous premise can turn a selector into a source argument or move later arguments. F06-a is a source-confirmed guard target, not a reproduced current binary failure.
5. **An external value method can acquire unrelated address-shaped x20 as Self. [R premise, I wrong receiver]** D:9810–9888 has representation filters, but an external target without a summary bypasses the positive entry-read veto. Address shape alone cannot select the compiler's convention. F01-a needs a linked decoy-carrier repro before claiming the exact manifestation.
6. **A virtual tail can inherit a base method's passthrough result. [R premise, I wrong value]** D:4597–4608 records a declared vtable implementation address. D:9462–9473 can then classify a tail by that body's unwritten-result summary without a virtuality veto. CG:14–17 already recognizes that a subclass override may run. A base identity/override-plus-nine fixture should expose any `return arg0` substitution. F04-a covers field/argument dispatch as well as self dispatch.
7. **A correctly provider-qualified runtime name can receive an unproved direct-result convention. [R premise, I corruption]** IR:213 treats swift_/objc_ prefixes as direct after separate membership checks. That is not an exact result declaration. A future/unsupported runtime member or stale catalog interaction can let stale result-buffer contents survive. O01-b removes the premise. I have not identified a current system runtime function that concretely refutes this fallback.
8. **Foreign twins of three void-runtime names lose their result. [R premise, I omission]** V:1164–1166,1191 sets void by spelling, then V:2352–2360 clears x0/v0. A value-returning foreign `swift_job_run` is a direct counterexample candidate. This primarily loses completeness rather than inventing a value, but can alter exit rendering, so provider qualification belongs in the first guard batch.
9. **Empty rendered bodies can be mislabeled pure leaves. [R misleading statement]** P:61–64 distinguishes no instructions, then calls every remaining empty statement list `leaf / pure computation`. Unsupported `_read`/backing-field yield controls explicitly expect that message at T/ReconstructionTests.swift:658–663. X08 corrects the diagnostic without claiming recovery.

The following are **not** current confirmed wrong-output claims: the original F07 false adoption (fixed), the old untyped struct positional layout (guarded), arbitrary aggregate results (`?`), missing block captures, spilled adoption, self-result stores, globals, collection counts, U01/U02, or C++ lifetimes. Tail-called retain duplication remains a historical wrong-output lead with targeted reproduction still required. Keep those distinctions in the integration plan and in any status update.

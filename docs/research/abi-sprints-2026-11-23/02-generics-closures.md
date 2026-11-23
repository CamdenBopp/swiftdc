# Generics and callable ABI sprints

Read-only source review, 2026-11-23. No compiler, decompiler, build, test, native execution, or performance measurement was run. Fixture sketches below are proposals, not compiled evidence. Before/after examples are acceptance targets unless explicitly described as an existing test assertion. No project file was changed.

## Revisions and evidence limits

- Official compiler checkout `<swift checkout>` is **`1b7bd8eaf460396047c2644d1d69afb4a404b13d`**, subject `Merge pull request #91963 from xedin/called_once+dependent-types`. Its working tree was clean when inspected. It **does not match** the plan's `83eb12448e4323abbf81b0153dced2faff02d22f`. `git cat-file -t` cannot find that pinned object locally. This review verifies local rules, not a complete commit-to-commit diff or the installed compiler's provenance.
- swiftdc HEAD is **`ca9eef5ce2909f5f584d8270026f606c3f1b1e0e`**, on `dev`. There is substantial pre-existing WIP. I read the current source and checked its relevant differences from HEAD. The changed Disassembler hunks concern the draft async closed-caller work, not the generic/callable rules below. Disassembler citations below use **committed HEAD line numbers**, located with `git grep -n ... HEAD`; current working-tree line numbers are shifted by the async additions. Other cited source/test files are unchanged in the inspected diff. Do not interpret the draft async files as shipped support.
- `docs/STATUS.md:5-13` describes a published qualification, not this HEAD's test result. `docs/ABI-CLOSURE-PLAN.md:27` already records the G07 guard. The old G07 audit's present-tense wrong-label claim is stale.
- Relevant readiness leads remain at `docs/PRODUCTION-READINESS.md:776-842`: function-typed storage, merged closures/forwarders, source metatypes, generic cast types, merged specializations, capture descriptors, and descriptorless generic witness calls. These are reproduction leads, not fresh measurements.
- Evidence notation: **R** means the mechanism or test assertion was verified by reading code. **I** means a predicted binary/render consequence or proposed extension. **H** means historical execution reported by repository documentation, not repeated here. No new end-to-end claim is made.

Classification counts across the 18 whole audit items: **0 already closed, 8 partially closed, 3 safely declined, 7 possibly wrong**. A possibly-wrong classification takes priority over the bounded support an item also has. It does not mean a fresh native counterexample was executed. The scalar G07 defect is closed as a subcase; G07 as a whole is not.

### Citation shorthand

All shorthand below expands to an absolute local file path. A range attached to a shorthand is a file:line citation, not an audit's old line number.

| Shorthand | Absolute path |
| --- | --- |
| D | `Sources/SwiftDecompilerCore/Disassembler.swift` at HEAD |
| VT | `Sources/SwiftDecompilerCore/ValueTracking.swift` |
| SS | `Sources/SwiftDecompilerCore/SpecializedSignature.swift` |
| SL | `Sources/SwiftDecompilerCore/SwiftLowering.swift` |
| PS | `Sources/SwiftDecompilerCore/Pseudo.swift` |
| SI | `Sources/SwiftDecompilerCore/SwiftIdioms.swift` |
| TI | `Sources/SwiftDecompilerCore/TypeInference.swift` |
| VI | `Sources/SwiftDecompilerCore/VTableIndex.swift` |
| MS | `Sources/SwiftDecompilerCore/MetadataSymbolizer.swift` |
| ST | `Sources/SwiftDecompilerCore/SelfTypeIndex.swift` |
| CR | `Sources/SwiftDecompilerCore/CalleeRegisterSummary.swift` |
| FM | `Sources/SwiftDecompilerCore/FieldMap.swift` |
| IR | `Sources/SwiftDecompilerCore/IndirectResults.swift` |
| Tests | `Tests/SwiftDecompilerCoreTests/` |

## Compiler rules re-read in the local checkout

These rule keys provide the compiler citation for each inventory row and sprint. The local checkout is the authority for these citations.

| Rule | Verified local rule and citation | Difference from the audit citation |
| --- | --- | --- |
| K01 | Canonical invocation requirements are shape classes, canonical type/value parameters, then conformances requiring tables. Fulfilled requirements are omitted. Witness Self and ObjC Self have separate source rules. `<swift checkout>/lib/IRGen/GenProto.cpp:215-331,369-481,4390-4478`. | Enumeration remains at 280; expansion moved from audit 4368 to 4390 and trailing witness expansion from 4444 to 4466. Do not transplant the old ranges. |
| K02 | Exact metadata can fulfill its own type. Inexact metadata can expose nominal generic arguments but does not establish exact identity. Inherited protocol paths are explicit. `<swift checkout>/lib/IRGen/Fulfillment.cpp:129-185,237-261,298-352`. | The audit's 37-341 range no longer contains the entire inherited-table rule, which continues through 352. |
| K03 | Class-constrained archetypes use references, fixed-size trivial constraints have a distinct representation, other archetypes are opaque. Formal indirectness and native parameter expansion are separate. `<swift checkout>/lib/IRGen/GenArchetype.cpp:339-426`; `<swift checkout>/lib/IRGen/GenCall.cpp:1820-1869`. | Archetype rule remains at 339; parameter expansion's local endpoint is 1869, not the audit's assumption about source type alone. |
| K04 | More than one formal indirect result disables sret. Direct and indirect results are expanded independently. `<swift checkout>/lib/IRGen/GenCall.cpp:686-761`. Substituted function-value abstraction can preserve an error channel independently of concrete throwing behavior, `<swift checkout>/lib/SIL/IR/SILFunctionType.cpp:2870-2943`. | Result expansion starts at 686 rather than 688. SIL function-type lines are additional local evidence. |
| K05 | Witness Self metadata and table trail the call. Slot loads account for conditional tables, relative tables and entry-specific authentication. `<swift checkout>/lib/IRGen/GenProto.cpp:4466-4478,4481-4512,4563-4622`. Relative tables default off in `<swift checkout>/include/swift/AST/IRGenOptions.h:697`. | `emitWitnessMethodValue` moved from 4541 to 4563. Relative support is not automatically installed-toolchain support. |
| K06 | Type metadata has a VWT-bearing header. Required and enum-extension witnesses have distinct signatures and slot rules. `<swift checkout>/include/swift/ABI/Metadata.h:152-176`; `<swift checkout>/include/swift/ABI/ValueWitness.def:97-180,258-289`; `<swift checkout>/include/swift/ABI/MetadataValues.h:165-185`; `<swift checkout>/lib/IRGen/GenOpaque.cpp:390-485`. | The header is now split into a layout prefix and VWT base at 160-169, not the audit's Metadata.h 341-389. `HasEnumWitnesses` is explicitly at MetadataValues.h 181. |
| K07 | Opaque containers contain buffer, metadata and applicable tables. Class containers contain object plus tables; ObjC/marker protocols need no table. Error has its own box. Existential metatypes carry metadata plus applicable tables. `<swift checkout>/lib/IRGen/GenExistential.cpp:1670-1899,1985-2022`. | Audit conversion/opening range 1560-1860 is insufficient locally. `emitMetatypeOfOpaqueExistential` moved from 2033 to 2209. |
| K08 | Resilient structs have opaque lowering despite implementation layout. Opaque descriptor substitutions use an ordered requirements buffer. `<swift checkout>/lib/IRGen/GenStruct.cpp:1901-1924`; `<swift checkout>/lib/IRGen/GenArchetype.cpp:443-489`. | The audit's GenStruct 1797-1845 now covers projection and declaration emission, not the resilience converter. This is a substantive citation mismatch. |
| K09 | Metadata accessors receive request then 0-3 direct key arguments or one pointer to all arguments. Response includes metadata and state. Class generic offsets depend on resilient bounds. Field-offset vectors are runtime initialized. `<swift checkout>/lib/IRGen/MetadataRequest.cpp:2533-2567,2592-2623`; `<swift checkout>/include/swift/ABI/Metadata.h:96-113,3861-3953,4684-4707`; `<swift checkout>/lib/IRGen/GenMeta.cpp:3288-3406`. | Access call moved +2, GenMeta initialization +22, MetadataAccessFunction from audit 3798 to 3861, class argument offset from 4605 to 4686. |
| K10 | Descriptor key arguments start with pack lengths, then metadata/pack pointers, tables/table packs, then values. This is not identical to invocation ordering. `<swift checkout>/include/swift/ABI/GenericContext.h:59-106,264-349`; kinds are `<swift checkout>/include/swift/ABI/MetadataValues.h:2254-2264`. Pack shape, metadata packs, witness packs and value-address arrays are separate, `<swift checkout>/lib/IRGen/GenPack.cpp:157-193,457-502,598-638,1144-1188`. | These main GenPack ranges still match their named mechanisms. Never reuse descriptor-array order as the function invocation order in K01. |
| K11 | Thick/noescape function storage is two words, blocks one object, thin/method/witness/closure/C/key-path representations one code pointer. Differentiable products are dispatched before that representation switch. `<swift checkout>/lib/IRGen/GenFunc.cpp:606-668`. | Audit 605-665 misses the end of ordinary thick allocation at 666-668. |
| K12 | Pointer-representable self is a special context; thick functions need context and synchronous throwing thin entries reserve one. Formal parameters and generics precede context/error. `<swift checkout>/lib/IRGen/GenCall.cpp:1885-1918,2020-2106`. Method rationale also appears in `<swift checkout>/docs/ABI/CallingConvention.rst:574-614`. | The local rule retains the mechanism. A slot's existence does not prove it is a lexical capture, receiver or error. |
| K13 | Partial apply stores necessary bindings and captured operands, may adopt one object, and otherwise uses an optimal heap layout. Witness context and dynamic function context are distinct. `<swift checkout>/lib/IRGen/GenFunc.cpp:2390-2498,2530-2637,2640-2672,1950-2005,2319-2361`. | Audit 2302-2555 misses later layout/adoption code locally. The broad no-thunk adoption branch at 2573 is explicitly disabled; the active single-object route still builds a forwarder at 2601-2637. Do not promise universal thunk elision. |
| K14 | Capture descriptors omit the NecessaryBindings prefix from capture elements and separately encode metadata/shape/value sources. They do not preserve every substitution affecting box representation. `<swift checkout>/lib/IRGen/GenReflection.cpp:1368-1390,1437-1512`. | Additional compiler evidence absent from the two audit narratives. A type-only capture descriptor is not an offset/value-category oracle. |
| K15 | Reabstraction translates parameters contravariantly and plans inner/outer results independently, including indirect outputs and isolation. `<swift checkout>/lib/SILGen/SILGenPoly.cpp:5691-5775`; `<swift checkout>/lib/SIL/IR/SILFunctionType.cpp:2889-2937`. | Audit SILGenPoly 5499-5534/5752-5925 is not a reliable local function boundary. The explanatory rule is now 5693-5708. |
| K16 | Closure specialization creates a bare thin entry, retains nonclosure arguments, then appends unique root captures using their lowered types. Mangling records AST capture types and loses SIL address category. `<swift checkout>/SwiftCompilerSources/Sources/Optimizer/FunctionPasses/ClosureSpecialization.swift:514-543,605-624,687-705`; `<swift checkout>/lib/SILOptimizer/Utils/SpecializationMangler.cpp:244-268,299-301`. Repeated-root payload grammar is `<swift checkout>/lib/Demangling/Demangler.cpp:3555-3581`. | Audit closure-specialization 421-538 now covers root discovery/dependencies and declaration creation, not the whole capture appending rule. Local nested-specialization folding is explicit at 633-683. |
| K17 | Signature specialization indexes SIL arguments, including indirect results. Modified self can turn a method into Thin. Generic specialization independently converts results and arguments and drops eligible operands. `<swift checkout>/lib/SILOptimizer/Utils/SpecializationMangler.cpp:41-70,355-371`; `<swift checkout>/lib/SILOptimizer/FunctionSignatureTransforms/FunctionSignatureOpts.cpp:365-476`; `<swift checkout>/lib/SILOptimizer/Utils/Generics.cpp:826-930`; `<swift checkout>/lib/SIL/Utils/GenericSpecializationMangler.cpp:93-148`. | Method conversion is now 452-457, outside audit 361-431. Local and vendored parameter tags agree: closure 5, repeated root 11, escaping 12, ownership 128/512. Compare `<swift checkout>/include/swift/Demangling/Demangle.h:122-145` with `.build/checkouts/swift-demangling/Sources/Demangling/Enums/FunctionSigSpecializationParamKind.swift:1-21`. The source comment in SS 403-405 about numbering divergence is stale relative to this checkout. |
| K18 | A merged body keeps the first LLVM function type and appends parameters for differing constants. `<swift checkout>/lib/LLVMPasses/LLVMMergeFunctions.cpp:1086-1115`. | The older readiness citation to line 899 no longer reaches this rule. A demangled source specialization is not the merged LLVM signature. |
| K19 | Blocks pass the block object as first foreign argument and load invoke from its block field. C pointers have no implicit block object. `<swift checkout>/lib/IRGen/GenCall.cpp:1588-1608,6431-6455`. | The audit's early argument rule still applies; the invocation proof is additional local evidence. |
| K20 | Async-demotion code still has body/call-rewrite TODOs and a commented async-removed mangling call. `<swift checkout>/SwiftCompilerSources/Sources/Optimizer/FunctionPasses/AsyncDemotion.swift:271-316`. Generic closure bindings are K13. | No source support for enabling positive async-removal layout merely because a demangler node exists. |
| K21 | Differentiable products contain original/JVP/VJP or original/transpose. Distributed dispatch can bypass the thunk only under specific isolation conditions. `<swift checkout>/lib/IRGen/GenDiffFunc.cpp:402-413`; `<swift checkout>/lib/SILGen/SILGenDistributed.cpp:300-324`. | Autodiff lines match. Distributed decision starts at 300, not audit 296. |
| K22 | Key-path getter, setter, equals and hash expand different operands and packet pointer/size tails. The packet serializes generic requirements and/or index values. `<swift checkout>/lib/IRGen/GenCall.cpp:1929-1979,2140-2158,4836-4876`; `<swift checkout>/lib/IRGen/GenKeyPath.cpp:1317-1386`; `<swift checkout>/lib/SILGen/SILGenExpr.cpp:3894-3944`. | The getter helper is independently created from base/property/index conventions. Audit 2140-2163 is dispatch to dedicated expansion, not an extra ordinary polymorphic tail. Model packet pointer **and size**, not a generic closure x20. |
| K23 | General casts pass the exact source and target metadata to the runtime. `<swift checkout>/lib/IRGen/GenCast.cpp:82-100`. | Additional authority for the readiness cast-type lead. An unspecialized accessor base name alone cannot prove its instantiated target. |

## Every audit item at current HEAD

| Item | Current classification | swiftdc evidence and relevant tests | Compiler evidence and conclusion |
| --- | --- | --- | --- |
| G01 | Possibly wrong | R: D 7062-7212 admits bounded synchronous free-function metadata/table registers and explicitly excludes fulfillment/stack cases. VT 1312-1327 consumes those maps. PS 1445-1448 strips all trailing metadata-looking source arguments. Tests `DroppedArgumentsTests.swift:331-335` protects a leading metatype, not a final/only metatype. | K01/K02/K12. Bounded hidden placement is partial. I: final source metatype loss remains a soundness risk, independent of placement correctness. |
| G02 | Partially closed | R: D 7285-7356,7592-7597,7659-7782 uses one word for bare/dotted generic values and declines generic tuple-result placement. IR 26-49,286-334 bounds x8 admission but has no general result ledger. `IndirectResultOrderTests.swift:12-113` covers existing x8 ordering/escape cases. | K03/K04. Generic address vs reference meaning and multiple ordinary result destinations remain open. Pointer width alone is not a class-archetype ownership/value proof. |
| G03 | Partially closed | R: D 4627-4772 supports selected opaque/class/lookup/generic/class-context dispatch. Generic table paths require `protocolRequirement`, unlike the lookup/existential fallback to requirement kind. MS 442-523 names bounded witness metadata and declines ambiguous identities. `ProtocolWitnessCallTests.swift:15-44`, `ExistentialWitnessTests.swift:37-70` cover selected positives and mismatch negatives. | K05/K02. The readiness descriptorless generic-witness gap is still real, although some other descriptorless paths already render requirement ordinals. No reason to redo those. |
| G04 | Possibly wrong | R: MS 120-124 and PS 881-899 have required/enum names, arities and void sets. D 4814-4824 admits enum-extension offsets from metadata equality without enum-kind evidence. `ValueWitnessArgumentTests.swift:45-63` guards mismatched metadata, not a same-metadata non-enum decoy. | K06. Required-slot arity/void handling is bounded support. I: equality does not establish `HasEnumWitnesses` or even prove an arbitrary stripped table is a VWT. |
| G05 | Partially closed | R: D 4627-4667 supports a single local opaque protocol or class-bound protocol. FM 451-466 resolves constrained field spelling, not existential call layout. `ExistentialWitnessTests.swift:37-111` covers single-table dispatch and VWT metadata. | K07. Compositions, existential metatypes, box/payload identity and constrained openings still lack a shared proven layout. |
| G06 | Possibly wrong | R: SL 231-236/FM 385-390 decline possibly resilient register layouts. IR 306-329 does not generally reconstruct cross-image opaque returns. PS 320-328 truncates metadata types at the first `(` and cannot instantiate generic accessor arguments. `ResilientTypeTests.swift:11-93` protects layout caution. | K08/K23. Resilience caution is useful and incomplete. I: the separate generic-cast type spelling can still assert an incomplete/wrong target. |
| G07 | Partially closed | R: VI 127-143 requires no pack/value header, known flags, plain key types and sufficient key words. `GenericClassPackIndexTests.swift:13-94` expects packed decline/plain A. `GenericClassPackGuardIsolationTests.swift:75-115` isolates failed premises. `git log -S 'typePackHeader == nil'` identifies `e795299`. | K10/K01. The former false B label is guarded now. Positive class pack offsets, invocation packs and value parameters remain open. This is not an outstanding reproduced wrong-output item at HEAD. |
| G08 | Partially closed | R: PS 958-969 knows SDK accessor arity bands. MS 91-110 identifies descriptor accessors. VI 127-143 rejects resilient-superclass/nested layouts; FM has fixed offsets and explicit uncertainty. | K09. Request/response state, exact key-array contents and dynamic field-offset expressions are not modeled generally. |
| C01 | Partially closed | R: SL 64-76,135-160 recognizes whole arrow types as direct, but not exact storage representations. D 7659-7831 does not generally place thick function values. `ClosureCollectionCompilerOracleTests.swift:79-99,129-155` tests directness, not ordered function/context components. | K11/K04. Ordinary thick pairs as arguments/results remain a major completeness gap. Directness is not proof of two particular carriers. |
| C02 | Partially closed | R: VT 420-433 keeps x20 separate from source facts. ST 37-43 intentionally excludes closure/reabstraction context from nominal self; ST 74-109 handles conflicting vtable owners. CR 227-236 observes x22/x20 reads without establishing their roles. | K12/K13. This is correctly cautious. No neutral, typed closure-context origin is shared across all entry/call sites. |
| C03 | Partially closed | R: D 10848-10915 bounds local/closure calls by physical body reads and declines unproved mixed-bank source order. SI 245-260 explicitly distinguishes original local entries from merged closures and partial-apply forwarders. `ClosureCaptureTests.swift:9-15` explicitly expects `closure #1 (arg0, ?)`. | K13/K14/K18. No Core capture-descriptor consumer was found. Forwarded captures and merged-entry layouts remain open, not freshly solved. |
| C04 | Safely declined | R: arbitrary indirect targets and physical read summaries exist, but no dedicated block-object/invoke proof was found in the reviewed callable paths. CR 179-225/D 10853-10915 preserve machine extent without proving block formals. | K19/K11. Classification applies to representation-specific block recovery. Existing ObjC selector support is not block ABI support. |
| C05 | Safely declined | R: ST 37-43 excludes reabstraction nominal self; ordinary call-layout identifier checks in D 7746-7761 exclude thunk prose. Body-read recovery remains available without reconstructing adaptation semantics. | K15. No two-sided entry/forwarding/result contract found. This is a bounded decline, not a claim that every possible thunk heuristic elsewhere is sound. |
| C06 | Possibly wrong | R: SS 364-423 appends capture types and accepts one-GP captures as placed. TI 15-28,59-62 can then treat their AST spelling as a source integer. SS 394-395 ignores the earlier-root payload entirely. `DroppedArgumentsTests.swift:126-174,275-317` covers order, repeated positives and mixed-width declines. | K16. I: one GP word can be an address, not the captured scalar value. Missing repeated-root validation is a distinct parser soundness risk, not a claimed valid-compiler counterexample. Tag numbering was checked and matches locally. |
| C07 | Possibly wrong | R: SS 107-116 returns absent for unsupported transforms lacking `DroppedArgument`; SS 236-272 provides bounded drops/substitutions; D 7010-7043 separately guards some printed method/signature transformations. `DroppedArgumentsTests.swift:75-91,165-174` expects bounded declines; `SpecializationTests.swift:46-52` refuses folded symbols. | K17/K18. Bounded ordinary substitutions/drops already shipped. I: scattered consumers and unhandled/merged conventions still require a reproduction sweep before any original declaration ABI is trusted. Do not call all Dead cases wrong; many already decline. |
| C08 | Safely declined | R: SS 162-166,243-248 rejects transformed async lists; `DroppedArgumentsTests.swift:88-91,167-174` pins declined/absent grammar cases. Existing descriptor-backed method recognition is not a proof of restored generic closure bindings. | K13/K20. Keep async removal disabled without actual emitted evidence. Async generic closure binding is still unproved. |
| C09 | Possibly wrong | R: SL 138-155 discards attributes and may accept differentiable arrow shapes as ordinary direct values. No dedicated differentiable/distributed ABI oracle was located in the reviewed tests. | K11/K21. I: ordinary directness can suppress a needed indirect result for a multi-component differentiable product. Actual consumer/render reachability must be reproduced. Distributed source semantics remain unproved rather than known wrong. |
| C10 | Possibly wrong | R: SI 270-273 detects storage entities, but SI 276-302 `splitSignature` does not use that guard. D 7292-7317 and TI 18-28 consume printed signatures. No dedicated key-path entry schema exists in reviewed lowering. | K22. I: function-typed property/key-path names can supply unrelated parameter types. The readiness warning remains applicable despite the already-shipped getter throwing fix `60ce7c7`. |

## Sprint contract and ordering

Each numbered heading below is one candidate commit. It must prove only the stated behavior. Sizes mean S = a bounded guard/consumer change, M = a bounded dataflow/schema consumer, L = a difficult but still single-behavior integration. Do not bundle several headings merely because they share D or VT.

Every fixture defaults to **-Onone, -O, -Osize**. For optimization-created clones, -O/-Osize must retain the relevant entry and -Onone is a nonspecialized control. If optimization deletes the entry, use separate-module boundaries or compiler-verified executable SIL. Never count an absent symbol as a passing positive. Generic value parameters, relative tables, derivative and distributed features need explicit compiler/feature availability records.

Every sprint inherits these gates: same-toolchain SIL and LLVM declaration/call operands, independently decoded linked instructions and metadata, native sentinel observations when executable, named/stripped variants where applicable, filtered/array/streaming and both source renderers. Existing tests stay. Each listed mutation must compile and fail its intended assertion after rebuilding. Later run the enforcing suite, release blast radius and CLI paths required by CLAUDE.md. None of those gates ran in this review.

Dependency labels `B01/B02/B03`, `J02/J03`, `K01/K04`, and `A01/A02/A06` below refer to the **plan's** shared boundary, ordered placement, provider, lifetime, target/authentication and async tracks. They are not the compiler rule keys, which are written as `compiler Kxx`. A small sprint may add a narrow internal role fact rather than wait for a wholesale framework rewrite.

## Ordered sprints

### 1. G01-a: Keep a source metatype argument visible

- Axis: soundness. Compiler K01/K12. A source metatype is a formal even if hidden generics also contain metadata.
- Change site: PS `strippingGenericPlumbing` (1445), D rendered-call consumer (HEAD 11812), Pseudo/Structurer call assembly. Pass proven source/hidden roles instead of deleting by rendered prefix.
- Fixture sketch: `@inline(never) public func keep<T>(_ t: T.Type) -> T.Type { t }; public func use() -> Int.Type { keep(Int.self) }`. Add `keep2(_ n: Int, _ t: T.Type)` for trailing-only discrimination. True behavior returns the supplied type.
- Before/after: predicted `keep()` or `keep2(7)` becomes `keep(Int.self)`/`keep2(7, Int.self)` or equivalent full metadata spelling. Hidden type/table operands stay hidden.
- Negative controls: unknown source-role mapping preserves opaque arguments, not invented metatypes. Real hidden metadata remains nonformal.
- Mutations: remove role check, mark last formal hidden, move metadata before a real formal. Dependencies: none beyond a narrow source-role fact. Size M. Confidence high mechanism R, render reproduction I.

### 2. G06-a: Do not print a generic cast with a truncated target

- Axis: soundness. Compiler K23/K08.
- Change site: PS `swiftTypeName` (320-328), `swiftCastIdiom` (279-310), metadata value rendering in D.
- Fixture sketch: `final class Box<T> {}; public func cast(_ x: Any) -> Box<(Int, Int)>? { x as? Box<(Int, Int)> }`. Add `cast<T>(_ x: Any, _: T.Type) -> Box<T>?` with distinct instantiations. True behavior tests the complete instantiated target.
- Before/after: bare `Box`, `Box<`, or truncated parenthesized type becomes the exact proven type. If substitutions cannot be reconstructed, keep the raw runtime cast instead of asserting a target.
- Negative controls: unknown generic substitutions, local/private type prose, malformed nesting and metadata patterns without instance identity stay raw.
- Mutations: truncate on first `(`, discard accessor substitutions, select source metadata instead of target. Dependencies: none for decline; G08-a for richer positive instantiation. Size S. Confidence high helper defect R, emitted case I.

### 3. C10-a: Reject a storage property's function type as its entry signature

- Axis: soundness. Compiler K22/K11.
- Change site: SI `splitSignature`/`isStorageEntityName` (270-302), D `swiftArgumentRegisters` (7285), `swiftFloatArgumentInfo` (8113), TI `argumentTypes`.
- Fixture sketch: `public final class Holder { public var f: (Double) -> Int = { _ in 7 } }; public func get(_ h: Holder) -> (Double) -> Int { h.f }`. Also form `\Holder.f` and a function-valued subscript.
- Before/after: no getter/key-path entry may seed the property's Double as its own `arg0`. Use a proven accessor boundary or decline. The getter's function-valued result remains separate.
- Negative controls: an actual closure nested inside an accessor remains a function; ordinary subscript indices and setters keep their own conventions.
- Mutations: bypass storage guard independently in GP, FP and type consumers. Dependencies: none for guard. Size S. Confidence high code-path risk R/I.

### 4. C07-a: Make an unsupported specialization contract explicitly unavailable

- Axis: soundness. Compiler K17/K18.
- Change site: SS `parseClause`, `SpecializationClause`, D `followsASignature`/layout/result consumers and method receiver checks.
- Fixture sketch: `@inline(never) func use(_ a: Int, _ b: Int) -> Int { b &* 23 }` under a wrapper passing different constants. Add a generic method and emitted representation-changing/merged clones. Inspect each emitted modifier separately.
- Before/after: any affected original-signature seed or typed result becomes unknown/body-proven unless the complete transform is understood. Existing well-proved substitutions stay unchanged. An already-declined case produces no new output delta.
- Negative controls: ordinary names and ownership-only transformations retain proven layouts; unknown future modifiers never fall through to original declaration ABI.
- Mutations: map unsupported to absent, strip merged prefix, reuse original receiver contract. Dependencies: none. Size M. Confidence medium, suspected surviving consumers need reproduction.

### 5. C06-a: Separate a placed capture word from its source value category

- Axis: soundness. Compiler K16, especially SpecializationMangler.cpp 263-267.
- Change site: SS `SpecializedParameter`/`isPlacedCapture`, TI argument classification and VT entry/call value provenance.
- Fixture sketch: paired `run(_ n: Int, _ f: (Int) -> Int) -> Int` calls with an immutable Int capture and a mutated captured Int whose root partial apply is by address. Match emitted SIL operand categories before making any assertion.
- Before/after: the word may remain physically placed, but an address must not become an Int argument value or inherit integer signedness. A load from proved captured storage may recover the value later.
- Negative controls: identical printed capture types with different SIL categories, boxed mutation, unknown spills and joins remain untyped.
- Mutations: restore AST-type-as-value typing, equate address and scalar origins, discard category at a spill. Dependencies: narrow boundary provenance or B01. Size M. Confidence high erased-category mechanism R, numeric wrong render I.

### 6. G04-a: Require enum evidence for enum-only witness names

- Axis: soundness. Compiler K06, MetadataValues.h 181.
- Change site: D `valueWitnessCall.slotName` (HEAD 4814), metadata identity supplied by VI/MS.
- Fixture sketch: generic enum payload copy plus a source-owned pointer-table decoy called with the same pointer as its last operand. Add a synthetic same-metadata `Swift.Int` table extension. True behavior of the decoy is its own function, not enum injection.
- Before/after: an enum-extension-shaped decoy cannot acquire `getEnumTag`/inject/project semantics. Proven enum metadata retains existing labels. Unknown enum kind declines the enum-only name while preserving the indirect call.
- Negative controls: same metadata does not suffice, flags/offset padding are not function slots, unknown table provenance stays raw.
- Mutations: remove enum-kind/flag proof and metadata pairing separately. Dependencies: none for guard. Size S. Confidence high missing premise R, false-positive binary I.

### 7. C06-b: Validate repeated propagated-closure roots

- Axis: soundness. Compiler K16 and Demangler.cpp 3571-3581.
- Change site: SS `applying` (394-395).
- Fixture sketch: `twice(_ f: (Int) -> Int, _ g: (Int) -> Int, _ x: Int) -> Int { f(x) &+ g(x) }`, called with the same closure and with two distinct roots. Preserve actual emitted symbols, then mutate only the earlier-argument payload in synthetic trees.
- Before/after: valid repeated roots still append captures once; a missing, forward, nonclosure or unplaced root reference cannot authorize dropping another operand.
- Negative controls: invalid index, reference to ordinary formal, incomplete root payload and composed-clause index changes decline.
- Mutations: ignore reference payload, accept a later root, duplicate root captures. Dependencies: C06-a or a physical-only root ledger. Size S. Confidence high parser omission R; valid compiler emission of invalid references is not alleged.

### 8. C09-a: Decline ordinary function directness for differentiable products

- Axis: soundness. Compiler K11/K21.
- Change site: SL `isFunctionType`/`of`, indirect-result directness and result-bank consumers.
- Fixture sketch: with `_Differentiation`, an exported function returning `@differentiable(reverse) (Float) -> Float`, with a native invocation and gradient control. Record the actual product's native schema; do not assume every product is six words.
- Before/after: an unsupported differentiable product cannot inherit ordinary thick directness. Its result/arguments stay unknown or use proven output storage; no fabricated x0 result appears.
- Negative controls: ordinary thick/noescape closures keep direct classification; unfamiliar attributes do not silently erase product identity.
- Mutations: strip differentiability before representation, classify every arrow direct, omit guard in x8 eligibility. Dependencies: none for guard. Size S. Confidence medium, consumer reachability I.

### 9. C01-a: Place an ordinary thick function argument as a pair

- Axis: completeness. Compiler K11.
- Change site: SL callable representation, D `swiftCallArgumentLayout`/entry placement, VT component origins.
- Fixture sketch: `@inline(never) public func apply(_ f: (Int) -> Int, _ x: Int) -> Int { f(x) }`. Separate-module caller captures 11 and passes x=7; result 18.
- Before/after: `apply(?, ?)` becomes `apply(provenFunctionValue, 7)` and invocation uses the matching context. Following scalar identity is preserved. Anonymous code/context components may remain explicitly anonymous.
- Negative controls: thin/C/block values are not two words; mismatched pair joins, stack overflow and unresolved abstraction keep declining.
- Mutations: use one word, swap code/context, pair code from one predecessor with context from another. Dependencies: B01/B02 or a bounded two-word schema. Size M. Confidence high.

### 10. C01-b: Preserve a thick function result's code/context pairing

- Axis: completeness. Compiler K11/K04.
- Change site: VT result facts, D call-result rendering and result projection, separate from C01-a argument placement.
- Fixture sketch: `public func make(_ k: Int) -> (Int) -> Int { { $0 &+ k } }`; a noninlined caller invokes the result twice with different inputs.
- Before/after: unresolved result projection becomes one function value whose code and context come from the same call. It must not publish x0 alone as the complete closure.
- Negative controls: different producers, clobbered x1, thin results, indirect aggregate result and opaque reabstraction remain unpaired.
- Mutations: drop producer identity on context, retain stale x1, reconstruct from only code. Dependencies: C01-a and ordered result components B02. Size M. Confidence high.

### 11. C02-a: Seed a neutral closure-context role at a proved entry

- Axis: completeness. Compiler K12/K13.
- Change site: VT abstract entry origins (currently x20/self snapshots), ST boundary queries, D entry/call convention.
- Fixture sketch: an escaping closure capturing two distinct objects, invoked through an opaque `(Int) -> Int` parameter. True x20 at invocation is its context, not either captured object's nominal self.
- Before/after: raw unknown context loads become `context + offset` facts without invented lexical names or nominal fields.
- Negative controls: throwing thin placeholder, ordinary callee-saved x20, class receiver, async error and unrelated saved x20 remain distinct roles.
- Mutations: seed from mere x20 read, reuse receiver type, preserve through a partial overwrite. Dependencies: C01-a, B01. Size M. Confidence high.

### 12. C03-a: Type one concrete captured field from descriptor plus layout evidence

- Axis: completeness. Compiler K14/K13.
- Change site: add a bounded capture-descriptor reader alongside metadata indexes; D/VT context-field query, not FM nominal self reuse.
- Fixture sketch: `public func make(_ k: Int64) -> () -> Int64 { { k } }`, with reflection enabled and two distinct inputs. Independently bind allocation, descriptor, forwarder and actual load offset.
- Before/after: `return ?` becomes a typed neutral capture-field value when all layout premises agree. Do not invent lexical `k` if only its type survives.
- Negative controls: descriptor absent, opened archetype, generic substitution TODO, optimized field reordering, box/address capture and conflicting descriptors decline.
- Mutations: remove descriptor/allocation association, use source capture order as offset, include NecessaryBindings as a capture. Dependencies: C02-a, exact storage/lifetime evidence J02. Size M. Confidence medium.

### 13. C03-b: Forward one proven scalar capture through a partial-apply thunk

- Axis: completeness. Compiler K13.
- Change site: D forwarder transfer/call enrichment and VT context load facts; retain CR physical input evidence.
- Fixture sketch: `make(_ k: Int64) -> (Int64) -> Int64 { { $0 &+ k } }`. Preserve an -Onone forwarder, with optimized counterparts as separate shapes.
- Before/after: existing `closure #1 (arg0, ?)` becomes `closure #1 (arg0, captureField)` only when creation/store/load/forwarding agree.
- Negative controls: single-object adoption without box, thin-to-thick null context, changed context word, address capture and opaque joins retain unknown captures.
- Mutations: remove context pair association, permit intervening overlapping store, swap forwarded operand. Dependencies: C01-a, C02-a, C03-a. Size M. Confidence high scope, dataflow I.

### 14. C03-c: Preserve the physical input layout of a merged closure

- Axis: completeness. Compiler K18/K13.
- Change site: SI `isLocalFunctionName`, D summary-driven call mapping, CR exact-body facts.
- Fixture sketch: two closures with the same arithmetic shape and differing constants, forcing an optimizer merge at -O/-Osize; -Onone keeps separate closures.
- Before/after: retain all body-proven input words, including appended constants, without assigning the original closure's lexical capture layout. Unknown mixed-bank source order remains `?`.
- Negative controls: merged partial-apply forwarder is not an original local function; missing body and conflicting physical evidence stay opaque.
- Mutations: strip `merged` and reuse original layout, drop appended input, assume GP/FP source order. Dependencies: C07-a, C02-a; no dependence on full descriptor typing. Size M. Confidence medium, emitted merge must be confirmed.

### 15. G01-b: Emit canonical scalar generic requirements in one ordered plan

- Axis: completeness. Compiler K01.
- Change site: D `genericMetadataRegisters`, `genericWitnessTableRegisters`, `passesEveryGenericMetadata`; VT entry consumers.
- Fixture sketch: `protocol P { func n() -> Int }; public func f<T,U:P>(_ t: T, _ u: U, _ z: Float) -> Int { u.n() }`. Add same-type equalities and a marker protocol before P.
- Before/after: unresolved metadata/table roles become explicit canonical identities with the same plan at entry and call. Hidden roles must not add source arguments.
- Negative controls: unknown requirement kind, protocol requiring no table, multiple depth without support and ambiguous module identity decline affected placements.
- Mutations: include noncanonical parameter, count marker as table, interchange metadata/table requirement order. Dependencies: B01/B02. Size M. Confidence high.

### 16. G01-c: Fulfill a generic metadata requirement from a nominal parameter

- Axis: completeness. Compiler K01/K02.
- Change site: D all-metadata admission guard and new fulfillment-path facts.
- Fixture sketch: `final class Box<T> {}; public func f<T,U>(_ b: Box<T>, _ u: U) -> U { u }`. Add `Box<T>.Type` and a subclass control.
- Before/after: the omitted T metadata no longer blocks correct U metadata placement. Exact nominal generic argument paths become queryable without claiming exact dynamic class identity.
- Negative controls: bare inexact `T.Type`, ObjC type-erased generic class, unknown superclass path and source clobber decline.
- Mutations: treat all metadata inexactness as exact, retain fulfilled T in outgoing ledger, reuse a stale object-derived metadata source. Dependencies: G01-b, G08-a. Size M. Confidence high.

### 17. G01-d: Account for early metadata of an indirect nominal self

- Axis: completeness. Compiler K01, GenProto.cpp 420-430/4442-4446.
- Change site: D generic method boundary and metadata role placement, VT entry binding.
- Fixture sketch: `struct Holder<T> { var t: T; mutating func replace(_ x: T) { t = x } }`, called across a noninlined boundary. True self is an address and its extra nominal metadata precedes remaining unfulfilled requirements.
- Before/after: generic receiver metadata is no longer confused with a formal or ordinary trailing type parameter.
- Negative controls: indirect nonself formal does not automatically provide a metadata source; nested/unknown layouts remain unplaced.
- Mutations: omit early source, append it after witnesses, treat indirect self address as metadata itself. Dependencies: G01-b, receiver-role foundation B01. Size M. Confidence high.

### 18. G01-e: Place a scalar hidden generic role after GP exhaustion

- Axis: completeness. Compiler K01/K12.
- Change site: D register-only metadata guards, ordered stack placement and VT incoming stack facts.
- Fixture sketch: exported generic function with enough integer formals to exhaust x0-x7, one independent Float, and a conformance witness call. All sentinels differ.
- Before/after: the proven hidden metadata/table stack locations become available without shifting FP formals. Source formal arity is unchanged.
- Negative controls: unknown-sized preceding role, packed narrow stack interval, unsupported split and incomplete stack stores remain unknown.
- Mutations: force hidden role into x7, round every stack value to an unchecked word, spill independent FP bank when only GP is exhausted. Dependencies: G01-b and B02's byte-accurate stack rules. Size M. Confidence high rule, implementation I.

### 19. G02-a: Distinguish a class archetype reference from an opaque value address

- Axis: completeness. Compiler K03.
- Change site: D `isGenericValue`, formal role schema and VT generic argument identity.
- Fixture sketch: `public func identity<T: AnyObject>(_ x: T) -> T { x }` paired with unconstrained `identity<T>`. Pass distinct class instances and nonclass values.
- Before/after: class archetype entry/call/result can preserve the object reference; unconstrained archetype remains an address transported under its own convention.
- Negative controls: superclass/layout constraints not proven, associated archetypes and same-word pointer decoys must not acquire object semantics.
- Mutations: classify every generic as address, classify every pointer-width generic as class, omit class constraint identity. Dependencies: G01-b, B01. Size M. Confidence high.

### 20. G02-b: Name the output destination of one opaque generic result

- Axis: completeness. Compiler K04/K03.
- Change site: IR admission/result roles, D entry/call placement and VT destination writes.
- Fixture sketch: `public func copy<T>(_ x: T) -> T { x }`, separately called with a nontrivial value. True output is the exact destination supplied by the caller, not an unrelated x0.
- Before/after: preserve the generic result-buffer identity and initialized bytes without pretending the unknown layout is a direct value.
- Negative controls: buffer escapes, mismatched producing call, inactive typed-error destination and unknown writes decline reconstruction.
- Mutations: infer ownership from any x8 read, use first formal as destination, keep buffer facts after alias write. Dependencies: G01-b, B02 and J02 initialization. Size M. Confidence high.

### 21. G02-c: Place one formal indirect result beside a direct result

- Axis: completeness. Compiler K04.
- Change site: IR distinct result ledger, D `returnsGenericTupleFromX0` guard and formal placement.
- Fixture sketch: `public func split<T>(_ x: T, _ n: Int) -> (T, Int) { (x, n &+ 3) }`. Native checks distinguish T's destination from the direct Int.
- Before/after: all-or-none tuple-result decline becomes independent proven indirect and direct components. The first ordinary GP destination is never arg0.
- Negative controls: unproved T producer, missing direct component, overlapping destinations and unsupported tuple reabstraction decline whole-value assembly.
- Mutations: force x8 sret, seed destination as x, merge component producer identities. Dependencies: G02-b and B02 grouped results. Size M. Confidence high.

### 22. G02-d: Keep two indirect result destinations distinct

- Axis: completeness. Compiler K04, GenCall.cpp 707-709.
- Change site: same ledger as G02-c, adding only the multiple-indirect-result behavior.
- Fixture sketch: `public func pair<T,U>(_ t: T, _ u: U) -> (T,U) { (t,u) }` with two different nontrivial values and distinct output buffers.
- Before/after: two ordinary destination roles can be proven separately; no universal x8 assumption and no first-buffer-as-formal seed.
- Negative controls: swapped aliases, one missing component, partial initialization and unknown result count retain a partial/unknown result.
- Mutations: enable sret with two destinations, coalesce buffers, shift source formals by one instead of two. Dependencies: G02-c. Size M. Confidence high.

### 23. C07-b: Recover one scalar Dead-argument transformation

- Axis: completeness. Compiler K17.
- Change site: SS ordered SIL-operand transformations and D consumers.
- Fixture sketch: `@inline(never) func f(_ unused: Int, _ live: Int) -> Int { live &* 23 }`, kept internal so optimization emits a Dead clone. True live operand follows the transformed SIL ledger.
- Before/after: body-only opaque clone arguments become the known surviving scalar argument, with no source-position shift from a hidden result.
- Negative controls: tuple explosion, typed error, indirect result, SROA/box/inout/existential changes and unsupported methods stay declined.
- Mutations: ignore dropped index, count only AST formals, apply nested clauses in forward rather than reverse order. Dependencies: C07-a, B01; G02 result ledger before extending beyond direct scalars. Size M. Confidence high.

### 24. C07-c: Place retained self after a method becomes thin

- Axis: completeness. Compiler K17, FunctionSignatureOpts.cpp 452-457.
- Change site: SS representation facts, D `signatureSpecializationRewritesSelf` and receiver extraction, ST queries.
- Fixture sketch: value/class method whose self transformation forces a thin specialization while retaining a live self operand. Preserve emitted SIL; source alone cannot force every optimizer shape.
- Before/after: the transformed self is read from the proved ordinary operand, not stale x20. Existing broad decline can become a correctly placed value.
- Negative controls: removed self, unmodified method, throwing placeholder and closure context remain distinct.
- Mutations: retain method representation, reuse x20 based on original owner, remove self from formal ledger. Dependencies: C07-b, receiver-role B01. Size M. Confidence medium emission, high rule.

### 25. C07-d: Recover a merged specialization's body-proven appended operand

- Axis: completeness. Compiler K18.
- Change site: D specialization identity/layout query, CR exact input summaries, SS must not infer this from substitution text alone.
- Fixture sketch: two noninlined generic arithmetic wrappers with distinct constants and a Double input, producing a merged specialized body at -O/-Osize. Preserve original wrappers as independent callers.
- Before/after: body-proven original FP input and appended constant remain present with physical provenance. Do not claim source-order formals when merging erased that mapping.
- Negative controls: missing first-body signature, different incoming representations and mixed-bank ambiguity remain opaque.
- Mutations: use the first demangled declaration as the whole merged signature, drop FP input, omit appended constant. Dependencies: C07-a, C03-c, ordered physical pieces B02. Size M. Confidence medium.

### 26. C05-a: Prove both boundaries of one synchronous reabstraction thunk

- Axis: completeness. Compiler K15/K04.
- Change site: D callable/thunk boundary facts and VT parameter/result translation; no wholesale thunk elision.
- Fixture sketch: `public func use<T>(_ f: (T) -> T, _ x: T) -> T { f(x) }`, called with an Int function under a retained generic boundary. True outer T can be indirect while inner Int is direct.
- Before/after: unknown thunk arguments/results become a proven address load/store adaptation between two independent contracts.
- Negative controls: isolation conversion, async adaptation, typed errors, ownership-sensitive and unknown-result thunks remain uncollapsed.
- Mutations: reuse inner contract at entry, reuse outer contract at call, omit result writeback. Dependencies: C01-a/b, G02-b, J02. Size M. Confidence high rule, medium fixture shape.

### 27. C04-a: Recover one C function-pointer formal without a context word

- Axis: completeness. Compiler K11/K19.
- Change site: callable value representation, foreign argument schema and D indirect call layout.
- Fixture sketch: `public func apply(_ f: @convention(c) (Int32) -> Int32, _ x: Int32) -> Int32 { f(x) }`. Use a source-owned C callback and a following integer sentinel.
- Before/after: one pointer formal and its C invocation are proven; no Swift context consumes the following formal.
- Negative controls: block object, thick closure, unknown foreign prototype and unauthenticated arm64e target remain unsupported.
- Mutations: use thick width, pass a context, interpret callback as Swift native entry. Dependencies: foreign schema/B01/B02 and applicable target contract. Size M. Confidence high.

### 28. C04-b: Recover a block invoke's implicit object argument

- Axis: completeness. Compiler K19.
- Change site: D indirect target proof, VT block object/invoke identity, foreign source-formal rendering.
- Fixture sketch: `public func call(_ b: @convention(block) (Int32) -> Int32, _ x: Int32) -> Int32 { b(x) }`, exercised with copied escaping and global blocks. True invoke receives block object before x.
- Before/after: raw register list becomes a block invocation with x as source formal, retaining implicit object in machine facts.
- Negative controls: arbitrary pointer-table offset, wrong object at call, C pointer, overwritten invoke and auth mismatch decline.
- Mutations: remove object pairing, use wrong invoke field, drop/duplicate hidden first operand. Dependencies: C04-a, provider/auth foundations, block lifetime evidence. Size M. Confidence high rule, medium integration.

### 29. G08-a: Decode a descriptor-backed metadata accessor's key operands

- Axis: completeness. Compiler K09/K10.
- Change site: MS accessor identity, D metadata call schema, PS SDK-only arity fallback.
- Fixture sketch: generic nominal accessors with 0, 3 and 4 total key arguments, including a conformance table. True four-key case receives a pointer to the complete key array, not its first three elements directly.
- Before/after: unknown/stale accessor operands become exact request/key roles. This establishes identity and transport, not initialized layout state.
- Negative controls: same-spelled local function, incomplete descriptor, array-order mismatch and unavailable key counts remain unproven.
- Mutations: switch boundary from >3 to >=3, omit a key table from count, bind by spelling alone. Dependencies: B03 and descriptor identity. Size M. Confidence high.

### 30. G08-b: Track metadata response state separately from its pointer

- Axis: completeness. Compiler K09, Metadata.h 102-112.
- Change site: VT multi-result facts and D metadata state-sensitive consumers.
- Fixture sketch: a generic type metadata request retained in compiler-verified SIL/IR with a nonblocking request and state test; ordinary blocking accessor calls are controls. True layout access requires a sufficient response state.
- Before/after: x0 metadata identity and x1 state no longer become one undifferentiated result. State-dependent facts become available only on proved sufficient-state edges.
- Negative controls: unknown request bits, state lost at join, insufficient response and ordinary two-register result remain unqualified.
- Mutations: assume every accessor complete, reuse request as response state, merge opposite state branches. Dependencies: G08-a, B02 outcome components. Size M. Confidence high rule; source-only way to force nonblocking form may require SIL.

### 31. G03-a: Name a generic witness slot without a method-name descriptor

- Axis: completeness. Compiler K05/K01.
- Change site: D `genericWitnessCall` (HEAD 4760), VI class witness path where applicable; reuse existing `protocolRequirementShape` fallback rather than copying it.
- Fixture sketch: `protocol P { func a() -> Int; func b() -> Int }; public func call<T:P>(_ x:T) -> Int { x.b() }`, with no library evolution and stripped variants.
- Before/after: unresolved call becomes `P requirement 1 (method) witness for T(...)`, not an invented source method name. Argument ABI remains separately unknown if its requirement signature is absent.
- Negative controls: base-conformance/associated-type/data slots, wrong table format, non-Self pairing and same protocol spelling in another module decline.
- Mutations: pick first requirement, ignore kind, allow unknown preceding table eligibility. Dependencies: G01-b; B01/B02 for any positive argument mapping. Size S. Confidence high.

### 32. G03-b: Follow one inherited protocol witness-table path

- Axis: completeness. Compiler K02/K05.
- Change site: descriptor/slot index and D `protocolWitnessCall`, preserving dispatch identity rather than asserting one implementation.
- Fixture sketch: `protocol Q { func q() -> Int }; protocol P: Q {}; public func f<T:P>(_ x:T)->Int { x.q() }`. Distinct requirements prevent accidental slot agreement.
- Before/after: a proved inherited table load names Q's requirement instead of staying unresolved.
- Negative controls: associated conformance is not base table, imported descriptor without provider proof and offset-unit ambiguity stay raw.
- Mutations: treat base-table slot as method, skip inherited descriptor, resolve using source-name order. Dependencies: G03-a, G01-b. Size M. Confidence high.

### 33. G03-c: Follow one conditional conformance table identity

- Axis: completeness. Compiler K02, Fulfillment.cpp 264-293, and K05.
- Change site: conformance descriptor index, D table provenance and metadata substitution identity.
- Fixture sketch: `struct Wrap<T> { var x:T }; extension Wrap:P where T:Q { func p()->Int { x.q() } }`, with two different Q conformers.
- Before/after: a requirement reached from a proven instantiated conditional table can be named, without treating the table pattern as its exact final code body.
- Negative controls: unsatisfied/wrong condition, pack conditional requirement, unknown provider and generic instantiation not proven stay declined.
- Mutations: omit condition identity, use pattern as runtime table, conflate T conformers. Dependencies: G03-b, G08-a/b. Size M. Confidence medium.

### 34. G04-b: Preserve initialized-copy witness destination identity

- Axis: completeness. Compiler K06, ValueWitness.def 125-133.
- Change site: shared value-witness operation schema, VT byte initialization and result alias, D witness call facts.
- Fixture sketch: `public func duplicate<T>(_ x:T)->T { x }` using a nontrivial source-owned value. True `initializeWithCopy` initializes destination from source and returns that destination pointer.
- Before/after: a known copy's result can alias the proven destination and record initialization. This does not claim take/destroy/assignment semantics or suppress side effects.
- Negative controls: unknown metadata/size, reversed or overlapping operands, escaped destination and uninitialized source remain unknown.
- Mutations: return source pointer, swap destination/source, assume initialization after an unproved witness. Dependencies: G02-b, G08-b, J02. Size M. Confidence high.

### 35. G04-c: Invalidate source initialization after a proved take witness

- Axis: soundness. Compiler K06, ValueWitness.def initializeWithTake/assignWithTake signatures.
- Change site: same operation schema as G04-b and VT byte lifetime state. This is ordered here because positive byte-state use is its dependency, not because a current stale-source render was measured.
- Fixture sketch: compiler-preserved move-only/nontrivial generic transfer with a take witness, plus a copy control. Verify source invalidation in SIL and a source-owned lifetime log.
- Before/after: once positive storage reuse exists, a moved source cannot remain a valid value. The destination can remain initialized where proven.
- Negative controls: copy leaves source live; unknown size/effects do not produce selective byte-state claims.
- Mutations: treat take as copy, fail to invalidate an alias, conflate assign with initialize. Dependencies: G04-b, J02/J03. Size M. Confidence high rule, future guard rather than observed present bug.

### 36. G05-a: Select the correct table in a two-protocol existential

- Axis: completeness. Compiler K07/K05.
- Change site: D single-protocol existential descriptor/entry assumptions, typed container identity and ordered tables.
- Fixture sketch: `protocol P { func p()->Int }; protocol Q { func q()->Int }; public func f(_ x:any P & Q)->Int { x.p() &+ x.q() }`, implemented with distinct sentinel returns.
- Before/after: the two requirement calls acquire their correct protocol identities while payload/container remain distinct.
- Negative controls: class-bound mixture, ObjC/marker no-table constraint, reversed tables and lost metadata at join decline.
- Mutations: pick first table, use source textual protocol order, include an ObjC constraint as a table. Dependencies: G03-a, G01-b. Size M. Confidence high.

### 37. G05-b: Preserve out-of-line existential payload identity

- Axis: completeness. Compiler K07, GenExistential.cpp 1985-2022.
- Change site: VT existential projection and box address facts, D opening/call operands.
- Fixture sketch: `any P` values using a small inline payload and a large nontrivial payload whose method reads a distinct stored Int. True container, box and payload are different addresses where the ABI requires them.
- Before/after: the proven projection supplies the payload address to a witness/generic call rather than the box header or whole container.
- Negative controls: unknown inline/box flag, Error box, cast-induced new opening and possible writer invalidate the projection.
- Mutations: return container as payload, omit box load, retain opening across destructive replacement. Dependencies: G05-a, G08-b, J02. Size M. Confidence high.

### 38. G05-c: Place an existential metatype's metadata and tables

- Axis: completeness. Compiler K07, GenExistential.cpp 1866-1899.
- Change site: SL metatype representation, D argument/result layout and VT existential opening identity.
- Fixture sketch: `public func f(_ t:any P.Type)->Int { t.staticRequirement() }`, with a concrete-class metatype and `Any.Type` controls. Use actual supported syntax and emitted SIL.
- Before/after: the metadata/table product is preserved and never reduced to an ordinary class metatype or thick closure pair.
- Negative controls: bare `T.Type`, concrete nominal metatype, unknown composition and wrong conformance pairing retain distinct layouts.
- Mutations: force one word, classify all `.Type` alike, strip the table independently of metadata. Dependencies: G01-a, G05-a, B02. Size M. Confidence high rule, medium fixture emission.

### 39. G06-b: Place a scalar following a proved resilient indirect formal

- Axis: completeness. Compiler K08/K03.
- Change site: SL/FM storage-vs-transport evidence, D partial formal placement.
- Fixture sketch: separately built library-evolution provider exports `struct Payload` and `use(_ p: Payload, _ n:Int)->Int { n &* 5 }`. Rebuild provider with changed private Payload fields, keeping the client fixed.
- Before/after: current following-scalar decline becomes the proved n location after one indirect pointer. Payload's inaccessible fields remain unknown.
- Negative controls: exported `@frozen` not independently proven, opaque unknown module, nested aggregate and changed transport convention do not inherit this rule.
- Mutations: use visible storage field count as transport, drop indirect pointer, infer frozen from symbol export. Dependencies: B01/B02 and exact provider identity. Size M. Confidence high.

### 40. G06-c: Preserve a generic opaque factory's result destination

- Axis: completeness. Compiler K08/K04.
- Change site: opaque descriptor/substitution identity, IR result roles and D consumer projection.
- Fixture sketch: provider `public func make<T>(_ t:T)->some P { PrivateBox(t) }`, private underlying type changed between compatible provider builds. A client calls only P's declared operation.
- Before/after: recover the opaque output destination and P conformance identity, not the private concrete layout or an imagined direct result.
- Negative controls: opaque descriptor/discriminator mismatch, dynamic replacement, unavailable substitutions and changed private size preserve unknown concrete storage.
- Mutations: substitute known underlying nominal transport, ignore opaque discriminator, attach result to wrong factory call. Dependencies: G02-b, G08-a/b, G03-c. Size M. Confidence medium.

### 41. G08-c: Name one field selected by a dynamic field-offset vector

- Axis: completeness. Compiler K09, GenMeta.cpp 3288-3406.
- Change site: FM dynamic offset expressions, VT address algebra and D field read rendering.
- Fixture sketch: generic struct with a T field followed by Int, instantiated with differently sized T. True Int byte offset changes; field ordinal remains fixed.
- Before/after: a proven metadata-vector offset can yield `arg.field` instead of `mem[base + ?]`, without converting it into a fixed offset valid for all instantiations.
- Negative controls: wrong metadata state/descriptor, field ordinal out of range, arbitrary offset global and unknown arithmetic remain raw.
- Mutations: cache first instantiated byte offset globally, change vector ordinal, detach metadata identity. Dependencies: G08-b, J02 and typed address expressions. Size M. Confidence high.

### 42. G07-a: Recover a scalar class metadata argument after pack lengths

- Axis: completeness. Compiler K10/K09.
- Change site: VI `genericArguments` representation and `genericParameter`; keep the published scalar guard for unsupported layouts.
- Fixture sketch: existing `class PackBox<A, each T>` versus `PlainBox<A,B>` identityA reduction, plus empty/one/many heterogeneous packs. True scalar A follows encoded shape words.
- Before/after: packed `identityA` can name A's witness instead of unresolved, never B's. Ordinary PlainBox remains unchanged.
- Negative controls: unknown header flags, value descriptors, nested/resilient superclass bounds, invalid shape index and unknown kinds still decline.
- Mutations: omit shape prefix, count each pack element as a scalar key slot, bypass each existing header/kind guard independently. Dependencies: G08-a and a typed descriptor-key role decoder. Size M. Confidence high.

### 43. G07-b: Keep an invocation's pack shape separate from metadata-pack identity

- Axis: completeness. Compiler K01/K10.
- Change site: D generic requirement plan and VT shape/metadata-array roles.
- Fixture sketch: `public func forward<each T>(_ values: repeat each T) { consume(repeat each values) }`, with empty, one and heterogeneous packs. True shape length is a scalar count; metadata pack is a pointer to metadata entries.
- Before/after: expose distinct shape/metadata-pack physical facts and preserve later scalar roles without inventing element types for unknown extents.
- Negative controls: same-shape vs independent shapes, Swift Array variadics, C variadics and tagged pack/scalar ambiguity remain distinct.
- Mutations: seed shape as type metadata, duplicate same-shape count, read pack pointer as element zero. Dependencies: G01-b/e, descriptor role decoder. Size M. Confidence high.

### 44. G07-c: Resolve a witness-pack element using the matching shape and index

- Axis: completeness. Compiler K10, GenPack.cpp 598-638.
- Change site: D witness resolution and VT dynamic array projection, no scalar-table fallback.
- Fixture sketch: `func visit<each T: P>(_ x: repeat each T) { repeat consume((each x).p()) }`, with distinguishable conformers and empty-pack control.
- Before/after: a bounded/proved element table names the right requirement. Unknown index/extent stays unresolved, not an arbitrary first conformance.
- Negative controls: differing shape, out-of-range index, table-pack/metadata-pack swap and unknown element conformance decline.
- Mutations: ignore index, pair another shape, treat pack pointer as scalar witness table. Dependencies: G07-b, G03-a, B02. Size M. Confidence medium.

### 45. G07-d: Preserve value-pack element addresses as an address array

- Axis: completeness. Compiler K10, GenPack.cpp 1144-1158.
- Change site: VT pack payload projection and D formal/result address roles.
- Fixture sketch: generic `identity<each T>(_ x: repeat each T) -> (repeat each T)` across a preserved boundary, with multiple nontrivial elements. True pack entries are element addresses in the supported indirect convention.
- Before/after: a proven element destination/source remains its own address, not a contiguous inline T byte region or metadata pointer.
- Negative controls: unknown element index, mismatched shape, unsupported direct packs and incomplete result destinations decline.
- Mutations: scale index by element size instead of pointer size, load element value where an address is required, conflate payload and metadata arrays. Dependencies: G07-b, G02-d, J02. Size M. Confidence high rule.

### 46. G07-e: Gate one generic value-parameter role by descriptor version

- Axis: completeness. Compiler K01/K10, MetadataValues.h 2254-2264.
- Change site: generic requirement/descriptor kind decode and D placement; no fallback to type metadata.
- Fixture sketch: a source generic value parameter if the selected compiler exposes its feature flag; otherwise compiler-verified SIL/descriptor fixture and an explicit unavailable-source record. True value bits are a value role, never a metadata pointer.
- Before/after: the selected supported scalar role is placed or explicitly unavailable. Do not manufacture a positive from public source enum presence.
- Negative controls: feature unavailable, unknown descriptor version/kind, invalid value type and pack layout stay declined.
- Mutations: treat Value as Type, use descriptor key-array order for invocation order, ignore feature gate. Dependencies: G01-b, G07-b, B02. Size S/M. Confidence high rule, low positive toolchain availability until measured.

### 47. C08-a: Restore one synchronous generic closure binding from its context

- Axis: completeness. Compiler K13/K01.
- Change site: capture/context binding index, D polymorphic forwarding and VT metadata/table origins.
- Fixture sketch: `public func make<T:P>(_ t:T)->()->Int { { t.p() } }`, preserved across module boundaries. True context may carry necessary bindings separately from payload capture fields.
- Before/after: a proved restored T metadata/table binding can name the witness call; no fixed offset is assigned merely from capture source order.
- Negative controls: absent binding, metadata/table swap, local archetype descriptor omission, dynamic function context and stale capture generation decline.
- Mutations: include binding prefix as payload, omit conformance identity, restore from wrong context pair. Dependencies: C03-a/b, G01-b, G03-a, G08-b. Size M. Confidence high rule, medium shape.

### 48. C08-b: Associate a generic async forwarder's descriptor with its binding context

- Axis: completeness. Compiler K13/K20.
- Change site: async descriptor/callable identity index and D binding facts. Do not extend carried-value transport in this commit.
- Fixture sketch: generic async closure capturing T:P, with `await Task.yield()` and a post-resume witness operation. Native sentinels check captured identity, not a fabricated scalar transport proof.
- Before/after: descriptor code/context-size identity and the independently restored generic bindings can be associated. Unproved async source operands/results remain `?`.
- Negative controls: code pointer mistaken for descriptor, size record mismatch, resume mistaken for entry, unsupported isolation and unknown incoming owner decline.
- Mutations: pair descriptor with another context, skip code/data check, seed entry generics at a resume. Dependencies: C08-a, async A01/A02/A06 and target/auth support. Size M. Confidence medium. Async-removal stays unsupported under compiler K20.

### 49. C10-b: Give a key-path getter its own boundary

- Axis: completeness. Compiler K22.
- Change site: D entry/call schema keyed by typed key-path getter kind, IR result roles and VT base/packet roles.
- Fixture sketch: `struct Root { var n:Int }; public func read(_ r:Root)->Int { r[keyPath: \Root.n] }`, plus a computed subscript key path with a captured index. True getter base/output roles come from accessor lowering, not the property type's arrow.
- Before/after: raw/unseeded accessor gets independently proved base and result destination/components. Serialized packet pointer and size remain hidden roles.
- Negative controls: ordinary getter, function-valued property, setter/equals/hash and record without proven accessor identity decline.
- Mutations: seed from property type, swap base/output, remove packet size. Dependencies: C10-a, G02-b/c, B02. Size M. Confidence high.

### 50. C10-c: Give a key-path setter its own value/base boundary

- Axis: completeness. Compiler K22, GenCall.cpp 1941-1947.
- Change site: dedicated setter schema beside C10-b and VT address roles.
- Fixture sketch: `public func write(_ r:inout Root,_ n:Int) { r[keyPath:\Root.n] = n }`, plus indexed computed property. True new-value and base positions are independently checked in SIL/IR.
- Before/after: correct value/base/packet roles replace a body-only list, without reusing getter order or treating indices as ordinary formals.
- Negative controls: read-only key path, unknown accessor representation, address-only new value and invalid packet extent stay unplaced.
- Mutations: reuse getter schema, swap new value/base, treat packet as swiftself. Dependencies: C10-b, J02. Size M. Confidence high.

### 51. C10-d: Give key-path index equality its two-packet boundary

- Axis: completeness. Compiler K22, GenCall.cpp 1948-1955.
- Change site: typed equals entry, D/VT operand/result layout.
- Fixture sketch: two key paths to a Hashable-indexed computed subscript, equal and unequal indices. Preserve the generated equals callback at all claimed optimization levels.
- Before/after: lhs packet, rhs packet and size become distinct physical roles with a proven Bool result.
- Negative controls: same pointer is not proof of contents/size, hash callback is not equals, unknown index type remains opaque.
- Mutations: drop rhs packet, swap size with address, choose getter schema. Dependencies: C10-b, B02. Size S/M. Confidence high rule, medium retention of callback.

### 52. C10-e: Give key-path index hash its packet/size boundary

- Axis: completeness. Compiler K22, GenCall.cpp 1956-1961.
- Change site: dedicated hash entry and D/VT scalar result roles.
- Fixture sketch: indexed key paths inserted into a Set using two distinct Hashable index values. The exact hash number is not an oracle; callback argument identity and lawful equality/hash behavior are.
- Before/after: packet and size are correctly placed without a fictitious base or closure context.
- Negative controls: equals/getter/setter, unknown serialized type and missing size retain decline.
- Mutations: use equals operand count, read x20 as context, publish stale result for an unproved callback. Dependencies: C10-b. Size S/M. Confidence high.

### 53. C10-f: Resolve one serialized generic key-path binding

- Axis: completeness. Compiler K22/K01, GenKeyPath.cpp 1331-1383.
- Change site: key-path record/packet identity and generic binding buffer decoder; D table/type consumers.
- Fixture sketch: `struct Box<T> { var value:T }; func path<T>(_:T.Type)->WritableKeyPath<Box<T>,T> { \Box<T>.value }`, plus a generic Hashable subscript index.
- Before/after: a descriptor-backed generic metadata/table binding can be restored from the exact packet. No ordinary trailing witness or closure-context assumption is used.
- Negative controls: unknown packet size, mismatched originating pattern, malformed requirements and arbitrary buffer reuse decline.
- Mutations: decode as capture context, ignore requirement order, use size from another packet. Dependencies: C10-b/e, G01-b, G08-a/b. Size M. Confidence medium.

### 54. C09-b: Preserve differentiable original/JVP/VJP component identity

- Axis: completeness. Compiler K21/K11.
- Change site: SL differentiable product schema and VT component projection. This sprint identifies components only; it does not recover derivative invocation ABI.
- Fixture sketch: a reverse-differentiable function value stored and forwarded across a noninlined boundary. Independently inspect original/JVP/VJP components and invoke only the original through a supported projection.
- Before/after: unknown product can expose a proven original function component while the derivative components remain explicit identities/unknown invocation contracts.
- Negative controls: linear original/transpose product, missing derivative, foreign representation and mismatched projection remain unqualified.
- Mutations: swap original/VJP, assume product is ordinary thick, combine contexts from different products. Dependencies: C09-a, C01-a/b, B02. Size M. Confidence high rule, medium feature oracle. Follow with separate JVP, VJP and linear-product invocation sprints only after emitted contracts are retained and measured; they are not claimed covered here.

### 55. C09-c: Distinguish a distributed local implementation from its thunk

- Axis: completeness. Compiler K21, SILGenDistributed.cpp 300-324.
- Change site: callable entry kind and D target/receiver facts; retain descriptor/accessor records as data.
- Fixture sketch: a source-owned `distributed actor` using a minimal test actor system, with an isolated same-actor caller and an external caller. Give the local implementation a distinct observable body effect.
- Before/after: actual code targets are named as local implementation versus distributed thunk where evidence proves them. Do not collapse the external thunk into the local method or claim network behavior.
- Negative controls: unknown isolation, method accessor/record, remote actor identity, dynamic replacement and unresolved actor-system callback keep their own unknown semantics.
- Mutations: bypass thunk for every call, infer local isolation from name, treat accessor data as method code. Dependencies: B01/B03, async/actor entry contracts and target authentication. Size M. Confidence high rule, medium fixture infrastructure.

## Remaining narrowly gated follow-ons

The 55 sprints above avoid pretending that a whole ABI domain fits one commit. These remaining extensions are explicit, not hidden inside a larger sprint:

- **G03-d**, relative witness slot decoding: completeness, M, medium confidence. Compiler K05. Change descriptor format and slot-address decoder only. Fixture is G03-a built with a demonstrated relative-table flag, ordinary absolute table as control. Before unresolved relative slot; after correct requirement identity, still no exact body effect. Mutate relative/absolute discriminator and displacement origin independently. Depends on G03-a and auth/target work. If the installed compiler cannot emit it, record unavailable and retain decline.
- **G05-d**, one constrained existential opening: completeness, M, medium confidence. Compiler K07/K01. Extend G05-a's container identity for `protocol Bag<Element> { associatedtype Element; func first()->Element }; func f(_ b:any Bag<Int>)->Int { b.first() }`. Before unknown associated result; after Int only when shape requirements and opening agree. Unknown shape/substitution and wrong table remain declined. Mutate opening generation, same-type requirement and protocol descriptor separately. Depends on G05-a/b, G01-b, G02 result roles.
- **G08-d**, one resilient-superclass generic argument offset: completeness, M, medium confidence. Compiler K09. Change VI dynamic bounds query only. Independently build an evolving base class and generic subclass; rebuild base with larger private layout. Before generic metadata declined; after correct descriptor-relative argument identity. Unknown runtime bounds and absent provider stay declined. Mutate bounds/word units/descriptor association. Depends on G08-b/c and provider proof.
- **C05-b**, synchronous-to-async adaptation entry: completeness, M, medium confidence. Compiler K15/K20. Extend the two-sided thunk contract for `let f: (Int) async -> Int = synchronousFunction` retained by compiler SIL. Before unknown adapter roles; after only entry/forwarded operand identity, not general suspension preservation. Isolation-erased and unknown-resume controls remain declined. Mutate entry/resume kind and inner argument mapping. Depends on C05-a and async entry schemas.
- **C09-d**, one JVP invocation: completeness, M, medium confidence. Compiler K21 plus actual derivative SIL function type. Extend a single component invocation consumer, using `valueWithDifferential` on a source-owned Float function whose derivative is known. Before derivative invocation unknown; after only that measured component/result tuple. VJP/transpose/product-wide assumptions remain declined. Mutate derivative kind, primal/tangent positions and pullback/context pairing. Depends on C09-b, C01 pair/results and ordered tuples.
- **C09-e**, one VJP/pullback invocation: completeness, M, medium confidence. Same source discipline as C09-d, using `valueWithPullback`. Before unknown pullback; after correctly paired primal and pullback plus one measured tangent return. JVP/linear transpose remain unsupported. Mutate pullback producer/context, result grouping and cotangent order independently. Depends on C09-b and two-sided callable/result schemas.
- **C09-f**, linear original/transpose product identity: completeness, M, low-to-medium confidence. Compiler K21, GenDiffFunc.cpp 410-413. Use compiler-verified linear SIL if no source spelling is supported. Before unsupported product; after separately identified original and transpose components only. Ordinary reverse differentiable products and unavailable feature modes remain declined. Mutate product kind and component index. Depends on C09-b. A later transpose invocation requires its own retained emitted contract.

These follow-ons are individually landable behavior slices with bounded acceptance targets. None licenses claiming the rest of its parent audit item closed. The roadmap also deliberately leaves unproved ownership-only result effects, arbitrary SROA/box/existential transformations, unknown capture substitutions and unavailable runtime layouts as declines. Add another measured slice rather than enlarge one of the listed commits.

## What may currently render wrong and should jump the queue

No fresh binary render was produced in this review. The following are current-source risks, with different strengths of evidence.

1. **A final/only source metatype can disappear.** R: PS 1445-1448 deletes every trailing metadata-looking argument without the callee's formal roles; D HEAD 11812 uses it in nested call rendering, and both source renderers call the same policy. Compiler K01/K12 permits metadata-valued source formals. I: a live call `sink(Box<Int>.self)` can become `sink()`. The existing leading-metatype test does not disprove this. G01-a first.
2. **A generic cast target can be incomplete or wrong.** R: PS 326 truncates on the first parenthesis, even one inside a generic argument; accessor base names do not include instantiated type arguments. Compiler K23 passes exact target metadata. I: a cast can assert `Box` or `Box<` instead of `Box<(Int, Int)>`, or erase T in `Box<T>`. Use raw cast when exact target identity is unavailable. G06-a.
3. **A property function type can be mistaken for the getter/key-path entry's parameters.** R: SI 270 recognizes storage, but its signature parser does not gate on that; entry and type consumers use that parser. Compiler K22 creates dedicated accessor signatures. I: an unrelated entry register can become the property's function argument. The getter throw correction is separate and does not close this. C10-a.
4. **A propagated integer capture can acquire value semantics despite being an address.** R: SS proves only bank-compatible physical placement for one-GP capture types, while TI can assign scalar type from the rebuilt signature. Compiler K16 mangles only AST type and discards address category. I: downstream comparisons/arguments can misinterpret the address as the Int rather than load its value. Need paired emitted address/value reductions. C06-a.
5. **Enum-only witness semantics can be attached to a non-enum/decoy table.** R: D HEAD 4814-4824 checks offset and last metadata equality, not enum witnesses or proof that arbitrary stripped input is metadata. Compiler K06 requires the enum extension. I: source-owned decoy functions can get enum operation names, arity or void behavior. Existing mismatch tests do not isolate this premise. G04-a.
6. **Unhandled/merged specialization ABI may reach an original-signature consumer.** R: SS distinguishes only some unsupported transforms from absent, and D has several separate printed-name guards. Compiler K17/K18 allows representation changes and appended LLVM operands. I: a surviving consumer could shift parameters/self/result type. I did not establish a current emitted wrong-output counterexample. Many Dead, tuple, async and typed-error shapes already decline. C07-a is a reproduction/guard sprint, not permission to rewrite all specialization logic.
7. **Differentiable products may inherit ordinary function directness.** R: SL erases attributes before recognizing arrows; compiler K11 dispatches differentiability before normal representation. I: an actual product exceeding supported direct carriers could lose result-buffer eligibility. No dedicated oracle was found, so this is lower-confidence than the preceding source-render defects. C09-a.
8. **Invalid repeated-root payload can authorize a dropped closure operand.** R: SS 394-395 ignores the payload required by compiler demangling grammar. This is an unsupported/malformed-symbol soundness issue, not evidence that a valid compiler emits invalid root references. C06-b.

**Do not re-queue the old PackBox A-as-B defect as an open wrong render.** VI's scalar-admission guard and paired tests are present at HEAD, shipped by `e795299`. H: the plan/readiness record reports the successful qualification. Positive packed metadata recovery remains a completeness sprint (G07-a).

No evidence here upgrades ordinary thick function values, missing capture-field names, generic witness calls without method names, opaque factory destinations, or correctly guarded unknown async bindings into observed wrong output. They remain completeness gaps until a specific current claim is refuted.

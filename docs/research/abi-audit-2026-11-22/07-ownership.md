# 07 Ownership, runtime contracts, exclusivity and synchronous coroutines

Target is arm64/arm64e Mach-O, dev b404252 plus unqualified runtime-hop WIP. Verified checkout heads Swift 83eb12448e4323abbf81b0153dced2faff02d22f and LLVM/Clang fb5f84d903a3b4e7aea15cd5666598a46f56c833. PATH selects /Library/Developer/CommandLineTools/usr/bin/swift, Swift 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1). xcrun selects Xcode 27.1 (27A9275) Swift 6.4.0 (swiftlang-6.4.0.34.1 clang-2100.3.34.1). Both report default arm64-apple-macosx27.2.0. Pin executable, SDK, target/deployment, optimization, resilience, feature modes, and runtime/cache OS build per oracle. Public release source and Apple binaries have separate build identities. This report used source only. Existing tests were inspected without running builds or tests.

Reports 01/02 own ordered ABI and witness dispatch, 03 task/async allocations, 04 error/exit state, 05 closure capture and specialization, 06 foreign dispatch and 08 machine ABI. This report supplies ownership and synchronous scope semantics.

## O01 Exact runtime identity and contract selection

**Partial.** RuntimeFunctionReference.swift:12–60,74–102 identifies exact two-level imports or exact runtime-image exports. Disassembler.swift:4471,4854,5531–5550,5851–5914 and CacheSymbols.swift:135–218 connect those to call sites. RuntimeFunctionReferenceTests, ARCImportBindingTests, RuntimeCacheARCOriginTests and RuntimeARCOriginFixtureTests cover foreign twins, conflicting bindings, addends, malformed islands and export flags. Identity membership is calibrated to ARC result forwarding. Void ARC, weak/unowned, access scopes and distinct conventions need their own exact contracts.

Compiler declares different conventions, effects and result attributes across similarly named symbols in RuntimeFunctions.def:215–288,332–367,437–492. IRGenModule.cpp:548 maps SwiftDirectRR to PreserveMost. HeapObject.cpp:69–88,226–238 contains assembly aliases and runtime dispatch entries. [Runtime declarations][rr] [Convention mapping][rrcc] [Aliases][aliases]

Implement an exact symbol/provider contract registry. Preserve ordinal, bind/addend, resolved owning image/slice, export kind and verified bounded island chain. Resolve ordinary reexports and availability/alias variation from pinned SDK and cache evidence. Attach version or build evidence where a claim depends on implementation layout or preservation. Separate signature, register mask, result identity, scoped effect and renderer use. IndirectResults.swift:206–232 currently lets a correctly bound swift_/objc_ prefix imply a direct result, with exceptions. Require an exact declaration result role. Coordinate with 03/04 and 08. The trust boundary is normal loader agreement.

Compare independently decoded bind/load commands, dyld_info fixups/exports and disassembly against actual system calls and local/foreign twins. Mutate ordinal, addend, slot, export flag/address and island opcode. Close when no foreign path receives a system contract, aliases supported by evidence qualify, and filtered, array and streaming paths share the decision.

## O02 Strong ARC, bridge bits and ObjC handshakes

**Partial, source-risk.** Pseudo.swift:1236–1325 gates selected helpers by ARC identity while wider runtime-noise selection uses prefixes. ValueTracking.swift:1118–1155,2409–2425 applies field-preservation using spelling for e.g. objc_retainBlock and swift_beginAccess/endAccess, carried across outlined helpers by CalleeRegisterSummary.swift:1005–1023. FieldAliasTests.swift:36–45,94 encode access-marker preservation without positive binding. RuntimeResultIdentityTests checks single evaluation. RuntimeStatementTests/ReconstructionTests distinguish statements and visible values.

HeapObject.cpp:474–588,835–849 retains transported pointer and can invoke destruction through release. SwiftObject.mm:676–808 routes tagged, native and ObjC bridge operations and preserves bits of retain result. RuntimeFunctions.def:648–696 distinguishes uniqueness Bool from retain identity. [Native ARC][native] [Bridge ARC][bridge] [Uniqueness][unique]

After O01, separate exact result identity, bridge bits, register-specific forms, counted/nonatomic forms, deinit and callback effects, ObjC return handshakes, pools and block heap-copy. Apply source ARC reduction only under a valid local lifetime pattern, preserving observable release ordering. A retain alias does not justify replaying the producer or assuming purity. Consume 06's proven ObjC ABI; native/foreign bridging deserves separate effect contracts.

Use emitted IR/assembly plus native logs for bridge/native/ObjC identity, CoW Bool, nil, autorelease pools, copied blocks, and last release invoking a callback that mutates an alias. Change retain to release, alter identity source register, and redirect same-spelling release or access to an ordinary local or foreign implementation. Require exact value and effect order across renderers, including an opaque effect when the proven contract disappears.

## O03 Weak, unowned and side tables

**Partial.** SwiftRuntimeSignatures.swift:449–454,591–631 has scalar carriers; RuntimeArityTests.swift:152–173 checks arity. Neither represents slot lifecycle or ownership of a successful load result.

HeapObject.cpp:762–811 upgrades checked unowned refs or aborts on deinitializing target and the consume form releases unowned storage. HeapObject.cpp:1068–1125 defines native weak entrypoints. RefCount.cpp:19–115 allocates and transitions side-table counts. SwiftObject.mm implements unknown-object routing; Objective-C weak slots and unsafe-unowned storage need distinct classification. Weak load may produce an owned value or nil, and take consumes the slot. Side-table identity cannot substitute for object identity. [Unowned upgrade][unowned] [Weak entrypoints][weak] [Side tables][side]

After O01/O05, add weak/unowned init, assign, copy, take, load and destroy source/destination transitions. Model nil or trap conditions and release effects. Use compiler test/IRGen/weak.sil and weak_value_witnesses.sil, Swift and ObjC weak properties, and native live-load, nil-after-deinit and dead checked-unowned subprocess oracles. Mutate load to take, copy-init to assign, overlap source/dest or remove provider evidence. Require exact bounded storage roles and uncertainty for unknown weak target or slot.

## O04 Borrow, consume, move-only, lifetime dependence and self

**Partial and conservative declines required.** SwiftLowering.swift, Disassembler.swift:8334 and ValueTracking.swift provide receiver and carrier evidence. CompilerHelperInputs.swift:24–25 recognizes some outlined ownership helpers. These do not provide cross-call lifetime state.

Types.h:4450–4512,4918–4967 defines owned/guaranteed and direct/indirect plus aliasable inout and result ownership. IRGenSIL.cpp:1281–1302,1429–1441,6304–6321 can erase move/borrow/dependence markers from machine transport. SILGenApply.cpp:7988–7997 marks an addressor result dependent on self. Darwin AArch64 CCIfSwiftSelf passes an attributed carrier in x20; receiver, metatype, closure context, inout self and dependent storage each need separate proof. [Parameter conventions][params] [Ownership forwarding][mark] [Addressor][addressor] [SwiftSelf][self]

Retain all parameter contracts in the schema. Indirect_In transfers a valid nonaliasing object into callee destruction. Indirect_In_Guaranteed preserves it for the borrow without writes. Indirect_Inout permits exclusive mutation while preserving a valid object. Indirect_InoutAliasable allows well-typed aliases within the scope without escape. Indirect_In_CXX allows writes with caller destruction. Direct_Owned transfers destruction responsibility, Direct_Unowned guarantees validity at entry, and Direct_Guaranteed guarantees validity through the call. Pack_Inout, Pack_Owned and Pack_Guaranteed carry the corresponding access/transfer distinction per element. Track UnownedInnerPointer dependence on self separately from Autoreleased return handshakes. [Parameter conventions][params] [Result conventions][result]

Extend 01/O05 facts with transfer/borrow scope and a dependent base region, using typed and machine-local provenance, retaining only path-consistent facts. Decline source ownership distinctions erased by lowering. Compare test/SILGen/lifetime_dependence_lowering.swift plus SIL/IR/asm for move-only deinit counters, borrowing and consuming boundaries, addressors and self/argument-dependent Span-style results. Native logs check survival during borrow and exactly-once cleanup after consume, on normal and throwing paths. Mutate the dependent base or introduce an escape, and include distinct SIL with identical machine transport as a required conservative decline.

## O05 Value witnesses and initialized result storage

**Partial.** MetadataSymbolizer.swift:117–174, Disassembler.swift:4700–4816 and Pseudo.swift:879–900,972–980 identify and classify witness calls. ABISourceLoweringTests, ValueWitnessArgumentTests and VoidWitnessTests cover naming and arity. IndirectResults.swift:26–132,288+ and ValueTracking.swift carry x8/frame tracking. Separate witness identification (02) from its ownership effects.

ValueWitness.def:114–163 defines distinct initialize/assign/copy/take/destroy assumptions and destination alias results. IRGenSIL.cpp:8494–8568 chooses operations from source take and destination init bits and type lowering. Types.h:4918–4967 defines indirect result ownership. [Witness semantics][vwt] [Address operations][copy] [Result conventions][result]

Add storage identity, extent and generation with initialized, uninitialized, moved/destroyed and unknown states. Lifetime and content effects are distinct. Copy preserves source, take invalidates source, assign replaces live destination, destroy consumes it, and new indirect result storage becomes initialized only on proved result edges. Imported/custom destruction can affect aliases. O03/O06/O07/O09 share storage effects; 04 supplies exit checks.

Use independent SIL/IR and native deinit/write logs for POD, ARC, noncopyable and C++ values, outlined/indirect witnesses and normal/error result buffers. Mutate witness slots, metadata size, init status, swap/overlap buffers, and leave an error-path buffer untouched. Close when no stale use follows take/destroy, valid returned destination aliases still identify the buffer, and unknown extents or effects cause conservative invalidation.

## O06 Access scopes, inout, aliasing and escapes

**Partial, source-risk.** FrameMemoryEffect.swift and CalleeMemoryEffect.swift:53–75,84–227 support bounded body stores and conservative frame reachability. ValueTracking.swift:6539–6733 carries durable escapes. SharedFrameMemoryEffectTests, ExactFrameMemoryEffectTests, ABIFrameOwnershipTests and FieldAliasTests cover range and marker evidence. There is no complete scope token joining begin/end across CFG, signed accesses, aliases and no-track forms.

IRGenSIL.cpp:7097–7155,7276–7355 erases static/unsafe checks, emits dynamic scratch and flags, can omit end for no nested conflict, and uses arm64e authenticated temporary/writeback for signed scopes. RuntimeFunctions.def:1946–1961 and Exclusivity.h:31–50 specify the four operands, including PC, and the scratch lifetime. MetadataValues.h:1516–1554 defines flags. Types.h:4473–4485 distinguishes inout from aliasable inout. The marker has scoped scratch/tracking effects and can trap. It says little about pointer escape from the scope's user code. [Begin][begin] [End][end] [Runtime scratch][scratch] [Access flags][accessflags]

After O01/O05, pair begin/end by proven scratch generation, checked address and action flags. Model scratch/TLS/cleanup separately from changes to accessed storage. Track writeback, disjoint subfield alias and escaped inout via shared effects. Reuse 05 capture/escape and 08 arm64e support.

Use IRGen/exclusivity.sil and preserve_exclusivity.swift/Swift controls for static, disabled, read/modify, no-nested-conflict, disjoint field, nested or escaped access, and throwing cleanup. Native conflict subprocess and writeback sentinels verify semantics. Mutate scratch, flags, alias span or an exit; retain bounded facts only with full applicability proof.

## O07 Synchronous coroutine signature and ramp results

**Partial, source-risk.** Disassembler.swift:12939+ and ValueTracking.swift:587–603,1579 specialize the .modify ramp to x1. ReconstructionTests.swift:645 exercises a stored-property ramp. MethodImplementation.swift:10–11, VTableIndex.swift:146, ResilientWitnessIndex.swift:34 and MetadataSymbolizer.swift:569–572 distinguish certain descriptor references without an ordered coroutine resume/yield signature.

Types.h:5237–5259 defines None, legacy YieldOnce for _read/_modify, callee-allocated YieldOnce2 for yielding borrow/mutate, and YieldMany. GenCall.cpp:820–908 expands continuation first, individually direct or indirect yields, and an overflow pointer as needed. YieldMany continuation repeats ramp yield schema, while once continuations use normal-result expansion. IRGenSIL.cpp:3958–3984,4828–4861 supplies legacy buffers versus static frame plus allocator. Metadata.h:585–607 and GenCall.cpp:2618–2652,2736–2848 describe CoroImpl and indirect descriptor paths. [Kinds][kinds] [Results][cororesult] [Frame setup][corocall] [Method descriptor][coroimpl]

SILYieldInfo uses ParameterConvention as YieldConvention (Types.h:5191–5235). Preserve the ordered guarantee/ownership/access kind with each yielded carrier. For accessor normal results, Types.h:4952–4964 defines GuaranteedAddress and Guaranteed for address/value borrowing within a valid scope, and Inout for mutation within a valid scope. These are result conventions separate from yield carriers and from an initialized owned x8 output. The arm64 Darwin SwiftCoro attribute puts the allocator in x23 (AArch64CallingConvention.td:387–388), distinct from the frame operand and SwiftAsync context. [Yield convention][yieldconv] [Scoped result conventions][result] [Darwin SwiftCoro][swiftcoro]

After 01/02, use ordered signature roles for ramp, continuation, buffer/allocator, yield transport/overflow and declaration/descriptor identity. Preserve partially known roles. Compare ordinary getter, _read/_modify and yielding borrow/mutate in direct, witness and virtual calls with value, address, FP, generic and overflowing yields. Use test/IRGen/coroutine_accessors.swift, coroutine_accessors_popless.swift and loadable_by_address.sil. Include valid YieldMany SIL through the matching IRGen harness when source syntax is unavailable. Mutate descriptor indirection/flag, result piece, witness slot and suffix. Require correct ordered yields without fabricated yield at a getter or final once continuation.

## O08 Coroutine activation, normal end, abort and frame lifetime

**Conservative decline / missing activation model.** O07 represents portions of entry/ramp behavior. It has no pairwise begin_apply/yield/end/abort activation timeline. Task/async resume (03) uses a different ABI.

SILGenApply.cpp:5369–5397,7999–8014 routes legacy unwind to abort and new yielding accessors to completion even on caller throw. IRGenSIL.cpp:4863–4930 authenticates continuation using frame and type schema, passes buffer plus abort bit for legacy or buffer plus allocator for callee-allocated, then cleans temporaries. IRGenSIL.cpp:6898 deallocates allocated frames at dealloc_stacks. GenCall.cpp:5050–5068,5180–5250,5271–5308 covers pointer-auth and retcon variants. [SIL cleanup][coroclean] [Unwind][corounwind] [Continuation][cororesume] [Retcon][retcon]

After O04/O05/O06/O07, track activation identity from each ramp/frame/allocator, yield scope, replacement continuation for YieldMany, and edge-specific completion/abort and memory lifetimes. Preserve distinction between frame, overflow and user yielded address. Consume 04 and 08 auth/exit proof. Compare SIL begin/end/abort, retcon IR and split disassembly with a native accessor logging before yield, after yield and defer across a normal value and an enclosing throwing consumer. Include nested same-callee activations, frame fallback and repeated yield. Mutate frame/allocator/auth modifier, continuation, throw edge or legacy abort bit. Close when exactly-once cleanup, writeback and scope matching are verified and incomplete matches render explicit calls or unknown yields.

## O09 C++ lifetimes at Swift boundaries

**Partial / unverified.** IndirectResults.swift:26–132,186–188 has result-buffer recognition. SwiftLowering.swift has no C++ lifetime classification. Report 06 supplies foreign classification.

GenStruct.cpp:570–678,754–792,845–923 selects copy/move construction and complete destructor versus Swift type handling. IRGenSIL.cpp:3179–3232 forms foreign signatures with constructor info. Clang ItaniumCXXABI.cpp:74–82,1389+, Targets/AArch64.cpp:418,742 and CGCall.cpp:4280,4866–4880 classify non-register records, return ABI and callee-destroyed args. [Swift construction][cxxcopy] [Swift destruction][cxxdestroy] [Clang record ABI][cxxabi] [Clang parameter cleanup][cxxtemp]

Use 06 declarations, 01 carrier roles and O05 storage roles to represent construction, this, copy/move source, sret, and caller/callee cleanup, preserving arbitrary constructor/destructor effects. Compare Swift SIL/IR with Clang IR/asm and native copy/move/destroy logs across trivial, nontrivial, trivial-ABI, by-value/reference, deleted-copy and return-in-place forms. Mutate destructor ownership or variant, this/source order, and result storage. Require count/order agreement and conservative unknown where declaration or ownership is erased. Coordinate exception behavior with 04/06.

## Integration

1. Qualify O01/O02 along with 03/04 and separate identity, preservation and side effects.
2. Implement O05/O06 shared storage and scoped effects. Integrate O03/O04/O09 as evidence producers.
3. Implement O07/O08 together with 01/02/08 ABI proofs. Qualify descriptor dispatch and cleanup separately from rendering.
4. Record checked-correct, reproduced-wrong, conservative-decline and unavailable-oracle counts separately. Run supported contracts and mutations through both renderers and filtered, array and streaming consumers. A provable role needs a positive sample and regression test. An erased role needs a negative sample and a documented decline.

[rr]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/Runtime/RuntimeFunctions.def#L215-L492
[rrcc]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenModule.cpp#L548
[aliases]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/stdlib/public/runtime/HeapObject.cpp#L69-L88
[native]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/stdlib/public/runtime/HeapObject.cpp#L474-L588
[bridge]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/stdlib/public/runtime/SwiftObject.mm#L676-L808
[unique]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/Runtime/RuntimeFunctions.def#L648-L696
[unowned]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/stdlib/public/runtime/HeapObject.cpp#L762-L811
[weak]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/stdlib/public/runtime/HeapObject.cpp#L1068-L1125
[side]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/stdlib/public/runtime/RefCount.cpp#L19-L115
[params]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/AST/Types.h#L4450-L4512
[mark]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenSIL.cpp#L6304-L6321
[addressor]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/SILGen/SILGenApply.cpp#L7988-L7997
[self]: https://github.com/swiftlang/llvm-project/blob/fb5f84d903a3b4e7aea15cd5666598a46f56c833/llvm/lib/Target/AArch64/AArch64CallingConvention.td#L377
[vwt]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/ABI/ValueWitness.def#L114-L163
[copy]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenSIL.cpp#L8494-L8568
[result]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/AST/Types.h#L4918-L4967
[begin]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenSIL.cpp#L7097-L7155
[end]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenSIL.cpp#L7276-L7355
[scratch]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/Runtime/Exclusivity.h#L31-L50
[accessflags]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/ABI/MetadataValues.h#L1516-L1554
[kinds]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/AST/Types.h#L5237-L5259
[cororesult]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenCall.cpp#L820-L908
[corocall]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenSIL.cpp#L3958-L3984
[coroimpl]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/ABI/Metadata.h#L585-L607
[coroclean]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/SILGen/SILGenApply.cpp#L5369-L5397
[corounwind]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/SILGen/SILGenApply.cpp#L7999-L8014
[cororesume]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenSIL.cpp#L4863-L4930
[retcon]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenCall.cpp#L5180-L5250
[cxxcopy]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenStruct.cpp#L570-L678
[cxxdestroy]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenStruct.cpp#L754-L792
[cxxabi]: https://github.com/swiftlang/llvm-project/blob/fb5f84d903a3b4e7aea15cd5666598a46f56c833/clang/lib/CodeGen/ItaniumCXXABI.cpp#L74-L82
[cxxtemp]: https://github.com/swiftlang/llvm-project/blob/fb5f84d903a3b4e7aea15cd5666598a46f56c833/clang/lib/CodeGen/CGCall.cpp#L4866-L4880
[yieldconv]: https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/AST/Types.h#L5191-L5235
[swiftcoro]: https://github.com/swiftlang/llvm-project/blob/fb5f84d903a3b4e7aea15cd5666598a46f56c833/llvm/lib/Target/AArch64/AArch64CallingConvention.td#L387-L388

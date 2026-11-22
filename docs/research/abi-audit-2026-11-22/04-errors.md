# 04 — Swift error channels and exits

Darwin arm64/arm64e scope. Source-only audit, with no build or native reproduction performed here.
Status describes code evidence. Source-risk requires a compiled reproducer for promotion to confirmed-wrong.
Use the PATH Apple Swift 6.4.2 CLT executable pinned in scope-and-evidence.md. Upstream pins establish
compiler mechanisms, and the installed compiler establishes emitted ABI. Fixture-gated tests listed below
are coverage pointers.

## Physical and semantic taxonomy

- Sync native untyped uses swifterror x21 for the error object, with null input. Normal return can
  leave null untouched. Throw can leave the success lanes undef. Caller clears after observing the
  error. Swiftself uses x20 where applicable, and a thin throwing entry can have a placeholder context.
  An Error existential is determined by canonical SIL type and indirect convention.
  [GenCall.cpp expandParameters L2040–2134](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenCall.cpp#L2040-L2134)
  [SILFunctionType.cpp isTypedError L5709–5714](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/SIL/IR/SILFunctionType.cpp#L5709-L5714)
  [LLVM AArch64CallingConvention.td L65–77](https://github.com/swiftlang/llvm-project/blob/fb5f84d903a3b4e7aea15cd5666598a46f56c833/llvm/lib/Target/AArch64/AArch64CallingConvention.td#L65-L77)
- Sync typed direct uses x21 as flag 0/1, including empty error types. The combined native schema
  pairs integer/pointer lanes, widens unlike paired components, skips FP success components while
  building error mapping, and leaves inactive output lanes undefined. Success and error interpretations
  are mutually exclusive. A type name and integer x0 alone are insufficient to project the payload.
  [GenCall.cpp combineResultAndTypedErrorType L432–499](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenCall.cpp#L432-L499)
  [IRGenSIL.cpp visitThrowInst L4666–4722](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenSIL.cpp#L4666-L4722)
- Sync typed indirect retains x21 flag and adds an ordinary error payload pointer after flag in IR
  signature and before witness trailers. This applies when either SIL side is indirect, the native
  success schema requires indirect, or the error schema requires indirect including non-int/ptr
  components. Distinguish SIL error destination with throw_addr from an IRGen temporary for SIL-direct
  payloads lowered indirectly. Ordinary success buffers are independent and leading. Multiple SIL
  indirect success results disable sret. Darwin x8 applies to the sret case.
  [GenCall.cpp expandResult/expandIndirectResults L688–763](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenCall.cpp#L688-L763)
  [GenCall.cpp sync call slots L2865–2914](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenCall.cpp#L2865-L2914)
  [IRGenSIL.cpp visitThrowAddrInst L4782–4821](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenSIL.cpp#L4782-L4821)
- Async native has distinct entry, await resume and parent resume. Darwin async context is x22.
  Continuation x20 holds a null success or an untyped error object / typed flag as swiftself.
  At entry x20 can be self. Typed direct uses combined lanes. Typed indirect adds a separate payload
  pointer before closure context and witness trailers. Async success buffers precede user formals
  and sret is disabled. Receiver, context and runtime transfer provenance are independent.
  [GenCall.cpp async return and entry signature L2181–2345](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenCall.cpp#L2181-L2345)
  [GenCall.cpp expandAsyncAwaitType L2379–2431](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenCall.cpp#L2379-L2431)
  [GenCall.cpp emitAsyncReturn L6656–6715](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenCall.cpp#L6656-L6715)
- SIL try_apply has success/error edges and distinguishes flag tests from payload extraction.
  Return, throw, throw_addr, unreachable and coroutine unwind have different meanings. A Never success
  type rules out normal values. A Never thrown type rules out errors while still permitting abstracted
  code to thread the error channel. C noreturn, hardware trap, coroutine exit, foreign EH and NSError
  bridge have separate semantics. Foreign kinds are ZeroResult, NonZeroResult, ZeroPreservedResult,
  NilResult and NonNilError with parameter index and ownership. SIL ResultConvention is Indirect,
  Owned, Unowned, UnownedInnerPointer, Autoreleased, Pack, GuaranteedAddress, Guaranteed, Inout.
  Formal indirect is Indirect or Pack. SIL ownership and machine location are independent.
  [IRGenSIL.cpp try_apply L4053–4159](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenSIL.cpp#L4053-L4159)
  [IRGenSIL.cpp visitUnreachableInst L4465–4492](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenSIL.cpp#L4465-L4492)
  [SILType.cpp isNoReturnFunction L759–767](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/SIL/IR/SILType.cpp#L759-L767)
  [AST Types.h L4918–4969](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/AST/Types.h#L4918-L4969)
  [ForeignErrorConvention.h L27–77](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/AST/ForeignErrorConvention.h#L27-L77)

## Gaps and independent negatives

| ID / status | Current consumer / tests | Work item and acceptance mutation |
|---|---|---|
| E01 supported baseline, partial CFG | SwiftErrorExitProof.swift:28,47,63,74,116 and Disassembler.swift:12432–12503. ErrorExitProofTests.swift:26,36,78,116. | Generalize to full-width zero/nonzero/unknown with channel owner and guard provenance. Recognize proven compare+branch, copies and restores. Mutate a full-width test to W-width with high bits nonzero, insert undecoded instruction or unknown predecessor. No invented exit. |
| E02 partial call effects | ValueTracking.swift:1815,2215–2238 and Structurer.swift:1282. SwiftErrorCalleeTests.swift:35–148 and PlainNameErrorABITests.swift:108–291. | Share preserve/define/unknown effects across the tracer and renderer. A call without proof cannot preserve a live channel merely because unarmed or conventionally callee-saved. Keep unrelated register use separate. Mutate import provider, call target or arming independently. |
| E03 source-risk typed error projection | Disassembler.swift:13173–13190 reads x0 literal for enum cases without proving error payload location, including the use of a sync result map at async exit projection. SwiftErrorCalleeTests.swift:187,206 covers tiny typed error. | Recover typed payload only from proved lane map or buffer. Include FP success, zero-width payload, indirect tiny error forced by large success, multiple lanes and async. Mutate unrelated x0 to a valid enum tag while preserving flag and actual payload. No invented case. |
| E04 conservative-decline typed buffers | Disassembler.swift:7350,9886,12110,13244 and IndirectResults.swift:25–103,235–333 cover known argument-layout decline and x8 result. ResilientTypedErrorSpecializationTests.swift:18–90 and IndirectResultOrderTests.swift:12–82. | Independently locate success and error buffers including stack, caller/callee temporaries, resilience, witnesses, multiple results, alias/escape and per-outcome initialization. Mutate just error pointer identity, escape or write on wrong edge. |
| E05 partial/source-risk merged outcomes | Disassembler.swift:12385–12429,12437–12457,13169, which moves proved throws to predecessor ends. SwiftErrorCalleeTests.swift:217,277,289. | Track correlated flag/lane/buffer edge facts including CSEL. Prove exit movement preserves shared epilogue effects and applies to the selected edge only. Mutate epilogue effect, add another predecessor successor or unknown incoming edge. Preserve effect and verdict. |
| E06 partial handler reconstruction | Structurer.swift:184–201,1987 and ErrorExitProofTests.swift:131. | Analyze try? optional injection/nil, catch dispatch/cleanup, try! trap and rethrows forwarding on explicit equivalent CFG first. Mutate only optional tag, cleanup or catch terminal. Raise source syntax only with sufficient evidence. [SILGenExpr.cpp force/optional try L1303–1379](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/SILGen/SILGenExpr.cpp#L1303-L1379) [SILGenStmt.cpp visitDoCatchStmt L1357–1433](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/SILGen/SILGenStmt.cpp#L1357-L1433) |
| E07 partial terminal proof | Structurer.swift:112,1857,1971 and FunctionCFG.swift:81,156. NeverThrowingSpecialization.swift:36–131 and its tests; ErrorExitProofTests.swift:94. | Independently prove no success, no error and no machine continuation. Compare throwing Never, throws(Never), native trap and imported noreturn. Mutate call identity/contract or make the target return. [GenCall.cpp C noreturn handling L4048–4068](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenCall.cpp#L4048-L4068) |
| E08 conservative-decline throwing tails | Disassembler.swift:12514–12569 handles call+ret untyped only and selected direct values. Actual scalar tail logic at 6453,12956,13104. SwiftErrorCalleeTests.swift:206 typed control. | Prove b/br/authenticated transfer or bl/ret, correct arming, compatible success/error schemas and buffer identity, and no intervening handler. Reabstraction/boxing retains its own effects. Mutate lanes, buffer, context, target type or cleanup one at a time. [AArch64ISelLowering.cpp tail/sibling decision L8997–9044](https://github.com/swiftlang/llvm-project/blob/fb5f84d903a3b4e7aea15cd5666598a46f56c833/llvm/lib/Target/AArch64/AArch64ISelLowering.cpp#L8997-L9044) [Swift typed throws thunk IR tests](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/test/IRGen/typed_throws_thunks.swift) |
| E09 partial async outcomes | Disassembler.swift:2567–2593 declines typed awaited value, 12305–12362 uses bounded single-predecessor x20 guard, 12488–12503 normal proof. ErrorExitProofTests.swift:166–200 and Fixtures/Sample/typedthrowsawait.swift. | Use E01/E03/E04 after proving await producer and resume role. Join across authenticated parent transfers and known executor hop lineage. Mutate parent slot, x20 role, producer, guard width or error storage. Keep mixed/escaped contexts unresolved. |
| E10 source-risk helper identity | Disassembler.swift:12355,12368–12392 uses helper prefixes and a function-wide set of swift_willThrow operands. ThrowValueTests.swift:10 and SwiftErrorCalleeTests.swift:247. | Require provider-bound runtime identity and value provenance. A hook observed on only one path cannot prove non-null across a join. Mutate target to a same-prefix local helper or move hook to just one branch. [SILGenStmt.cpp emitThrow L1667–1713](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/SILGen/SILGenStmt.cpp#L1667-L1713) |
| E11 unverified foreign composition | PlainNameErrorABITests.swift:108–184 system C controls, SwiftErrorCalleeTests.swift:129 ObjC thunk. | Share foreign importer's parameter, ownership, sentinel and provider evidence. Keep NSError bridge, native error and foreign EH separate. Add each applicable foreign convention and mutate just sentinel polarity or provider. |

## Implementation dependency and completion criteria

1. **Shared lowered signature.** Record target ABI, representation, abstraction/substitution level,
   and boundary kind. Record physical locations with bank/lane/width, stack offset or proved context
   slot. Give each location role, ownership, evidence, and validity (always, success-only, error-only,
   unknown). Keep self, current/parent context, direct and indirect success, discriminator, untyped
   error object, typed error lanes/buffer, metadata and witnesses independently queryable. Record
   semantic outcome possibilities independently of machine channel presence.
2. **Proof transfer and exits (E01, E02, E05, E10).** Use shared call effects, exact channel owner,
   SSA or memory-version guard provenance, null/non-null/unknown joins and explicit CFG opacity.
   Apply proven edge initializations to the proper outputs. Publish one exit verdict across APIs.
3. **Physical payloads/storage (E03, E04).** Map complete typed error and success lanes using
   target/schema and abstraction, with buffer provenance. Permit proven throw with unknown payload.
4. **Compose (E06–E09, E11).** Use proven async relationships and foreign transition contracts.
   Distinguish normal exit, throw, conditional forwarding, trap/no continuation, unwind and unresolved.
   Track effects and preserve their order even where a typed result cannot be named.
5. **Close against independent oracles.** For each row capture exact Apple compiler/version and
   target, then SILGen, IR and machine assembly at -Onone and -O. Compare symbols, relocations and
   stripped image. Build separate provider/client artifacts for resilience, run native success and
   error values with distinct sentinels, check optional results and ordered cleanup effects, and use
   a subprocess for trap/no-return outcomes. Use arm64e static checks or executable tests where
   available. Upstream [typed_throws_abi.swift](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/test/IRGen/typed_throws_abi.swift)
   and [typed_throws_generic.swift](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/test/IRGen/typed_throws_generic.swift)
   seed the matrix. Mutate one condition at a time in decoded or binary fixtures. Acceptance per row
   is matched static/native positive evidence, a failing-before negative for correctness fixes,
   agreed verdict and output provenance across API paths, and explicit unresolved output where
   evidence is insufficient.

### Runtime declarations and terminal control flow (E12, partial / coverage unverified)

The generated SwiftRuntimeSignatures.swift projection (header lines 1–26) and
Tools/runtime-signatures.py:24–62 retain scalar width/arity for filtered entries
and use unknown result for unsupported shapes. A void result is not a terminal
call contract. Audit generation against canonical RuntimeFunctions.def,
IRGenModule's runtime attribute translation, and matching exported declarations
and availability for the selected provider. For instance the pinned runtime
table carries NoUnwind and NoReturn together, while the compiler defines
WillReturn independently. Record unknown arity, actual formal roles, indirect
results, Swift channels, NoUnwind, NoReturn and relevant target/provider
availability separately. Reconcile generated rows by counts and reason for
omission only when the source corpus and manifest are available. Any 609/661
figure is historical and unmeasured in this audit.

Apply terminal edges in FunctionCFG.swift:81,156 and propagate the same outcome
through value tracking and all renderers. Qualify by exact provider and resolved
target as with the existing named ABI contract, including authenticated resolved
targets where supported. An ordinary noreturn call and foreign-unwinding call
have different successor requirements. Keep a possible unwind edge when proof
permits unwind. Independently mutate a true noreturn import to a returning
shadow provider with identical spelling, and change a genuine void control to
consume a later effect. Accept only when genuine terminal and returning void
controls distinguish in CFG and output, static declaration evidence agrees with
native subprocess behavior, and stale values across a cut are impossible.
[RuntimeFunctions.def L193–205](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/Runtime/RuntimeFunctions.def#L193-L205)
[IRGenModule.cpp RuntimeConstants L784–799](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenModule.cpp#L784-L799)

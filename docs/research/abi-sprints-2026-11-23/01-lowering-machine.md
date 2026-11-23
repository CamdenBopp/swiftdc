# Lowering and machine ABI sprints

Read-only research, 2026-11-23. Reference prose genre. No compiler, decompiler, build, test, native fixture or measurement was run. All before/after renders in the sprint specifications are proposed acceptance criteria, not observations from this session.

## Revisions, evidence and limits

- swiftdc HEAD is `ca9eef5ce2909f5f584d8270026f606c3f1b1e0e` on `dev`.
- `git -C <swift checkout> rev-parse HEAD` returned `1b7bd8eaf460396047c2644d1d69afb4a404b13d`. It does **not** match the plan's `83eb12448e4323abbf81b0153dced2faff02d22f` pin. The local commit subject is `Merge pull request #91963 from xedin/called_once+dependent-types`, dated 2026-09-07.
- The pinned object is absent locally. `git cat-file -t 83eb12448e4323abbf81b0153dced2faff02d22f` failed, so an exact source diff against that pin was unavailable. I did not fetch during the running measurement.
- Clang's `SwiftCallingConv.cpp`, `ABIInfo.cpp` and LLVM's AArch64 target implementation are not in the Swift checkout. A tracked-file search of that checkout found no `SwiftCallingConv.cpp` or `AArch64CallingConvention.td`. The conventional sibling locations `~/llvm-project` and `~/llvm` did not supply the former file either. Backend details below are explicitly conditional on re-reading the LLVM pin before implementation. Swift's call sites and ABI summary verify only part of those rules.
- I read the two audits, `docs/ABI-CLOSURE-PLAN.md`, the current-status and entry-oracle sections of `docs/STATUS.md`, and topic-selected readiness entries. STATUS's published baseline is older than HEAD. It is not a current ABI coverage result.
- Existing uncommitted work was preserved. In the inspected files, the Disassembler changes are async additions before the lowering consumers; they shift those consumer lines by +87. ValueTracking has an eight-line insertion after HEAD line 4230. The researched lowering and call-effect bodies are unchanged at HEAD. I checked the zero-context diff and HEAD symbol line numbers. Untracked async solvers and the uncommitted flag-width changes are not counted as shipped support.
- Citation roots below are absolute. `S/` means `Sources/SwiftDecompilerCore/`; `T/` means `Tests/SwiftDecompilerCoreTests/`; `C/` means `<swift checkout>/`. **S citations use HEAD line numbers**, including Disassembler and ValueTracking. In the live working tree, add 87 to the cited Disassembler consumer lines and eight to ValueTracking lines after 4230. All other cited source/test files were unchanged by the relevant working diff.
- `Read-verified` means I inspected the implementation or test assertion. `Inference` means the source suggests a possible output or missing behavior that still needs execution. Existing test assertions are evidence of intended coverage, not a fresh passing result.

The audit links are not interchangeable with local citations. Examples of verified local locations are GenCall's native schema at 957-984 rather than the audit's 959-986; GenStruct's field lowering at 1036-1042 rather than 947-975; SIL tuple input expansion at 2169-2210 rather than 2118-2210; and the ABI-version getter at IRGenModule.cpp:2517 rather than 2345. The local enum implementation also has a concrete-pointer payload-schema path at GenEnum.cpp:1991-2107. Do not transplant the audit's generic-word explanation without checking that branch. The missing pinned object prevents a claim about exactly when these differences appeared.

## Every audit item at current HEAD

Classification is for the whole audit item. A closed subcase does not close an entire item. Counts are **0 already closed, 14 partially closed, 2 safely declined, 6 possibly wrong**. "Possibly wrong" is a triage classification, not a reproduced wrong-output finding.

| Item | Classification and current evidence | Compiler rule re-read locally | Remaining sprints |
| --- | --- | --- | --- |
| L01 Atomic scalars | Partially closed. S/SwiftLowering.swift:81-112 contains Int64/UInt64 and Float16, but S/Disassembler.swift:10323-10330 repeats a result list without Float16. Imported integer enums get a parameter override at S/Disassembler.swift:8768-8770, not the shared result classifier. `Unicode.Scalar` and `Unmanaged` are merely `.direct`. Read-verified. T/SwiftLoweringTests.swift:7-34 and T/Int64FieldLoweringTests.swift:20-72 cover bounded cases. | C/lib/IRGen/GenType.cpp:2460-2516 derives pointer, IEEE16/32/64, arbitrary integer and fixed-vector storage. C/stdlib/public/core/UnicodeScalar.swift:35-38 stores UInt32; C/stdlib/public/core/Unmanaged.swift:17-21 stores one unsafe-unowned reference. Backend register legalization is not present locally. | L01-a through L01-f |
| L02 Zero components | Safely declined for the remaining cases. Known no-payload singleton entry is skipped at S/Disassembler.swift:7344-7347. Outgoing layout has no singleton branch at S/Disassembler.swift:7774-7809. Void and supplied empty maps work at S/SwiftLowering.swift:207-215, but S/FieldMap.swift:373-374 omits empty field layouts. T/ZeroSizedArgumentABITests.swift:19-116 proves intended Void/source-slot handling. T/ABISourceLoweringTests.swift:315-322 does not assert positive caller recovery. | C/lib/IRGen/GenCall.cpp:1862-1869 drops empty native schemas. C/lib/IRGen/GenEnum.cpp:535-543 forwards singleton payloads, otherwise zero components. A singleton with payload is not necessarily empty. | L02-a, L02-b |
| L03 Ordered aggregate pieces | Possibly wrong. S/SwiftLowering.swift:217-263 combines integers by chunk Set, ignoring an intervening FP component. Entry trusts counts at S/Disassembler.swift:7381-7408. Read-verified mismatch candidate; a wrong render is not reproduced here. Existing T/ABISourceLoweringTests.swift:654-666 checks common following-argument constants, not ordered mixed-half barriers. | C/lib/IRGen/GenStruct.cpp:1036-1042 and GenTuple.cpp:276-282 emit ordered offset-bearing fields. C/lib/IRGen/GenCall.cpp:957-984 delegates finishing and indirectness to Clang. The precise adjacent-merge and four-counted-component implementation remains unverified locally because Clang is absent. | L03-a, L03-b |
| L04 Tuples and abstraction | Safely declined for ordinary unsupported tuples. S/SwiftLowering.swift:74-78 has no tuple classifier; S/Disassembler.swift:7798-7809 stops placement. S/Disassembler.swift:8667-8672 and :8753-8756 strip the last colon without nesting, which must not underpin new labeled-tuple support. T/SwiftLoweringTests.swift:39-47 preserves tuple-of-closures decline. | C/lib/SIL/IR/SILFunctionType.cpp:1584-1649 separates tuple results and borrowed/mutating accessors. :2169-2210 expands eligible tuple formals but not inout or Clang references. Struct storage expansion is a different layer. | L04-a, L04-b |
| L05 Resilience and output roles | Partially closed. S/SwiftLowering.swift:231-236 vetoes possibly resilient layouts; S/FieldMap.swift:383-390 conservatively infers exported resilience. S/Disassembler.swift:7731-7734 declines generic tuple-result calls. S/IndirectResults.swift:26-38 gates x8 ABI and :278-283 requires complete nominal storage. Storage certainty still does not identify the boundary abstraction. | C/lib/IRGen/GenCall.cpp:707-760 disables sret for multiple indirect SIL outputs; :1113-1115 disables it beside a nonempty direct result. C/lib/IRGen/GenStruct.cpp:1241-1267 distinguishes nonfixed storage and ABI accessibility. | L05-a, L05-b |
| L06 Optional and enum layouts | Possibly wrong. S/SwiftLowering.swift:46-55 recursively treats Optional of any direct payload as direct without a size or extra-inhabitant bound. S/IndirectResults.swift:242-243 consumes that claim to exclude x8. Existing S/Disassembler.swift:8014-8053 handles only selected scalar payload/tag shapes. This proves an unbounded premise, not an executed bad result. | C/lib/IRGen/GenEnum.cpp:1558-1574 emits payload components plus excess tag storage. :1967-1988 proves a bounded nullable-reference rule; :2034-2042 checks extra-inhabitant capacity; :2091-2107 chooses the payload schema. | L06-a through L06-d |
| L07 Direct result projection | Partially closed. S/Disassembler.swift:6764-6781 has no field map and accepts whole results only for shared one-register cases. ValueTracking's call-result-bank path at S/ValueTracking.swift:2377-2388 distinguishes nonscalar results but does not carry arbitrary component projection paths. S/Disassembler.swift:7979-7981 still has an independent two-integer result predicate. T/ABISourceLoweringTests.swift:93-141 protects stale GP and x8 cases. | C/lib/IRGen/GenCall.cpp:973-984 enumerates native components; :1092-1115 selects direct/indirect result. C/lib/IRGen/NativeConventionSchema.h:55-76 separates component enumeration and native/non-native mapping. | L07-a, L07-b |
| L08 Native exhaustion and stack | Partially closed. Entry abandons overflow at S/Disassembler.swift:7326-7332 and :7383. Calls use one `spilled` suffix at :7771-7831. :7892-7913 only reads exact integer words at offsets divisible by eight. S/ValueTracking.swift:2523-2537 captures at most 16 contiguous slots. T/StackArgsTests.swift:9-82 mainly protects ellipsis and owned-save exclusions. | C/lib/IRGen/GenCall.cpp:1866-1869 creates the component sequence; C/docs/ABI/CallingConventionSummary.rst:168-180 specifies FP bank and SP alignment; :211-212 explicitly notes Apple's packed stack arguments. Exact independent-bank allocation and i128 boundary rules need LLVM. | M04-a, L08-a through L08-d, L01-f |
| L09 SIMD/HFA/HVA | Partially closed. S/FieldMap.swift:253-271 admits only contiguous Float/Double HFA fields; :309-339 admits a narrow flat mixed subset. S/SwiftLowering.swift:74-78 has no general vector shape. T/ABISourceLoweringTests.swift:102-123 covers HFA self, not general vector transport. | C/lib/IRGen/GenType.cpp:2500-2516 builds fixed LLVM vectors and rounded storage. NativeConventionSchema delegates target coercion. This does not prove every Swift SIMD is one Q register or that C HVA follows Swift flattening. | L09-a, L09-b, M03-a |
| L10 C/ObjC fixed calls | Partially closed. S/ObjCArgumentABI.swift:93-158 already has independent banks and natural stack packing. :185-193 explicitly declines many aggregates. S/Pseudo.swift:1177-1211 stores compact prototype codes; S/Disassembler.swift:7935-7956 has bounded register-only foreign layout. Do not redo the working ObjC scalar packing. | C/lib/IRGen/GenCall.cpp:1575-1607 distinguishes ObjC self/_cmd, objc_direct, blocks and C++ self; :1633-1644 asks Clang to arrange the foreign call; :1660-1719 handles extensions/coercions. Actual AArch64 record classification is external to this checkout. | L10-a, L10-b |
| L11 Variadics | Partially closed. S/SwiftLowering.swift:57-58 treats Swift variadics as Array. S/Disassembler.swift:10587-10628 decodes bounded printf stack tails, and :10636-10649 retains only known integer fixed formals for nonformat declarations. Named stack extent is not represented in that path. Custom declarations are often unsupported, so the missing rule is not itself evidence of current wrong output. | C/lib/IRGen/GenCall.cpp:1548-1551,1633-1644 establishes foreign arrangement; C/docs/ABI/CallingConventionSummary.rst:211-212 verifies packed fixed arguments. The unnamed Darwin assigner and promotion/slot details cited by the audit are in missing LLVM/Clang sources. | L11-a |
| L12 Hidden roles | Partially closed. Receiver seeding has separate HFA/word/mixed branches at S/Disassembler.swift:8579-8663. S/IndirectResults.swift:26-38 separates x8 eligibility. No common typed role selector covers all hidden inputs. The existing receiver paths are real support, not a blank slate. | C/lib/IRGen/GenCall.cpp:509-531 emits SwiftSelf/Coro/Error attributes; :929-954 separates Async/Coro roles. C/docs/ABI/CallingConventionSummary.rst:140-157 names x8/x20/x21/x22. x15 nest and x23 physical assignment need missing backend proof. | M02-a, M02-b, L05-b |
| M01 Call masks | Possibly wrong for unsupported conventions. S/ValueTracking.swift:2282-2323 assumes default preservation with body-clobber and throwing exceptions. S/CalleeRegisterSummary.swift:2100-2112 has another default mask. There is no demonstrated edge selector for PreserveNone/SwiftTail/SwiftCoro. Unsupported conventions may not be recoverable from a stripped binary; inferred stale-value risk remains unexecuted. | C/docs/ABI/CallingConventionSummary.rst:143-173 verifies baseline and d8-d15 width. C/lib/IRGen/IRGenModule.cpp:558-588 explicitly chooses PreserveMost, Swift, SwiftTail and SwiftCoro. Exact target masks are unavailable locally. | M01-a |
| M02 Hidden input reach | Possibly wrong. S/CalleeRegisterSummary.swift:610-613 and :2112 use an opaque ABI input set omitting x22/x23. :2077-2083 incorrectly generalizes that x22 is never a stack address. S/ValueTracking.swift:2195-2200 adds direct-body x22 reach separately, so it is not correct to claim every async call misses x22. Unknown/imported edges remain the proposed witness. | C/lib/IRGen/GenCall.cpp:929-954 proves distinct async/coro attributed operands and adds no noalias to async. C/lib/IRGen/IRGenModule.cpp:572-588 chooses their conventions. Swift's summary names x22; x23 needs backend confirmation. | M02-a, M02-b |
| M03 SIMD slices | Partially closed. S/ValueTracking.swift:5271-5290 already retains only the low lane through default calls. S/CalleeRegisterSummary.swift:632-648 distinguishes full from lane argument writes, but preservation keys remain coarse. T/NativeVectorPreservationTests.swift:6-37 asserts native values and three analysis paths for its bounded fixtures. None was rerun. | C/docs/ABI/CallingConventionSummary.rst:168-173 explicitly preserves only lower 64 bits. C/lib/IRGen/GenType.cpp:2500-2516 establishes fixed-vector storage, not arbitrary lane identity. | M03-a, L09-a/b |
| M04 Stack reach and ownership | Possibly wrong. S/ValueTracking.swift:2202-2212 stops escape scanning at a hole and after 16 words. :2523-2537 uses the same bounded snapshot. A missed pointer may leave stale pointee facts, unlike an argument display decline. Typed byte placement and SP ownership remain separate obligations. | C/docs/ABI/CallingConventionSummary.rst:179-212 specifies aligned entry SP and packed arguments. C/lib/IRGen/GenCall.cpp:1866-1869 preserves ordered exploded operands. Exact tail reuse and i128 rules require LLVM. | M04-a, L08-b/c/d |
| M05 Frames, probes, outlining | Partially closed. S/CalleeRegisterSummary.swift:962-988 proves one exact framed wrapper and :1580-1612 checks LR origin. Stack-probe register invalidations now agree at S/ValueTracking.swift:2095-2106 and S/CalleeRegisterSummary.swift:2047-2061. The audit's proposed reconciliation is stale for those lists. Red-zone ownership and helper completeness still matter. | C/docs/ABI/CallingConventionSummary.rst:176-212 verifies the frame/SP model and 128-byte red zone. Eligibility, outlined LR rewrites and probe implementation remain in missing backend/runtime code. | M05-a; preserve existing probe checks |
| M06 Exits | Partially closed. S/CalleeRegisterSummary.swift:951-988 recognizes bounded forwarding; :1580-1612 proves the incoming return-address value. Neither a CFG branch nor that proof alone supplies a coroutine completion contract. Existing ordinary/conditional tail tests must survive. | C/lib/IRGen/IRGenModule.cpp:576-580 uses musttail for supported SwiftTail, otherwise tail. C/lib/IRGen/GenCall.cpp:694-698 routes coroutines separately; :5054-5067 distinguishes coroutine resume families. Backend RET_POPLESS and sibling eligibility remain unverified locally. | M06-a |
| M07 Authentication | Possibly wrong if symbol identity authorizes invocation effects without PAC proof. S/RuntimeFunctionReference.swift:13-37 accepts BRAA/BRAB families but returns only a slot; S/Disassembler.swift:5872-5887 drops the import to symbol/provider. S/CalleeRegisterSummary.swift:1592-1595 accepts RETAA/B without a key/SP token. T/RuntimeFunctionReferenceTests.swift:127-145 positively checks slot lookup, not authentication. | C/include/swift/ABI/MetadataValues.h:1697-1816 names distinct discriminators. C/lib/IRGen/GenCall.cpp:3409-3436 signs async parent/resume with storage; :5054-5067 separates coroutine schemas. C/lib/IRGen/GenMeta.cpp:325-334 differentiates method schemas. Return-address target lowering is missing. | M07-a, M07-b |
| M08 Runtime endpoint identity | Partially closed. S/RuntimeFunctionReference.swift:40-81 requires exact export flags and provider/symbol matches. S/Disassembler.swift:5872-5887 carries no feasible-target set. Same-name impostors already have negative tests at T/RuntimeFunctionReferenceTests.swift:32-68. Backdeployment, replacement and reexport alternatives are not closed by those checks. | C/lib/SILGen/SILGenAvailability.cpp:324-349,352-433 emits original/fallback alternatives. C/lib/IRGen/GenDecl.cpp:1892-1931 uses a mutable replacement chain with sync/async/coro pointer schemas. These are distinct from ordinary exact body identity. | M08-a, M08-b |
| M09 Width and operations | Partially closed. S/InstructionSemantics.swift:109-158 already models extensions and BFI/BFXIL, with W-destination zeroing owned by the reader. S/ValueTracking.swift:5223-5228 narrows W writes. S/TypeInference.swift:41-51 covers narrow integers/Float16. The narrow/FP qualification recorded in STATUS is real bounded work, not general ISA closure. Do not queue already implemented scalar BFI or Float16 bitcasts as new fixes. | C/lib/IRGen/GenType.cpp:2460-2516 supplies type widths; C/lib/IRGen/GenCall.cpp:1660-1682 derives foreign extension attributes. Full ISA semantics cannot be proved from Swift IRGen and need a separate architectural oracle. | Width controls are required by L01, L08, L09 and M03; no speculative duplicate opcode fix |
| M10 Target/version selection | Partially closed. RuntimeFunctionReference.swift:57-81 validates providers without a target/deployment parameter. MachOPreflight validates build-version structure at S/MachOPreflight.swift:2496,2567-2572, but that is not a shared semantic envelope. No observed wrong output was established. | C/lib/IRGen/IRGenModule.cpp:2517-2518 returns the Swift ABI version. C/lib/IRGen/TBDGen.cpp:634 writes it separately. C/lib/SILGen/SILGenAvailability.cpp:324-349 depends on expansion/deployment. Compiler version is not ABI version or minimum OS. | M10-a |

## Finite-list omissions worth fixing, and one worth leaving alone

These are read-verified differences, with their render consequences still inferred unless the commit record says otherwise.

1. `wordIntegerFieldOffsetsInRegisters` still accepts only Si/Su at S/FieldMap.swift:287-296. **Do not schedule another UInt64 fix just for that list.** `mixedScalarFieldBanksInRegisters` now supplies the same ordinary struct seeds. The ca9eef5 commit and T/Int64FieldLoweringTests.swift:20-72 establish that exact slice. Unexercised mangled Int64/UInt64 spellings were deliberately removed after a surviving mutation; adding them without a fixture repeats the mistake.
2. Float16 is recognized by shared scalar lowering but omitted from `returnsOneFloat` and both field-decomposition lists. One Half field can have a proved footprint while lacking a field seed.
3. Typed pointer fields are counted by `collectScalars` but rejected by the flat `FieldMap` mixed list. Scalar pointer arguments are already supported. Preserve pointer identity, not the pointee's value or lifetime.
4. A nested one-field struct is recursively counted at S/SwiftLowering.swift:257-260 but not recursively seeded by S/FieldMap.swift:309-339. The following scalar may be recoverable while every nested field remains unknown.
5. Tuples used as stored fields lack the structured field recursion that GenTuple uses. They must not be treated as source tuple formals.
6. Character is already `.direct`, but no two-word parameter footprint follows from that. Its frozen String field is visible at C/stdlib/public/core/Character.swift:64-72. This is placement work, not permission to render its raw bits as a String literal.
7. Unicode.Scalar is a frozen UInt32 wrapper, yet is only `.direct`; Unmanaged is a frozen one-reference wrapper, yet shares a generic multiword bucket. Each merits its own scalar placement commit.
8. Int128/UInt128 and Builtin.Int128 are absent from the one-word sets, correctly so. C/stdlib/public/core/Int128.swift:18-23 and UInt128.swift:18-23 prove 128-bit storage. They require a two-word schema and backend allocation proof, not another name in `integers`.
9. A known empty struct still has no production FieldMap because the builder drops empty field layouts. The empty-map helper is not evidence that actual empty struct parameters work.
10. No general SIMD scalar/vector decomposition exists. Float16, Int128 and SIMD are different omissions and must not be landed as one expanded whitelist.

## Sprint contract

Each numbered sprint below is one commit-sized behavior. Small means a bounded classifier/consumer change with one fixture family. Medium means one shape through multiple existing consumers. Large means one behavior with a substantial oracle or provenance requirement; narrow it further if implementation starts spanning unrelated shapes.

For every sprint, keep caller and callee separately compiled, noinline and observable. Swift fixtures use **-Onone, -O and -Osize** unless the sprint explicitly says static SIL/IR/assembly is required. C/ObjC uses **-O0, -O2 and -Os**. Compile both compiler families named in the plan with explicit paths once measurements are allowed. The source snippets are sketches, not files created or code compiled here.

Before means the expected current limitation or suspicious claim, not a measured baseline. After names the one behavior the commit must prove. Preserve calls and side effects when a result declines. Every claimed behavior needs both renderers and the applicable filtered, array and streaming APIs. Snapshot the baseline release, demonstrate the new assertion red, mutate each independent gate separately, rebuild between mutations, run the enforcing suite and explain the corpus delta before committing. Do not weaken existing tests to obtain the new positive.

### 1. M04-a: Keep pointer reach past outgoing stack holes

- Axis: soundness. Size M. Confidence high in the finite scan defect, medium in an end-to-end witness. Dependencies none.
- Rule: packed stack arguments and SP coordinates, C/docs/ABI/CallingConventionSummary.rst:179-212. A missing tracked word does not prove the absence of later argument bytes. The 16-word cap has no ABI basis in the local rule.
- Change sites: S/ValueTracking.swift:2202-2212,2523-2537. Iterate tracked outgoing byte ranges within proved call-time ownership, independent of the display snapshot. An unknown extent must conservatively add reach, not stop at the last readable word.
- Fixture sketch: Swift wrapper keeps `var x = 7`, passes `&x` as the last of at least 25 pointer/integer formals to an opaque C function, then reads x. The C body writes 11. Add an authored conforming caller with an untracked/unaligned slot before the pointer. All Swift/C levels.
- Before/after: suspected `return 7` or another stale fact becomes `return ?`; no promise to render 11. Independently execute the C mutation as the truth oracle.
- Negatives: pointers only in the caller's saved-register area, disjoint callee-private stack, exact readonly callee and proven nonargument bytes must not cause arbitrary invalidation.
- Mutations: restore hole `break`; restore 16-slot cap; include save slots as arguments; suppress reach from a later byte range. Give each its own witness.

### 2. M02-a: Include a proven async context in unknown-edge reach

- Axis soundness. Size M. Confidence high in omitted input set, medium in witness. Dependencies none; coordinate with async owner work.
- Rule: C/lib/IRGen/GenCall.cpp:929-936 supplies SwiftAsync without noalias; C/lib/IRGen/IRGenModule.cpp:572-580 selects its distinct convention. An async context can be caller-owned storage. Physical x22 follows C/docs/ABI/CallingConventionSummary.rst:156-157.
- Change sites: S/CalleeRegisterSummary.swift:610-613,2075-2112 and S/ValueTracking.swift:2195-2200. Add role-aware MAY reach at explicitly admitted async edges; do not blanket classify every ordinary BL's x22 as an argument.
- Fixture sketch: `func outer() async -> Int { let n = await source(); await hop(); return n }`, plus ABI-authored veneer forwarding frame-backed context in x22 to an unresolved attributed endpoint that writes the carried bytes. All Swift levels; static assembly for the adversary.
- Before/after: a stale carried value, if reproduced, becomes unknown. The ordinary no-publication control retains its existing decline/precision. This sprint adds no positive cross-await value recovery.
- Negatives: ordinary synchronous String call while x22 temporarily holds SP; known complete body with no context read; missing entry/edge role.
- Mutations: remove x22 from admitted inputs; suppress capture at unresolved edge; misclassify an ordinary call as async. Distinct tests must reject all three.

### 3. M01-a: Decline ordinary preservation for an unproved nondefault convention

- Axis soundness. Size M. Confidence medium. Dependencies none. Acquire the pinned AArch64 mask selector before implementing a positive alternate mask.
- Rule: C/lib/IRGen/IRGenModule.cpp:558-588 distinguishes PreserveMost, Swift, SwiftTail and SwiftCoro. C/docs/ABI/CallingConventionSummary.rst:149-173 proves only the baseline. Exact PreserveNone/vector masks are not locally verified.
- Change sites: S/ValueTracking.swift:2282-2323 and S/CalleeRegisterSummary.swift:2044-2112. Admit a conservative edge mask only from target/convention/body evidence. Unknown alternate convention must not inherit default callee-save claims.
- Fixture sketch: generated caller/callee LLVM IR or supported C convention attributes, plus a veneer setting x19 to 7 before a callee that legally returns x19=11 under its nondefault convention. Swift noinline wrapper observes the register-dependent result. C and Swift levels; retain IR/assembly as the convention oracle.
- Before/after: suspected stale `return 7` becomes unknown for that admitted nondefault edge. Ordinary x19-preserving calls remain unchanged.
- Negatives: default Darwin C/Swift calls; complete local bodies proving stronger preservation; convention unavailable in the artifact must not be guessed from a name.
- Mutations: force default mask; ignore explicit definitions; apply stronger mask by symbol spelling. Each must turn a targeted test red.

### 4. L06-a: Bound recursive Optional direct-result claims

- Axis soundness. Size S/M. Confidence high in unbounded recursion, medium in a reachable wrong-render witness. Dependencies none.
- Rule: C/lib/IRGen/GenEnum.cpp:1558-1574,2034-2042 and GenCall.cpp:957-969. Tag growth and extra-inhabitant capacity participate in the native schema.
- Change sites: S/SwiftLowering.swift:46-55; S/IndirectResults.swift:242-243. Unknown nested schema must not prove x8 unused. Keep already qualified pointer/scalar/String optionals admitted on their own proofs.
- Fixture sketch: generated nested `Optional<...>` wrappers around UInt64 and a four-word frozen payload, paired with same-depth reference optionals. A separately compiled maker returns a nonnil distinctive payload, caller forwards into a buffer and reads it. All Swift levels. Increase nesting until compiler IR independently crosses the direct boundary; do not assume `Int??` already does.
- Before/after: currently recursive `isDirect == true` becomes unknown for unproved growth. If stale buffer contents are reproduced, they become `?`; positive buffer reconstruction is not required here.
- Negatives: unknown payload, unknown tag, resilient payload and four-piece boundary; retain ordinary Optional<Int>, Optional<String> and one pointer optional behavior.
- Mutations: restore recursive boolean; ignore tag contribution; infer directness from byte size alone. Distinct boundary fixtures must kill the relevant mutations.

### 5. L03-a: Preserve an FP barrier when counting integer pieces

- Axis soundness. Size M. Confidence high in local unordered Set, conditional on checking Clang's exact rule. Dependencies acquire/re-read LLVM pin, not an entire schema rewrite.
- Rule: ordered typed fields at C/lib/IRGen/GenStruct.cpp:1036-1042 and GenTuple.cpp:276-282 feed NativeConventionSchema at GenCall.cpp:957-984. The audit's adjacent-merge algorithm must be reverified in missing SwiftCallingConv.cpp before copying it.
- Change sites: S/SwiftLowering.swift:217-263, consumed by S/Disassembler.swift:7381-7408,7794-7797. Introduce only enough ordered pieces to count these barriers. Decline contradictory layouts until exact allocation is available.
- Fixture sketch: `struct A { var a:Int16; var h:Float16; var b:Int16 }`, paired reordered B with adjacent integers. Add two Doubles to each to probe the four-component direct boundary. `func after(_ a:A,_ k:Int)->Int { k &* 13 }`. All Swift levels.
- Before/after: current chunk count merges both integer fragments in A; corrected count must match independent IR. Following k becomes correctly placed or safely unknown. No invented field value or indirect pointer.
- Negatives: overlapping/untrusted map, resilient nominal, unknown field type, vector barrier, padding not represented as a field.
- Mutations: remove FP barrier; merge every shared chunk; count a wide integer as one; admit untrusted layout. Use independent assertions, including threshold and source-slot identity.

### 6. M07-a: Separate authenticated slot identity from invocation proof

- Axis soundness. Size M. Confidence high in discarded auth evidence, medium in observable effect witness. Dependencies an arm64e static fixture and pinned backend authentication rules.
- Rule: C/include/swift/ABI/MetadataValues.h:1697-1816 and C/lib/IRGen/GenCall.cpp:3409-3436 distinguish category, storage and discriminator. A known slot alone does not prove successful authentication.
- Change sites: S/RuntimeFunctionReference.swift:13-37; S/Disassembler.swift:5872-5887 and its runtime-effect consumers. Preserve displayable candidate identity while withholding invocation-specific identity/preservation contracts without the matching tuple.
- Fixture sketch: C arm64e `int (*f)(int)` in authenticated storage, with Swift wrapper calling it. Produce paired static images differing only in key, discriminator, address diversity or slot. Do not execute deliberately invalid PAC images. Use supported optimized source plus authored fixup/branch variants.
- Before/after: slot still names f; an unproved authenticated edge no longer licenses exact-body/runtime effects. Ordinary arm64 stub resolution stays unchanged.
- Negatives: plain GOT, correct exact auth tuple, same symbol at different slot, mismatching key/modifier. Do not claim to enforce runtime PAC security.
- Mutations: erase each key/modifier/storage premise independently; conflate slot identity with callable eligibility. Tests must preserve the name while declining the effect.

### 7. L02-a: Preserve singleton enum source slots at calls

- Axis completeness. Size S. Confidence high. Dependencies none.
- Rule: C/lib/IRGen/GenEnum.cpp:535-543 and GenCall.cpp:1862-1869. A no-payload singleton contributes zero native components.
- Change sites: S/Disassembler.swift:7774-7809 and source-slot layout; reuse S/SwiftLowering.swift:42-43. Entry's skip is already shipped.
- Fixture sketch: `enum One { case only }; func take(_ a:Int,_ o:One,_ b:Int)->Int { a &* 7 &- b }; func call(_ a:Int,_ b:Int)->Int { take(a,.only,b) }`. Add singleton between two FP scalars and after eight GP formals. All Swift levels.
- Before/after: `take(arg0, ?, ?)` becomes `take(arg0, ?, arg1)` or `.only` if separately proven by enum identity. Preserve all three source positions. Do not require unrelated singleton rendering.
- Negatives: resilient singleton, `inout One`, payload singleton, Optional<One>, unknown empty-looking nominal.
- Mutations: consume one GP register; drop the source slot; stop placement after zero components; erase the resilience guard.

### 8. L01-a: Keep a Float16 producer when forwarding its FP result

- Axis completeness. Size S. Confidence high in duplicate-list omission, medium in exact rendered witness. Dependencies none.
- Rule: C/lib/IRGen/GenType.cpp:2469-2476 defines Half/Float/Double separately; GenCall.cpp:1092-1115 uses the native result schema.
- Change site: S/Disassembler.swift:10323-10341 `returnsOneFloat`/`holdsWholeResults`; consume the shared scalar result classification with existing precision proof.
- Fixture sketch: `@inline(never) func half(_ h:Float16)->Float16 { h + 1 }; func forward(_ h:Float16) { knownDoubleSink(Double(half(h))) }`, using an independently admitted foreign sink declaration, and a synthetic equivalent if fixture sink discovery is not supported. All Swift levels.
- Before/after: a declined FP operand becomes `knownDoubleSink(Double(half(arg0)))` in the renderer's existing conversion syntax. The producer call must not disappear.
- Negatives: Half nominal aggregate, HFA, tuple, wrong bank, widened raw bits without numeric conversion and unknown producer precision.
- Mutations: remove Float16 admission; classify an aggregate as scalar; replace 16-bit producer width by consumer width. The first regression must reach the actual foreign whole-result gate.

### 9. L01-b: Seed a one-Float16 stored field

- Axis completeness. Size S. Confidence high. Dependencies none; L03-a before expanding multi-field half layouts.
- Rule: C/lib/IRGen/GenStruct.cpp:1036-1042 forwards a represented Half field from GenType.cpp:2471-2472.
- Change site: S/FieldMap.swift:253-271,309-339 and existing field width seed consumers. Support one Half field first, not arbitrary packed HFAs in this commit.
- Fixture sketch: `struct H { var h:Float16; func scaled(_ k:Float16)->Float16 { h*k } }; func read(_ h:H)->Float16 { h.h }`. All Swift levels.
- Before/after: unknown field becomes `arg0.h`/`self.h`, with h following the FP formal in its own bank.
- Negatives: two half fields sharing a chunk until their ordered proof exists, wrong field width, foreign/resilient H, packed SIMD and partial wider reads.
- Mutations: omit Half; assign GP bank; use 32-bit width; seed self before formal.

### 10. L01-c: Place Unicode.Scalar as its one narrow integer piece

- Axis completeness. Size S. Confidence high in frozen storage, medium in end-to-end value syntax. Dependencies none.
- Rule: C/stdlib/public/core/UnicodeScalar.swift:35-38 and GenStruct.cpp:1036-1042.
- Change sites: S/SwiftLowering.swift:85-108, scalar width/view queries and S/Disassembler.swift:8747-8770. Prove a UInt32 piece without importing an unrelated Unicode textual value.
- Fixture sketch: `func after(_ u:Unicode.Scalar,_ k:Int)->Int { k &* 17 }`; a second function returns `u.value`. All Swift levels.
- Before/after: following k goes from unknown to arg1 in x1. The scalar value may render only a proved 32-bit projection, never arbitrary high register bits.
- Negatives: Unicode.Scalar.UTF8View, invalid/unproven scalar bits, similarly named custom nominal, tuple of scalars.
- Mutations: retain `.direct` with no footprint; use two words; widen the value proof to 64 bits.

### 11. L01-d: Place Unmanaged without inventing ownership

- Axis completeness. Size S. Confidence high in storage, medium in physical oracle. Dependencies none.
- Rule: C/stdlib/public/core/Unmanaged.swift:17-24; GenStruct.cpp:1036-1042. One unsafe-unowned reference is storage, not a retain effect.
- Change sites: S/SwiftLowering.swift:99-112 and shared scalar classification.
- Fixture sketch: `final class Box {}; func after(_ u:Unmanaged<Box>,_ k:Int)->Int { k &+ 9 }`. Add a pointer roundtrip consumer without taking ownership. All Swift levels.
- Before/after: k becomes placed in x1 and renders `(arg1 + 9)`; no retain, release or pointee identity is synthesized.
- Negatives: nested `.Iterator`-style suffix, unknown reference representation, Optional<Unmanaged> until extra inhabitants are proved, foreign nominal with same spelling.
- Mutations: leave unshaped generic bucket; match a generic prefix rather than whole type; assign implicit ARC identity.

### 12. L01-e: Seed one typed pointer field in a direct struct

- Axis completeness. Size S/M. Confidence high. Dependencies none.
- Rule: C/lib/IRGen/GenType.cpp:2466-2468 and GenStruct.cpp:1036-1042.
- Change sites: S/FieldMap.swift:309-339 and typed width propagation; use structured/full generic type identity, not a loose prefix.
- Fixture sketch: `struct P { var p:UnsafePointer<Int> }; func read(_ p:P,_ k:Int)->Int { p.p.pointee &+ k }`. All Swift levels.
- Before/after: pointer field base becomes `arg0.p`; actual pointee content stays unknown absent a memory proof. Following k remains correctly placed.
- Negatives: weak/unowned storage protocols, pointer-like nested types, unknown pointee memory, a tuple/buffer pointer field and resilient P.
- Mutations: omit pointer admission; use a pointee value as pointer; preserve loaded pointee across an opaque writer.

### 13. L03-b: Seed nested single-field projections from ordered pieces

- Axis completeness. Size M. Confidence high in count/seed asymmetry. Dependencies L03-a.
- Rule: C/lib/IRGen/GenStruct.cpp:1036-1042 recursively adds each represented field at its byte offset.
- Change sites: S/SwiftLowering.swift:226-263 plus S/FieldMap.swift:309-339 and S/Disassembler.swift:7388-7396. Carry projection paths alongside offsets; do not add another recursive name whitelist.
- Fixture sketch: `struct Inner { var n:UInt64 }; struct Outer { var i:Inner }; func read(_ o:Outer,_ k:UInt64)->UInt64 { o.i.n &- k }`. Paired Double wrapper. All Swift levels.
- Before/after: `return ?` becomes `(arg0.i.n - arg1)`; support only the nested single-piece shape here.
- Negatives: recursive/unknown layout, trust-limited inner, resilient inner, two fields coalesced into one unknown word, class-valued nominal treated as storage.
- Mutations: discard path; add rather than compose offset incorrectly; count wrapper as an extra piece; ignore inner trust.

### 14. L02-b: Keep production empty-struct layout evidence

- Axis completeness. Size S/M. Confidence high in builder exclusion. Dependencies L02-a.
- Rule: empty field expansion at C/lib/IRGen/GenStruct.cpp:1036-1042 and empty schema behavior at GenCall.cpp:1862-1864.
- Change sites: S/FieldMap.swift:367-390, SwiftLowering.swift:212-215. Retain an explicit proved zero-sized struct record without fabricating empty ranges for an unknown layout.
- Fixture sketch: `struct Empty {}; func after(_ e:Empty,_ k:Int)->Int { k &+ 3 }`; include nested Empty field. All Swift levels.
- Before/after: current `take_Empty(?, ?)` behavior guarded at T/ABISourceLoweringTests.swift:664-666 becomes `take_Empty(?, 7)` only for proved Empty.
- Negatives: zero fields because metadata is absent, generic/resilient external type, omitted property reflection, empty class instance.
- Mutations: restore empty-map drop; turn any missing map into zero; consume a register; discard nominal identity.

### 15. L07-a: Project a one-field nominal direct result

- Axis completeness. Size M. Confidence high. Dependencies L03-a; use existing width proofs.
- Rule: C/lib/IRGen/GenCall.cpp:973-984,1092-1115 and NativeConventionSchema.h:55-76. One component can belong to a nominal result without being the whole scalar call expression.
- Change sites: S/Disassembler.swift:6764-6781, S/ValueTracking.swift:2377-2388 and a typed producer/projection fact. Keep the current stale-x0 guard.
- Fixture sketch: `struct D { var d:Double }; func make(_ x:Double)->D { D(d:x+0.5) }; func use(_ x:Double)->Double { make(x).d*2 }`. A one-UInt64 nominal is the GP counterpart, exercised before admitting that counterpart. All Swift levels.
- Before/after: unknown projection becomes `make(arg0).d * 2.0`, never `make(arg0) * 2.0`.
- Negatives: two components, mixed result, x8 result, stale pre-call GP, unavailable field map and call-ID mismatch.
- Mutations: erase projection; equate piece with whole call; read wrong bank; reuse a preceding call's result.

### 16. L08-a: Continue the other bank after one bank spills

- Axis completeness. Size M. Confidence high in shared suffix limitation; backend rule requires recheck. Dependencies L03-a and pinned backend allocation rule.
- Rule: independent GP/FP banks in C/docs/ABI/CallingConventionSummary.rst:131-173; exploded operands at GenCall.cpp:1866-1869. Re-read the actual Darwin allocator before admitting split composites.
- Change sites: S/Disassembler.swift:7771-7831 and :7285-7421. Track bank exhaustion separately from unknown shape. Preserve known source order even when an argument value is unknown.
- Fixture sketch: nine Ints then Double, and nine Doubles then Int; each callee returns the final other-bank scalar. All Swift levels.
- Before/after: currently unknown final scalar becomes its correct source argument, x0 or v0 as appropriate. Overflowing scalar itself can stay unknown until the stack sprint.
- Negatives: unknown type before the final scalar, HFA/composite exhaustion, ambiguous hidden outputs, unsupported convention.
- Mutations: restore shared `spilled`; advance wrong bank; erase unknown source positions.

### 17. L08-b: Read packed narrow outgoing parameters by byte interval

- Axis completeness. Size M. Confidence high. Dependencies M04-a, L08-a.
- Rule: C/docs/ABI/CallingConventionSummary.rst:211-212; scalar storage widths at GenType.cpp:2489-2498. Exact fixed-slot assignment must be pinned to LLVM.
- Change sites: S/Disassembler.swift:7874-7913, S/ValueTracking.swift:2523-2537 and typed frame-byte snapshots.
- Fixture sketch: eight Ints followed by `UInt8(0x12), UInt16(0x3456), UInt32(0x789abcde)` and an aligned Int. Callee writes each to independent observable sinks. All Swift levels.
- Before/after: packed arguments currently `?` become exact typed values at their actual offsets; a hole stays unknown without hiding the later aligned Int.
- Negatives: partial store, merged store that includes a neighbor without an exact byte projection, unknown alias store, save-area overlap, unreadable width.
- Mutations: round every fixed slot to eight; read the whole stored word as one formal; stop at a hole; accept an insufficient byte cover.

### 18. L08-c: Seed one incoming stack scalar from entry-SP coordinates

- Axis completeness. Size M. Confidence high in current overflow decline. Dependencies L08-a/b and exact frame coordinates.
- Rule: C/docs/ABI/CallingConventionSummary.rst:179-212 describes entry SP and packed incoming arguments.
- Change sites: S/Disassembler.swift:7285-7421, existing MethodEntryConvention and ValueTracer entry/frame seeding. Do not infer a scalar from a function's reload alone.
- Fixture sketch: ninth Int returned after a nonleaf call, with frame-pointer and frameless optimized variants. A second family uses packed narrow neighbors once the first scalar is qualified. All Swift levels.
- Before/after: `return ?` becomes `return arg8` for the admitted ninth Int. Callee-private saved-register reloads never become arguments.
- Negatives: unknown SP, incomplete prologue, own stored save slot, tail destination frame with different coordinates, unsupported hidden prefixes.
- Mutations: use current SP instead of entry SP; ignore writeback; treat own save as incoming; seed without signature/placement proof.

### 19. L08-d: Place a split two-word Swift String formal

- Axis completeness. Size M. Confidence medium pending backend oracle. Dependencies L03-a, L08-b/c.
- Rule: native exploded operands at C/lib/IRGen/GenCall.cpp:1866-1869. Splitting at x7 is a Swift lowered-piece decision, not C composite/HFA allocation.
- Change sites: S/Disassembler.swift:7815-7831 and SwiftArgumentLayout's StaticString-only `splitStackWords` exception. Replace that exception only for the qualified two-word String case.
- Fixture sketch: seven Ints, then String, then Int; consumer observes both String identity and final Int. Keep independently distinguishable source values. All Swift levels.
- Before/after: the String may remain opaque, but both pieces occupy their proven places and the following Int is recovered from the right stack offset.
- Negatives: one matching word only, words from different producers, C record of the same byte size, HFA, unknown String representation, tail stack mismatch.
- Mutations: spill both pieces; keep both in registers; skip only one wrong stack word; assemble two unrelated words.

### 20. L01-f: Place Int128 as a wide piece, not a scalar whitelist entry

- Axis completeness. Size M. Confidence high in storage, medium in target placement. Dependencies L03-a, L08-a/b and missing backend i128 rules.
- Rule: C/stdlib/public/core/Int128.swift:18-23 and UInt128.swift:18-23, plus GenType.cpp:2489-2498. A 128-bit integer cannot count as one 64-bit component or pointer.
- Change sites: ordered lowering and placement consumers; do not add Int128 to S/SwiftLowering.swift:85-98's one-integer set.
- Fixture sketch: `func after(_ n:UInt128,_ k:UInt64)->UInt64 { k &* 19 }`, plus seven GP prefixes before UInt128 and a trailing scalar. All Swift levels.
- Before/after: following k changes from unknown to correctly placed. Wide arithmetic reconstruction is outside this commit; n can remain opaque.
- Negatives: x7 boundary, stack alignment, signed/unsigned high half, unsupported target, foreign __int128 allocation unless independently qualified.
- Mutations: count i128 as one; put it in x7 alone; align a spilled pair to eight; swap high/low order.

### 21. L04-a: Place an ordinary labeled tuple formal by its SIL abstraction

- Axis completeness. Size M. Confidence high. Dependencies L03-a; introduce a structured type/source-group fact only as needed for this behavior.
- Rule: C/lib/SIL/IR/SILFunctionType.cpp:2169-2210 distinguishes tuple formal expansion from inout and Clang references.
- Change sites: S/Disassembler.swift:8667-8672,8753-8756,7285-7421 and :7659-7832. Replace last-colon parsing on this admitted path.
- Fixture sketch: `func f(_ t:(a:Int,b:Double),_ k:Int)->Int { t.a &- k }`, nested-label and unlabeled controls. All Swift levels.
- Before/after: tuple and following k currently decline; after, t.a and k have correct source indices and banks. Preserve one tuple source slot in rendered calls.
- Negatives: generic/reabstracted original type, inout tuple, C++ reference, tuple of closures, unknown specialization modifiers.
- Mutations: treat tuple as one struct budget; take text after nested colon; consume an address as tuple pieces; flatten source argument numbering.

### 22. L04-b: Flatten a tuple stored as one struct field

- Axis completeness. Size M. Confidence high in distinct compiler storage path. Dependencies L03-a/b, L04-a's structured type parsing only.
- Rule: C/lib/IRGen/GenTuple.cpp:276-282 and GenStruct.cpp:1036-1042 recursively compose storage offsets. This is not SIL formal tuple expansion.
- Change sites: ordered scalar collector and field projection paths, currently S/SwiftLowering.swift:226-263.
- Fixture sketch: `struct T { var pair:(Int,Double) }; func f(_ t:T,_ k:Int)->Int { t.pair.0 &+ k }`. All Swift levels.
- Before/after: unknown shape becomes known piece placement and `arg0.pair.0` when its exact component is observed.
- Negatives: unresolved tuple labels/type, resilient element, inout T transport, padding read, unknown element.
- Mutations: treat tuple field as a pointer; omit parent offset; confuse field projection index with source formal index.

### 23. L05-a: Admit a frozen cross-module value only with boundary evidence

- Axis completeness. Size M. Confidence high in conservative map, medium in artifact evidence availability. Dependencies L03-a.
- Rule: C/lib/IRGen/GenStruct.cpp:1241-1267,1404-1434 separates layout/accessibility; SILFunctionType.cpp:2185-2207 uses minimal convention versus actual expansion.
- Change sites: S/FieldMap.swift:383-390 and boundary-specific lowering context, not the memory-map trust flag alone.
- Fixture sketch: separately built evolution-enabled provider has `@frozen struct Fixed { let n:Int }` and nonfrozen SameSize. Client passes both to exported noinline functions. Rebuild provider with changed nonfrozen private layout. All Swift levels.
- Before/after: only artifact-proven frozen Fixed gains direct placement; nonfrozen external SameSize remains indirect or opaque. Equal storage size must not decide.
- Negatives: absent frozen/accessibility evidence, same-module optimized body mistaken for public ABI, stale provider, generic field.
- Mutations: infer frozen from small size; ignore provider/boundary; reuse local expansion at external call. If the binary lacks frozen evidence, record that row unsupported rather than guess.

### 24. L05-b: Place one ordinary indirect output beside a direct result

- Axis completeness. Size M. Confidence high. Dependencies ordered result roles from L03-a and generic original-abstraction proof supplied by the generics domain.
- Rule: C/lib/IRGen/GenCall.cpp:707-760,1113-1115. The nonempty direct result disables sret for associated indirect SIL outputs.
- Change sites: S/Disassembler.swift:7731-7734, S/IndirectResults.swift result-convention consumers and entry seeding. One source result group may consume x0 as a buffer while direct success returns separately.
- Fixture sketch: `@inline(never) func split<T>(_ t:T,_ k:Int)->(T,Int) { (t,k &+ 23) }`, independently compiled caller with T fixed to a known value. All Swift levels, no inlining across the boundary.
- Before/after: call/entry currently decline; after, t and k no longer alias the leading output buffer. Direct Int and the by-address T stay distinct.
- Negatives: unknown generic abstraction, two indirect outputs, typed-error buffer, async result, x8 used as ordinary data.
- Mutations: assign ordinary output to x8; omit its GP consumption; call direct result the whole tuple; initialize output on an inactive outcome.

### 25. L07-b: Keep two direct result projections tied to one call

- Axis completeness. Size M. Confidence high. Dependencies L07-a and ordered component schema.
- Rule: C/lib/IRGen/NativeConventionSchema.h:55-76 and GenCall.cpp:973-984.
- Change sites: S/ValueTracking.swift:2377-2388, typed component transport and render projection consumers.
- Fixture sketch: `struct Pair { var a:UInt64; var b:Double }; func make(_ n:UInt64)->Pair {...}; func use(_ n:UInt64)->Double { let p=make(n); return Double(p.a)+p.b }`. Use distinguishable component values, stack copies and a second producer. All Swift levels.
- Before/after: both projections currently unknown; after they render `make(...).a` and `.b` through one retained producer binding.
- Negatives: join mixing producer IDs, partial overwritten spill, missing one component, wrong outcome, callee not proven direct.
- Mutations: use whole-call value for one piece; substitute prior producer; merge disagreeing projection IDs; suppress producer effect after decline.

### 26. L06-b: Place Optional<Float16> payload and tag

- Axis completeness. Size S/M. Confidence high in omitted scalar payload list, medium in target coercion. Dependencies L03-a and explicit enum-layout proof.
- Rule: C/lib/IRGen/GenType.cpp:2471-2472 and GenEnum.cpp:1558-1574,2091-2107. Optional's native payload schema need not use the naked Half's FP bank.
- Change sites: S/Disassembler.swift:8014-8053 and ordered enum schema. Do not simply classify it as one FP scalar.
- Fixture sketch: `func take(_ h:Float16?,_ k:Int)->Int { h == nil ? k : k &+ 1 }`; caller sends nil and 1.5. All Swift levels.
- Before/after: following k and known tag become placed; only a proved `.some` payload is rendered.
- Negatives: unknown tag, NaN payload, nested Optional, inconsistent byte width, Half field mistaken for a Float.
- Mutations: use v0 for Optional payload; omit tag; treat unknown tag as some; advance two GP words regardless of actual schema.

### 27. L06-c: Decode one fixed single-payload enum's register tag

- Axis completeness. Size M. Confidence medium. Dependencies L03-a and exact enum storage evidence.
- Rule: C/lib/IRGen/GenEnum.cpp:1558-1574,1967-2042,2091-2107. Choose a bounded explicit-tag integer payload first.
- Change sites: PayloadEnumCaseIndex integration and ordered lowering/projection consumers, not no-payload EnumCaseIndex alone.
- Fixture sketch: `enum E { case value(UInt64); case absent }; func f(_ e:E,_ k:Int)->Int { switch e { case .value(let n): return Int(truncatingIfNeeded:n); case .absent:return k } }`. All Swift levels.
- Before/after: opaque payload/tag becomes the correct case and payload only on its matching branch. Following k stays correctly placed.
- Negatives: unknown tag, invalid tag, resilient E, indirect case, pointer/spare-bit near twin without independent schema.
- Mutations: use declaration-order index as raw tag; drop tag gate; project payload on absent path; use scalar Optional's footprint for every enum.

### 28. L06-d: Decode one two-payload enum's proven common tag bits

- Axis completeness. Size M. Confidence medium. Dependencies L06-c and separately verified multi-payload strategy.
- Rule: C/lib/IRGen/GenEnum.cpp:31-91 describes distinct strategies; payload expansion remains :1558-1574. Re-read the exact multi-payload tag calculation for the chosen fixture before implementation.
- Change sites: enum storage schema and case-aware component projection consumers.
- Fixture sketch: `enum E { case a(UInt64); case b(UInt64); case empty }`, each case returns a different observable scalar in a noinline switch. All Swift levels.
- Before/after: unknown case becomes the exact case only when all required tag bits are known; no pointer-spare-bit generalization in this commit.
- Negatives: mixed reference payload, unknown spare bits, oversized/indirect payload, resilient E, discriminator from another enum.
- Mutations: equate payload with discriminant; swap two case tags; retain payload after a case join; omit excess tag byte.

### 29. L09-a: Place one Swift SIMD2<Float> without scalarizing it

- Axis completeness. Size M. Confidence medium pending Clang legalization. Dependencies L03-a, M03-a's needed slice coverage and backend rule.
- Rule: C/lib/IRGen/GenType.cpp:2500-2516 plus GenCall.cpp:957-984. Swift storage and target-legal vector transport are separate steps.
- Change sites: ordered shape/placement and vector-valued projection facts. Do not put SIMD in scalar `floats`.
- Fixture sketch: `func f(_ v:SIMD2<Float>,_ k:Int)->Int { k &+ Int(v[1]) }`. Distinct lane values, call and result pass-through. All Swift levels.
- Before/after: following scalar is placed; a proved vector lane may render `arg0[1]`. Never render v as a scalar Float result.
- Negatives: unknown lane, scalar write covering only part of a vector, SIMD8, mixed C HVA, unsupported scalable vector.
- Mutations: count two scalar FP arguments; treat one lane as whole vector; reuse unknown upper bits; swap lane index.

### 30. L09-b: Keep SIMD3 padding outside source value lanes

- Axis completeness. Size M. Confidence medium. Dependencies L09-a and exact SIMD3 storage oracle.
- Rule: C/lib/IRGen/GenType.cpp:2512-2516 rounds vector storage. The scalar lane count remains three.
- Change sites: vector lane/byte schema, spill and result component coverage.
- Fixture sketch: `struct V { var v:SIMD3<Float> }; func f(_ v:V)->Float { v.v[2] }`; observe a copied/spilled result with nonzero adjacent storage. All Swift levels.
- Before/after: a proved third lane becomes accessible; padding stays absent/unknown, never a fourth source field.
- Negatives: wider load containing unrelated bytes, overwritten lane, incomplete Q value after call, SIMD4 near twin.
- Mutations: infer four lanes from 16 bytes; fill padding with stale register state; ignore spill width.

### 31. L10-a: Place one foreign small GP record with structured provenance

- Axis completeness. Size M. Confidence medium until Clang AArch64 source is available. Dependencies target allocator and fixed prototype provenance.
- Rule: C/lib/IRGen/GenCall.cpp:1633-1644,1712-1719 delegates/coerces foreign arguments. This is not Swift's four-component rule.
- Change sites: S/Pseudo.swift:1177-1211, SDK prototype generation and S/Disassembler.swift:7935-7956. Reuse S/ObjCArgumentABI.swift:120-142 where rules match.
- Fixture sketch: C `struct P { uint64_t a,b; }; long f(struct P p,long k) { return p.a-k*p.b; }`, with Swift imported caller and separate C body. All C/Swift levels.
- Before/after: known following k is placed after the coerced record; record may remain opaque until its pieces have proven identity.
- Negatives: packed record, union, bitfield, opaque declaration, unsupported alignment, wrong provider, same-name local function.
- Mutations: use Swift aggregate budget; count record as one x register; drop declaration/provider; infer shape from prototype name.

### 32. L10-b: Preserve foreign HFA whole-group exhaustion

- Axis completeness. Size M. Confidence high in existing ObjC rule, medium in C extension. Dependencies L10-a, L08-b.
- Rule: C/lib/IRGen/GenCall.cpp:1633-1644 delegates to Clang; exact HFA whole-group rule needs missing AArch64 classifier. Existing S/ObjCArgumentABI.swift:109-119 is the behavior to preserve, not replace with Swift piece splitting.
- Change sites: shared foreign placement interpreter and S/Disassembler.swift:7935-7956.
- Fixture sketch: C takes seven Doubles, then `struct H{double a,b;}`, then Int and Double. Each field/formal feeds an independent sink. All C/Swift levels.
- Before/after: later Int remains in GP bank and HFA is entirely stack-placed; its final Double stays stack-placed under the verified foreign FP exhaustion rule.
- Negatives: Swift struct with independently exploded pieces, heterogeneous record, missing prototype, HVA without explicit vector schema.
- Mutations: split HFA at v7; allow final Double into a supposedly freed v register; spill GP merely because FP spilled.

### 33. L11-a: Start Darwin unnamed arguments after named stack extent

- Axis completeness. Size M. Confidence medium, backend/promotion source still required. Dependencies L10-a/b and byte stack layout.
- Rule: foreign arrangement at C/lib/IRGen/GenCall.cpp:1633-1644. Fixed packed stack versus unnamed tail assignment must be reverified in LLVM before admission.
- Change sites: S/Disassembler.swift:10587-10649 and structured foreign declaration/variadic evidence. Format or declaration proof must establish the tail's types/count.
- Fixture sketch: C `void collect(long a0,... eight more named longs ..., const char *fmt,...);` called with named overflow, then promoted int and double. C body records each named and variadic value with va_arg. Pair plain `printf`, Swift `Int...`, and va_list forwarding. All levels.
- Before/after: unsupported call becomes a correctly placed fixed prefix and known promoted tail. First unnamed value is never the ninth named argument.
- Negatives: invalid/unreadable format, unknown va_list contents, arbitrary nonformat tail, missing declaration, insufficient bytes, sentinel after unknown extent.
- Mutations: start unnamed tail at stack zero; omit float/integer promotion; use stale GP registers for unnamed values; treat Swift Array varargs as Darwin C tail.

### 34. M02-b: Give a proven coroutine role its own input reach

- Axis soundness. Size M. Confidence medium pending backend x23 mapping. Dependencies M02-a's role-aware contract, local/pinned SwiftCoro fixture.
- Rule: C/lib/IRGen/GenCall.cpp:516-519,910-954 and IRGenModule.cpp:583-588 keep SwiftCoro operands distinct. Backend x23 assignment is not locally available.
- Change sites: S/CalleeRegisterSummary.swift:2112 and per-edge reach/define contracts. Never extend async x22 semantics by analogy.
- Fixture sketch: Swift `_modify` accessor yielding an inout value, retaining its ramp/resume SIL. If selected compiler uses a different coroutine family, author the smallest valid SIL/IR carrying SwiftCoro and an address to observable storage. All supported optimization levels, explicit unsupported rows otherwise.
- Before/after: unaccounted coroutine-held alias must invalidate affected storage rather than preserve it. No new high-level coroutine reconstruction.
- Negatives: ordinary call where x23 holds a private callee-save, legacy coroutine without that attributed role, unresolved convention, unknown pointer bits.
- Mutations: remove role input; substitute x22; preserve a role defined by the callee; infer role from register read alone.

### 35. M03-a: Preserve a proved low SIMD slice across an upper-lane-only write

- Axis completeness. Size M. Confidence medium. Dependencies exact machine-slice oracle, not a type-name change.
- Rule: C/docs/ABI/CallingConventionSummary.rst:172-173 proves low-64 default preservation. Lane write identity needs ISA/native evidence beyond Swift source.
- Change sites: S/CalleeRegisterSummary.swift preservation write keys and S/ValueTracking.swift:5271-5290; existing whole-Q upper invalidation must remain.
- Fixture sketch: authored arm64 callee changes only `v8.d[1]`; caller stores distinct low/high halves, calls, and reads d8 and q8 separately. A Swift noinline wrapper observes the low Double and a raw C/assembly oracle observes both halves. All optimization modes preserving the authored boundary.
- Before/after: low-word result can recover; whole-Q result remains partially unknown unless the actual upper write is modeled. Do not restore zero upper bits from a prior scalar write.
- Negatives: low-lane write, unknown lane index, full Q write, vector PCS without selected mask, unsupported scalable instruction.
- Mutations: mark any lane write as whole-register clobber; retain full Q on default call; assume a lane index or write width. Separate assertions kill precision loss and unsound retention.

### 36. M05-a: Prove one additional complete framed forwarding shape

- Axis completeness. Size M. Confidence medium. Dependencies none. First demonstrate it is actually declined by complete-body summaries.
- Rule: C/docs/ABI/CallingConventionSummary.rst:179-212 specifies coordinates. Exact outlined/frame transformations must be read in pinned LLVM before broadening a recognizer.
- Change sites: S/CalleeRegisterSummary.swift:962-988 and shared frame-coordinate/return-origin proof. Avoid a name-based `OUTLINED_FUNCTION` shortcut.
- Fixture sketch: noinline C forwarding wrapper with frame-pointer omission and a preserved alternate LR register, emitted at -Os or authored as conforming assembly. Swift wrapper observes the forwarded scalar. Record full helper extent independently.
- Before/after: if baseline declines the complete shape, result/preservation follows only the exact proved target/frame transformation. If complete-body analysis already handles it, close this proposed sprint without a code commit.
- Negatives: incomplete helper, changed saved LR, different SP restoration, unknown stack write, out-of-body branch not proven an entry.
- Mutations: omit LR origin; omit SP relation; accept incomplete prefix; assume conventional inputs. Existing stack-probe invalidate lists already agree and must not be refactored here.

### 37. M06-a: Keep coroutine partial return distinct from function completion

- Axis soundness. Size M. Confidence medium. Dependencies a real emitted SwiftCoro/legacy coroutine partial-return oracle and M02-b's role selection.
- Rule: C/lib/IRGen/GenCall.cpp:694-698 and :5054-5067 distinguishes coroutine results/resumptions; IRGenModule.cpp:583-588 selects the machine convention. RET_POPLESS lowering must be verified in missing LLVM.
- Change sites: typed exit classification between CFG, S/CalleeRegisterSummary.swift:1580-1612 and source return rendering.
- Fixture sketch: `_modify` accessor plus an early normal return control; retain ramp, yield and resume machine entries. Use compiler SIL if source emits another family. All supported optimization levels.
- Before/after: a yield/partial completion, if currently treated as a source return, stays an explicit yield/unresolved transfer. Do not claim a wrong result before the baseline demonstrates it.
- Negatives: true sibling tail, ordinary ret, noreturn tail, async hop, unknown endpoint and same branch family with different entry contract.
- Mutations: collapse all return opcodes into normal completion; inherit ramp result at resume; ignore endpoint kind or SP relation.

### 38. M07-b: Require a matching authenticated return token

- Axis soundness. Size M. Confidence medium. Dependencies M07-a and pinned return-signing/backend oracle.
- Rule: distinct authentication categories are read-verified at C/include/swift/ABI/MetadataValues.h:1697-1816. The actual PACIASP/PACIBSP/RETAA/B key and modifier rule is external to Swift IRGen and must be sourced before implementation.
- Change sites: S/CalleeRegisterSummary.swift:1555-1612. Track incoming return identity separately from signing key and SP modifier.
- Fixture sketch: static arm64e framed function with matched signing/return pair; key-swapped and SP-modifier-swapped variants. A plain arm64 native sentinel is the non-PAC control. Do not execute invalid PAC variants.
- Before/after: RETAA/B alone no longer proves a valid return-origin/preservation edge. Matching signed token retains the bounded proof.
- Negatives: plain ret x30, alternate return register, stripped authentication not restored, overwritten LR, sign at a different SP.
- Mutations: accept any RETAA/B; ignore key; ignore modifier; reuse token after LR overwrite. Keep name/CFG classification separate from callable proof.

### 39. M08-a: Intersect effects across a backdeployment alternative

- Axis soundness. Size M. Confidence medium in current reachable defect; high in compiler alternatives. Dependencies typed endpoint identity and target availability evidence.
- Rule: C/lib/SILGen/SILGenAvailability.cpp:324-349,352-433 emits original/fallback choices and forwards separate output/isolation roles.
- Change sites: exact-body summary admission and runtime reference consumers; S/RuntimeFunctionReference.swift:57-81 alone is not a feasible-target proof.
- Fixture sketch: an `@backDeployed` function and its separately built client, with original and fallback producing distinct observable memory effects. Build at two deployment minima; all Swift levels.
- Before/after: no body-specific preservation survives unless common to all feasible endpoints or the branch is artifact-proven. A declared common ABI may remain.
- Negatives: unknown OS availability, weak endpoint, flat/resolver import, same-name provider impostor, direct exact local body.
- Mutations: select first alternative; use host OS instead of artifact facts; transfer one endpoint's readonly contract to the other.

### 40. M08-b: Expire exact-body effects at a replacement chain

- Axis soundness. Size M. Confidence medium. Dependencies typed endpoint alternatives; coordinate with U01 rather than duplicate it.
- Rule: C/lib/IRGen/GenDecl.cpp:1892-1931 signs a mutable replacement-chain function pointer by entry family.
- Change sites: local callee summary admission, replacement endpoint resolver and runtime effect application. A source declaration remains different from its installed implementation.
- Fixture sketch: dynamic function returns/updates a sentinel, replacement changes the update, prior-implementation call has a distinct log. Separate dylibs, all Swift levels; keep mangling/SIL and link-entry evidence.
- Before/after: potentially stale exact-body result/memory refinements become unknown at an unresolved replacement chain, while the declared argument ABI stays available.
- Negatives: direct private nonreplaceable body, unknown chain generation, multiple possible replacements, async/coro families not yet qualified.
- Mutations: reuse original body after chain change; conflate prior with current; drop generation/endpoint check. If a complete thunk summary already declines, add the exact missing regression only after reproduction.

### 41. M10-a: Select one target-dependent effect from artifact facts

- Axis soundness. Size M. Confidence medium. Dependencies typed boundary target key; do not block established arm64 behavior merely because compiler version is absent.
- Rule: C/lib/IRGen/IRGenModule.cpp:2517-2518 and TBDGen.cpp:634 separate ABI version; SILGenAvailability.cpp:324-349 selects by deployment and expansion.
- Change sites: target/deployment fact supplied from BinaryLoader/MachOPreflight into one chosen runtime/frame contract. Missing facts remain unknown. Start with one concrete version-dependent contract backed by a fixture, not a generic version database.
- Fixture sketch: same source at two deployment minima retains an availability-selected thunk with different endpoint/frame evidence. Compare Mach-O minimum OS, actual lowering and native sentinels where executable. All Swift levels.
- Before/after: an affected effect is admitted only under the proved artifact envelope; unsupported slice or unknown prerequisite declines that effect. Names and other established baseline ABI facts remain usable.
- Negatives: no build-version command, compiler-version string mistaken for ABI, unsupported CPU subtype, unknown runtime provider and host deployment substituted for input deployment.
- Mutations: ignore minimum OS; reuse one target's contract for another; infer compiler version from ABI version; fill missing facts with host defaults.

## Deferred subcases and why they are not another sprint yet

- Imported integer-enum result recovery needs the exact builtin width exposed from EnumCaseIndex, plus result-bit proof. The parameter-only asymmetry is verified. No baseline projection witness was executed, so queue this immediately after L01-a if that probe fails.
- Character, Substring and buffer-pointer transport need exact multiword shapes. Character's missing footprint is clear, but one sprint should admit only Character's two-word placement after the ordered schema exists. Proposed follow-on `L01-g`: `func after(_ c:Character,_ k:Int)->Int { k &+ 5 }`, paired small/large graphemes at all three levels, should change only the following scalar from unknown to arg1. Mutate word count/source slot and keep unknown Character payload bits declining. Size S, completeness, high storage/medium witness confidence, depends L03-a/L08-a. This is not String-literal recovery.
- C direct/sret aggregate results require the foreign result schema, separate from L10-a argument placement. Proposed `L10-c`: C `struct P make(long x)` and Swift caller consuming each field; before unknown, after exact projections or a proven sret buffer, never x0 as whole record. Negatives include HFA versus GP results, unknown prototype and same-name provider. Mutations swap result bank, ordinary output with x8, and producer identity. Size M, completeness, depends L07-a/b and L10-a, medium confidence pending missing Clang source.
- Foreign HVA, unions, bitfields, over-aligned records, callbacks, blocks and objc_direct need separately admitted declaration shapes. Keep explicit declines. They are not safely closed by compact SDK codes or an Objective-C encoding alone.
- x15 nest, uncommon preserve attributes, scalable vectors and custom conventions need the pinned backend and an artifact-level admission story. Their absence is not permission to label every opaque call with those conventions.
- General multiword reconstruction, multiple indirect outputs and typed-error outcome maps belong with the neighboring generics/error sprints. L05-b must not silently expand to them.
- M09 does not justify a generic "rewrite integer semantics" sprint. Existing BFI, W/X and narrow-FP rules are already implemented. New scalar/vector shapes must carry width mutation controls into those existing paths. A freshly reproduced missing opcode should become its own commit.

## Suggested landing sequence and shared-file discipline

The numbered sequence is the recommendation, with soundness guards first and common scalar/struct gaps next. Later M02/M07/M08 soundness work needs evidence unavailable in this read-only session. Promote a reproduced wrong-output witness ahead of any completeness sprint regardless of its current number. In particular, an executable historical-pointer publication witness outranks a new nominal-field projection.

Do not make "shared ABI architecture" a prerequisite mega-commit. L03-a can introduce a small internal ordered-piece record used for its one proof. Each later sprint can add one role or projection it actually consumes. Preserve separate source slot, formal abstraction, physical location and value identity. Refactor duplicate consumers only in its own independently gated commit when behavior is unchanged.

The current ca9eef5 regression family is a required control for all field-seed work. Its commit record reports a three-test red under removal of the resolved spellings and a reviewed corpus delta. I read that engineering record; I did not rerun it. Do not count the 17 unrelated async WIP tests as part of the committed slice.

## Current wrong-output candidates that jump the queue

**No new wrong render was reproduced in this research session.** Running binaries was prohibited. These are the strongest inferred candidates, with the precise missing premise and a reproduction plan.

1. **M04: missed outgoing pointer leaves stale memory.** The escape loop at S/ValueTracking.swift:2206-2212 stops at a hole and at sixteen slots. An opaque callee can legally receive a pointer later in the outgoing area and mutate its pointee. If no other alias invalidation catches it, a pre-call scalar could survive incorrectly. Independent oracle: C callee writes 11, caller initialized 7, with pointer after a gap or at stack word 17. This is a potential soundness defect, not just an omitted argument.
2. **M02: hidden context omitted from opaque-edge reach.** S/CalleeRegisterSummary.swift:2112 excludes x22/x23 and :2077-2083 makes an overbroad no-stack-address assertion for x22. Direct-body x22 handling exists, so the witness must use an actual attributed unknown/imported edge. If that context aliases caller-owned bytes, preserved facts could be stale. Async and coroutine roles require separate witnesses.
3. **L06: unbounded Optional direct claim excludes a real buffer.** S/SwiftLowering.swift:54-55 recursively promotes every direct payload; S/IndirectResults.swift:243 consumes that claim. Sufficient tag growth can exceed direct transport. The test must first find a compiler-emitted depth crossing the boundary; ordinary nested pointer Optional is not automatically a bad case.
4. **L03: unordered coalescing can shift later roles.** S/SwiftLowering.swift:217-263 merges integer fragments on both sides of a Half FP barrier. Once independently confirmed against the actual Clang classifier, a trailing scalar or a direct/indirect threshold could expose wrong seeds. The closure plan says the previously tested root example declined. Do not relabel that historical decline as observed wrong output.
5. **M01: wrong default preserve mask.** S/ValueTracking.swift:2288-2309 and S/CalleeRegisterSummary.swift:2100-2104 retain default callee-saves. A proved weaker convention could legally change those values. It remains unverified whether current artifact recognition admits such an edge with enough facts to render a wrong value.
6. **M07: authenticated candidate treated as invocation.** RuntimeFunctionReference.swift:13-37 and CalleeRegisterSummary.swift:1592-1595 do not prove key/modifier compatibility. If an authenticated branch/return licenses runtime effects or completion without that proof, output could falsely describe a successful call/return. A known symbol alone is not wrong. Static PAC mismatch evidence is required; invalid PAC variants must not be executed.

The Float16, pointer-field, nested-field, Unicode.Scalar, Character and Int128 omissions are completeness gaps under the current inspected guards. I found no basis to call them wrong-value bugs. The narrow `wordIntegerFieldOffsetsInRegisters` whitelist is not itself a remaining ordinary UInt64 bug because the newly fixed mixed path covers those structs.

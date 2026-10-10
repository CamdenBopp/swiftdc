# The Swift native calling convention on arm64, from IRGen source

Mined from `/Users/camden/swift` (read-only) to ground swiftdc's self/error
register tracking and argument recovery in the actual ABI, not heuristics.
Every claim below carries a `file:line` citation into that checkout. Where the
checkout doesn't settle a question — most notably the exact numeric threshold
for direct-vs-indirect aggregate passing, which lives in clang, not this repo —
that is stated explicitly rather than filled in with a plausible number.

Per the authority hierarchy in the project's `CLAUDE.md`: this document is
research documentation (rank 4). It is a record of what the swiftlang/swift
checkout said on 2026-09-08. Verify against swiftdc's own tests (rank 1) and
`git log -S` in the swift checkout (rank 2) before trusting a claim here in a
dispute.

## Scope

- Target: arm64 (Apple platforms), the Swift **native** calling convention
  (`swiftcc`), not the C/ObjC-matching convention IRGen also emits for `@objc`
  and `@_cdecl` functions.
- Source consulted: `docs/ABI/CallingConvention.rst`,
  `docs/ABI/CallingConventionSummary.rst`, `docs/ABIStabilityManifesto.md`,
  `lib/IRGen/GenCall.cpp`, `GenFunc.cpp`, `GenProto.cpp`, `GenStruct.cpp`,
  `GenTuple.cpp`, `GenEnum.cpp`, `GenHeap.cpp`, `NativeConventionSchema.h`,
  `Signature.h`, `TypeInfo.h`, `include/swift/AST/Types.h` (`ParameterConvention`),
  `include/swift/SIL/SILDeclRef.h`, `include/swift/Runtime/RuntimeFunctions.def`.
- **Not in this checkout**: the actual aggregate-classification algorithm
  (`clang::CodeGen::swiftcall::SwiftAggLowering`, declared in
  `clang/CodeGen/SwiftCallingConv.h` and included by
  `lib/IRGen/NativeConventionSchema.h:20`) lives in the clang/LLVM monorepo,
  which is not vendored here and was not searched. Every claim below that
  depends on it (§2, "when does a struct go indirect") is bounded by what
  Swift's call sites *do* with the answer, not by the classification logic
  itself. Don't invent a numeric byte/register cutoff and attribute it to this
  checkout.

## 1. Register roles on arm64

`docs/ABI/CallingConventionSummary.rst:128-174` is a literal register table,
current at HEAD. It is the single most load-bearing citation in this document:

| Register | Swift role | C++/ObjC role |
|---|---|---|
| `x0` | integer arg 1 / 1st return value | `this` / `self` |
| `x1` | integer arg 2 / 2nd return value | `_cmd` |
| `x2`–`x7` | integer args 3–8 / 3rd–8th return values | — |
| `x8` | indirect result location register | — |
| `x20` | **`self`** (callee-saved) | ordinary callee-saved |
| `x21` | **error return** (callee-saved) | ordinary callee-saved |
| `x22` | **async context** (callee-saved) | ordinary callee-saved |
| `x23`–`x28` | ordinary callee-saved | ordinary callee-saved |
| `v0`–`v7` | FP/SIMD args 1–8, also return | — |
| `v8`–`v15` | callee-saved (low 64 bits only) | — |

(`docs/ABI/CallingConventionSummary.rst:131-174`)

This is exactly swiftdc's existing model
(`Sources/SwiftDecompilerCore/ValueTracking.swift:238-244`: x20 = self, x21 =
error, x8 = indirect result) — this mining confirms it against the primary
source rather than introducing anything new. Two things worth stating
precisely because swiftdc's code comments already lean on them correctly:

- **x20/x21/x22 are ordinary callee-saved registers at the hardware level.**
  Swift's convention is "roughly the same categorization of registers as the
  standard calling convention" with "additional **situational** uses of some
  callee-saved registers"
  (`docs/ABIStabilityManifesto.md:322`). A non-Swift callee, or a Swift
  function with no `self`/error/async need, leaves x20/x21/x22 as plain
  callee-saved scratch — which is exactly why `ValueTracking.swift:238-240`'s
  comment says x20 is "meaningless for a non-Swift callee" and why
  `MethodEntryConvention` (`ValueTracking.swift:194-227`) only seeds x20 under
  a proven Swift-instance-method entry, never unconditionally.
- **The role is assigned by an LLVM parameter attribute, not by argument-list
  position.** IRGen marks the LLVM IR parameter that should become x20/x21/x22
  with `llvm::Attribute::SwiftSelf` / `SwiftError` / `SwiftAsync`
  (`lib/IRGen/GenCall.cpp:509-514` `addSwiftSelfAttributes`,
  `:516-521` `addSwiftCoroAttributes`, `:523-534` `addSwiftErrorAttributes`,
  `:502-507` `addSwiftAsyncContextAttributes`). The LLVM AArch64 backend is
  what turns that attribute into "goes in x20/x21/x22 regardless of where it
  sits in the IR parameter list" — that backend behavior is standard LLVM
  ABI lowering and is not itself Swift source, so it isn't separately cited
  here, but `CallingConventionSummary.rst`'s table is the doc that states the
  *result* of it.

The C ABI comparison in the same table (`this`/`self` in x0, `_cmd` in x1 for
C++/ObjC) is what backs swiftdc's separate `MethodEntryConvention.objectiveC`
case (`ValueTracking.swift:201-203`) — a genuinely different register set from
the Swift case, not a variant of it.

## 2. Aggregate lowering: `NativeConventionSchema` / the "explosion"

### The type

`NativeConventionSchema` (`lib/IRGen/NativeConventionSchema.h:31-84`) wraps a
`SwiftAggLowering` (clang, out-of-tree — see Scope) and one bit,
`RequiresIndirect`. Constructed once per (type, isResult) pair and cached on
the `TypeInfo` (`lib/IRGen/TypeInfo.h:564-567`,
`lib/IRGen/GenType.cpp:366-378`).

Construction (`lib/IRGen/GenCall.cpp:957-971`):

```cpp
NativeConventionSchema::NativeConventionSchema(IRGenModule &IGM,
                                               const TypeInfo *ti,
                                               bool IsResult)
    : Lowering(IGM.ClangCodeGen->CGM()) {
  if (auto *loadable = dyn_cast<LoadableTypeInfo>(ti)) {
    loadable->addToAggLowering(IGM, Lowering, Size(0));
    Lowering.finish();
    RequiresIndirect = Lowering.shouldPassIndirectly(IsResult);
  } else {
    Lowering.finish();
    RequiresIndirect = true;
  }
}
```

Two decision points here, both important for a decompiler:

1. **Non-`LoadableTypeInfo` (address-only) types are unconditionally
   indirect** — no aggregate classification even runs
   (`GenCall.cpp:967-970`, the `else` branch). This is the concrete trigger
   for "resilient type, generic-dependent layout, or a type containing a weak
   reference always goes through a hidden pointer," matching
   `docs/ABI/CallingConvention.rst:766-803`'s description of inherently and
   contingently address-only types.
2. **Loadable types get classified by `shouldPassIndirectly(IsResult)`**,
   which this checkout does not contain the body of (see Scope). Swift's own
   call sites treat its answer as authoritative and binary — there is no
   partial/hybrid direct-plus-indirect split for a single value.

### Flattening — tuples, structs, single-field collapse

`addToAggLowering` is a virtual `LoadableTypeInfo` method
(`lib/IRGen/LoadableTypeInfo.h:172-174`) that every aggregate `TypeInfo`
overrides by delegating to its fields', at the field's byte offset — this is
the literal implementation of the whitepaper's "typed layout" merge
(`docs/ABI/CallingConvention.rst:893-919`):

- **Struct**: `LoadableStructTypeInfo::addToAggLowering`
  (`lib/IRGen/GenStruct.cpp:1036-1043`) loops fields and recurses.
- **Tuple**: identical shape, `lib/IRGen/GenTuple.cpp:276-283`.
- **Two-field scalar pair** (e.g. `(Int, Int)`-shaped types with a dedicated
  `ScalarPairTypeInfo`, used for things like `String`'s two-word
  representation): `lib/IRGen/ScalarPairTypeInfo.h:66-74` adds each element
  individually at its own offset — this is what makes a two-word type land in
  exactly two registers rather than one merged blob.
- **Single-field struct wrapping one scalar** (a `RawRepresentable` newtype,
  a phantom wrapper, etc.): `SingleScalarTypeInfo::addToAggLowering`
  (`lib/IRGen/ScalarTypeInfo.h:224-231`) adds *one* scalar at the struct's own
  offset. At the ABI level this genuinely collapses to indistinguishable from
  the wrapped scalar type — a decompiler cannot tell `struct Meters { let v:
  Double }` from a bare `Double` parameter by register occupancy alone.
- **Single-payload-case enum with no other cases needing a discriminator**
  (`SingleCaseEnum`-style layout): `lib/IRGen/GenEnum.cpp:535-539` passes
  through to the payload's own `addToAggLowering` when a "loadable singleton"
  exists — the same collapse as the single-field struct.
- **General enum** (payload + discriminator bits): four more
  `addToAggLowering` overrides for the different enum layout strategies
  (`GenEnum.cpp:1118`, `:1558`, `:6342`, `:6895-6897`), all ultimately merging
  payload and discriminator ranges per the whitepaper's opaque/legal-type
  merge algorithm (`docs/ABI/CallingConvention.rst:920-993`).

### Direct-vs-indirect is a dynamic decision, illustrated concretely

The coroutine-yield result path shows the algorithm's shape even though its
numeric threshold isn't in this repo. `SignatureExpansion::expandCoroutineResult`
(`lib/IRGen/GenCall.cpp:818-889`) greedily strips the *last* legal-type
component and re-tries `shouldPassIndirectly` until it's satisfied:

```cpp
while (clang::CodeGen::swiftcall::
              shouldPassIndirectly(IGM.ClangCodeGen->CGM(), components,
                                   /*asReturnValue*/ true)) {
  if (!overflowTypes.empty()) components.pop_back();
  overflowTypes.push_back(components.pop_back_val());
  --numDirectComponents;
  components.push_back(IGM.Int8PtrTy);
}
```
(`GenCall.cpp:874-887`)

So: a struct too large to return directly doesn't uniformly go indirect —
IRGen keeps as many leading components direct as fit and spills only the
overflow through one trailing pointer. **A decompiler must not assume "returns
a struct too big for registers" implies "the whole struct comes back through
x8"**; it may be a partial direct/indirect split. `docs/ABI/CallingConvention.rst:1230-1245`
states the target policy in prose (roughly 4 registers / 32 bytes as of when
that whitepaper was written, itself flagged `:orphan:` and "at least as we
want it to be", `CallingConvention.rst:10-11`) — treat that number as
descriptive intent, not a value this checkout lets you verify against the
compiled behavior.

## 3. Direct vs. indirect returns; out-parameters

`SignatureExpansion::expandDirectResult` (`lib/IRGen/GenCall.cpp:1092-1120`)
is the whole decision:

```cpp
auto &native = ti.nativeReturnValueSchema(IGM);
if (native.requiresIndirect())
  return std::make_pair(addIndirectResult(resultType), nullptr);
if (!native.empty()) CanUseSRet = false;
return std::make_pair(native.getExpandedType(IGM), &ti);
```

`addIndirectResult` (`GenCall.cpp:675-683`) adds a `noalias` pointer parameter
carrying the `sret` attribute when allowed
(`addIndirectResultAttributes`, `GenCall.cpp:406-425`) — this is the x8 slot
per the register table (§1). `native.getExpandedType`
(`GenCall.cpp:973-985`) is a single legal type, or an LLVM struct of them,
which the backend places across x0.../v0... in order.

Note `CanUseSRet = false` when there *is* a non-trivial direct result
(`GenCall.cpp:1114`): the `sret`/x8 pointer attribute is only actually usable
for the zero-or-indirect cases; a function can't simultaneously use x8 for one
purpose and return direct values in x0. Relevant if a decompiler is trying to
decide whether an observed x8 write before a call is a real indirect-result
setup or an unrelated pointer argument that happens to be in x8 (AAPCS64's x8
is not otherwise special except as the Swift indirect-result register too —
same role in both conventions, per `CallingConventionSummary.rst:140-142`).

**Typed throws** (`func f() throws(MyError) -> T`) can pack the error into
the *same* direct-result registers as the success value, when both are small
enough. `combineResultAndTypedErrorType` (`GenCall.cpp:430-490`) interleaves
the two legal-type sequences component-by-component, widening an integer slot
to fit whichever of (result, error) is bigger at that position
(`GenCall.cpp:467-473`). This is invoked from
`expandParameters`/error-result setup at `GenCall.cpp:2207-2231`: **when the
function has a typed error and both the success and error schemas are direct,
no extra opaque error pointer is added at all** — contrast with the untyped
`throws` case, which always reserves the swifterror/x21 slot
(`GenCall.cpp:2101-2124`). See §6 for what this means for a decompiler reading
x21.

## 4. Ownership: `@owned` / `@guaranteed` and what a decompiler sees around calls

`ParameterConvention` (`include/swift/AST/Types.h:4521-4580`) is the SIL-level
enum with doc comments spelling out the three static conventions the
whitepaper discusses (`docs/ABI/CallingConvention.rst:269-331`):

- `Direct_Owned` (`Types.h:4553-4555`) — callee destroys; caller transfers a
  live reference.
- `Direct_Guaranteed` (`Types.h:4562-4564`) — caller keeps it valid for the
  call's duration; callee does not retain/release it.
- `Direct_Unowned` (`Types.h:4557-4560`) — trivial or the callee simply isn't
  responsible.
- Indirect equivalents (`Indirect_In`, `Indirect_In_Guaranteed`,
  `Indirect_Inout`, …, `Types.h:4522-4551`) — same ownership semantics, but
  the value is an address rather than register contents.

`self` is the canonical `guaranteed` case
(`docs/ABI/CallingConvention.rst:354-363`): "It's quite common for clients ...
to call multiple methods on a single value... And it's relatively uncommon
... for a non-mutating method ... to suddenly store `self` aside." Ordinary
parameters default to `owned`
(`CallingConvention.rst:365-374`) specifically to make copy-on-write transfers
free of extra retain traffic.

**What a decompiler actually observes**: ownership convention is not encoded
in a register or an instruction bit — it governs whether a `swift_retain`
call precedes the argument setup or a `swift_release` follows the callee's
use. The concrete runtime symbols:

- `swift_retain` / `swift_release` (`include/swift/Runtime/RuntimeFunctions.def:283-292`)
- `swift_retain_n` / `swift_release_n` (`:331-340`, for a batched count)
- `swift_nonatomic_retain` / `swift_nonatomic_release` (`:445-454`)
- IRGen's emission point: `IRGenFunction::emitNativeStrongRetain`
  (`lib/IRGen/GenHeap.cpp:1088-1111`) picks the atomic/direct/nonatomic
  variant and marks the call `Returned` on its argument
  (`GenHeap.cpp:1108-1110`).

**A `guaranteed` parameter produces no retain/release pair around the call at
all** (the whole point of the convention); an `owned` parameter whose value
the caller still needs afterward does. This means: seeing *no* `swift_retain`
before a call is not evidence the value is unused afterward, and seeing one
*is* evidence the argument convention was owned (or the caller had to acquire
a fresh reference for some other reason) — not proof either way about which
formal parameter position it fills.

swiftdc already treats these calls correctly as pseudocode noise rather than
program logic — `Pseudo.swift:391-403`'s `isRuntimeNoise` lists
`swift_retain`, `swift_release`, `swift_bridgeObjectRetain/Release`,
`swift_unknownObjectRetain/Release`, `swift_beginAccess/endAccess`, and the
ObjC ARC equivalents. That's the right place for this fact to live; nothing
here contradicts it. What's missing is using the *presence/absence* pattern
as a signal for argument liveness/ownership recovery (see §7).

## 5. `self`: value types vs. classes vs. metatypes; init entry points

The exact boolean rule for "does `self` get the x20/context treatment" is
`irgen::hasSelfContextParameter` (`lib/IRGen/GenCall.cpp:1885-1919`):

```cpp
bool irgen::hasSelfContextParameter(CanSILFunctionType fnType) {
  if (!fnType->hasSelfParam()) return false;
  SILParameterInfo param = fnType->getSelfParameter();
  if (param.isFormalIndirect()) return true;         // mutating value-type self: pointer
  CanType type = param.getInterfaceType();
  if (auto metatype = dyn_cast<MetatypeType>(type))
    return metatype->getRepresentation() != MetatypeRepresentation::Thin;
  if (type->mayHaveSuperclass() || isa<SubstitutableType>(type) ||
      type->isObjCExistentialType())
    return true;                                      // class instance / class-bound generic
  return false;                                        // non-mutating value-type self: NOT special
}
```

This is the load-bearing citation for swiftdc's `MethodEntryConvention` split
(`ValueTracking.swift:194-221`):

| Source-level self | `hasSelfContextParameter` | Register | swiftdc case |
|---|---|---|---|
| Class instance method | `mayHaveSuperclass()` → true | x20 (pointer) | `.swiftInstance` |
| Class static/type method | thick metatype | x20 (metadata ptr) | `.swiftInstance` (metatype) |
| Mutating value-type method | `isFormalIndirect()` → true | x20 (address of value) | `.swiftInstance` |
| Non-mutating value-type method | none of the above | **no context register** — self is an ordinary trailing formal parameter, expanded like any other loadable value (registers per §2) | `.swiftValueInstance` |

`docs/ABIStabilityManifesto.md:328-331` states the same four cases in prose
("Instance methods on class types: pointer to self"; "Class methods: pointer
to type metadata"; "Mutating method on value types: pointer to the value";
"Non-mutating methods on value types: self may fit in one or more registers,
else passed indirectly") — this is exactly the manifesto's list, now with the
IRGen boolean that implements it. swiftdc's `.swiftValueInstance` comment
("self ... arrive[s] decomposed across SIMD registers ... no x20 pointer",
`ValueTracking.swift:361-365`) is precisely the `return false` branch above.

Note the ordering consequence already visible in `expandParameters`
(`GenCall.cpp:2020-2027`): self is dropped from the *ordinary* parameter list
first (`params.drop_back()`, since `self` is always the SIL-level last
formal parameter) and re-added after the generic signature, right before the
error result (`GenCall.cpp:2051-2096`) — so in the *LLVM IR* parameter list
self is near the end, but that has no bearing on its physical register: the
`SwiftSelf` attribute is what sends it to x20 regardless of IR position (§1).

### Allocating vs. initializing entry points

`SILDeclRef::Kind` (`include/swift/SIL/SILDeclRef.h:102-114`) distinguishes:

- `Allocator` — "the allocating constructor entry point of a class
  ConstructorDecl **or** the constructor of a value ConstructorDecl"
  (`SILDeclRef.h:107-110`). For a class, this is the entry point whose `self`
  is the **type metadata** (thick metatype → x20 per the metatype branch
  above); it allocates the instance (via a runtime allocation call) and
  tail-invokes the initializer. For a value type there is only this one
  entry point.
- `Initializer` — "the initializing constructor entry point of the class
  ConstructorDecl" (`SILDeclRef.h:112-114`), class-only. Here `self` is the
  (partially-)constructed instance — a class type, so it still qualifies for
  x20 via `mayHaveSuperclass()`. The initializing entry point returns `Self`
  as its direct result (x0), which may be a *different* pointer than what
  arrived in x20 (delegation, `self = anotherInit(...)`, failable-init
  early-return-nil). **A decompiler should not assume the x20 value observed
  at entry is still the "real" self by the time of `ret`** for an
  `Initializer`-kind function; the x0 exit value is the authoritative result.

I did not trace the exact SILGen/IRGen code that builds the `Allocator`
thunk's call into `Initializer` (out of the `lib/IRGen` files mined here) —
flagging that as unverified rather than asserting a specific instruction
sequence.

## 6. Disassembly-side patterns and where to decline

Patterns swiftdc already implements correctly (confirmed against the source
above, not new):

- **x20 = self only for a Swift-mangled callee, only when freshly written.**
  `Disassembler.swift:1487-1489`'s `isSwiftMangled` (checks `$s`/`$S` prefix)
  gates the whole convention; `ValueTracking.swift:644-653`'s `selfFreshKey`
  requires x20 to have been written *for this call* rather than inherited
  from an earlier one. Both are necessary: §1 confirms x20 is ordinary
  callee-saved scratch for anything else, so an unwritten x20 surviving from
  a prior Swift call could easily be misattributed without the freshness
  check.
- **x21 clear-then-test as the error check**, not just clear or just test
  (`Structurer.swift:114-142`, `:568-614`) — correctly distinguishes a real
  swifterror check from incidental x21 zeroing (their own worked ObjC
  `isEqual:`/`reduce` counter-examples at `Structurer.swift:134-138`).
- **Coroutine yield**: continuation pointer in x0, first yielded value in x1
  (`ValueTracking.swift:303-309`, citing `expandCoroutineResult`) — matches
  `GenCall.cpp:818-889`'s "continuation pointer first, then yield components"
  ordering exactly (`GenCall.cpp:852` pushes the continuation pointer before
  the yield loop).
- **Retain/release calls treated as noise, not program logic**
  (`Pseudo.swift:391-403`) — correctly excludes `swift_retain`/`swift_release`
  and friends from rendered pseudocode (§4).

Concrete gaps and decline conditions this mining surfaces:

1. **Typed throws (`throws(E)`): CORRECTED 2026-10-09 by measurement — x21 is
   still used.** The claim here was that the
   `combineResultAndTypedErrorType` path (`GenCall.cpp:2207-2231`) leaves x21
   unused for a small, direct error. Compiled (Swift 6.3, `-Onone` and `-O`),
   `typedSmall(_:) throws(SmallErr) -> Int` does pack the *error value* into the
   result register (`mov x0, #0` for `.bad`), but the callee still sets
   `w21 = 1` on the throw exit, and the caller still clears x21 before the call
   and tests it after (`mov x21, #0; bl …; cmp x21, #0; csinv x0, x0, xzr, eq`).
   x21 is the *threw* flag; only the payload moved. So the clear-and-test
   heuristic does see typed throws.

   The defect typed throws actually caused was elsewhere: the demangled
   `f(Swift.Double, Swift.Int) throws(M.E) -> …` has a paren group after the
   parameters, and every signature reader took it as the parameter list. x0 (the
   second argument) rendered as `arg0`, and the literal `0` as an `M.E` case.
   Fixed by `DisassembledFunction.splitSignature` (see
   `docs/PRODUCTION-READINESS.md`, soundness). Still open: a small typed
   error's throw exit renders `return 0` (the error payload in x0) as if it
   were a successful return.
2. **Async functions still get `SwiftSelf` on `self`** at their synchronous
   entry (`GenCall.cpp:2338-2339`, inside `expandAsyncEntryType`), so x20 = self
   likely still holds for an async instance method. But an async function's
   LLVM return type is unconditionally `void`
   (`GenCall.cpp:2283`, `ResultIRType = IGM.VoidTy`) — there is no meaningful
   x0 at a `ret` because results are delivered by calling through the async
   context's resume-function pointer instead of returning normally. swiftdc's
   `exitValues`/`exitFloatValues` tracking (`ValueTracking.swift:295-302`),
   which reads x0/v0 immediately before `ret`, will silently produce garbage
   or nothing useful for an async function's *own* return, even though it
   works for what that function returns to *its own callers* is a different
   question from what a caller of an async function observes (which goes
   through `swift_task` machinery, not a direct `bl`+check). **I was not able
   to fully trace whether the x21 error role is preserved, replaced, or
   dropped at an async entry point in this pass** — the general
   `expandParameters`/error-result code (`GenCall.cpp:2098-2125`) is not the
   function `expandAsyncEntryType` calls into for its own error handling, and
   I did not chase the async-specific error path to a conclusion. Flag as
   unresolved rather than asserting a register.
   Recommend: detect `async` from the mangling (an `Yields`/`TY`-style suffix
   — verify the exact grammar before coding) and **decline** self/error/return
   recovery for async functions until this is independently verified, rather
   than reusing the sync-function heuristics.
3. **Generic type-metadata and witness-table arguments are indistinguishable
   from ordinary pointer arguments by register alone.**
   `expandPolymorphicSignature` (`GenProto.cpp:4459-4464`, invoked from
   `GenCall.cpp:2037-2043`) and `expandTrailingWitnessSignature`
   (`GenProto.cpp:4466-4479`, appending a type-metadata pointer then a
   witness-table pointer, invoked from `GenCall.cpp:2128-2131`) both land
   their pointers in the *same* x0–x7 sequence as real formal arguments —
   there is no dedicated register for "this is a `T.Type` witness," unlike
   self/error/async. A decompiler recovering call arguments for a generic
   Swift function must not label a trailing pointer argument as a "real"
   parameter (or vice versa) without corroborating evidence (a mangled
   generic signature, a known vtable/witness-table layout, or an entry-point
   `MethodEntryConvention` proof) — this is exactly the kind of case the
   project's decline-rather-than-guess rule exists for.
4. **The direct/indirect aggregate threshold is not independently verifiable
   from this checkout** (§2). Any numeric cutoff swiftdc encodes for "this
   struct's fields fit in registers" is a hypothesis to test against compiled
   binaries (per this project's "measurement, not guess" rule), not a fact
   traceable to Swift source alone — the classifying code lives in clang,
   out of tree.
5. **Single-field-struct and single-payload-enum collapse (§2) means a
   "self" or argument that looks like a bare scalar in a register may
   actually be a wrapped type.** Without DWARF/reflection metadata naming the
   wrapper, a decompiler cannot recover the wrapper type name from the
   register pattern alone — this is a legitimate `?`/decline case for field
   *type* naming, not a bug to "fix" by guessing.

## 7. Ranked recommendations for swiftdc

1. ~~**Add a typed-throws detection gate before trusting an absent x21
   clear-and-test as "non-throwing."**~~ Premise measured false (§6.1): typed
   throws keeps the x21 flag. The real typed-throws defect (the signature
   parse) is fixed; the `return <error payload>` render on the throw exit is
   open.
2. **(Return values: DONE 2026-10-09 — `swiftReturnRegister` declines async
   functions and their resume funclets; a funclet's `ret` rendered
   `return swift_task_dealloc()` in libswiftObservation.)**
   **Gate the entire x20/x21/exit-value convention behind an async check**,
   not just the Swift-mangled check `isSwiftMangled` already does
   (`Disassembler.swift:1487-1489`). Self may still be valid; return-value
   recovery (`exitValues`, `exitFloatValues`) is questionable at best for an
   async function's own `ret`, per §6.2 — and the error-register status there
   is presently unverified, which itself argues for declining rather than
   asserting.
3. **Treat trailing pointer arguments on a generic Swift function as
   `.unknown` by default** unless a demangled generic signature or witness
   layout corroborates them as real parameters vs. type-metadata/witness-table
   filler (§6.3). This is a direct instance of the project's "decline rather
   than guess" rule applied to a case this mining specifically surfaced.
4. **Use retain/release call presence as a corroborating (not decisive)
   signal for argument liveness**, not just pseudocode noise to hide. A
   `swift_retain` on a value immediately before a call is consistent with
   (though not proof of) an `owned`-convention parameter; its absence around
   a `self` argument is consistent with the near-universal `guaranteed`
   convention (§4). This is additive to the existing `isRuntimeNoise`
   filtering (`Pseudo.swift:391-403`), not a replacement — the filtering
   should stay, but the *pattern* of what's filtered could feed argument
   ownership annotations if swiftdc ever renders those.
5. **Do not encode a numeric direct/indirect threshold** for aggregate
   returns/arguments as if it were derived from this checkout (§2, §6.4). If
   swiftdc currently has such a constant, it should be labeled a measured
   heuristic against real binaries, with a citation to the measurement, not
   to Swift source.
6. **Lower priority — allocating vs. initializing entry points (§5).** Useful
   for naming `init` call chains correctly (recognizing that an `Initializer`
   entry's x0 exit may diverge from its x20 entry), but this wasn't traced
   to a concrete disassembly pattern in this pass and needs its own
   follow-up before implementation.

## Verification notes

- Every `file:line` above was read directly from `/Users/camden/swift` at
  whatever commit was checked out on 2026-09-08; no line was inferred from
  memory of Swift's public source. Re-run `git -C /Users/camden/swift log -1`
  before trusting a line number against a different checkout state.
- `clang::CodeGen::swiftcall::SwiftAggLowering` (the aggregate classifier
  itself) was not located anywhere under `/Users/camden/swift`; a bounded
  filesystem search for `SwiftCallingConv.cpp` outside this checkout and the
  installed Xcode toolchain also found nothing. Treat §2's boundary claims as
  bounded by call-site behavior, not by having read the classifier.
- §6.2's claim about async error-register handling is explicitly marked
  unresolved above — don't downstream it into swiftdc as a settled fact
  without re-tracing `expandAsyncEntryType`'s error path (`GenCall.cpp:2282`
  onward) to a conclusion, or building a small `async throws` fixture and
  checking the emitted IR/assembly directly (which would also satisfy this
  project's "measure, don't assert" rule better than reading IRGen source
  alone).
- The typed-throws mangling grammar (needed for recommendation 1) was not
  looked up in this pass — it lives in the demangler
  (`lib/Demangling/` or `include/swift/Demangling/`), out of the file set
  this task scoped to (`docs/`, `lib/IRGen/`, `include/swift/ABI/`).

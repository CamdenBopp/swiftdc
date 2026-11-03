# ABI invariants and the defect inventory

Consolidates the fourteen-area review ([ABI-REVIEW-2026-11-02.md](ABI-REVIEW-2026-11-02.md))
with what has been fixed since, and asks whether the defects are isolated
or share a cause. Status as of 2026-11-02, dev f25743d.

Evidence labels: **verified** means a fixture reproduced it and a test seen
red guards the fix; **reported** means a reviewer reproduced it with a
probe outside the repository and it has not yet been rebuilt as a fixture;
**judgment** is an engineering assessment, not a measurement.

## The finding: one question, answered in many places

Most of the confirmed defects are wrong answers to one question: *for a
Swift type, how many registers of which bank does a value of it occupy,
and is it passed directly at all?* swiftdc answers it in eight places,
each with its own list of types:

| Consumer | Where | Asks |
|---|---|---|
| Entry seeding | `swiftScalarArgumentRegisters` (Disassembler.swift) | which register holds each parameter |
| Call layout | `swiftCallArgumentLayout` / `scalarParameterClass` / `integerRegisterFootprint` | which registers a call passes |
| Result in registers | `swiftReturnRegister(forReturnType:)` | is the result one x or one v register |
| Result after a call | `callResultBank` (5b2135d) | which register after the call is the whole result |
| x8 convention | `isKnownDirectReturnType` (IndirectResults.swift) | is the result never through x8 |
| x8 runtime callees | `isKnownDirectReturnCallee` | the same, by name |
| `self` | `selfValueBySite`, `receivesThinMetatype`, `takesNoSelf`, `swiftValueTypeSelfFields` | does x20 hold self |
| Specializations | `signatureSpecializationKeepsLayout`, `specializedSignature` | does the printed signature still describe the registers |

Their type lists disagree. `isKnownDirectReturnType` calls any type
containing ` -> ` direct, so a tuple of three closures (six words) and
`Dictionary<Int, Int>.Iterator` (40 bytes) are taken as returned in
registers, while `swiftReturnRegister` declines both (reported, a3 #4).
`scalarParameterClass` accepted a one-case enum as one register and so did
the return-register gate, because both read `isNoPayloadEnum` (verified,
4aa9d18: one shared gate, one fix covered both paths). The specialization
defect needed two separate fixes, one for seeding (dcb54c3) and one for
calls (8c1f202), because each consumer parses the demangled name itself
(verified).

So the defects are not isolated (judgment, from the table above and the
fix history): the same type-lowering facts are re-derived per pass, and a
gap in one copy surfaces as a defect in that pass only.

## Invariants

Each invariant names the shared fact it needs and where it is enforced
today.

1. **A word of a multi-register value is never the value.** Needs: the
   result's lowering. Enforced for Swift call results (5b2135d) and ObjC
   method returns (f25743d); not for ObjC sends' results (a4, `take1([self
   range:x].location)`, reported) or C 16-byte struct results consumed by
   field (reported).
2. **Arity is never inferred from occupied registers alone.** Needs: the
   parameter lowering, or the callee's proven body reads. Enforced where a
   layout exists, by body reads for signatureless and reshaped callees
   (8c1f202), and by the trailing entry-value rule (78fa7ff). Open:
   positional fallback for struct/SIMD/tuple/closure parameters (a2 #5,
   a9 #2, reported), async callees (a7 #1, reported).
3. **Zero-sized, indirect and multi-register types are accounted for.**
   Needs: lowering with a zero-size and an indirect class. Enforced for
   one-case enums (4aa9d18) and String/Optional-scalar/StaticString/inout
   footprints (78fa7ff). Open: empty structs as parameters, generic `A`
   (indirect) parameters before scalars, the x0 indirect result of a
   generic function with a direct result too (a8 #1, reported).
4. **A specialization does not inherit its original's layout.** Needs:
   the specialization clause, parsed once. Enforced for function signature
   specializations (dcb54c3, 8c1f202). Open: `Tt` (dropped metatype)
   specializations print like `Tg` (a8 #2, reported); closure-propagated
   survivors (a8 #3, reported). The unclosed `[` of a closure-propagation
   name is FIXED: its signature parses, and nested clauses must all keep
   the layout.
5. **A receiver is never taken from a callee-saved register without
   proof.** Needs: whether the callee reads x20. Enforced for in-image
   callees (6c07b3e), and for methods and initializers of frozen
   standard-library structs, which take x20 only as a mutating method's
   address (`standardLibraryStructMethod`). Open: value types of other
   modules seen only by name.
6. **No value flows from a throwing or unreachable path into a normal
   return.** Enforced for merged `ret`s (e2ecce1, 77cf9ef). Open: x21
   after a throwing call has no value of its own, so `try?`/do-catch
   results decline (a6 #2, completeness, reported).
7. **Operand width and signedness are respected.** Enforced for 32-bit
   signed orders and w sign tests (c78254f). Open: narrow non-constant
   returns (a4 #2), narrow C constants (a11 #2), Float16 constants and
   vector `fmov` immediates (a2 #1, #3), `ucvtf` signedness (a2 #4),
   vector lane inserts/extracts (a12 #1), v8-v15 upper halves across calls
   (a12 #2). All reported, all soundness.
8. **Unknown is never spelled as a value.** A cross-cutting rule; each
   item above is an instance.

## Where a shared abstraction pays

**Proposed:** one `SwiftLowering` classification of a demangled type,
computed in one place, consumed by all eight rows of the table:

```
enum Lowering { case zeroSized, oneInteger, oneFloat,
                integerWords(Int), floatWords(Int), mixed, indirect, unknown }
```

with the image's indexes (classes, no-payload enums, field maps) as
input. Each consumer keeps its own policy (decline, render `?`, keep a
statement) but asks the same question. Evidence that it removes
demonstrated defects, not just duplication:

- `isKnownDirectReturnType` and `swiftReturnRegister` disagree today on
  closures and nested collection types (a3 #4); one classifier removes the
  disagreement.
- The one-case enum fix needed one gate because the gate was already
  shared; the specialization fix needed two because the parse was not.
- Every open item under invariants 2 and 3 is a lowering the parameter
  side lacks but the result side has, or the reverse (judgment).

**Not proposed:** a rewrite of the tracer or the renderers. The policy
code (what to print when a fact is missing) differs legitimately per
consumer.

**Order:** land `SwiftLowering` as a behaviour-preserving refactor first,
with a test that every consumer gives the same answer it gave before for
every fixture signature; then make `isKnownDirectReturnType` use it (a
soundness change, measured on its own).

## Inventory, by risk of confident wrong output

| # | Rule | Modelled in | Failure | Kind | Reproducer | Scope | Fix belongs in |
|---|---|---|---|---|---|---|---|
| 1 | Struct/enum results span registers | `callResultBank` | FIXED 5b2135d | soundness | multiresult.swift | every -O Swift caller of a struct-returning function | shared lowering |
| 2 | x20 is self only for a method taking it | `selfValueBySite` + `readsSelfRegister` + `standardLibraryStructMethod` | in-image FIXED 6c07b3e; stdlib struct methods and inits FIXED; other out-of-image value types open | soundness | parkedself.swift, stdself.swift | any -O caller parking a temp in x20 | shared callee facts |
| 3 | w compares are 32-bit | `flagCondition`, tbz/tbnz | FIXED c78254f | soundness | signed32.c | C, ObjC, Int32, value witnesses | isolated (flag model) |
| 4 | ObjC return register from encoding | method exits | FIXED f25743d; x8 tail open | soundness | objcreturns.m | ObjC methods returning float/struct | shared lowering (ObjC side) |
| 5 | swift_willThrow is void; throw paths are not returns | `voidRuntimeCalls`, merged exits | FIXED e2ecce1, 77cf9ef | soundness | throwselect.swift | throwing Swift functions at -O | isolated |
| 6 | swift_dynamicCast returns Int1 | `swiftCastIdiom` | FIXED 0488667 | soundness | dynamiccast.swift | `is`/`as?` on non-class types | isolated |
| 7 | Async calls: x0 context/result, formals from x1 | none (positional) | open | soundness | a7 #1 probes | every async caller | shared lowering + async convention |
| 8 | One-case enums are zero-sized | `isNoPayloadEnum` | FIXED 4aa9d18 | soundness | onecase.swift | functions taking unit-like enums | shared lowering |
| 9 | Narrow ints: high bits undefined | `renderTypedConstant`, `narrowedResult` | constants FIXED 1fd4b94; computed returns FIXED; C declared parameters and printf conversions FIXED | soundness | narrowreturns.swift, a11 #2 | Int8-32 returns; C APIs taking `int` | shared (type width) |
| 10 | Vector lanes, Float16, vector immediates, ucvtf | `InstructionSemantics`, fmov | open | soundness | a2 #1/#3/#4, a12 #1 | SIMD code, struct copies via q regs | isolated (instruction semantics) |
| 11 | Generic x0 indirect result; `Tt`; closure-prop survivors | positional, `specializedSignature` | open | soundness | a8 #1-#3 | unspecialized generics, stdlib specializations | shared lowering + specialization parse |
| 12 | Struct/SIMD/closure params | `swiftCallArgumentLayout` unplaced tail | FIXED (unplaced from the first unprovable parameter) | soundness | structargs.swift | any call passing a struct by value | shared lowering |
| 13 | Body-reads sees only x0-x7 | `CalleeRegisterSummary` | v0-v7 FIXED; incoming stack area open | soundness (arity) | floatreads.c | C callees with float or stack args | isolated (summary) |
| 14 | -Onone stack reloads in conditions | `Structurer.condition` | open | soundness | a14 #1 | -Onone payload switches | isolated (text path) |
| 15 | Untyped ObjC float guard is block-local | `setsFloatingPointArgument` | a call's float result FIXED; a predecessor block's write open (the compiler duplicated the send in the probe) | soundness | objc_untyped_float.m | sends of image-only selectors with floats | isolated |
| 16 | Register preservation edge cases (x18, below-sp, blr summaries, flags across calls) | `ValueTracer` call transfer | open | soundness | a12 #3-#8 | mostly hand-written assembly | isolated |
| 17 | x21 after a throwing call | tracer | open | completeness | a6 #2/#3 | every `try?` / do-catch / propagating caller | isolated |
| 18 | Async function pointer records, context escapes | AsyncFuncletIndex, tracer | open | completeness | a7 #3/#4, a6 #4 | async code | isolated |
| 19 | Value witness calls | none | open | completeness | a13 #4 | every generic function | isolated |
| 20 | `Wvd` field offsets, inherited fields, class-param fields | FieldMap | open | completeness | a14 #3-#5 | classes over resilient or ObjC bases | isolated |

## Next: struct lowering from field metadata

Since b26d282 a struct, SIMD or closure parameter, and every parameter
after it, renders `?`, and entry seeding declines a function with one
(`callPut(_ b: Box, _ k: Int)` shows `k` as `?`). An in-image struct's
field records give its stored types, so its register footprint is
derivable. The rules are IRGen's explosion of a loadable struct (one
scalar per field, nested structs flattened) and its indirect-passing
threshold (swift/lib/IRGen/GenCall.cpp, clang's SwiftCallingConv). They
must be checked against a compiler oracle (`-emit-ir` signatures for a
fixture of field shapes) before any layout uses them. This is the
largest remaining completeness item in the argument layouts. Observed
2026-11-03. Call layouts and entry seeding use it
(`SwiftLowering.aggregateRegisters`); the async-chain seeding does not
have field maps yet.

First oracle, `swiftc -O -emit-ir` (Swift 6.3, arm64), each struct passed
before an `Int`:

| Struct | IR parameters |
|---|---|
| `{Int}` | i64 |
| `{Int32, Int32}` | one i64: integer fields in one 8-byte chunk merge |
| `{Int8, Int8}` | one i16 |
| `{Bool, Int}` | i1, i64 |
| `{Int?, Int}` | i64, i8 (the Optional's tag), i64 |
| `{Int, Double}` | i64, double |
| `{Double, Double, Double, Double}` | four doubles |
| `{Int, Int, Int, Int}`, `{{Int, Int}, {Int, Int}}` | four i64 |
| `{Int ×5}`, `{Float ×5}` | by address (`ptr`) |
| `{String, Int}` | i64, ptr, i64 |
| `{AnyObject, Int}` | ptr, i64 |

So the footprint is clang's SwiftCallingConv on the field byte layout
(integer data merged per 8-byte chunk, more than four legal values
passed indirectly), not one register per field. A layout from field
metadata needs the fields' offsets and scalar types, and a second oracle
for floats sharing a chunk and for enums with payloads.

## Next: value-witness call sites

`ldur xN, [meta, #-0x8]; ldr xN, [xN, #k]; blr xN` calls slot `k / 8` of
a type's value-witness table (swift/include/swift/ABI/ValueWitness.def):
0 initializeBufferWithCopyOfBuffer, 1 destroy, 2 initializeWithCopy,
3 assignWithCopy, 4 initializeWithTake, 5 assignWithTake, and so on.
Measured 2026-11-03 at the struct-seeding commit, in the four swift-syntax
host dylibs: 187 of 810 `/* unresolved call */` sites have this shape
(Operators 4/23, IfConfig 32/142, ParserDiagnostics 21/122,
CompilerPluginMessageHandling 130/523).

Two provenances for `meta`:
- **A static metadata address.** Example: `outlined assign with take of
  PrecedenceGroup`, `adrp x2, …; add x2, x2, #0xda8`, slot 5. `[meta - 8]`
  and `[vwt + k]` are pointers in the image (rebases or binds), so the call
  target is provable by reading them. The tracer does not follow loads
  through image pointers yet.
- **Metadata loaded from an existential container's type word**
  (`ldr x2, [x0, #0x18]`, an `outlined init with copy` of `any P`). The
  slot is still provable, but the type is not: render the slot name only.

A load at `-8` from anything else is not proven to be metadata and
declines.

## Oracle limits

Fixture tests compare renders to expectations written from the source and
`llvm-objdump`; they show a shape is right, not that every shape is. The
compiler-grounded audit's native-execution and z3 oracles check returns
and entry-block conditions only, on a small synthetic corpus and four
swift-syntax dylibs. Tracer conditions (invariant 7) are not in the z3
harness. Nothing here measures ObjC or async beyond the fixtures.

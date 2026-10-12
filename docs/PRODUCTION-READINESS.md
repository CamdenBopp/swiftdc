# Production readiness

What stands between swiftdc and a decompiler whose output can be trusted without
hand-checking it. Organised by **risk**, not by feature appeal.

Each item is `[status] claim — evidence`. Status is one of **OPEN**, **FIXED**,
**MITIGATED**, or **UNKNOWN**. *UNKNOWN means nobody has measured it* — it is not
a synonym for "probably fine", and an UNKNOWN in Soundness or Completeness
outranks an OPEN in Reconstruction quality.

Every claim here should carry either a commit, a file:line, or a command you can
re-run. Claims without one are marked UNKNOWN by definition.

Last audited: 2026-10-12, unified merge of all feature branches (MachOSwiftSection
0.22.0, Capstone 6, x8 indirect returns, arm64e preflight, async funclets), then a
sweep of every subcommand over 7 large apps and 5 dyld-cache frameworks (partial
when written: Prime Video, Fiery Feeds, part of Swiftcord).

---

## 1. Soundness — can it fabricate or misattribute semantics?

The highest-severity category. A wrong render is worse than a missing one,
because it cannot be distinguished from a right one by reading the output.

- **FIXED — unsigned comparisons rendered as signed.** `cset w0, lo` (unsigned)
  used to render `(arg0 < 10)`, which evaluates differently from the machine at
  negative inputs. Fixed in `2be9e31` via a per-value type lattice carrying
  signedness. Verified at HEAD: `x >= 0 && x < 10` at `-O` renders
  `((0 <= arg0) && (arg0 < 10))`; a genuinely signed `x < 10` renders
  `(arg0 < 10)`. Unknown signedness renders an explicit `<ᵁ` rather than
  guessing.
- **FIXED — field-map name collisions fabricated fields.** Two types sharing a
  simple name let one type's layout name the other's fields. Ambiguous simple
  names are now dropped, and qualified keys recover the precise layout
  (`0237af1`, `1ec5872`, `f423666`).
- **FIXED — an async resume funclet's registers were seeded from its parent's
  signature.** The funclet's symbol demangles to the parent's full signature,
  so x0 at its entry was labelled `arg0`; it holds the awaited callee's result,
  and no parameter is in any register there (every live value is spilled to
  the async context, and the ABI preserves no callee-saved register across a
  suspension). It rendered: `twoAwaits`'s second await printed
  `fetchOther(arg0)` for a call whose argument is the first await's result.
  A grouped resume funclet now gets no signature-derived convention
  (`86b35be`); `resumeFuncletsDoNotInheritTheSignatureArgumentsIfPresent`
  was seen red with the seeding restored.
- **FIXED — an optional return of a value type was read from x0 alone.** Its
  nil lives elsewhere: a tag in w1 for `Int?`, an extra inhabitant for an
  enum's optional. `return ((arg0 == 0) ? 0 : (arg0 + 1))` printed nil as 0,
  and a `Tier?` printed nil as its raw tag `3`. An optional return is one
  register now only for a pointer or class payload (`8feed90`), in both the
  `Swift.Optional<T>` and `T?` spellings. `declinesTaggedOptionalReturnIfPresent`
  was seen red.
- **FIXED — int/float conversions were dropped.** `scvtf`/`ucvtf`/`fcvt`/
  `fcvtzs` passed the value through, so `Double(n) * 1.5` rendered
  `(arg0 * 0x3ff8000000000000)`, which executes as n times 4.6e18 (`b3a8510`).
  Conversions render as `Double(x)`/`Float(x)`/`Int(x)`, anchor float context
  for the constant beside them, and the int-to-float fixed-point form
  (`ucvtf d0, x0, #2`) renders `(Double(arg0) / 4.0)`.
  `recoveredConversionsAgreeWithTheCompiledCode` executes five -O conversions
  bit-exactly and was seen red.
- **FIXED — a vtable dispatch named another class's method.** The vtable index
  is keyed by simple name, so `Alpha.Node` and `Beta.Node` shared one slot table
  and `Beta.Node.work()` rendered `return (Alpha.Node.launchMissiles() +
  self.count)`. A colliding simple name now declines (`d6d0e90`);
  `doesNotDispatchThroughAnotherClassesVtableIfPresent` was seen red. Keying by
  qualified name would recover the names (needs the qualified self type).
- **FIXED — an async context slot whose address escaped was still "proven".**
  `var n = a &* 3; await Task.yield(); syncBump(&n); return n` rendered `return
  (arg0 + (arg0 << 1))` for 3a + 11: the slot's address (`add x0, x22, #0x10`)
  went to an `inout` callee. Slots from the lowest escaped offset up are no
  longer proven (`f403603`); `declinesAnEscapedContextSlotIfPresent` was seen red.
- **FIXED — `cmn` was read like `cmp`.** The structurer's text path rendered
  `if x == -1` (`cmn x0, #1; b.eq`) as `if (x0 == 1)`, and `b.mi`/`b.pl` as
  `lhs < 0 // rhs`. `cmn`/`adds` now compare with the negated operand and
  `b.mi`/`b.pl` render the sign of the difference or sum (`5d6c7b7`); both seen
  red.
- **OPEN — a Swift callee's arguments are not capped at its demangled arity.**
  Leftover registers show up as arguments: `static Alignment.center.getter`
  (no parameters) renders `Alignment.center.getter(SwiftUI.Text.init(…))`,
  `sink(Int)` renders `P.sink(arg0, arg1)`, and a non-generic metadata accessor,
  whose body never reads x0, renders `type metadata accessor for P.Box(arg0)`.
  The demangled signature gives the count; plain float parameters (d0–d7) and
  `T?` pairs (payload, isNil) also need laying out from it, which is why
  `.frame(width: 120)` shows `_FrameLayout.init(0x405e…, 0, …)` and
  `takeOpt(nil, 420, nil)` shows six arguments.
- **OPEN — an async function's throw renders as a bare `return`.** It returns
  its error in x20 through ResumeParent (`mov x20, x21; br x1`): `sleepy() async
  throws -> Int` collapses to `return`, and a rethrowing resume shows `else {
  return }`. Name x20 at await-returns and render the error path as `throw ?`.
- **OPEN — a throw merged into the normal epilogue renders as a return.**
  `untyped` renders `return ((arg0 < 0) ? swift_willThrow(swift_allocError(…)) :
  (arg0 << 1))`; `swift_willThrow` returns nothing and x21 carries the error.
  Typed `throws(Err)` copied out through the value-witness table renders no
  throw at all.
- **OPEN — `Tm` merged outlined helpers name one type for all callers.** A
  merged `…WOcTm` demangles as "outlined init with copy of VStack<…>", but each
  call passes its own type's cache in x2; every call prints the VStack name.
- **OPEN — `awaitedN` is bound for a generic or indirect async result.** The
  result is written into a context buffer, so x0 at the resume is not it.
- **OPEN — one call can read as two.** A call consumed by both a branch
  condition and the return prints in both: `if ((Compares.sink(arg0) + …) < 0)
  { trap() } else { return (Compares.sink(arg0) << 1) }`. The machine calls
  `sink` once; binding it (`let r0 = …`) as indirect results already do would
  fix it.
- **FIXED — the uniqueness check was read as the object it checks.**
  `swift_isUniquelyReferenced_nonNull_native` (the lowering of
  `isKnownUniquelyReferenced`) returns a Bool, but the renderer read every
  `isRuntimeNoise` call's result as its argument: a `-> Bool` CoW method
  rendered `return self.storage`, and the CoW branch tested a bit of the storage
  pointer. Only the retain/autorelease family is read through now; a uniqueness
  check renders `isKnownUniquelyReferenced(x)`, any other runtime result `?`
  (`07ec716`). `rendersTheUniquenessCheckAsABoolIfPresent` was seen red.
- **FIXED — an async return could print a two-register or indirect result.**
  An async function returns by branching through its context's ResumeParent,
  and the result is in x0 there only for a type proven to travel in one
  register; an indirect result arrives as a buffer pointer in x0 and the
  compiler branches through x0 itself (`7b20cfc`).
  `declinesTwoRegisterAsyncReturnIfPresent` was seen red on the `Int?` case.
- **OPEN — a call into a linker-deduplicated function is named after an
  arbitrary alias.** ld folds identical functions by default in a release link,
  so one address carries every folded symbol. In an -O probe (`func optK(_ k:
  K?) -> K? { k }` beside struct accessors), 11 symbols share one bare `ret` at
  0xa78; `optK`'s specialization calls it, and swiftdc renders that call as
  `Sync3.pair(arg0)` under `--pseudo` and `Sync3.P2.a.modify … .resume.0` under
  `disasm`. Neither is what the source called, and the two modes disagree.
  Repro: `nm libX.dylib | awk '$1=="<addr>"'` lists the aliases. The rendering
  needs a decision: decline (`sub_…` with a "folded: N functions" note), list the
  aliases, or prefer the one a specialization names.
- **OPEN — an unknown-arity C call is shown consuming the previous call's
  result.** A C callee has no signature, so x0 left over from the last call is
  rendered as its argument: clang -O0 `printf(…); return bump();` with
  `long bump(void)` renders `bump(printf(0x100000847))`. Found by compiling a C
  probe with TinyCC (0.9.28rc, its own Mach-O linker) and confirmed on clang.
  A sound fix: for a callee in the same image, classify which argument
  registers its body reads before writing them (as `IndirectResultUse` does for
  x8); decline for an external one unless a signature table names it.
- **OPEN — a variadic call's stack arguments are dropped, and a scratch x1 is
  read as one.** Apple's arm64 ABI passes variadic arguments on the stack. On
  the TinyCC probe, `printf("%s %ld %ld\n", greet(), add3(1,2,3), sum_to(10))`
  renders `printf(0x100004020, greet())`: x1 held `greet()` only on its way to
  `[sp]`, and the `add3`/`sum_to` calls vanish from the structured view.
- **OPEN — `-f` cannot select a folded function, and its callers ignore the
  fold.** The definition declines as `sub_5d8` with its candidates
  (`foldedByAddress`), but call sites name an arbitrary alias, and `disasm -f
  '$s1P7secondsySiAA7SecondsVF'` prints "No function matched" for a symbol in
  the export table: the empty-result class this project's rules forbid.
- **OPEN — a call to an address that also carries linker marker symbols is
  named after the marker.** TinyCC places `__start_text`, `__init_array_start`
  and friends on `add3`'s address; the function header declines
  (`sub_100001000`) but the call is annotated `→ _init_array_end`. Same class as
  the deduplicated-function alias entry above.
- **OPEN — a float argument to a call is not tracked.** -Onone
  `Double(f) * 1.5` renders `(Swift.Double.init() * 1.5)`: the Float argument
  is in s0, call-site tracking reads only general registers, and the trailing
  unknown is trimmed, so the call reads as a zero-argument init.
- **MITIGATED — the decline-rather-than-guess rule.** Verified as systematic, not
  incidental: `.unknown` renders `?` (`Disassembler.swift:2322`); the structurer
  refuses to structure an unprovable branch (`Structurer.swift:214`); `clobber`
  is deliberately over-pessimistic because under-clobbering "leaves a stale value
  that renders as a confident, fabricated" one (`ValueTracking.swift:1583`);
  fixed-ABI callee args are clamped to real arity so a stale register cannot
  surface as a trailing argument.
- **MITIGATED — `self` is conservative.** x20 is read as `self` only for a
  Swift-mangled callee and only when freshly written (`Disassembler.swift:2847`,
  `ValueTracking.swift:636`). Deliberate false-negative-over-false-positive.
- **MITIGATED — field naming requires two independent halves.** Receiver type
  known AND offset inside the type's trusted prefix; the `isInstance` flag
  refuses metatypes. Consulting the symbol first (which lacks that flag) produced
  a real `swift_allocObject(self, …)` fabrication before the ordering was fixed.
- **OPEN — `X → self.layout` imprecision.** LayoutWrapper structs over `__C`
  types render the whole `self.layout` because the backing C struct has no Swift
  field metadata. A *real* field name at the wrong granularity — imprecise, not
  fabricated. Needs C-struct field data.
- **MITIGATED — a differential oracle now exists** (`DifferentialOracleTests`).
  Every other soundness test compares recovered pseudocode against a string
  someone wrote down, which cannot catch a plausible-but-wrong render: the
  expectation was written by the same reasoning that produced the bug. U1
  survived exactly that way.

  This harness compares against the **binary** instead. It recovers the
  expression swiftdc renders, parses it (the output is fully parenthesized, so
  no precedence table is needed), evaluates it over chosen inputs, calls the
  **real compiled function** via `dlsym`, and asserts they agree. Ground truth
  is resolved from swiftdc's *own reported symbol*, so the oracle cannot drift
  onto a different function than the one it analysed.

  Currently **979 comparisons — 493 at `-Onone` and 486 at `-O`**, 17 functions
  at `-Onone` and 16 at `-O`: comparisons, ternaries, arithmetic, bit operations,
  the signed-range idiom, **integer division/remainder**, and **multi-branch
  switches**, at edge inputs including `Int.min`/`Int.max`.

  Division and remainder are the sharpest arithmetic additions: `a / b` is
  non-commutative, so operand order is executed rather than assumed, and a `udiv`
  mistaken for `sdiv` renders the same `/` yet disagrees at negative dividends —
  the U1 fabrication class, one operator over. Inputs are curated to the
  non-trapping domain (`sdiv` traps on a zero divisor and on the single
  `Int.min / -1` overflow), but deliberately keep `Int.min`/`Int.max` dividends
  against small divisors, where a signedness confusion would surface. Proven
  sensitive: an injected operand swap (`(arg1 / arg0)`) fails at every asymmetric
  input, and an injected operator confusion (`/` ↔ `%`) fails at both levels for
  both cases — before the injection, neither the `/` nor the `%` render had ever
  been executed (the evaluator's division path existed but no case reached it).

  The multi-branch switches (`gradeOf`, `polarity`) are where the two
  optimization levels tell different stories the oracle must reconcile against the
  same binary. At `-Onone` they recover as a chain of `==` ternaries; at `-O` the
  optimizer collapses `gradeOf`'s dense cases into the **U1 unsigned-range idiom
  plus arithmetic** — `((0 <= arg0) && (arg0 < 3)) ? (10 + (arg0 * 10)) : 99` — a
  jump-table→arithmetic transform whose equivalence to the original switch had
  only been reasoned about. Executed across every case value (0,1,2), the first
  default (3), and the signed edges, it now agrees with the compiled switch at
  each. Proven sensitive: corrupting the default arm (`99`→`98`) fails at both
  levels; `polarity`'s negative-constant default (`-3`→`-4`) fails at `-Onone`
  (it does not recover at `-O`, so it is required there alone).

  The `-O` half is the part that matters most, because optimized lowering is
  where U1 lived. It executes the recovered idiom
  `((0 <= arg0) && (arg0 < 100))` against the machine's single unsigned compare
  (`cmp x0, #100; cset w0, lo`) at `Int.min`, `-1`, `0`, `100` and `Int.max`.
  **That is the first execution-based confirmation the U1 fix is correct** — it
  had previously only been reasoned about. `-O` also covers a `csel` cascade
  (`threeWay`) that `-Onone` cannot recover at all, and commuted operands
  (`(arg1 & arg0)`) that `-Onone` renders in source order.

  The two fixtures are separate builds of the same source, so they export
  **byte-identical mangled symbols**. Resolved pointers are therefore verified
  with `dladdr` to lie in the intended image; without that, `dlsym` collapsing
  onto the first-loaded library would make the `-O` half silently re-test
  `-Onone` code while reporting optimized coverage. Confirmed live: the same
  symbol resolves to distinct addresses in distinct owners.

  Proven sensitive, not merely green: injecting U1's shape (`((arg0 >= 0) &&
  (arg0 < 100))` → `(arg0 < 100)`) fails at exactly the negative inputs where
  that defect manifests. The first injection attempt was a **no-op** — it
  targeted the `-O` spelling, which the `-Onone` fixture never emits — and
  passed misleadingly.

  The guards that came out of that: a per-fixture comparison floor, and a
  **named list of cases that must not be skipped** at each level. The named list
  is not redundant with the count — simulating a loss of `-O` `rangeCheck`
  recovery leaves 309 comparisons, which clears the floor of 200 while removing
  the single case the oracle exists for. Only the named check catches it, and it
  was confirmed firing.
- **MITIGATED — the oracle covers floating point too.** A further **628
  comparisons** (314 per optimization level) over six functions: `Double` and
  `Float` arithmetic, an intrinsic (`sqrt`), a literal-returning function, and
  the mixed-register ABI. Zero skips at either level.

  Doubles are compared **bit-exactly**, not approximately — that is the point.
  A rendered constant like `3.14` is a claim about *which* of ~2^64 doubles the
  binary holds, and an approximate comparison would accept a rounded or
  truncated decimal. Proven at that resolution: injecting a **one-ULP**
  perturbation (`3.14` → `3.1400000000000006`, a difference of 4.4e-16) fails at
  both levels. So swiftdc's decoded constants round-trip exactly.

  Edge inputs are the ones that break floats and not integers: signed zero,
  subnormals (`leastNonzeroMagnitude`), both infinities, and NaN — with NaN
  treated as agreeing with NaN, since NaN is not bit-stable across a
  computation.

  `floatMath` is `Float`-typed, so the oracle rounds every intermediate to
  `Float` precision. Evaluating it in `Double` would disagree wherever the two
  round differently and would have looked like a swiftdc defect rather than an
  oracle defect.

  `interleaved(Int, Double, Int, Double)` renders `(arg1 + arg3)`, which is an
  **ABI claim** — integers in `x0`/`x1`, doubles in `d0`/`d1`, with `argN`
  indexing source position rather than register order. Executing it confirms the
  mapping rather than assuming it.
- **OPEN — the oracle's remaining domain gaps.** Strings, enums with payloads,
  memory effects, and anything with side effects are still uncovered, and it
  samples rather than proves. Both optimization levels and both numeric domains
  are now covered; what remains is aggregate and effectful values.
- **FIXED — a declined return value rendered as a bare `return`.** A function
  whose return value was not recovered printed `return` with no operand even when
  its signature said `-> Swift.Int`, reading as "returns nothing" rather than
  "we did not recover this". Not a fabrication, but a declined value described
  misleadingly — and it contradicted the contract that unprovable values render
  `?`. Not a corner case either: bare returns were **~45% of all returns** in the
  fixture (121 bare vs 143 with a value).

  Now `return ?`, but **only where the signature proves a value exists**. The
  rule is one-sided by design, since over-claiming would assert a value that is
  not there:

  - **Void functions keep the bare form** — a void return really is just
    `return`. Measured: 7 in the fixture, all correct before and after.
  - **Unrecognisable signatures keep it too** (`sub_<addr>`, thunks, witness
    accessors — 98 of them). Declining is the house rule.
  - **Throwing functions keep it.** A throwing function's error exit genuinely
    yields no value (the result travels in x21), and whether a given exit is the
    error path is not known per-block, so asserting a missing value on a throw
    path would be wrong. Where the normal exit *is* recovered it already prints
    `return <expr>`, so little is lost.

  Two emission sites had to change, not one; the second was found only by
  re-measuring the whole fixture after fixing the first and noticing a throwing
  function still classified oddly.

  Both directions are proven. Reverting the fix fails the value-side tests
  (including a floor that reported "only 0 function(s) rendered `return ?`");
  over-applying it fails the void and throwing guards, with the population check
  naming the four void functions it would have corrupted.
- **FIXED — an ObjC method's unrecovered return rendered a bare `return`.**
  Closing the "unit-tested only" gap on the classifier's ObjC branch — by
  auditing real system methods rather than the fixture — surfaced a genuine
  integration bug, exactly the kind a unit test could not see.

  The structurer's `usesSwiftError` heuristic treats a body that clears x21
  (`mov x21, #0`) as threading the Swift error register, which suppresses
  `return ?` on the unrecovered path (rendering a bare `return`). But ObjC does
  not use that ABI — its errors bridge through an `NSError**` out-parameter — so
  an ObjC method that merely zeroes x21 while computing a `BOOL` (routine in
  `isEqual:`) was misclassified. Confirmed by disassembly: the offending
  `-[UNNotificationTopicRequest isEqual:]` contains `mov w21, #0`; a
  near-identical `-[UNNotificationCategory isEqual:]` that does not clear x21
  rendered `return ?` correctly. Measured on UserNotifications: **7 non-void ObjC
  methods** rendered a bare `return` purely for this reason.

  Fixed by never setting `usesSwiftError` for an ObjC method (the same gate also
  stops an incidental `x21 == 0` being mis-named `error != nil`). Verified both
  directions: `ObjCValuelessReturnTests` (a population property over real system
  ObjC methods: zero bare returns under a non-void signature, ≥10 `return ?` so
  it is not vacuous) was observed failing without the gate, naming all 7 methods;
  and the existing `aThrowingFunctionsErrorExitKeepsItsBareReturn` confirms a
  genuine Swift `throws` error exit still renders a bare `return`.
- **FIXED — the same misfire hit *Swift* functions too, and the heuristic itself
  was wrong.** Auditing real Swift methods (Combine) for the analogous defect
  confirmed it: **10 non-throwing, value-returning Swift functions** — Publisher
  constructors like `compactMap`, `reduce`, `min(by:)`, `output(at:)` — rendered
  a bare `return` because they zero x21 as incidental scratch. The ObjC `!ObjC`
  gate could not help here (Swift functions genuinely can thread swifterror).

  The real defect was the heuristic: "the body clears x21" is not swifterror
  threading. Genuine threading **clears x21 before a throwing call *and* tests it
  (`x21 == 0`) after** to catch the throw; a function that only zeroes x21 and
  never reads it back is not error-checking. The heuristic now requires **both**,
  which is also why it subsumes the ObjC case — `isEqual:` tests `cmp x21, x0`,
  against a register, not zero.

  This partitions cleanly on real code, measured on Combine: 28 functions that
  clear *and* test x21 (genuine — the "Try" operators catching a closure's
  throw) keep `usesSwiftError`; the 10 that clear without testing flip to
  `return ?`. Both directions proven: the discriminators
  (`clearsSwiftErrorRegister`/`testsSwiftErrorRegister`) are unit-tested
  including the `cmp x21, x0`-is-not-a-zero-test case, and reverting the "and
  tests" requirement was observed regressing exactly those 10 Combine functions
  back to a bare `return` while a `throws` function (`mightFail`) stays bare via
  the `isThrowing` override.

  Along the way the audit *harness* was wrong twice before the tool was — a
  return-type regex that read a parameter's `(A) -> Bool` as the return type, and
  bare-return attribution across `merged` headers — each corrected before
  trusting the count (18 → then a name-parse-free raw-disasm oracle → 10).

- **FIXED — signature parsing read the wrong parameter list and result type.**
  Nine readers (argument registers, argument/enum/Bool/float types, the return
  register, `returnsValue`, `isThrowing`) took the *last* ` -> ` and the *last*
  `(...)` group. Three real demangled shapes defeat that:
  `f(Swift.Double, Swift.Int) throws(M.E) -> Swift.Double` (the typed-throws
  group read as one `M.E` parameter: x0, really the second argument, rendered
  `arg0`, and `0` rendered `M.E.negative`); `f(Swift.Int) -> (Swift.Double) ->
  Swift.Double` (the closure's types read as the function's; `return arg0`
  printed a stale `d0`); and `closure #1 (…) -> () in g() -> Swift.Never` (the
  enclosing function's result read as the closure's, so `return ?` on a Void
  closure). `DisassembledFunction.splitSignature` now splits at the first
  depth-0 arrow, cuts ` in <context>`, and strips `async`/`throws`/`throws(E)`.

  Reading the *real* result type exposed results that never come back in x0:
  a closure reabstracted to a generic convention returns through the x8 buffer,
  and an async function delivers its result through its context. Both now
  decline (`readsIncomingIndirectResult`, the async check in
  `swiftReturnRegister`). That also removed older fabrications on ordinary
  indirect returns, e.g. `OuterY.Wide.init` (40 bytes) printing `return arg0`,
  `ObservationRegistrar.init()` printing `return _ManagedCriticalState.init(…)`
  when it stores a different value through x8, and `-> String` witnesses
  printing `return 0`.

  The decline is now the fallback, not the answer (`3dc93d0`): x8 use is
  classified on the CFG from Capstone's operand roles (`IndirectResultUse`),
  the tracer follows the stores through the incoming x8 (and through
  `memcpy`/`memset` and the outlined copies into it), and a `ret` renders
  `return Type(field: value, ...)` only when the stores cover the result
  type's complete layout exactly, `return callee(args)` when a callee proven
  to read its own x8 filled the buffer, and nothing at all when the pointer
  escaped or a field is stored on one path only. See the Completeness entry.

  Measured old→new with `disasm --structured` on four cache images:
  libswift_RegexParser 102/2734 functions changed, libswiftObservation 38/713,
  libswiftDistributed 4/367, SwiftData 0/6506. Every change was reviewed;
  the one lost-looking label (`tryEat(self: arg0, …)` → `tryEat(…)`) had been
  derived from the *enclosing* function's `(Bool, Bool)` parameters, so its
  correctness was luck. Guarded by `SignatureSplitTests` (each of the four
  guards injected back to the old behaviour and watched fail).

  The typed-throw exit that rendered `return 0` is FIXED below.

- **FIXED — the swifterror arming value read as the callee's error.** A caller
  arms swifterror by loading x21 with its current error (zero, or a saved copy
  of the error it was handed) before a throwing call, then tests x21 after. The
  do/catch fix (`e39f64b`) invalidated x21 only when the callee's demangled name
  said ` throws`, and only in the tracer. Two consequences, both measured in
  SwiftData (`disasm --structured`/`--pseudo --image-path …/SwiftData`):
  an `@objc` thunk calling a stripped throwing method rendered `if (0 != 0)`,
  `return 1` (really `return (error == nil)`) and `swift_errorRelease(0)`; and
  the structurer's text walk-back crossed *every* call for x21, so 164
  functions rendered a post-call `cbz x21` as a test of the register x21 was
  re-armed from (`x19 != 0`), even for callees named ` throws`.

  Now the tracer invalidates an armed (zero) x21 at any callee not
  `provablyDoesNotThrow` (a C-level symbol, a value-witness/metadata helper,
  or a full Swift signature without `throws`; an unnamed callee, a
  signature-less metadata label like `Type.method`, and an accessor, whose
  demangling never shows `throws`, all may throw). The structurer stops its
  x21 walk at the same callees, except when x21 holds a call's result
  (`bl f; mov w21, w0`), which an armed x21 never is. 181 SwiftData functions
  changed in `--structured`, 10 in `--pseudo`; the other three cache images and
  every fixture are unchanged. Guarded by `SwiftErrorCalleeTests` against a new
  fixture, `Fixtures/Sample/swifterror.swift` (`-O`, plain and `strip -x`).

  The `(0 != 0)` that remains in `-Onone` value witnesses
  (`getEnumTagSinglePayload`) is faithful: the compiler emitted
  `mov w8, #0; cbnz w8`. Folding it would be a readability change.

- **FIXED — a throw exit rendered as a successful return.** A throwing
  function returns its error in x21; x0 at that `ret` is not a result. For a
  small typed error it is the error's payload, so `throw .negative` rendered
  `return 0`. Untyped throws rendered `return swift_willThrow(…)`, and a typed
  forwarder's `-Onone` error path rendered `return (typedPick(arg0) & 255)`.
  The tracer now records x21 at each `ret`. An exit is a throw only where x21
  is *proven* set: a non-zero constant (typed throws sets `w21 = 1`) or a fresh
  `swift_allocError` box. A normal exit leaves x21 as it came in, which the
  tracer never knows. It renders `throw <E.case>` when the typed error is a
  no-payload enum whose tag is in x0, else `throw ?`. A merged exit
  (`csel x21, x21, x8, eq`) proves neither and keeps its `return`. Guarded by
  `SwiftErrorCalleeTests` (two cases, so the tag→case mapping is pinned).

  Coverage gap, declined rather than guessed: an error built by a helper
  (`mov x21, x0` after `sub_…`) proves nothing, so SwiftData's throw paths
  are unchanged (0/6506 functions). Strict and loose classification
  ("any known x21") could not be told apart on any measured binary; the
  strict form is kept because it cannot over-claim.

- **FIXED — negating a branch condition by text replacement.** When the arm
  it renders is the fall-through, the structurer negates the condition. It
  did that by replacing the first operator text it found, everywhere in the
  string. Three measured failures: the `-O` range guard
  `(0 <= x) && (x < 101)` negated to `(0 > x) && (x < 101)`, never true where
  the `throw .tooBig` it guards runs; a ` == ` inside a demangled generic
  clause was rewritten (`where A.Element == Swift.String` → `!=`, SwiftData);
  and in 6 RegexParser functions that rewrite *replaced* the real negation, so
  `if (!starts<… == …>(…))` kept its `!` with a corrupted name, inverting the
  branch. `ControlFlowStructure.inverted` now rewrites an operator only for a
  single comparison at paren and generic depth zero, and wraps anything else
  as `!(…)`. Measured against `36b611e`: RegexParser 24/2734, Observation
  16/713, Distributed 5/367, SwiftData 90/6506 functions changed; besides the
  fixes above, every change is a precedence-correct wrap
  (`!x23 overflow 1` → `!(x23 overflow 1)`). Guarded by
  `ConditionInversionTests`.

- **FIXED — `swift_willThrow`'s operand read from x0.** The runtime takes the
  thrown error in x21 (`SWIFT_ERROR_RESULT`, swift/include/swift/Runtime/
  Error.h:71) and nothing in x0, so the rendered argument was whatever x0
  last held: `swift_willThrow(0)` 20 times in SwiftData, and
  `swift_willThrow(swift_errorRelease(?))` in RegexParser, where a release ran
  between boxing the error and throwing it. It now shows x21, or nothing when
  x21 is unknown. SwiftData's throws now read
  `swift_willThrow(swift_allocError(…))` (4 → 55) or the converted NSError.
  Guarded host-gated by `willThrowShowsTheErrorInX21NotX0IfAvailable`.

- **FIXED — a local passed by address kept its pre-call value.** A call that
  receives a local's address may write it, but the tracer kept the value
  stored before the call. Measured: an NSError out-parameter rendered a
  failure's error as `_convertNSErrorToError(0)` (20× in SwiftData); a value
  mutated in place through `self` in x20 rendered as its original
  (`Stack.count.getter(Stack.init())` after pushes; `String.append("Optional")`
  for a string already extended to `"Optional {"`; `self.entries =
  self.entries` across an `inout` call). A call now forgets each escaped
  local (any frame address in x0–x8, x20, or an outgoing stack argument) up to
  the next local whose address the function takes separately
  (`ValueTracer.addressTakenFrameOffsets`), never the incoming stack
  arguments, and not for `__swift_project_boxed_opaque_existential_1`, which
  only reads its container. Measured against `0c3bb54` (`--pseudo`):
  RegexParser 35/2734, Observation 3/713, Distributed 12/367, SwiftData
  250/6506 functions changed; a token scan found no changed function gaining
  a new value, only stale values removed or declined. Known imprecision: a
  spill slot inside an escaped extent that is not separately address-taken
  is also forgotten (`self: self` lost in `Event.cancel`), a decline.
  Guarded by `EscapedLocalTests` and `resolvesConcreteWitnessTableDispatch`.

## 2. Completeness — what does it silently omit?

Silent omission is the worst failure mode: it is indistinguishable from a
correct empty answer. See the empty-result rule in `CLAUDE.md`.

- **FIXED — whole-binary disassembly returned nothing on most dylibs.**
  llvm-objdump right-aligns its address column; the parser required
  `allSatisfy(isHexDigit)` on everything before the first colon, so every
  instruction line of a low-based binary was dropped. Reported
  `// No functions matched.` — 0 functions where the binary had 446 (`d1ca94f`).
- **FIXED — the guard against that class.** An empty parse is now cross-checked
  against `LC_FUNCTION_STARTS` and throws `DisassembleError.parsedNothing` with
  both counts rather than returning `[]`.
- **FIXED — the call graph dropped every tail call.** `CallGraph` read only
  `bl`/`blr`, so a `b` into another function's entry added no edge. On Fiery
  Feeds 14,401 of 180,015 functions are reached only that way, and `xrefs
  --unreferenced` listed all of them as having no caller. Found with an
  independent oracle: a raw `bl`/`b` imm26 scan of `__text` (89 ms) agreed
  with the graph on every `bl` target and disagreed on exactly those `b`
  targets, each from another function. A `b` is now an edge, marked
  `(tail call)`, when it leaves its function for a recovered entry or a stub;
  one into the middle of another function is not. Test:
  `countsATailCallAsACallerIfPresent`.
- **FIXED — an x8-indirect return rendered `return ?` (or a stale x0).**
  `3dc93d0`, `17efe56`, `854ffc5`. Callee side: the stores through the
  incoming x8 that reach a `ret` on every path render field-wise against the
  result type's complete FieldMap (`OuterY.Wide.init` → `return
  Reconstruction.OuterY.Wide(v1: arg0, …)`; the resilient `IntPair.init`,
  `Vec2.init`, `Point.init` likewise), a forwarded buffer renders the callee
  (`makeWide` at -Onone → `return Indirect.Wide5.init(arg0, …)`, its `memcpy`
  folded), and a payload enum of more than four scalars names its case from
  the stored tag and its declared word-tuple payload (`return
  Indirect.Shape4.box(arg0, arg1, arg2, arg3)`, `return Indirect.Shape4.empty`).
  Caller side: a proven x8 reader of known size called with x8 into the frame
  leaves words of its result in those slots, bound once (`let r0 = makeWide(…)`;
  `return (r0.a + r0.e)`), never spelled out per field. -O constant fills
  through `ldr q`/`dup` read the `__TEXT` literal pool and nothing else.
  Measured on the shared fixtures (0c8550e tool vs `854ffc5`, `--structured`):
  libReconstruction 6 lines, .opt 2, .resilient 30, libSample 2, sample.debug
  7, every one a stale-x0 return replaced or declined. Still declines, by
  design: a generic result (its pointer escapes into the value witness), an
  existential (no stored-property layout), a result copied from a local whose
  address escaped (`escapedWide`), a payload whose scalar arity is not a
  word-tuple's (`tagged(String, Int, Int)`), and a buffer filled by an
  unknown callee. Guarded by the indirect-result section of
  `ReconstructionTests`, `PayloadEnumCaseIndexTests`, `ReturnTypeNameTests`.
- **FIXED — the Capstone whole-image decode stopped at the first undecodable
  byte.** `cs_disasm` halts at the first byte sequence it cannot decode and
  returns the count so far; the engine called it *once* and took that as the
  decode. `__text` is full of things that stall it — inline data, alignment
  padding, jump tables, unknown arm64e forms — so every whole-image decode
  truncated at the first one.

  The prior entry here recorded "~285 functions" as a modest shortfall. Adding
  the coverage metric reframed it: **285 of 105,647 declared functions, 0.27%**,
  decoding 4,040 instructions over 16,160 contiguous bytes before stopping
  silently. The listing looked entirely normal. ARM64's fixed 4-byte width makes
  recovery exact rather than heuristic — on a stall, skip one instruction slot
  and resume — so the fix carries no realignment guesswork.

  Confirmed at full scale: SwiftUI now recovers **105,644 of 105,644 declared
  functions (100%)** and 5,654,282 instructions, up from 285 and 4,040 — 371×
  more functions, 1,400× more instructions.

  This entry previously read "105,644 of 105,647 … the three unrecovered
  functions are worth a look". There were never three: the denominator was
  inflated by `LC_FUNCTION_STARTS` padding (see the oracle fix in Completeness).
  A residue reported against a wrong denominator is a phantom, and chasing it
  would have been wasted work.

  Covered by `CapstoneResyncTests`, which pins the resync *stride* (a
  wrong-sized skip still yields the right instruction count at wrong addresses),
  and was observed failing against the single-call decode before being trusted.
- **OPEN — names for statically-dispatched Swift on stripped binaries.** Free
  functions, closures, thunks, and struct/enum non-protocol methods render
  `sub_<addr>`. Boundaries recover; names have no metadata record to recover
  *from*. Measured, on CoreLocation: 2,018 of 4,126 recovered functions
  (~49%) render `sub_<addr>` — the single dominant real-output gap.

  The standard tool workaround — reading the dyld cache's **local-symbols
  region**, which is what IDA/Hopper use to name internal functions — was checked
  and **does not apply here**: on the shipping macOS cache `localSymbolsInfo` is
  nil (the `localSymbolsSize` header field is zero) and there is no separate
  `.symbols` subcache file. Local symbols are stripped from the production cache,
  so there is nothing to recover. This upgrades "partly inherent" from a claim to
  a measurement: for `--image` targets the names are *genuinely* absent, not
  merely unread. (A standalone unstripped `.dylib` on disk keeps its local
  nlist symbols; the gap is specific to cache images.)
- **FIXED — async resume funclets were anonymous, ungrouped functions.** The
  compiler splits an async function at each suspension point into an entry
  funclet plus one resume funclet per `await` (`…TQ<n>_`) or executor hop
  (`…TY<n>_`). Those are local symbols, so a stripped binary listed each as an
  unrelated `sub_<addr>` with nothing recording that it is the second half of
  some `await`. `AsyncFuncletIndex` (`3368fc8`) recovers the grouping from two
  cross-checked sources: the `__TEXT,__swift_as_entry` / `__swift_as_ret` /
  `__swift_as_cont` relative-pointer tables the compiler emits for the
  backtracer (present on a stripped system app, Stocks), and the resume-pointer
  stores in the code (a funclet materialises its successor's address before
  suspending). Without the tables it falls back to the code evidence with a
  stricter test (context allocation or a hop in the same function), so a
  synchronous function storing a plain function pointer is never grouped, and a
  suspension-free async leaf is then undetectable by construction. A declared
  funclet nothing reaches is an orphan, attached to no parent.

  Measured on `libAsyncFns` (7 async functions, 7 resume funclets, 5 await-
  return and 2 continuation): all 14 grouped with the parent, ordinal and kind
  the unstripped symbol table gives, on `-Onone`, `-O` and stripped `-O`; the
  stripped listing recovers 34 of 34 `LC_FUNCTION_STARTS` functions; the nine
  synchronous fixtures change zero output lines. A nameless funclet is titled
  `resume #N of <parent>` (source `async-funclet`), `--function` on an async
  function brings its whole chain, and the JSON carries the chain. Oracle:
  `AsyncFuncletTests.groupsFuncletsAsTheSymbolTableDoesIfPresent`.
- **OPEN — unresolved indirect call edges.** Generic witness tables, unknown
  receiver vtables, and block pointers stay unresolved. `xrefs` reports the
  count, so this is *disclosed* rather than silent — but `--unreferenced` is
  therefore not a dead-code proof.
- **FIXED — the completeness oracle itself over-counted.**
  `declaredFunctionCount` is what the empty-result rule compares against: an
  empty parse throws when it disagrees, and an unfiltered run warns below 50% of
  it. It was inflated. `LC_FUNCTION_STARTS` is a ULEB128 list of *deltas*,
  zero-padded to alignment, and each padding byte decodes as a delta of zero —
  "another function at the same address as the last". The raw list therefore ends
  in a run of repeats.

  Measured: 453 raw vs 449 distinct, 182 vs 176, 172 vs 171 — and the distinct
  count matches `dyld_info -function_starts` **exactly** in every case. Now
  deduped at the source. Boundary callers were always unaffected (they wrap it in
  a `Set`), so the change moves counts only — verified by enumerating all five
  call sites rather than assuming.

  The visible consequence was a phantom: SwiftUI read as "105,644 of 105,647
  recovered", and the missing three were padding entries, not functions.
- **MITIGATED — recovery coverage is now reported.** An unfiltered run that
  recovers under half of what `LC_FUNCTION_STARTS` declares warns on stderr with
  both counts and a percentage (stdout stays pipeable). This is the
  "unusually small" half of the empty-result rule; the empty case throws.
  It is what turned the SwiftUI shortfall from a vague "~285" into a diagnosis.
- **MITIGATED — byte-level coverage measured; no truncated bodies found.**
  Function-count coverage could not distinguish a fully-decoded function from one
  recovered with a truncated body. Measured two ways, against
  `dyld_info -function_starts` as an independent extent source:

  - **Every declared 4-byte slot decodes**: 100.000% on `libReconstruction.dylib`
    (7,624 slots) and `sample.release` (2,291) via the objdump path.
  - **No holes inside recovered bodies**: 0 hole-bytes across the fixtures and
    across `UserNotifications` (1,391 functions, 52,071 instructions) via the
    Capstone path — the one that carried the resync truncation.

  The first attempt at this measurement was **vacuous** and is worth recording:
  it compared each function's decoded end against the *next recovered function's*
  start, both of which come from the same decode. It reported a flawless 100%
  with zero gaps across 1,391 functions — implausible, since real binaries have
  alignment padding between functions. Comparing a decoder against itself proves
  nothing; the numbers above use an external tool.

## 3. Robustness — what breaks it?

- **FIXED (upstream) — MachOKit read an empty `seg_info_offset` as a segment's
  starts.** Recorded against the 0.52.102 fork (`07d7633`): a zero
  `seg_info_offset` ("no fixups in this segment") was resolved as a starts
  record at offset 0, and a three-segment dylib read 32 KB past its mapping.
  MachOKit 0.54.101 skips it (`guard offset != 0` in
  `MachOFile+DyldChainedFixups.swift` `startsInSegments(of:)`, mirrored for
  `MachOImage`), and the current fork (`4c4738f`) is 0.54.101 plus one unrelated
  change. Verified against the source, not by re-running the original
  40-iteration loop.
- **FIXED — an ivar whose offset is computed at load time trapped `objc`,
  `xrefs`, `disasm` and `analyze`.** A Swift class whose stored properties
  follow a resilient-size one (a Foundation `Date`) keeps its field offsets in
  zero-fill `__common`, and ObjCDump `try!`-reads them as if file-backed. On
  Prime Video the slot maps past the end of the file: at origin/master four of
  eight subcommands died by SIGTRAP with no output (`objc` at 0.5 s; `xrefs`,
  `disasm --structured`, `analyze` after 488–569 s and 4–6 GB). Inside the file
  the read returns padding (offset 0). Such ivars are now recorded at
  `ObjCMetadataSnapshot.runtimeIvarOffset` and never named in a field map
  (`267e341`); `recordsLoadTimeIvarOffsetsAsRuntimeIfPresent` was seen red.
- **FIXED — a C string read at a zero-fill address ran `strlen` off the
  mapping.** `ReferenceResolver.name(at:)` read a string at any unnamed operand
  address through `fileOffset(of:)` + `readString`; an `adrp` to a `__common`
  global on Prime Video pointed past the end of the file, and the scan faulted
  whenever the next page was unmapped (`objc` SIGSEGV after 282 s in one run,
  exit 0 under lldb). Standalone images now read strings only from file-backed,
  non-zero-fill bytes, bounded by the segment and 4 KB, at all three sites
  (`1741748`).
- **FIXED — the preflight's zero-fill table had 0x13 for 0x12.** 0x13 is
  `S_THREAD_LOCAL_VARIABLES` (file-backed TLV descriptors), 0x12 is
  `S_THREAD_LOCAL_ZEROFILL`, so a large `__thread_bss` would have been refused and
  an overrunning `__thread_vars` passed (`bc344aa`, both directions tested red).
- **FIXED — malformed input crashed the process.** The audit recorded this as
  one case (a truncated Mach-O). Surveying nine hand-written malformed inputs
  found **seven crashed** — six SIGTRAP, one **SIGSEGV** — including an *empty
  file* (`MachOKit/FileHandle+.swift:188: Precondition failed: Invalid Data
  Size`). Four distinct trap sites across MachOKit and `FileIOBinary`, all
  `try!`/`precondition`, all in dependencies, therefore all uncatchable.

  Fixed by `MachOPreflight`, a structural validator run before the file reaches
  MachOKit. Every check compares two numbers the file itself declares — header
  size vs file size, `sizeofcmds` vs bytes available, `ncmds` vs the 8-byte
  minimum command, fat slice extents vs file length — so it encodes no
  heuristic about what binaries "normally" look like. Nine of nine inputs now
  exit 1 with a specific message; zero crash.

  The over-rejection risk is guarded explicitly, because a validator that
  refuses real binaries would be worse than the crash: tests assert acceptance
  of well-formed headers, headers whose load commands extend past the read
  prefix, every built fixture, and real fat system binaries (`/bin/ls`,
  `/usr/lib/dyld`). Non-Mach-O files (a PNG) fall through to the existing
  "Not a Mach-O file" path rather than being called malformed.

  The end-to-end guard runs the CLI as a **subprocess** and asserts it exited
  rather than died by signal — the crash cannot be observed in-process, since a
  trap would take the test runner down with it.
- **MITIGATED — other malformed inputs degrade cleanly.** Random bytes →
  `Error: Not a Mach-O file`, exit 1. A truncated-but-parseable binary →
  `llvm-objdump failed: …`, exit 1. Both correct.
- **FIXED — malformed load-command PAYLOADS crashed four subcommands.** The
  header survey above was recorded FIXED while this entire class was still live,
  because it exercised `disasm` — which shells out to llvm-objdump, and
  llvm-objdump rejects a bad file before MachOKit ever parses it. `dump`,
  `layout`, `interface` and `objc` reach MachOKit directly.

  Mutating a real fixture's load-command payloads produced **12 SIGTRAPs**: a
  segment `fileoff` past EOF killed all four subcommands, and each of the four
  `LC_SYMTAB` range fields (`symoff`, `nsyms`, `stroff`, `strsize`) killed `dump`
  and `interface`. The process died **silently — empty stderr**, so it vanished
  with no diagnostic at all. Some cases also emitted partial stdout before dying.

  Fixed in `ae66f3e` by extending `MachOPreflight` to the payloads: segment
  `fileoff`/`filesize`, per-section `offset`/`size`, and the `LC_SYMTAB` symbol
  and string ranges must lie inside the file. Same philosophy as the header
  checks — every comparison is between two numbers the file declares about
  itself. Zero-fill sections (`S_ZEROFILL`, `S_GB_ZEROFILL`,
  `S_THREAD_LOCAL_ZEROFILL`) are exempt because their `size` is a memory extent,
  legitimately larger than the binary; bounds-checking them would reject real
  `__bss`. 64-bit fields are clamped rather than converted, since `Int(_:)` traps
  above `Int.max` — the exact hostile input this code exists to survive.

  All 12 now exit 1 with a field-level diagnostic naming the segment or table,
  the bytes claimed and the file size, and emit no stdout. Verified by
  `MachOPreflightTests` (28 tests): 8 unit tests over the pure validator plus an
  end-to-end test that mutates a real fixture and drives the CLI as a subprocess
  across all four subcommands. Every one was observed failing against the
  pre-fix validator — the end-to-end test on both `terminationStatus == 1` and
  `stdout.isEmpty`.

  Over-rejection re-checked: every fixture, `/bin/ls`, `/usr/lib/dyld` and an
  object file still analyse normally.
- **FIXED — a structurally valid Mach-O missing an expected segment trapped.**
  Renaming `__TEXT` to `__TEXTX`, or letting an unknown `cmd` hide `__LINKEDIT`,
  is valid ASCII in a legal layout, and MachOKit aborted on it: exit 133 from
  `dump`, `interface`, `disasm` and `analyze` (and `objc` for the `__LINKEDIT`
  case), with empty stderr.

  This was recorded as uncontainable, on the grounds that "require a segment
  named `__TEXT`" would reject object files, which carry one unnamed segment.
  That holds for a blanket rule but not for dyld's own. `dlopen` on each
  re-signed mutant names three distinct checks, applied to loadable images
  only (`MH_EXECUTE`, `MH_DYLIB`, `MH_BUNDLE`): a section's `segname` must
  match its containing segment ("section '__text' segment name '__TEXT' does
  not match containing segment's name '__TEXTX'"), "missing __TEXT segment",
  and "malformed mach-o has no LINKEDIT". `MachOPreflight` now applies exactly
  those, after walking every load command. An object file is exempt: its one
  unnamed segment holds `__TEXT`, `__DATA` and `__LD` sections, and it still
  analyzes (exit 0).

  Measured: every subcommand on the three mutants now exits 1 with dyld's
  reason. A sweep of 328 real on-disk Mach-O files (`/bin`, `/usr/bin`,
  `/usr/sbin`, Xcode dylibs, app and kext binaries) gave 0 rejections and 0
  crashes. Guarded by the segment tests in `MachOPreflightTests`.

  Two more of dyld's rules close the rest of the class the fuzz still found:
  "section '…' end address … is beyond containing segment's end address …"
  (a flipped top byte of a section `addr`; SIGSEGV/SIGTRAP), and "chained
  fixups, seg_count exceeds number of segments" (a flipped `cmd` byte turns a
  segment into an unknown command and its memory vanishes; SIGSEGV). The
  address rule skips unmapped segments and debug sections: a Go binary's
  `__DWARF` (`vmsize` 0, `S_ATTR_DEBUG`, sections sized past its empty range)
  loads under dyld, and the first version of the rule falsely rejected
  `com.docker.build` in the real-binary sweep.

  Measured with `Tools/container-fuzz.py Fixtures/Sample/libSample.dylib 120 7`
  plus a second 120-mutant set drawn in a different RNG order: **6 + 3 crashes
  before (`0c3bb54`), 0 now.** Every mutant rejected with a dyld-attributed
  message (92) is one dyld also refuses after re-signing; 0 disagreements. A
  real-binary sweep of 465 on-disk Mach-O files (system, Xcode, apps, kexts,
  fat and thin): 0 rejected, 0 crashed.
- **MITIGATED — a bounded container fuzz exists, and its yield is measured.**
  It is now committed as `Tools/container-fuzz.py` (seeded, deterministic;
  exits nonzero on any crash). History: 3 crashes in 120 (2.5%) after the
  payload fix; 0 in 240 after the dyld-rule preflight above. Still run by
  hand, not a CI gate.
- **FIXED — the `--cache` entry point trapped on a short file.** The recorded
  reasoning ("the system cache is not attacker-supplied") held only for `--cache`
  *omitted*; an extracted cache passed by path is user-supplied, and that
  assumption was tested rather than trusted. `FullDyldCache(url:)` reads a whole
  `dyld_cache_header` at offset 0 **before** checking the magic, via a `try!`, so
  any file shorter than that struct trips
  `precondition(data.count >= layoutSize)` and aborts — exit 133, empty stderr,
  the same uncatchable-dependency class as the Mach-O path.

  Probed: **5 of 7** malformed caches crashed, every one shorter than the header
  (`MachOKit/DyldCache.swift:82`). And the residue is *zero*: every file at least
  header-length — including valid-magic files with lying mapping/image
  offsets — declines cleanly through MachOKit's own magic and cpu-type checks. So
  the entire class closes with **one size guard** on the `cachePath` branch of
  `openDyldCache`, throwing when the file is shorter than `DyldCacheHeader.layoutSize`
  (read from the type, 552 bytes today, so it tracks the struct rather than
  hardcoding it). The host-cache branch is left unguarded — it is the running
  system's cache, not a user path.

  Both directions proven. The end-to-end test drives the CLI as a subprocess and
  was observed failing without the guard ("empty: killed by signal 5"); the
  over-rejection test pins the one-byte boundary — a file of `layoutSize - 1` is
  rejected *by the size guard* (which names the size), while `layoutSize` exactly
  passes the guard and is declined *by MachOKit* on content. A real 737 KB
  extracted cache still dumps Foundation through the guarded branch.
- **FIXED — structurer stack overflow on deep CFGs** (`ca82d6f`).
- **FIXED — spurious dyld-cache markers trapped ObjC index construction**
  (covered by `buildsObjCIndexWithoutTrappingOnSpuriousCacheMarkers`). The
  markers were never real: the iOS simulator's frameworks are linked
  `-interposable`, so a class-list slot pointing at an exported class holds a
  bind to the image itself, and MachOObjCSection 0.8.105 resolved rebases only,
  so those classes were read from the wrong place. The guard kept the process
  alive but skipped them: `objc` on the iOS 18.3 simulator's
  `UIKit.axbundle/UIKit` printed 6 of its 853 classes. MachOObjCSection 0.8.110
  resolves the self-bind (its `f17ace7`); at the 0.22.0 pin the same command
  prints all 853 (the `__objc_classlist` size, 0x1aa8 / 8) plus its 6
  categories, and the guard filters nothing. The test now asserts that.
- **FIXED — a dylib command's name offset outside its command trapped
  `dump`/`interface` at the 0.22.0 pin.** New trap class, opened by the
  upgrade: the class dumper's ObjC ancestor walk reads
  `MachOFile.dependencies`, and MachOKit's `DylibCommand.dylib(in:)` reads
  each name with `try! readString` at the command's `name.offset`.
  `Tools/container-fuzz.py Fixtures/Sample/libSample.dylib 150 7` mutant 63
  and `sample.release 150 7` mutant 104 died by SIGTRAP on 0.22.0 and failed
  cleanly on 0.19.0 (0 crashes, same seeds). `MachOPreflight.validateDylib`
  requires `24 <= name.offset < cmdsize` on the six dylib command kinds;
  both mutants now decline with rc 1 on every subcommand. Covered by
  `rejectsADylibNameOffsetOutsideItsCommand` (seen red) and
  `acceptsAWellFormedDylibCommand`.
- **MITIGATED — `MachOFile.symbols` fatalErrors on cache images** whose
  `__LINKEDIT` sits in another subcache. Uncatchable; avoided by reading the
  export trie instead, which is also semantically correct.
- **PARTLY FIXED — metadata parsing crashes on corrupted `__swift5_*` /
  `__objc_*` contents.** The flat relative-pointer tables are now validated;
  the structured sections are not. Details of the fix are below the measurement. The prediction that the `try!`-in-a-dependency class would recur
  has now been tested a **third** time and held again. `MachOPreflight` validates
  the Mach-O *container*; it says nothing about section *contents*, which
  MachOSwiftSection / MachOObjCSection parse.

  Measured with `Tools/metadata-fuzz.py` (seeded, deterministic —
  `libSample.dylib`, 100 mutants, seed 1234): **49 crashes in 800 runs, 6.1%**,
  versus 2.5% for the container fuzz. All die with **empty stderr**:

  | section | signal | subcommands killed |
  |---|---|---|
  | `__swift5_protos` | SIGTRAP | **all eight** — no entry point survives (now contained) |
  | `__swift5_assocty` | SIGTRAP + SIGSEGV | dump, interface, analyze (now contained: walked by record layout, 2026-10-10) |
  | `__objc_methlist` | SIGSEGV | objc, objc --methods, disasm, xrefs, analyze (now contained for relative lists, 2026-10-10) |
  | `__swift5_mpenum` | SIGTRAP | objc, disasm, analyze (found 2026-10-10; contained the same day) |
  | `__swift5_fieldmd` | SIGTRAP | objc, layout, disasm, xrefs, analyze (found on `sample.release`, seed 4242; contained) |
  | `__swift5_proto` into code | SIGTRAP | dump, analyze (an in-file target inside `__text`; contained) |
  | `__swift5_builtin` | SIGTRAP | dump, interface, objc, layout (found on `libReconstruction.opt`, seed 777; contained) |
  | `__swift5_typeref` | SIGTRAP | dump, interface (symbolic references; contained, parsed only from names records point at) |
  | `__swift5_mpenum` spare bits | SIGTRAP | analyze (`Index out of range` on a mask the record cannot hold; contained) |
  | `__objc_selrefs`, `__objc_classlist`, `__objc_nlclslist`, `__objc_catlist` | SIGSEGV/SIGTRAP | contained: each slot's decoded target must land, aligned, in the section that kind of slot names |
  | `__objc_const`, `__objc_data` | SIGSEGV/SIGTRAP | contained: classes walked through their pointer fields only (table below) |

  **`sample.release`, seed 4242, 150 mutants: 114 → 76 → 28 crashes in 1200
  runs (2026-10-10).** The pointer *arrays* are now checked slot by slot:
  chained-fixup formats 2 and 6 decoded (binds checked against the import
  table, other formats declined), plain pointers read as addresses, and each
  rebase required to land (8-aligned for classes and categories) in the section
  that kind of slot names on 1,058 real thin binaries (453k selrefs, all in
  `__objc_methname`).

  **Then 28 → 0.** `__objc_const`/`__objc_data` interleave pointers with
  flags, sizes and offsets, so each class named by a class list is walked
  through the fields that are always pointers, and each must land where it
  does in all 44,323 classes of those 1,058 binaries:

  | field | lands in (rebase), else |
  |---|---|
  | class / metaclass `isa` | `__objc_data`, `__data` (8-aligned); metaclass also null/bind |
  | `superclass` | `__objc_data`, `__data`; null; bind |
  | `cache` / `vtable` | bind or null / null only |
  | `data` (low 3 bits masked) | `__objc_const` or `__objc_data` (both hold `class_ro_t`) |
  | `ro.name` | `__objc_classname`, `__cstring`, `__const` |
  | `ro.baseMethods` | `__objc_methlist`, `__objc_const`, `__objc_methname`; null |
  | `ro.ivars` / `baseProtocols` / `baseProperties` | `__objc_const`; null |
  | ivar layouts | `__cstring`, `__objc_classname`; null |
  | ivar list (entsize 32) | offset in `__objc_ivar`/`__const`/`__data`/`__common`/`__bss`; name in `__objc_methname`/`__cstring`; type in `__objc_methtype`/`__cstring` |
  | property list (entsize 16) | name and attributes in `__objc_methname`/`__cstring` |

  A raw zero is a null field outside every fixup chain, not a rebase to the
  image base (the first prototype got this wrong and misread 3,000+ nulls).
  Measured: both metadata fuzz sets now 0 crashes (`libSample.dylib 100 1234`:
  0/800; `sample.release 150 4242`: 0/1200), the container fuzz 0/120, 0 false
  rejections on the 1,058 binaries, and every one of the 48 class-walk
  rejections in the two fuzz sets names a field the mutation changed.

  **A third binary and seed (`libReconstruction.opt.dylib 150 777`): 44 → 0.**
  It found `__swift5_builtin`, `__swift5_typeref`, the multi-payload enum
  spare-bit mask, a bind planted in a `class_ro_t` field, and a corrupt
  metaclass `class_ro_t`. Binds never occur in any `class_ro_t` field or list
  entry of the 1,058 binaries (only in `cache`, `superclass` and the metaclass
  `isa`/`superclass`), so they are refused there, and metaclass read-only data
  is walked like a class's.

  **A resilient build (`libReconstruction.resilient.dylib 150 31`): 6 → 0.**
  Two `__swift5_proto` mutants aimed a conformance entry into the middle of a
  descriptor. Descriptors are 4-byte-aligned records: every entry of
  `__swift5_proto`/`__swift5_types`/`__swift5_protos`/`__swift5_types2` in the
  1,058 binaries (556,643 of them) targets an aligned word, so a misaligned
  target is refused.

  **A fresh seed on the executable (`sample.release 150 99`): 10 → 0.** Both
  mutants flipped `next` bits of a chained pointer (`__objc_selrefs`,
  `__objc_data`). The chain then skipped slots, and MachOKit read a skipped
  slot's raw chained bits as a plain address, so a MachOObjCSection `try!`
  trapped. Preflight walks every fixup chain the way dyld does, from each
  page start, refusing one that leaves its page, lands on a slot that is not
  4-byte aligned, or binds past the import table. It records the slots the
  chains reach, and a nonzero Objective-C pointer slot or class field
  outside them is refused. Measured: every one of 3.94 million ObjC
  pointer-array slots in the chained images of four corpora (1,058 + 832
  thin, 1,434 arm64e system binaries, 1,609 universal binaries under
  /Applications) is a chain entry.

  **Universal binaries were not checked at all until 2026-10-10.** Every
  section-content check ran only for thin files, so a fat file's slices
  reached MachOKit with nothing but their headers validated: the selref
  mutant above, wrapped by `lipo -create`, still trapped in
  `objc --arch arm64` (exit 133). Each 64-bit slice now goes through the
  same checks as a thin image. Sweeping fat files surfaced three false
  rejections in the thin-only rules (tagged `__swift5_types` entries,
  x86_64 ObjC layouts, packed x86_64 chains), each fixed in its own commit,
  and a symlink-sizing bug that refused `/usr/bin/ex` and 46 other system
  binaries. 0 rejections over the 4,933-binary sweep afterwards.

  **arm64e images were walked for the first time on 2026-10-10.** Preflight
  decoded only the 64-bit pointer formats 2 and 6, so the ObjC checks skipped
  every arm64e image (formats 1, 9, 12). With the decoder in place, the first
  metadata fuzz of an arm64e binary (the arm64e slice of Stickies,
  `metadata-fuzz.py ... 60 11`) found 17 crashes, all in `__objc_protolist`,
  which was never checked. The protocol and reference arrays are now checked
  slot by slot, and each protocol the lists name is walked through its
  pointer fields like a class. 17 → 0, with 0 rejections over the 4,933
  binaries.

  Dead ends, recorded so they are not retried. Requiring 8-byte-aligned slots
  (true of all 10.6 million arm64 slots measured) refuses Electron
  Framework, whose x86_64 slices pack pointers at 4-byte offsets. Requiring
  rebase targets inside the image refuses `/usr/libexec/fairplaydeviceidentityd`,
  which dyld loads with 690 rebases pointing outside it (`dyld_info -fixups`).

  Dead end, recorded so it is not retried: `__swift5_typeref` is **not** a
  plain table of mangled names. Current toolchains place 16-byte-aligned binary
  records between the names, and walking the section front to back misread
  them as symbolic references, falsely rejecting 130 of 832 real binaries (in
  both file and VM space). Names are parsed only from the starts the
  field-descriptor, associated-type, builtin and multi-payload-enum records
  point at, by the grammar in `docs/ABI/Mangling.rst`, with references
  resolved in VM space (an indirect one names a GOT slot in `__DATA_CONST`,
  16 MB from its file offset in Xcode's frameworks). Those slots are chained-fixup-encoded, and
  `__objc_const`/`__objc_data` interleave pointers with flags, sizes and
  ivar offsets, so a flat "every word is a pointer" scan would reject valid
  files. Containing them needs a struct-aware walk (`class_t`, `class_ro_t`,
  category, protocol lists) over decoded chained-fixup targets, a larger
  piece than the relative-pointer layouts above. `libSample.dylib`, seed
  1234: 0 crashes in 800.

  **2026-10-10: 0 crashes in 800 runs** at the same settings (`metadata-fuzz.py
  libSample.dylib 100 1234`), after `__swift5_assocty` and `__swift5_mpenum`
  were walked by record layout and relative ObjC method names were checked
  against `__objc_selrefs`. Each rule was swept against real thin binaries
  carrying its section with 0 false rejections (401 / 432 / 571 binaries; the
  method-list walk covered 504,037 relative names).

  `disasm` is among them. Container corruption never reached it because
  llvm-objdump rejects the file first, but metadata is parsed in-process, so that
  shield does not apply here.

  **At least five sections are affected, not three.** A second seed (20 mutants,
  seed 999) found `__swift5_types` — again killing all eight subcommands — and
  `__swift5_fieldmd`, neither of which the first seed reached. Its yield was
  21.9%, though on a much smaller sample. The section list below is therefore a
  lower bound on the blast radius, not an inventory; whichever sections a seed
  happens to hit is what it reports.

  Two distinct dependency defects, from backtraces:

  1. **A negative resolved offset traps instead of being rejected.**
     `MangledName.resolve` → `MachOFile.readElement(offset:)` → `numericCast` →
     `Negative value is not representable`. The bounds check *already exists* —
     it is simply performed after an unsigned conversion. Proven by a controlled
     test on one relative pointer: `+32767` (out of range) returns
     `Error: offsetOutOfBounds` and exit 1, while `-32767` SIGTRAPs. Note the fix
     is **not** "reject negative": `-1024` resolves in-bounds and exits 0,
     because relative pointers legitimately point backwards. The check must
     happen on the resolved absolute offset, before conversion.
  2. **An unbounded string read walks off the mapping.**
     `ObjCMethodList.indirectMethod` and `AssociatedTypeRecord.name` →
     `readString(offset:)` → `strlen` → SIGSEGV.

  **Contained for the flat pointer tables.** `MachOPreflight` now validates
  `__swift5_protos`, `__swift5_proto`, `__swift5_types` and `__swift5_types2`:
  each is a bare array of 4-byte relative pointers, so `target = pointerOffset +
  value` must land inside the file. No record layout is modelled, and sign is not
  the test — every entry in every real fixture is *negative*, pointing backwards
  into `__TEXT`, so a validator that rejected negative deltas would refuse every
  Swift binary in existence.

  Measured across three seeds, before → after:

  | seed | mutants | before | after |
  |---|---|---|---|
  | 1234 | 100 | 49 crashes (6.1%) | **22 (2.8%)** |
  | 999 | 20 | 35 (21.9%) | **8 (5.0%)** |
  | 424242 | 40 | 14 (4.4%) | 14 (4.4%) — hit only uncovered sections |

  Sections are read individually rather than from the 1 MiB header prefix:
  metadata sits after the code, so in any real app it lies far beyond that
  window, and validating only the prefix would leave exactly the large binaries
  unprotected. Verified on a 36 MB binary whose tables hold 4,033 entries.

  **The covered list was not widened by measurement, though it was tempting.**
  On real binaries `__swift5_assocty` and `__swift5_capture` also have every
  int32 resolve in-file, which looks like the same flat shape. They are
  structured records, and some of those int32s are *counts*, not pointers — they
  resolve in-file here only because the counts are small and the sections sit far
  into the file. A large count in a small binary would be rejected as an
  out-of-range pointer, refusing a valid input.

  **Still OPEN**, and the residue was measured rather than estimated. Across
  four seeds (220 mutants) the sections still crashing are `__swift5_assocty`
  (20), `__objc_methlist` (10), `__swift5_fieldmd` (8), `__swift5_builtin` (6)
  and `__objc_const` (5) — **five sections, and more would surface with more
  seeds**. Extending the section-by-section approach is therefore a treadmill
  with no defined end, which is why it was not continued.

  **The one-guard upstream fix was tested, not assumed.** Applying
  `guard offset >= 0 else { throw ReadingError.invalidAddress(offset) }` to the
  seven read entry points of `MachOSwiftSection` (via `swift package edit`, then
  reverted) removes **49 → 21 crashes, ~57%**, with no regression on any fixture
  or on a 36 MB real binary:

  | seed | mutants | before | with the guard |
  |---|---|---|---|
  | 1234 | 100 | 22 (2.8%) | 10 (1.2%) |
  | 999 | 40 | 8 (2.5%) | **0 (0.0%)** |
  | 424242 | 40 | 14 (4.4%) | 6 (1.9%) |
  | 7 | 40 | 5 (1.6%) | 5 (1.6%) |

  Written up as [docs/upstream-negative-offset.md](upstream-negative-offset.md),
  ready to file. Not fixed in-tree: the fix belongs in the dependency, and
  forking would take swiftdc off upstream — a maintainer's decision, not a side
  effect of a bug hunt.

  The residue after that guard is two further defects, both distinct: an
  **unbounded `strlen`** in `readString(offset:)` (SIGSEGV, needs a length bound
  rather than a sign check), and **`MachOObjCSection`**, which has the same
  unsigned-conversion shape and was not patched — every surviving SIGTRAP is in
  `__objc_methlist` or `__objc_const`, which it parses.
- **MITIGATED — metadata fuzzing is now repeatable, not hand-run.**
  `Tools/metadata-fuzz.py` is seeded and deterministic for a given
  (binary, mutants, seed), covers all eight metadata-reading subcommands, and
  exits nonzero when any mutant kills the CLI — so it can become a gate the
  moment the class above is contained. It is not yet wired into CI.
- **OPEN — fuzzing is bounded and manual; metadata parsers are unprobed.** The
  prediction that the `try!`-in-a-dependency pattern would recur in load-command
  payloads was tested and **held** — 12 crashes across four subcommands, now
  fixed. A 120-mutant fuzz over the load-command region has since been run
  (2.5% crash yield, all in the uncontainable class). `__swift5_*` and
  `__objc_*` **metadata** parsing has since been probed and is crashing — see the
  metadata entry above (6.1% yield, three sections, one of which kills every
  subcommand). **Fat slice thin headers** — flagged here as unprobed — were then
  probed and **crashed**: a slice whose *extent* is in-bounds but whose thin
  Mach-O header lies (`sizeofcmds` claiming load commands past the slice) passed
  preflight and trapped in `MachOKit/MachOFile.swift:61` when `fat.machOFiles()`
  parsed it. Confirmed by corrupting a real fat binary (`/bin/ls`). **Now
  fixed**: `MachOPreflight` validates each slice's thin header against the
  *slice* size, with the same two consistency checks `validateThin` applies to a
  top-level header (`FatSlicePreflightTests`; both directions proven — the crash
  test observed "killed by signal 5" without the fix, the over-rejection test
  observed a valid `/bin/ls` slice being refused when the check was made
  over-eager). Still unprobed: anything beyond the 1 MiB preflight read prefix
  that is not a fat slice or a validated relative-pointer table. Nothing runs in
  CI.
- **MITIGATED — behavior across optimization levels.** The differential oracle
  now runs at both `-Onone` and `-O` (318 comparisons each), executing the
  recovered expression against the real compiled function at each level. This is
  the level where lowering genuinely diverges: `-O` turns a signed range check
  into one unsigned compare, folds branches into `csel`, commutes operands, and
  optimizes some functions away entirely. Scoped to the scalar domain the oracle
  covers — it says nothing about optimized lowering of strings, payload enums,
  or side-effecting code.

## 4. Determinism

- **MITIGATED — output is stable across runs.** Three consecutive
  `disasm --structured` runs over the fixture hash identically:
  `for i in 1 2 3; do swiftdc disasm Fixtures/Sample/libReconstruction.dylib --structured | shasum; done`
  Tests additionally pin a shared symbol-index store (`withStableDependencies`),
  which suggests dependency-injection order once mattered.
- **MITIGATED — determinism is enforced across processes, and the stated risk
  was wrong.** This entry used to blame concurrency: "the pipeline is `async` …
  scheduling varies more". Checked at HEAD: the decompiler has **no concurrent
  fan-out at all** — no task groups, no `async let`, no `Task {}`, no
  `concurrentPerform` — and the single large-stack worker thread is joined before
  its result is read. `async` here is sequential I/O, not parallelism, so
  scheduling is not a source of variation.

  The actual dependency is **~16 explicit `.sorted()` calls** placed where an
  unordered collection reaches output. Nothing enforced them, so emitting
  straight from a `Dictionary` or `Set` in a future change would reorder output
  silently.

  `DeterminismTests` now compares four runs of six subcommands — Swift metadata,
  the ObjC index, field layout, the call graph, and structured disassembly.
  It must run them as **subprocesses**: Swift seeds `Hasher` per process, so
  `Set`/`Dictionary` order is permuted *between* runs but constant *within* one.
  Repeating a call in-process would reuse the seed, reorder nothing, and prove
  nothing.

  Proven to have power, not merely green. Deleting the real `.sorted()` from
  `CallGraph.unreferenced()` fails it immediately, with the signature that
  identifies reordering rather than a content change:

      xrefs --unreferenced: run 2 differs from run 1 (29537 vs 29537 bytes)

  A companion test asserts the premise itself — that iteration order really does
  vary between processes on this toolchain. If a future toolchain made hashing
  deterministic by default, the guard would keep passing while having lost all
  of its power, and that should be visible rather than silent.

## 5. Performance and memory on large frameworks

- **OPEN — `xrefs` on Swiftcord exceeds 8 GB.** The ship2 sweep stopped
  `xrefs --unreferenced` at the RSS ceiling after 112.8 s (8,636 MB); the
  earlier merge sweep peaked at ~7.8 GB. Unprofiled.
- **FIXED — a standalone binary re-opened itself as a dyld cache on every
  `MachOFile.cache` access.** The 0.22 upgrade dropped the fork that memoized
  the failed load, estimating it at about 2.5% of a Keynote `dump`. On a
  Swift-heavy app it dominated: Time Profiler, attached 90 s to `dump --arch
  arm64` on Prime Video (296 MB), put 71.5% of samples under
  `MachOFile.cache.getter` -> `DyldCache.init(url:)` (`__open` 37.5%, `__munmap`
  19.4% self), reached once per relative-pointer resolve in 0.22's class
  dumper. Re-pinned to `CamdenBopp/MachOKit` 4c4738f (0.54.101 plus the
  three-line memo, `3608e37`). Back to back at matched load: `layout` 69.9s to
  4.4s, `dump` 168s to 77s, `interface` 240s to 74s, `objc` 610s to 375s, all
  byte-identical (`cmp`). SwiftPM warns the fork and MachOObjCSection's upstream
  URL share the identity `machokit` and says it will become an error.
- **OPEN — `xrefs`/`disasm` pay for a full Swift class dump to name vtable
  slots, and 0.22 made that dump walk every class's ObjC ancestors.**
  `MetadataSymbolizer.classMethodNames(in:)` renders the whole `.types` dump and
  scans it for `sub_` addresses. Under 0.22, `ClassDumper.body` resolves each
  class's ObjC ancestor chain unconditionally (no configuration skips it). Fiery
  Feeds `xrefs --unreferenced`: origin/master 153.5 s, HEAD 966.5 s, same
  output size class. `sample` (20 s, 60 s in): 3,850 of 6,884 command-thread
  samples under `classMethodNames`, 1,429 under
  `ObjCClassMethodIndex.ancestors`, whose hot frames are MachOKit re-deriving
  cache structures per call: `DyldCache._machO(at:)` 685,
  `_headerOptimizationRO64` 619, `_objcOptimization` 261. Two independent
  fixes: name vtable slots from the method descriptors directly (no dump), and
  memoize those `DyldCache` derivations in the MachOKit fork (both the old and
  new ObjC-optimization formats).
- **DEAD END — reserving the decode array once at the text bound.** A memory
  sample at 7 GB in Swiftcord `xrefs` put every frame in `decodeText` ->
  `CapstoneEngine.append` -> `_ArrayBuffer._consumeAndCreateNew`, and
  `append` reserves `results.count + batch` per Capstone batch. Hypothesis: the
  exact-size reserve defeats geometric growth. Replacing it with one
  `reserveCapacity(code.count / 4)` was worse at matched settings, alternating
  runs, `disasm --structured --arch arm64` UTM: baseline 47.7 s / 1.9 GB and
  45.8 s / 2.7 GB, candidate 53.2 s / 2.9 GB and 48.7 s / 3.0 GB, output
  byte-identical. The up-front bound allocates for every word, data included.
  Reverted; do not retry. The Swiftcord peak itself (7.8 GB, sawtooth between
  ~2 and ~7.6 GB) matches origin/master's 7.85 GB.
- **OPEN — whole-image `xrefs`/`disasm`/`analyze` exceed 30 minutes on a 296 MB
  app.** Prime Video, release build: `xrefs --unreferenced` and `disasm
  --structured` both hit the sweep's 30-minute cap (5.7 GB and 6.8 GB peak).
  origin/master never finished either (it trapped at 488 s and 569 s, see
  Robustness), so there is no baseline. `sample` early in `xrefs`: whole-image
  Capstone decoding (`CapstoneEngine.append`, Capstone 6's `matchAliasPatterns`)
  plus malloc/free. Whether Capstone 6 decodes slower than the Homebrew
  Capstone 5 it replaced is **UNKNOWN**: the migration measured byte-identical
  output, not speed.
- **OPEN — the MachOSwiftSection 0.22.0 pin makes `dump`/`interface`/`objc`
  on standalone ObjC-heavy apps 7x to 40x slower, upstream.** Measured with
  the same binary set before and after the pin (times under build load, so
  indicative; the `sample` attributions are not): Keynote `dump` 1.35s to
  20.2s, `interface` 1.36s to 24.4s, `objc` 60s to 2,424s; GoodLinks `dump`
  7.4s to 54.5s, `objc` 10.4s to 106s; peak RSS roughly doubled. Two causes,
  both in the dependencies: (a) 0.22's class dumper resolves each class's ObjC
  ancestor chain inside the system dyld cache, and MachOKit's
  `DyldCache.locateValue` re-reads `headerOptimizationRO64` / `mappingInfos`
  on every call (3,235 of 5,225 samples under
  `ObjCClassMethodIndex.ancestors` on Keynote `dump`); (b) MachOObjCSection
  0.8.110's `info(in:)` resolves referenced protocol infos recursively, each
  method slot through a fixup lookup (2,448 of 5,560 samples under
  `referencedProtocolInfos` on Keynote `objc`). The dropped MachOKit fork
  memoisation was estimated here at about 2.5% of a `dump`; on Prime Video it
  was 71.5%, and it is restored (see the FIXED entry above). Cache images are faster
  (SwiftUICore `dump` 228s to 160s, `interface` 260s to 163s, `objc` 70s to
  35s, same load caveat). Candidate fixes: memoise the `DyldCache` header
  parsing in MachOKit; pass `ObjCInfoOptions.headerDump` from swiftdc's own
  `objc` path if its output stays byte-identical. Profiles:
  `sample <pid> 8` on `dump --arch arm64 Keynote` and `objc --arch arm64 Keynote`.
- **OPEN — whole-image decoding does not scale to the largest frameworks.**
  Measured after the resync fix: `disasm --image UserNotifications` recovers
  1,391 functions / 52,103 instructions in **19s**, with no coverage warning.
  SwiftUI, at 105,644 recovered functions and 5.65M instructions, took
  **6m03s** before streaming — now **2m37s** (streaming no longer thrashes swap),
  but still slow for interactive use. Streaming fixed the *memory* (see the FIXED
  entry below), not the decode/analysis *time*.

  This cost was previously *hidden by the truncation bug*: stopping after 4,040
  instructions made SwiftUI look fast. Fixing completeness exposed the real
  workload, which is the correct trade (a fast wrong answer is worth nothing)
  but leaves unfiltered runs on the largest images slow.

  Not pathological — the resync loop was checked for a degenerate
  one-call-per-4-bytes case on a large data region and UserNotifications shows
  none. It is the per-instruction analysis pipeline, run over ~75× more code.
  `--function` remains fast on any image, since it decodes only matched ranges.
- **FIXED (memory) — whole-image text output is now streamed, ~8–10× less peak
  memory, and the largest frameworks fit in RAM.** `disasm --image X` in the
  text/`--structured`/`--pseudo`/`--cfg` modes now decodes, analyses, renders and
  **releases one function at a time** (`disassembleStreamingRender`), instead of
  holding the whole image's decoded instructions at once. Measured before → after
  (`/usr/bin/time -l`, release, peak footprint):

  | image | instructions | before | after | factor |
  |---|---|---|---|---|
  | CoreLocation | 473,670 | 1,192 MB | **117 MB** | 10× |
  | SwiftUI | 5,654,282 | 13,794 MB | **1,633 MB** | 8.4× |

  SwiftUI **no longer exceeds a 16 GB host** — 1.6 GB fits in RAM, and it also
  ran *faster* (2m37s vs 6m03s) because it no longer thrashes swap. The residual
  is O(function count), not O(instructions): the cross-function name index
  (~105 k demangled names + resolver for SwiftUI) is what remains resident, and
  `--json`/`xrefs`/`analyze` — which genuinely need every function — keep the
  array path and its old footprint (verified unchanged: CoreLocation `--json`
  still 1,241 MB, the control).

  Output is **byte-identical** to the array path — verified on
  `disasm --image UserNotifications` across all five modes (text, structured,
  pseudo, cfg, json) against pre-refactor golden hashes — because the streaming
  path reuses the same `makeFunction` naming and the same `analyzeFunction`
  analysis, and boundaries are instruction-aligned so its spans are exactly the
  functions `segment` cuts. The foundation (extracting `analyzeFunction`, so both
  paths share one code path rather than a parallel reimplementation) landed
  separately in `09d9026`, itself golden-verified.

  How the cause was localised, for the record (an earlier version of this entry
  reasoned it was `detail`; that was measured false). Four candidates ruled out
  on CoreLocation, each leaving 1,192 MB unchanged: stripping `detail` at decode;
  the rendered output (only 16 MB); skipping value-tracking; and returning the
  raw decoded list with no `assemble` at all — the last proving the entire peak
  is present the instant `__text` is decoded. The held whole-image instruction
  list was the cost; streaming holds one function's worth.

  Reproduce:
  `/usr/bin/time -l swiftdc disasm --image CoreLocation >/dev/null` (streamed) vs
  `… --json >/dev/null` (array) — read `peak memory footprint`.
- **OPEN — time, and the array modes, still scale with the whole image.**
  Streaming fixed peak *memory* for text output but not *time*: CoreLocation
  still takes ~23 s (the decode + per-function analysis work is unchanged, just
  no longer all resident). And `--json`/`xrefs`/`analyze` still materialise every
  function, so their memory is unchanged by design — a streaming JSON writer, or
  chunking the array modes, is the remaining scale work.
- **MITIGATED (memory) — a whole-image memory regression guard now exists**
  (`MemoryRegressionTests`). The memory limit above is now FIXED by
  streaming, but nothing stopped it regressing meanwhile, and it still guards the
  array path (`--json`) that keeps the old footprint: an
  added held field on `Instruction`, or an extra retained copy of the list,
  would balloon per-instruction memory silently. The guard runs
  `disasm --image UserNotifications --json` under `/usr/bin/time -l` — an
  **external** oracle, process accounting rather than any number swiftdc reports
  about itself — and asserts `peak footprint ÷ instruction count` stays under
  **5,632 B** (~1.6× the measured ~3,400 B/instruction baseline, so it trips on a
  doubling-class regression, not the ~4% run-to-run variance).

  Proven to have teeth, and the proof taught the boundary. A first injection —
  two extra `map { $0 }` copies of the instruction list — did **not** trip it,
  because `Instruction`'s String/`detail` heap buffers are copy-on-write, so the
  copies shared bytes rather than allocating them. That is correct: retaining
  references to the same instructions is not a memory regression. Injecting a
  genuine per-instruction allocation (3 KB of fresh bytes each) did trip it, at
  6,025 B/instruction. So the guard catches the realistic regression — a new
  held field carrying heap data — while ignoring reference retention.

  Host-gated: it needs a system dyld cache image and skips cleanly without one
  (a skip is instant; the passing run takes ~18 s, which confirms it measured).
  It was the **before/after oracle for the streaming refactor** (measured
  10× on CoreLocation); it now guards the `--json` array path against regression.
- **MITIGATED (memory) — the streaming text path has its own guard**
  (`streamingWholeImageMemoryStaysLowIfPresent`). The `--json` guard above bounds
  the array path; this bounds the path the refactor created —
  `disasm --image CoreLocation` (no `--json`), which decodes, analyses, renders,
  and **releases** one function at a time. Same external oracle
  (`/usr/bin/time -l`), an absolute ceiling of **200 MB** on peak footprint.

  The bound is calibrated by injection, not guesswork, and the calibration
  corrected a wrong first threshold. Measured on CoreLocation (debug): clean
  streaming **123 MB**; accumulating every analysed `DisassembledFunction` instead
  of releasing it — the realistic regression — **261 MB**; the `--json` array path
  **1,192 MB**. The array-path figure is a red herring here: it is dominated by
  `JSONSerialization` boxing every field, *not* by held function objects, so a
  "well under 1,192" bound (e.g. 500 MB) would sail past the actual failure mode,
  which tops out at 261 MB. 200 MB splits the two — ~1.6× over the 123 MB baseline,
  under the 261 MB a hold-every-function regression reaches. Proven both
  directions: the injection trips it (262 MB), the clean path clears it (123 MB).
  Host-gated on CoreLocation; ~60 s, skips cleanly without the cache.
- **UNKNOWN — no wall-time regression guard.** The memory guard above covers
  allocation; nothing guards decode *time*, which is deliberately left to a
  measured OPEN rather than a test — wall time is too machine- and load-dependent
  to assert as a stable bound without flaking.

## 6. Usability — are commands, diagnostics, and docs accurate?

- **FIXED — three README defects.** A documented command that errors
  (`--sections types,protocols` is space-separated); an entire undocumented
  subcommand (`layout`, including the `--self-index` flag that produces numbers
  the README cited); a stale measurement (49/33 → re-measured 60/39). `f549857`.
- **FIXED — the ambiguous empty-result message.** `// No functions matched.`
  covered three distinct causes including a parser failure. Now distinguishes
  "no function matched `<filter>`" from "this binary contains no recoverable
  functions", and an analysis failure throws instead.
- **FIXED — an empty `--function ""` meant opposite things.** `disasm` and
  `objc` matched every function; `xrefs` matched none and printed `// No
  function matched ''.` with exit 0. Every command that takes `--function`
  now rejects an empty name as a usage error. Test:
  `everyFunctionFilterRejectsAnEmptyNameIfPresent`, which finds the commands
  from their help text.
- **FIXED — two stale doc artifacts.** A fixed defect still headlined
  `CONFIRMED DEFECT`; a shipped feature still described as "a scoped follow-up".
- **MITIGATED — exit codes are correct** except the crash above: success 0,
  bad input 1, filter-miss 0.
- **MITIGATED — whole-image `disasm` shows live progress.** A `disasm --image X`
  run is minutes long on a large framework and used to be silent, reading as a
  hang. The streaming path now reports `decompiling <done>/<total> functions…` on
  stderr, updated in place, and erases the line when done. Gated on
  `isatty(stderr)`: a redirected or piped stderr stays clean for scripting
  (verified: 0 stderr bytes when piped), and **stdout is untouched** (golden
  hashes unchanged across all five modes). Verified through a pty that the line
  advances to the total and clears. The other slow paths (`objc --image
  Foundation`, and the array `disasm` modes) do not yet report progress — this
  covers the streamed whole-image text modes only.

## 7. Reconstruction quality — how source-like is the output?

Real, but last. Everything above must hold first.

- **OPEN — L1: locals are inlined, not promoted.** `let a = x+1; let b = a*2;
  return a+b` renders `((arg0 + 1) + ((arg0 + 1) * 2))` — value-correct, but
  subexpressions are recomputed and no named locals exist. Ghidra promotes stack
  slots to `HighVariable`s. A design gap, not a bug.
- **OPEN — S1: struct-parameter decomposition is method-only.** Small integer
  structs decompose in getters (`e1a3b6a`, `73eaf73`); free-function HFA params
  (`dot(p: Point, q: Point)`) still decline.
- **OPEN — closures, existentials, generic witnesses, `throws`** render as
  low-level runtime calls rather than reconstructed control flow. Honest
  declines; large surface. A generic or existential *result* in particular
  still declines its `return`: the x8 pointer escapes into the value-witness
  call, or the type has no stored-property layout to cover (`identity<A>`,
  `asAny` in the indirect fixture).
- **MITIGATED — `async` functions.** Each funclet of an async function is
  grouped under its entry (see Completeness), and on the `-O` build the body
  reads as source: `let awaited1 = await AsyncFns.fetchValue(arg0)` in the
  entry, `return (awaited1 + awaited2)` in the last funclet, an executor hop
  as `await hop_to_executor(generic)`, and a parameter reloaded from the async
  context as `arg0` (`04682ec`). Every claim carries a proof: the return is a
  `br` through the context's ResumeParent that the tracer followed from the
  seeded x22; the awaited result is seeded only when the callee's signature
  proves a single-register result; a context slot is named only when exactly
  one store in the whole chain reaches it and the value is portable. What is
  still declined, by design: `-Onone` funclets reload the context through
  stack spills the chain pass does not follow, so their returns print no
  value (pinned by `declinesUnprovenAsyncReturnsAtOnoneIfPresent`); the error
  register at an await-return funclet is left as a raw register (`x20 == 0`);
  an executor obtained from an actor's `unownedExecutor` renders
  `hop_to_executor(?)`; and a value spilled twice to the same slot is never
  named. Repro: `swiftdc disasm --structured -f twoAwaits
  Fixtures/Sample/libAsyncFns.opt.stripped.dylib`.
- **PLATEAU — condition naming.** ~70% of raw-register conditions are compiler
  plumbing (value witnesses, generic specializations, Codable machinery) with no
  source-level named value to recover. Investigated and documented as
  coverage-bound in `docs/research/field-map-name-collision.md`. Not a tractable
  slice; do not re-mine it without new evidence.

## 8. Validation — what independent oracle checks each subsystem?

The meta-category. Every gap here weakens confidence in every claim above.

| Subsystem | Oracle | Status |
|---|---|---|
| Function boundaries | `LC_FUNCTION_STARTS` | **Enforced** — throws on empty parse, warns below 50% recovery. The count is deduped and cross-checked against `dyld_info` in tests |
| Byte-level decode coverage | `dyld_info -function_starts` extents | **In tests + measured by hand** — 100.000% of declared slots decode; no holes inside bodies on either decoder |
| Peak memory | `/usr/bin/time -l` peak footprint | **Measured + guarded** — linear ~2.5 KB/instruction; SwiftUI 13.5 GB exceeds a 16 GB host; `MemoryRegressionTests` bounds per-instruction footprint |
| Instruction decode | `llvm-objdump` vs in-process Capstone | Two independent decoders exist; **nothing cross-checks them**. Both silent-truncation bugs found so far were in whichever decoder the other wasn't covering |
| Enum tag → case index | SIL (`swiftc -emit-sil`) | Used once, manually, to confirm the `rank` lowering |
| Field offsets | `__swift5_fieldmd`, computed offline | Runtime-exact by construction |
| Cross-image symbols | export trie | Used as the primary source |
| Recovered semantics | the compiled function itself, called via `dlsym` | **In tests** — 1,264 comparisons at both `-Onone` and `-O`: 636 integer/boolean (catches an injected U1) and 628 floating point (catches a one-ULP constant error). Narrow: no strings, payload enums, or side effects |
| Async funclet grouping | the unstripped symbol table (`…TQ<n>_` / `…TY<n>_` suffixes) | **In tests** — parent, ordinal and kind of all 14 funclets on three builds, and the stripped build must match address for address; the code-only fallback is checked against the same oracle |
| Malformed-input handling | the CLI's own exit status, checked from a subprocess | **In tests** — 9 header-shaped inputs; no fuzzer, no malformed metadata |
| Whole-binary output | — | **None.** No golden-output corpus, so a silent regression on a real framework would not be noticed |

The two decoders being cross-checkable against each other is the cheapest
unexploited oracle in the project: the objdump path and the Capstone path decode
the same bytes, and the bug in `d1ca94f` existed precisely because only one of
them was ever exercised end to end.

---

## How to use this document

Pick the highest-risk **OPEN** or **UNKNOWN** item you have evidence to move.
Update its status in the same commit that changes the behavior, and record the
evidence — a command, a commit, or a file:line. An item may only be marked FIXED
if a test was observed to fail without the fix.

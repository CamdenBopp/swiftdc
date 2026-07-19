# Blank computational bodies on the self-host (probe + first fix)

> Findings for the user-chosen area: functions rendering `// no non-runtime calls
> (leaf / pure computation)`. Probe + first fix at repo `e1a3b6a`.

## The 36,287 blank bodies, by function kind

| Kind | count | Verdict |
|---|---|---|
| value witness | 7,035 | **compiler plumbing** — not source; should stay blank |
| protocol witness | 6,690 | **compiler plumbing** |
| type metadata accessor | 1,719 | **compiler plumbing** |
| getter | 4,120 | real code — the tractable slice |
| resume / modify / read (coroutine accessors) | ~4,000 | hard (coroutine ABI, x21-pointer self) |
| `.init(` | 1,404 | real code — field assignments |
| setter | 690 | real code — `self.field = arg` |
| == infix / hash / description / append / … | rest | mixed |

**~43% (≈15.4k) are compiler plumbing** (value/protocol witness, metadata) that
*should* be blank — they are not user source. The current message ("leaf / pure
computation") is misleading for them; labeling plumbing accurately (vs. genuinely
unreconstructed user code) is a possible honesty pass, but it is relabeling, not
reconstruction.

## Fixed: small integer-struct getters (commit `e1a3b6a`)

Class getters and large-struct getters (indirect self via x20) already rendered
`return self.field`. The blank slice among getters was **small integer structs**
(≤16 bytes, `Int`/`UInt` fields) whose `self` is passed decomposed in general
registers x0/x1 — only float-HFA self (SIMD) was decomposed. Now `IntPair.sum` →
`return (self.a + self.b)`. **Impact small** on the self-host (blank 36,302 →
36,278; self.field returns 659 → 682 on the same target) — swiftdc's own code has
few small integer-struct getters; the win is on Swift code that uses small value
structs (points, ranges, wrappers).

**Safety catch:** a value-type METHOD with parameters passes `self` AFTER the
formal params in the shared GPR bank (`k=x0, self=x1/x2`), an order not modeled —
decomposing it mis-reconstructs a non-commutative body (`a*k+b`). So methods with
parameters DECLINE (adversarial-tested), and the fix is scoped to getters.

## Remaining, ranked

1. **Setters (690)** and **`.init` (1,404)** — real field assignments. A class
   setter already renders `self.value = …` but the RHS (newValue arg) is
   unresolved; resolving it, and rendering init field stores, is the next
   tractable reconstruction slice.
2. **Small-struct METHODS with params** — needs the self-after-params GPR order
   modeled (also fixes the same latent question in the float-HFA path, currently
   hidden by mul commutativity).
3. **Plumbing labeling (≈15k)** — relabel value/protocol-witness/metadata bodies
   accurately instead of "leaf / pure computation" (honesty, not reconstruction).
4. **Coroutine accessors (~4k)** — hard (x21-pointer self, resume ABI).

**Pattern across this session's incremental fixes** (enum-tag, tbz, small-struct):
each is correct and fixture-proven but has small self-host impact, because
swiftdc's own code doesn't exercise these shapes much. x21 (−6.5k conditions) was
the outlier big win. The remaining gaps are genuinely incremental.

## Follow-up probe: field STORES are already done; the gap is getters (`73eaf73`)

Probed the field-store slice this doc ranked #1. Finding: **the `self.field =
value` statement path already exists and works** — `fieldWrite` via
`selfFieldAccesses` renders `self.field = value` (proven) or `self.field = …`
(unproven RHS), and fires ~900× on the self-host. **Zero** blank setters in
swiftdc's own code. Every blank setter is a dependency struct that is either

- **missing a field map entirely** (`MachOSwiftSection.*.Layout`, `ProtocolDescriptor.Layout` — `swiftdc layout` returns nothing for them; both getters AND setters blank), or
- a **generic dynamic-offset store** (`str x0, [x20, x8]` where the offset is loaded from a witness table) — an indexed store `memoryTarget` correctly declines.

Both are correct declines. So the field-store slice needed **no** work.

The real tractable gap was **getters of multi-field structs passed decomposed in
general registers**. The Swift convention explodes an all-integer value across the
first FOUR registers x0–x3 (field at `8·n` in `x{n}`, confirmed:
`ExtensionIndexingResult.failed.getter`, field +0x18, is `mov x0, x3; ret`), but
the decomposer capped at 2 fields. Raising the cap to 4 (`FieldMap`
`wordIntegerFieldOffsetsInRegisters`, `(1...2)` → `(1...4)`, still gated on proven
`Si`/`Su`) closed the 3–4 field all-integer slice: −11 blank bodies on the
self-host (`MachOKit.Version.major/minor/patch`, the Swift index-result structs).

### Blocked behind a dependency prerequisite (scoped recommendation)

Two adjacent slices are **blocked**, both by the pinned MachOSwiftSection
dependency, and should NOT be patched locally:

1. **Register-decomposed structs with mixed/non-`Si` word fields** —
   `CallEdge.site/caller/callee.getter` (three `UInt64`, `ret`/`mov x0,x2`) and
   `BasicBlock.startAddress.getter` (`UInt64` + two `Array` fields) render blank.
   Their fields are word-sized and GPR-class, but their `typeMangledName` is
   **empty** (`swiftdc layout` shows `site: ` with no type). Empty names come from
   `SwiftLayout.StaticLayoutCalculator` in the MachOSwiftSection checkout, not
   swiftdc. Without a type name I cannot prove a field is integer-class rather
   than a `Double` (SIMD) — and the `x{n}=offset/8` mapping mis-maps a mixed
   int/float struct, which would **fabricate** a wrong field name. So this needs
   the dependency to surface primitive field type names first.

2. **`MachOSwiftSection.*.Layout` structs with no field map at all** — the largest
   blank-setter/getter population. Needs field-map coverage for those nested/
   generic layout structs, again in the dependency's layout calculator.

**Recommendation:** further computational-body gains here are gated on
MachOSwiftSection metadata quality (primitive type names + `Layout`-struct field
maps), not on swiftdc's rendering. That is a dependency-level prerequisite, out of
scope for a "smallest general change." The remaining swiftdc-local computational
blanks are plumbing (should stay blank) or coroutine accessors (`modify`/`read` —
x20-pointer self + resume ABI), which are a separate, larger piece.

## Re-survey — the tractable slices are mined (STOP + REPORT)

Fresh frequency table of the 23,102 blank bodies (new tool, fixed target):

| kind | count | verdict |
|---|---|---|
| protocol witness | 5,746 | plumbing — stay blank |
| value witness | 5,563 | plumbing |
| type metadata | 1,481 | plumbing |
| outlined copy/consume/destroy | 1,056 | plumbing |
| generic specialization | ~1,094 | plumbing |
| **.getter** | 3,489 | ~112 local; dependency-blocked / String / Bool / enum |
| **.modify / .read** | ~1,850 | coroutine `yield_once` ABI (below) |
| **.setter** | 371 | dependency field-map / dynamic-offset — declines |
| **== infix** | 261 | trivial single-compare — low information (below) |

**~65% is compiler plumbing** that must stay blank. The non-plumbing remainder is
each blocked or low-value:

- **`.modify` / `.read` coroutine accessors (~1,850)** — a `_modify` for a stored
  property is `mov x1, x20; adrp x0, →.resume.0; ret` (+ a `.resume.0: ret`). It
  yields the field's address via the `yield_once` coroutine convention; **which
  register carries the yielded `inout` address is the crux, and getting it from
  the instruction stream alone is a guess.** Even the trivial (frame-less, stored-
  property) sub-slice needs the authoritative yield_once ABI first — a prerequisite
  to *research*, not a smallest-general-change. Payoff is also partly plumbing
  (a stored-property `_modify` is compiler-synthesized, like its setter).
- **`== infix` (261)** — the blank ones are single-compare bodies
  (`ldrb w8,[x0]; ldrb w9,[x1]; cmp; cset w0,eq; ret`) on no-payload enums and
  one-field wrappers (`Bucket`, `Index`, `_Word`). They reconstruct to
  `return (arg0 == arg1)` — correct but ~zero information (it is the definition of
  a synthesized `==`). Multi-field struct `==` has branches, so it is not blank
  and already renders via the structured path.
- **`.getter` (3,489)** — after the register-decompose fix, the local remainder is
  String (16-byte / retainable), Bool (sub-word bitfield), enum, or collections;
  the dependency remainder is the empty-`typeMangledName` / no-field-map cases
  above. No clean local slice left.

**Correctness spot-check** (a mis-render outranks a blank): the self-host has no
fabrications — `(0 == 0)`/`(0 != 0)` (16) render a constant comparison literally
(correct, just unsimplified), and `(? …)` (33) are diffuse value-coverage gaps.
Folding tautologies and simplifying `(? …)` is cosmetic and low-value.

**Conclusion:** the "fill blank computational bodies with a small general change"
frontier is **mined**. Every remaining population is (a) plumbing that should stay
blank, (b) prerequisite-blocked (coroutine `yield_once` ABI; MachOSwiftSection
metadata quality), or (c) low-value (trivial `==`, cosmetic folds). Per the loop's
own guidance, STOP and REPORT rather than force a low-value patch.

**Proposed next area:** research the Swift `yield_once` coroutine ABI
authoritatively (the compiler checkout at `/Users/camden/swift` documents the
convention) to decide whether `_modify` / `_read` accessors — the single largest
unblocked population (~1,850) and a genuine Swift construct, not plumbing-only —
can be rendered without a full coroutine-frame model. Evidence-first, decline over
guess. If it needs the full frame/continuation model, that is the honest larger
prerequisite to scope next. Alternatives the user may prefer: a shift from body-
coverage to `--structured` control-flow readability, or accepting the current
plateau as good coverage.

## The `_modify` slice was NOT blocked — ABI research made it tractable (`a54f9cf`)

The proposed research paid off and **overturned** the "prerequisite-blocked"
verdict above. The authoritative source (`swiftlang/swift`
`lib/IRGen/GenCall.cpp` `expandCoroutineResult`) builds the yield_once ramp
result as `{ continuation, yields… }` — **continuation first**:

```cpp
SmallVector<llvm::Type*, 8> components;
components.push_back(IGM.Int8PtrTy);            // the continuation pointer
for (auto yield : FnType->getYields()) { … }   // yielded values follow
```

So on ARM64 the ramp returns **x0 = continuation** (→`.resume.0`) and **x1 = the
first yield**. For a stored-property `_modify` that yield is `&self.field`. Three
self-host disasm samples confirm it exactly (e.g. `Options.fieldOffsets.modify`:
`add x1, x20, #1`, which swiftdc already tags `&self.…`). This is not a guess.

**Implemented** (`a54f9cf`): `exitYieldValues` records x1 at each `ret`; a
`_modify` ramp renders `yield &self.field`; `pseudoStatement` surfaces a `yield …`
note. **−483 blank bodies** on a clean same-target self-host (MachOKit's resilient
`layout`/`offset` accessors dominate) — the biggest single computational-body win
of the session, and every render is correct.

**The safety that made it honest — a match-gate.** Render only when the
body-derived yielded field agrees with the accessor's own property name. This
caught a real fabrication hazard: `InterfaceReconstructor.Options.fieldOffsets`
mis-resolves `self` to a type with a bogus `rawValue` at offset 1, and an explicit
`_modify` can yield a differently-named backing field. On any mismatch it declines
rather than name the wrong storage. (`_read`, which yields a borrowed *value* not
an address, is intentionally left alone.)

**Lesson:** "prerequisite-blocked" is a claim to *test*, not assume. The block
here was my own lack of the ABI, not a missing capability — authoritative research
(the loop's own instruction) dissolved it. Only `_read` and the coroutine cases
that truly need a frame remain; those are the next thing to probe the same way.

## `_read` is an empty slice; the blank frontier is exhausted (pivot)

Probed `_read` the same way. It is the same yield_once shape as `_modify`
(`UncheckedSendable.wrappedValue.read`: `mov x1, x20; adrp x0, →.resume.0; ret`, so
x1 = `&self.field`). But the population is tiny and unreachable:

- **9** blank `_read` ramps on the whole self-host; **0** are swiftdc-local.
- All 9 are dependency generic / noncopyable wrappers (`ConcurrencyExtras`,
  `AsyncAlgorithms`, `DequeModule`) whose generic layouts have no concrete field
  map — the match-gate declines every one, so support would render **~0**.
- A resilient stored `var` emits `get`+`_modify` but **no** `_read` (borrow-read is
  only emitted where it avoids a copy), so it cannot even be fixtured cleanly.

So `_read` is not worth a code path. **With `_modify` done, the computational-body
blank frontier is exhausted for tractable swiftdc-local slices** — the remainder is
compiler plumbing (must stay blank), dependency-metadata-blocked (getters/setters/
`_read` on generic types with no field map), or low-value (trivial `==`).

### Next quality dimension — `--structured` raw-register conditions

A fresh `--structured` self-host survey points at the single biggest remaining
readability gap, in a *different* dimension than blank bodies:

| signal | count | note |
|---|---|---|
| `if (` total | 106,717 | |
| **raw-register conditions** (`if (w8 == 0)`, `if (x8 > 2)`) | **73,977** | ~70% of all conditions |
| `goto` | 3,384 | unstructured / depth-degraded control flow |
| `?` in a condition | 3,094 | value-coverage holes |

The raw-register conditions are the value-coverage frontier (the tracer left the
compared register unnamed). The top clusters are telling: `if (w8 == 3)` (1,366),
`if (w8 == 4)` (1,381), `if (w8 != 2)` (1,302) look like **enum-tag `switch`
chains** — a switch on `self.someEnum` lowered to a chain of tag compares that we
render with a raw `w8`. Naming the switched value (extending the enum-tag work,
`ea788b0`) and/or reconstructing the `switch` is a concrete, swiftdc-local lead
worth a concentrated root-cause probe — while remembering the earlier
`value-unknown-causes.md` finding that the *general* condition-base gap is diffuse.
If a concentrated probe finds no dominant tractable pattern, the honest call is to
accept the current coverage as a plateau.

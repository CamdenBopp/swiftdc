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

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

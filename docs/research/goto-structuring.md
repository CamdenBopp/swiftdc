# The `goto` dimension is sound; remaining gotos are honest loop back-edges

> Probe of the `--structured` goto/structuring frontier. Repo state after
> `5a0f251`. Conclusion: no small-change win here; the structurer is already sound.

## Every goto is a loop back-edge — zero irregular/degraded gotos

Categorized the 3,384 `goto` on the self-host by the tag the structurer attaches:

| kind | count |
|---|---|
| `goto loc_X  // loop` (loop back-edge) | **3,384** |
| plain `goto loc_X` (depth-guard degradation / irregular) | **0** |
| `// continues at loc_X` (fall-through *annotation*, not a goto) | 48,899 |

The structurer emits a bare untagged `goto` only when the `maxStructuringDepth`
guard trips (Structurer.swift:241). There are **none** — the 256 MB worker thread +
depth guard structure every function on the self-host without degrading. So the
structurer handles all reducible, single-exit control flow cleanly. The only gotos
are loop back-edges, which are inherent to *some* loop shapes.

## Why the back-edges aren't `while/continue`

`loops` (the foldable-loop map) admits a natural loop only when it has **≤ 1
distinct forward-exit target** (Structurer.swift:138, "provably correct"; sink
tails that `return`/`trap` are excluded, so a loop that can trap still folds).
Such loops render as `while (cond) { … }` (rotated) or `while (true) { … }`, and
their back-edge becomes an implicit loop or `continue`.

The remaining loop headers are `isLoopHeader` but **not** in `loops`, i.e.

- **multi-exit loops** (≥ 2 distinct exit targets), or
- **nested continues** — a back-edge to an *outer* loop's header (a Swift labelled
  `continue outer`).

These render honestly as `loc_HEADER:  // loop header … goto loc_HEADER  // loop`.
The control flow is correct and readable; it is just not the idiomatic
`while/continue`.

## Why this is not a smallest-general-change

Turning a multi-exit loop into `while (true) { … continue … }` requires choosing
ONE exit as the fall-out `break` and emitting the others as `goto exitN` (or
labelled `break`), and emitting only the loop *body* inside the `while` (the exit
blocks must land after it). Get the exit classification wrong and the rendered
structure **misrepresents** the control flow — strictly worse than an honest goto.
That is a real multi-exit / labelled-loop structuring algorithm, a larger feature
with correctness risk, not an incremental change. Per the loop's own guidance:
STOP and REPORT rather than force it.

## Feature-mode follow-up: there is NO safe incremental slice (measured)

Deliberate-feature mode revisited this to find a tractable sub-slice. Instrumented
the two back-edge emission sites and categorized all 3,384 back-edge gotos on the
self-host:

| category | count | share |
|---|---|---|
| **multi-exit loop** — not inside a folded loop, target not foldable | **3,030** | 89.5% |
| back-edge while inside *some* folded loop, target a different header | 330 | 9.8% |
| not in a loop context, target foldable | 24 | 0.7% |

(2,464 further back-edges already render as `continue`, inside folded loops.)

The 330 looked like labelled-`continue` candidates, so that was implemented: an
enclosing-loop stack threaded through `emit`/`edge`, a back-edge to an ENCLOSING
header emitted as `continue loc_<addr>`, and the loop's `while` line written after
its body so the label could be attached. It works and is safe (self-host: 4 labels
defined, 4 used, **zero dangling**, braces balanced, EXIT 0) — but it converts only
**5** gotos, not 330.

**Why the 330 collapsed to 5:** "inside some loop with a back-edge to a different
header" is NOT the same as "back-edge to an ENCLOSING header". In 325 of those cases
the target is a loop we are not lexically nested inside, where `continue` would be
invalid and `goto` is the only honest rendering. The strict enclosing check is
correct; the slice is simply tiny.

**Worse, the idiom that would use it is self-defeating.** A Swift `continue outer`
gives the INNER loop a second exit (its normal exit plus the jump to the outer
header), so the inner loop is multi-exit, is not folded, and renders as
`loc_HEADER: … goto loc_HEADER` — landing in the 3,030 bucket, not the
labelled-continue bucket. The fixture `nestedLabelledContinue` demonstrates exactly
this. So the feature is unreachable for the very construct it was meant to serve,
and no fixture can exercise it.

The change was therefore **reverted**: correct, but 5 incidental occurrences and no
possible regression test do not earn threading two parameters through the core
recursion. What was kept is `rendersMultiExitLoopHonestlyIfPresent`, pinning the
invariant that an unfoldable loop degrades to an honest goto rather than a structure
that misrepresents control flow — the guarantee any future multi-exit work must not
break.

**Conclusion: every meaningful goto reduction in this dimension requires multi-exit
loop folding** (89.5% of the population). There is no safe incremental slice — this
is now measured, not assumed. That feature must admit a multi-exit loop to `loops`,
emit `while (true)` over exactly its body set (`bodies[header]`, already computed),
render back-edges as `continue`, choose one exit as the fall-out `break`, and emit
the remaining exits as `goto loc_exitN` with the exit blocks after the loop. The
correctness bar is that the emitted body contains exactly the loop's body blocks.

## Increment 1 SHIPPED: multi-exit loops fold (`2a6fadb`)

Every natural loop now folds. Single-exit loops keep the rotation/`break` path
unchanged; a multi-exit loop becomes `while (true)` bounded to exactly
`bodies[header]`, back-edge as `continue`, each exit leaving by an explicit `goto`.
No exit is chosen as the fall-out, so nothing is classified and nothing can be
misrepresented.

| metric (same fixed target) | before | after |
|---|---|---|
| `loc_X: // loop header` (unfolded) | 3,140 | **0** |
| `while (true)` | 1,549 | **4,689** (+3,140 exactly) |
| `continue` | 2,464 | 5,241 |
| `goto loc_` | 3,384 | 9,654 |
| **dangling gotos** | 30 | **0** |
| duplicate labels | 0 | 0 |

The goto rise is expected and was predicted: a back-edge becomes `continue` while
each exit becomes an explicit goto. The honest measure is loops made structurally
explicit, which is 3,140 → all of them.

**Two latent defects surfaced and were fixed**, both invisible before folding:

1. Back-edge gotos never registered their target in `gotoTargets`. Harmless while a
   header always printed `// loop header`; once folded that line is gone and the goto
   dangles. Fixing it removed the 619 folding introduced *and* the 30 that already
   existed.
2. `gotoTargets` gates label printing but is populated *during* emission, so a goto
   emitted after its target was written could not label it. Emission now runs a
   discovery sweep first, then emits with the complete set.
3. The non-rotated path re-enters the header block and printed its label twice. The
   `while` line carries it; the inner repeat is suppressed.

`foldsMultiExitLoopWithoutDanglingGotoIfPresent` consciously replaces the old
"must not fold" test and asserts the honesty bar directly: every goto resolves, no
label is defined twice.

**Next increment:** promote one exit to `break` (fall-out selection) so the common
two-exit loop reads idiomatically. That one DOES classify an exit, so it needs the
care the original probe warned about — the body-bounding and label invariants above
are now regression-tested, which is the safety net for attempting it.

## Increment 2 SHIPPED: unambiguous fall-out promoted to `break` (`a7ae168`)

Increment 1 chose no fall-out on purpose. Increment 2 promotes one exit to `break`
only where the choice is forced: the header's immediate post-dominator is where
control provably reconverges after the loop, so when that block is itself one of the
exits it IS the fall-out. When control reconverges past the exits, no exit is
privileged and all stay explicit gotos — decline over guess.

| metric (same fixed target) | inc 1 | inc 2 |
|---|---|---|
| `break` | 2,052 | **2,160** (+108) |
| `goto loc_` | 9,654 | 9,537 (−117) |
| `while (true)` | 4,689 | 4,689 |
| `continue` | 5,241 | 5,258 |
| dangling gotos / duplicate labels | 0 / 0 | **0 / 0** |

`LoopContext` now separates a `break` exit (`exitNode`) from whether emission must
stay inside the loop's block set (`boundsBody`). They were conflated: body-bounding
keyed on `exitNode == nil`, so granting a multi-exit loop a `break` would have
switched its bounding OFF — the precise way this rewrite could have begun emitting
blocks that do not belong to the loop. Splitting them is what makes the increment
safe.

Spot-verified end to end on a real conversion: an inner loop's `goto loc_100779d2c`
became `break`, and that block is now emitted directly after the inner `while` —
where `break` lands.

### Known limitation, for the next increment

The emitted body is a **subset** of `bodies[header]`, not exactly equal. Bounding
guarantees nothing foreign is emitted inside a loop; it does not guarantee every
body block is reached by the bounded walk. Blocks the walk cannot reach linearly are
drained afterwards as labelled blocks, so they remain correct and reachable, but they
sit outside the loop that owns them — and a fall-through annotation can then point
from an outside block into a loop body, which reads awkwardly. Closing that gap
(emitting each loop's full body inside it) is the natural increment 3, and the
corpus-wide invariant test added here is the safety net for attempting it.

## Increment 3 (PARTIAL): the body-subset gap is measured, not closed (`1b802ad`)

Measured the gap before touching anything. Of **142,364** loop-body blocks on the
self-host, **28,870 (20%)** are emitted OUTSIDE the loop that owns them, across
**2,538 of 11,400** folded loops — single-exit loops included (732 of them), so most
of this predates increments 1–2.

| miss kind | count | share of misses | movable? |
|---|---|---|---|
| already emitted BEFORE the loop | 10,346 | 35% | no — would duplicate |
| still unemitted at loop close | 18,524 | 64% | yes, in principle |

The increment drains the second group into its loop, but only when the chunk
transfers control explicitly: a block pulled in before the closing brace would fall
through to it and read as a loop-back. The emitter already marks that case with
`// continues at`, so chunks carrying it are left at top level (the trial emission is
rolled back).

**That guard rejects nearly every candidate** — `// continues at` occurs 46,918
times. Stranded top-level labels fall only **4,799 → 4,699 (−100)**, ~0.35% of the
28,870. The gap is **not** closed. Secondary gains are real but modest: `continue`
5,258 → 5,722 (+464, drained blocks now carry loop context), `break` 2,160 → 2,196,
`goto` 9,537 → 9,509. All hard bars hold (dangling 0, duplicate labels 0, balanced,
EXIT 0, single-exit unchanged).

**Increment 4 — the actual fix.** The blocker is now identified rather than guessed:
implicit fall-through. Rendering `// continues at loc_X` as an explicit `goto loc_X`
*when draining into a loop* makes the chunk self-contained and unlocks most of the
18,524. The 35% already emitted before their loop remain out of reach without node
splitting / header duplication, which is a genuinely larger change and should not be
attempted just to raise a coverage number.

## Broader assessment: the small-change reconstruction frontier is a plateau

Across this session the incremental frontier has been mined and the remaining
opportunities are each a *larger* deliberate feature, not a smallest-general-change:

| Area | State | To go further needs |
|---|---|---|
| Blank computational bodies | mined (`_modify` −483; getters) | plumbing stays blank; deps' metadata |
| Condition naming | coverage-bound plateau | diffuse value coverage; switch reconstruction |
| `goto`/structuring | **sound** (all honest back-edges) | multi-exit / labelled-loop structuring |
| Field-map correctness | fabrication fixed + tested | qualified keys (coordinated refactor) |
| `→ self.layout` precision | known limitation | `__C` struct field data |

The tool is mature and, after the collision fix, free of known fabrications. The
next real gains are **feature-sized** (each a multi-iteration project), which is a
different mode than the incremental loop. Honest recommendation: either
**consolidate** (the tool is in a good, correct state), or **deliberately invest**
in ONE of the feature-sized items above as a scoped project — rather than continue
hunting small changes that are now largely exhausted.

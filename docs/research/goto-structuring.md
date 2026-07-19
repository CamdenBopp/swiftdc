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

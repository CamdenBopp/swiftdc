# Value-unknown causes on the self-host (probe + first fix)

> Findings note for the user-directed "probe & fix the top value-unknown cause"
> step. Repo at the probe: `9f33f93`; fix committed `3a70531`.

## The gap landscape (swiftdc self-host, `--structured` + `--pseudo`)

| Gap | Count | Where |
|---|---|---|
| raw-register conditions (`if (x8 >= x9)`) | 44,872 | --structured |
| unresolved `?` call arguments | 22,213 | --pseudo |
| "no non-runtime calls" (computational bodies) | 36,287 | --pseudo (of 70,502 fns) |
| `// continues at` (irreducible merges) | 20,587 | --structured |
| `trap()` (mostly genuine safety checks) | 5,565 | --structured |
| `goto` (depth-guard / irreducible) | 528 | --structured |

## Raw conditions by tested register (the 44,872)

| Register | ~count | Cause |
|---|---|---|
| **x21** | **7,657** | **Swift error register** — throwing-call error check `x21 != 0`. FIXED. |
| w8 / x8 | ~19,000 | a temp holding a load / call-result / computed flag left `.unknown` |
| w0 / x0 | ~4,000 | a call result compared (`if (call() != 0)`) |
| x20 | ~430 | `self` in a comparison |
| other | rest | mixed |

Operators are dominated by `!=` (22,923) and `==` (11,558) — equality/nil tests,
not ordering. The single most common *tractable* cause (one idiom, one fix) is
the x21 error check; the w8/x8 bucket is bigger but heterogeneous (many distinct
value sources), so no single fix addresses it.

## Fixed: x21 error checks → `error != nil` (commit `3a70531`)

A branch on x21 against zero (`cbnz`/`cbz x21`, or `cmp x21, #0; b.ne/eq`) is the
swifterror convention. The structurer now names it `error != nil` / `error ==
nil`, gated on the function threading swifterror (`throws` in the name, or a
`mov x21, #0` clear before a call). Where the compiler cleared x21, the old
back-substitution even produced a *wrong* always-false `if (0 != 0)`.

**Impact (self-host --structured):** raw `if (x21 …)` 7,657 → **1,317** (−83%);
`error != nil`/`== nil` 0 → **6,547**. EXIT 0, braces balanced, --pseudo
unaffected (structurer-only).

## Remaining, ranked for future work

1. **w8/x8 value comparisons (~19k)** — the big one, but heterogeneous. Needs the
   value tracer to reach more operands (loads through unresolved slots/fields,
   call results, two-level loads). Best split by a finer trace of the specific
   unknown sources.
2. **`?` call arguments (22,213)** — same underlying cause (tracer coverage);
   likely overlaps with (1). A fix to a common load/slot cause lifts both.
3. **do/catch value select still stale-reads x21** — the tracer renders
   `(0 != 0) ? …` in a returned expression (a wrong always-false). Not fixed
   here: a universal x21 invalidation broke ObjC (x21 is general there); needs a
   Swift-vs-ObjC gate in the tracer's `transfer`.
4. **`// continues at` (20,587)** — irreducible/duplicated merges the structurer
   can't fold; a structuring, not a value, problem.

The evidence says the next value-coverage investment should trace the w8/x8
unknown *sources* specifically (not the register) to find the next single most
common cause — the same evidence-first method that isolated x21 here.

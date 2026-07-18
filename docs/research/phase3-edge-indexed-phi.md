# Phase 3 — edge-indexed φ at CFG joins (guiding doc)

> Next "guiding light" task doc. Follows Phases 1–2 (type lattice + U1 fix +
> typeOf precision). Companion to `decompiler-comparison.md` §3 (Ghidra's
> MULTIEQUAL), §8 (debt #2: `.select`-as-join), §9.3 step "edge-indexed φ",
> candid assessment #6 ("best deliberately-scoped next feature").

## Why (the debt)

Today a CFG join is represented **directly as `.select(cond, whenTrue, whenFalse)`**,
built by two hand-written special-case passes — `resolveDiamondSelects` (2-arm)
and `resolveSwitchSelects` (N-arm tag cascade). The study's finding (Ghidra
`heritage.hh`, `ruleaction.cc:9373` `RuleConditionalMove`): a real decompiler keeps
a **φ (MULTIEQUAL) whose input slot *i* is CFG in-edge *i***, and *derives* a
ternary only late, from a φ whose arms are pure/single-use. Our `.select`-as-join
throws away the predecessor→value mapping that copy-propagation, type-meet (now
that we HAVE types — Phases 1–2), and future structuring all need. It is also why
merging is bolted on as two growing special cases instead of falling out of one
join rule — the exact "accumulation of special cases vs a coherent IR" risk.

## Goal (evolutionary, not a rewrite)

Introduce a **φ value** — `phi(incoming: [(predecessor: UInt64, value: AbstractValue)])`
— as the representation of a value that differs across a block's predecessors.
Replace the two special-case resolvers with **one φ-placement step** at joins;
keep `.select` **only as a derived form** produced by a single, guarded rule
("collapse a φ to a `.select` when there are exactly two distinct pure,
side-effect-free, single-use arms with a recovered branch condition"). Everything
`.select` renders today must render identically after the φ→select derivation —
this phase is a **representation change with no output change** on existing
fixtures, plus it must merge the Phase-1/2 **types** across φ inputs with
`ValueType.meet` (the first real consumer of the lattice at joins).

## Design

1. **`AbstractValue.phi([(UInt64, AbstractValue)])`** — a new case; update the
   exhaustive switches (renderValue, sanitizeValue, collectCallResults,
   expressionDepth, isFloatValued, typeOf, …) — compiler-guided, as with prior
   new cases. `typeOf(phi)` = `meet` of the incoming values' types (lattice join
   at the merge — the invariant the study calls for).
2. **Placement:** at a block with ≥2 predecessors, for each state key whose
   value differs across predecessors, set the entry value to
   `phi([(pred, outValue)…])` (edge-indexed). This subsumes both current passes:
   the diamond and the switch cascade are both just φ with 2 / N inputs.
3. **Derivation (φ → `.select`), the ONLY place a ternary is manufactured:**
   a guarded rule that fires when a φ has exactly two distinct arms, both pure
   (no call/load side effects, bounded depth) and the branch condition is
   recovered (reuse `branchTakenCondition`). The N-arm tag cascade derives to the
   nested `.select` chain exactly as `resolveSwitchSelects` does today (same
   mutual-exclusivity gate). A φ that does not qualify stays a φ and renders as
   its edge values or declines — never a fabricated ternary.
4. **Rendering:** `renderValue(.phi)` renders the derived `.select` when available;
   otherwise a bare φ is a *merge we could not turn into an expression* — render
   the arms honestly (or decline), matching the current "no non-runtime calls"
   behavior. This is the honest-uncertainty escape the study praises (Ghidra keeps
   the φ; it does not invent).

## Non-goals

- No loop structurer (φ over a **back-edge** — a loop-carried value — must be
  *recognized and left as a φ / declined*, NOT collapsed to a select). Loops are
  the phase AFTER this; this phase must simply not mis-handle a back-edge φ.
- No rule-pool refactor, no Optional model, no variable promotion.
- No new node kinds beyond `.phi`.

## Validation (must be output-stable, then additive)

- **Every existing select/switch/ternary fixture byte-identical** — `clampLow`,
  `maxOf`, `pickInc`, `ptrOrElse`, `rank`, `gradeOf`, the `&&`/`||` cases,
  `computedRange` — this phase changes representation, not output, for them.
- **The decline cases still decline** — `threeWay` (3-way non-mutually-exclusive),
  tagged-optional, and any **loop back-edge** φ must NOT become a select.
- New unit tests: φ placement is edge-indexed (input *i* ↔ predecessor *i*);
  `typeOf(phi)` is the `meet` of arms (a `signed` and an `unsigned` arm → unknownSign).
- Debug/`-O`/stripped; full suite; self-host crash + a **new over-firing scan**:
  count `.select` renderings before/after — they must MATCH (no new ternaries),
  and scan for any select over a back-edge (there must be none).

## Stop condition

If φ-placement over irreducible or back-edge CFGs cannot be done without a real
dominator/loop analysis, **stop and report** — that is the signal the loop
structurer (with proper back-edge handling) must be co-designed, and this phase
should land only the reducible-forward-join φ, explicitly deferring back-edges.

## Forward compatibility

Edge-indexed φ is the join representation the loop structurer consumes (a
loop-header φ is a loop-carried variable); `typeOf(phi)` via `meet` is the type
merge at joins the whole lattice was built for; and the guarded φ→select rule is
the first member of the future simplification-rule pool. Nothing is throwaway.

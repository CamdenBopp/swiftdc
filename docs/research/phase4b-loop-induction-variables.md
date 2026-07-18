# Phase 4b — loop-carried induction variables (value↔structure unification, step 1)

> Guiding doc for the first concrete step of the value↔structure unification
> (`phase4-unify-value-and-structure.md`). Written after an **evidence probe** of
> the value tracer's loop handling (repo `13836ad`). Companion to
> `decompiler-comparison.md` §8.

## STATUS — step 1 DONE (commit `2be20dd`)

Implemented as designed below: `AbstractValue.local(Int)` + a hard-gated
post-fixpoint pass (`resolveLoopInductions`) that seeds a header slot with a
proven constant initial value, re-transfers the loop body, and accepts only a
proven `i ± c` linear recurrence. A counting loop's exit comparison now
reconstructs `if (i >= arg0)` instead of `if (x9 >= x10)`. `meet` untouched;
only `inState[header]` is modified (naming localized to the exit comparison).

Verified declines (no fabrication): non-linear (`i *= 2`), collection/iterator
for-in, `-O` vectorized. 98 tests; output-stable on existing `--pseudo`
fixtures; self-host `--structured` EXIT 0 (540k lines, 0 crashes, **0 false
positives**) and `--pseudo` EXIT 0.

**Honest impact note:** idiomatic Swift favors iterator/higher-order loops over
integer counters, so the swiftdc self-host named **0** loops (0 false positives)
— the win shows on C-style counting loops, not this corpus. This is the
foundational `.local`/recurrence infrastructure the follow-ups build on.

**Follow-ups:**
1. **DONE (commit `a47a313`)** — body update `i += c`. `resolveLoopInductions`
   now identifies the *compared* slot (the `.local` in the re-transferred header
   flags) and names only it (killing the -Onone phantom copies), records the
   proven step as `FunctionAnalysis.loopUpdates`, the enrichment bakes a
   `loop-update:` note (ignored by `pseudoStatement`, so `--pseudo` is
   unaffected), and the structurer appends `i += c` at the body end — gated on
   `bakedCondition != nil` so the increment's `i` always matches a named
   condition (else a raw-register condition would leave `i` undefined; caught on
   self-host). `sumTo`/`countTo` → `while (i < arg0) { i += 1 }`.
2. **DONE (commit `4fa5b6b`)** — while-condition rotation.
3. **(NEXT)** Loop-carried accumulators (`total += i`) and multi/coupled
   induction vars — a *coupled* recurrence (`total_new = total_old + i`, where
   `i` is itself an induction var), harder than the linear `i ± c` case. Would
   complete `sumTo` to `while (i < n) { total += i; i += 1 }`.
4. `do { } while` (exit test at the back-edge, not the header).

**Honest state:** simple C-style counting loops now reconstruct as
`while (i < n) { …; i += 1 }`. Idiomatic Swift favors iterator/higher-order
loops, so swiftdc's own code shows 0 of these (0 false positives throughout) —
the win is on C-style loops. The `.local`/recurrence/`loop-update` infrastructure
is the foundation for the accumulator + coupled-IV work.

## The goal (recap)

A loop today renders with an empty/opaque body:

```
LoopProbe.sumTo(Swift.Int) -> Swift.Int {
    while (true) {
        if (x9 >= x10) { return }   // want: while (i < n) { … }
        else { continue }
    }
}
```

We want the loop header condition to read `(i < n)` (named operands), and the
body to show the update `i += 1`. The overflow-trap noise is already folded
(Phase 4a); the loop *structure* already recovers (the structurer). The missing
piece is naming the **loop-carried induction variable**.

## The probe (what the value tracer actually does)

Evidence, not assumption — all confirmed by reading `ValueTracking.swift`:

1. **Stack slots ARE modeled.** `State` tracks register *and* stack-slot values,
   slots keyed by a symbolic frame offset (`.frame(Int64)` / `stackKey`) so a
   local survives prologue `sp` adjustments. So `-Onone` locals (everything is a
   stack slot at `-Onone`) are not inherently opaque — `ldr x9, [sp,#0x40]`
   loads the slot's tracked value.

2. **`meet` drops divergent slots.** The join is an all-or-nothing intersection:
   `meet(states) = accumulator.filter { state[key] == value }` — it keeps only
   entries **identical across all predecessors**. At a loop header the induction
   slot = `meet(pre-loop value 0, back-edge value i+1)`; these differ, so the
   slot is dropped → the header reads `.unknown` for `i`.

3. **The tracer is loop-unaware.** The forward fixpoint (worklist re-queues
   successors to convergence) *traverses* back-edges but never *identifies*
   headers or back-edges, and `resolveDiamondSelects` **explicitly declines
   loops** ("a loop back-edge … leaves the value dropping to `.unknown`").

4. **The `cond:` bake is all-or-nothing.** The structurer prefers a baked
   comparison note (`cond: (arg0 >= arg1)`) over raw-register text, but the note
   is baked only when the *whole* reconstructed comparison is clean
   (`condition != .unknown`, no call-result operand). A header whose loop-carried
   operand is `.unknown` bakes nothing → the structurer falls back to
   `condition(of:)`'s text back-substitution, which can't see through a stack
   load → raw `x9 >= x10`. (Even the loop-*invariant* operand `n`, which the
   tracer knows is `arg0`, is lost this way.)

**Conclusion:** the gap is not a renderer patch. Naming the induction variable
needs (a) loop awareness in the tracer, (b) a loop-carried value representation,
and (c) recurrence (init+step) detection. This is the substantive unification —
correctly sized as its own focused feature.

## Design (smallest coherent first step)

Add induction-variable recognition as a **post-fixpoint pass** in
`ValueTracer.analyze`, gated hard to the common, provable case; decline anything
else (the project's decline-over-guess discipline).

1. **Loop awareness (self-contained).** Compute back-edges with the same DFS the
   structurer uses (a node with an edge to a gray/on-stack ancestor). This gives
   `{header → back-edge predecessor}`. ~15 lines; no dependency on the structurer
   (the tracer runs first).

2. **Loop-carried value representation.** Add an `AbstractValue` case for a named
   induction variable — a *placeholder* the recurrence check resolves against:
   `case local(id: Int)` (rendered `i`, `j`, … by id). This is the φ the earlier
   phases deferred, finally with a consumer.

3. **Recurrence detection (the φ-placeholder trick).** For each header `H` and
   each slot that (a) has a *known constant* value on the pre-loop entry edge and
   (b) is dropped by `meet` (divergent):
   - Seed `inState[H][slot] = .local(freshId)`.
   - Re-transfer the loop body so the back-edge out-state for the slot is
     expressed in terms of the placeholder.
   - Accept **iff** back-edge `out[slot] == .binary(.add|.sub, .local(id), .immediate(c))`
     — a genuine `slot = i ± c` recurrence. Record `(name, init, step)`.
   - Otherwise revert the slot to `.unknown` (decline — non-linear, multiple
     writers, address-taken, etc.).

4. **Rendering.**
   - `.local(id)` renders `i`/`j`/… — so the header comparison reconstructs
     (`(i < n)`), baked as a `cond:` note the structurer already consumes.
   - The recurrence renders the body update `i += c` (reuse the existing `+=`
     path used for ivar updates).

## Non-goals (decline, don't guess)

- Multiple/coupled induction variables, non-constant step, non-linear updates.
- Loop-carried *accumulators* (`total += i`) beyond a first single-variable pass
  — a follow-up once the single-IV case is solid.
- Irreducible/multi-header loops (the structurer already degrades these).

## Validation bar

- New fixtures assert the header reads `(i < n)` and the body shows `i += 1`
  (`sumTo`/`accumulate`), across `-Onone`/`-O`/stripped.
- **Adversarial:** a non-induction loop-carried slot (data-dependent update),
  and a loop whose bound isn't a clean comparison, must still decline (no
  fabricated `i`). A pointer/collection loop must not invent an integer IV.
- **Output-stable on all existing `--pseudo` fixtures** — this adds a
  post-pass; straight-line/diamond reconstruction must be byte-identical.
- Full suite; `--pseudo` and `--structured` self-host SOLO (both must stay
  EXIT 0, no regression; `--structured` is now crash-safe).

## Why a post-pass, not a change to `meet`

`meet` is correct as-is for straight-line/diamond code (its intersection
semantics are what keep the lattice sound and the existing reconstruction
stable). Loop-carried values are a *different* kind of join (a recurrence, not an
intersection) and belong in a dedicated, gated pass that runs after the base
fixpoint — keeping the risky new logic out of the hot, well-tested `meet`.

## Provenance

Probe at repo `13836ad`. Confirmed: `ValueTracking.swift` `meet` (intersection),
`State` stack-slot model (`.frame`/`stackKey`), fixpoint loop-unawareness,
`resolveDiamondSelects` loop exclusion, and the `cond:`-bake gate in
`Disassembler.swift` (`analysis.branchConditions`, `condition != .unknown`).

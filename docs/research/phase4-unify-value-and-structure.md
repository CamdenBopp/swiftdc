# Phase 4 — unify the value layer with the structured (control-flow) layer

> Guiding doc. Supersedes the "add loops / add φ" framing of
> `phase3-edge-indexed-phi.md`. Written after an **evidence probe** (repo
> `9a15e35`) that overturned that framing. Companion to
> `decompiler-comparison.md` §8 (technical debt) and candid-assessment #5
> ("most important architectural investment next").

## Progress log

- **Phase 4a DONE (commit `fc7e310`) — step 4, the checked-arithmetic trap fold**
  (the user-chosen "trap-fold first"). Swift's checked `+`/`-`/`+=` overflow
  branch to a trap sink is folded in the structured view; adversarially verified
  at -O that genuine precondition/bounds/unwrap/fatalError traps survive. Also
  fixed a CFG root cause (`brk`/`udf` had a spurious fall-through successor).
  `sumTo` → clean `while`; `Tree.sum()` loses its overflow trap. New
  structured-view test harness. 96 tests; --pseudo self-host green (0 crashes).
- **⚠️ DISCOVERED — pre-existing `--structured` stack overflow.** Running
  `--structured` over a large binary (swiftdc self-host) SIGBUSes: the recursive
  `emit`/`edge` structuring has no depth bound and overflows the 8 MB stack on a
  deep CFG (crash report: KERN_PROTECTION_FAILURE at the stack-guard region).
  Confirmed pre-existing (the pre-fold binary crashes identically) — never caught
  because prior self-host gates used `--pseudo`. It violates the Structurer's own
  "degrade to goto, never crash" contract. **This is the immediate next step**
  (a prerequisite for reliable `--structured`, which the layer-unification builds
  on): thread a depth counter through `emit`/`edge` and degrade to the existing
  `goto loc_<addr>` fallback past a safe depth. Then steps 1–3 (loop-carried φ,
  body updates, named conditions) can proceed on a crash-safe structured path.

## TL;DR — the plan was misdiagnosed; here is what the code actually does

Phases 1–3 assumed the next step was "add a loop structurer, with φ to feed it."
A probe showed **a loop structurer already exists**, and the real gap is
different and larger: swiftdc has **two disjoint reconstruction layers**, and a
loop body comes out empty. Per the standing instruction — *"if a larger
prerequisite is exposed, stop and report the evidence rather than hiding the
problem behind another renderer-specific patch"* — this doc reports it.

## The probe (reproducible)

Fixture (`-Onone -g` dylib):

```swift
public func sumTo(_ n: Int) -> Int {
    var total = 0, i = 0
    while i < n { total += i; i += 1 }
    return total
}
```

`swiftdc disasm … --pseudo -f sumTo` (the rich value-reconstruction path — what
phases 1–3 improved, what `ReconstructionTests` exercise):

```
LoopProbe.sumTo(Swift.Int) -> Swift.Int {
    // no non-runtime calls (leaf / pure computation)
}
```

→ **declines the loop entirely.** It reconstructs *return values* by a forward
abstract-interpretation fixpoint, but a loop's result depends on **loop-carried
state it has no representation for**, so it emits nothing.

`swiftdc disasm … --structured -f sumTo` (the CFG structurer):

```
LoopProbe.sumTo(Swift.Int) -> Swift.Int {
    while (true) {
        if (x9 >= x10) {
            return
        } else {
            if (bit 0 of w8 set) { break }
            else { if (bit 0 of w8 set) { trap() } else { continue } }
        }
    }
    trap()
}
```

→ recovers the control-flow **shape** (`while`/`break`/`continue` — a real loop
structurer: `ControlFlowStructure`, natural-loop detection via back-edges,
post-dominators), but the body is **semantically empty**:
- **no value statements** — `total += i` and `i += 1` are gone (they are
  stack-slot load/add/store sequences; per-instruction `pseudoStatement` only
  emits *recognized calls*, so raw local arithmetic produces nothing);
- **raw-register conditions** — `x9 >= x10`, not `i < n`;
- **value-less `return`** — not `return total`;
- **checked-arithmetic trap noise** — Swift's `+=` overflow check leaks in as
  `if (bit 0 of w8 set) trap()`.

## The corrected architecture picture

| Layer | Entry | Handles | Misses |
|---|---|---|---|
| **Value reconstruction** | `renderPseudo` → `ValueTracer` / `AbstractValue` (Disassembler.swift) | rich typed values, forward joins → `.select`, optionals, enums (phases 1–3) | **any control flow beyond a forward diamond/switch**; declines loops |
| **Control-flow structure** | `renderStructured` → `ControlFlowStructure` (Structurer.swift) | if/else, **while/break/continue**, goto fallback, post-doms, natural loops | **rich values** — bodies are per-instruction, conditions/returns are raw registers |

`ControlFlowStructure` calls `renderValue`/`AbstractValue` **zero** times
(verified: grep count 0). The layers are almost fully separate — with **one
existing seam**: `condition(of:)` *prefers the value tracer's reconstructed
comparison when the enrichment baked a `cond:` note* (so a forward `if` reads
`arg0 >= arg1`, not raw registers). That seam is the unification path — and it
**breaks exactly at loops**: for `sumTo` no `cond:` note exists for the header
compare, because its operands are loop-carried locals the tracer cannot name.

## Where φ actually belongs (phase-3 reconciled)

Phase 3 deferred φ because it had **no consumer**. The consumer is now concrete
and evidence-backed: **the structured view's loop conditions and bodies.** A
loop-header φ *is* the loop-carried variable `i`/`total`; naming it lets the
tracer (a) bake a `cond:` note so the header reads `i < n`, and (b) emit the
body updates `i += 1; total += i`. Phase 3's stop-condition ("φ must be
co-designed with the loop structurer") was right; the structurer already exists,
so the co-design is **φ-in-the-value-tracer ↔ structured-loop rendering**, joined
at the `cond:`/statement seam that already exists for forward code.

This is the study's "unified IR, not two rendering passes" point (§8) made
concrete, and it is candid-assessment #5's "most important architectural
investment": **widen the value↔structure seam to carry loops.**

## The investment (larger than a one-iteration patch — flagged, not hidden)

Widen the seam so the value tracer's reconstruction flows into the structured
view for loops:

1. **Represent loop-carried values** in `ValueTracer`: at a loop header, a value
   that differs on the back-edge becomes a recurrence/φ (name it `i`), not
   `meet → unknown`. The fixpoint already traverses back-edges (worklist
   re-queues successors); today it just joins them to ⊤.
2. **Emit loop-body update statements**: render a recognized loop-carried update
   (`i += 1`, `total += i`) as a structured statement — the tracer already models
   the ivar-update `+=` form (`renderValue … "+="`), so extend it to stack-slot
   locals inside a loop body.
3. **Name loop conditions**: with `i` named, bake the header compare as a `cond:`
   note so the existing seam renders `(i < n)` instead of `x9 >= x10`.
4. **Fold checked-arithmetic trap idiom**: Swift's `add/subs + b.cs/b.vs → trap`
   overflow check is a fixed ABI idiom; recognize and suppress it (like the
   enum/optional idioms) so loop bodies aren't sprayed with `if (overflow)
   trap()`. General, testable, needed for any readable loop or `+=`.

Steps 1–3 are the co-design (interdependent); step 4 is independent and is the
smallest genuinely-general standalone win.

## The honest fork (why this is a stop-and-report, not an autonomous next patch)

Steps 1–3 are a **layer-unification**, the largest architectural move since the
type lattice, and they are literally the user's open question ("most important
architectural investment next"). Doing them well means committing to the seam
design (does φ live in `AbstractValue`, or a parallel recurrence table? does the
structurer drive the tracer per-region, or vice-versa?). That is a direction
decision worth surfacing before spending the tokens — not something to prejudge
by shipping a narrow patch that later has to be unwound.

**Recommended scoped first step if the loop continues autonomously:** step 4
(checked-arithmetic trap fold) — general, self-contained, improves every
`+=`/loop body, and is a prerequisite for 1–3 regardless of how the seam is
designed. It needs structured-view test assertions (the suite currently only
asserts `--pseudo`); adding a small structured-view harness is itself worthwhile.

**Recommended if pausing for direction:** decide the seam design (φ-in-
`AbstractValue` vs. recurrence table; who drives whom) before steps 1–3.

## Validation bar (unchanged discipline)

- Output-stable on every existing `--pseudo` fixture (this touches the structured
  path and the tracer's loop handling, not forward-diamond reconstruction).
- New **structured-view** assertions on `sumTo`/`countUp`: condition names (`i <
  n`), body updates present, no trap-noise, `return total`.
- Adversarial: an irreducible/multi-exit loop must still degrade to `goto`, never
  a fabricated `for`/`while` with invented bounds.
- Debug/`-O`/stripped; full suite; self-host crash + a trap-noise-count scan
  (before/after) and a "structured loop body non-empty" scan.

## Provenance

Probe + findings at repo `9a15e35`. `sumTo`/`countUp` probe fixture built with
`xcrun swiftc -parse-as-library -Onone -g -emit-library`. Layer-separateness
confirmed by `grep -c 'renderValue\|AbstractValue' Structurer.swift` → 0.

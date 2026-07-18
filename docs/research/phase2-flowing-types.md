# Phase 2 — a flowing type-state through the abstract interpreter (guiding doc)

> Next "guiding light" task doc. Builds directly on Phase 1
> (`phase1-type-lattice.md`, commit `2be9e31`). Companion to the study
> `decompiler-comparison.md` §9.3 (evolution step: "flowing type-state").

## Why (the gap Phase 1 left open)

Phase 1 introduced `ValueType` + `meet` and fixed U1, but types are still
**computed at render time** by `TypeInference.typeOf` reading `argumentTypes`.
That satisfies the *argument-based* cases but not the user's full goal —
"semantic facts should travel with values through the analysis rather than being
rediscovered from function signatures inside the final renderer." Concretely,
Phase 1 cannot type a value that is not a bare argument:

- Self-host evidence: `((demangleIndex() - 1) >ᵁ 0) && (… <=ᵁ 0x1000)` and
  `(57 & 255) >=ᵁ arg0` (`Punycode.isDigit`) render **exposed unsigned** because
  the compared value is a *computed expression* whose signedness Phase-1 `typeOf`
  cannot establish — even when the ABI proves it (`isDigit`'s `arg0` is `UInt8`).
- A sign/zero-extend or truncate of a **non-argument** mid-body value carries no
  signedness (extensions are currently transparent in the tracer).

These are precision losses, not correctness bugs — Phase 1 exposes `<ᵁ` honestly.
Phase 2 recovers the precision by making the type *flow*.

## Goal

Thread a **parallel type-state** `types: [String: ValueType]` through `ValueTracer`
alongside `registers: State`, seeded from `argumentTypes`, propagated by the
transfer function, and **met at CFG joins with `ValueType.meet`**. Comparisons
record the operand's flowed type so the render decision consults a *flowed* fact,
not a render-time recomputation.

## What propagates (conservative; unknown is always allowed)

| Instruction / value | Type effect |
|---|---|
| argument seed | `argumentTypes[i]` (ABI evidence) |
| `mov`/copy | copy the source's type |
| `sxtb/sxth/sxtw` (sign-extend) | `signed`, width = destination width — **instruction evidence** |
| `uxtb/uxth/uxtw` / low-byte mask | `unsigned`, width = mask/dest width — truncation, keeps unsigned |
| `add/sub/mul` | `meet` of operand types (category/signedness both agree) |
| `and/or/xor/shift` (non-mask) | `integer, unknownSign` |
| signed `sdiv`/`asr` | `signed` |
| unsigned `udiv`/`lsr` | `unsigned` |
| load / call result / cast | `.unknown` (conservative — a load's/call's type is not encoded by the op) |
| `fmov`/float ops | `floatingPoint` |
| CFG join | `ValueType.meet` of predecessors' `types` (keep only agreed facts) |

**Hard rules carried from Phase 1:** never infer `signed` from "a register holds
an integer"; a load/call is `.unknown` unless separately typed; conflicting merges
resolve DOWN. The meet at joins must be the *same* `ValueType.meet` a future phi
will use — do not fork a second merge.

## Where the fact is consumed

The comparison built in the transfer function (`comparisonValue` / `cset`) records
the operand's flowed `ValueType` (e.g. into `FunctionAnalysis` keyed by the
comparison's address, or attached so enrichment can read it). `renderUnsignedComparison`
then uses the **flowed** operand type instead of `TypeInference.typeOf(…, argumentTypes)`.
Result: `isDigit`'s `arg0` (`UInt8`) flows unsigned through `& 255` and the compare
renders a plain `<` (Case 1) rather than `<ᵁ`; a computed signed value compared
unsigned against a constant recovers the range idiom.

## Non-goals (keep it evolutionary)

- No phi redesign, rule pool, loop structurer, or Optional model.
- No new `AbstractValue` cases — the type-state is a *parallel* map, not a field
  on every value (that is the phi/IR phase).
- Loads/calls stay `.unknown` — inferring their result types is a later phase.

## Validation

- The Phase-1 fixtures must stay green (byte-stable), plus new fixtures where the
  compared value is **computed** or **extended mid-body**: e.g.
  `f(_ x: UInt8) -> Bool { x >= 48 && x <= 57 }` must now render plain `<`/`>=`,
  not `<ᵁ`; a mid-body `let y = x &- 1` then `y < N` over an unsigned `x`.
- Differential testing over boundary + random inputs for any new range-idiom
  recovery, as in Phase 1.
- `meet`-at-join test: a value that is `signed(64)` on one path and `signed(32)`
  on another must flow as `signed`, width nil (not one arm's width).
- Debug/`-O`/stripped; full suite; self-host crash + over-firing (count `<ᵁ`
  before/after — it should DROP as precision improves, with each remaining one
  spot-checked as a genuinely-untypable operand).

## Stop condition

If flowing the type-state cleanly requires representing values in SSA first
(e.g. the parallel map cannot express a value that lives in two registers over
its lifetime), **stop and report** — that is the signal that the phi/variable
phase must come before further type precision, and it should be surfaced, not
patched around.

## Forward compatibility

The flowing `types` map is the direct precursor of per-SSA-value types once phi
lands; `ValueType.meet` at joins is literally the phi's type merge. Nothing here
is discarded by the phi phase — it is absorbed.

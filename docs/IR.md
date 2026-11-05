# Settling on an intermediate representation

swiftdc is building an IR between decoded instructions and rendered text.
This document says why that now limits soundness more than any single missing
rule, what the IR should be, and the order to build it in so that every step
ships on its own, output-identical unless it is a deliberate fix.

It builds on, and does not replace, the layered target in
[decompiler-comparison.md §9.3](research/decompiler-comparison.md) (effect-explicit
ops, edge-indexed φ, typed values, a simplification rule pool, block-tree
structuring, a thin emitter). That section argued from design debt. This one
argues from defects found since, and puts the memory model first, because that
is where the open soundness bugs are.

## The starting design

This design motivated the plan; the progress notes below describe what has
since shipped.

1. **Decode.** `Instruction` carries objdump text, Capstone's `StructuredInsn`,
   a control-flow class and a branch target.
2. **Analyse.** Several independent forward dataflows run over the same
   instructions, each with its own state and its own model of the frame:

   | Analysis | State | Frame/memory model |
   |---|---|---|
   | `ValueTracer` | `[String: AbstractValue]`, keys `"x0"`, `"stack@-16"`, `"stack-width@…"`, `"ownctx@…"`, `"result@…"`, `"nzcv.flags"` | Slots survive a call unless the slot's own address is in an argument register at that call. Stores through unknown pointers change nothing. |
   | `Preservation` (CalleeRegisterSummary) | registers and 8-byte slots of `.entry`/`.stack`/`.unknown` | Exact store extents, MAY frame-alias provenance, persistent escape flag, caller-owned ranges. The most careful of the five. |
   | `CalleeRegisterSummary` argument reads | written-register sets | none |
   | `addressTakenFrameOffsets` | parses instruction **text** | offsets only |
   | `AsyncContextEscapes`, `SwiftErrorExitProof` | per-question | per-question |

3. **Hand off.** Enrichment renders each fact to a string and appends it to
   `Instruction.annotation`, two spaces between notes: `→ name`, `args(…)`,
   `return …`, `let r0 = …`, `await=…`, `swift-exit=…`. Call arguments are
   stored pre-rendered as `[String]`.
4. **Render.** `Pseudo`, `Structurer`, `CallGraph` and JSON re-parse those
   strings by prefix.

## The defects this shape produces

- **Five memory models, five sets of holes.** The top open soundness item was
  a `ValueTracer` hole that `Preservation` does not have: `cacheEscape` at -O
  stores a frame address to a global, writes 7 through it, calls a helper that
  writes 11 through the global, and renders `return 7`. Native execution
  returns 11. Each analysis that needs frame facts re-derives escape and
  aliasing, and each one gets a different subset right. (The stopgap below
  shipped on 2026-10-15: per-region escape markers in the tracer, unioned at
  joins. Step 4 now shares write footprints and current-frame fact storage;
  boundary/provenance discovery, MAY carriers and complete layout/space
  unification remain open.)
- **Facts are strings.** `demangledName(from:)` returns any leading note not on
  its deny-list as a callee name. Adding the `swift-exit=` note on 2026-10-15
  would have made call graphs list it as a callee; the deny-list had to grow
  again. CLAUDE.md has carried "a new note must never look like a callee name"
  as a manual rule because nothing in the types enforces it. Pseudo and the
  structurer contain 47 `hasPrefix("…")` tests on note text.
- **No value identity.** The -Onone `try` exit spills the callee's x21 to a
  slot, tests x21 with `cbz`, and on the zero edge reloads x21 from the slot.
  Proving the reload is zero needs "this slot holds the value that was tested",
  which no analysis can express: `AbstractValue` has `.callResult(site)` for x0
  only, and nothing names a register's value at an arbitrary definition. The
  exit stays declined (`machine_return()`).
- **Repeated work.** `basicBlocks()` is rebuilt at 14 call sites, including per
  return instruction in some paths; `calleeName(of:)` re-parses annotation text
  at 29 call sites, several per instruction per pass; every tracer state lookup
  hashed and often parsed a string key. (The tracer's share of the last two is
  fixed; see step 3 and `ValueTracer.CallFacts`.)

## Target

A per-function IR built once after segmentation, owned by one struct, and
consumed by every analysis and renderer.

- **CFG, once.** Dense block ids, typed edges (fallthrough, taken, switch case,
  unresolved indirect), the entry, and the set of blocks reachable only by
  unmodelled edges (landing pads, targets of unresolved branches). Built once
  per function and passed by reference.
- **Typed locations.** `enum Location { gpr(UInt8), vector(UInt8), flags,
  frame(offset: Int64, bytes: UInt8), asyncContextSlot(Int), resultBuffer(Int,
  UInt8) }`. Replaces string keys in `ValueTracer.State` and in every other
  analysis.
- **One frame memory model.** Extracted from `Preservation` and extended:
  per-variable regions from address-taking (`addressTakenFrameOffsets`, moved
  off text onto `StructuredInsn`), MAY escape per region with a whole-frame
  fallback for frame aliases of unknown offset, escape that persists across
  later calls, invalidation of escaped regions at calls and at stores through
  pointers not proven to point elsewhere, caller-owned ranges, and call effects
  from body-proven callee summaries (which registers an outlined fragment reads
  as inputs, which it writes). Every analysis that reads or writes frame facts
  asks this model.
- **Value identity.** Values are named by definition: entry values, the result
  of instruction *A* in location *L*, a call's result in each result register
  (x0–x3, v0–v3, x21 for swifterror, x20 at an async return), and edge-indexed
  φ at joins. A fact about a value is killed when its definition re-executes.
  Branches refine: on the zero edge of `cbz x21` every location holding the
  tested value holds zero.
- **Typed facts.** Enrichment produces `[Fact]` per instruction, an enum
  (`callee`, `arguments([Expr])`, `selfValue`, `await`, `condition`,
  `exit(.normal(Expr?) | .throw(Expr?) | .unclassified)`, `binding`, …).
  Text annotations become a rendering of facts, produced last.
- Above that, the §9.3 layers: typed values, a named-rule simplification pool,
  block-tree structuring, and a thin emitter that makes no semantic decisions.

## Order of work

Each step lands as its own commits. A refactor step must leave every fixture
view (`disasm --structured` and `--pseudo` over `Fixtures/Sample`)
byte-identical and pass `DeterminismTests`; a step that changes output is a
fix, measured and explained like any other.

1. **Typed facts beside the strings.** Add `facts: [Fact]` to `Instruction`.
   Producers write both; consumers move one note kind at a time; the string
   channel is deleted when nothing reads it. Removes the callee-name hazard
   class outright.
   *Started 2026-10-21 with the callee: `Instruction.callee` is fixed where
   a call's target is named and kept through note-only rebuilds; every
   `calleeName(of:)` consumer reads it for calls and branches. The
   annotation still carries the name for display and for instructions
   built by hand. Exits and bindings followed the same day as
   `Instruction.exit` (`.normal(value?)`, `.throw(error)`,
   `.unclassified`), `Instruction.binding` (`let r0 = …`) and
   `thenThrows`: the pseudo statement and the structurer read them, and a
   note that only reads as a return no longer makes one. That fixed real
   output: a string literal's text, split at its double spaces, had been
   printed as a `return` on Clarc and GoodLinks. Typed accessors rather
   than `[Fact]`, because each kind has at most one value per instruction;
   the facts share one optional box, so an instruction without any pays
   one pointer. The rest followed on 2026-10-22 in `Instruction.facts`:
   the statement the pseudo view scanned for (a field write, a setter or
   ivar-helper assignment, `self = [super init]`, a yield, an executor
   hop), `await=`, `jump=`, `cond:`, the loop notes, the field read the
   structurer substitutes into a condition, and `dispatch=self`. That
   fixed real output too: a literal holding one of those notes printed it
   in place of its call, and a field write, jump target or condition whose
   value spelled a literal with a double space was cut there. No renderer
   reads a note from the annotation now; it is display text, and a
   rebuild passes `facts: insn.facts`. The callee is still parsed from the
   annotation for an instruction built by hand without one.*
2. **CFG once.** Share `FunctionCFG` within each analysis phase, then retain
   the final graph for rendering. The graph owns index ranges, block ids,
   successor/predecessor ids and switch cases; instruction views come from
   the current function.

   The initial implementation (2026-10-22) centralized block recovery while
   preserving instruction-order ids and successor order and multiplicity.
   `BasicBlock` views still materialize copies of current instructions.

   1. *Done in `0f0b2716fe07ed3b7122ae5dfd422e2bb0f9ea5d`: build register
      summaries after jump-table recognition (D1). A switch's `br` previously
      looked like a tail call, hiding case clobbers and inventing arguments.
      D2, resolving a `br` into its own function without creating an
      internal edge, was fixed in `277b543`.*
   2. *Done in `a83a2de`: build a local graph after outlined-fragment
      rewriting and `JumpTables.recognize` in `analyzeFunctionBody`. Share it
      with the tracer, setter retrace, async-throw/error-proof/binding block
      builders, probe snapshots, return-path conditions and x8 classifiers.
      Funclet tracing and context-escape analysis also share their graph.
      Internal overloads accept the graph; existing callers keep their
      fallback. No graph retains instruction arrays or escapes streaming
      analysis. A resolved external `br` target rebuilds the graph; call
      naming, notes and facts do not. A proven async return rewrites a
      nil-target `br` to `.return` only after the local graph's last use.
      At that revision the returned function did not retain the graph;
      final-function retention follows in step 2.3. Debug recorder checks compare each
      supplied graph with a fresh graph, and construction budgets detect
      redundant recovery. Fourteen separately compiled mutations failed;
      restored focused and full tests passed. All 335 inputs in four views,
      four large SDK outputs and five app pseudo outputs are byte-identical;
      nine CLI command pairs and 96 explicit current-binary subprocess runs
      pass. All 1,344 positive cost pairs meet default budgets. Three release
      pairs on Clarc and GoodLinks reduce retired instructions by 0.7391%
      and 0.7832%; footprint is mixed. Allocation-history totals remain
      inconclusive because the bounded text exports are incomplete.*
   3. *Final graph ownership done in `43af592`: enriched functions retain
      their final immutable topology. The structurer, JSON, CFG output and
      remaining default tracer/probe/x8/escape/accessor consumers reuse it.
      All three enrichment exits attach a matching graph, after an external
      indirect-tail target has refreshed it. Final async nil-target BR→RET
      preserves the graph's partition and empty successor list; instruction
      views read the final payload. Generic instruction or switch-table
      replacement invalidates the cache, while payload-only changes and
      async metadata preserve it. Public manual construction keeps its safe
      uncached fallback. Twenty separately compiled mutations fail intended
      assertions; restored 22 focused tests and the enforcing 1,353/21 full
      suite pass. All 335 inputs in four views, four SDK outputs, five app
      pseudo outputs and nine CLI pairs are byte-identical; 96 current-binary
      subprocess checks pass. Release A/B numbers and default budgets are
      recorded in PRODUCTION-READINESS.md with their measured scope.*
   4. *OPEN: replace materialized `BasicBlock` instruction copies with views
      for internal consumers, including `AsyncFuncletIndex.trapGuardedRuns`.
      Its merged instruction sequences can be noncontiguous; one index range
      cannot preserve them. Keep public APIs and current trap/switch/order
      semantics, exact output checks and alternating release measurements.
      Final topology retention does not establish allocation-volume savings
      or complete the shared frame memory model in step 4 below.*

      A local async-only block/run/path view prototype was measured and
      reverted on 2026-11-05: three alternating pairs on Clarc and GoodLinks
      establish no CPU improvement and mixed peak footprint despite validated
      async coverage. See the DEAD END record in PRODUCTION-READINESS.md. Do
      not repeat that optimization without new evidence; prioritize the shared
      frame memory model next. A future shared-body IR can revisit views when
      multiple consumers need the same ownership and value identities.

3. **Typed locations in the tracer.** `[Location: AbstractValue]` instead of
   string keys. Pure refactor; measure the speed. *Done for `ValueTracer`
   (2026-10-15), ahead of steps 1 and 2 because string keys were about half
   the tracer's samples: every fixture view, Clarc and GoodLinks unchanged;
   Clarc -12% instructions retired. `Location` carries the escape markers as
   well as places; the other analyses still key by string.*
4. **One frame memory model**, shared by the analyses. This is where the
   `cacheEscape` class of bug is fixed once instead of per analysis; it must
   also keep the Onone spill/reload recovery that a blanket "forget memory at
   every call" rule loses (measured on 2026-10-13: argument spills, string
   interpolation folding, witness-pair loads).

   *First foundation in `6a1fa5e`: `FrameMemoryExtent` and
   `FrameMemoryEffect` provide one MAY-write invalidation decision for the
   tracer and Preservation. Disjoint finite regions, whole-frame reach,
   caller-owned straddles and start-only dynamic writes retain their current
   meanings. Wrapping tracer endpoints and checked Preservation endpoints
   remain explicit compatibility policies; finite Int64 sentinels are not
   reinterpreted as infinity. Durable markers, joins, boundary discovery,
   pointer-loss closure, reload ordering and result/context spaces stay with
   their current analyses. Exact-store footprint sharing follows below;
   the complete shared memory model remains OPEN. This first slice preserves
   output and does not complete step 4.*

   The enforcing 1,360/22 suite, sixteen independently compiled mutant reds,
   restored 56 focused/native controls, exact semantics and 112 subprocess
   checks pass. All 335 inputs in four views, four SDK outputs, five app
   pseudo outputs and nine CLI pairs match. Default corpus costs pass;
   PRODUCTION-READINESS.md records the measured scope and the observed
   temporary-Set allocation path. No allocation-volume saving is established.

   *Exact-store footprints follow in `3f72b65`: both real overlap-kill
   paths use `FrameMemoryEffect`. Canonical empty/single/multiple storage
   gives an exact store a direct inline region without a singleton Set.
   The tracer's explicit legacy region defers trapping endpoint additions
   until a query and preserves write-bound-first short circuiting, including
   the no-old-fact case. Preservation retains checked overflow handling and
   its separate incoming-state ownership policy. Exact overwrite and unknown
   pointer-loss transfers remain distinct; byte/vector widths, pair strides,
   value installation, register-file and outgoing metadata are unchanged.*

   Sixteen new compatibility controls pass against both legacy and migrated
   consumers. Twenty independently compiled mutations fail intended
   assertions; restored 176 focused/native controls and enforcing 1,376/25
   tests pass. All previous outputs and fresh semantics match; 128 explicit
   subprocess checks pass, including saved-slot/register-file fixtures.
   Default corpus budgets pass with scope recorded in PRODUCTION-READINESS.md.
   This does not establish allocation-volume savings or a complete shared
   frame value/layout/provenance model.

   *Shared fact ownership follows in `086bd05`: both tracer State and
   Preservation's slots use `FrameFacts` for lookup, fieldwise must joins,
   effect-selected removal and installation. Concrete record specialization
   keeps Preservation value-only; tracer value, width, register-bank and
   outgoing fields retain independent presence, including explicit unknown,
   orphan metadata and symbolic selects. Lazy projections bridge the tracer's
   existing Location API without a shadow frame map or combined arrays.*

   Existing frontend rules still decide self-isa repair, width/bank veto,
   pointer-loss escape and caller ownership. Their ordering is preserved;
   start-selected clear, exact overwrite and unknown knowledge loss remain
   distinct. State budgets count legacy components, not rows. Layout/boundary
   discovery, MAY carriers, SelfState's MAY slots and result/context spaces
   remain separate; completing step 4 is still OPEN.

   Eleven new tests, twelve compiled assertion-red variants and restored
   34 tests across seven focused suites pass; the enforcing suite passes 1,387/28.
   Fresh semantics, 144 explicit subprocess checks, 336 inputs in four views,
   four SDK outputs, five apps and nine CLI pairs match. Default corpus
   budgets pass with their measured scope in PRODUCTION-READINESS.md. No
   general speed, allocation-volume or retained-heap improvement is claimed.

5. **Value identity and edge refinement.** Recovers declined exits such as the
   -Onone `try` shape and gives conditions and loop variables stable names.
6. **Renderers read the IR**, then the §9.3 layers above it.

Steps 1–3 and the shared write-footprint/fact-store extractions in step 4 are refactors.
Completing step 4 is the intended memory-model soundness payoff. A stopgap
that fixes `cacheEscape` inside the current tracer
(persistent per-region escape, union at joins) is acceptable before step 4 if
it is written so step 4 can absorb it.

## Non-goals

- A rewrite. Every step keeps the existing analyses running and comparable.
- Ghidra's C-shaped pieces (see §9.2 of the comparison study).
- Speed for its own sake. Each performance claim needs an alternating release
  A/B with identical output.

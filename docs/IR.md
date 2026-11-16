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
  joins. Step 4 now shares write footprints, current-frame facts, durable
  escape state and register-fact ownership. Layout discovery and complete
  space/provenance/value unification remain open.)
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
  object regions from proven layout and structured uses of addresses, rather
  than reparsed text. Two calculated addresses can name words of one object;
  address-taking observations alone do not establish its extent. MAY escape
  persists per region, with a whole-frame fallback for unknown provenance.
  Calls and stores through pointers not proven to point elsewhere invalidate
  escaped regions. The model also owns caller-owned ranges and body-proven
  callee effects: which registers an outlined fragment reads as inputs, which
  it writes, and which memory ranges it can write. Every analysis that reads
  or writes frame facts asks this model.
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
   distinct. State budgets count legacy components, not rows. Durable MAY
   reach follows below; layout discovery, register alias provenance, SelfState's
   MAY slots and result/context spaces remain separate. Step 4 remains OPEN.

   Eleven new tests, twelve compiled assertion-red variants and restored
   34 tests across seven focused suites pass; the enforcing suite passes 1,387/28.
   Fresh semantics, 144 explicit subprocess checks, 336 inputs in four views,
   four SDK outputs, five apps and nine CLI pairs match. Default corpus
   budgets pass with their measured scope in PRODUCTION-READINESS.md. No
   general speed, allocation-volume or retained-heap improvement is claimed.

   *Durable escape state follows in `d2f05ad`: both states now store
   their actual MAY frame reach in `DurableFrameReach`. Concrete storage
   keeps original tracer point/below/all/dynamic keys and payloads, or
   Preservation's frozen range Set and whole flag. Presence/count updates,
   ordered payload union, raw intersection, reset and effect emission share
   one implementation. No shadow marker map or second range/whole store
   remains. Whole coverage retains finite identities; dynamic allocation
   evidence alone does not escape memory.*

   Tracer ranges resolve from actual layout evidence at each query;
   Preservation freezes bounds from live entry saves when a pointer escapes.
   Each input resolves transactionally, preserving selected-default Any versus
   finite-empty origins. Caller-owned reach is query-only. SelfState's finite
   read query uses the shared effect with wrapping endpoints; its MAY self
   slots remain separate from must facts. Context progress, state reset,
   pointer-loss closure, alias selection and ownership policies retain their
   existing meanings. Complete layout/provenance/space unification remains
   OPEN.

   Eleven new tests include six controls green on previous production.
   Sixteen compiled variants fail 74 intended assertions; the same union and
   finite-effect omissions fail actual tracer, Preservation-call and SelfState
   read consumers. Both successor orders guard the self-read result that stays
   true once observed. Restored 53 tests/seven suites, enforcing 1,398/30,
   fresh semantics and 152 separate-process checks pass. All 336 inputs in
   four views, four SDK outputs, five apps and nine CLI pairs match. Default
   costs pass; PRODUCTION-READINESS.md records the standalone release scope
   and sampled temporary-Set path. No general CPU or heap saving is claimed.

   *Register-fact ownership follows in `4cafe27`:
   `FrameRegisterFacts` owns both analyses' actual register bindings, with
   sparse Preservation columns for independently present exact values, MAY
   membership and finite alternatives. Common lookup, installation, source-first
   copies, raw must intersection, lost-value walks, per-key input selection,
   reset and current-frame coordinate/access planning replace the separate
   state operations. Borrowed/lazy projections keep raw payloads, orphan finite
   metadata, explicit unknown versus absence, physical NZCV versus reconstructed
   flags and component-weighted counts without shadow stores.*

   Frontend policies retain below-max repair before finite-origin derivation,
   legacy empty-union-to-Any normalization, self-isa repair, pre-veto loss
   enumeration and subsequent escape marking. Escape inputs remain separate
   transactions, so a bounded input survives beside another Any input. Partial
   vector widening, wrapping/checked arithmetic, query-time tracer layout versus
   escape-time live saves, reload ordering and separate result/context handling
   retain their meanings. This is a refactor; full layout, space aliasing,
   SelfState's MAY self slots and value identity remain OPEN.

   Seventeen new tests include eight baseline controls. Eighteen independently
   compiled variants produce 58 assertion issues across 27 required consumer
   checks; restored 22 tests/six suites and enforcing 1,415/35 pass. Paired
   variants fail actual tracer and Preservation consumers; reset's Preservation
   half tests the owner API. The authored three-function fixture has three NM
   symbols/LC_FUNCTION_STARTS and 33 words, returns native 11, and passes array,
   filtered and streaming paths. Synthetic words/targets have independent
   Clang/LLVM checks; no native overflow repair is claimed.

   Fresh semantics match; 184 separate-process captures and 40 probe traces
   match, including 1,620 debug fresh-CFG checks and the intentional absence of
   that DEBUG-only event in release. All 337 inputs in four views, four SDK
   outputs, five apps and nine CLI pairs match. The standalone `ffb6a8c2` release
   against official `1e8304f8` passes all 1,352 default cost pairs: +2.0097%
   retired instructions / -0.6194% summed peak footprints, without override.
   The official gate validates its rebuilt binary separately. Two event-triggered Parser CPU samples
   expose owner meet/selection and resize/move paths; they establish no speed,
   allocation-volume or retained-heap benefit. PRODUCTION-READINESS.md records
   the exact validation and sampling scope.

   *Layout observations are separated from escape bounds in `20c530f`.*
   Immutable `FrameLayout` now carries observed address coordinates, prologue
   save slots and precomputed escape evidence separately. Only the existing
   register-save policy supplies those bounds; calculating an interior address
   no longer proves a different object starts there. Calls, unknown stores and
   transitive loss use the same evidence. The old linear scan could also place
   observations above entry sp after an earlier epilogue, erasing caller-area
   spills. Removing those bounds recovers five Go functions' argument facts;
   matching Go source, machine spills/reloads and paired probes confirm them.

   An authored two-word local exposes the unsafe boundary: native execution
   returns 11, while both old views claimed 7. The fixed views decline. Its
   no-escape control retains native/rendered 7; NM and LC_FUNCTION_STARTS agree
   on three functions and LLVM checks all 20 words. Two compiled variants fail
   15 assertions; restored 27 focused tests and enforcing 1,417/35 pass.
   Twenty-four fresh debug/release fixture captures and fresh semantic exports
   match their references; prior solver statuses are reused without rerunning
   the solver. Seventy-two filtered captures recheck 36 changed app/SDK/IfConfig
   functions without changing their machine instructions.

   Six of 338 inputs change in each of four views. The standalone `adc6ae8e`
   release against published `4aa810c1` passes all 1,356 default cost pairs:
   -2.2367% retired instructions / -0.8690% summed peak footprints. These
   measurements include changed outputs and establish no general speed or heap
   benefit. PRODUCTION-READINESS.md records the reviewed changes and losses;
   the integration gate validates its rebuilt binary separately.

   Two existing controls with native 7 now decline. Recovering them needs a
   proven object extent or callee write footprint. Structured layout discovery,
   complete object/space provenance and value identity remain OPEN; the
   existing save and ownership policies are retained.

   *MAY self-slot ownership follows in `464399e`.* `StoredFrameFacts` now owns
   the tracer's and Preservation's must facts and SelfState's MAY frame slots.
   Concrete dictionary storage retains values and independent metadata; Set
   storage retains self presence without a dictionary of empty payloads.
   Lookup, installation/removal, counts, iteration and effect queries share
   the owner. Must joins still intersect fields, while MAY joins explicitly
   union presence. Exact word clears, partial writes and staged pair spills
   keep their existing rules. The read effect preserves checked query-end
   overflow and wrapping stored-slot ends; empty slots still read nothing.

   Five new consumer controls pass on prior production. Eight new tests,
   ten independently compiled variants failing 207 assertions at 83 test
   locations, restored 24 focused tests and enforcing 1,425/37 pass. Clang and
   LLVM check 75 words in 11 analysis cases; these are not native-executed ABI
   functions. Four permanent ordering cases exercise initializer self spills;
   76 ordering captures and 24 explicit debug/release captures agree.

   All 338 inputs in four views, five apps, four SDK workloads and nine CLI
   pairs are byte-identical. Fresh semantic exports retain prior solver
   statuses without rerunning the solver. Standalone `32f9b470` against
   published `14341da6` passes all 1,356 default cost pairs: -0.0078% retired
   instructions / -0.1409% summed peak footprints. App footprints vary from
   -7.46% to +19.81%; no general speed or heap benefit is established. The
   integration gate validates its own rebuild separately.

   This closes the MAY-slot storage extraction. Complete layout, object and
   space provenance, ownership proofs, callee memory footprints and value
   identity remain OPEN. Result/context spaces and register alias policies
   retain their existing representations.

5. **Value identity and edge refinement.** Recovers declined exits such as the
   -Onone `try` shape and gives conditions and loop variables stable names.

   Landed (2026-11-11) in a narrower, block-local form: the spill and the
   branch must be in one block, so the identity is proved by replaying that
   block and needs no fact that outlives it; see PRODUCTION-READINESS.md.
   The cross-block design below stays the plan for spills made before the
   branch's block.

   Design (2026-11-11). The target is `Reconstruction.typedForward`
   at -Onone: `bl typedPick; str x21, [sp, #0x18]; cbz x21, ok; …; ok: ldr x21,
   [sp, #0x18]; …; ret`. The source returns `r0 + 1` on that path; swiftdc
   renders `machine_return()` because the reload of x21 is unknown.

   - *Identity, not a value.* After a call that may throw, x21 is `.unknown`
     today, and it must stay unknown to every consumer that reads it as a
     value: `exitErrorValues` records any x21 that is not `.unknown`, and the
     exit classifier reads a recorded value as the thrown error. So the
     identity is a separate fact, not a new `AbstractValue` case: a State key
     `copyOf(slot) = register` (and register-to-register), meaning "this slot
     holds the word that register held when it was stored, and neither has
     been written since". Nothing renders it.
   - *Invalidation.* Any write to the register or to any byte of the slot ends
     the fact. An audit of the write paths (2026-11-11) rules out hooking
     each one: registers change through 105 subscript assignments in
     ValueTracking.swift plus `installCopy` and `reset`; frame words through
     the subscript, `patch` (3 sites), `removeComponents` (2), `forget` (2)
     and `clearValueStarts`, and the meet. So the identity rides on the facts
     themselves: the spill stamps one token on the register's fact and the
     slot's fact, every write replaces a fact (dropping its token) whatever
     path it takes, and refinement requires the two tokens to match. A join
     keeps a token only where its facts are equal on every predecessor, which
     the existing intersection already does once the token is part of the
     fact. Unknown-valued registers and slots hold no fact today, so the
     token needs a fact that is present but valueless: that is the change
     to `TraceFrameRegisterFacts` and `TraceFrameFact` this step makes.
   - *Refinement point.* The meet in the forward fixpoint is the only place:
     when an incoming state's predecessor ends in `cbz`/`cbnz` on register R
     and this block is the edge where R == 0, that state is refined before
     the meet: R becomes `.immediate(0)`, and so does every slot whose
     `copyOf` names R. `tbz`/`tbnz` and flag branches are out of scope at
     first. The snapshot pass and the per-predecessor exit replay
     (`exitErrorValuesByPredecessor`) read the same refined states, or a
     path would classify differently from the fixpoint that proved it.
   - *Soundness argument.* On the zero edge R is 0, and a slot that still
     holds R's stored word holds 0. Both facts are exact, so the refinement
     claims nothing a run could contradict. A refinement that reached a slot
     after an intervening write would fabricate a value, so the invalidation
     rules carry the whole proof and each needs its own mutation test.
   - *Tests.* The -Onone and resilient typedForward renders (`return r0 + 1`
     natively checked), plus hand-built bodies: a store to the slot between
     the spill and the branch, a write of R, a call between, a join where one
     path lacks the fact, and the nonzero edge. Each must stay declined, and
     each invalidation rule is mutated away to watch its test fail.
   - *Cost.* One more key family in every block state; the cost gate
     measures it, and a function with no `cbz`/`cbnz` on a spilled register
     never installs one.
6. **Renderers read the IR**, then the §9.3 layers above it.

Steps 1–3 and the step 4 extractions of write footprints, fact storage,
durable reach, register-fact ownership and MAY self-slot ownership are refactors.
Completing step 4 is the intended memory-model soundness payoff. A stopgap
that fixes `cacheEscape` inside the current tracer
(persistent per-region escape, union at joins) is acceptable before step 4 if
it is written so step 4 can absorb it.

## Non-goals

- A rewrite. Every step keeps the existing analyses running and comparable.
- Ghidra's C-shaped pieces (see §9.2 of the comparison study).
- Speed for its own sake. Each performance claim needs an alternating release
  A/B with identical output.

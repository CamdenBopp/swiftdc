# Settling on an intermediate representation

swiftdc has no IR between Capstone's decoded instructions and rendered text.
This document says why that now limits soundness more than any single missing
rule, what the IR should be, and the order to build it in so that every step
ships on its own, output-identical unless it is a deliberate fix.

It builds on, and does not replace, the layered target in
[decompiler-comparison.md §9.3](research/decompiler-comparison.md) (effect-explicit
ops, edge-indexed φ, typed values, a simplification rule pool, block-tree
structuring, a thin emitter). That section argued from design debt. This one
argues from defects found since, and puts the memory model first, because that
is where the open soundness bugs are.

## What the code does today

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
  joins. The duplication it describes remains.)
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
2. **CFG once.** A `FunctionCFG` built at segmentation and threaded through
   enrichment, the tracer, the summaries and the structurer. Measure with a
   release A/B on a large app.
3. **Typed locations in the tracer.** `[Location: AbstractValue]` instead of
   string keys. Pure refactor; measure the speed. *Done for `ValueTracer`
   (2026-10-15), ahead of steps 1 and 2 because string keys were about half
   the tracer's samples: every fixture view, Clarc and GoodLinks unchanged;
   Clarc -12% instructions retired. `Location` carries the escape markers as
   well as places; the other analyses still key by string.*
4. **One frame memory model**, used first by the tracer. This is where the
   `cacheEscape` class of bug is fixed once instead of per analysis; it must
   also keep the Onone spill/reload recovery that a blanket "forget memory at
   every call" rule loses (measured on 2026-10-13: argument spills, string
   interpolation folding, witness-pair loads).
5. **Value identity and edge refinement.** Recovers declined exits such as the
   -Onone `try` shape and gives conditions and loop variables stable names.
6. **Renderers read the IR**, then the §9.3 layers above it.

Steps 1–3 are refactors. Step 4 is the first that changes output, and it is the
soundness payoff. A stopgap that fixes `cacheEscape` inside the current tracer
(persistent per-region escape, union at joins) is acceptable before step 4 if
it is written so step 4 can absorb it.

## Non-goals

- A rewrite. Every step keeps the existing analyses running and comparable.
- Ghidra's C-shaped pieces (see §9.2 of the comparison study).
- Speed for its own sake. Each performance claim needs an alternating release
  A/B with identical output.

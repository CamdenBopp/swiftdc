# Parallel development: plan, measurements, ownership

How several agents work on swiftdc at once without wrecking each other's
builds, measurements or merges. Written 2026-11-02 at dev c340e62 from three
read-only audits (dependency map, build and test timing, fixtures and
integration). The raw notes stayed in the session scratchpad. The numbers
below are what they measured, with the conditions they were measured under.

## What costs time today

Measured on the 12-core, 16 GB host. Other builds were running for most of
these runs (load 4 to 42, logged per run), so the absolute numbers are noisy.
The ratios held.

| Step | Median | Notes |
|---|---|---|
| Cold `swift build --build-tests` in a new worktree | 275 s | 62 s of it is package resolve |
| No-op rebuild | 7.4 s | nearly all manifest loading and planning |
| Body edit, any Core file, `--build-tests` | 19-22 s | rewrites 1 Core `.o`, **0 of 174** test `.o` |
| Internal signature change | 24 s | still 0 test `.o` |
| Full enforcing suite | 145 s | 984 tests, about 850 CPU-seconds |
| Suite without the three outliers | 96 s | 590 CPU-seconds |
| One test file (`--filter 'X\.swift'`) | 1.7 s + the tests | fixed overhead |
| `Fixtures/Sample/build.sh` | 96-118 s | 147 serial stanzas, about 190 compiler calls |
| Blast radius, fixtures, 4 views, release, `-P6` | 52 s | 217 products |
| Blast radius, 8 swift-syntax dylibs, structured | 22 s | |

Findings that change the guidance:

- A body edit recompiles no test files. CLAUDE.md said it recompiled all of
  them, and that line is now corrected.
- `swift test --parallel` measured identical to the default. All 984 tests are
  Swift Testing, which already runs them concurrently. Only cutting CPU makes
  the suite faster.
- Per-test durations from a full run are meaningless, because every test
  starts at once and the clock includes queueing. Rank tests from filtered
  runs.
- Three tests set the suite's critical path:
  - `streamingWholeImageMemoryStaysLow` (76 s), the dyld-cache memory test.
  - Three stripped-Go-image tests (45, 41 and 16 s). Go is not a target.
  - The every-fixture sweeps in FunctionCFG, ExitFact and CalleeFact (about
    23 s each). Each redoes all 215 dylibs.
- ReconstructionTests runs 61 filtered disassemblies of one image. Each pays
  the image setup (`ObjCMetadataIndex.build`, `matchedRanges`) again, about
  100 CPU-seconds in all.
- A fresh worktree pays two costs before its first test: the 275 s cold build
  and the 100 s fixture build. The fixture half is now gone (stage 1).
- Merge conflicts concentrate in process files, not code. Since 2026-10-01:
  - `docs/PRODUCTION-READINESS.md`: 331 commits.
  - `Fixtures/Sample/build.sh`: 139.
  - `FixturePresenceTests.swift`: 115.
  - `Disassembler.swift`: 195, the only code file in that range.
  - `ValueTracking.swift` follows at 94.

## Dependency map

Measured by a token scan of identifiers across files, at c340e62. Edge
weights count distinct identifiers used. "core" is `Disassembler.swift`
outside `enrichCallArguments`, and "enrich" is that function, 3,324 lines.

```
            +---------- load (BinaryLoader, MachOPreflight, CacheReader) <---+
            |                                                                |
  arm64 ----+--> tracer (ValueTracking, TypeInference) <---- abi ----------> meta (FieldMap, *Index,
 (Capstone,  |        ^        ^                         (SwiftLowering,      ObjCMetadataIndex,
 Machine-    |        |        |                          IndirectResults,    AsyncFuncletIndex)
 Detail,     |      cflow    enrich ---------------------> CalleeRegister-        ^
 Instruction-|   (CFG, Struct-  (enrichCallArguments)      Summary, ObjCArg-      |
 Semantics)  |    urer, Jump-                              ABI, Specialized-   core --+
             |    Tables)                                  Signature)
             +--> render (Pseudo, SwiftIdioms)  <-- tracer, abi, cflow, enrich, core
```

The edges that matter for ownership:

- **abi → render (45)**, **enrich → render (35)**, **cflow → render (25)**,
  **core → render (12)**. `calleeName`, `splitSignature`, `knownCArity`,
  `cPrototype` and `parameterType` live in `Pseudo.swift` and
  `SwiftIdioms.swift`, but they are signature parsing, not rendering. This
  is the one cycle that makes an ABI change touch a renderer file.
- **meta → load (111)** and **load → meta (17)**: metadata and loading are
  one subsystem in practice.
- **arm64** depends only on tracer value types and Probe. It is the cleanest
  leaf.
- The ABI type-lowering question is answered in eight places
  ([ABI-INVARIANTS.md](ABI-INVARIANTS.md)). `SwiftLowering` is the start of
  the shared answer.

### The shared contract

These types cross every boundary. A change to their shape is an
**interface change** (rules below):

- `Instruction.callee`, `Instruction.facts`, `Instruction.annotation`
  (the note format).
- `AbstractValue` and its operators.
- `SwiftLowering`, `CallResultBank`, `CallFacts` / `CallFactsCache`.
- `DisassembledFunction`, `PerFunctionContext`.
- `ProbeEvents.swift`, the event catalogue.

The planned common ABI model is a `CallContract` built from `CallFacts`. It
holds one argument layout, the result convention, the self convention and
the error convention per call site, computed once and read by the tracer,
enrichment and renderers. It extends `SwiftLowering` from types to call
sites. It lands as its own refactor (stage 5), never inside a soundness fix.

## Ownership

One owner per subsystem at a time. The owner may edit the subsystem's files
freely; anyone else edits them only through the interface-change rule.

| Subsystem | Files | Owned tests (filter) |
|---|---|---|
| ARM64 semantics | `Capstone*`, `MachineDetail`, `AArch64AliasCanon`, `InstructionSemantics`, `LiteralScan`, `MagicConstants`, `MagicDivision` | `Semantics\|Capstone\|Alias\|Magic\|VectorLane\|Fmov\|Conversion` |
| ABI and calls | `SwiftLowering`, `IndirectResults`, `CalleeRegisterSummary`, `ObjCArgumentABI`, `SpecializedSignature`, the ABI statics and `enrichCallArguments` in `Disassembler.swift` | `ABI\|Arity\|CallArg\|SwiftLowering\|Signature\|Specializ\|Async` |
| Value propagation | `ValueTracking`, `TypeInference`, `ProbeSnapshots` | `Tracer\|Value\|Exit\|Condition\|Fact` |
| Control flow | `CFG`, `Structurer`, `JumpTables` | `CFG\|Struct\|Switch\|Loop\|JumpTable` |
| Swift metadata and loading | `FieldMap`, `*Index`, `MetadataSymbolizer`, `ObjCMetadataIndex`, `AsyncFuncletIndex`, `BinaryLoader`, `MachOPreflight`, `CacheReader` | `Field\|Index\|Metadata\|MachO\|Dyld\|Fat\|ObjC` |
| Rendering | `Pseudo`, `SwiftIdioms`, the `render*` functions | `Pseudo\|Render\|Reconstruction\|Idiom` |
| Audit and tooling | `Tools/`, `Benchmarks/compiler-grounded`, `Probe*` | `Probe\|Determinism\|Differential` |

`Disassembler.swift` has two owners by region. ABI owns lines from the ABI
statics through `enrichCallArguments`; core (the integrator) owns the rest.
Splitting it into files along that line is stage 5, a pure move.

### The interface-change rule

An agent that needs a shared-contract change does not make it alongside its
fix. It:

1. Writes the proposed change (new case, new field, renamed fact) and its
   consumers into its handoff, and stops that line of work.
2. The integrator lands the interface change alone, as a `(refactor)` commit,
   through the gate.
3. Owners rebase onto it and continue.

Two agents never change a shared-contract file in the same window. Adding a
new probe event is exempt: append-only, a single line in
`ProbeEvents.swift`.

## Test classification

Four tiers. Each one is a superset of the tier before it.

| Tier | When | Command | Time |
|---|---|---|---|
| 1. Individual | every edit | `swift test --skip-build --filter '<TestFile>\.swift'` or a test name | 2-20 s |
| 2. Subsystem | before asking for review | the owner's filter from the table above | 10-40 s |
| 3. Affected | before handing to the gate | tier 2 plus every subsystem that imports a changed shared-contract file, plus `Determinism` and `FixturePresence` | 40-100 s |
| 4. Full | the gate only | `SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build` | 145 s |

Tier 4 is never skipped before a push; CLAUDE.md requires it per commit, and
the gate enforces it. Tiers 1-3 are what an agent runs while it iterates.

A `--filter` regex matches the test's file name as well as its name, so
`'SmokeTests\.swift'` runs exactly that file. That is why the filters work
without tags. Swift Testing tags (`.slow`, `.wholeImage`, `.dyldCache`,
`.subprocess`) are stage 3, so the outliers are skipped by tag instead of by
a regex of names.

### Mutation proofs are unchanged

Every fix still shows its test red under a mutation of the fix (CLAUDE.md,
"Verification, exactly"). The tiers change only how often the full suite
runs, never whether the mutated build is checked. The batched mutation loop
runs at tier 1: apply the mutation, rebuild, run the filtered test, restore.
The gate then proves the restored tree green at tier 4.

## Worktrees

- One worktree per agent, from `origin/dev`, on a branch of its own. Its own
  `.build` and `.build-release`, so no agent rebuilds another's tree or
  measures while another compiles in it.
- `Tools/fixtures.sh` brings fixtures in from the content-addressed cache:
  one build per distinct fixture input on the whole host, then a 0.4 s APFS
  clone per worktree.
- The cold Swift build (275 s) is the remaining fresh-worktree cost.
  Re-measure before copying another tree's `.build` into a new worktree:
  SwiftPM embeds absolute paths, and that has not been measured to work.
- **Memory:** at most two agents compile at once on this host. A release
  build and a debug suite together peak near 6 GB. Every large-app run goes
  through `Tools/audit/guard.sh`.

## The integration gate

`Tools/integration-gate.sh [--push]` is the only path to `origin/dev`. It
runs one at a time on the host, behind a lock:

1. HEAD is on `dev`, clean, and fast-forwards `origin/dev`. An agent's branch
   is rebased onto dev by the integrator, one branch at a time.
2. Fixtures come from the cache.
3. The full enforcing suite runs, with the release build beside it.
4. Blast radius against `origin/dev`'s release binary covers all four views,
   the fixtures and the swift-syntax dylibs. The gate fails on a render that
   traps now but did not before. Every other changed line must be explained
   in the commit, and the gate prints where the diffs are.
5. `--push` pushes.

Release binaries are kept per commit, so the next gate's baseline is already
built. The expected gate time on a cache hit is the suite (145 s) plus the
blast radius (about 75 s). That makes about 4 minutes, while a release build
that overlaps the suite stays off the critical path.

### Expensive audit verification stays separate

The compiler-grounded audit (`Benchmarks/compiler-grounded`, native-execution
and z3 oracles, app sweeps under the memory guard) is not in the gate. It
runs after a batch of soundness commits, or nightly, against a pushed commit.
Its results go to PRODUCTION-READINESS with the commit they measured
(`SWIFTDC_COMMIT`). Fast checks prove that nothing changed unexpectedly. The
audit measures whether what changed is right.

## Plan, in stages

Each stage is measured before and after and lands through the gate on its
own.

1. **DONE: fixture cache, blast radius, gate scripts.** No source change.
   Measured on a fresh build: miss 50 s, hit 0.35-0.54 s, and the suite
   passes on restored products (984 tests).
2. **DONE: conflict hotspots.**
   - `FixturePresenceTests` derives its required list from the complete
     `Fixtures/Sample/…` literals in the test sources, plus eight paths
     tests build by interpolation. That is 209 paths against the 190
     hand-listed, and every old entry is kept.
   - `docs/PRODUCTION-READINESS.md` and `handoff.md` merge with `union`.
   - Measured: two branches that each add a readiness entry at the same spot
     and a fixture test. The rebase conflicts without the attribute and is
     clean with it, keeping both entries.
   - `build.sh` stays a conflict point until stage 4.
3. **Test tiers.**
   - Tag the outliers. The Go tests leave the default run (Go is not a
     target) but stay in the gate.
   - A process-wide analysis cache in the test target, keyed by file
     identity. The sweeps and ReconstructionTests stop redoing whole-image
     work.
   - Acceptance: tier 4 falls by at least 30 s at matched load, with the
     test count unchanged.
4. **build.sh in parallel.**
   - One stanza per file, sorted and run with bounded parallelism.
   - Acceptance: a miss in under 30 s with byte-identical swiftdc renders.
   - Adding a fixture then creates a file instead of editing a shared one.
5. **Ownership moves.** Each is a pure `(refactor)` commit with
   byte-identical renders in all four views:
   - Signature parsing moves out of `Pseudo.swift`.
   - The ABI statics move to `CallContract.swift`.
   - `enrichCallArguments` gets its own file.

## Acceptance criteria for the whole effort

- **Fixture cost per new worktree:** 100 s down to under 1 s on a hit.
  Measured: 0.35-0.54 s.
- **Gate:** at most 5 minutes on a fixture and baseline cache hit, at low load.
- **Focused-test latency:** under 25 s from an edit to a tier-1 result.
- **Full-suite latency:** at most 115 s at low load after stage 3, against
  145 s.
- **Duplicated work:**
  - Fixtures built at most once per input on the host.
  - A baseline release binary built at most once per commit.
  - No test that re-derives a whole image another test already analysed.
- **Integration failures:**
  - Zero conflicts in the three process files across concurrent branches.
  - Every gate failure names its step and its log.
- **Behaviour:** the suite count never drops, all four views are
  byte-identical across every refactor stage, and the mutation-proof
  requirement is unchanged.

## Found while building this

- `swiftdc disasm`, `interface`, `objc` and `analyze` trap on
  `Fixtures/Sample/abi_source_aliased.o`, a 424-byte object file, at a
  `try!` in MachOKit's `DyldCache.swift:87` (`offsetOutOfBounds`).
  `sample_objc.o` fails cleanly. The old render scripts never ran `.o`
  files; the new blast radius renders every Mach-O product. Robustness,
  OPEN.
- 23 stale products were left in the main checkout's `Fixtures/Sample` from
  removed fixtures. No test, script or source referenced them, but the
  every-fixture sweeps were reading them. A cache restore clears them.
- `DeclarationPlacementTests.aStrippedCopyLoadedAfterItsOriginalReadsOnlyItselfIfPresent`
  failed once in eight full runs. The stripped copy printed the original's
  `Local #1 in` names, through the per-image cache keyed by install name and
  UUID. It looks like a race, so it is soundness, OPEN.
- The release build in `.build-release` after this session's edits took
  530 s against the 70 s that CLAUDE.md quotes. Another project's build was
  running at load 400+, so this needs a re-measurement before the table
  changes.

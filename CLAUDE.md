# swiftdc: working agreement

A Swift-aware Mach-O decompiler for arm64. The goal is a **production**
decompiler: output you can trust without checking it against the disassembly
by hand. The core rule is **decline rather than guess**: a value, name, type,
callee or condition that cannot be proven renders `?` (or stays raw), never a
plausible guess. A wrong render is worse than a missing one, because a reader
cannot tell it apart from a right one.

## Authority hierarchy

When sources disagree, believe them in this order:

1. Current source and tests at HEAD.
2. Git history. `git log -S<symbol>` finds when a behaviour appeared, and
   commit messages carry the reasoning and the numbers.
3. Reproducible measurements: a command anyone can re-run.
4. `docs/research/`: true when written, often stale.
5. Conversation memory and [handoff.md](handoff.md): the weakest. A compacted
   conversation can carry a "next task" that already shipped.

When a doc turns out stale, fix it in the same change.

## Priority order

Work on whatever most limits production readiness. Track state in
[docs/PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md).

1. **Soundness**: fabricated or misattributed semantics.
2. **Completeness**: silently omitted code or metadata.
3. **Robustness**: crashes, malformed input, unusual binaries.
4. **Determinism**: same input, same output, across processes.
5. **Correctness across optimization levels**: -Onone, -O, -Osize lower
   differently. A fix proven at one is not proven at the others.
6. **Test coverage for every CLI path**, unfiltered and whole-image included.
7. **Diagnostics**: "nothing exists" and "analysis failed" never read the same.
8. **Performance and memory** on large apps and frameworks.
9. **Reconstruction quality**: real, but last.

## The empty-result rule

Never accept an empty or unusually small result until it has been checked
against independent binary evidence: `LC_FUNCTION_STARTS`, the symbol table,
the export trie, or a raw `llvm-objdump` run. A parser bug once printed
`// No functions matched.` for a 446-function dylib, and no test noticed
because every test passed `--function`.

- In code, an empty result consults an oracle before it is returned
  (`DisassembleError.parsedNothing` is the pattern). A `try?` that turns a
  failure into an empty result breaks this rule.
- In diagnostics, one message never covers two causes.

## Map of the code

`Sources/SwiftDecompilerCore` (library) and `Sources/swiftdc` (CLI). Most of
the analysis is in a few large files:

| File | Owns |
|---|---|
| `Disassembler.swift` | Entry points (`disassemble(path:)`, `disassemble(machO:)`, `disassembleStreaming(machO:transform:)`), segmentation and naming, `ReferenceResolver` (names for addresses, C strings, binds, `ChainedFixupTable`), `PerFunctionContext`, `analyzeFunction`, `enrichCallArguments` (argument layout, value rendering, return values, async notes) |
| `ValueTracking.swift` | `ValueTracer`: the forward abstract interpreter over `AbstractValue`; call sites, exit values, branch conditions, loop inductions |
| `Structurer.swift` | `ControlFlowStructure`: if/else/loop/switch structuring, the text-path branch conditions, post-dominators. It runs on its own large-stack `Thread` |
| `Pseudo.swift` | Flat statements, callee-name parsing from annotations, runtime-noise hiding, ObjC send idioms |
| `AsyncFuncletIndex.swift` | Async funclet chains, owners, suspension points |
| `CalleeRegisterSummary.swift` | What a signatureless callee reads and which callee-saved registers it does not preserve |
| `JumpTables.swift`, `CFG.swift` | Switch recovery, basic blocks |
| `FieldMap.swift`, `SelfTypeIndex`, `VTableIndex`, `EnumCaseIndex`, `PayloadEnumCaseIndex`, `ClassTypeIndex`, `MetadataSymbolizer` | Metadata-derived names and layouts |
| `ObjCMetadataIndex.swift`, `ObjCSelectors.swift`, `ObjCArgumentABI.swift` | Objective-C classes, IMPs, selectors, outgoing signatures |
| `CallGraph.swift` | `xrefs`. `CallGraph.sites(of:)` is the slimmed per-function input used when streaming |
| `Probe.swift`, `ProbeEvents.swift` | Instrumentation (below) |
| `MachOPreflight.swift`, `BinaryLoader.swift` | Validation and loading. Malformed input must fail as an error, never a trap |

The pipeline:

1. **Decode.** An unfiltered file decodes with llvm-objdump for its listing
   text, with Capstone attached for detail. A filtered run, a dyld-cache
   image and `xrefs` decode with Capstone in process.
2. **Segment** at `LC_FUNCTION_STARTS`, symbols and ObjC IMPs.
3. **Analyse** with `analyzeFunction`: tracer, then enrichment.
4. **Render** from `render`, `renderPseudo`, `renderStructured`,
   `renderCFG` or JSON.

Stages hand facts to each other as notes in `Instruction.annotation`, each
note separated by **two spaces**: `→ name`, `args(…)`, `self=…`, `await=…`,
`cond: …`, `return …`, `let r0 = …`, `jump=…`. A new note must never look
like a callee name to `calleeName(of:)`/`stripNotes`.

The whole-image array path holds about 1 KB per instruction. A large app
does not fit in it, so a new whole-image mode should stream
(`disassembleStreaming`) and keep only what it needs.

## Branches, commits, pushes

- Work on `trial/unified-merge`, which tracks `origin/dev`. Push with
  `git push origin HEAD:dev`. **Never commit to or push master**: merging
  dev into master is the owner's call. Don't push to any other repository
  without asking.
- **One provable behaviour per commit.** The subject is imperative and names
  its axis in parentheses: `Decline a branch whose flags come from an
  unmodelled setter (soundness)`. The axes are soundness, completeness,
  correctness, determinism, speed, memory, diagnostics, validation, tests,
  refactor and docs. A refactor that only enables later work lands on its
  own.
- The body is an engineering record: the symptom (with the real binary and
  function), the mechanism, what changed, the measured numbers, the fixture
  blast radius, then a `Verified:` line naming the tests, the mutation each
  was seen red under, and the suite count.
- No attribution or co-author lines in commits or PRs.
- When several fixes share files, split them into separate commits anyway:
  save the full files, reverse-apply the later hunks, then build and run the
  suite at **each** intermediate state before committing it.

## Verification, exactly

1. **Reproduce first.** Write or reduce a fixture that shows the wrong
   output with the current binary. Keep a release copy of the pre-change
   binary in the scratchpad as the baseline.
2. **Prove the test red.** Mutate the fix away (revert the hunk, or `if false`
   the branch), rebuild, and watch the specific test fail, then restore.
   Mutate each half of a two-part fix separately: a test that only fails when
   both are removed guards neither. If a mutation survives, write a test that
   kills it (a synthetic `CapstoneEngine().disassemble(Data(words), address:)`
   body, or a hand-built `DisassembledFunction`).
3. **Always rebuild before running tests.** `swift test --skip-build` runs
   whatever binary is there. Restoring a source file without rebuilding has
   produced false reds and false greens more than once.

   ```bash
   swift build --build-tests 2>&1 | grep -E "error:|Build complete"
   swift test --skip-build --filter "<test name>"
   SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build   # full enforcing suite, before every commit
   ```

4. **Measure the blast radius.** Render every fixture with the baseline and
   the new build (`disasm <f> --structured`, plus `--pseudo` or the plain
   listing when they are affected), diff, and explain every changed line in
   the commit. An unexplained change is a regression until shown otherwise.
   Several "regressions" turned out to be previously wrong renders the fix
   exposed, and those belong in the commit message.
5. **Recheck the real binary** the defect came from. A probe count (below) is
   a cheap measure of how many sites a fix moved.
6. **Survey every entry point**, not the convenient one. `disasm`, `dump`,
   `layout`, `interface`, `objc`, `xrefs` and `analyze` take different paths,
   and a robustness result on one does not carry over.

## Fixtures

Everything lives in `Fixtures/Sample/`. The built products are git-ignored.
Run `Fixtures/Sample/build.sh` once after a fresh checkout.

To add a fixture:

1. Write the source yourself: a reduction of the shape, never code copied
   from a private app.
2. Add a `build.sh` stanza with an `echo "==> what and why (file, -O)"` line,
   using the optimization level the bug needs. Bugs are often -O or -Osize
   only.
3. Build it once by hand.
4. Write a test named `…IfPresent` that returns early when the fixture is
   missing. `swift test` stays green on a clean checkout, and
   `SWIFTDC_REQUIRE_FIXTURES=1` turns a missing fixture into a failure.
5. Wrap a disassembly in a test with `withStableDependencies { … }`.

A comment in the fixture source names the lowering it exercises and the
true behaviour, for example "`cmp; ccmp …, ge; b.lt`: taken iff
lo <= x < hi".

## Soundness idioms

- When two pieces of evidence disagree (folded addresses, ObjC bindings,
  field-map collisions, merged `Tm` functions), decline. Never pick one.
- A bound that is hit (visit caps, depth caps) must fall back to claiming
  nothing. It must never fall back to the last state it had.
- A register "unknown" is spelled both `.unknown` and absent in tracer
  states. Compare facts, not dictionaries (`sameFacts`).
- Read flags from the last instruction that set them (Capstone
  `updatesFlags`). Carry conditions (`b.hi/hs/lo/ls`) are unsigned and
  render `>ᵁ` and friends.
- A call that returns nothing produces no x0, and a callee takes only the
  arguments its signature or body proves.

## Determinism

`Set`/`Dictionary` order changes with every process (per-process hash seed),
so output must never depend on it. Iterate `.sorted()`, and break `max(by:)`
and `min(by:)` ties explicitly (a post-dominator tie went to hash order:
six runs, six outputs). In-process repetition proves nothing; the only real
check is `DeterminismTests`, which compares separate processes. Add a case
there when a fix touches ordering.

## Instrumentation (`--probe`)

See [docs/INSTRUMENTATION.md](docs/INSTRUMENTATION.md). In brief:

- **Adding a probe** takes an event in `ProbeEvents.swift` plus a call such as
  `Probe.record(.event, at: address, ["key": .int(n)])`. No plumbing: the
  recorder and the current function are task-locals.
- **Categories:** decision, decline, limit, claim and metric. A claim is a
  statement an outside oracle can check.
- **Never let analysis read a recorder.**
  `probeRecordingDoesNotChangeOutputIfPresent` enforces that probes cannot
  change output.
- **Wrap a pass that repeats work in `Probe.muted`,** so its events are not
  counted twice.
- **Carry `Probe.context` across any new raw `Thread`.** Task-locals do not
  cross threads.
- **Use probes to find bugs:** `swiftdc xrefs <app> --unreferenced --probe -
  --probe-summary` gives decline and limit counts across a whole app in one
  run.

## This host: memory and measurement

- 16 GB of unified memory, and runaway runs have crashed it. Guard large runs
  on **footprint**, not RSS (compressed pages leave RSS):
  `Tools/audit/guard.sh <outdir> <kill-MB> -- swiftdc …`. Kill well below
  8 GB, because the guard samples once a second and a spike can be shorter.
- Unfiltered `disasm`/`analyze` on a large app holds the whole image (Enchanted
  debug, 7M instructions, would need 7 GB+); filter with `-f`, or use `xrefs`,
  which streams.
- Measure with a **release** build (`swift build -c release`, about 5
  minutes), copied to the scratchpad so later edits cannot change it:
  `/usr/bin/time -l` for wall time and `peak memory footprint`, and `cmp` the
  outputs.
- For A/B runs, alternate the two binaries back to back, at least three
  rounds, and report medians. Don't compile while measuring.
- A measured idea that doesn't beat baseline is reverted and recorded as a
  DEAD END in PRODUCTION-READINESS.md, so it is not retried.

## Docs ship with code

Every behaviour change updates
[PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md) in the same commit or
the one right after:

- **FIXED** with the commit hash, the measured before and after, and the
  command;
- **OPEN** with the evidence;
- **DEAD END** with the numbers.

Also update `docs/INSTRUMENTATION.md` when the event catalogue changes, and
prune `handoff.md` as items ship.

## Privacy: this repository is public

- Never commit a private app's code, string literals, function bodies or
  audit report. Reduce to your own fixture.
- App names and aggregate counts are fine.
- The devices and apps README example uses `example.com` placeholders, never
  a real device capture.
- The app audit harness ([Tools/audit](Tools/audit/README.md)) reads its app
  list from the git-ignored `Tools/audit/apps.conf`.

## Gotchas

- SwiftPM warns that `machokit` has two identities: MachOKit is pinned to the
  `CamdenBopp/MachOKit` fork for a `MachOFile.cache` performance fix. The
  warning is expected. Revert to upstream when that fix ships there.
- `llvm-objdump` comes through `xcrun`. Capstone 6 builds from source as a
  SwiftPM dependency; there is no Homebrew capstone.
- zsh: `status` is read-only, so use `rc`. An unquoted `$cmd` does not word-split
  (use `${=cmd}`), and a failed glob aborts the command, which once killed a
  memory guard mid-run.
- When piping into `grep` or `tail`, the exit code you see is the last
  command's. Check the real one.

## Build

```bash
Fixtures/Sample/build.sh                # build fixtures once (git-ignored)
swift build                             # .build/debug/swiftdc
swift build --build-tests               # before any `swift test --skip-build`
SWIFTDC_REQUIRE_FIXTURES=1 swift test   # enforcing: a missing fixture fails
swift build -c release                  # for any timing or memory number
```

Requires Apple Silicon, Xcode 26+ (Swift 6.3+; tools version 6.2, macOS 15
deployment). `brew install openssl@3` is needed only for the device
commands.

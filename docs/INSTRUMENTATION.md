# Instrumentation

swiftdc can explain what it decided, what it declined and why, how often, and
what it claimed, as typed events. Use it for three things:

- debugging a rendering without editing source;
- measuring completeness on a real app;
- letting an oracle outside swiftdc (DWARF, objdump, the source, a test)
  check a claim.

The code is [Probe.swift](../Sources/SwiftDecompilerCore/Probe.swift) and the
event catalogue is
[ProbeEvents.swift](../Sources/SwiftDecompilerCore/ProbeEvents.swift).

## Using it

```bash
swiftdc disasm <bin> --structured --probe trace.jsonl      # every event, then a summary line
swiftdc xrefs <bin> --unreferenced --probe - --probe-summary  # counts and times only, on stderr
swiftdc disasm <bin> -f Parser --structured --probe t.jsonl \
    --probe-filter 'category=decline|limit,function=parse'
```

`--probe` works on `disasm`, `xrefs` and `analyze`. Each line is one JSON
object. The last line is the summary:

```json
{"seq":12,"event":"abi.argument-layout","subsystem":"abi","category":"decision",
 "function":"0x1a2c","functionName":"name#5c1e09aa","address":"0x1a48",
 "fields":{"strategy":"positional","callee":"name#e1b2c0d4","count":2}}
{"schema":"swiftdc-probe/1","summary":{"counts":{"abi.argument-layout":147,…},
 "times":{"perf.analysis":{"seconds":0.162,"runs":96},…},"violations":[]}}
```

**Privacy.** A name read from the binary (a symbol, a type, a selector)
becomes `name#<fnv1a>` unless `--probe-names` is given. The hash is stable,
so events still correlate. Addresses and swiftdc's own labels are always
written. No file path is written.

**Determinism.** Analysis runs one function at a time, so events arrive in a
fixed order and `seq` numbers them. Summary counts are sorted by event id.
Times are wall clock and sit in their own object, so they never mix with the
deterministic stream.

**Filters.** `--probe-filter` narrows the trace and leaves the counts alone,
so a narrow trace still carries whole-run metrics. Its keys are
`subsystem=`, `category=`, `event=`, `function=` (a substring of the name)
and `address=<lo>-<hi>`. Separate values with `|`.

## Categories

| Category | Meaning | Counts against |
|---|---|---|
| `decision` | One reading was chosen over others; the payload says which and why. | — |
| `decline` | Nothing was claimed; the payload gives the reason. | completeness only |
| `limit` | A bound was hit (a visit cap, a recursion depth). What follows is a conservative fallback, not a proof. | completeness, and a soundness risk if the fallback is not conservative |
| `claim` | A semantic statement the output makes, in a form an independent oracle can check. | soundness, when the oracle disagrees |
| `metric` | A count or a cost. | — |

A valid decline is never a semantic error. A claim the oracle refutes is one.

## Adding an instrument

You write a definition and a call. Nothing gets passed through intermediate
signatures.

```swift
// ProbeEvents.swift
static let fieldUnnamed = ProbeEvent(
    "types.field-unnamed", .types, .decline,
    "An access at offset into type was left unnamed; reason is past-instance-size, …")

// at the decision, anywhere in the core (a static helper, the tracer, the structurer)
case .failure(let failure):
    Probe.record(.fieldUnnamed, ["type": .name(fieldMap.typeName), "offset": .int(offset),
                                 "reason": .label(Self.fieldFailureLabel(failure))])
    return nil
```

Three more forms cover the other kinds of instrument:

```swift
Probe.count(.someHotMetric)                       // a count, no trace line
Probe.timed(.analysisTime) { analyze(function) }  // a cost, kept out of the event stream
Probe.inFunction(start, name) { … }               // attribute events to a function (already done
                                                  // for analysis and rendering)
```

### How it stays cheap

- **No plumbing.** The recorder and the current function are task-locals.
  The structurer runs on its own large-stack `Thread`, so
  `ControlFlowStructure.onLargeStack` carries them across with
  `Probe.context`/`withContext`; task-locals do not cross a raw thread.
- **Near-zero cost when off.** A call loads one relaxed atomic (the number of
  installed recorders anywhere in the process) and branches. The payload is
  an `@autoclosure` and is never built.
  `aProbeWithoutARecorderBuildsNothing` holds that.
- **Never changes output.** Instruments observe; they never decide. Nothing
  reads a recorder's contents. `probeRecordingDoesNotChangeOutputIfPresent`
  compares every render with and without a recorder. It was seen red with a
  probe site that returned early while recording.
- **No double counting.** A pass that repeats another's work is wrapped in
  `Probe.muted`. That covers the structurer's discovery sweep and the
  streaming path's first decode.

Swift macros were considered for call sites and rejected. They need a
swift-syntax dependency, and an `@autoclosure` already gives the
zero-cost-when-off property. Result builders and property wrappers simplified
no call site.

### Validation hooks

`ProbeRecorder(validators:)` runs each closure on every event, including
events the filter keeps out of the trace. A non-nil return is a violation,
collected in `violations` and in the summary. Two uses:

- **Tests.** `theTracerModelsEveryWriteOnTheFixturesIfPresent` requires that
  no fixture trips the tracer's write check or its iteration bounds.
- **An external oracle.** The audit harness reads `types.field-named` claims
  (type, offset, field) and checks them against DWARF member offsets in the
  dSYM.

## Measured cost

These measurements predate the structured value snapshots added below. They
are a historical baseline, not measurements of the expanded full trace.
Summary-only recording now skips payload construction unless a validator needs
it; recording disabled still skips every payload.

Release builds, alternating runs on a host shared with other work, wall
clock:

| Workload | No probes compiled | Probes off | `--probe-summary` | Full trace |
|---|---|---|---|---|
| WeatherRadio (-O, 298K instructions) `disasm --structured`, median of 3 | 11.33 s | 11.39 s (+0.5%) | 11.58 s (+2.2%) | 11.88 s (+4.9%), 5.5 MB trace |
| Enchanted (-O, 3.66M instructions) `xrefs --unreferenced`, 2 runs | 121.2 / 122.6 s | 120.8 / 122.3 s | 122.6 / 122.5 s | 126.7 / 127.8 s (+4%), 109 MB trace |

Peak footprint was unchanged in every configuration (326–365 MB on
Enchanted, 350–357 MB on WeatherRadio). `xrefs` output was byte-identical
in all four configurations.

To reproduce, run the same command with and without `--probe <file>`
(`/usr/bin/time -l` for footprint).

## What the probes found first

- **`values.fixpoint-cap` fired once on an app** (20 blocks, 1,296
  iterations). The tracer represents "unknown" both as `.unknown` and as an
  absent key, and comparing states literally saw a loop flip between the
  two forever. Past the bound, the snapshot pass replayed a state that had
  not converged. Fixed separately; see `theTracerConvergesWhereUnknownAndAbsentAlternateIfPresent`.
- **`values.unmodelled-write` is silent** on every fixture and on three
  release apps (20,000–26,000 call sites each). It does fire when the
  tracer's clobber of an instruction's destination is removed: 6 and 3 hits
  on two fixtures.

## Event catalogue (schema `swiftdc-probe/1`)

| Event | Category | Fields | Exposes |
|---|---|---|---|
| `values.fixpoint-cap` | limit | blocks, cap | The tracer's states are not a fixpoint; its rendered values rest on an unconverged, optimistic state. |
| `values.loop-body-cap` | limit | blocks, cap | Same, for the induction re-transfer. |
| `values.unmodelled-write` | claim | register, instruction, kept | An instruction writes a register (Capstone access flags) whose proven value the tracer kept: a stale value that renders as a confident argument. |
| `abi.argument-layout` | decision | strategy, callee, count | Which layout set a call's arguments. `positional` is where stale-register fabrications have come from. |
| `abi.summary-cap` | limit | pass | A callee summary gave up (it claims nothing, or that every written register is clobbered). |
| `types.field-named` | claim | type, offset, bytes, field, fieldType, coverage | A field name at an offset, checkable against DWARF. |
| `types.field-unnamed` | decline | type, offset, bytes, reason | Why an access stayed `+0x…`. |
| `cfg.jump-table` | decision | cases | A `br` proven a jump table. |
| `cfg.unresolved-indirect-branch` | decline | text | A `br` with no successors in the CFG. |
| `cfg.unresolved-indirect-call` | decline | text | A `blr` absent from the call graph. |
| `decode.skipped-slot` | decline | — | Capstone could not decode 4 bytes. |
| `decode.jump-without-detail` | decline | — | A jump assumed conditional for lack of detail (an invented fall-through). |
| `decode.unmatched` | claim | text | An objdump instruction with no Capstone match: no control-flow class. |
| `structure.depth-goto` | limit | depth | The structurer's recursion bound produced a goto. |
| `structure.detached-block` | decline | — | A labelled block outside structured flow; often a CFG gap upstream. |
| `structure.unknown-condition` | decline | — | `if (?)`. |
| `structure.unknown-switch-index` | decline | cases | `switch (?)`. |
| `perf.analysis`, `perf.render` | metric | (times) | Per-phase cost. |

Renaming an event id is a schema change: bump `ProbeRecorder.schema`.

## Extension points

### Scoring without parsing pseudocode

The native flag-scoring session distinguished correct, wrong, unevaluable and
missing returns, and explicitly wrapped results modulo 2^64. It also showed
why trial structuring must not inflate final-output counts. These concerns are
now represented directly:

| Event | Fields / purpose |
|---|---|
| `loader.image` | UUID, architecture; correlate the trace with the native oracle |
| `analysis.function` | symbol, instructions, blocks, calls; one completed analysis |
| `cfg.block` | successors, instructions; CFG evidence |
| `values.exit-registers` | x0, v0, x20, x21; raw facts at ordinary/async returns, not source ABI claims |
| `values.call` | arguments, floatingArguments, stackArguments, receiver, indirectResult |
| `values.condition` | value; signed and unsigned operators stay distinct |
| `render.return-outcome` | status, type; recovered, unknown, void, throw, or unsupported layout/value |
| `render.return-value` | value, register, type, rendered; a recovered return claim |
| `render.function` | view, symbol, returns, returnStatements, unknownReturns, gotos, lines; committed output only |
| `async.context-escape` | offset; possible aliases on either incoming path invalidate slots |
| `async.context-escape-cap` | blocks, cap; no slots proven after an incomplete analysis |
| `async.context-escape-unknown` | reason; missing instruction semantics |
| `async.slot-proven` | offset, value; a chain-wide portable slot claim |

`ProbeValue` supports exact unsigned bit patterns (`uint`, JSON hex strings),
arrays and objects. Nested `name` values follow the existing redaction policy.
`ProbeValue.abstractValue` exports `swiftdc-value/1`: an `expression` object
whose `kind` is `immediate`, `argument`, `binary`, `unary`, `select`, or a named
provenance leaf. A binary node has `operator`, `lhs` and `rhs`; an immediate has
exact `bits`. Unknown values, provenance requiring an external oracle, and
export truncation remain explicit. The export is bounded to depth 32 / 1,024
expanded nodes, with explicit truncation markers. It does not add missing machine widths or turn a register fact into a
proven source ABI. Floating-point immediates are raw bit patterns.

```json
{"schema":"swiftdc-value/1","expression":{"kind":"binary","operator":"unsigned-less",
 "lhs":{"kind":"argument","index":0},"rhs":{"kind":"immediate","bits":"0xffffffffffffffff"}}}
```

`Probe.observe(analysis, of: function)` is public for native fixture harnesses
using `ValueTracer` directly. It records a completed snapshot, not worklist
iterations. The main decompiler calls it after its final trace.
`Probe.rendered(output, of: function, view: "custom")` exposes final-render
counts to other renderers. The built-in renderers call it once each; a
structured render's flat fallback is muted. Both APIs are observational.

`Probe.record`, `inFunction`, `count`, `timed`, and `ProbeRecord.jsonLine` are
public extension surfaces. `ProbeFunction` has a public initializer.

An `assessmentValidators` closure returns `ProbeAssessment` with an oracle ID
and `verified`, `refuted` or `notEvaluated`; nil means inapplicable. Assessments
retain the original record (function, address, event, sequence). They run even
when the trace filter excludes that record, outside the recorder mutex with
their own incidental probes muted, and
are available through `recorder.assessments`. The JSON summary adds separate
assessment counts. An unsupported claim never counts as a verified one. The
legacy string-returning `validators` / `violations` API remains available.

The scoring system is Swift, in `SwiftDecompilerCore`. Common cases need expected
returns, not a custom validator or a manifest. Width defaults to 64 bits,
arguments default to empty, and an omitted exit requires exactly one observed
exit for the function. For a sampled one-argument function:

```swift
let cases = ReturnExpectation.samples(in: functionStart, inputs: [0, 1, .max]) {
    $0 &+ 1  // independent oracle, or a typed call to the native fixture
}
let report = try await ProbeScore.recording(cases) {
    let functions = try await Disassembler().disassemble(path: binary, functionFilter: "increment")
    for function in functions { _ = function.renderStructured() }
}
print(try report.json())
```

For a constant, use `[ReturnExpectation(7, in: functionStart)]`. Add `at:` for
multiple exits, `arguments:` for manual samples and `bits:` for narrow results.
`samples` accepts typed Swift `Int`, `UInt64` and other scalar integer inputs,
preserves their bit patterns, and defaults the result width to that type's width.
Use `ReturnExpectation(signed: -1, in: functionStart)` for a signed constant.
For more control, construct `ProbeScore`, install `score.recorder` around the
existing pipeline, and call `score.report()` afterward. Arbitrary semantic
checks use the existing typed `assessmentValidators` surface.

The recorder's `.records` output streams typed events outside its mutex, with
incidental probes muted. It avoids serialization and full-trace retention.
The scorer retains only selected functions' exits, bounds duplicate storage,
and indexes facts once for repeated samples. It distinguishes verified,
refuted, not-evaluated and missing cases. An explicitly declined source return
is not-evaluated; a filtered-out or absent return is missing. Agreement covers
evaluated cases; coverage uses every supplied case. Unsupported provenance,
floating-point expressions and bounded exports never count as verified.

The authored native width fixture runs in one command:

```bash
swift run swiftdc score Fixtures/Sample/libWidthFlagProbes.dylib --width-flags \
    --output /tmp/width-score.json
swift test --filter 'integerOracle|score|typedProbeSink|presentButDeclined'
```

All 1,174 functions use an explicit no-argument UInt64 ABI. Native CPU execution
supplies expected values; nm/objdump independently supply symbol and exit
addresses, and dwarfdump supplies the UUID. This option only supports that
fixture family. It audits raw x0 facts, independently of source return-layout
recovery.

General Swift return cases also work through optional JSON manifests:

```bash
swiftdc score fixture.dylib --oracle oracle.json --output score.json
swiftdc score trace.jsonl --trace --oracle oracle.json --output score.json
```

Manifests use `swiftdc-oracle/1`, with a `cases` array containing `function`
and `expected`; `address`, `arguments`, `bits` and `id` are optional. Integers
accept exact hex strings or 64-bit JSON integers (including signed bit patterns).
An optional `binaryUUID` binds cases to one image; keep `loader.image` in saved
traces. Saved traces are read incrementally and require exactly one closing
`swiftdc-probe/1` summary. `--raw-register` selects raw x0 rather than recovered
return claims. An ambiguous exit or duplicate analysis cannot verify a case.

The CLI exits 1 on refutation, 3 on incomplete evaluation, and 2 on invalid
scoring data or I/O. Invalid command-line syntax follows ArgumentParser's usage
errors. `--allow-incomplete` permits incomplete cases, never refutations. Empty
oracles and invalid result widths are rejected. Scores describe the explicit
integer sample corpus; neither mode establishes app-wide accuracy.

The additions preserve existing event identifiers and fields in
`swiftdc-probe/1`; structured values have their own versioned schema.

A hook belongs here only when it has a real user today. Anything speculative
stays out: an abstraction with one implementation is a cost with no
customer.

### Public API (a compatibility promise)

| Hook | User | Contract |
|---|---|---|
| `Disassembler.disassemble(path:…)` / `disassemble(machO:…)` | every command, tests | The whole image or a filter, analysed. Holds every function. |
| `Disassembler.disassembleStreaming(machO:transform:progress:)` | `xrefs`, cache-image `disasm`, coverage tooling | Each function analysed one at a time and handed to `transform`; only what `transform` returns stays resident. Same analysis as the array path (`aStreamedCallGraphMatchesTheWholeImageGraphIfPresent`). |
| `CallGraph(functions:)`, `CallGraph.sites(of:)` | `xrefs`, tests | `sites(of:)` is the minimum the graph reads. |
| `ProbeRecorder`, `ProbeFilter`, `ProbeRecord`, `ProbeValue` | `--probe`, tests, the audit harness | Schema `swiftdc-probe/1`. |

### Test-only seams (internal, `@testable`)

| Seam | Purpose |
|---|---|
| `ProbeRecorder(validators:)` | Oracle checks on every event, admitted or not. |
| `Probe.recording` around any call | Capture events from one analysis. |
| `renderStructured(maxStructuringDepth:)` | Exercise the structurer's depth bound on a small stack. |
| `AsyncFuncletIndex.build(hints:functionStarts:instructions:nameOf:)` | Feed synthetic funclet chains. |
| `ValueTracer.calleeClobbers`, `calleeConventions`, `asyncContextSlots` | Inject callee facts into one function's trace. |
| `withStableDependencies` | Fix the symbol index store. |

### Internal composition points (no public contract)

Each of these is already a value passed to the analysis, so a new strategy
is a new value, not a new protocol:

- `PerFunctionContext` holds every image-wide index (fields, self types,
  vtables, enum cases, class types, async chains, callee summaries,
  indirect-result uses).
- `CalleeRegisterSummary.of(_:)` is the callee-effect summary for
  signatureless callees.
- `JumpTables.recognize` recovers switches.
- `DisassembledFunction.knownCArity`, `cFormatVariadics` and
  `MessageSend.isVariadicSelector` are fixed-ABI tables.

### Not added, and why

- **A decoder protocol.** Capstone is the only decoder of record. objdump
  supplies only listing text, and since `xrefs` streams, only the standalone
  `disasm` listing uses it. A second decoder has no user.
- **A plugin interface.** There is no external consumer, and a dynamically
  loaded plugin could feed the analysis evidence that breaks its soundness
  rules with no test catching it.
- **An external symbol database (`.tbd`, symbol files).** It would be
  valuable for stripped binaries, but no input has needed it yet. When one
  does, it enters as a name source with the lowest precedence, and a
  conflict with the binary's own evidence is a decline, never an override.
- **Runtime oracles (dynamic instrumentation).** These belong in the audit
  harness as validators over `claim` events, not in the core.

### Evidence an extension supplies

Any future name or type source must follow the precedence the core already
uses: binary metadata, then symbols, then outside evidence. Disagreement
declines. `FieldMap` collisions, folded addresses and ObjC bindings that
disagree already decline that way, and an extension must not resolve those
by picking one.

### Repeating the native research matrix

Run from the repository root:

```bash
swift run swiftdc research --iterations 2 --seed 7
```

The Swift command snapshots `Fixtures/Sample/researchinteger.swift`, compiles
it at `-Onone`, `-O` and `-Osize` with distinct module names per batch, and
executes only its declared UInt64-to-UInt64 exports. Independent nm and system
demangler output identify each entry and its explicit scalar signature.
`dladdr` verifies that native execution belongs to the intended image.
Deterministic SplitMix64 samples supplement fixed integer edge cases.

Every build is analyzed with all three demangling presets through both array
and streaming entry points. The loop retains the source snapshot, assembly,
oracle manifests, individual scores, probe summaries and `swiftdc-research/1`
metadata in a fresh directory under `work/research`. Metadata binds evidence
to source and binary SHA256s, native UUIDs, the running decompiler's SHA256,
the Git revision/diff and compiler version. Compilation uses the snapshot,
so editing the original source during a run cannot change later builds.

A completed exploration and a verified case are separate facts. The marker
starts with `completed: false`; failures leave partial evidence, and no older
success marker can be reused. Refuted claims produce exit 1 after the matrix
finishes. Unknown and missing cases stay in the report as discoveries; exit 0
means the exploration completed, not that every case was verified. The loop
runs only when invoked; it does not schedule background work.

The review cycle is: inspect the next refuted or unexpectedly missing case,
check its independently retained machine code, reduce it to a failing fixture,
fix the semantic mechanism, mutation-check the regression and repeat the same
seed plus a fresh batch. Keep per-function coverage requirements in tests;
an aggregate count can conceal losing the case a regression exists to protect.

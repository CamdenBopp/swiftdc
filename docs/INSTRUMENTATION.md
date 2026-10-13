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

## Async context escape evidence

`async.context-escape` identifies a computed slot address (offset).
`async.context-escape-cap` reports blocks and the exhausted work bound.
`async.context-escape-unknown` reports missing detail, an unknown convention,
missing funclets, unresolved indirect flow or context-base writeback. A cap or
unknown instruction semantics declines all chain-slot proofs.

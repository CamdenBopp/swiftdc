# handoff.md

A running "what's left" for swiftdc, so the work can be picked up in a new
thread. This is **tier-5 (conversation-memory) authority** per
[CLAUDE.md](CLAUDE.md): dated, stale by default, and outranked by source, tests,
git history, and measurements. Verify each claim against HEAD before acting, and
delete items from this file as they ship.

_Last updated: 2026-10-11, unified merge of all feature branches into master._

## Just merged (2026-10-11)

All five feature branches unified into master in one pass:

- **Robustness (source-findings, preflight-arm64e):** fixup-chain walker,
  fat-slice validation, arm64e pointer decoding, protocol/class-reference
  arrays, ObjC method bounds, Swift metadata section validation
- **Dependencies (upgrade/machoswiftsection):** MachOSwiftSection 0.22.0,
  Capstone 6, dylib-name bounds check
- **x8 indirect returns (improve/indirect-returns):** `IndirectResultUse` CFG
  classifier, result-buffer tracking, literal-pool constants, payload-enum
  case naming from stored tags
- **Async funclets (improve/async-funclets):** `AsyncFuncletIndex`, resume
  funclet grouping, await/return rendering, context-slot naming, effect
  specifier stripping, runtime bookkeeping hiding

## Where things stand

The 2026-10-09 session, newest first. All soundness, each with a red/green
proof and an old-vs-new diff over four dyld-cache images (RegexParser,
Observation, Distributed, SwiftData) recorded in its commit message:

- `0c3bb54` a lazy witness-table accessor takes no arguments (was stale x0)
- `498f966` `swift_willThrow`'s operand is x21, not x0 (`swift_willThrow(0)`)
- `6582380` shift counts and masks over a float stay integers (`>> 2.57e-322`)
- `d2eeb96` negate a branch condition structurally (it negated one conjunct,
  and rewrote `==` inside demangled names, flipping 6 RegexParser branches)
- `36b611e` a throw exit renders `throw E.case` / `throw ?`, not `return x0`
- `4a341ee` swifterror's arming value is never the callee's error (`0 != 0`,
  and 164 SwiftData error tests attributed to the wrong register)
- `ac411ff` signature parsing reads the function's own parameters and result
  (typed-throws group, closure results, indirect x8 and async results)

Earlier on this branch: `8018482`…`ebede99` (oracle error path, do/catch x21,
`swift-version`, analyze/layout/xrefs content tests).

Suite: **239 tests**, green under `SWIFTDC_REQUIRE_FIXTURES=1 swift test` after
`Fixtures/Sample/build.sh` (which now also builds `libSwiftErrorProbe`).

The branch is unmerged and unpushed; merge or open a PR when ready.

## Dependencies: MachOSwiftSection 0.22.0, upstream MachOKit 0.54.101, Capstone 6

Branch `upgrade/machoswiftsection` (2026-10-10) moves the pins. What it bought
and cost, all measured (the before/after sweep ran under build load, so the
times are indicative; the profiles are not):

- **Completeness.** `objc` on the iOS 18.3 simulator's `UIKit.axbundle/UIKit`
  went from 6 to all 853 classes (MachOObjCSection 0.8.110 resolves the
  `-interposable` self-binds). Main-executable vtable slots are named
  (`sample.release`: `sub_100001688` is now `Animal.__allocating_init(name:)`;
  stripped `sample.stripped` went 11 `sub_` slots to 5 through the ObjC thunk
  symbols). `@objc(SDWidget)` is printed on renamed classes. Extensions of
  C-imported types are named (`extension __C.NSAppearanceName:
  @retroactive RawRepresentable` in GoodLinks, Keynote). Property wrappers are
  synthesised (`@Combine.Published var`, `@ArgumentParser.Flag var`), 452 in
  Developer's interface alone. Did not reproduce: an `init`/`init?` spelling
  change (no such diff in any output) and field offsets for the renamed
  `@objc` class (`layout` declines `sample.Widget` on both builds with
  `objCAncestorUnresolved(NSObject)`; `layout` output is byte-identical
  everywhere).
- **Decoder.** Capstone 6 built from the `capstone` package replaces Homebrew
  libcapstone 5; every `disasm`, `disasm --pseudo`, `xrefs` output is
  byte-identical on standalone binaries. `docs/capstone6-migration.md` lists
  every renamed identifier and the three shape normalisations.
- **Robustness.** Fuzz is at 0 crashes again, but 0.22.0 opened one new trap
  class first: its class dumper walks the ObjC ancestor chain, which reads
  `MachOFile.dependencies`, which `try!`-reads each dylib command's name.
  `container-fuzz.py libSample.dylib 150 7` mutant 63 and `sample.release 150
  7` mutant 104 killed `dump`/`interface` by SIGTRAP (0.19.0: 0 crashes, same
  mutants). The preflight now bounds dylib name offsets to their command.
- **Performance, the open cost.** With the fork pin gone, `MachOFile.cache`
  re-opens the dyld cache on each access again, but `sample` puts that at
  about 2.5% now (0.22 no longer touches `.cache` per symbol). Two larger
  upstream costs dominate on standalone ObjC-heavy apps: (a) `dump`/`interface`
  resolve every class's ObjC ancestor chain inside the system dyld cache, and
  MachOKit's `DyldCache.locateValue` re-reads `headerOptimizationRO64` and
  `mappingInfos` on every call (3,235 of 5,225 samples on Keynote `dump`:
  1.35 s to 20.2 s; GoodLinks 7.4 s to 54.5 s; the sampled self-dump is the
  symbol-index demangling sweep as before). (b) `objc` resolves referenced
  protocol infos recursively with per-slot `resolveString` fixup lookups
  (Keynote `objc` 60 s to 2,424 s). Both are upstream defects to report or
  patch in a fork (memoise `DyldCache` header parsing; memoise protocol
  infos); swiftdc's own `objc` path could pass `ObjCInfoOptions.headerDump`
  if that proves output-identical. Not done on this branch: no push.

## What's left, by risk tier

The authoritative OPEN/UNKNOWN tracker is
[docs/PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md). Found but not
yet done in the 2026-10-09 session:

### 1. Soundness (tier 1): the do/catch `(0 != 0)` fabrication

Confirmed live at HEAD, `-Onone`. A do/catch that returns a value renders a
fabricated always-false condition, i.e. a wrong render, the project's top
severity:

```
main.classify(Swift.Int) -> Swift.Int {
    return ((0 != 0) ? -1 : (main.mayThrow(Swift.Int) throws(arg0) + 1))
}
```

Repro: build a `do { r = try f() } catch { r = ... }; return r` dylib at
`-Onone`, then `swiftdc disasm --pseudo -f <fn>`. The value tracer stale-reads
x21 (the Swift error register) as a live value in the select condition. Fix per
[docs/research/value-unknown-causes.md](docs/research/value-unknown-causes.md)
("Remaining", item 3): gate the read Swift-vs-ObjC in the tracer's `transfer`.
Highest-value change on the board.

### 2. Validation

- **Extend the differential oracle to throwing / do-catch.**
  `DifferentialOracleTests` executes the compiled function over curated
  *non-trapping* inputs, so error paths are uncovered. Add inputs that take the
  catch path; the oracle then goes red on item 1 until it is fixed.
- **Whole-binary golden corpus.** No committed golden output for a real
  framework exists, so a silent whole-binary regression would pass unnoticed.

### 3. Everything else

- **Completeness:** generic and existential indirect results still decline
  (the x8 path handles concrete types). A throw whose error is built by a
  helper (`mov x21, x0` after `sub_…`) is not recognised as a throw exit.
- **Robustness:** 0 crashes across all fuzz sets. Next probes: an arm64e
  image, a fat file, a large real framework; pointer-based (entsize 24) method
  lists; ObjC categories' and protocols' own fields beyond category-list slots.
- **Readability:** the structurer's `cond <op>` fallback renders an opaque
  `if (cond ==)`.
- **Async gaps (deliberate declines):** `-Onone` context reloads through stack
  spills; error register at await-return renders raw `x20 == 0`; executor from
  actor's `unownedExecutor` renders `hop_to_executor(?)`.
- Older items (stripped-binary `sub_` naming, `objc` ivar types, whole-image
  `disasm` time, L1 locals) stand as recorded in the readiness doc.

## How to run

```bash
Fixtures/Sample/build.sh                 # build fixtures once (git-ignored)
swift build && swift build -c release     # debug CLI + release
SWIFTDC_REQUIRE_FIXTURES=1 swift test     # enforcing run (missing fixture fails)
python3 Benchmarks/benchmark.py           # swiftdc vs ipsw (needs `ipsw`)
```

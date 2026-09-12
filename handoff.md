# handoff.md

A running "what's left" for swiftdc, so the work can be picked up in a new
thread. This is **tier-5 (conversation-memory) authority** per
[CLAUDE.md](CLAUDE.md): dated, stale by default, and outranked by source, tests,
git history, and measurements. Verify each claim against HEAD before acting, and
delete items from this file as they ship.

_Last updated: 2026-09-12, at master `4be4ca1`._

## Where things stand

master carries, newest first:

- `4be4ca1` content-assert the `layout` and `xrefs` commands
- `ebede99` content-assert the `analyze` report
- `925a83e` decoder-parity oracle (objdump vs Capstone, every shared function)
- `4d78769` fixture-presence tripwire (an enforcing run can't be green-on-empty)
- `73d5c6c` re-pin MachOKit to a fork that memoizes `MachOFile.cache` (perf)
- `688252d` swiftdc-vs-ipsw benchmark (`Benchmarks/`)

Suite is green: **207 tests on master, 212 with the uncommitted WIP below.** The
enforcing form is `SWIFTDC_REQUIRE_FIXTURES=1 swift test` after
`Fixtures/Sample/build.sh` and a `swift build` (the `layout`/`xrefs` tests spawn
`.build/debug/swiftdc`, so they skip without it).

## Uncommitted WIP — not on master

A `swift-version` subcommand lives in the working tree only:

- `Sources/swiftdc/Entrypoint.swift` — `SwiftVersionCommand` wiring (modified)
- `README.md` — its docs (modified)
- `Sources/SwiftDecompilerCore/SwiftVersionDetector.swift` — untracked
- `Tests/SwiftDecompilerCoreTests/SwiftVersionTests.swift` — untracked (5 tests)

It compiles and those tests pass locally. Commit or set it aside before any git
operation that assumes a clean tree.

## Dependency fork pin — revert when upstream ships

`Package.swift` pins MachOKit to `CamdenBopp/MachOKit@07d7633` (a fork of the
0.52.102 tag) for one perf fix, submitted upstream as
[MxIris-Reverse-Engineering/MachOKit#1](https://github.com/MxIris-Reverse-Engineering/MachOKit/pull/1).
When #1 merges and ships in a release, revert to an upstream version pin and drop
the fork. The rationale is in the Package.swift comment block.

## What's left, by risk tier

The authoritative OPEN/UNKNOWN tracker is
[docs/PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md). Two items this
session surfaced are **not yet recorded there** — add them when you take them on.

### 1. Soundness (tier 1): the do/catch `(0 != 0)` fabrication — not in the readiness doc

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
x21 is a general register in ObjC, and a blanket invalidation broke ObjC last
time, so do it narrowly and re-check the ObjC path.

Highest-value change on the board. Ship it together with the oracle extension
below so it stays fixed.

### 2. Validation

- **Extend the differential oracle to throwing / do-catch.**
  `DifferentialOracleTests` executes the compiled function over curated
  *non-trapping* inputs, so error paths are uncovered, which is exactly why the
  fabrication above slipped past it. Add inputs that take the catch path; the
  oracle then goes red on item 1 until it is fixed, and stays a guard after.
- **Whole-binary golden corpus.** There is no committed golden output for a real
  framework, so a silent whole-binary regression would pass unnoticed (the
  readiness doc's validation table lists this as the one subsystem with no
  oracle). `Benchmarks/samples/` is a small start.

### 3. Everything else

From [docs/PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md), highest first:

- **Completeness:** ~49% of functions render `sub_<addr>` on stripped binaries /
  cache images (measured on CoreLocation). Largely inherent for cache images
  (local symbols are genuinely stripped), so low-ROI.
- **Robustness:** the upstream negative-offset trap is still present in
  MachOSwiftSection 0.19.0 (a valid but hostile offset aborts the process before
  a bounds check); see [docs/research/upstream-negative-offset.md](docs/research/upstream-negative-offset.md).
- **Completeness (small, tractable):** `objc` renders a Swift `@objc` class's
  ivars as `unknown` while `dump` already recovers their types from the field
  descriptor. Under-recovery, not a decline. `Sources/SwiftDecompilerCore/ObjCDumper.swift`.
- **Performance:** the `dump`/`interface` path is fixed (see the fork pin);
  whole-image `disasm` *time* on the largest frameworks is still open.
- **Reconstruction quality:** local-variable promotion (L1), and
  closures/existentials/generic-witnesses/`throws`/`async` still render as
  low-level runtime calls. Real, but last.

Also worth doing when you touch the readiness doc: fold in the two items above
(the perf fix as FIXED, the do/catch fabrication as an OPEN soundness item), so
it stops being stale on both.

## How to run

```bash
Fixtures/Sample/build.sh                 # build fixtures once (git-ignored)
swift build && swift build -c release     # debug CLI + release
SWIFTDC_REQUIRE_FIXTURES=1 swift test     # enforcing run (missing fixture fails)
python3 Benchmarks/benchmark.py           # swiftdc vs ipsw (needs `ipsw`)
```

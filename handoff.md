# handoff.md

A running "what's left" for swiftdc, so the work can be picked up in a new
thread. This is **tier-5 (conversation-memory) authority** per
[CLAUDE.md](CLAUDE.md): dated, stale by default, and outranked by source, tests,
git history, and measurements. Verify each claim against HEAD before acting, and
delete items from this file as they ship.

_Last updated: 2026-09-12, on branch `improve/source-findings` at `e39f64b`
(6 commits ahead of master `925a83e`; not yet merged)._

## Where things stand

The branch carries, newest first:

- `e39f64b` stop the do/catch tracer fabricating `(0 != 0)` from a stale x21
  (tier-1 soundness; was item 1 below)
- `6a8468a` mark the swift-version WIP as shipped in handoff.md
- `cfad110` evidence-backed `swift-version` subcommand (was the uncommitted WIP)
- `d49a1af` add handoff.md and reference it from CLAUDE.md
- `4be4ca1` content-assert the `layout` and `xrefs` commands
- `ebede99` content-assert the `analyze` report

master carries, newest first:

- `925a83e` decoder-parity oracle (objdump vs Capstone, every shared function)
- `4d78769` fixture-presence tripwire (an enforcing run can't be green-on-empty)
- `73d5c6c` re-pin MachOKit to a fork that memoizes `MachOFile.cache` (perf)
- `688252d` swiftdc-vs-ipsw benchmark (`Benchmarks/`)

Suite is green: **213 tests** on the branch. The enforcing form is
`SWIFTDC_REQUIRE_FIXTURES=1 swift test` after `Fixtures/Sample/build.sh` and a
`swift build` (the `layout`/`xrefs` tests spawn `.build/debug/swiftdc`, so they
skip without it).

The tree is clean. The branch is unmerged; merge or open a PR when ready.

## Dependency fork pin — revert when upstream ships

`Package.swift` pins MachOKit to `CamdenBopp/MachOKit@07d7633` (a fork of the
0.52.102 tag) for one perf fix, submitted upstream as
[MxIris-Reverse-Engineering/MachOKit#1](https://github.com/MxIris-Reverse-Engineering/MachOKit/pull/1).
When #1 merges and ships in a release, revert to an upstream version pin and drop
the fork. The rationale is in the Package.swift comment block.

## What's left, by risk tier

The authoritative OPEN/UNKNOWN tracker is
[docs/PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md).

### 1. Soundness (tier 1): the do/catch `(0 != 0)` fabrication — SHIPPED (`e39f64b`)

Fixed. A throwing call now invalidates x21 in the tracer's transfer (the Swift
error convention returns the error there), so the tracer no longer reads the
pre-call `mov x21,#0` as a live value in the post-call error check. Gated to a
throwing callee, so the ObjC path (x21 general) is untouched. Guarded by
`declinesDoCatchSelectRatherThanFabricatingIfPresent`. Details in
[docs/research/value-unknown-causes.md](docs/research/value-unknown-causes.md)
("Remaining", item 3, now marked FIXED).

Checked while verifying (a negative result, recorded so it is not re-chased): at
`-O`, `tryOrDefault` inlines `mightFail` and renders
`return (((arg0 + 1) > 0) ? arg0 : ~0)`. This is **sound** — `(x+1) > 0` ≡
`x >= 0`, true → `x` (mightFail returns `x`), false → `~0` = `-1`, exactly
`tryOrDefault`. It is only unsimplified (`(x+1) > 0` rather than `x >= 0`), a
readability nit at tier 9, not a soundness bug. No `(0 != 0)` fabrication on any
optimization level for this fixture.

### 2. Validation

- **Extend the differential oracle to throwing / do-catch.** Item 1 is now
  guarded by a fabrication-absence test, but the *stronger* guard the fix
  deserves is execution-based. `DifferentialOracleTests` executes the compiled
  function over curated *non-trapping* inputs, so error paths are uncovered —
  which is exactly why the fabrication slipped past it. Add inputs that take the
  catch path; the oracle then proves the recovered value matches the real one on
  both paths, not just that no constant was invented.
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

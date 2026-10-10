# handoff.md

A running "what's left" for swiftdc, so the work can be picked up in a new
thread. This is **tier-5 (conversation-memory) authority** per
[CLAUDE.md](CLAUDE.md): dated, stale by default, and outranked by source, tests,
git history, and measurements. Verify each claim against HEAD before acting, and
delete items from this file as they ship.

_Last updated: 2026-10-09, on branch `improve/source-findings` at `0c3bb54`
(unmerged; also carries `f6a4e0c`, the Swift-source research notes cherry-picked
from `research/swift-source-mining`)._

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

## Dependency fork pin — revert when upstream ships

`Package.swift` pins MachOKit to `CamdenBopp/MachOKit@07d7633` (a fork of the
0.52.102 tag) for one perf fix, submitted upstream as
[MxIris-Reverse-Engineering/MachOKit#1](https://github.com/MxIris-Reverse-Engineering/MachOKit/pull/1).
When #1 merges and ships in a release, revert to an upstream version pin and drop
the fork. The rationale is in the Package.swift comment block.

## What's left, by risk tier

The authoritative OPEN/UNKNOWN tracker is
[docs/PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md). Found but not
yet done in the 2026-10-09 session:

- **Soundness, to investigate:** `Foundation._convertNSErrorToError(0)` in
  SwiftData error paths. The `0` may be another stale argument (the NSError
  usually comes back through an out-pointer). Check against the machine code.
- **Completeness:** an indirect (x8) return now declines (`return ?`). The
  value stored through the incoming x8 is the result and could be rendered
  (`SyntaxOptions.init(rawValue:)` is `str x0, [x8]; ret`).
- **Completeness:** a throw whose error is built by a helper (`mov x21, x0`
  after `sub_…`) is not recognised as a throw exit; it declines.
- **Diagnostics:** `disasm`'s "image not found" error tells you to use
  `--list-images`, which only `dump` accepts.
- **Readability:** the structurer's `cond <op>` fallback (an `fcmp`/`ccmp` or
  out-of-block flag setter) renders an opaque `if (cond ==)`.
- **Research items not yet done** (docs/research/swift-source/README.md):
  classify symbol roles on `Node.Kind` instead of printed text; enumerate
  async funclets from `__swift_as_entry/_ret/_cont`.
- Older items (stripped-binary `sub_` naming, the upstream negative-offset
  trap, `objc` ivar types, whole-image `disasm` time, L1 locals) stand as
  recorded in the readiness doc.

## How to run

```bash
Fixtures/Sample/build.sh                 # build fixtures once (git-ignored)
swift build && swift build -c release     # debug CLI + release
SWIFTDC_REQUIRE_FIXTURES=1 swift test     # enforcing run (missing fixture fails)
python3 Benchmarks/benchmark.py           # swiftdc vs ipsw (needs `ipsw`)
```

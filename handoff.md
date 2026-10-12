# handoff.md

A running "what's left" for swiftdc, so the work can be picked up in a new
thread. This is **tier-5 (conversation-memory) authority** per
[CLAUDE.md](CLAUDE.md): dated, stale by default, and outranked by source, tests,
git history, and measurements. Verify each claim against HEAD before acting, and
delete items from this file as they ship.

_Last updated: 2026-10-12. The unified merge and the fixes below are on the
`dev` branch on GitHub, not on master. A sweep of every subcommand over 7 large
apps and 5 dyld-cache frameworks was still running when this was written (Prime
Video, Fiery Feeds and part of Swiftcord done); merge `dev` into master once it
finishes clean._

## On `dev` (2026-10-11/12), not yet on master

The five feature branches (source-findings, preflight-arm64e,
upgrade/machoswiftsection, indirect-returns, async-funclets) merged into one
line, then fixed against what the merge and the sweep exposed. Each commit
carries its measurement and a red/green `Verified:` line:

- `7b20cfc` async returns print only for a proven one-register result type (the
  merge had silently dropped every async return value)
- `8feed90` an optional return of a value type declines (nil printed as `0`, or
  as an enum's raw extra-inhabitant tag)
- `b3a8510` int/float conversions render as `Double(x)` / `Int(x)` (was
  `(arg0 * 0x3ff8000000000000)` for `Double(n) * 1.5`)
- `bc344aa` preflight zero-fill table: 0x12 (thread-local zero-fill), not 0x13
- `267e341` load-time ivar offsets (zero-fill `__common`) are recorded, not
  read: origin/master died by SIGTRAP in 4 of 8 subcommands on Prime Video
- `3608e37` MachOKit re-pinned to `CamdenBopp/MachOKit` 4c4738f (0.54.101 plus
  the `MachOFile.cache` memo): Prime Video `layout` 16x, `dump` 2.2x,
  `interface` 3.2x faster, byte-identical
- `1741748` C strings are read only from file-backed bytes (an `adrp` to a
  `__common` global made `strlen` run off the mapping: a SIGSEGV that came and
  went with memory layout)
- `07ec716` only the retain family is read through as its argument; a
  uniqueness check renders `isKnownUniquelyReferenced(x)` (was `return
  self.storage` for a `-> Bool` CoW method)
- `d6d0e90` vtable dispatch declines for class names that collide
  (`Beta.Node.work()` rendered `Alpha.Node.launchMissiles()`)
- `f403603` an async context slot whose address escapes (`inout` across an
  await) is no longer "proven" (rendered the pre-call value as the return)
- `5d6c7b7` `cmn` compares with the negated operand (`x == -1` rendered
  `x0 == 1`); `b.mi`/`b.pl` render the sign of the difference or sum

The last four came from agents that read Jacob's Tech Tavern (runtime,
concurrency, compiler posts) and probed each lowering fact against swiftdc.
Their probes live in the session scratchpad; the remaining findings are OPEN
entries in the readiness doc.

Suite: **334 tests**, green under `SWIFTDC_REQUIRE_FIXTURES=1 swift test` after
`Fixtures/Sample/build.sh` (new fixtures: libConversions, libRuntimeIvars,
libCow; `maybeNext` in asyncfns, `nextUnlessZero`/`rankUnlessZero` in indirect).

## What's left, by risk tier

The authoritative OPEN/UNKNOWN tracker is
[docs/PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md). Highest value
first:

### 1. Soundness: folded and aliased call targets (needs a decision)

ld deduplicates identical functions in a release link, so one address carries
many symbols, and a call into it is named after an arbitrary one. An -O probe
put 11 symbols on one bare `ret`; `optK`'s call renders as `Sync3.pair(arg0)`
under `--pseudo` and as `Sync3.P2.a.modify … .resume.0` under `disasm`. TinyCC
shows the same class with linker markers: `add3`'s call is annotated `→
_init_array_end`. Options: decline (`sub_…` plus a "folded: N functions" note),
list the aliases, or rank them (a function symbol over a marker; the one a
specialization names). Pick one, then make `disasm` and `--pseudo` agree.

### 2. Soundness: unknown-arity and variadic C calls

`long bump(void)` called after `printf` renders `bump(printf(…))` (clang -O0 and
TinyCC alike): x0 left by the previous call is taken as an argument. Proposed
fix: for an in-image callee, classify which of x0–x7 its body reads before
writing them, like `IndirectResultUse` does for x8; decline for an external
callee unless a signature table names it. Variadic calls (`printf`) pass their
variable arguments on the stack under Apple's ABI; today the stack arguments
vanish and a scratch x1 is read as one.

### 3. Performance

- `xrefs`/`disasm` name vtable slots by rendering a full Swift class dump
  (`MetadataSymbolizer.classMethodNames`), and 0.22's dumper walks each class's
  ObjC ancestors through the dyld cache: Fiery Feeds `xrefs` 153 s on
  origin/master, 966 s now. Read the method descriptors directly instead, and
  memoize `DyldCache._machO(at:)` / `_headerOptimizationRO64` /
  `_objcOptimization` in the MachOKit fork. Profile in the readiness doc.
- Prime Video (296 MB) whole-image `xrefs --unreferenced` and `disasm
  --structured` exceed 30 minutes (5.7 / 6.8 GB). Early `sample`: Capstone
  decode (`matchAliasPatterns`) plus malloc. Capstone 6 vs 5 decode speed is
  unmeasured; A/B it on a mid-size binary first.
- `objc` on Prime Video is 375 s: MachOObjCSection's recursive protocol-info
  expansion (recorded in the readiness doc with its profile).

### 4. Soundness found by the Tech Tavern probes, still open

All in the readiness doc with repros. Highest value: cap a Swift callee's
arguments at its demangled arity and lay float / `T?` arguments out from the
signature (one root cause behind stale-argument renders, SwiftUI raw CGFloat
bits, and `sink(arg0, arg1)` for a one-parameter function). Then: async
throws via x20 rendered as bare `return`; a throw merged into the epilogue
rendered as `return (… ? swift_willThrow(…) : …)`; `Tm` merged helpers naming
one type for every caller; `-f` unable to select a folded function.

A corpus note: `grep -cE '\(0 != 0\)|\(0 == 0\)'` is no longer a pure
fabrication count. Fiery Feeds still shows 115 (171 on origin/master), and the
ones checked are real constant branches in -Onone code (`mov w8, #1; cbnz
w8`, sub_10028dc1c). Check the asm before calling one a fabrication.

### 5. Mined from revng, NeverD and ReDyne (2026-10-12): the next plan

Three agents read those projects against the open problems above. Licenses:
revng's cited files carry MIT headers (repo GPLv2 via QEMU); NeverD is
AGPL-3.0-only and says that covers AI-assisted translation (ideas only, re-derive
everything); ReDyne is MIT but nothing in it beats what swiftdc has. Ranked:

1. **Register-usage summaries for call arity** (revng
   `lib/EarlyFunctionAnalysis/AnalyzeRegisterUsage.cpp`; NeverD
   `lib/ir/low/CallRegisterEffects.cpp`, same idea). Per function: which of
   x0–x7 / d0–d7 it reads before writing (arguments) and which it writes that
   reach the return (results), solved to a fixed point over the call graph.
   revng's key detail: a callee's result write is a *clobber* at the call site,
   which is exactly the `bump(printf(…))` bug. Unknown callees must stay
   unknown (decline), not default to zero arguments as revng does. Generalise
   `IndirectResults.swift`'s x8 walk; clamp at the arity site in
   `Disassembler.swift`. Effort M.
2. **Jump tables.** Confirmed gap: `CFG.swift` `successors(of:)` gives a `br xN`
   no successors, so switch arms are orphaned. Recognise the AArch64 compact
   table (`adrp/add` table, `adr` anchor, `ldrb/ldrh`, `add …, lsl #s`, `br`),
   bound it by the dominating `cmp; b.hi` guard, decline without one. Effort M.
3. **An SDK-generated C prototype table** (NeverD's idea: libclang over the SDK
   headers, variadic and unprototyped left empty) to replace the hand list
   `knownCArity` in `Pseudo.swift`; it also marks variadics for stack-argument
   recovery. Write our own generator. Effort M.
4. **Oracles.** A structural flow oracle (rebuild the edges the structured
   output implies, diff against the CFG; NeverD `HighFlowOracle.cpp`) as a
   test-only check, and an ABI execution oracle (call with random bytes,
   capture registers and stack, check the layout predicted every byte; revng
   `share/revng/test/tests/abi/`) before writing float / HFA / `T?` layout.
5. **Goto-first structuring then rewriting** (revng `RestructureCFG` +
   `CliftTransforms`): never fail to structure; `// continues at` becomes a goto
   that later passes remove. Effort L.
6. Small: argument-register contiguity (x3 an argument implies x0–x2); a
   per-command minimum `cmdsize` table in the preflight (it checks the generic
   8-byte minimum and some specific layouts); code-signature Team ID and
   entitlements in `analyze` (ReDyne has a parser; take the idea).

Do not adopt: majority-vote signedness (reintroduces U1), callee-saved
suppression (deletes swiftcc's x20/x21/x22), any "pick one arbitrarily" ABI
mode, ReDyne's pseudocode (`b.lo` -> `<`, the U1 defect) and its silent caps.

### 6. Everything else

- A float argument to a call is not tracked (`Swift.Double.init()` for
  `Double(f)` at -Onone).
- Async: `-Onone` context reloads through stack spills decline; executor from
  an actor's `unownedExecutor` renders `hop_to_executor(?)`.
- Validation: no committed whole-binary golden output for a real framework.
- TinyCC (`git clone https://repo.or.cz/tinycc.git`, `./configure && make` with
  `SDKROOT` set) builds Mach-O with its own linker: no `LC_FUNCTION_STARTS`, no
  `LC_UUID`. It is a cheap source of unusual inputs for the robustness corpus;
  the 2026-10-12 probe found items 1 and 2 above.
- Older items (stripped-binary `sub_` naming, `objc` ivar types, L1 locals)
  stand as recorded in the readiness doc.

## How to run

```bash
Fixtures/Sample/build.sh                 # build fixtures once (git-ignored)
swift build && swift build -c release     # debug CLI + release
SWIFTDC_REQUIRE_FIXTURES=1 swift test     # enforcing run (missing fixture fails)
python3 Benchmarks/benchmark.py           # swiftdc vs ipsw (needs `ipsw`)
```

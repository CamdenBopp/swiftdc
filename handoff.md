# handoff.md

A running "what's left" for swiftdc, so the work can be picked up in a new
thread. This is **tier-5 (conversation-memory) authority** per
[CLAUDE.md](CLAUDE.md): dated, stale by default, and outranked by source, tests,
git history, and measurements. Verify each claim against HEAD before acting, and
delete items from this file as they ship.

## Current session (2026-10-15)

Swift error exits are classified per exit (see the readiness entry
"2026-10-15: Swift error exits"): `f2587e2` (per-exit preservation,
refactor) and the soundness commit after it. Enforcing suite: 688 tests.
The IR plan is in [docs/IR.md](docs/IR.md). Next, in order: the escaped
stack facts across unknown calls (`cacheEscape`, fixture
`stackcalleffects.swift` and `async_call_effects.s`, still untracked),
then IR steps 1–3.

## Soundness development session (2026-10-13)

Baseline `9910115`; eight coherent corrections (latest known unknown argument footprint) are committed on
local `dev`. The freshly rebuilt enforcing suite passes **677 tests** in eleven
suites. Added regressions independently kill guards for process exit propagation,
escaped/caller-owned register saves, represented async aliases/effects, ambiguous
image scoring and async slot chronology. Final release A/B measurements and the
full native matrix are still pending. Async unknown-pointer writes now invalidate
mutable context seeds/headers; fourteen independent mutations fail and six of
184 source views change. The separately exposed known-signature omission now retains unknown x0
placeholders for onError(Int) and log(Int); its guard mutation fails five
assertions. Next is compiler-generated escaped stack cache facts across unknown
calls (native 11, optimized final source incorrectly return 7). Do not treat the earlier 614-test summary as current.

Confirmed remaining risks include transitive outlined/tail register effects and
writes through incoming x29. Independent native reductions confirm them;
prevalence in current compiler fixtures has not been established. A child
clobber union is insufficient when a wrapper transfers the clobbered value into
a different register. The general correction needs callee effects inside
Preservation, dependency reanalysis and equivalent filtered/array/stream decoding.

Broader tuple/memory/call-order final-render verification remains a design, not
implemented proof. Existing native scalar research and targeted native memory
observations do not establish complete rendered-body semantics. See the latest
entries in [PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md) and retained
session evidence under `work/session-*`.

## Earlier committed baseline on local `dev` (2026-10-13)

Three dedicated agents completed focused fixes for ABI preservation, complex
control flow and CFG jump-table bounds. Saved-register proofs now use exact
store-byte ranges; loop exits crossing a switch use labeled transfers; four
unsafe table-bound forms decline. Each safeguard was independently disabled
and its regression observed failing, then restored and rebuilt.

The enforcing suite passes **614 tests**. Across 88 fixture CFGs, only the new
invalid-bound reduction loses edges; all 22 recovered `/bin/zsh` tables remain
unchanged. After byte reversal, seven of 176 structured/pseudo fixture views
change, with every change explained in
[PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md).
Scalar byte reversal (`c9de323`) also has build/presence wiring; the
unknown-return test now uses an unmodelled CLZ fixture. ABI preservation
(`7b5d5ce`), CFG bounds (`334628b`) and loop transfers (`9e2f279`) are
committed on local `dev`. Full ABI layout, aliasing and irreducible flow remain
separate work.

_Historical handoff from 2026-10-12, second session (see "Shipped in the second session"
and sections 7 and 8, which hold the second mining wave and the ranked plan).
The unified merge and the fixes below are on the
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

### Shipped in the second session (2026-10-12)

Each with a measured or reproduced defect and a red/green `Verified:` line:

- `1837f3b` chained-fixup rebases walked once (`ChainedRebases`), not per slot:
  Keynote's selector table was quadratic per page
- `3d2c9cc` + `dbb51a3` MachOKit fork pinned to the fat64 fix, and the lockfile
  committed to match (3d2c9cc had left Package.resolved on the old revision)
- `48d20d6` magic-number division and remainder folded back to `x / D`, `x % D`
  (new fixture `libCodegen`, its own image so libReconstruction's fuzz offsets
  stay put)
- `c00e5a7` stripped class methods named from method descriptors and override
  tables: Fiery Feeds symbolizer 36.3 s to 1.03 s, no names lost
- `e3ed073` a body two classes share at -O is a fold, never one owner's name
- `22df212` `udiv` kept apart from `sdiv` (`/ᵁ` unless the dividend is a proven
  UInt); signed constants fold signed
- `3fbbff5` a call forgets the tracked NZCV flags

Then, continuing the same day (each with a reproduction and a red/green
`Verified:` line):

- `d28689b` magic division proven by matching LLVM's own constants
- `c18e6b4`, `ecf353e` Swift callee arguments laid out from the signature
  (stale registers dropped; float slots from v0–v7; `Double(f)` fixed)
- `6018c78`, `206ab79`, `6621442` folded vtable slots named for self's class;
  self seeded for layout-less classes; a self dispatch renders `self.m()` and
  its `xrefs` edge is marked possible
- `e068140`, `e26feb7` variadic sends: format-counted arguments, positions
  kept (nil was rendered as the first object), nil-terminated lists, `…` when
  unprovable
- `cb702aa` jump tables (compressed and arm64e hardened) into the CFG, `switch`
- Recovered from the pre-merge stash (see "The pre-merge stash" below):
  `ea5e58e` entry state only at the entry, `7e9a8c7` field lookup bounds,
  `c6f23b2` self-field snapshots, `8d92415` traps/`goto`/unresolved calls,
  `096868b` return register allowlist and HFA self order, `a2ef33c` hygiene,
  `ed4f157`/`0c92a85` typed Objective-C argument ABI (entry, sends to self and
  to typed ivars), `8014828` qualified enum/class/payload identity, `2ee0578`
  qualified field-map identity
- Async ownership (2026-10-12): `07918b2` a function-typed or closure result
  read from the signature's own arrow, `db8484a` async context pointers only in
  full-width integer registers, and the async index rewrite after them: the
  stash's context-slot handoff plus every arm64e shape that defeated it on the
  system libswift_Concurrency (0 → 586 resume lines of 610; the other 16 lines
  name a funclet folded across two functions, now "shared by N async
  functions"). See the readiness entry "async ownership was first-wins".

Reverted before commit: a callee arity cap by parameter *count*. It dropped a
real argument (`sink(_: String, _: Int)`: the String fills x0 and x1, the Int
is x2). The sound version is the register-footprint plan in section 8.

Suite: **442 tests** (334 before this session), green under `SWIFTDC_REQUIRE_FIXTURES=1 swift test` after
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

- Fiery Feeds whole-binary `xrefs --unreferenced` re-measured 2026-10-12 at
  `74b7b06`: 953 s, 11.05 GB peak footprint (5.47 GB max RSS), against 153 s on
  origin/master. The symbolizer fix (`c00e5a7`) took out only ~35 s; the
  chained-fixup bind table (`3840616`) took the whole run to 275 s, output
  byte-identical; the lean decode then took the peak footprint from 11.8 GB
  to 7.0 GB; the selector index, jump-table ranges and rebase table took it
  to 204.9 s. Next: profile again for the remaining 1.3× against
  origin/master's 153.5 s. Every big run
  goes under a footprint guard (`memprobe2.sh` pattern: `footprint -p` of
  the real child, 1 s poll, kill well under 8 GB; spikes outrun the poll). A memory watcher
  must read the footprint, not `ps -o rss`: an RSS watcher saw 4.0 GB and
  never tripped while the footprint passed 11 GB.
- Prime Video (296 MB) whole-image `xrefs --unreferenced` and `disasm
  --structured` exceed 30 minutes (5.7 / 6.8 GB). Early `sample`: Capstone
  decode (`matchAliasPatterns`) plus malloc. Capstone 6 vs 5 decode speed is
  unmeasured; A/B it on a mid-size binary first.
- `objc` on Prime Video is 375 s: MachOObjCSection's recursive protocol-info
  expansion (recorded in the readiness doc with its profile).

### 4. Soundness found by the Tech Tavern probes, still open

All in the readiness doc with repros. Highest value: bound a Swift callee's
arguments by its demangled signature's register footprint (not its parameter
count; see section 8) and lay float / `T?` arguments out from it (one root cause behind stale-argument renders, SwiftUI raw CGFloat
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

### 6. Mined from kuna, koute/ghidra-decompiler and glaurung (2026-10-12)

All three are Apache-2.0 (code portable with NOTICE attribution). Additions and
refinements to section 5's plan:

- **Variadic calls, soundly.** kuna (`docs/features/varargstackargs/`): on Apple
  arm64 empty x1–x7 at a variadic call is the ABI, not the end of the list; with
  a resolved format string, take the fixed parameters plus one 8-byte stack slot
  per conversion from `CallSite.stackArguments`, `?` for any missing. glaurung's
  `ir/printf_format.rs` is a fail-closed format parser (positional `$`, `*`, and
  ambiguous conversions decline). Re-derive Darwin's stack layout; both tools
  model other ABIs. Effort S–M.
- **Jump tables, better than a shape match.** kuna `p2_lift/jumptable.rs` and
  Ghidra `rangeutil.rs` / `jumptable.rs`: pull the index range back from the
  dominating guards (strided, wrapping intervals), then emulate the address
  computation per in-range value on the existing tracer. Keep the sound core;
  decline where Ghidra guesses (range halving above 0x10000, the 256-entry byte
  fallback, cutting at the first gap). Every unresolved `br xN` reports a typed
  coverage gap, never an empty successor list (glaurung `analysis/dispatch.rs`).
- **Structure accounting in production** (glaurung
  `ir/structure_accounting.rs`): before emitting, check the region tree against
  the CFG both ways (unexpressed edges, invented edges, duplicated blocks) and
  fall back to labelled gotos when it fails. Stronger than the test-only flow
  oracle. Its named failure shapes (multi-latch rotated loops, joins beyond the
  loop) are ready fixtures.
- **Loop body extension** (Ghidra `blockaction.rs` `LoopBody::extend`,
  `label_exit_edges`) for the measured gap of loop-body blocks emitted outside
  their loop; and kuna's capped SAILR passes (tail duplication with at most one
  call, cross-jump reverting, guard-clause flattening) plus lowered compare-tree
  to switch (`kuna_loweredswitch.rs`, for -O enum switches).
- **Arity refinements for the register-usage plan:** bits that reach no
  observable effect are not reads (glaurung `ir/definedness.rs`; `movk`/`bfi`
  preserved lanes, padding); a register holding the caller's own callee-saved
  input or an earlier call's killed result is provably not an argument (Ghidra
  `AncestorRealistic`, negative half only).
- **Magic-number division** (Ghidra `ruleaction/division.rs`): shipped as
  `48d20d6`, then proven for every input (structural match against LLVM's own
  lowering).
- **Oracles:** koute's pure-Rust Ghidra port (no C++/Java, raw-bytes entry
  `Program::from_raw_bytes(…, "AARCH64:LE:64:AppleSilicon:default", …)`) can serve
  as an instruction-semantics oracle (run its p-code emulator and swiftdc's
  transfer functions on random inputs; it would have caught `cmn` and U1) and as
  a jump-table oracle. Not as a Swift output oracle: its Apple cspec treats
  x20/x21/x22 as callee-saved. Qualify every oracle with glaurung's mutation
  method (`tools/metric_mutation.py`): measured sensitivity and specificity,
  not assumed.
- Also: kuna's closed-function gate for caller type votes (exclude vtable,
  witness, method-list entries); its byte-identical-to-serial `--jobs` contract
  if parallel decode is ever added (profile first); PAC instructions as identity
  on the pointer (check whether arm64e loses values in the tracer first).

Do not adopt: positional "gap ends the list" arity, arity from earlier calls to
the same callee, type votes as arity evidence, any cspec as a swiftcc model,
glaurung's keyword-matching LLM naming, WARP hashing for identity.

### 7. Mined in the second wave (2026-10-12)

Seven agents read eleven more projects; every swiftdc claim below was checked
against HEAD by reading code unless it says "reproduced".

- **unwasm** (MIT/Apache-2.0) and **asmlift** (MIT core, `apps/web` GPL-2.0).
  (1) Prove the magic-division fold: regenerate the compiler's own magic
  constants for the recovered divisor (LLVM's `SignedDivisionByConstantInfo` /
  `UnsignedDivisionByConstantInfo`) and require a match (asmlift
  `raise/magicdiv.ts`). (2) Compile the rendered expression with swiftc and
  compare value and trap in a child process (unwasm `tests/differential.rs`),
  because the oracle's evaluator is our own. (3) A per-instruction hardware
  oracle: one-instruction fixtures called on edge inputs against the tracer's
  transfer function (unwasm `tests/opcodes.rs`). (4) A decline census: a reason
  id on every `?` and structurer fallback, counted over a corpus (asmlift
  `docs/measurement-discipline.md`). (5) Ambiguity names nothing (unwasm). (6)
  Promote stack slots only when the frame address never escapes. (7) Hazard
  checks before re-rendering: load past store, trapping op where it did not run
  (asmlift `structure/hazards.ts`). (8) Split `xrefs --unreferenced` into
  exported, address-taken, neither. (9) A width quarantine assertion: no 32/64
  mix without an extend (asmlift `ir/verify.ts`). (10) Stripped C/ObjC names
  from `__assert_rtn`'s `__func__` argument. asmlift's IR (second pass): the
  "call printed twice" defect is effect ordering, not typing; extend the
  `let rN =` temp to every `.callResult` with more than one render position
  (asmlift `structure/analysis.ts`). Block parameters at loop headers only, plus
  a test-time SSA verifier. Do not adopt its typed L2 boundary (it refuses
  whole functions).
- **w1tn3ss** (no license: ideas only; the dependency would be QBDI,
  Apache-2.0). In-process QBDI is the only mode usable here (spawn and attach
  are defeated by the hardened runtime). Uses: a call-site capture oracle (a
  PREINST callback on `BL`/`BLR` comparing x0–x7, d0–d7, x8, x20–x22 and stack
  bytes with the `CallSite` prediction), and a dynamic edge oracle for jump
  tables and `blr` targets (every observed edge must be in the static CFG).
  QBDI embeds LLVM: look for a prebuilt before building on this host. Its own
  ABI model is wrong for Darwin (stack slots at `sp + 8*(i-8)`).
- **sleuthre** (MIT) and **Aether** (MIT). Shipped from it: `3fbbff5`. Also:
  `__TEXT,__unwind_info` as a one-way boundary check (every entry start must be
  a known function start; never enumerate from it, ld64 folds entries); a
  `swiftc -parse` syntax gate on rendered output. Aether: nothing to port.
- **angr** (BSD-2), calling convention. The `CallSignature` design in section 8
  comes from here: provenance tiers (`function.py` `PrototypeSource`),
  read-before-write facts (`fact_collector.py`), and the known-void rule (a call
  to a `-> ()` callee should leave x0 and v0 unknown, not `.callResult`).
  Possible hole, unverified: `IndirectResults.swift` treats a `bl` reached
  while x8 still holds the entry value as not reading x8.
- **GhidraApple** (GPL-3.0, ideas only), **FOX** (MIT), **Binary Ninja's ObjC
  docs**. A message send is three facts: selector, proven receiver type, and
  candidate implementations; candidates never rename the call. Predicted by
  reading, all to reproduce first: `setAlpha:0.5` renders a stale x2 (floats go
  to d-registers); CGRect arguments are wrong; a variadic send can print stale
  x3–x7 before its stack values; a user method named `…WithFormat:` gets extra
  variadic arguments (variadic is decided by selector name, `Pseudo.swift`
  around 257). Fix: an encoding-driven ABI classifier (integer/pointer to x,
  `f`/`d` to v, HFA to consecutive v, small composites to 1–2 x, larger by
  pointer; Darwin packs stack arguments; variadics always on the stack;
  decline on bitfields, unions and `?`). `xrefs` gains a possible-edge layer
  ranked by evidence (exact lookup, cone of overrides, declared type,
  selector only), never capped silently. Blocks: global block literals give
  proven edges to their invoke functions; stack blocks need dominating header
  stores.
- **ghidra-nativeaot** (MIT), **ghidra-decomp** (MIT), Frida, Ghidra's Swift
  support. A fold-aware type graph keyed by descriptor offset, with a reverse
  map from implementation address to every descriptor pointing at it, built
  once per image (`machO.swift.types` re-parses on every access and about nine
  builders walk it). It also resolves inherited vtable slots (an ancestor's
  slot range plus the most-derived override). A runtime metadata oracle with
  only `dlopen`/`dlsym`: call each type's metadata accessor and read field
  offsets, live vtables, `destructiveInjectEnumTag` per case, and
  `swift_conformsToProtocol` witness tables. Bounded-memory `xrefs`/JSON: make
  the streaming render a visitor, reduce each function to its call edges, and
  write NDJSON with a final summary record via a temp file and rename. Do not
  adopt: Frida (it knows no more than swiftdc on stripped code), headless
  Ghidra (its Swift cspec drops x21/x22), persistent analysis caches before
  measuring. Ghidra issue #8607 (read 2026-10-12) closed for 12.1 with markup
  of Swift's trailing objects only; building types from them is "not on my
  short-term radar". GhidraApple's team plans that on top of Ghidra's parser,
  which would make it, not stock Ghidra, the independent Swift second opinion
  to watch.

### 8. Next plan, ranked across all mining

Soundness first, then completeness. Repro before any fix marked "unverified".

1. **Callee arguments from a `CallSignature`** (first slice shipped,
   `c18e6b4`/`ecf353e`; next: the ObjC encoding classifier, known-void, `T?`). Per slot: location (x0–x7,
   v0–v7, x8, x20, x21, stack), role (formal, self, metadata, witness table,
   context, error, indirect result), provenance (Swift mangled signature, ObjC
   encoding, SDK prototype, callee read-before-write summary), and
   completeness; two proven sources that disagree decline. First slice: Swift
   callees with a mangled symbol, no generics, async or coroutines, every
   parameter a proven single-register scalar (`scalarParameterClass`); apply
   once where `argumentsByAddress` is built in `Disassembler.swift`. Fixture
   `callarity.swift` at -Onone and -O: `one(Int)` called with x1 live must
   render `one(arg0)`; `mixed(Int, Double, Int)` must render
   `mixed(arg0, ?, arg1)`; a generic callee stays unchanged. Then the
   known-void rule, then float arguments (snapshot v0–v7), then the ObjC
   encoding classifier. M.
2. **Fold-aware identity**: `SelfTypeIndex` and vtable naming shipped
   (`6018c78`); the type graph remains. M.
3. ~~Prove magic division~~: shipped (structural match against LLVM's
   lowering with its own constants; exact linear check for the remainder).
4. ~~Demote the self-vtable edge~~ (`6621442`); the possible-edge layer in
   `xrefs` (edges to overrides, selector candidates) remains. M.
5. ~~Jump tables~~: compressed and hardened forms shipped (`JumpTables.swift`).
   Still owed: the switch index expression, a typed gap for an unrecovered
   `br`, and dyld-cache images. The stash (`git show d921fc1:Sources/SwiftDecompilerCore/JumpTableIndex.swift`)
   targeted only the hardened form, Capstone 5; it is superseded.
6. **Oracles**: per-instruction hardware oracle (M); runtime metadata oracle
   via `dlsym` (S–M); `__unwind_info` boundary check (S–M); compile the render
   with swiftc (M); decline census (M).
7. **Bounded-memory `xrefs` and JSON** (M).
8. Smaller: `mulh` renders as a pseudo-operator (render
   `multipliedFullWidth(by:).high`); 32-bit `smull`/`umull`; variadic
   arguments from the stack only; `__assert_rtn` names; `xrefs --unreferenced`
   split.

### The pre-merge stash (stash@{0} = 983aa25, untracked half d921fc1)

Taken on `improve/source-findings` before the unified merge; the merge
carried that branch's commits but not this dirty tree. An audit
(2026-10-12) found real, tested, unmerged work in it; it is Capstone 5, so
every recovery is a port. Recovered so far: see the shipped list above.
Still in the stash, by the audit's priority:

- ObjC ABI leftovers: packed sub-8-byte stack arguments and the structurer's
  metadata register naming (both need the width work below).
- `buildIncludingLoaderPathDependencies` (foreign field names through the
  `@loader_path` dylib): rests on `ImageUniverse.dependencyClosure`, which
  FieldMap.swift records as trapping on resilient fields. Measure the trap on
  MachOSwiftSection 0.22 before porting.
- W-register width, full NZCV, CCMP/FCMP/FCSEL, subword stack extents (four
  new modules, 84k native vectors). L.
- LSDA cleanup-pad tests. S.
- Do not recover as written: the ObjC ivar-offset provenance (`try!` file
  read, per-slot `resolveRebase`); the `work/` binaries and Ghidra projects.

### 8b. -Osize fragments (from the 2026-10-12 compiler-differential probe)

Inline `OUTLINED_FUNCTION_n` bodies into their callers (tracer: run the
fragment's instructions in the caller's state; a fragment ending in `b X` is
a call to X; one reached by `b` is the caller's return). Soundness is already
handled by `CalleeRegisterSummary`; this is readability. On a stripped build
the fragments are `sub_` functions, so detect them by shape (no prologue,
writes or reads outside the convention), not by name. Also worth a second
compiler/linker for differential fixtures (ld64.lld, an older Swift): not
installed on this host.

### 9. Everything else

- Findings in `docs/research/decompiler-comparison.md` that never reached this
  file or the readiness doc (found by the 2026-10-12 audit): the named-rule
  pool; a bit-level known-zero / consumed-bits lattice; a "not settling" cap on
  type propagation; a cross-optimization semantic-invariance harness;
  signedness property tests; standing over-firing scans; mapping witness
  offsets to protocol requirement names; a headless-Ghidra comparison of
  concrete output (rejected in section 7); Malimite's library skip by
  namespace. And from `findings-scratch.md`: seeding a function's own `Int?`
  parameter (the `orZero` case).

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
swift Benchmarks/benchmark.swift          # swiftdc vs ipsw (needs `ipsw`)
```

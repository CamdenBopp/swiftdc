# swiftdc status

The short, current record for anyone assessing swiftdc from outside,
including automated reviewers. It holds only what was measured, each with
its commit, its denominator and the command that reproduces it. The long
history is [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md); this page
is what to quote.

Updated 2026-11-19. Each measurement names its commit; the benchmark
tables retain their original measurements.

## What to report, and what not to

- swiftdc publishes no readiness percentage, no ABI coverage percentage
  and no per-capability score. Any such figure is the reviewer's own
  judgment: nothing here supports one, and none should be carried from an
  earlier report as if it were measured.
- The measured outcomes are counts of **correct, partial, wrong and
  declined** on a pinned corpus (below). Quote those, with the commit.
- "Declined" is by design: a value swiftdc cannot prove renders `?`.
  A decline is a gap in usefulness; a wrong render is a defect. They are
  not the same thing and should not be added together.
- A fix's commit message states what was verified for that fix (a test
  seen failing without it, the fixtures whose output moved). It is not a
  claim about anything else.

## Decompilation outcomes, against Ghidra 12.2

173 builds of 70 small sources in twelve areas (Swift, Objective-C, C),
2,601 function builds, scored per function against the source and the
disassembly. Interface is the parameters and result shown; body is the
statements and values.

| | swiftdc 3837ea3 | swiftdc 5f012f8 | Ghidra 12.2 |
|---|---|---|---|
| Body correct | 671 (26%) | 862 (33%) | 1,414 (54%) |
| Body partial | 912 (35%) | 990 (38%) | 382 (15%) |
| Body wrong | 594 (23%) | 466 (18%) | 769 (30%) |
| Body declined | 424 (16%) | 283 (11%) | 36 (1%) |
| Interface correct | 1,734 (67%) | 1,748 (67%) | 2,031 (78%) |
| Interface wrong | 356 (14%) | 263 (10%) | 260 (10%) |
| Interface declined | 511 (20%) | 590 (23%) | 309 (12%) |

On the six Swift areas alone (1,077 builds) at 5f012f8: swiftdc's
interface is wrong on 1% and its body on 13%; Ghidra's on 12% and 35%.
Ghidra's body is correct on 40% there, swiftdc's on 24%. On plain C
Ghidra is clearly better.

- Recompute: `Tools/ghidra-compare/tally.py
  Tools/ghidra-compare/scores/2026-11-13b` (and `…/2026-11-13`).
- Rebuild the corpus and check it is the scored one:
  `Tools/ghidra-compare/corpus/build.sh <dir>` then `corpus/check.sh
  <dir>` (173 code hashes in `MANIFEST.tsv`).
- Method, examples and what each tool gets wrong:
  [research/ghidra-comparison-2026-11-13.md](research/ghidra-comparison-2026-11-13.md).

Limits of this measurement: the sources were written to probe ABI
shapes, so it is not a sample of real applications; the scoring is by
model agents under a written rubric (`scores/*/RUBRIC.md`), not by
execution, and the tables note their judgment calls; Ghidra's columns
were scored once and not re-scored.

## Entry conventions, against the compiler

The one measurement here with no human or model judgment in it. Each
corpus source is compiled to LLVM IR, whose `define` lines give every
function's lowered parameters (with `swiftself`, `sret`, `swiftasync`),
which fixes its arm64 entry registers. swiftdc's side is what its
analysis seeded at each entry.

| | swiftdc ab29dc3 | swiftdc 0f1f69b |
|---|---|---|
| Functions with parameters | 1,005 | 987 |
| Every parameter register seeded | 559 (55.6%) | 559 (56.6%) |
| Some seeded, none wrong | 126 (12.5%) | 126 (12.8%) |
| None seeded (declined) | 301 (30.0%) | 302 (30.6%) |
| A register seeded that the compiler passes no parameter in | 19 (1.9%) | 0 |

The 19 wrong entries were one defect, found by this check and fixed in
0f1f69b: the compiler's `default argument N of f(…)` generators take no
parameters (or only metadata), and swiftdc read `f`'s parameter list out
of their name. In that measured version, x8 was seeded as a possible result
buffer in every function, though the compiler passes one in 13 of 1,176;
30% of entries were not seeded at all. `9479048` now qualifies x8 by entry
ABI eligibility, but this corpus has not been remeasured. Actual hidden-result
parameter ownership remains open; the table above is still the pinned run.

Reproduce: `Tools/ghidra-compare/interface_oracle.py <swiftdc>
<built-corpus>`. It covers symbols the compiler emits IR for; it does not
cover results, bodies, or Objective-C methods (4 matched).

## Hosted CI configuration and hosted verification

At `7fb855dec2047b1e2c4d1dfa2375f22f7e1349dd`, hosted CI requests the documented `xcode-27`
ARM64 preview image and explicitly selects the tested Xcode 27.1. The
previous `macos-15` route failed Toolchain with Swift 6.2.4 / Xcode 26.3
in [run 44400919902](https://github.com/CamdenBopp/swiftdc/actions/runs/44400919902),
so fixtures, build and tests were skipped. The optional self-hosted route,
Swift 6.4 minimum and all fixture/build/test enforcement remain unchanged.

Local verification: actionlint 1.7.12 passes; executing the actual old/new
selector commands under isolated mock commands selects 27.2 / 27.1
respectively. Parsed workflow comparison preserves every other step.
After `Tools/ci/environment.sh`, `Tools/fixtures.sh` and
`swift build --build-tests`, `SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build`
passes **1,993 tests / 43 suites (954.812 s)**. All **344 tracked test files**
and all executable, fixture and package sources are unchanged. The **1,152
public input hashes** remained fixed throughout that local qualification.

The original integration gate independently rebuilt and pushed `d69fff8`,
passing **1,993 tests / 43 suites (939.996 s)**. All **723 inputs x four views**
and four SDK workloads are unchanged. All **2,896 paired cost rows** pass the
default caps without override: **7,717,056,592,175 instructions** and
**27,034,322,280 bytes summed per-run physical peaks** on each side (0% change).
The rebuilt release is byte-identical to the published baseline, SHA256
`a37b9db488cf42e29251286de2eb001ac3652f883b5798b60f5bfbb6324fd717`.
The **1,152 public input / 862 fixture product hashes** match both clean
trees, and an independent remote-head check confirms the push.

**VERIFIED hosted execution at published `d69fff8`:** completed
[run 44411756483](https://github.com/CamdenBopp/swiftdc/actions/runs/44411756483)
and its decoded job logs confirm **1,993 tests / 43 suites passing
(2,253.679 s)** with fixture presence enforced. The `xcode-27` runner selected
**Xcode 27.1 / Swift 6.4** on **arm64 macOS 27.0.1**, with **Go 1.27.4,
7 GB memory and 36 GB free disk**. Toolchain, Fixtures, Build and Enforcing
suite all completed successfully. This covers that published revision.
The later published `a841357` also completed
[run 44423167838](https://github.com/CamdenBopp/swiftdc/actions/runs/44423167838):
**2,000 tests / 43 suites passed (2,384.404 s)** with fixture presence enforced.
Its terminal job state and decoded logs were checked. That hosted result
covers code `3385323`. Published `5c5ab71` also completed
[run 44448308320](https://github.com/CamdenBopp/swiftdc/actions/runs/44448308320):
**2,005 tests / 43 suites (1,938.195 s)**. Terminal state and decoded logs
confirm Toolchain, Fixtures, Build and Enforcing suite passed. This covers
code `8a15928`; the local receiver change requires its own gate/publication
and hosted result. See [CI setup and image sources](CI.md).
No decompilation benchmark or readiness percentage changes.

## Latest local verification: async link-register facts

**FIXED for call-clobbered async ownership facts (soundness, `5291877`).**

At `5291877b835e54d9d0ba65a25b5ee81caae466fa`,
`AsyncFuncletIndex` discards held addresses, address pages
and context aliases in x30 after a call. It previously cleared x0...x17
but retained x30: a later copy into another register could fabricate a
resume handoff from the old LR value, although BL/BLR had replaced it.
Callee-saved x19 facts retain their existing behavior.

A standalone inline-header regression covers address/page/context facts,
direct/indirect calls and hint-backed/code-only indexing: **12 false
handoffs become declines**, while **12 x19 controls retain their chains**.
The initial rebuilt tests fail with **24 issues**. Three independently
compiled mutations, each retaining one x30 fact domain, fail with **eight
issues each**; their x19 controls pass. Exact restoration rebuilds both
regressions green. The source-controlled regression decodes explicit machine
words with Capstone and checks recovered chains and suspension records;
it is a reduced ownership proof, not an application-wide accuracy or
carried-value result.

All **348 preexisting test files/assertions remain byte-identical**. One
new file adds two test declarations. The rebuilt fixture-enforced suite
passes **2,009 tests / 43 suites (926.957 s)**. The frozen snapshot has
**1,173 public input files / 901 fixture products**.

Matched frozen releases produce **identical outputs for all 762 inputs
in four views**, including 35 unchanged expected preflight-decline pairs.
All **3,052 paired cost rows** pass every default limit without override:
**8,564,422,553,288 -> 8,572,825,019,096 instructions (+0.098109%)**;
**28,674,159,896 -> 28,770,205,872 bytes summed per-run physical peaks
(+0.334957%)**. No performance improvement is claimed. Baseline release
SHA256: `f7959128c7cd520851b181a0bc0042bd23923d905d5236a25773093f436cba75`;
candidate: `e14bb8102648e4e3d30b4de1327dd4d9f5dc54f931d33c217c0d17a021a800b3`.

All **338 CLI invocations over 13 inputs and 13 paths** pass with
identical output: **65 metadata/xrefs pairs**, **169 stderr pairs**,
**104 whole views** matching the measurements, and **52 filtered/whole
comparisons**. Analyze and Lab remain identical. All four measured SDK
workload outputs are unchanged; four guarded structured rerenders match
the measured hashes.

Ten original Clarc/GoodLinks/Terminal/TextEdit/Chess renders pass the
**2,000 MB footprint guard**, preserving identical outputs and all
**84,833 function headers in order**. The largest sampled footprint is
**308 MB**. These are reliability/output comparisons, not source-grounded
application accuracy measurements. Private reports remain under ignored
`work/`.

Reproduce the regressions with `swift build --build-tests`, then
`swift test --skip-build --filter 'asyncCalls(ForgetPriorLinkRegister|KeepCalleeSaved)'`.
The full command is `SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build`
after rebuilding. Compare frozen releases with
`Tools/blast-radius.sh <baseline> <candidate> <outdir> --real --perf`.
See the [engineering record](https://github.com/CamdenBopp/swiftdc/commit/5291877b835e54d9d0ba65a25b5ee81caae466fa).

**Publication pending:** this is local verification. The original integration
gate and a hosted run covering this change remain to be checked. Separately,
published receiver code `dbbdc83` at `83443a5` completed hosted
[run 44456365627](https://github.com/CamdenBopp/swiftdc/actions/runs/44456365627):
**2,007 tests / 43 suites (2,555.394 s)**, confirmed from terminal job state
and decoded fixture-enforced logs. That hosted result does not cover this fix.

**OPEN:** recovering values carried across awaits and context handoffs through
outlined helpers. This commit fixes a false ownership proof; it does not add
value propagation. No decompilation benchmark or readiness percentage changes.

## Previous local verification: receiver formal type alignment

**FIXED for already placed GP value receivers (soundness, `dbbdc83`).**

At `dbbdc834b5a02894d5b8b5e8b062d3da6a7523ac`, extracting trailing integer
receiver words into `self` also removes their type placeholders from the
formal list. Previously the unequal value/type counts suppressed the
existing scalar views and typed literal rendering: an `Int8` argument
read `arg0` (or its 32-bit reload), Float `3.5` read `0x40600000`, and Bool
`true` read `1`. Receiver placement and producer-use rules retain their
existing proofs. The Onone unknown receivers remain explicit unknowns.

Own-source one- and two-word GP receivers, an FP-receiver control and
Float/Bool controls run at **-Onone / -O / -Osize**. **2,322 native
observations** include **2,304 numeric formal values** (baseline **768
refuted / 1,536 matched**, candidate **2,304 matched**) and **18 literal
controls**. **30 independent nlist/export/start/raw frames** bind **15
physical calls** to their signatures. All five public analysis APIs check
exact formal values and receiver rendering. The regression was seen red
with **180 issues**; separately rebuilt omission and one-type-only cleanup
mutations fail with **180 / 45 issues**. Exact restoration, rebuild and
focused tests pass.

The fresh fixture cache restores **901 products** from **1,172 public
inputs**. All **347 preexisting test files** are byte-identical; one new
file adds two test declarations. The full fixture-enforced suite passes
**2,007 tests / 43 suites (911.246 s)** after rebuilding.

All **762 Mach-O inputs x four views** are reviewed. Only the three new
libraries change: **40 JSON fields** (16 annotations, 12 arguments,
12 statements) for **12 sites**: six Int8 views, three Float literals and
three Bool literals. Exact reconstruction explains JSON, both source
views and listing. Raw instructions, CFG, metadata, receiver spelling and
producer effects are unchanged. The other **759 inputs** and all four SDK
workload outputs are byte-identical.

All **3,052 paired cost rows** pass default caps without overrides:
**8,574,052,349,126 -> 8,571,964,071,628 instructions (-0.024356%)**;
**28,673,162,360 -> 28,735,768,024 bytes summed per-run physical peaks
(+0.218342%)**. No speed improvement is claimed. All **416 CLI invocations**
pass: **80 metadata/xrefs pairs**, **208 stderr pairs**, **128 whole-view /
measured comparisons**, **64 filtered / whole comparisons**, and **16 Lab
pairs** are unchanged or match their corresponding reviewed output. All
**32 changed Analyze lines** and **24 changed lines per filtered source
view** map to the reviewed fields/whole-source lines. Four guarded SDK
structured rerenders match measured hashes.

The original five apps produce byte-identical outputs across **84,833
functions**, preserving every header and its order. All ten guarded renders
exit zero without kills, maximum sampled **231 MB** under the **2,000 MB**
guard. Private bodies and reports remain ignored. This is reliability/output
comparison, not source-grounded vendor accuracy scoring.

Reproduce with `Tools/fixtures.sh`, `swift build --build-tests`, and
`SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build`; native drivers are the
three `Fixtures/Sample/narrow-integer-return-SwiftReceiverTypeList.*-oracle`
products. See the [engineering record](https://github.com/CamdenBopp/swiftdc/commit/dbbdc834b5a02894d5b8b5e8b062d3da6a7523ac).
**PUBLISHED through the original integration gate:** `83443a5` (code
`dbbdc83`) passed an independent **2,007 tests / 43 suites (967.051 s)**
and was pushed to `origin/dev`. Both gate releases match the reviewed
outputs across all **762 inputs x four views** and four SDK workloads.
All **3,052 paired cost rows** pass default caps without override:
**8,574,052,349,126 -> 8,564,422,553,288 instructions (-0.112313%)**;
**28,673,162,360 -> 28,674,159,896 bytes summed per-run physical peaks
(+0.003479%)**. Both clean checkout snapshots retain the **1,172 public
input / 901 product hashes**, and a separate remote-head check confirms
publication. Independent gate release SHA256:
`f7959128c7cd520851b181a0bc0042bd23923d905d5236a25773093f436cba75`.

Hosted [run 44456365627](https://github.com/CamdenBopp/swiftdc/actions/runs/44456365627)
at `83443a5` completed successfully (suite job `135332241554`). Terminal
job state and decoded fixture-enforced logs confirm **2,007 tests / 43 suites
(2,555.394 s)**. This result covers receiver code `dbbdc83`.

**OPEN:** general argument/entry/RET/fallthrough placement, other tail-result
conversions, C/ObjC result widths, enum-bit qualification and values carried
across awaits. Existing readiness/scoring tables are not recomputed.

## Previous verification: qualified Swift argument views

At `8a1592827b1ff7fc96a5eeb3eee08c57ac868941`, bounded Swift call sites with matching type/value lists
read canonical 8/16/32-bit integer formals at their declared width and
signedness. For example, `signed8BitPatternCaller(UInt8)` previously passed
`arg0` to an `Int8` consumer: input 128 denoted 128 although the native
formal is -128. The argument now has an explicit signed view.

The existing scalar-bit proof runs before producer-use collection. Existing
exactly recovered narrow stack words keep their formal types; unproved
producer widths become `?` while their calls remain visible. Inout addresses,
receivers and FP banks retain their roles. This adds no entry, frame/context,
argument-location or extension seeds, and no semantic annotation parsing.

Own-source fixtures at -Onone/-O/-Osize provide **390 selected unique
export/nlist/start/raw frames**, **186 wrapper call sites**, and **12,645
native observations**. All **12,417 numerically classified formal values
match**, including **4,723 refuted before**. Separate scopes are **72 address
controls**, **144 unknown-width provider observations with one actual effect
per call**, and **12 observations with the existing Onone Float getter
receiver limitation**. Supplemental allocating-constructor drivers pass
**1,704 observations**, including stored bits, zero setter count and dynamic
class identity; **17 additional argument views have 34 raw/symbol/start/export
witnesses**. Nonallocating initializer exports are not separately invoked.
Existing optimized unsigned-to-signed nominal constructor aliases are not a
claim of recovered nominal receiver context.

All **346 prior test files and assertions remain byte-identical**; one file
adds five declarations. The new regressions first fail with **1,642 issues**
(register views 1,035; roles 247; opaque producers 360). Five separately
compiled mutations fail: omit Swift views (1,642), erase stack types (42),
omit producing-ABI proof (280), substitute the requested type for unknown
producer proof (360), and consume a declined producer effect (450). Exact
restoration/rebuild passes 26 focused tests, then the fresh fixture-enforced
suite passes **2,005 tests / 43 suites (884.860 s)**. Fixture cache: **895
products**. Public input snapshot: **1,168 files**.

Matched frozen releases cover **756 inputs x four views** plus four SDK
workloads. The complete corpus delta is **711 fields across 12 inputs**:
**119 native-proved argument views, 17 initializer views, and 61 honest
argument declines** (18 opaque producers, 42 outlined results, one stripped
SDK input). JSON, listing and both source views reconstruct exactly from
those changes. **60 producer statements** survive; four now appear before
existing unknown UXTH conditions. Those conditions and their consumed-call
visibility remain open. Raw instructions, CFGs, function metadata and all
other fields are unchanged.

All **3,028 paired cost rows** meet every default cap without override:
**8,554,101,285,176 -> 8,552,526,784 instructions (-0.018406%)**;
**28,505,280,064 -> 28,537,816,504 bytes summed per-run physical peaks
(+0.114142%)**. No performance improvement is claimed. The frozen main
release hashes are `a302e4b9e1715beac48449094ef2ed92257237a453506f1da07f0e7ea977c01b`
and `cfd93816ce8cbfe72edd60fb5a627cda24f72879c988d60eb75f33f0304838a7`.

All **832 CLI invocations over 32 inputs and 13 paths** pass. **160
metadata/xrefs pairs**, **416 stderr pairs** and **32 Lab pairs** are
identical; **256 whole views** match measurements and **128 filtered
comparisons** match whole bodies. All 514 changed analyze lines and the
filtered pseudo/structured changes map to the reviewed corpus fields.
Four guarded SDK rerenders match measurement hashes: Syntax is unchanged;
Parser has one enum-self byte argument to `Hasher._combine(UInt8)` become
unknown. Its raw byte load, entry seeds and call layout are unchanged.
Both SDK xrefs workloads are unchanged.

Ten original Clarc/GoodLinks/Terminal/TextEdit/Chess renders pass a **2,000 MB
footprint guard** (maximum sampled **237 MB**). All **84,833 function
headers/order** and all call spellings/counts remain intact. The **130
diff-side lines in 24 functions** are reconstructed from **52 pure argument
precision declines**, **six UInt16 mask tightenings**, and consistent result
binding cleanup. Removed binding references occur only in the declined
arguments; the calls still execute at the same statements. **144 unique
guarded filtered pseudo/JSON/Lab artifacts** inspect those functions. Two
preexisting whole/filtered precision differences remain exactly unchanged;
they are not repaired by this work. Private bodies, literals and reports
remain ignored. This is reliability/output review, not app accuracy.

**FOLLOW-UP FIXED (`dbbdc83`):** the separate GP/FP receiver probe's
value/type-list mismatch is repaired by the receiver-extraction change
recorded in its own verification entry. The earlier matching-list claim
above remains the scope of `8a15928`. General argument/entry/RET/fallthrough
placement, C/ObjC result widths, enum-bit qualification and values carried
across awaits remain open. Pinned scoring/readiness percentages are not
recomputed.

Reproduce with `Tools/fixtures.sh`, `swift build --build-tests`, and
`SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build`; authored native drivers
are the nine `Fixtures/Sample/narrow-integer-return-SwiftArgument*-oracle`
products. See the [engineering record](https://github.com/CamdenBopp/swiftdc/commit/8a1592827b1ff7fc96a5eeb3eee08c57ac868941)
for the compiled faults and their observed red regressions.

**PUBLISHED through the original integration gate:** `5c5ab71` (code
`8a15928`) passed an independent **2,005 tests / 43 suites (946.199 s)**
and was pushed to `origin/dev`. Both gate releases match the reviewed main
outputs across all **756 inputs x four views** and four SDK workloads.
All **3,028 paired cost rows** pass default caps without permission or use of
an override: **8,554,276,841,592 -> 8,559,398,887,902 instructions
(+0.059877%)**; **28,407,856,576 -> 28,578,409,896 bytes summed per-run
physical peaks (+0.600374%)**. The **1,168 public input / 895 product hashes**
matched both clean trees at publication, and a separate remote-head check
confirmed the push. Independent gate release SHA256:
`76f321ea18de668baf6ba4f7c90f28a3a82ee074b6fc71d96005b13c81833e25`.

New hosted [run 44448308320](https://github.com/CamdenBopp/swiftdc/actions/runs/44448308320)
at `5c5ab71` completed successfully. Its terminal job state and decoded
logs confirm fixture-enforced **2,005 tests / 43 suites (1,938.195 s)**;
Toolchain, Fixtures, Build and Enforcing suite all passed. This covers
published code `8a15928`, not the subsequent local receiver change. The prior
published `a841357` completed its own hosted **2,000-test / 43-suite** run;
that result does not cover these five new declarations.

## Previous verification: converted integer tail returns

At `3385323e011e675f1c5bc97078b96110ead2a17e`, an ordinary Swift function or getter tail can retain
its return when caller and callee use opposite signedness at the same
8/16/32-bit width. The previous exact-type-spelling check omitted those
returns. The existing physical-bit proof supplies the explicit mask or
signed view; branch arguments never become the result, and no ABI,
frame/context slot or extension seed is added.

Own-source evidence at -Onone/-O/-Osize covers **120 selected unique
export/nlist/function-start/raw-byte frames**, **six libraries and six native
drivers**, and **3,846 native observations including controls**. All **24
omitted optimized returns** now have explicit views; all **36 existing-return
wrapper controls** remain byte-identical. Different-width ordinary call/RET
wrappers are controls. Each selected wrapper is checked through all five
public analysis APIs. All **344 existing test files and assertions remain
byte-identical**; two files add seven test declarations. Six separate source
faults compile and fail their intended regressions, with unaffected tests and
controls green; exact restoration/rebuild is followed by **2,000 tests / 43
suites passing (907.926 s)** with fixture presence enforced.

Matched frozen releases cover **735 inputs x four views** and four SDK
workloads. The complete delta is **48 fields in 24 functions across four
new libraries**: 24 return annotations and 24 converted return statements.
Structured/pseudo/listing each change 48 diff-side lines; JSON changes 96.
Every changed JSON and text/listing output is reconstructed exactly from
those approved fields and return insertions. All raw instructions, arguments,
CFGs and function metadata remain fixed. Every other corpus output matches;
all **5,880 render exits** match, including 35 header-checked preflight-decline
pairs, and all eight SDK exits are zero. All four SDK hashes are unchanged.

All **2,944 positive paired cost rows** meet every default cap without
override: **7,796,073,720,617 -> 7,787,964,732,650 instructions (-0.104014%)**;
**27,428,898,136 -> 27,280,790,520 bytes summed per-run physical peaks
(-0.539969%)**. These qualify the cost budget; they are no speed/memory claim.
All **572 CLI runs** pass (22 inputs x 13 paths x two releases): all new and
changed inputs, legacy and named/stripped SDK controls. All 110 metadata/xrefs,
286 diagnostic and 22 Lab pairs match. All 176 whole views match measurements,
all 88 filtered comparisons match whole bodies, and Analyze/filtered changes
map to approved fields. Four guarded SDK rerenders match measured hashes.
Ten guarded renders of the original five apps retain all **84,833 function
headers, bodies and order byte-for-byte**; source/diagnostic hashes match,
maximum sampled footprint **211 MB under a 2,000 MB guard**. No source-grounded
app/SDK accuracy claim or readiness percentage follows.

Reproduce: `python3 build-swift-integer-tail-results.py`
from `Fixtures/Sample` (or `Tools/fixtures.sh` for the complete cache);
execute the six `Fixtures/Sample/narrow-integer-return-TailResults.*-oracle`
and `…TailGetters.*-oracle` products; `swift build --build-tests`, then
`SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build`. Compare frozen releases
with `Tools/blast-radius.sh <base> <new> <out> --real --perf`. The **1,159
public input / 874 fixture product hashes** remained pinned throughout
qualification. Reviewed release SHA256:
`a302e4b9e1715beac48449094ef2ed92257237a453506f1da07f0e7ea977c01b`.
The original integration gate independently rebuilt and pushed `a841357`
with code `3385323`, passing **2,000 tests / 43 suites (942.385 s)**. Both
sides match the reviewed frozen releases across all **735 inputs x four
views** and four SDK workloads. Every **2,944 paired cost row** meets the
default caps without override permission or use: **7,796,073,720,617 ->
7,794,797,509,654 instructions (-0.016370%)**; **27,428,898,136 ->
27,246,259,528 bytes summed per-run physical peaks (-0.665862%)**.
The **1,159 public input / 874 fixture product hashes** match both clean
trees; an independent remote-head check confirms publication. Gate release
SHA256: `4e16def0eb587925dfe8b73b86dfb2dbb19bef5b2a28784b8f2a9c211dd1a2fc`.

**VERIFIED hosted execution:**
[run 44423167838](https://github.com/CamdenBopp/swiftdc/actions/runs/44423167838)
at `a841357` completed successfully: **2,000 tests / 43 suites (2,384.404 s)**
with fixture presence enforced. Toolchain, Fixtures, Build and Enforcing
suite passed; terminal job status and decoded logs were checked. This
covers the published tail-return revision, separately from the newer
argument-view verification. The earlier
[run 44411756483](https://github.com/CamdenBopp/swiftdc/actions/runs/44411756483)
at `d69fff8` passed **1,993 tests / 43 suites (2,253.679 s)** on **Xcode 27.1 /
Swift 6.4**.

Still open: other tail-result conversions (including differing widths and
64-bit sign views), general Swift argument/entry/RET/fallthrough cases,
C result widths, enum-bit qualification and values carried across awaits.
Pinned scoring tables are not recomputed. The
[engineering record](https://github.com/CamdenBopp/swiftdc/commit/3385323e011e675f1c5bc97078b96110ead2a17e)
names each separately compiled fault and the regression seen red under it.

### Earlier narrow-return verification

At `3ba928e1387e58ad1a4b9c173a78b50e9c51a01b`, narrow Swift integer returns use their declared signed or
unsigned 8/16/32-bit view after proving the available physical bits. Existing
argument, field, call-result and qualified awaited-result facts supply that
proof; no new ABI or async-slot seed is created. Unproved C results decline
while retaining their call, including tail exits.

Own-source evidence covers **45 exported/function-start/raw-byte entries at
-Onone/-O/-Osize**, **54 fixture products** and **702 native observations**
(453 conversion observations and 249 controls). Twenty refuted return
instances now show an explicit view; three refuted signed-to-unsigned C
wrapper results now decline with their calls retained. Existing getter and
partial-memory views are controls. The address-only API's existing Osize
outlined-helper decline remains pinned. This is no general ABI coverage or
native async correctness claim.

The rebuilt enforcing suite passes **1,993 tests / 43 suites (1,021.366 s)**.
All **342 original test files remain**: 341 byte-identical, with the annotation
oracle extended by 16 added lines and no original assertion removed. Sixteen
new tests include **12 regression guards each observed red under compiled
faults** and four controls. **27 independently compiled faults** are rejected;
the four controls stay green throughout. Exact source restoration rebuilds
and passes all 30 focused tests. All **1,152 public inputs / 862 fixture
products** stay fixed through qualification and review.

Matched frozen releases over **723 inputs in four views plus four SDK
workloads** yield **2,896 positive paired cost rows**: **+0.056923% instructions /
+0.198652% summed per-run physical peaks**. Every default limit passes without
override. All **5,784 render exits** match, including **35 unchanged preflight
decline pairs independently checked against raw headers**. All eight SDK
workload runs exit zero. Three SDK workload output pairs are identical; the
Syntax structured change is one enum getter precision loss, described below.

All **23 changed corpus inputs / 71 functions / 158 JSON fields** are reviewed.
Candidate JSON and every changed listing, pseudo and structured line
reconstruct exactly from the classified changes. Raw instructions, arguments,
blocks and function metadata stay fixed. The costs include 36 C wrapper
return declines and three SDK unknown-result references; nine SDK witnesses
gain explicit same-width signed-to-unsigned views. The indirect calls remain
visible. Independent SDK evidence checks **18 nlist/function-start frames /
3,007 raw instruction words**. Named/stripped SDK text matches. Separately,
`CompilerSwiftSyntax.Keyword.rawValue.getter : UInt8` changes `(self & 255)`
to `?` because enum-self bit width is unproved. This is a precision cost,
not a refutation of its old value. Independent symbol/start/raw checks bind
its two instructions (ldrb/ret) to ten guarded filtered/Lab runs; both
structured bodies match measured output and raw Lab facts stay identical.

All **1,742 CLI runs** pass (67 inputs, 13 commands, two releases). All 335
metadata/xrefs pairs, 67 Lab pairs and 871 diagnostic pairs match. All 536
whole views match their measured renders, all 268 filtered comparisons match
whole bodies, and all Analyze/filtered changes map to approved fields.
An additional 48 filtered runs cover every changed SDK function. Four guarded
SDK structured rerenders match measured hashes. Ten guarded renders of
Clarc/GoodLinks/Terminal/TextEdit/Chess retain all **84,833 function headers,
bodies and order byte-for-byte**; all original app hashes and diagnostics
match. Maximum sampled footprint is **211 MB under a 2,000 MB guard**.
No source-grounded SDK/app accuracy claim or readiness percentage follows.

Reproduce: `Tools/fixtures.sh`; execute the 27
`Fixtures/Sample/narrow-integer-return-*-oracle` binaries; rebuild with
`swift build --build-tests`, then
`SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build`. Compare matched frozen
releases with `Tools/blast-radius.sh <base> <new> <out> --real --perf`.
Reviewed candidate SHA256:
`879cd1118b45598489c2209d89bc4463a873fcaecceef583930ce5a27018f81a`.
The original integration gate independently rebuilt and pushed `6c40aea`
with code `3ba928e`, passing **1,993 tests / 43 suites (962.779 s)**.
Both sides match the reviewed releases across all **723 inputs x four views**
and all four SDK workloads. All **2,896 paired cost rows** meet every default
cap without override permission or use: **7,704,142,369,610 ->
7,717,056,592,175 instructions (+0.167627%)**; **26,858,166,808 ->
27,034,322,280 bytes summed per-run physical peaks (+0.655873%)**.
The **1,152 public file / 862 fixture product hashes** match main and gate;
both trees were clean, and a fresh fetch confirmed the remote head.
Independent gate release SHA256:
`a37b9db488cf42e29251286de2eb001ac3652f883b5798b60f5bfbb6324fd717`.
Hosted [run 44400919902](https://github.com/CamdenBopp/swiftdc/actions/runs/44400919902)
failed **Toolchain** on **Swift 6.2.4 / Xcode 26.3**. Fixtures, build and the
enforcing suite were skipped. The completed job/logs were checked; this
provides no hosted test result.

Still open: exact C result widths, enum-bit qualification, differing-Swift-result
tail completeness, general Swift argument/entry/RET/fallthrough cases and
values carried across awaits. Pinned scoring tables are not recomputed.
See the [engineering record](https://github.com/CamdenBopp/swiftdc/commit/3ba928e1387e58ad1a4b9c173a78b50e9c51a01b)
for the compiled fault-to-test mapping.

At `9ed9748`, qualified C declaration arguments read their declared signed
or unsigned 8/16/32-bit value instead of an entire register. Wide Swift scalar
inputs receive explicit truncation/sign interpretation; unavailable physical
bits decline before producer-use collection, retaining the producing call.
Computed comparisons, literal phis and masks retain their proven complete 0/1
words. A bare source Bool does not prove the rest of its incoming register.

Own-source fixtures cover **12 functions at all three Swift optimization
levels**, **36 independently bounded exported entries**, **57 native
observations**, **96 numeric conversions** and **96 computed-word cases**.
All **341 existing Swift test files remain byte-identical**. Eleven tests are
added: eight regressions observed red under **ten independently compiled
faults**, plus three independent controls. Restored tests rebuild green.
The fixture-enforced suite passes **1,977 tests / 43 suites (960.794 s)**.

Against the prior published behavior (`3a51ab8`), **669 inputs in four views
plus four SDK workloads** give **2,680 paired cost rows**: **+0.014855%
instructions / +0.376453% summed per-run physical peaks**. Every default budget
passes without override. All **5,352 render exits** match, including the
**35 independently checked preflight-decline pairs**; those remain declines.
Both releases use the exact same **808-product corpus**. All **1,141 public
input hashes** remain fixed throughout qualification and review. The cache
retains every product; 184 product hashes changed during the full rebuild,
mostly UUID/stabs changes. No cross-slice product-byte equivalence is claimed.

All differences are reviewed: **five inputs / 130 JSON fields**, comprising
**56 own-source corrected fields, 54 precision fields, ten value-equivalent
views and ten binding renames**. Every listing (90), structured (87), pseudo
(87) and JSON (249) diff-side line maps to these fields. Applying the fields
reconstructs candidate JSON exactly; function/block/CFG metadata and raw
instruction data match. C result widths remain unproved: getpid/fileno
producers stay visible while affected consumers lose arguments. The stripped
SDK strerror_r site also loses an unqualified argument; its named counterpart
was already unknown. These are explicit precision costs, not native-refuted
old values. Raw instruction bytes, starts and strong system imports corroborate
the changed SDK sites.

All **416 CLI/view invocations** pass. Metadata/xrefs and all 16 Lab pairs
match; whole/filtered outputs and every analyze delta are reviewed. Four
guarded SDK rerenders match measured hashes; all four SDK workload pairs are
byte-identical. Ten guarded renders of the original five apps pass and retain
all **84,833 function headers/order**. **216 changed functions / 874 diff-side
lines** contain **397 argument precision losses and seven value-equivalent
views**. All **974 visible catalog calls** retain their exact order/count;
14 lifted ObjC/Swift producer cases retain complete expressions. Independent
Mach-O/raw checks cover **33,108 instruction words, 419 direct C consumer
sites and 74 strong import/provider names**. Memory-write widths and control
statement counts remain. TextEdit is unchanged. Maximum sampled footprint is
**336 MB under a 2,000 MB guard**. These checks measure vendor-binary output
reliability; source-grounded app accuracy remains unmeasured.

Reproduce: `Tools/fixtures.sh`; run the three
`Fixtures/Sample/c-narrow-arguments-*-oracle` executables; rebuild with
`swift build --build-tests`, then
`SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build`. Compare matched frozen
releases using `Tools/blast-radius.sh <base> <new> <out> --real --perf`.
Reviewed release SHA256:
`49c17af2630176679118565e82c9a5e6d983e1a5f1dfb7e2c9d893e85b897877`.
The original integration gate independently rebuilt `549350f`, passed
**1,977 tests / 43 suites (1,034.902 s)**, and pushed it with code `9ed9748`
to `origin/dev`. Both sides of the gate comparison match the reviewed frozen
releases across all **669 inputs in four views** and four SDK workloads.
All **2,680 paired cost rows** meet every default limit without an override:
**7,599,375,196,685 -> 7,606,306,521,185 retired instructions (+0.091209%)**;
**25,294,568,272 -> 25,393,504,080 bytes summed per-run physical peaks
(+0.391135%)**. The gate's **1,141 public file / 808 fixture product hashes**
match main, both trees were clean, and a fresh fetch confirmed publication.
Independent gate release SHA256:
`5c47463d19a9c0ccfa933489ca031215bad628409ace3c30e7282e2ab660d899`.
Hosted [run 44359228060](https://github.com/CamdenBopp/swiftdc/actions/runs/44359228060)
failed **Toolchain** on **Swift 6.2.4 / Xcode 26.3**. Fixtures, build and the
enforcing suite were skipped; it supplies no hosted test result.

**OPEN:** C result widths, fixed integer parameters on special format paths,
C Bool formals, source widths for fields/call results, general Swift
argument/RET narrowing, incoming-x8 ownership and values across awaits.
Pinned Ghidra/entry benchmarks and readiness/coverage percentages are unchanged.
See the [engineering record](https://github.com/CamdenBopp/swiftdc/commit/9ed974813e44b84da368f40adeb8627cabce43bf)
and [readiness follow-up](PRODUCTION-READINESS.md#2026-11-18-read-c-arguments-at-their-declared-widths).

The projection-result verification below remains historical.

At `3a51ab8`, opaque boxed-existential projection results retain possible
caller-frame origins. A later write through the returned pointer now declines
a stale local value. The own-source fixture has **48 callers / 144 native
observations**: **70 known results** across named/stripped images were wrong
and now decline; **26 correct controls** stay unchanged. The three optimization
levels apply to the C driver; the two assembly helper bodies are fixed.

All **340 existing Swift test files are byte-identical**. Eleven tests are
added: ten regression tests each seen red and one native/raw/import control.
**22 independently compiled faults** fail with the native control green;
canonical restoration and rebuilt tests pass after every batch. The fresh
fixture-enforced suite passes **1,966 tests / 43 suites (922.508 s)**.

Against the published `7a7f43f` release, **663 inputs in four views plus four
SDK workloads** give **2,656 paired cost rows**: **+0.01% instructions /
-0.46% summed per-run physical peaks**. Every default budget passes without
override. The **35 identical preflight-decline pairs** are independently
checked against raw headers and remain declines. Both releases use the same
**802-product corpus**, with **1,075 public input hashes** pinned throughout.
The cache adds five products; 181 existing product hashes changed on rebuilding.

Every difference is reviewed: **12 inputs / 80 functions / 436 JSON fields**,
with 342 listing, 288 structured, 286 pseudo and 832 JSON diff-side lines.
The 70 new-fixture results account for 210 fields. The remaining 226 fields
are **precision losses in ten existing inputs** after possible pointer escape:
metadata, receivers, vectors, result aliases and saved return values decline.
Twelve inferred indirect targets retire; xrefs reports the additional unresolved
sites with its existing warning. General readonly/noncapture summaries remain
open. These precision costs are separate from the 70 native-refuted results.

All **858 core CLI/view invocations** pass; all differences and the pre-existing
filtered/whole extent or address-label variants are classified. Four guarded
SDK rerenders match measured hashes. Whole SwiftSyntax changes six lines for
an unused binding and producer renumbering; the other three SDK workload
hashes match. Ten guarded renders of the original five apps pass and retain
all **84,833 function headers and order**. Clarc and GoodLinks change **93
functions / 930 diff-side lines**, reviewed against raw instructions as further
precision losses; Terminal, TextEdit and Chess are byte-identical. Maximum
sampled footprint is **201 MB** under a **2,000 MB** guard. These checks measure
vendor-binary output/reliability; app accuracy remains unmeasured.

The original integration gate independently rebuilt `877e613`, passed
**1,966 tests / 43 suites (983.799 s)** and pushed it with code `3a51ab8`
to `origin/dev`. All **663 inputs in four views** and all four SDK workload
hashes match the reviewed release. All **2,656 paired cost rows** meet every
default budget without override: **+0.10% instructions / +0.15% summed physical
peaks**. All **1,075 source / 802 product hashes** agree between main and gate;
a fresh fetch confirmed remote agreement. Gate release SHA256:
`6396b0d83af266954f1a3ea8f81dcbde98536ccab1b1cd4fe997ad1e74065b78`.
Hosted [run 44320110986](https://github.com/CamdenBopp/swiftdc/actions/runs/44320110986)
failed **Toolchain** on **Swift 6.2.4 / Xcode 26.3**. Fixtures, build and the
enforcing suite were skipped; it supplies no hosted test result.
The prior gate and hosted toolchain failure below remain historical. Pinned
Ghidra/entry measurements and readiness/coverage percentages are unchanged.
See the
[engineering record](https://github.com/CamdenBopp/swiftdc/commit/3a51ab8f414ea2c80c3c8f4f4e1a10e4a55d455f)
and [readiness follow-up](PRODUCTION-READINESS.md#2026-11-18-retain-frame-origins-of-projection-results).

The earlier body-proof verification follows as historical evidence.

At `c0429a1`, boxed-existential projection memory preservation and call
hiding require an independently checked complete helper body. A foreign
import or in-image mutator with that name no longer keeps a stale local
value or disappears from the output. Exact 9/19-instruction projection
bodies remain supported through direct calls and immutable pointers; names,
SDK declarations, ARC identity and no-Swift-error proofs do not supply this
memory fact. Late additions and revocations refresh the analysis.

All **339 existing Swift test files and function declarations remain**;
**338 files are byte-identical**. One test supplies explicit body proof to
its original positive expectations and adds name-only rejection. **13 tests
are added**: twelve regression tests each observed failing and one native
control. **25 independently compiled faults** fail with **1,681 assertion
issues**, while the native control stays green. Own-source assembly and C
drivers give **129 native observations**, at three **C driver** optimization
levels; this is not a three-level Swift code-generation claim. The fresh
fixture-enforced **1,955 tests / 43 suites** pass (**903.366 s**).

Against the published `90b4169` release, **658 inputs in four views plus
four SDK workloads** give **2,636 paired cost rows**: instructions **+0.60%**,
summed per-run physical peaks **+0.07%**. Every default budget passes without
override. Only the new client and its stripped copy change: five functions,
22 JSON fields, 14 listing diff-side lines and 11 lines in each pseudo and
structured view. Every delta is reviewed against native execution and raw
LLVM instructions/imports. The 35 identical independently checked
preflight-decline pairs are not successful decompilations.

All **468 CLI invocations** pass and every difference is classified. Four
guarded SDK rerenders match measured hashes; all four whole-SDK
structured/xrefs output pairs are unchanged. Ten guarded renders of the
five original apps pass with **byte-identical output**, retaining all
**84,833 function headers and their order**; maximum sampled
footprint is **195 MB** under a **2,000 MB** guard. This is output
reliability, not source-grounded app accuracy. The final rebuilt release is
byte-identical to the reviewed candidate.

The original integration gate independently rebuilt `7a7f43f`, passed
**1,955 tests / 43 suites (994.975 s)** and pushed it and code
`c0429a1` to `origin/dev`. All **658 inputs in four views** and all four
SDK workload hashes match the reviewed release. Gate costs are
**+0.71% instructions / +0.38% summed physical peaks**; all
**2,636 paired cost rows** meet every default budget without override.
All **1,071 source / 797 product hashes** agree in main and gate checkouts;
a fresh fetch confirmed remote agreement. The independent gate release
SHA256 is `dca3dbdd1d4728ddf053b558a8dc573da780ff2d4244ce7dfd41a4218175e1a4`.
Hosted [run 44289424221](https://github.com/CamdenBopp/swiftdc/actions/runs/44289424221)
failed Toolchain on **Swift 6.2.4 / Xcode 26.3**. Fixtures, build and the
enforcing suite were skipped; it supplies no hosted test result.

A historical check against Claude's `ff0e782` retains all **318 original
Swift test files** and their named function declarations. **293 files are
byte-identical**; the other **25** have reviewed setup/expectation changes,
including explicit declines, FP views and positive binding/body evidence.
No `@Test` or `@Suite` annotations were removed. Inspect the original-file
changes with `git diff --diff-filter=M ff0e782..7a7f43f -- Tests`.

The in-image near-shape helper's existing two-GP body-read projection is
not a full source-formal ABI proof: its handwritten x9 input remains
outside that projection. Returned projection-pointer aliasing is addressed by
`3a51ab8` above. Other name-only call effects, general source ABI and incoming-x8
ownership, C widths, RET/fallthrough and values across awaits remain open. Pinned
Ghidra/entry benchmarks and readiness/coverage percentages are not recomputed.
See the
[engineering record](https://github.com/CamdenBopp/swiftdc/commit/c0429a16395044d146ce382658186c73e59581d3)
and [readiness follow-up](PRODUCTION-READINESS.md#2026-11-18-require-body-proof-for-boxed-existential-projection-effects).

The provider-binding verification below is historical evidence.

At `3af60f8`, catalogued SDK/runtime declarations require an exact
symbol/provider binding before supplying argument layout, result-bank,
memory-helper or result-buffer facts. A foreign Swift function named
`getpid`, `sqrt`, `free`, `CGRectInset`, `printf` or `malloc` cannot borrow
the SDK declaration. Language conventions remain independent, and ARC
retains its stronger identity requirement. Late binding refreshes the
analysis when needed; a stack-probe replay is omitted only when the initial
trace already used that exact GOT slot's special transfer.

All **338 existing Swift test files and declaration counts remain**;
**330 files are byte-identical**. Seven files supply binding evidence to
positive controls; one Go expectation retires an unproven prototype while
checking the exact call and raw inputs. **27 tests are added**, including
25 regression tests observed failing under independently compiled faults
and two independent native/declaration controls. **34 faults** compile and
fail their intended assertions. Own-source fixtures at Onone/O/Osize, named
and locally stripped, pass **672 native observations**, **30 import checks**
and **45 lowered declaration/definition checks**. The buffer native control
reads the first field; decompiler assertions inspect all five stored words.
The rebuilt fixture-enforced **1,942 tests / 43 suites** pass
(993.561 s).

Against `1635cbc`, **648 inputs in four views plus four SDK workloads** give
**2,596 paired cost rows**: instructions **+0.08%**, summed per-run physical
peaks **+0.54%**. Every default budget passes without override. All changed
fixture fields and lines are reviewed; serialized raw-instruction and
control-flow DTOs match. The corpus includes **35 identical independently
checked preflight-decline pairs**, which are not successful decompilations.
Four guarded SDK rerenders match the measured hashes; both whole-SDK
structured and xrefs output pairs are unchanged. All **1,248 CLI invocations**
pass, with every delta classified. Ten guarded renders of the five original
apps pass (maximum sampled **203 MB** under a **2,000 MB** guard). All
**84,833 function headers and their order** remain; all **1,674 changed
diff-side lines / 391 functions** are reviewed. This is an output-reliability
comparison, not source-grounded app accuracy. Production and fixture bytes
are unchanged since those CLI/SDK/app runs; an added synthetic late-probe
test prompted a fresh full suite and cost comparison.

The original integration gate independently rebuilt `90b4169`, passed
**1,942 tests / 43 suites (1014.377 s)** and pushed it and code `3af60f8`
to `origin/dev`. All **648 inputs in each of four views** and all four SDK
workload hashes match the reviewed release. Gate costs are **+0.19%
instructions / +0.06% summed per-run physical peaks**; every default budget
passes without override. A fresh fetch confirmed agreement with origin/dev.
Hosted [run 44271037278](https://github.com/CamdenBopp/swiftdc/actions/runs/44271037278)
at `90b4169` failed Toolchain on Swift 6.2.4 / Xcode 26.3; fixtures, build and
the enforcing suite were skipped. It supplies no hosted test result.
General/transitive incoming-x8 ownership, narrow C
widths, other name-only call-effect models, RET/fallthrough reconstruction
and values across awaits remain open. No pinned Ghidra/entry benchmark or
readiness/coverage percentage is recomputed. See the
[engineering record](https://github.com/CamdenBopp/swiftdc/commit/3af60f82f0652308f834a534b21b1dd8c0237c17)
and [readiness follow-up](PRODUCTION-READINESS.md#2026-11-18-qualify-named-declaration-contracts-by-provider).

The compare-and-branch follow-up below is historical evidence.

At `86054a1`, the tracer reads `cbz`/`cbnz` operands at their encoded
width. A test of `w0` previously used the entire tracked `x0`: with a
producer returning `0x100000000`, native execution returned 1 while the
rendered whole-result condition selected 2. Word tests now retain a
low-word mask in branch facts and selected values; 64-bit tests stay wide.

All **337 existing Swift test files and declarations remain**; **336 files
are byte-identical**, and one lab assertion is strengthened to require the
masked condition. Four tests are added. **Three independently compiled
faults** fail their intended tests, with native controls green. Own-source
assembly and C callers at O0/O2/Os pass **216 native observations**; named
and locally stripped libraries cover **240 function/API cases**. The full
fixture-enforced **1,915 tests / 43 suites** pass (924.489 s).

Against `23d7bb1`, **610 inputs in four views plus four SDK workloads** give
**2,444 paired cost rows**: instructions **-0.05%**, summed per-run physical
peaks **+0.12%**. Every default budget passes without override. Every changed
line across **80 inputs / 147 functions** is reviewed; each change is the
low-word mask, with serialized raw-instruction/control-flow DTOs unchanged.
Six additional whole-SDK Boolean stores have independent LLVM raw checks.
All **234 CLI invocations**, four guarded SDK rerenders and ten guarded
renders of the five original apps pass. The app changes are **129 line
pairs / 133 inserted masks**, preserving surrounding calls and control text;
maximum sampled footprint is **210 MB** under a **2,000 MB** guard.

The original integration gate independently rebuilt `1635cbc`, passed
**1,915 tests / 43 suites (945.388 s)** and pushed it and code `86054a1`
to `origin/dev`. All **610 inputs in four views** and all four SDK workload
hashes match the reviewed release. Gate costs are **+0.07% instructions /
+0.23% summed per-run physical peaks**, with every default budget passing
without override. A fresh fetch confirmed agreement with origin/dev.
Hosted [run 44219380730](https://github.com/CamdenBopp/swiftdc/actions/runs/44219380730)
at `1635cbc` failed Toolchain on Swift 6.2.4 / Xcode 26.3; fixtures, build
and the enforcing suite were skipped. It supplies no hosted test result.
Earlier hosted [run 44209378717](https://github.com/CamdenBopp/swiftdc/actions/runs/44209378717)
at `23d7bb1` failed Toolchain before fixtures/build/tests, so it supplies no
hosted test result. Foreign C prototypes and other named runtime contracts,
general RET/fallthrough reconstruction and values across awaits remain open.
No pinned benchmark or readiness/coverage percentage is recomputed. See the
[engineering record](https://github.com/CamdenBopp/swiftdc/commit/86054a10d6906d10c82b4676f909dfa80557b7c6) and
[readiness follow-up](PRODUCTION-READINESS.md#2026-11-17-preserve-compare-and-branch-operand-width).

The callee error-proof follow-up below is historical evidence.

At `e0b608c`, Swift error checks require a language contract, exact
callee ABI binding, or independent body-preservation proof. A plain symbol
name alone no longer proves that x21 survives. Separate Swift providers named
`plain_error_raise` and `getpid` previously caused real error paths to fold
away. Closed body proofs also reject redirected returns, open fallthroughs,
unresolved transfers and strict transitive frame-alias hazards.

All **335 existing Swift test files are byte-identical** to the previous
published HEAD; two new files add **34 tests**. **95 independent mutations**
(91 product, four generator) compile and fail their intended tests; all
**342 native observations** remain green under each. Six compiler ABI pairs
and twelve call instructions establish `swiftcc`/`swifterror`; twelve import
inspections distinguish the custom provider from libSystem. The full
fixture-enforced **1,911 tests / 43 suites** pass (950.578 s).

Against `c095298`, **601 inputs in four views plus four SDK workloads** give
**2,408 paired cost rows**: retired instructions **+1.39%**, summed per-run
physical peaks **+0.88%**. Every default budget passes without override.
Every delta across **14 inputs / 86 functions** is reviewed; serialized
instruction and control-flow DTOs match. SDK changes recover six raw-proved
Bool returns and two saved allocation pointers. All **468 CLI invocations**,
four guarded SDK rerenders and ten five-app renders pass; paired app outputs
are identical (maximum sampled 196 MB under a 2,000 MB guard).

The original integration gate independently rebuilt `23d7bb1`, passed the
same **1,911 tests / 43 suites (959.261 s)** and pushed it and code `e0b608c`
to `origin/dev`. Every reviewed output matches: **601 inputs in four views
plus four SDK workloads**. Gate costs are **+1.48% instructions / +1.04%
summed per-run physical peaks**, with every default budget passing without
override. A fresh fetch confirms local dev and origin/dev agree.
Hosted [run 44209378717](https://github.com/CamdenBopp/swiftdc/actions/runs/44209378717)
at `23d7bb1` failed Toolchain (Swift 6.2.4 / Xcode 26.3); fixtures, build
and the enforcing suite were skipped. This supplies no hosted test result.
Hosted [baseline run 44124725391](https://github.com/CamdenBopp/swiftdc/actions/runs/44124725391)
at `c095298` failed Toolchain (Swift 6.2.4 / Xcode 26.3); fixtures, build
and tests were skipped. This supplies no hosted test result. Foreign C
prototype arity/order/results/memory ownership, general RET reconstruction
and values across awaits remain open. No pinned benchmark or readiness
percentage is recomputed. See the
[engineering record](https://github.com/CamdenBopp/swiftdc/commit/e0b608c2873fa4c3a30f0d23bce75d0651fda0cf) and
[readiness follow-up](PRODUCTION-READINESS.md#2026-11-17-qualify-callee-evidence-for-swift-error-folds).

The ordinary-call follow-up below is historical evidence.

At `09324d7`, ordinary BL forwarders retain unknown source inputs even
when the caller has no tracked argument snapshot. Possible FP inputs close
through the call graph separately from positive parameter proofs. When GP/FP
source order is unproved, values decline to `?`; fixed pointer prefixes of
unambiguous compiler helpers remain. Native controls pass **195 observations**
across O0/O2/Os and **160 caller/API contract cases** across named and locally
stripped fixtures. Complete forwarding arity/order remains open.

All **334 original Swift test files and named functions** remain. **Five
original test files intentionally change expectations** for newly recognized
input uncertainty; placed-capture, zero-input and closed-body positive controls
remain. Ten tests are added. **26 unique product mutations** separately compile
red, with native controls green; an additional run proves the amended capture
expectations red. The fixture-enforced **1,877 tests / 43 suites** pass
(827.707 s). The original integration gate independently rebuilt `9b28a45`,
passed the same **1,877 tests / 43 suites** (1002.168 s), passed every default
cost budget and pushed both commits to `origin/dev`. All **583 inputs in each
of four views** and all four SDK workload hashes match the reviewed release.

Against `e6c478c`, **583 inputs in four views plus four SDK workloads** give
**2,336 paired cost rows**: retired instructions **-2.48%**, summed per-run
physical peaks **-0.59%**, all default budgets passing without override.
All changed lines are reviewed, including the large Go changes and SDK/five-app
expression/binding redisplays. Decoded instruction/target/control-flow DTOs match;
this comparison does not prove app-wide source semantics. All **130 CLI runs**,
four SDK rerenders and ten guarded renders of the five original apps pass.
No pinned benchmark or readiness estimate is recomputed. See the
[engineering record](https://github.com/CamdenBopp/swiftdc/commit/09324d78f3bcc4d82533bdb312bd62d4e5212066) and
[readiness follow-up](PRODUCTION-READINESS.md#2026-11-17-retain-input-uncertainty-through-ordinary-calls).

The previous x8 follow-up is retained below as historical evidence.

At `9479048`, an incoming x8 read no longer establishes result-buffer
ownership. Unsupported entries decline in both entry seeds and caller result
conventions; removing a phantom seed retains proved or opaque input extents.
Native controls pass **53 LLVM signatures / 420 observations** across
assembly, fixed/resilient Swift, reabstracted and ObjC results. Separate
Go-absent builds retain all **53 signatures / 406 observations**.
All **1,845 existing tests** remain, with every original test body/assertion
byte-identical across **333 Swift files**; only a selected-FP setup helper
changes. **22 tests** are added. **48 product mutations and two fixture
controls** separately compile red with native controls green. The full
fixture-enforced **1,867 tests / 43 suites** pass (849.252 s).

The original integration gate then rebuilt committed `917dea7`, passed the
same **1,867 tests / 43 suites** (907.882 s), passed every default cost budget
and pushed it to `origin/dev`. Its independently built release matches all
**578 inputs in four reviewed views** and all four SDK workload hashes.
This is bounded x8 ABI qualification, not actual sret ownership or complete
Go source input/result recovery. Resolved BL-only forwarding arity remains
open; an absent list does not establish zero source parameters. See the
[hash-pinned engineering record](https://github.com/CamdenBopp/swiftdc/commit/947904890b2b712b7b33ef0492a3ec74da20c1ac)
and [readiness follow-up](PRODUCTION-READINESS.md#2026-11-17-qualify-incoming-x8-by-the-entry-abi).

Earlier, at `774ed56`, failed complete callee transfers retain their proved
possible writes. The native controls pass **105 observations** across C O0/O2/Os,
covering context, result-buffer and private-frame aliases; the existing
**15** AsyncCalls native cases also pass. All **1,838** existing test
declarations remain and every existing test file is byte-identical. Seven
tests are added; **23** distinct mutations separately compile and fail.
The fixture-enforced suite passes **1,845 tests / 43 suites**. This is a
bounded memory-effect correction; unmodelled callees and general source
reconstruction remain open.

Earlier, at `92e1007`, body-only call layouts no longer turn possible register reads
into source arguments. The native fixture passes **252 observations / 147
opaque effects** at O0/O2/Os; eight new tests cover named/stripped images,
five analysis APIs, GP/FP ambiguity and exact input forwarders. All **1,830**
existing test declarations remain. Seven old test files change expected
argument tails; the identity and memory-budget tests are byte-identical.
**Thirty** separate mutations compile and fail their targeted checks. The
full fixture-enforced suite passes **1,838 tests / 43 suites**. This does not
prove complete source arity or arbitrary forwarding through calls.

Earlier, at `7311942`, body-proven unwritten x0/v0 registers retain their
physical values through opaque helper calls. Five tests were added; **1,830
tests / 43 suites** passed. Native controls cover 21 assembly observations
and 142 compiler-generated async observations. At `29bb3b2`, ambiguous async
integer prefixes were declined; ordinary values carried through arbitrary
await context slots remain open.

Earlier, at `59db870`, scalar FP call controls checked **44 LLVM ABI
signatures / 36 native observations** and **1,815 tests / 43 suites** passed.
Synthetic Objective-C and async return checks did not establish a native
async ABI.

Earlier, at `7fd125d`, the scalar FP entry fixture checks **24 LLVM ABI signatures**
and **192 native observations**. Five new tests cover entry precision,
physical register views, field proofs, copies and async slot-proof limits.
All **1,805** upstream test declarations remain; the full fixture-enforced
suite passes **1,810 tests in 43 suites**, compared against `2425b30`.

Earlier, at `542f6a7`, dev and the seven local FP commits were reconciled.
The earlier **1,468** count belonged to stale local `23cbcab`, based on
`cc525d7`; it omitted 260 later upstream commits. It did not establish a
passing suite for current upstream dev. The merge retains all **1,780**
upstream test declarations, the **24** local additions, and one new
integration test: **1,805 tests in 43 suites** passed at that commit.

| Check | Result | Where |
|---|---|---|
| Enforcing test suite (a missing fixture fails) | 1,877 tests / 43 suites pass at `09324d7` (827.707 s); independent gate at published `9b28a45` passes (1002.168 s) | `SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build`, after a fresh test build; `Tools/integration-gate.sh --push` |
| Output change against `e6c478c` | 583 inputs in four views. Structured/pseudo: 63 changed inputs, 39,719/40,248 lines; listing/JSON: 75, 41,088/153,241 lines. Every difference reviewed; SDK source outputs differ, xrefs match | `Tools/blast-radius.sh` |
| Cost budget (instructions, footprint) | Published gate: 2,336 paired rows; -2.32% retired instructions, -0.24% summed per-run peak footprint. Every default budget passes without override; output hashes match the reviewed release | same, `--real --perf` |
| GitHub Actions, inspected 2026-11-17 | Run at published `9b28a45` is queued at inspection, with no test result yet. Earlier `e6c478c` fails Toolchain on Xcode 26.3 / Swift 6.2.4; fixtures, build and suite are skipped. The older runner-capacity failure is separate | [run 44121265588](https://github.com/CamdenBopp/swiftdc/actions/runs/44121265588), [previous run](https://github.com/CamdenBopp/swiftdc/actions/runs/44073528460), [CI.md](CI.md) |
| Independent execution of rendered expressions | return values of the differential-oracle fixtures, integer and floating point (compared bit for bit). Not checked by execution: which way a branch went, registers at call sites, results beyond the first register, memory writes | `DifferentialOracleTests` |

Render exit statuses match the baseline, including **35** identical expected
preflight declines for object and unsupported input shapes. Those declines
are not successful decompilations.

These checks are local measurements on one machine. Publication still
requires the original `Tools/integration-gate.sh --push` to rebuild, test
and compare the committed head. Until a CI run completes, the local
results are author-reported.

## Robustness

| Measurement | Result | Commit |
|---|---|---|
| Malformed Mach-O mutants: 354 mutants, 10 entry points, 3,540 runs | 0 signal-terminated (89 before the fix) | d4ed36b |
| An image built with the direct retain/release runtime (a 64-bit bind addend with the top bit set) | exit 0 on 10 entry points (SIGTRAP on 5 before) | b814bc0 |
| Synthetic corpus: built products with a failing output directive | 53 of 226; no command exited nonzero on any product | 5f012f8 |

The corpus checker now fails on a nonzero exit from any command, on a
failed determinism repeat, and on a directive whose view did not render
(it used to accept the first for six commands and skip the other two).
Run strictly, nothing was hiding behind those: all 53 failures are
output directives. They are failing products, not 53 distinct defects,
and not a sample of real code. Reproduce: `Tools/synthcorpus/build.sh`
then `Tools/synthcorpus/check.py --swiftdc <binary>`.

## Open defect classes, most damaging first

A read of the compiler's own source against swiftdc (thirty areas,
2026-11-13) reported more wrong-render classes than the list below
holds. They are recorded as leads, not yet measured, in
[research/compiler-source-read-2026-11-13.md](research/compiler-source-read-2026-11-13.md)
and ranked in PRODUCTION-READINESS.md. The three that touch the most
ordinary code: a property's function type read as an accessor's
parameter list (fixed in part, 60ce7c7), preconditions folded away as
overflow checks (fixed, 28df4e7), and stores hidden as runtime noise (shown
since 77a2886).

1. **C return values.** A function with no signature whose x0 is only
   its last call's result, a float in d0, or a load shows no result (137
   frames and 22 globals bodies in the scoring above).
2. **Calls taking arguments the binary bounds away**: a register-target
   call to an in-image function, sanitizer and other void runtime hooks,
   zero-formal mutating Array members at -Osize.
3. **Code dropped**: an overflow or bounds trap folded away inside a
   loop, a C store with an extended index, the first segment of an -O
   string interpolation, `yield` in `_read` and static `modify`.
4. **Switches**: clang's `adr`/`ldrb` jump tables are not decoded, and
   -O0 tables placed after a `ret` render as functions.
5. **Unseeded entries (declines)**: loads through a struct passed by
   address, Array count and element loads, closure and pack parameters,
   non-allocating initializers.
6. **arm64e**: `aut*`/`pac*` are not modelled as identities, so vtable
   and witness calls are unnamed.
7. **No noreturn model at -O2/-Os.**

Fixed since the 2026-11-13 06:16 UTC external review (at a78bdb2), each
with a test seen failing without it: x18 surviving a call (a47f0f2);
malformed linkedit traps (d4ed36b); signed `scvtf` on UInt (58580ca);
optional protocol properties (98d5b42); key path intrinsics (7602e01);
mixed-bank struct self and parameters (87ac62f, d55b351, 7b5d6a5); bare C returns, in part
(36ba8db, 5f012f8); signed compares on UInt, including the negative
constant (275a60b); tail returns to getters and runtime entries
(466b14a) and their in-image twin guard (3cb21d9); `AnyObject.Type`
(9997a59); UTF-16 constant strings (89920f9); autorelease pools and
`objc_retainBlock` hidden as noise (a1200f7); `objc_opt_new` (8347f86).
Still open from that review's list: false helper results without a decoded
preservation proof, a body-entered loop losing its exit test, and the
malformed condition from reused flags. Body-proven unwritten x0/v0 transport
was fixed in `7311942`; `9479048` qualifies entry/caller x8 interpretation
by supported ABI eligibility. Actual hidden-result ownership remains open.

## Not established

- Accuracy on real applications: no ground truth exists for them here.
- Unattended use: output still needs an analyst's check.
- Safety on untrusted input beyond the mutation classes listed.
- Anything on `master`, which is an old snapshot; development is on `dev`.

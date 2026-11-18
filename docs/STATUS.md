# swiftdc status

The short, current record for anyone assessing swiftdc from outside,
including automated reviewers. It holds only what was measured, each with
its commit, its denominator and the command that reproduces it. The long
history is [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md); this page
is what to quote.

Updated 2026-11-18. Each measurement names its commit; the benchmark
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

## Latest local verification

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

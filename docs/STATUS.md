# swiftdc status

The short, current record for anyone assessing swiftdc from outside,
including automated reviewers. It holds only what was measured, each with
its commit, its denominator and the command that reproduces it. The long
history is [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md); this page
is what to quote.

Updated 2026-11-16. Each measurement names its commit; the benchmark
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
of their name. Still open from it: x8 is seeded as a possible result
buffer in every function, though the compiler passes one in 13 of 1,176;
and 30% of entries are not seeded at all.

Reproduce: `Tools/ghidra-compare/interface_oracle.py <swiftdc>
<built-corpus>`. It covers symbols the compiler emits IR for; it does not
cover results, bodies, or Objective-C methods (4 matched).

## Latest local verification

At `59db870`, the scalar FP call fixture checks **44 LLVM ABI signatures**
and **36 native observations**: 30 Swift returns with a single producer
counter update, plus six C reads checked at their proven widths. Five new
tests cover physical result views, outgoing arguments, exact scalar proofs
and call retention. All **1,810** upstream test declarations and files remain
unchanged; the enforcing suite passes **1,815 tests in 43 suites**. Fourteen
separate mutations compile and fail their targeted checks. The release
comparison below uses published `db2f822` as its baseline. Synthetic
Objective-C and async return checks do not establish a native async ABI.

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
| Enforcing test suite (a missing fixture fails) | 1,815 tests / 43 suites pass at `59db870` | `SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build`, after a fresh test build |
| Output change against `db2f822` | FPReturns corrects 24 returns and 10 outgoing arguments; 13 producer calls remain visible when wider reads decline. DroppedArgs.Onone retains one comparison call absent from its unknown return. Structured/pseudo: 62 changed lines each; listing: 68; JSON: 150. Every changed line reviewed | `Tools/blast-radius.sh` |
| Cost budget (instructions, footprint) | All 2,024 render/workload pairs positive; -0.04% retired instructions, +0.25% summed per-run peak footprint; all default budgets pass without an override. All four SDK outputs match | same, `--real --perf` |
| GitHub Actions, last inspected 2026-11-16 | Run at published `db2f822` fails at Toolchain (Swift 6.2.4, older than the required 6.4). Fixtures, Build and Enforcing suite are skipped. This is not a CI test pass | [run 43838075389](https://github.com/CamdenBopp/swiftdc/actions/runs/43838075389), [CI.md](CI.md) |
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
Still open from that review's list: an outlined helper given a false x0
result, a body-entered loop losing its exit test, and the malformed
condition from reused flags.

## Not established

- Accuracy on real applications: no ground truth exists for them here.
- Unattended use: output still needs an analyst's check.
- Safety on untrusted input beyond the mutation classes listed.
- Anything on `master`, which is an old snapshot; development is on `dev`.

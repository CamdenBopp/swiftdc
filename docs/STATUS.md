# swiftdc status

The short, current record for anyone assessing swiftdc from outside,
including automated reviewers. It holds only what was measured, each with
its commit, its denominator and the command that reproduces it. The long
history is [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md); this page
is what to quote.

Updated 2026-11-13. Each table names the commit it was measured at.

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

## Verification of the head commit

| Check | Result | Where |
|---|---|---|
| Enforcing test suite (a missing fixture fails) | 1,774 tests pass at head | local gate, `Tools/integration-gate.sh` |
| Output change against the previous commit | every changed line explained in each commit message | `Tools/blast-radius.sh` |
| Cost budget (instructions, footprint) | within budget; one fixture over, declared (`Perf-cost:` in 36ba8db) | same |
| GitHub Actions | **no passing run**. GitHub's hosted images cannot build the fixtures: `macos-26` jobs get no runner, and `macos-15` carries Swift 6.2.4. The workflow now runs on a repository's own Mac when one is registered ([CI.md](CI.md)); none is registered for this repository yet | `.github/workflows/ci.yml`, `Tools/ci/` |
| Independent execution of rendered expressions | return values of the differential-oracle fixtures, integer and floating point (compared bit for bit). Not checked by execution: which way a branch went, registers at call sites, results beyond the first register, memory writes | `DifferentialOracleTests` |

The suite, blast radius and cost budget are run by the author's gate on
one machine. Until a CI run completes they are author-reported.

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

# swiftdc against Ghidra 12.2 (2026-11-13)

How does swiftdc compare with Ghidra on Swift and Objective-C binaries? Both
decompiled the same 173 fixture builds, and every user-written function was
scored against ground truth: 2,601 function builds in twelve ABI areas.

The short answer: **swiftdc says far less, and what it says is wrong far less
often on Swift-specific code; Ghidra recovers far more, and is confidently
wrong much more often.** On plain C, Ghidra is clearly ahead, mostly because
of one swiftdc defect (C return values, below).

## Method

- **Fixtures.** The second ABI probe's fixtures
  ([abi-probe-2-2026-11-13.md](abi-probe-2-2026-11-13.md)): noncopyable
  types, property wrappers, actors, strings, collections, integer arithmetic,
  generics and parameter packs, Objective-C runtime idioms, switch lowering,
  linker transforms, globals and thread-locals, stack frames and sanitizer
  builds. Each was written for the probe, with comments stating the true
  behaviour, and built at -Onone, -O and -Osize (C at -O0, -O2, -Os, plus
  instrumented builds), pinned in `Tools/ghidra-compare/corpus/`.
- **Ghidra.** 12.2 (the newest release), headless, default analysis, with
  `GHIDRA_SWIFT_DEMANGLER` set so Swift names demangle, then every function's
  prototype and decompiled C (`Tools/ghidra-compare/DumpDecomp.java`).
- **swiftdc.** dev at 3837ea3 with the key path signatures (7602e01, before
  its x8 result input), `disasm --structured`.
- **Scoring.** Six read-only agents scored every public user-written function
  in every build against the source, its comments and `llvm-objdump`, under one
  shared rubric applied identically to both tools, on two axes:
  - *interface*: the parameters and result the tool shows. CORRECT, WRONG
    (a parameter the code does not take, one it reads missing, a value in the
    wrong register, a wrong result type or arity) or DECLINED (`?`, or a raw
    `in_x0`/`unaff_x20` register standing in for a value);
  - *body*: CORRECT (every statement, value and condition right), PARTIAL
    (right, with `?` or unresolved pieces), WRONG (anything contradicted by
    the binary, or user-visible code silently missing: a dropped call,
    argument, trap or return value) or DECLINED (nothing recovered).

  A plausible guess that is wrong is WRONG. A bare `return` in a function
  that returns a value is WRONG for both tools.

Reproduce with `Tools/ghidra-compare/compare.sh <swiftdc> <outdir>
<binaries…>`, which writes each tool's render side by side.

## Results

On the Swift-specific areas, where the two tools differ most:

| | swiftdc | Ghidra 12.2 |
|---|---|---|
| Swift areas (1,077 builds): interface wrong | 1% (11) | 12% (129) |
| Swift areas: body wrong | 14% (150) | 35% (375) |
| Swift areas: body correct | 21% | 40% |
| Swift areas: body partial or declined | 65% | 25% |
| All areas (2,601 builds): interface correct | 67% | 78% |
| All areas: interface wrong | 14% | 10% |
| All areas: body correct | 26% | 54% |
| All areas: body wrong | 23% | 30% |

Per area, as function builds, then interface (correct / wrong / declined)
and body (correct / partial / wrong / declined), Ghidra first:

| area | builds | Ghidra interface | swiftdc interface | Ghidra body | swiftdc body |
|---|---|---|---|---|---|
| noncopyable | 126 | 73 / 28 / 25 | 53 / 1 / 72 | 73 / 12 / 39 / 2 | 32 / 38 / 6 / 50 |
| property wrappers | 111 | 72 / 22 / 17 | 49 / 1 / 61 | 70 / 10 / 27 / 4 | 26 / 45 / 14 / 26 |
| actors | 191 | 72 / 21 / 98 | 133 / 6 / 52 | 77 / 71 / 43 / 0 | 30 / 114 / 18 / 29 |
| strings | 268 | 241 / 8 / 19 | 228 / 3 / 37 | 38 / 101 / 127 / 2 | 107 / 119 / 25 / 17 |
| collections | 175 | 144 / 29 / 2 | 175 / 0 / 0 | 110 / 7 / 58 / 0 | 3 / 114 / 43 / 15 |
| generics, packs | 206 | 125 / 21 / 60 | 157 / 0 / 49 | 62 / 49 / 81 / 14 | 29 / 69 / 44 / 64 |
| Objective-C runtime | 389 | 382 / 5 / 2 | 381 / 0 / 8 | 226 / 62 / 101 / 0 | 177 / 171 / 25 / 16 |
| integer arithmetic | 398 | 358 / 34 / 6 | 283 / 0 / 115 | 369 / 0 / 23 / 6 | 221 / 30 / 36 / 111 |
| switch lowering | 133 | 112 / 6 / 15 | 69 / 61 / 3 | 60 / 18 / 54 / 1 | 12 / 29 / 66 / 26 |
| linker transforms | 102 | 58 / 37 / 6 | 22 / 7 / 73 | 49 / 0 / 47 / 6 | 9 / 41 / 12 / 40 |
| globals | 153 | 141 / 8 / 4 | 101 / 20 / 32 | 103 / 34 / 15 / 1 | 23 / 76 / 24 / 30 |
| frames, sanitizers | 349 | 253 / 41 / 55 | 83 / 257 / 9 | 177 / 18 / 154 / 0 | 2 / 66 / 281 / 0 |
| **total** | **2,601** | **2031 / 260 / 309** | **1734 / 356 / 511** | **1414 / 382 / 769 / 36** | **671 / 912 / 594 / 424** |

These are recomputed from the committed per-function tables by
`Tools/ghidra-compare/tally.py Tools/ghidra-compare/scores/2026-11-13`.
The first version of this document quoted each scorer's own totals
(2,593 builds; 349 and 7 where the tables give 356 and 11 for swiftdc's
wrong interfaces overall and on Swift): the tables are the record, and a
function Ghidra did not emit counts as declined.

### Reading it

- **Swift**: swiftdc's interface is wrong on 1% of builds and Ghidra's on
  12%; its body is wrong on 14% and Ghidra's on 35%. The price is that 65%
  of swiftdc's Swift bodies are partial or declined against Ghidra's 25%,
  and Ghidra gets twice as many bodies fully right. For output an analyst
  checks, wrong is the expensive outcome; for a first read, Ghidra shows
  more.
- **Objective-C**: both get almost every interface right. Ghidra's body is
  correct more often (226 against 177) and wrong four times as often (101
  against 25).
- **C-heavy areas** (switch, globals, frames, and the C half of integer
  arithmetic): Ghidra is plainly better. One swiftdc defect, a
  value-returning C function rendered with a bare `return`, is 317 of its
  356 wrong interfaces and 277 of its 594 wrong bodies (first addressed
  in 36ba8db; not re-scored yet).
- **Overall**, swiftdc's body is fully correct on 26% of builds and
  Ghidra's on 54%. No single percentage describes swiftdc better than
  that one, and it is the number to move.

## Reproducing it

The corpus is pinned: `Tools/ghidra-compare/corpus/` holds the 70 sources,
`build.sh` builds the 173 dylibs, and `MANIFEST.tsv` records each one's
code hash (`check.sh` verifies a build against it; all 173 match on the
toolchain named there). `Tools/ghidra-compare/compare.sh <swiftdc>
<outdir>` builds and checks the corpus, renders it with both tools, and
writes `RUN.tsv`: the swiftdc binary's hash, the revision, Ghidra's
version, the toolchain and every input's hash. The rubric and the scored
tables are in `Tools/ghidra-compare/scores/2026-11-13/`. Scoring itself
is by hand (agents under `RUBRIC.md`), so a re-score is a new dated
directory, not an edit.

## What each tool gets wrong

Ghidra, confidently:

- **Swift's calling convention.** A five-word noncopyable `Big` taken by
  value in x0…x4 reads the next Int as a field; an Optional's tag register
  read as a parameter returns the searched value instead of the index
  (`firstIdx`); `self` in x20 shown as an invented by-value parameter beside
  a raw `unaff_x20`; enum payloads truncated to a byte.
- **Runtime and send arguments.** Dropped variadic arguments
  (`stringWithFormat:` loses its values), an x8 result buffer or a float put
  in the receiver slot, value-witness calls with empty argument lists,
  `print` losing its terminator.
- **`___chkstk_darwin` as returning a value**: in every large-frame function,
  the argument it preserves becomes "chkstk's result".
- **Constants as unrelated symbols** (`&MACH_HEADER.cpusubtype + 2` for an
  integer), and `@try` handlers and a `checkCancel` throw path dropped as
  unreachable.

swiftdc:

- **C return values**: a bare `return` (above), the largest single defect.
- **Leaves it does not seed**: `return ?` for `add w0, w0, #7`, because a
  struct or noncopyable parameter, or a C argument, is not in the entry state.
- **Checked arithmetic**: the overflow trap folded into `+`, and a wrapping
  `&+` rendered as the same `+`, so the two read alike (see Defects).
- **Tail calls without `return`**, a -Osize result computed before an
  outlined return helper dropped, the first segment of an -O string
  interpolation dropped, sanitizer hooks taking leftover registers, an
  invented `if (error == nil)` in a C function under ASan.

Neither tool attributed an identically-folded body to the wrong name.

## Telling examples

| function | truth | Ghidra | swiftdc |
|---|---|---|---|
| `afterInoutBig` (-O) | `big.a = k; return k + 1` | `*(param_1.a) = param_1.b; return param_1.b + 1` | `mem64[arg0] = arg1; return (arg1 + 1)` |
| `Big.plusD` (-O) | `self.d + k` | `plusD(long param_1, Big param_2) … *(unaff_x20 + 0x18) + param_1` | `return (self.d + arg0)` |
| `-[Q many:…]` (O2) | `arrayWithObjects:a,b,c,d,e,f,a,b,nil` | drops arguments | `[NSArray arrayWithObjects:arg0, …, arg1, 0]` |
| `cbig` (O2) | `sink(buf, n)` across `___chkstk_darwin` | `sink(buf, chkstk())` | `sink(local_11190, arg0)` |
| `borrowFD` (-O) | `fd + 7` | `return param_1 + 7` | `return ?` |
| `konst` (O2, C) | `return 42` | `return 0x2a` | bare `return` |
| `sumAll` (-O) | traps on overflow | `SCARRY8(…)` then the trap | the trap is gone |
| `-[Kid sum:]` (O2) | fast enumeration sum | the whole loop | `[? integerValue]`, `return ?` |

Per-function tables and more examples are in
`Tools/ghidra-compare/scores/2026-11-13/`.

## Defects this found in swiftdc

Fixed since: a value struct whose fields span both register banks (an
`Int`, a `Double` and an `Int32`) is now read from its registers, so
`Gauge.scaled()` from Ghidra issue #9741 renders its value instead of
`return ?` (the commit after this document; the scores above predate it).

Also fixed since: a value-returning C function rendered a bare `return`;
its return now carries what x0 holds as a comment (`return // x0 = 42`,
36ba8db), unless x0 is built from a call's result.

OPEN, in the tracker:

1. A C function whose x0 at return is built from a call's result still
   renders a bare `return`.
2. A checked `+` and a wrapping `&+` render the same `+`; the overflow trap is
   folded away, so neither reading is safe.
3. Leaves with an unseeded parameter decline (`return ?`).
4. Calls to in-image callees through a register, and to void runtime hooks,
   take leftover registers as arguments.
5. Tail calls without `return`; -Osize outlined return helpers dropping the
   result.
6. clang's `adr`/`ldrb` C jump tables stay `indirect_jump(?)`.

## Against Ghidra issue #9741

The five cases in [NationalSecurityAgency/ghidra#9741](https://github.com/NationalSecurityAgency/ghidra/issues/9741)
(`Engine.speed.getter`, `Engine.speed.modify`, `Gauge.scaled()`,
`Gauge.raise(by:)` and the `Gauge` type), on the issue's own source at -O:

| case | Ghidra 12.2 | swiftdc |
|---|---|---|
| `speed.getter` | extra `Engine *param_1` | `return self.speed` |
| `speed.modify` | a `double` in d0 that is never read | `yield &self.speed` |
| `scaled()` | `scaled(Gauge param_1)` (body value right, from `in_d0`) | `return (self.scale * Double(self.level))` |
| `raise(by:)` | a by-value `Gauge param_2` | `self.level = min(self.level + arg0, self.limit)` (as a select) |
| `Gauge` | 16 bytes, `limit` missing | 20 bytes, `limit: Int32` at 0x10 |

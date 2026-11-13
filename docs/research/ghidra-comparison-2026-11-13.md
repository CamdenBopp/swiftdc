# swiftdc against Ghidra 12.2 (2026-11-13)

How does swiftdc compare with Ghidra on Swift and Objective-C binaries? Both
decompiled the same 173 fixture builds, and every user-written function was
scored against ground truth: 2,593 function builds in twelve ABI areas.

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
  instrumented builds). They live in the scratchpad, not the repository.
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

Function builds scored, then interface (correct / wrong / declined) and body
(correct / partial / wrong / declined), Ghidra first.

| area | builds | Ghidra interface | swiftdc interface | Ghidra body | swiftdc body |
|---|---|---|---|---|---|
| noncopyable | 125 | 72 / 28 / 25 | 53 / 0 / 72 | 73 / 11 / 39 / 2 | 32 / 38 / 6 / 49 |
| property wrappers | 110 | 71 / 22 / 17 | 49 / 0 / 61 | 70 / 9 / 27 / 4 | 26 / 45 / 14 / 25 |
| actors | 190 | 71 / 21 / 98 | 133 / 5 / 52 | 77 / 70 / 43 / 0 | 30 / 114 / 18 / 28 |
| strings | 267 | 240 / 8 / 19 | 228 / 2 / 37 | 38 / 100 / 127 / 2 | 107 / 119 / 25 / 16 |
| collections | 175 | 144 / 29 / 2 | 175 / 0 / 0 | 110 / 7 / 58 / 0 | 3 / 114 / 43 / 15 |
| generics, packs | 206 | 125 / 21 / 60 | 157 / 0 / 49 | 62 / 49 / 81 / 14 | 29 / 69 / 44 / 64 |
| Objective-C runtime | 389 | 382 / 5 / 2 | 381 / 0 / 8 | 226 / 62 / 101 / 0 | 177 / 171 / 25 / 16 |
| integer arithmetic | 398 | 358 / 34 / 6 | 283 / 0 / 115 | 369 / 0 / 23 / 6 | 221 / 30 / 36 / 111 |
| switch lowering | 132 | 111 / 6 / 15 | 69 / 60 / 3 | 60 / 17 / 54 / 1 | 12 / 29 / 66 / 25 |
| linker transforms | 101 | 58 / 37 / 0 † | 22 / 7 / 71 | 49 / 0 / 46 / 0 † | 9 / 41 / 12 / 38 |
| globals | 151 | 139 / 8 / 4 | 101 / 18 / 32 | 103 / 32 / 15 / 1 | 23 / 76 / 24 / 28 |
| frames, sanitizers | 349 | 253 / 41 / 55 | 83 / 257 / 9 | 177 / 18 / 154 / 0 | 2 / 66 / 281 / 0 |
| **total** | **2,593** | **2,024 / 260 / 303** | **1,734 / 349 / 509** | **1,414 / 375 / 768 / 30** | **671 / 912 / 594 / 415** |

† Ghidra did not create 6 linker functions (every function that is a pure
tail jump); they are not in its counts.

### Reading it

- **Swift-specific areas** (noncopyable through generics, six areas, 1,073
  builds): Ghidra's interface is wrong 129 times, swiftdc's 7. Ghidra's body
  is wrong 375 times, swiftdc's 150. Ghidra's body is correct 430 times,
  swiftdc's 227.
- **Objective-C**: both get almost every interface right. Ghidra's body is
  correct more often (226 against 177) and wrong four times as often (101
  against 25).
- **C-heavy areas** (switch, globals, frames, and the C half of integer
  arithmetic): swiftdc's interface WRONGs (317 of its 349) and most of its
  body WRONGs come from one defect: a value-returning C function renders a
  bare `return`, which reads as void. Counted as a decline instead, swiftdc's
  interface is wrong 32 times in total, and its body WRONGs drop from 594 to
  317.

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

Per-function tables and more examples are in the scratchpad score files; the
counts above are their totals.

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

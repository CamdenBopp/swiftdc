# Synthetic corpus

Small binaries written to exercise the shapes swiftdc is least sure of, each
carrying in its source what a correct render must and must not show. A
failing directive is a found bug, not a broken test: the directives encode
the machine's behaviour, checked by hand against the plain listing, whatever
the current binary prints.

```bash
Tools/synthcorpus/build.sh                       # every area, into Tools/synthcorpus/out (git-ignored)
python3 -I Tools/synthcorpus/check.py --swiftdc .build-release/release/swiftdc
python3 -I Tools/synthcorpus/check.py --swiftdc <bin> --area loops --jobs 3
Tools/synthcorpus/mutate.py --swiftdc <bin>      # malformed mutants of the built products
```

`check.py` runs every entry point on every product and checks robustness
(exit 0, no signal, timeout or memory ceiling, no empty disassembly), two
invariants that need no oracle (each `goto loc_X` has one `loc_X:` label,
and two processes print the same `--structured` and `--pseudo`), and the
`EXPECT`/`FORBID` directives in the sources (format in its docstring).
`mutate.py` applies seeded, targeted corruption to the structures
`Tools/fuzz.swift` does not reach (LC_DYLD_INFO streams, the export trie,
LC_FUNCTION_STARTS, chained fixups, the symbol tables, Objective-C
metadata) and runs every entry point on each mutant under the memory guard.

The corpus is not part of the enforcing suite: a directive moves into a
`Fixtures/Sample` fixture and a test when its bug is fixed.

## Areas

| Area | Sources | What it covers |
|---|---|---|
| `loops` | 7 | 32-bit counters, overflow-guard shapes, labeled break/continue 3-4 deep, counters from calls and fields, compares that write their operand |
| `swiftabi` | 8 | value-type self, mutating self, more than eight parameters, aggregates direct and indirect, throws and x21, async with awaits in loops, closures, vtable and witness dispatch |
| `objc` | 8 | many-argument and variadic sends, struct returns, blocks, super sends, properties, `@try`, direct methods |
| `control` | 11 | jump tables, `ccmp` range checks, `csel`/`cset`, bit tests, signed and unsigned bounds, float compares, short circuits, goto-heavy C |
| `odd` | 12 | functions cut in two by a label, merged code, data in `__text`, padding, noreturn tails, tail calls through tables, frame fragments, unusual sp writes, x16-x18, pointer authentication, branches into another function |
| `smoke` | 1 | the harness's own example |

## Findings at creation (2026-11-12, against dev 17e6f4c)

Each line was checked by hand against the instructions; its directive is in
the named source. Fixed ones say so. After the two fixes below, dev b45a1c9
builds 226 products, 53 failing (objc 18, loops 12, control 8, swiftabi 8,
odd 7), every one on a directive: no robustness, label or determinism
failure.

- Soundness:
  - FIXED (b45a1c9): a register rewritten between its compare and the
    branch (`cmp w21, w19; add w21, w21, #3; b.lt`, `cmp w19, #2; lsr w19,
    w19, #1; b.lo`) read by its name, one step off (loops/c_counters.c,
    control/bits.c).
  - FIXED (COMMIT): direct Objective-C methods (`objc_direct`) take no
    `_cmd`, but the structured send read its first argument from x2
    (objc/direct.m).
  - x18 assumed to survive a call: `mov x18, #7; bl ext; mov x0, x18`
    rendered `return 7` (odd/scratch_regs.s).
  - `let r0 = OUTLINED_FUNCTION_2()` for a helper that never writes x0, at
    an async resume at -Osize (swiftabi/asyncs.swift).
  - An exit test dropped from a loop entered at its body, inventing an
    infinite loop (control/gotos.c `into_loop`).
  - A UInt compare against `0xfffffffffffffffa` rendered `arg0 > -6`
    (control/swiftvalues.swift `uNearMax`, -Onone).
  - `if (cond !=)` for a branch that reuses an earlier block's flags
    (control/switches.c `sw_loop`).
- Completeness:
  - FIXED (688ed4c): value-type receivers with a float word, and payload
    enums, dropped at the call site (swiftabi/valueself.swift).
  - A receiver in x20 dropped at -Onone (`Counter.bump()`), partial-apply
    forwarders' tail calls without `return`, outlined epilogues losing a
    return value at -Osize, await inside a loop without `await`.
  - Loops whose 32-bit, call-seeded or field-seeded counter is never named
    read as tests of a register nothing changes.
  - The plain listing: a stack argument dropped without `…`, a selector
    stub's `_cmd` given the caller's x1, local symbols unnamed when
    unfiltered.
  - An orphan block merged into the previous function; a branch out of the
    span to a non-start dropped; a literal pool decoded as code; noreturn
    calls joined to `return` at -O0.
- Robustness (mutate.py): MachOKit `fatalError`/`try!`/unchecked arithmetic
  or unbounded reads on a bind special ordinal of -4, opcode stream sizes
  past the end of the file, function starts that wrap below the previous,
  a zero string-table size, chained-fixup starts past their array, a huge
  import count or an import name past the pool, and a 100k-deep export trie
  (stack overflow in `interface`).

# Benchmarks: swiftdc vs ipsw

A reproducible, side-by-side comparison of swiftdc against
[blacktop/ipsw](https://github.com/blacktop/ipsw) `macho` on the three
capabilities they both implement: reconstructing Swift declarations, dumping
Objective-C headers, and disassembling ARM64. It measures wall-clock time and
captures each tool's actual output so the two can be diffed directly.

ipsw is the closest widely-used tool to swiftdc on macOS: `ipsw macho info`
parses Swift and ObjC metadata, and `ipsw macho disass` disassembles ARM64. It
is a mature, fast Go program, which makes it a demanding baseline for a young
Swift tool to sit next to.

## Running it

```bash
swift build -c release              # time the release build, not debug
Fixtures/Sample/build.sh            # build the fixture binaries (once)
brew install ipsw                   # the baseline
python3 Benchmarks/benchmark.py     # writes RESULTS.md, results.json, outputs/
```

`--quick` skips the large self binary; `--runs N` sets the timed-run count.
The harness is stdlib-only Python.

Results land in [RESULTS.md](RESULTS.md) (timing and size tables) and
`results.json` (the same data, machine-readable, with median times). The harness
also writes every tool's full output per binary and axis to `outputs/` for local
diffing; that directory is git-ignored because the whole dump is ~7 MB. A small,
curated set of those outputs is committed under [samples/](samples) so the two
tools' direct output can be read without rebuilding anything.

## The binaries

Everything in the timed matrix is reproducible by anyone who checks out the repo:

- Five fixture dylibs from `Fixtures/Sample/build.sh`: the `Reconstruction`
  module at `-Onone`, `-O`, `-O`-stripped, and with library evolution
  (resilient), plus the `Sample` dylib. These are small and their source is
  known, so output can be judged against ground truth.
- swiftdc itself, a ~30 MB real-world Swift + Objective-C Mach-O, as the
  at-scale case for the metadata axes.

System frameworks (`SwiftUI`, `Foundation`, `libswiftCore`) live in the dyld
shared cache, not on disk, and vary by OS build, so they are left out of the
committed matrix. Both tools read shared-cache images (`swiftdc dump --image`,
ipsw's cache subcommands); that comparison is not reproducible across machines
and is out of scope here.

## The axes and the exact commands

| Axis | swiftdc | ipsw |
| --- | --- | --- |
| Swift declarations | `swiftdc dump <bin>` | `ipsw macho info --swift --demangle <bin>` |
| Objective-C headers | `swiftdc objc <bin>` | `ipsw macho info --objc <bin>` |
| ARM64 disassembly | `swiftdc disasm <bin>` | `ipsw macho disass --section __TEXT.__text <bin>` |

## Fairness notes

Each tool gets its best *usable* invocation for the axis, chosen by testing, not
assumption:

- **`--demangle` on ipsw's Swift dump.** Without it, ipsw prints raw mangled
  field types (`var a: _$sSi`); with it, `var a: Int`. The flag is strictly
  better, so the benchmark uses it. swiftdc demangles by default.
- **No `--demangle` on ipsw's ObjC dump.** `ipsw macho info --objc --demangle`
  exits non-zero and prints nothing in ipsw 3.1.660, so the ObjC axis runs plain
  `--objc`, which works.
- **Release build of swiftdc.** A debug Swift build is several times slower;
  timing it against ipsw's optimized Homebrew binary would be meaningless. The
  harness prefers `.build/release/swiftdc` and records which build it used.
- **`--no-color`** on ipsw so its output is plain text, matching swiftdc's
  non-TTY output, so the two are diffable and neither pays for ANSI formatting.
- **Whole-binary disassembly of the self binary is excluded from the timed set.**
  Disassembling a ~30 MB `__text` runs for minutes on *both* tools; it is not a
  useful repeated-run measurement. The disassembly axis runs on the fixtures.

## Reading the numbers honestly

Time is wall-clock, taken as the **minimum** over several warm runs (the OS page
cache is filled by a discarded warm-up first). Minimum is the least noisy summary
for a CPU-bound tool; medians are in `results.json`.

**Line count is size, not quality.** More lines can mean more recovered detail or
just more verbose formatting. The two tools also make different soundness
choices: swiftdc's rule is *decline rather than guess*, so an unrecoverable type
renders as `unknown` or `?` rather than a plausible-looking value. What the extra
lines actually contain is the point of the next section.

## Direct output comparison

Excerpts below are verbatim from the committed [samples/](samples), taken on
`libReconstruction.dylib` (`-Onone`).

### Swift declarations

swiftdc reconstructs full member signatures and groups members by kind
([recon.swift.swiftdc.txt](samples/recon.swift.swiftdc.txt)):

```
struct Reconstruction.IntPair {
    var a: Swift.Int
    var b: Swift.Int

    /* Allocator */
    Reconstruction.IntPair.init(a: Swift.Int, b: Swift.Int) -> Reconstruction.IntPair

    /* Variable */
    Reconstruction.IntPair.a.getter : Swift.Int
    Reconstruction.IntPair.a.setter : Swift.Int
    ...
    /* Function */
    Reconstruction.IntPair.combine(Swift.Int) -> Swift.Int
}
```

ipsw lists stored properties and demangled member names, without parameter or
return types ([recon.swift.ipsw.txt](samples/recon.swift.ipsw.txt)):

```
struct Reconstruction.IntPair {
    var a: Int
    var b: Int
}
...
class Reconstruction.Counter {
  /* fields */
    var value: Int
    var step: Int
  /* methods */
    func Counter.value.getter
    func Counter.value.setter
    ...
}
```

That is where swiftdc's 547 lines against ipsw's 227 come from: full call
signatures and grouped accessors, not padding.

### ARM64 disassembly

Same function, `Reconstruction.isEqual(_:_:)`. swiftdc groups by function under a
demangled header, keeps the mangled symbol and address as a comment, and
annotates the return with a reconstructed expression
([recon.disasm-isEqual.swiftdc.txt](samples/recon.disasm-isEqual.swiftdc.txt)):

```
Reconstruction.isEqual(Swift.Int, Swift.Int) -> Swift.Bool:
  // _$s14Reconstruction7isEqualySbSi_SitF  @ 0xb80
  b80:  sub	sp, sp, #0x10
  ...
  b94:  subs	x8, x0, x1
  b98:  cset	w0, eq
  ba0:  ret  ; return (arg0 == arg1)
```

ipsw's `--section` output is a flat address / raw-bytes / instruction listing
with no function grouping or semantic annotation
([recon.disasm-isEqual.ipsw.txt](samples/recon.disasm-isEqual.ipsw.txt)):

```
0x00000b80:  ff 43 00 d1   sub	sp, sp, #0x10
...
0x00000b94:  08 00 01 eb   subs	x8, x0, x1
0x00000b98:  e0 17 9f 1a   cset	w0, eq
0x00000ba0:  c0 03 5f d6   ret
```

ipsw does resolve and annotate call targets when disassembling by symbol
(`--symbol`); the flat form above is what `--section` produces on these local
dylibs. swiftdc annotates in both modes.

### Objective-C headers

Both tools keep the Swift `@objc` class names in mangled form (`_TtC…`). They
differ on ivar types. ipsw fills them from the Swift field metadata, printed as a
mangled ref ([recon.objc.ipsw.txt](samples/recon.objc.ipsw.txt)):

```
@interface _TtC14Reconstruction7Counter : _TtCs12_SwiftObject {
    /* instance variables */
    _$sSi value;
    _$sSi step;
}
```

swiftdc currently writes `unknown` for the same ivars
([recon.objc.swiftdc.txt](samples/recon.objc.swiftdc.txt)):

```
@interface _TtC14Reconstruction7Counter : _TtCs12_SwiftObject {
    unknown value;
    unknown step;
}
```

`_$sSi` is `Swift.Int`, and it is present in the field descriptor, so this is
under-recovery by swiftdc, not a soundness decline: the type is provable and
swiftdc should render it. A real gap this benchmark surfaces.

## What the results actually say

- **swiftdc recovers more on the Swift axis.** Full member signatures and grouped
  accessors, where ipsw stops at property types and bare member names.
- **swiftdc is faster on the ObjC axis** across every binary here, including the
  large self binary, but recovers less: ipsw fills Swift ivar types that swiftdc
  leaves as `unknown` (see above).
- **swiftdc is slower, and scales worse, on the Swift axis for large binaries.**
  On the fixtures the two are within a small factor; on the ~30 MB self binary
  swiftdc takes ~13 s to ipsw's ~0.6 s. That gap is a known cost of resolving
  every member signature, and it is the clearest thing this benchmark says to fix.
- **Disassembly is a different product on each side:** swiftdc trades raw speed
  for function grouping, demangled call targets, and return-value reconstruction.


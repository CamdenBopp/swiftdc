# swiftdc — a Swift-aware Mach-O decompiler

`swiftdc` reverse-engineers compiled Swift Mach-O binaries (executables,
frameworks, dylibs) on Apple Silicon. It reconstructs **approximate Swift
declarations** from the binary's Swift metadata and produces **ARM64
disassembly annotated with demangled symbols** — including for stripped
binaries, where the type structure still survives in the `__swift5_*` sections.

This is the "Swift-aware binary browser" tier (think `class-dump` / `dsdump` /
SwiftDump, plus annotated assembly), not a full control-flow decompiler. See
[Scope & limitations](#scope--limitations).

## What it produces

- **Declarations** — `struct` / `enum` / `class` / `protocol` definitions with
  stored properties, methods, enum cases (incl. `indirect`), generics, and
  inheritance, reconstructed from Swift runtime metadata.
- **Objective-C headers** — `@interface` / `@protocol` / category declarations
  with properties and method signatures, reconstructed from ObjC runtime
  metadata. Covers the Swift+ObjC mix in real apps/frameworks (and Swift classes
  exposed to the ObjC runtime); survives stripping.
- **Annotated ARM64** — function bodies disassembled via `llvm-objdump`, with
  branch/call targets demangled to readable Swift names and string-literal
  references surfaced. `adrp`/`add` operand references are resolved to the
  target's name (`→ Rectangle.origin.getter`, `→ type descriptor for Stack`,
  or a demangled Swift symbol) — context objdump leaves bare.
- **Control-flow graph (Capstone)** — `__text` is decoded in-process by Capstone
  into structured instructions (control-flow class + branch target), so each
  function can be split into **basic blocks with successor edges** (`disasm --cfg`,
  and `blocks` in JSON).
- **Call-argument recovery (data-flow)** — a small abstract interpreter
  propagates constants and `adrp`/`add` addresses through registers via a forward
  data-flow fixpoint **across the control-flow graph** (so callee-saved values
  surviving a branch are recovered too), and snapshots the argument registers at
  each call, so calls read like
  `swift_allocObject(type descriptor for Dog, 48, 7)` instead of bare branches.
  A call's return value flows into later arguments, so nested expressions
  surface: `print(swift_allocObject(…), …)`, `Hasher._finalize(Hasher._combine())`.
  Swift `_SmallString` literals packed into register pairs are decoded back to
  text — `String.append(" the ")`, `Dog("Rex", "Lab")`.
  Surfaced inline (`args(…)`), as `arguments` in JSON, and as a **proto-pseudocode
  view** (`disasm --pseudo`) that renders each function as its recovered call
  sequence (`String.append("Woof, I am ")`), hiding ARC/runtime bookkeeping.
- **Structured control flow** (`disasm --structured`) — folds the call statements
  into `if`/`else`/`while` using post-dominators over the CFG. Conditions are
  reconstructed and back-substituted through the block (`if ((w1 & 0xff) != 1)`);
  reducible loops fold into `while (true) { … break/continue }`; trivial tails
  (lone `return`/`trap`) are duplicated so branches aren't left empty. Anything
  irreducible degrades to a labeled `goto`, so the output is never structurally
  wrong (brace-balanced by construction).
- **Stripped-binary function recovery** — when the symbol table is gone,
  function boundaries are recovered from `LC_FUNCTION_STARTS` (which survives
  stripping), and names from Swift metadata for class vtable methods and
  protocol-conformance witnesses, so a stripped binary still disassembles as
  discrete, partly-named functions instead of one blob.
- **Combined report** — declarations followed by disassembly grouped by the
  owning type.

## Requirements

- macOS on **Apple Silicon (arm64)**
- **Xcode 26 / Swift 6.3** toolchain (provides `swiftc`, `llvm-objdump`,
  `swift-demangle`)
- **Capstone** for structured decoding / CFG: `brew install capstone`
  (linked via its pkg-config file)

## Build

```bash
swift build            # debug build → .build/debug/swiftdc
swift build -c release # optimized → .build/release/swiftdc
```

## Usage

```bash
# Full report: declarations + disassembly grouped by type
swiftdc analyze /path/to/Binary

# Point straight at an app, framework, or IPA — no need to dig out the binary.
# Any subcommand accepts a Mach-O, a .app/.framework bundle, or a .ipa (unzipped
# for you). Defaults to the bundle's main executable.
swiftdc interface MyApp.app
swiftdc dump MyApp.ipa --list-binaries        # main executable + embedded frameworks/extensions
swiftdc dump MyApp.ipa --binary SomeKit       # analyze an embedded framework by name
swiftdc analyze /path/to/SomeKit.framework

# Just the reconstructed declarations
swiftdc dump /path/to/Binary
swiftdc dump /path/to/Binary --sections types,protocols
swiftdc dump /path/to/Binary --demangle simplified   # drop module prefixes

# A full Swift interface (.swiftinterface-style source: generics, extensions,
# conformances) — higher fidelity than `dump`. Also works with --image.
swiftdc interface /path/to/Binary
swiftdc interface /path/to/Binary --enum-layout --field-offsets   # + memory layout comments

# Just the reconstructed Objective-C headers
swiftdc objc /path/to/Binary

# Just annotated disassembly, optionally filtered to a function
swiftdc disasm /path/to/Binary --function distance

# Control-flow graph: basic blocks + successor edges (Capstone)
swiftdc disasm /path/to/Binary --function sum --cfg

# Proto-pseudocode: recovered call statements per function (ARC noise hidden)
swiftdc disasm /path/to/Binary --function speak --pseudo

# Structured: fold the CFG into if/else/while with recovered conditions
swiftdc disasm /path/to/Binary --function sum --structured

# Fat/universal binaries: pick a slice
swiftdc analyze /path/to/Universal --arch arm64

# System frameworks: read straight from the dyld shared cache (they have no
# standalone on-disk binary on modern macOS/iOS). --image matches by name;
# omit --cache to use the running system's cache.
swiftdc dump --image Foundation --demangle simplified
swiftdc dump --image SwiftUI --sections types
swiftdc objc --image UserNotifications
swiftdc disasm --image UserNotifications --function authorizationStatus  # in-process Capstone
swiftdc analyze --image SwiftUI                   # declarations + disassembly
swiftdc dump --list-images                       # every image path in the cache
swiftdc dump --image-path /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
swiftdc dump --image Foundation --cache /path/to/dyld_shared_cache_arm64e   # an extracted cache

# Write to a file
swiftdc analyze /path/to/Binary -o report.txt

# Structured JSON (composable with jq, diffing across builds, etc.)
swiftdc disasm  /path/to/Binary --json        # [{ name, symbol, address, source, instructions:[…] }]
swiftdc dump    /path/to/Binary --json        # [ "<declaration block>", … ]
swiftdc analyze /path/to/Binary --json        # { declarations:[…], functions:[…] }
```

Demangle presets: `default` (fully-qualified, `sample.Point`), `simplified`
(drops module/standard-library prefixes), `interface` (interface-style names).

### Example

```text
$ swiftdc dump Fixtures/Sample/sample.release --sections types --demangle simplified
struct Point {
    var x: Double
    var y: Double
    /* Function */ Point.distance(to:)
}

$ swiftdc disasm Fixtures/Sample/sample.release --function distance --demangle simplified
Point.distance(to:):
  // _$s6sample5PointV8distance2toSdAC_tF  @ 0x100001628
  100001628:  fsub  d0, d2, d0
  ...
  100001640:  ret
```

## Architecture

```
swiftdc (CLI, swift-argument-parser)
        │
        ▼
SwiftDecompilerCore (library)
  ├── BinaryLoader          load Mach-O / select fat slice          (MachOKit)
  ├── SwiftDeclarationDumper reconstruct declarations from metadata  (MachOSwiftSection / SwiftDump)
  ├── ObjCDumper            reconstruct ObjC headers                 (MachOObjCSection / ObjCDump)
  ├── Disassembler          ARM64 + demangled annotation            (llvm-objdump + Demangling)
  ├── CapstoneEngine        structured decode (control flow, targets) (Capstone, CCapstone)
  ├── CFG                   basic-block / control-flow-graph recovery
  ├── ValueTracer           abstract interpreter → call-argument recovery
  └── AnalysisReport        combined, grouped report
```

Parsing leans on [`MachOKit`](https://github.com/p-x9/MachOKit) (Mach-O
container), [`MachOSwiftSection`](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection)
(Swift `__swift5_*` metadata → typed declarations), and
[`MachOObjCSection`](https://github.com/MxIris-Reverse-Engineering/MachOObjCSection)
+ [`ObjCDump`](https://github.com/p-x9/swift-objc-dump) (ObjC `__objc_*` metadata
→ headers). Demangling uses the in-process `Demangling` library. Instruction *text* comes
from the Xcode-bundled `llvm-objdump`; [`Capstone`](https://github.com/capstone-engine/capstone)
decodes the same `__text` bytes in-process to add per-instruction control-flow
class and branch targets (basic-block / CFG recovery).

> **Dependency note:** `MachOSwiftSection` is pinned to a specific `main` commit,
> not its 0.9.1 release. 0.9.1 does not compile under Swift 6.3 (an `await` was
> missing on `Node.print()` once swift-demangling added an async overload); the
> fix is on `main`. See the comment in `Package.swift`.

## Test fixture

`Fixtures/Sample/sample.swift` is a metadata-rich program (structs, enums,
classes, protocols, generics). Build debug/release/stripped variants with:

```bash
Fixtures/Sample/build.sh
```

Run the tests (the fixture-based test self-skips if the binary isn't built):

```bash
swift test
```

## Scope & limitations

- **Apple Silicon / ARM64 only** right now (x86_64 slices load, but the
  disassembly/annotation is tuned for ARM64).
- **Not a control-flow decompiler.** Output is reconstructed *declarations* +
  *annotated assembly*, not recovered C-like function bodies. (A Ghidra backend
  for true pseudocode is a possible future direction.)
- **Stripped binaries**: function *boundaries* are recovered from
  `LC_FUNCTION_STARTS`, and *names* from Swift metadata for **class vtable
  methods** (`Type.method`) and **protocol-conformance witnesses**
  (`Type: Protocol.kind`, read from the witness table). Free functions,
  closures, thunks, and **struct/enum non-protocol methods** still render as
  `sub_<addr>` — with static dispatch they have no metadata record, so only
  their boundary is recoverable, not their name.
- Class vtable method names occasionally fall back to `sub_<addr>` even
  unstripped (a SwiftDump resolution gap); the address is still correct and
  disassemblable.
- **dyld shared cache**: `dump`, `objc`, `disasm`, and `analyze` all read a cache
  image with `--image`. `disasm`/`analyze` decode **in-process with Capstone** (no
  `llvm-objdump`, which needs a standalone file that cache images don't have); the
  loader handles the fact that a cache image's `__text` code often lives in a
  different subcache file than its header. `objc --image` on a very large
  framework (Foundation, CoreLocation) is slow — it resolves every ObjC class
  through the cache; the other subcommands are fine.
- **Apps / IPAs**: any subcommand accepts a `.app`/`.framework` bundle or a
  `.ipa` (unzipped to a temp dir) and resolves to the main executable, or an
  embedded framework via `--binary` (see `--list-binaries`). **App Store `.ipa`s
  ship their main binary FairPlay-encrypted** (`cryptid != 0`) — swiftdc detects
  this and warns, but *cannot* decrypt it; you need a decrypted dump (e.g. from a
  jailbroken device via frida-ios-dump) or an un-encrypted build. Enterprise/dev
  builds and `.app`s are unaffected.
- **x86_64**: metadata/declarations/interface work on any slice, but
  disassembly is ARM64-only.

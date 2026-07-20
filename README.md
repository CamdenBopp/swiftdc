# swiftdc — a Swift-aware Mach-O decompiler

`swiftdc` reverse-engineers compiled Swift and Objective-C Mach-O binaries
(executables, frameworks, dylibs, `.ipa`s, and dyld shared-cache images) on
Apple Silicon.

It reconstructs **Swift and Objective-C declarations** from runtime metadata,
**annotated ARM64 disassembly**, and **structured, source-level function bodies**
— `if`/`else`/`while` with conditions back-substituted to source, message sends
in bracket syntax, `self.field` reads and writes, and recovered call arguments.
Most of this survives stripping, because Swift's `__swift5_*` and ObjC's
`__objc_*` metadata do.

**Core design rule: it declines rather than guesses.** A value the analysis
cannot prove renders as `?`. There is no confidence score to second-guess — if a
name or argument appears, metadata or data flow justified it.

---

## Quickstart

```bash
brew install capstone            # required
swift build -c release           # → .build/release/swiftdc

# Point it at anything: a binary, a .app, a .framework, or an .ipa.
swiftdc analyze /path/to/Binary          # declarations + disassembly, grouped
swiftdc interface MyApp.app              # .swiftinterface-style Swift source
swiftdc objc MyApp.app --methods         # ObjC headers + recovered bodies
```

`swiftdc <path>` with no subcommand means `analyze`.

### What the output actually looks like

Reconstructed Swift declarations, from metadata alone:

```text
$ swiftdc dump Fixtures/Sample/sample.release --sections types --demangle simplified
struct Point {
    var x: Double
    var y: Double
    /* Function */ Point.distance(to:)
}
```

A recovered Objective-C body — control flow, ivars, and arguments, all named:

```text
$ swiftdc objc Fixtures/Sample/libSample.dylib --function incrementIfEnabled --structured
-[SDObjCCounter incrementIfEnabled:] {
    // - (long long)incrementIfEnabled:(long long)arg0;
    if (self->_enabled) {
        self->_count += arg0
    }
    return self->_count
}
```

Stored-property layout — the reverse index that turns `ldr x8, [x0, #0x10]` into
`self.name`, and which survives stripping completely:

```text
$ swiftdc layout Fixtures/Sample/sample.release
Dog  // instance size 48 bytes
  +0x20   16B  breed: SS

Point  // instance size 16 bytes
  +0x0    8B  x: Sd
  +0x8    8B  y: Sd
```

---

## Command reference

Every subcommand accepts a Mach-O, a fat binary, a `.app`/`.framework` bundle, or
an `.ipa` (unzipped for you), and defaults to the bundle's main executable.
Exceptions: `devices` and `apps` take no path at all.

| Subcommand | What it does |
|---|---|
| `analyze` *(default)* | Declarations + disassembly, grouped by owning type |
| `dump` | Reconstructed Swift declarations from `__swift5_*` metadata |
| `interface` | A full `.swiftinterface`-style source view — higher fidelity than `dump` |
| `objc` | Reconstructed Objective-C headers, and optionally method bodies |
| `disasm` | Annotated ARM64, with `--cfg` / `--pseudo` / `--structured` views |
| `xrefs` | Callers and callees of a function, over the recovered call graph |
| `layout` | Byte offset → Swift stored property, per type |
| `devices` | Attached iPhones/iPads |
| `apps` | Installed apps + FairPlay encryption status |

### Shared options

Available on `analyze`, `dump`, `interface`, `objc`, `disasm` (and partially on
`xrefs` / `layout` — see the notes below):

| Option | Meaning |
|---|---|
| `-a, --arch <arch>` | Pick a slice of a fat/universal binary |
| `--image <name>` | Read this image from the dyld shared cache by name |
| `--image-path <path>` | Same, but by full path in the cache |
| `--cache <path>` | Use an extracted cache file (default: the running system's) |
| `--binary <name>` | For a bundle/`.ipa`: analyze this embedded framework |
| `--list-binaries` | List the main executable + embedded frameworks and exit |
| `-o, --output <file>` | Write to a file |
| `--json` | Structured JSON (composable with `jq`, diffable across builds) |

`xrefs` supports all of the above except `--list-binaries`. `layout` supports
all except `--image-path`, `--list-binaries`, and `--demangle`. `devices`
supports only `--json` (no `-o`).

### Per-subcommand options

```bash
# dump — reconstructed Swift declarations
swiftdc dump Binary --sections types protocols     # space-separated, NOT comma
swiftdc dump Binary --demangle simplified          # default | simplified | interface
swiftdc dump --list-images                         # every image path in the cache

# interface — a full Swift interface, with optional layout annotations
swiftdc interface Binary --field-offsets --enum-layout --type-layout
swiftdc interface Binary --member-addresses --vtable-offsets --sort-by-offset
swiftdc interface Binary --show-c-imported-types
swiftdc interface Binary --opaque-return-types     # experimental

# objc — headers, bodies, structured bodies
swiftdc objc Binary                                # headers only
swiftdc objc Binary --methods                      # + every metadata-backed IMP
swiftdc objc Binary --function incrementBy --pseudo
swiftdc objc Binary --function incrementIfEnabled --structured

# disasm — four views of the same code
swiftdc disasm Binary --function distance          # annotated ARM64
swiftdc disasm Binary --function sum --cfg         # basic blocks + successor edges
swiftdc disasm Binary --function speak --pseudo    # recovered calls, ARC noise hidden
swiftdc disasm Binary --function sum --structured  # if/else/while

# layout — stored-property offsets, and the self-type index behind field naming
swiftdc layout Binary                              # every type
swiftdc layout Binary --type Dog                   # substring filter
swiftdc layout Binary --at 0x10 --bytes 8          # what lives at this offset?
swiftdc layout Binary --self-index                 # addr → type of its `self`

# xrefs — call graph queries (needs the whole image disassembled, so it is
# slower than `disasm --function`, which decodes only what matched)
swiftdc xrefs Binary --function "Circle.describe"
swiftdc xrefs App.app --function 'objc_msgSend$standardUserDefaults'
swiftdc xrefs Binary --unreferenced                # nothing statically calls these
```

`-f` is short for `--function`; `-s` for `--sections`; `-t` for `--type`.

### Devices

```bash
swiftdc devices                       # 00008120-…  USB  iPhone (iPhone15,3, iOS 27.0)
swiftdc apps                          # user apps (default)
swiftdc apps --type system            # user | system | internal | any
swiftdc apps --encrypted-only
swiftdc apps --udid 00008120-…        # required only with >1 device attached
```

```text
iPhone (iPhone15,3, iOS 27.0) — 00008120-001122AABBCCDDEE

ENC  com.example.PhotoVault  3.2.1  PhotoVault
  ·  com.example.DevSandbox  1.0    DevSandbox

2 of 2 apps — 1 FairPlay-encrypted, 1 plaintext
```

Speaks usbmux → lockdown → installation_proxy natively: **no root, no
libimobiledevice, no Python.**

### dyld shared cache

System frameworks have no standalone on-disk binary on modern macOS/iOS.
`swiftdc dump|objc|disasm|analyze|xrefs|layout --image Foundation` reads them
straight out of the cache. See [docs/dyld-shared-cache.md](docs/dyld-shared-cache.md)
for how that works and what differs there.

---

## What it recovers

### From metadata (survives stripping)

- **Swift declarations** — `struct` / `enum` / `class` / `protocol` with stored
  properties, methods, enum cases (incl. `indirect`), generics, and inheritance.
- **Objective-C headers** — `@interface` / `@protocol` / category declarations
  with properties and method signatures, covering the Swift+ObjC mix in real
  apps (and Swift classes exposed to the ObjC runtime).
- **Objective-C IMPs** — class and category method records give real function
  boundaries and conventional names (`-[Class selector:]`) even after stripping.
  Type encodings become decoded signatures; runtime ivar offsets turn direct
  loads/stores into `self->_count` / `self->_count = arg1`.
- **Function boundaries on stripped binaries** — from `LC_FUNCTION_STARTS` plus
  ObjC IMPs, so a stripped binary disassembles as discrete functions, not one blob.
- **Stored-property layout** (`swiftdc layout`) — byte offset → field, computed
  offline from `__swift5_fieldmd`, so it is runtime-exact.

### From code analysis

- **Annotated ARM64** — branch/call targets demangled, string literals surfaced,
  and `adrp`/`add` operands resolved to their target's name
  (`→ Rectangle.origin.getter`, `→ type descriptor for Stack`) — context
  `objdump` leaves bare.
- **Control-flow graph** — `__text` decoded in-process by Capstone into
  structured instructions, then split into basic blocks with successor edges.
- **Call arguments** — an abstract interpreter propagates constants and
  `adrp`/`add` addresses through registers via a forward data-flow fixpoint
  *across the CFG*, then snapshots argument registers at each call. Calls read as
  `swift_allocObject(type descriptor for Dog, 48, 7)`. Return values flow into
  later arguments, so nested expressions surface. Swift `_SmallString` literals
  packed into register pairs decode back to text: `Dog("Rex", "Lab")`.
- **Objective-C message sends** — `[[NSUserDefaults standardUserDefaults]
  setBool:0 forKey:@"…"]`. Both dispatch shapes are handled: the modern
  per-selector stub (`__objc_stubs`, Xcode 14+) and the classic materialize-into-x1
  form. Receivers resolve through GOT binds; `__cfstring` operands render as
  `@"literal"`. Without this, a real app's pseudocode is *only* ARC bookkeeping.
- **Structured control flow** — recovered calls, stores, and returns fold into
  `if`/`else`/`while` using post-dominators over the CFG. Conditions are
  back-substituted through the block; reducible loops become
  `while (true) { … break/continue }`; loop induction variables, exit-test
  rotation, and loop-carried accumulators (`total += i`) are reconstructed.
  Anything irreducible degrades to a labeled `goto`, so output is never
  structurally wrong — brace-balanced by construction.
- **Cross-references** — a call graph over resolved branch targets, including
  indirect `blr` calls whose register value provably traces to a concrete
  witness/vtable/GOT pointer slot.

### Swift field naming — the structural differentiator

`ldr x0, [x20, #0x10]` renders as `self.age`, and `add x0, x20, #0x20` as
`&self.breed`, which then flows into recovered call arguments
(`swift_beginAccess(&self.age, …)`).

This is the one thing Ghidra structurally cannot do: it needs to know what a
Swift field descriptor and a class vtable slot *mean*. It takes two
metadata-sourced halves, both strip-proof — `swiftdc layout` says what lives at
`+0x10` of a `Dog`, and `SelfTypeIndex` says the pointer in x20 *is* a Dog.
`self` arrives in x20 under the Swift calling convention, and is seeded **only**
when the receiver's type is known — never guessed.

Measured on the fixture at HEAD — 60 named field sites unstripped, 39 after
`strip -x -S` (**65% retained**). Reproduce with:

```bash
for f in Fixtures/Sample/sample.release Fixtures/Sample/sample.stripped; do
  echo "$f: $(swiftdc disasm $f | grep -oE 'self\.[A-Za-z_][A-Za-z0-9_]*' | wc -l)"
done
```

The lost third is what only the symbol could name; the remaining two-thirds come
from class vtable slots, which are metadata.

**Name collisions are handled, not fabricated.** Two distinct types with the same
simple name (a common case across modules) would otherwise let one type's layout
name the other's fields. Field maps are indexed by *qualified* name as well as
simple name: a collided simple name is dropped, and a receiver whose qualified
name is known still resolves through the qualified key. Colliding types therefore
lose naming rather than gaining a wrong name.

---

## What it cannot recover

- **Not original source.** No original local names, macros, comments, exact
  source types, arbitrary pointer aliasing, or every optimized expression. Raw
  annotated assembly remains the authoritative fallback.
- **ARM64 only.** x86_64 slices load and their metadata/declarations/interface
  work, but disassembly and annotation are ARM64-tuned.
- **Names on stripped binaries are partial.** Boundaries always recover; *names*
  come from ObjC method records and Swift metadata for class vtable methods
  (`Type.method`) and protocol-conformance witnesses (`Type: Protocol.kind`).
  Free Swift functions, closures, thunks, and **struct/enum non-protocol methods**
  render as `sub_<addr>` — statically dispatched, so they have no metadata record.
  Class vtable names occasionally fall back to `sub_<addr>` even unstripped (a
  SwiftDump resolution gap); the address is still correct and disassemblable.
- **FairPlay-encrypted `.ipa`s cannot be decrypted.** App Store `.ipa`s ship
  their main binary encrypted (`cryptid != 0`); swiftdc detects and warns, but
  you need a decrypted dump (e.g. frida-ios-dump on a jailbroken device) or an
  un-encrypted build. Enterprise/dev builds and `.app`s are unaffected.
- **Device commands enumerate only.** They do not pull binaries off the device —
  a stock iOS device does not vend other apps' bundles over any lockdown service
  (`house_arrest` reaches an app's *data* container, not its `.app`).
- **`--unreferenced` is not a dead-code proof.** Generic witness tables, unknown
  receiver vtables, and block pointers stay unresolved; `xrefs` reports their count.
- **`self` is reported conservatively.** x20 is read as `self` only for a
  Swift-mangled callee, and only when written since the previous call. A Swift
  method whose self isn't pointer-shaped (`Double.write(to:)`, self in d0) shows
  no `self` rather than a stale x20 — a deliberate false-negative-over-false-positive
  trade.
- **Stack tracking is frame-local.** Slots key off `sp`/`x29` offsets and do not
  model aliasing: a callee handed `&local` can write through it unseen, so a
  slot's value can go stale across such a call.
- **Field naming needs both halves.** A field is named only where the receiver's
  type is known AND the offset is inside that type's trusted prefix. Swift lays
  out fields in declaration order, and the first unresolvable field (a resilient
  cross-module type, an existential, an unsubstituted generic) makes every later
  offset unknown rather than merely unnamed. Static methods and allocating
  initializers hold a *metatype* in x20, not an instance — the self-index's
  `isInstance` flag refuses them.
- **`apps` infers encryption from the FairPlay `ApplicationSINF` blob**, which is
  what installation_proxy exposes; it does not read `cryptid` off the device
  (that needs the binary, which the previous point rules out). The two agree by
  construction and empirically: across 573 apps on an iOS 27 device, every App
  Store app had a SINF and every system/development-signed app had none.
  `BinaryLoader` still reads the real `cryptid` whenever it has a binary in hand.

Known rough edges in cache images (including the undiagnosed
`disasm --image SwiftUI` decode shortfall) are in
[docs/dyld-shared-cache.md](docs/dyld-shared-cache.md).

---

## Requirements & build

- macOS on **Apple Silicon (arm64)**
- **Xcode 26 / Swift 6.3** toolchain (`swiftc`, `llvm-objdump`, `swift-demangle`)
- **Capstone** — `brew install capstone` (linked via pkg-config). Required for
  structured decoding and CFG recovery.
- **OpenSSL** — `brew install openssl@3`. Only needed for `devices` / `apps`.

```bash
swift build              # debug   → .build/debug/swiftdc
swift build -c release   # release → .build/release/swiftdc
swift test               # 110 tests; fixture-based ones self-skip if unbuilt
```

`Fixtures/Sample/sample.swift` plus `sample_objc.m` form a metadata-rich program
(Swift structs/enums/classes/protocols/generics; ObjC methods, properties, ivars,
categories). Build debug/release/stripped variants with `Fixtures/Sample/build.sh`.

---

## Architecture

```
swiftdc (CLI, swift-argument-parser)
        │
        ▼
SwiftDecompilerCore (library)
  ├── BinaryLoader           load Mach-O / select fat slice          (MachOKit)
  ├── SwiftDeclarationDumper declarations from Swift metadata        (MachOSwiftSection)
  ├── ObjCDumper             ObjC headers                            (MachOObjCSection / ObjCDump)
  ├── ObjCMetadataIndex      IMP → class/category/selector/signature; ivar layouts
  ├── Disassembler           ARM64 + demangled annotation            (llvm-objdump + Demangling)
  ├── CapstoneEngine         structured decode: control flow, targets (Capstone)
  ├── CFG                    basic-block / control-flow-graph recovery
  ├── ValueTracer            abstract interpreter → args, expressions, stores, returns
  ├── TypeInference          per-value type lattice (width, signedness, enum/Optional facets)
  ├── Structurer             CFG → if/else/while/goto via post-dominators
  ├── ObjCSelectors          __objc_stubs/__objc_selrefs → selector names
  ├── FieldMap               byte offset → Swift stored property      (`swiftdc layout`)
  ├── SelfTypeIndex          impl address → the type of its `self`    (strip-proof)
  ├── CacheSymbolResolver    dyld-cache stub islands → cross-image symbols
  ├── CallGraph              caller/callee edges                      (backs `xrefs`)
  └── AnalysisReport         combined, grouped report

MobileDevice (library)       talk to physical iOS devices
  ├── DeviceSocket           AF_UNIX socket + mid-stream TLS upgrade  (OpenSSL)
  ├── UsbmuxClient           ListDevices / ReadPairRecord / Connect
  ├── LockdownClient         StartSession → TLS → StartService
  └── InstallationProxy      Browse → installed apps + FairPlay status
```

`MobileDevice` is deliberately a separate target: the decompiler proper does not
depend on OpenSSL, and `swiftdc analyze` works with no device attached.

Parsing leans on [`MachOKit`](https://github.com/p-x9/MachOKit) (Mach-O
container), [`MachOSwiftSection`](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection)
(Swift `__swift5_*` metadata → typed declarations), and
[`MachOObjCSection`](https://github.com/MxIris-Reverse-Engineering/MachOObjCSection)
+ [`ObjCDump`](https://github.com/p-x9/swift-objc-dump) (ObjC metadata → headers).
Demangling uses the in-process `Demangling` library. Instruction *text* comes from
the Xcode-bundled `llvm-objdump`; [`Capstone`](https://github.com/capstone-engine/capstone)
decodes the same `__text` bytes in-process to add per-instruction control-flow
class and branch targets.

> **Dependency note:** `MachOSwiftSection` is pinned to a specific `main` commit,
> not its 0.9.1 release. 0.9.1 does not compile under Swift 6.3 (a missing `await`
> on `Node.print()` once swift-demangling added an async overload); the fix is on
> `main`. See the comment in `Package.swift`.

---

## Design notes and research

`docs/research/` holds the engineering record — each file is a probe, a
hypothesis, and what the evidence actually showed.

| Document | Subject |
|---|---|
| [decompiler-comparison.md](docs/research/decompiler-comparison.md) | Ghidra / Malimite / LittleSwift comparison; where swiftdc wins and loses; the architectural debt list |
| [phase1-type-lattice.md](docs/research/phase1-type-lattice.md) | Per-value type lattice (width + signedness); fixed the signed/unsigned comparison defect |
| [phase2-flowing-types.md](docs/research/phase2-flowing-types.md) | Propagating types through the mid-body type-state |
| [phase3-edge-indexed-phi.md](docs/research/phase3-edge-indexed-phi.md) | Edge-indexed phi nodes at CFG merges |
| [phase4-unify-value-and-structure.md](docs/research/phase4-unify-value-and-structure.md) | Unifying the value and structure layers |
| [phase4b-loop-induction-variables.md](docs/research/phase4b-loop-induction-variables.md) | Induction variables, exit-test rotation, loop-carried accumulators |
| [computational-bodies.md](docs/research/computational-bodies.md) | Which function bodies are computationally reconstructible, and which are dependency-blocked |
| [field-map-name-collision.md](docs/research/field-map-name-collision.md) | The one confirmed *fabrication* class, and the qualified-key fix |
| [value-unknown-causes.md](docs/research/value-unknown-causes.md) | Why the tracer leaves values unknown — the coverage frontier |
| [goto-structuring.md](docs/research/goto-structuring.md) | The irreducible-CFG `goto` dimension |
| [findings-scratch.md](docs/research/findings-scratch.md) | Raw probe evidence (historical; see its status header) |

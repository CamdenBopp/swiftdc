# swiftdc

swiftdc is a decompiler for Swift and Objective-C Mach-O binaries on Apple
Silicon. It reads executables, frameworks, dylibs, `.ipa`s and images in the
dyld shared cache.

From runtime metadata it rebuilds Swift and Objective-C declarations. From the
code it produces annotated ARM64 disassembly and structured function bodies:
`if`/`else`/`while` with conditions written in terms of the source values,
message sends in bracket syntax, `self.field` reads and writes, and recovered
call arguments. Most of this survives stripping, because the `__swift5_*` and
`__objc_*` metadata it depends on survives too.

The design rule is that swiftdc declines rather than guesses. A value the
analysis can't prove prints as `?`. There's no confidence score to
second-guess: if a name or argument appears, metadata or data flow justified
it. Returns follow the same rule. `return ?` means the function returns
something swiftdc couldn't recover. A bare `return` means it returns nothing,
or that its signature wasn't recoverable enough to tell.

## Quickstart

You need an Apple Silicon Mac with Xcode 26 ([requirements](#requirements-and-build)).
Clone and build a release binary, then put it on your `PATH` for this shell:

```bash
git clone https://github.com/CamdenBopp/swiftdc.git && cd swiftdc
swift build -c release --scratch-path .build-release
export PATH="$PWD/.build-release/release:$PATH"
```

The first build fetches and compiles every dependency, so it takes a while.
Then point it at a binary, a `.app`, a `.framework` or an `.ipa`:

```bash
swiftdc analyze /path/to/Binary          # declarations and disassembly, grouped
swiftdc interface MyApp.app              # .swiftinterface-style Swift source
swiftdc objc MyApp.app --methods         # ObjC headers and recovered bodies
```

`swiftdc <path>` with no subcommand runs `analyze`.

The examples below run on the test fixtures in `Fixtures/Sample/`, which
aren't checked in. Build them with `Tools/fixtures.sh` to run the examples
yourself.

### What the output looks like

Swift declarations, rebuilt from metadata alone:

```text
$ swiftdc dump Fixtures/Sample/sample.release --sections types --demangle simplified
struct Point {
    var x: Double
    var y: Double

    /* Allocator */
    Point.init(x:y:)

    /* Variable */
    Point.x.getter
    Point.x.setter
    Point.y.getter
    Point.y.setter

    /* Function */
    Point.distance(to:)

    /* Static Function */
    static Point.__derived_struct_equals(_:_:)
}
```

An Objective-C method body, with its control flow, ivars and arguments named:

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

Stored-property layout. This is the index that turns `ldr x8, [x0, #0x10]`
into `self.name`, and stripping doesn't touch it:

```text
$ swiftdc layout Fixtures/Sample/sample.release
Dog  // instance size 48 bytes
  +0x20   16B  breed: SS

Point  // instance size 16 bytes
  +0x0    8B  x: Sd
  +0x8    8B  y: Sd
```

## Commands

Every subcommand takes a Mach-O, a fat binary, a `.app` or `.framework`
bundle, or an `.ipa` (swiftdc unzips it), and reads the bundle's main
executable unless you name another. `devices`, `apps` and `research` take no
binary path. `score` takes a binary, or a probe trace with `--trace`, plus an
independent oracle; [INSTRUMENTATION.md](docs/INSTRUMENTATION.md) covers
fixture scoring, manifest defaults and the Swift API.

| Subcommand | What it does |
|---|---|
| `analyze` *(default)* | Declarations and disassembly, grouped by owning type |
| `dump` | Swift declarations from `__swift5_*` metadata |
| `interface` | A full `.swiftinterface`-style view, more faithful than `dump` |
| `objc` | Objective-C headers, and optionally method bodies |
| `disasm` | Annotated ARM64, with `--cfg`, `--pseudo` and `--structured` views |
| `xrefs` | Callers and callees of a function, from the recovered call graph |
| `layout` | Byte offset to Swift stored property, per type |
| `swift-version` | The Swift version that built the binary, when the binary carries evidence |
| `devices` | Attached iPhones and iPads |
| `apps` | Installed apps and their FairPlay encryption status |
| `score` | Scores integer return claims against independently known values, reporting agreement and coverage separately |
| `research` | Compiles and scores a matrix of native fixtures across optimization levels, display modes and analysis modes, keeping findings and provenance |

### Shared options

`analyze`, `dump`, `interface`, `objc` and `disasm` take all of these.
`xrefs` and `layout` take most of them (see below the table).

| Option | Meaning |
|---|---|
| `-a, --arch <arch>` | Pick a slice of a fat binary |
| `--image <name>` | Read this image from the dyld shared cache, by name |
| `--image-path <path>` | The same, by its full path in the cache |
| `--cache <path>` | Use an extracted cache file instead of the running system's |
| `--binary <name>` | In a bundle or `.ipa`, analyze this embedded framework |
| `--list-binaries` | List the main executable and embedded frameworks, then exit |
| `-o, --output <file>` | Write to a file |
| `--json` | Structured JSON, for `jq` or for diffing two builds |

`xrefs` takes everything except `--list-binaries`. `layout` takes everything
except `--image-path`, `--list-binaries` and `--demangle`. `devices` takes
only `--json`, not `-o`.

### Per-subcommand options

```bash
# dump: Swift declarations
swiftdc dump Binary --sections types protocols     # space-separated, not commas
swiftdc dump Binary --demangle simplified          # default | simplified | interface
swiftdc dump --list-images                         # every image path in the cache

# interface: a full Swift interface, with optional layout annotations
swiftdc interface Binary --field-offsets --enum-layout --type-layout
swiftdc interface Binary --member-addresses --vtable-offsets --sort-by-offset
swiftdc interface Binary --show-c-imported-types
swiftdc interface Binary --opaque-return-types     # experimental

# objc: headers, bodies, structured bodies
swiftdc objc Binary                                # headers only
swiftdc objc Binary --metadata-only                # headers without reading code (below)
swiftdc objc Binary --methods                      # plus every metadata-backed IMP
swiftdc objc Binary --function incrementBy --pseudo
swiftdc objc Binary --function incrementIfEnabled --structured

# disasm: four views of the same code
swiftdc disasm Binary --function distance          # annotated ARM64
swiftdc disasm Binary --function sum --cfg         # basic blocks and successor edges
swiftdc disasm Binary --function speak --pseudo    # recovered calls, ARC noise hidden
swiftdc disasm Binary --function sum --structured  # if/else/while

# layout: stored-property offsets, and the self-type index behind field naming
swiftdc layout Binary                              # every type
swiftdc layout Binary --type Dog                   # substring filter
swiftdc layout Binary --at 0x10 --bytes 8          # what lives at this offset?
swiftdc layout Binary --self-index                 # address to the type of its `self`

# xrefs: call graph queries. It disassembles the whole image, so it's slower
# than `disasm --function`, which decodes only what matched.
swiftdc xrefs Binary --function "Circle.describe"
swiftdc xrefs App.app --function 'objc_msgSend$standardUserDefaults'
swiftdc xrefs Binary --unreferenced                # nothing calls these statically
```

`-f` is short for `--function`, `-s` for `--sections` and `-t` for `--type`.

`objc` reads each property accessor's body to decide whether it's synthesized
or custom. A synthesized accessor is implied by its `@property`, so it's
dropped; a custom one stays. `--metadata-only` reads no code, which suits an
image too large to analyze or a quick look. Without the bodies it can't tell
the two kinds apart, so it keeps every accessor and says so:

```text
@property(copy, nonatomic) NSString *name; // @synthesize name=_name

- (NSString *)name; // unclassified accessor: body not analyzed
- (void)setName:(NSString *)arg0; // unclassified accessor: body not analyzed
```

### Swift version

`swift-version` names the Swift toolchain that built a binary, but only when
the binary proves it. The version comes from the stable-ABI bits in
`__objc_imageinfo` or from a swift-tool record in `LC_BUILD_VERSION`. With
neither, it reports the ABI generation (from `__swift5_*` metadata) or
declines. It shows the SDK as context and never passes it off as the compiler
version.

```bash
swiftdc swift-version MyApp.app         # "Swift 6.4", with the evidence
swiftdc swift-version Binary --json     # confidence, version, evidence[]
swiftdc swift-version --image Foundation
```

```text
Swift 6.4
  confidence: exact
  evidence:
    - objc image-info stable-ABI version bits → 6.4
    - __swift5 reflection metadata present (11 sections): __swift5_assocty, …
  build environment (not proof of the Swift version): macOS, min OS 27.0.0, SDK 27.0.0
```

The reflection sections and image info aren't part of the symbol table, so a
stripped binary still names its Swift version.

### Devices

`devices` and `apps` talk to a USB-attached device directly. `<udid>` is a
device identifier as `devices` prints it.

```bash
swiftdc devices                       # attached devices and their UDIDs
swiftdc apps                          # user apps (default)
swiftdc apps --type system            # user | system | internal | any
swiftdc apps --encrypted-only
swiftdc apps --udid <udid>            # needed only with more than one device attached
```

Example output, with made-up bundle IDs:

```text
iPhone (iPhone15,3, iOS 27.0) — 00008120-001122AABBCCDDEE

ENC  com.example.PhotoVault  3.2.1  PhotoVault
  ·  com.example.DevSandbox  1.0    DevSandbox

2 of 2 apps — 1 FairPlay-encrypted, 1 plaintext
```

swiftdc speaks usbmux, lockdown and installation_proxy itself. It needs no
root, no libimobiledevice and no Python.

### dyld shared cache

On modern macOS and iOS, system frameworks have no standalone binary on disk.
`swiftdc dump|objc|disasm|analyze|xrefs|layout --image Foundation` reads them
straight out of the cache. [docs/dyld-shared-cache.md](docs/dyld-shared-cache.md)
explains how that works and what behaves differently there.

## What it recovers

### From metadata, which survives stripping

- **Swift declarations:** `struct`, `enum`, `class` and `protocol`, with stored
  properties, methods, enum cases (including `indirect`), generics and
  inheritance.
- **Objective-C headers:** `@interface`, `@protocol` and category declarations
  with properties and method signatures. That covers the Swift and ObjC mix in
  real apps, including Swift classes exposed to the ObjC runtime.
- **Objective-C IMPs:** class and category method records give real function
  boundaries and conventional names (`-[Class selector:]`), even after
  stripping. Type encodings become signatures, and runtime ivar offsets turn
  direct loads and stores into `self->_count` and `self->_count = arg1`.
- **Function boundaries on stripped binaries:** `LC_FUNCTION_STARTS` plus the
  ObjC IMPs split a stripped binary into separate functions instead of one blob.
- **Stored-property layout** (`swiftdc layout`): byte offset to field, computed
  offline from `__swift5_fieldmd`, so it matches the runtime exactly.

### From code analysis

- **Annotated ARM64:** branch and call targets demangled, string literals shown,
  and `adrp`/`add` operands resolved to the name of what they point at
  (`→ Rectangle.origin.getter`, `→ type descriptor for Stack`). `objdump`
  leaves all of that bare.
- **Control-flow graph:** Capstone decodes `__text` in process, and swiftdc
  splits the instructions into basic blocks with successor edges.
- **Call arguments:** an abstract interpreter carries constants and
  `adrp`/`add` addresses through registers, as a forward data-flow fixpoint
  over the whole CFG, then reads the argument registers at each call. Calls
  print as `swift_allocObject(type descriptor for Dog, 48, 7)`. Return values
  flow into later arguments, so nested expressions come out nested. Swift
  `_SmallString` literals packed into register pairs decode back to text:
  `Dog("Rex", "Lab")`.
- **Objective-C message sends:** `[[NSUserDefaults standardUserDefaults]
  setBool:0 forKey:@"…"]`. swiftdc handles both dispatch shapes, the
  per-selector stub in `__objc_stubs` (Xcode 14 and later) and the older form
  that loads the selector into x1. Receivers resolve through GOT binds, and
  `__cfstring` operands print as `@"literal"`. Without this, a real app's
  pseudocode would be little more than ARC bookkeeping.
- **Structured control flow:** recovered calls, stores and returns fold into
  `if`/`else`/`while`, using post-dominators over the CFG. Conditions are
  rewritten in terms of the block's inputs. Reducible loops become
  `while (true) { … break/continue }`, with induction variables, exit-test
  rotation and loop-carried accumulators (`total += i`) rebuilt. Anything
  irreducible falls back to a labeled `goto`, so the braces always balance and
  the structure is never wrong.
- **Explicit integer semantics:** `>>ˢ` is an arithmetic (sign-filling) right
  shift and `>>ᵁ` a logical (zero-filling) one, whatever the source parameter
  or result type was. These operators work on register bit patterns, and
  32-bit normalization stays an explicit mask. In the same way, `mulhˢ` and
  `mulhᵁ` are the high 64 bits of signed and unsigned 128-bit products.
- **Cross-references:** a call graph over resolved branch targets. It includes
  indirect `blr` calls whose register provably holds a pointer loaded from a
  specific witness table, vtable or GOT slot.

### Swift field names

`ldr x0, [x20, #0x10]` prints as `self.age`, and `add x0, x20, #0x20` as
`&self.breed`, which then shows up in recovered call arguments
(`swift_beginAccess(&self.age, …)`).

Ghidra can't do this, because it doesn't know what a Swift field descriptor
or a class vtable slot means. swiftdc needs two facts, both from metadata and
both safe from stripping. `swiftdc layout` says what lives at `+0x10` of a
`Dog`, and `SelfTypeIndex` says the pointer in x20 is a `Dog`. Under the Swift
calling convention `self` arrives in x20, and swiftdc seeds it only when it
knows the receiver's type.

On the sample fixture at 9f92995, 49 field sites are named unstripped and 33
after `strip -x`, so 67% survive. To reproduce:

```bash
for f in Fixtures/Sample/sample.release Fixtures/Sample/sample.stripped; do
  echo "$f: $(swiftdc disasm $f | grep -oE 'self\.[A-Za-z_][A-Za-z0-9_]*' | wc -l)"
done
```

The third that's lost needed the symbol to name it. The rest comes from class
vtable slots, which are metadata.

Two types can share a simple name, which happens often across modules.
Left alone, one type's layout would then name the other's fields. So field
maps are indexed by qualified name as well as simple name. A simple name that
collides is dropped, and a receiver whose qualified name is known still
resolves through the qualified key. A colliding type loses its field names
instead of getting wrong ones.

## What it can't recover

- **Original source.** You don't get local names, macros, comments, exact
  source types, arbitrary pointer aliasing, or every optimized expression.
  The annotated assembly stays the authority to fall back on.
- **Other architectures.** On an x86_64 slice, `dump`, `interface`,
  `layout`, `objc` headers and `swift-version` work from metadata. Plain
  `disasm` prints llvm-objdump's text with no analysis, `analyze` prints the
  declarations and fails, and every other view of the code refuses.
- **All names on stripped binaries.** Function boundaries come from
  LC_FUNCTION_STARTS, which survives stripping. An image linked without it has
  only its symbols, and `disasm` warns when functions may be merged. Names
  come from ObjC method records and from Swift metadata for class
  vtable methods (`Type.method`) and protocol-conformance witnesses
  (`Type: Protocol.kind`). Free functions, closures, thunks, and struct or
  enum methods that aren't protocol requirements print as `sub_<addr>`: they
  dispatch statically, so no metadata records them. A class vtable name
  sometimes falls back to `sub_<addr>` even unstripped (a SwiftDump resolution
  gap); the address is still right and still disassembles.
- **FairPlay-encrypted `.ipa`s.** App Store `.ipa`s ship their main binary
  encrypted (`cryptid != 0`). swiftdc refuses such an image instead of
  decoding ciphertext, so you need a decrypted dump (frida-ios-dump on a
  jailbroken device, for example) or an unencrypted build. Enterprise and
  development builds and plain `.app`s are fine.
- **Binaries from a device.** The device commands list what's installed but
  don't pull binaries off. A stock iOS device doesn't hand out other apps'
  bundles over any lockdown service: `house_arrest` reaches an app's data
  container, not its `.app`.
- **Proof of dead code.** `--unreferenced` leaves generic witness tables,
  vtables of unknown receivers and block pointers unresolved, and `xrefs`
  reports how many.
- **Every `self`.** swiftdc reads x20 as `self` only for a Swift-mangled
  callee, and only when x20 was written since the previous call. A Swift
  method whose `self` isn't a pointer (`Double.write(to:)`, with `self` in d0)
  shows no `self` at all rather than a stale x20. That's a deliberate choice
  of a missing answer over a wrong one.
- **Aliased stack slots.** Stack tracking keys slots by `sp` and `x29` offsets
  and doesn't model aliasing. A callee handed `&local` can write through it
  unseen, so a slot's value can go stale across that call.
- **Field names without both facts.** A field is named only when the
  receiver's type is known and the offset falls inside the part of that type's
  layout swiftdc trusts. Swift lays fields out in declaration order, so the
  first field it can't resolve (a resilient type from another module, an
  existential, an unsubstituted generic) makes every later offset unknown, not
  just unnamed. Static methods and allocating initializers hold a metatype in
  x20 rather than an instance, and the self-index's `isInstance` flag refuses
  them.
- **`cryptid` from a device.** `apps` infers encryption from the FairPlay
  `ApplicationSINF` blob, which is what installation_proxy exposes. Reading
  `cryptid` would need the binary, which the device won't give up. The two
  signals agree by construction, and on 573 apps on an iOS 27 device every
  App Store app had a SINF and every system or development-signed app had
  none. When swiftdc does have the binary, the preflight reads the real
  `cryptid`.

[docs/dyld-shared-cache.md](docs/dyld-shared-cache.md) lists the known rough
edges with cache images.

If an unfiltered run recovers far fewer functions than the binary's own
`LC_FUNCTION_STARTS` declares, swiftdc prints a coverage warning to stderr.
Treat that listing as a sample, not an inventory, and please report it.

## Requirements and build

- macOS on Apple Silicon.
- Xcode 26 with Swift 6.3, which supplies `swiftc`, `llvm-objdump` and
  `swift-demangle`.
- Capstone 6, which SwiftPM builds from source. It's the same `capstone`
  package MachOSwiftSection links, and there's nothing to install. It's the
  decoder behind CFG recovery.
- OpenSSL (`brew install openssl@3`), only for `devices` and `apps`.

```bash
swift build              # debug: .build/debug/swiftdc
swift build -c release --scratch-path .build-release   # release: .build-release/release/swiftdc
swift test               # tests that need fixtures skip when they aren't built
```

If you build both debug and release, give release its own scratch path. In a
shared `.build`, switching configurations rebuilds every dependency, which
takes about 5 minutes instead of about 1.

`Fixtures/Sample/sample.swift` and `sample_objc.m` make up a program dense with
metadata: Swift structs, enums, classes, protocols and generics, and ObjC
methods, properties, ivars and categories. `Tools/fixtures.sh` builds its
debug, release and stripped variants, along with the other fixtures, and
caches them. [CONTRIBUTING.md](CONTRIBUTING.md) covers running the tests
properly.

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

`MobileDevice` is its own target so the decompiler doesn't depend on OpenSSL,
and `swiftdc analyze` works with no device attached.

Parsing builds on [`MachOKit`](https://github.com/p-x9/MachOKit) for the
Mach-O container,
[`MachOSwiftSection`](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection)
for turning `__swift5_*` metadata into typed declarations, and
[`MachOObjCSection`](https://github.com/MxIris-Reverse-Engineering/MachOObjCSection)
with [`ObjCDump`](https://github.com/p-x9/swift-objc-dump) for ObjC headers.
Demangling uses the in-process `Demangling` library. Instruction text comes
from the `llvm-objdump` that ships with Xcode, and
[`Capstone`](https://github.com/capstone-engine/capstone) decodes the same
`__text` bytes in process to add each instruction's control-flow class and
branch target.

MachOKit is pinned to a commit on the
[CamdenBopp/MachOKit](https://github.com/CamdenBopp/MachOKit) fork. The fork
adds one change to upstream 0.55.100: it remembers that a standalone binary
isn't a dyld cache instead of re-checking on every access, which took one
measured `layout` run from 69.9 s to 4.4 s. `Package.swift` records why each
dependency is pinned where it is.

## Design notes and research

[docs/PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md) is the running
list of what stands between swiftdc and a decompiler you can trust without
checking by hand. It covers soundness, completeness, robustness, determinism,
usability, reconstruction quality and validation, each with evidence. Read it
to learn what to believe, or to find something to work on.
[CLAUDE.md](CLAUDE.md) is the working agreement, including the empty-result
rule for verifying a "nothing found" answer.

Each file in `docs/research/` records one probe: the hypothesis and what the
evidence showed.

| Document | Subject |
|---|---|
| [decompiler-comparison.md](docs/research/decompiler-comparison.md) | Ghidra, Malimite and LittleSwift compared: where swiftdc wins and loses, and the list of architectural debt |
| [phase1-type-lattice.md](docs/research/phase1-type-lattice.md) | Per-value type lattice (width and signedness), which fixed the signed/unsigned comparison defect |
| [phase2-flowing-types.md](docs/research/phase2-flowing-types.md) | Propagating types through the type state inside a body |
| [phase3-edge-indexed-phi.md](docs/research/phase3-edge-indexed-phi.md) | Edge-indexed phi nodes at CFG merges |
| [phase4-unify-value-and-structure.md](docs/research/phase4-unify-value-and-structure.md) | Unifying the value and structure layers |
| [phase4b-loop-induction-variables.md](docs/research/phase4b-loop-induction-variables.md) | Induction variables, exit-test rotation, loop-carried accumulators |
| [computational-bodies.md](docs/research/computational-bodies.md) | Which function bodies can be rebuilt from computation alone, and which are blocked on dependencies |
| [field-map-name-collision.md](docs/research/field-map-name-collision.md) | The one confirmed class of fabricated names, and the qualified-key fix |
| [value-unknown-causes.md](docs/research/value-unknown-causes.md) | Why the tracer leaves values unknown |
| [goto-structuring.md](docs/research/goto-structuring.md) | `goto` in irreducible control flow |
| [findings-scratch.md](docs/research/findings-scratch.md) | Raw probe evidence (historical; see its status header) |

## License

MIT. See [LICENSE](LICENSE).

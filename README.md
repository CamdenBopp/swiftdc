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
- **Objective-C message sends** — `objc_msgSend` calls are rendered as real
  message syntax: `[[NSUserDefaults standardUserDefaults] setBool:0 forKey:@"…"]`.
  Both dispatch shapes are handled: the modern per-selector stub (`__objc_stubs`,
  Xcode 14+), whose selector is recovered by decoding the stub body and
  dereferencing its `__objc_selrefs` slot, and the classic form where the caller
  materialises the selector into x1. Receivers are resolved through GOT binds
  (`_OBJC_CLASS_$_NSUserDefaults` → `NSUserDefaults`), and `__cfstring` operands
  render as `@"literal"`. Without this a real app's pseudocode is *only* ARC
  bookkeeping — every actual call is an unnamed branch.
- **Swift calling convention** — `self` arrives in x20, not x0, so it would
  otherwise vanish from every method call; it's surfaced as
  `String.append(self: local_30, "…")`. Reported only for Swift-mangled callees
  (x20 is an ordinary callee-saved register elsewhere) and only when freshly
  written for that call, so a stale x20 is never passed off as a receiver.
- **Stack slots** — the abstract interpreter tracks frame-relative locals
  (`str x0, [sp, #n]` … `ldr x20, [sp, #n]`) against a symbolic frame base, so
  they survive the prologue's `sub sp, sp, #k` and `stp …, [sp, #-k]!`. This is
  what lets a receiver stored and reloaded across a branch resolve instead of
  reading `?`.
- **Cross-references** (`swiftdc xrefs`) — callers and callees of a function,
  over a call graph built from resolved direct-branch targets.
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
- **Device app inventory** (`swiftdc devices`, `swiftdc apps`) — enumerate apps
  installed on an attached iPhone/iPad and report which are FairPlay-encrypted,
  so you know up front which binaries are analyzable. Speaks usbmux → lockdown →
  installation_proxy natively; **no root, no libimobiledevice, no Python**.

## Requirements

- macOS on **Apple Silicon (arm64)**
- **Xcode 26 / Swift 6.3** toolchain (provides `swiftc`, `llvm-objdump`,
  `swift-demangle`)
- **Capstone** for structured decoding / CFG: `brew install capstone`
  (linked via its pkg-config file)
- **OpenSSL** for the device commands: `brew install openssl@3` (also via
  pkg-config). Only needed for `devices` / `apps`.

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

### Cross-references

```bash
# Who calls this, and what does it call?
swiftdc xrefs /path/to/Binary --function "Circle.describe"

# Works on selector stubs too: every site that sends a given message.
swiftdc xrefs /path/to/App.app --function 'objc_msgSend$standardUserDefaults'

# Functions nothing statically calls.
swiftdc xrefs /path/to/Binary --unreferenced
swiftdc xrefs /path/to/Binary --function foo --json
```

`xrefs` needs the whole image disassembled (unlike `disasm --function`, which
decodes only what matched), so it is slower on a large binary.

### Physical devices

```bash
# Attached devices
swiftdc devices                       # 00008120-…  USB  iPhone (iPhone15,3, iOS 27.0)

# Installed apps + FairPlay status. `ENC` = encrypted, `·` = plaintext.
swiftdc apps                          # user apps (default)
swiftdc apps --type system            # or: user, system, internal, any
swiftdc apps --encrypted-only
swiftdc apps --udid 00008120-…        # required only with >1 device attached
swiftdc apps --json                   # { device: {…}, apps: [{ bundleID, encryption, sinfLength, … }] }
```

```text
iPhone (iPhone15,3, iOS 27.0) — 00008120-001122AABBCCDDEE

ENC  com.example.PhotoVault  3.2.1  PhotoVault
  ·  com.example.DevSandbox  1.0    DevSandbox

2 of 2 apps — 1 FairPlay-encrypted, 1 plaintext
```

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
  ├── ValueTracer           abstract interpreter → call args, stack slots, self
  ├── ObjCSelectors         __objc_stubs/__objc_selrefs → selector names
  ├── CacheSymbolResolver   dyld-cache stub islands → cross-image symbol names
  ├── CallGraph             caller/callee edges (backs `xrefs`)
  └── AnalysisReport        combined, grouped report

MobileDevice (library)      talk to physical iOS devices
  ├── DeviceSocket          AF_UNIX socket + mid-stream TLS upgrade   (OpenSSL, COpenSSL)
  ├── UsbmuxClient          ListDevices / ReadPairRecord / Connect
  ├── LockdownClient        StartSession → TLS → StartService
  └── InstallationProxy     Browse → installed apps + FairPlay status
```

`MobileDevice` is deliberately a separate target: the decompiler proper does not
depend on OpenSSL, and `swiftdc analyze` works with no device attached.

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
- **dyld cache images** work, but differ from standalone binaries in ways worth
  knowing (all verified against an iOS 27 host cache):

  - `__objc_stubs` and `__objc_methname` are **stripped to size 0** — the cache
    pre-binds every call (so per-selector stubs are unnecessary) and uniques
    selectors into one cache-global region. Selector recovery therefore reads
    through `FullDyldCache` and validates by selector *shape*, since there's no
    per-image `__objc_methname` to bounds-check against.
  - Call sites don't load selrefs. The builder rewrites each `adrp`+`ldr` of a
    selref into an `adrp`+`add` forming the uniqued string's address directly,
    so selectors are matched **by string address** as well as by selref slot.
  - **~78% of a cache image's calls leave the image**, via a stub island outside
    every image (`adrp x17` / `ldr x16, [x17]` / `braa x16, x17`) whose slot is
    pre-bound to the real target. `CacheSymbolResolver` follows the island and
    looks the target up in the owning image's **export trie**. This takes
    CoreLocation from 10,387/48,053 named calls to 35,719, and Contacts from
    5,831/90,300 to 66,837.
  - Cache images make almost no direct `objc_msgSend` calls (5 in Contacts, 0 in
    CoreLocation) — sends are overwhelmingly `objc_msgSendSuper2`, so bracket
    syntax there is mostly `[super …]`.

  Three traps, each of which cost real time:

  1. `MachOFile.symbols` **fatalErrors** (`numericCast` on a bogus `n_value`) on
     cache images whose `__LINKEDIT` sits in another subcache. It cannot be
     caught — hence the export trie, which is also the semantically right source
     since a cross-image call can only target an export.
  2. An image's base is its **`__TEXT` segment vmaddr**, *not*
     `address(forOffset: 0)` — that returns the whole cache's base
     (`0x180000000`), and export offsets are image-relative.
  3. The two rebase resolvers disagree: `FullDyldCache.resolveRebase` returns a
     target **VM address**, `MachOFile.resolveRebase` an **image-relative
     offset**.
- **Call graph edges are direct calls only.** Indirect dispatch (`blr` through a
  vtable, witness table, or block pointer) has no static target, so `xrefs`
  reports the unresolved count rather than implying completeness — and
  `--unreferenced` is not a dead-code proof, since entry points, exports, and
  indirectly-called functions all look unreferenced.
- **`self` is reported conservatively.** x20 is only read as `self` for a
  Swift-mangled callee, and only when written since the previous call. A Swift
  method whose self isn't pointer-shaped (`Double.write(to:)`, whose self is a
  Double in d0) therefore shows no `self` rather than the stale x20 — a
  deliberate false-negative-over-false-positive trade.
- **Stack tracking is frame-local.** Slots are keyed off `sp`/`x29` offsets and
  do not model aliasing: a callee handed `&local` can write through it, and that
  store isn't seen, so a slot's value can go stale across such a call.
- **Device commands** (`devices`, `apps`) enumerate and classify only — they do
  **not** pull binaries off the device. A stock iOS device does not vend other
  apps' bundles over any lockdown service (`house_arrest` reaches an app's *data*
  container, not its `.app`), so getting a binary to analyze still means an
  `.ipa`, a local build, or a jailbroken dump.
- **`apps` infers encryption from the FairPlay `ApplicationSINF` blob**, which is
  what installation_proxy exposes; it does not read `cryptid` off the device
  (that needs the binary, which the previous point rules out). The two agree by
  construction — SINF is the DRM record whose consequence is `cryptid != 0` —
  and agree empirically: across 573 apps on an iOS 27 device, every App Store app
  had a SINF and every system and development-signed app had none. `BinaryLoader`
  still reads the real `cryptid` whenever it has a binary in hand.
- **x86_64**: metadata/declarations/interface work on any slice, but
  disassembly is ARM64-only.

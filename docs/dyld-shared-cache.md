# Reading the dyld shared cache

On modern macOS/iOS, system frameworks have **no standalone on-disk binary** —
they exist only inside the dyld shared cache. `swiftdc` reads them directly:

```bash
swiftdc dump    --image Foundation --demangle simplified
swiftdc objc    --image UserNotifications --function authorizationStatus --pseudo
swiftdc disasm  --image UserNotifications --function authorizationStatus
swiftdc dump    --list-images                    # every image path in the cache
swiftdc dump    --image-path /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
swiftdc dump    --image Foundation --cache /path/to/dyld_shared_cache_arm64e
```

Omit `--cache` to use the running system's cache. `disasm`/`analyze` decode
cache images **in-process with Capstone** — `llvm-objdump` needs a standalone
file, which a cache image does not have. The loader also handles the fact that
an image's `__text` often lives in a *different subcache file* than its header.

All of the following was verified against an iOS 27 host cache.

## How cache images differ from standalone binaries

- **`__objc_stubs` and `__objc_methname` are stripped to size 0.** The cache
  pre-binds every call (per-selector stubs are unnecessary) and uniques
  selectors into one cache-global region. Selector recovery therefore reads
  through `FullDyldCache` and validates by selector *shape*, since there is no
  per-image `__objc_methname` to bounds-check against.
- **Call sites don't load selrefs.** The cache builder rewrites each
  `adrp`+`ldr` of a selref into an `adrp`+`add` forming the uniqued string's
  address directly, so selectors are matched **by string address** as well as by
  selref slot.
- **~78% of a cache image's calls leave the image**, via a stub island outside
  every image (`adrp x17` / `ldr x16, [x17]` / `braa x16, x17`) whose slot is
  pre-bound to the real target. `CacheSymbolResolver` follows the island and
  looks the target up in the owning image's **export trie**. This takes
  CoreLocation from 10,387/48,053 named calls to 35,719, and Contacts from
  5,831/90,300 to 66,837.
- **Cache images make almost no direct exported `objc_msgSend` calls.** Ordinary
  sends target a cache-global selector-stub pool; those entries are not exports,
  so `CacheSymbolResolver` decodes their `adrp/add x1` selector materialization
  and verifies the tail branch reaches an exported Objective-C dispatcher before
  publishing bracket syntax. Stubs are decoded by shape (`adrp/add x1` followed
  by a verified `objc_msgSend` branch), including selectors longer than 256
  bytes.

## Three traps, each of which cost real time

1. **`MachOFile.symbols` fatalErrors** (`numericCast` on a bogus `n_value`) on
   cache images whose `__LINKEDIT` sits in another subcache. It *cannot be
   caught* — hence the export trie, which is also the semantically right source,
   since a cross-image call can only target an export.
2. **An image's base is its `__TEXT` segment vmaddr**, *not*
   `address(forOffset: 0)` — that returns the whole cache's base
   (`0x180000000`), and export offsets are image-relative.
3. **The two rebase resolvers disagree.** `FullDyldCache.resolveRebase` returns
   a target **VM address**; `MachOFile.resolveRebase` returns an
   **image-relative offset**.

## Known rough edges

- `objc --image` on a very large framework (Foundation, CoreLocation) is slow —
  it resolves every ObjC class through the cache. The other subcommands are fine.
- **Fixed: `disasm --image SwiftUI` used to decode only 285 functions.** Long
  recorded here as an undiagnosed shortfall, it was a silent truncation in the
  shared Capstone decode loop, not anything cache-specific: `cs_disasm` stops at
  the first undecodable byte, and the engine called it once. Measured against
  `LC_FUNCTION_STARTS` the shortfall was 285 of 105,647 — 0.27%. Whole-image
  decoding now resynchronises past undecodable bytes: SwiftUI recovers 105,644
  of 105,647 functions (99.997%), and an unfiltered run warns on stderr whenever
  recovery falls below half of what the binary declares.

  It is correct now, but slow — a full SwiftUI run takes about six minutes.
  `--function` remains fast, since it decodes only the matched ranges.

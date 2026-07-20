# Upstream defect: negative offsets trap instead of throwing

A report ready to file against
[MachOSwiftSection](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection).
It is written up here rather than fixed in-tree because the fix belongs in the
dependency, and because forking would take swiftdc off upstream — a call for the
maintainer of this project, not a side effect of a bug hunt.

Everything below was measured locally against the pinned revision, with the
patch applied via `swift package edit` and then reverted.

## The defect

`MachOFile+Readable.swift` converts a **signed** file offset to unsigned before
any bounds check:

```swift
public func readElement<Element>(offset: Int) throws -> Element {
    var offset = offset
    var fileIO = fileIO
    if let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {   // ← traps
        offset = cacheAndFileOffset.1.cast()
        fileIO = cacheAndFileOffset.0.fileIO
    }
    return try fileIO.machO.read(offset: numericCast(offset + headerStartOffset))  // ← traps
}
```

`cast()` is `numericCast` (`MachOExtensions/BinaryInteger+.swift`). Given a
negative offset it does not return an error — it **aborts the process**:

```
Swift/Integers.swift:3422: Fatal error: Negative value is not representable
```

Offsets reach this function from relative-pointer resolution
(`RelativeDirectPointerProtocol.resolve` → `MangledName.resolve` →
`readElement`). A Swift relative pointer is a signed 32-bit delta, so a
corrupted one resolves to a negative absolute offset and the process dies.

**The bounds check already exists** — it is just on the wrong side of the
conversion. A *positive* out-of-range offset is handled correctly and cleanly:

| relative-pointer value | result |
|---|---|
| `+32767` (out of range) | `Error: offsetOutOfBounds`, exit 1 |
| `+1024` (in range) | exit 0 |
| `-1024` (in range, points backwards) | exit 0 |
| `-32767` (out of range) | **SIGTRAP** |

Note that negative offsets are *normal*: every entry of `__swift5_types` and
`__swift5_protos` in a real binary is negative, because those tables sit after
the descriptors they point at. So the fix is not "reject negative" — it is
"range-check before converting".

## Suggested fix

The library already defines the right error case
(`MachOReading/Extensions/ReadingError.swift`):

```swift
public enum ReadingError: Error {
    case invalidDataSize
    case invalidLayoutSize
    case invalidAddress(Int)   // ← this one
}
```

Adding one guard at each public read entry point in `MachOFile+Readable.swift`
is sufficient:

```swift
guard offset >= 0 else { throw ReadingError.invalidAddress(offset) }
```

Applied to the seven entry points (`readElement` ×2, `readWrapperElement`,
`readElements` ×2, `readWrapperElements`, `readString`).

## Measured impact

Fuzzing swiftdc's eight metadata-reading subcommands against byte-mutated
`__swift5_*` / `__objc_*` sections (`Tools/metadata-fuzz.py`, seeded):

| seed | mutants | before | with the guard |
|---|---|---|---|
| 1234 | 100 | 22 crashes (2.8%) | **10 (1.2%)** |
| 999 | 40 | 8 (2.5%) | **0 (0.0%)** |
| 424242 | 40 | 14 (4.4%) | **6 (1.9%)** |
| 7 | 40 | 5 (1.6%) | 5 (1.6%) |

**49 → 21 crashes, ~57%, from one guard.** No regression: every fixture and a
36 MB real binary still parse identically with the patch applied.

Seed 7 is reported unchanged rather than omitted — its crashes are entirely in
the residue below.

## What the guard does *not* fix

Two things, both distinct from the above:

1. **An unbounded string read.** `readString(offset:)` reaches `strlen` on a
   pointer into the mapped file with no length bound, so a resolved offset that
   is in-range-but-wrong walks off the mapping:
   `ObjCMethodList.indirectMethod` / `AssociatedTypeRecord.name` →
   `readString(offset:)` → `_platform_strlen` → **SIGSEGV**. This needs a length
   bound against the mapping, not a sign check.

2. **`MachOObjCSection` has the same shape and was not patched.** The surviving
   SIGTRAPs after the guard are all in `__objc_methlist` and `__objc_const`,
   which that library parses. The same one-guard change likely applies there.

## Reproducing

```bash
swift build
python3 Tools/metadata-fuzz.py Fixtures/Sample/libSample.dylib 100 1234
```

The harness is deterministic for a given (binary, mutants, seed) and exits
nonzero if any mutant kills the CLI.

To re-apply the patch locally:

```bash
swift package edit MachOSwiftSection
# add the guard to the seven entry points in
# Packages/MachOSwiftSection/Sources/MachOReading/Readable/MachOFile+Readable.swift
swift build && python3 Tools/metadata-fuzz.py Fixtures/Sample/libSample.dylib 100 1234
```

Reverting needs both steps — `swift package unedit` refuses while the working
copy is dirty, and it re-resolves the dependency to a *tag* rather than the
pinned revision, which silently rewrites `Package.resolved`:

```bash
git -C Packages/MachOSwiftSection checkout -- .
swift package unedit MachOSwiftSection
git checkout -- Package.resolved && swift package resolve   # restore the pin
```

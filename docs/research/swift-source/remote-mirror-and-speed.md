# RemoteMirror architecture and speed techniques, mined for swiftdc

Status: current as of this writing. All citations are `file:line` against the
official `swiftlang/swift` checkout at `/Users/camden/swift` (read-only, not
modified). swiftdc lives at `/Users/camden/compiler`; the "swiftdc has/lacks X"
claims below were checked against its Sources tree the same session — grep
commands are noted so they can be re-run.

## Scope

Apple's SwiftRemoteMirror stack is the closest existing analog to swiftdc: it
also parses Swift metadata and reflection records out of `__swift5_*` sections
without running Swift code, and it is used for exactly the case swiftdc cares
about — walking a big process or a dyld shared cache fast. It is built from
four layers, cited throughout:

- `include/swift/Remote/MemoryReader.h` — the abstract "read bytes at an
  address" interface.
- `include/swift/Remote/MetadataReader.h` — decodes metadata/context
  descriptors/mangled names through a `MemoryReader`.
- `include/swift/RemoteInspection/{ReflectionContext,TypeRefBuilder,Records}.h`
  and their `.cpp` bodies in `stdlib/public/RemoteInspection/` — reflection
  sections, `TypeRef` construction, and the caches that make repeat lookups
  cheap.
- `tools/swift-inspect/` — the client that drives all of the above against a
  live process (`DarwinRemoteProcess.swift`), included here only to show what
  the abstraction does *not* need to special-case.

`stdlib/public/runtime/{MetadataLookup,LibPrespecialized,ImageInspectionMachO}.cpp`
are a separate, faster in-process path (the actual Swift runtime, not the
reflection library) and are cited in §3 for the caching ideas that don't
already appear in RemoteInspection — most importantly `LibPrespecialized`,
which is the strongest "avoid scanning at all" technique in the whole tree.

## 1. The MemoryReader abstraction

`swift::remote::MemoryReader` (`include/swift/Remote/MemoryReader.h:40-49`) is
an abstract class with one method a subclass *must* implement —
`readBytes(RemoteAddress, size)` returning an owned buffer, or the
pointer+size overload — plus a handful of virtuals with default
implementations: `getSymbolAddress`, `resolveIndirectAddressAtOffset`
(`:212-216`), `resolvePointer`/`resolvePointerAsSymbol`/`getDynamicSymbol`
(`:256-289`). Everything else in the file — `readInteger` (`:157-188`),
`readObj` (`:195-202`), `readPointer` (`:291-320`) — is written once, in terms
of those primitives, as templates/inline methods on the base class.

Two concrete backends ship in-tree, and neither touches the code above them:

- `CMemoryReader` (`include/swift/Remote/CMemoryReader.h:36-108`) wraps a
  struct of C function pointers (`MemoryReaderImpl`:`24-33`) — this is the
  seam `swift-inspect` and any other out-of-process client plug into: reading
  a live task's memory is just a `readBytes` callback that shells out to
  `task_peek`/`mach_vm_read_overwrite`.
- `InProcessMemoryReader` (`include/swift/Remote/InProcessMemoryReader.h:32-108`)
  reads the *current* address space. Its `readBytes` (`:104-107`) does not
  malloc or memcpy at all — it hands back the real pointer, wrapped in a
  `ReadBytesResult` with a no-op deleter: `RemoteAddress::getLocalPointer<void>()`
  directly. Reading "remote" memory that is actually local is zero-copy by
  construction.

`MetadataReader<Runtime, BuilderType>` (`include/swift/Remote/MetadataReader.h:186-199`)
takes a `std::shared_ptr<MemoryReader>` in its constructor (`:445-448`) and
never touches concrete process/file APIs again — every subsequent read in the
14k-line file goes through `Reader->readBytes`/`readInteger`/`readPointer`.
The result: the *identical* metadata-walking code (relative-pointer
resolution, symbolic-reference demangling, field-record iteration) runs
against a live inferior process, an in-process image, or — via `CMemoryReader`
— literally any byte source an embedder wants to hand it, including a static
file on disk. Apple never wrote three metadata walkers for three sources; it
wrote one walker and three eleven-method readers.

**What swiftdc could adopt.** swiftdc currently threads `MachOFile` (an
on-disk, mmap-backed MachOKit type) directly through its metadata/field/ObjC
code (`BinaryLoader.swift`, `FieldMap.swift`, `ObjCMetadataIndex.swift`), with
a *second*, separately-written path for dyld-shared-cache images
(`CacheSymbols.swift:11-52`'s `CacheReader`, which crosses subcache files by
hand because `MachOFile.fileOffset(of:)` only reaches the header's own
subcache — see the doc comment there). A `MemoryReader`-shaped `ByteSource`
protocol (`readBytes(at:count:) -> Data?`, `readCString(at:)`,
`resolvePointer(at:)`) with two conformances — one over `MachOFile`, one over
`FullDyldCache` — would let every metadata-walking routine be written once
against the protocol instead of once per backend. This is the architectural
idea worth the most long-term payoff and the most invasive to land; see §6.

## 2. Relative pointers, symbolic references, cross-image resolution

**Relative-pointer resolution.** The base primitive is
`RemoteRef<T>::resolveRelativeAddressData` (`MetadataReader.h:123-130`): read
a 4-byte signed offset from the *local* buffer, and add it to the **remote**
address, not the local pointer —

```
RemoteAddress resolveRelativeAddressData() const {
  int32_t offset;
  memcpy(&offset, LocalBuffer, sizeof(int32_t));
  if (offset == 0) return RemoteAddress();
  return Address + (int64_t)offset;
}
```

This is the one line that makes relative pointers work identically whether
the image is loaded at its preferred address or slid: the arithmetic is done
in the *target's* address space, using the *target's* base (`Address`), even
though the bytes were read into a local scratch buffer at a completely
different host address. `resolveRelativeField` (`:2127-2128`) is the same
operation projected through a struct field via `RemoteRef::getField`
(`:117-121`, pointer-subtraction against the same local buffer to get a
byte offset, which is then re-applied to the remote address).

Direct-vs-indirect and function-vs-data pointers are distinct template
instantiations in `include/swift/Basic/RelativePointer.h`:
`RelativeDirectPointer` (`:488-526`) stores the target inline;
`RelativeIndirectablePointer` (`:234-320`) stores either the target inline or
a pointer *to* the target, distinguished by the low bit of the stored offset,
and `RelativeIndirectPointer` (`:186-232`) is always-indirect. The
function-pointer specialization of `RelativeDirectPointer::get()`
(`:540-546`) re-signs the resolved pointer with
`ptrauth_sign_unauthenticated(ptr, ptrauth_key_function_pointer, 0)` — a
different ptrauth key than a signed *data* pointer would use. This is a live,
in-process-only concern (you only sign a pointer you're about to call); for
an offline reader the equivalent fact is "which mask to strip," covered next.

**Symbolic references.** `MetadataReader::demangle` builds a
`symbolicReferenceResolver` closure (`MetadataReader.h:474-577`) that the
Swift demangler calls back into whenever it hits a symbolic-reference control
byte embedded in a mangled name. The directness split happens right there:

```cpp
if (directness == Directness::Indirect) {
  auto remoteAddress = Reader->resolveIndirectAddressAtOffset(
      offsetAddress, offset, /*directnessEncodedInOffset=*/false);
  if (auto indirectAddress = readPointer(remoteAddress))
    resolved = stripSignedPointer(*indirectAddress);
  else
    return nullptr;
} else {
  auto remoteAddress = offsetAddress + offset;
  resolved = Reader->getSymbol(remoteAddress);
}
```
(`MetadataReader.h:485-496`)

An indirect reference is a pointer *to* a pointer: resolve the offset, then
read a pointer-sized value at that address and ptrauth-strip it. A direct
reference is the target itself, resolved to a `RemoteAbsolutePointer` via
`getSymbol` — which, per §5, degrades gracefully when there is no symbol
table entry at all. The resolved address then dispatches on
`SymbolicReferenceKind` (`Context`, `AccessorFunctionReference`,
`UniqueExtendedExistentialTypeShape`, `ObjectiveCProtocol`, …,
`:498-577`) to decide what kind of node to splice into the demangle tree.

**Ptrauth stripping.** `PtrAuthMask` is queried from the target once, at
`MetadataReader` construction (`queryPtrAuthMask`, `:440-443,448`), not
hardcoded — it comes from `MemoryReader::getPtrAuthMask()`
(`MemoryReader.h:68-84`), itself cached after the first successful query.
`stripSignedPointer` (`MetadataReader.h:423-433`) then just masks:
`P & PtrAuthMask`. One mask serves every ptrauth key, because reading the raw
address back out doesn't need to *verify* the signature (which does depend on
the key and a diversifier) — it only needs to discard the signature bits,
which live in the same high-bit range regardless of key.

**Cross-image resolution in a dyld shared cache.** There is no
shared-cache-specific code anywhere in `include/swift/Remote/` or
`include/swift/RemoteInspection/` — confirmed by
`grep -rl "SharedCache\|shared_cache\|dyld_shared_cache" include/swift/Remote include/swift/RemoteInspection stdlib/public/RemoteInspection tools/swift-inspect`
returning nothing. The reason: `MemoryReader` reads through a live task port
(`DarwinRemoteProcess.read`, `tools/swift-inspect/Sources/swift-inspect/DarwinRemoteProcess.swift:94-96`,
`task_peek(task.value, address, size)`), and the OS has already mapped every
shared-cache dylib into that process's one contiguous virtual address space.
A relative pointer that crosses from one cache image into another is, from
`MemoryReader`'s point of view, exactly the same operation as a relative
pointer that stays inside one image — just an address a fixed number of bytes
away. Apple's abstraction gets cross-image resolution for free from the
*live* address space rather than solving it explicitly. The
in-process Swift **runtime**, by contrast, does special-case the shared cache
— but for a completely different reason (avoiding rescanning hundreds of
dylibs' sections; see §3's `SharedCacheSectionsToScan`), not for address
resolution.

**Symbol-based naming, ordered by cost.** `MemoryReader::readPointer`
(`:291-320`) tries `getDynamicSymbol` *before* reading memory:

```cpp
// First, try to lookup the pointer as a dynamic symbol (binding), as
// reading memory may potentially be expensive.
if (auto dynamicSymbol = getDynamicSymbol(address))
  return dynamicSymbol;
```
(`:293-296`)

Cheap metadata lookup (a binding table entry) is tried before the possibly
expensive remote read, and `getSymbol`'s default (`:277-281`) falls back to
wrapping the raw address with no name at all rather than failing — this is
the mechanism that makes symbolic-reference resolution work on a **stripped**
binary: `resolvePointerAsSymbol` returning `std::nullopt` (its default,
`:271-274`) is not an error, it just means the resulting
`RemoteAbsolutePointer` carries an address and no symbol.

## 3. Caching and laziness

This is where the speed actually comes from. Four distinct mechanisms, in
increasing order of general applicability to swiftdc:

**Per-address memoization.** `MetadataReader` carries four `DenseMap`s keyed
by `RemoteAddress` (or `(RemoteAddress, bool)`): `TypeCache`, `MetadataCache`,
`ContextDescriptorCache`, `ShapeCache` (`MetadataReader.h:235-332`), with a
custom `DenseMapInfoTypeCacheKey` (`:208-231`) for the pair key. `clear()`
(`:459-463`) drops all three when the target's memory may have changed
underneath the reader (e.g. between GC-like states in a live process — not a
concern for a static image). `ReflectionContext` has its own analogous cache,
`Cache` (`ReflectionContext.h:130-132`), keyed by `(RemoteAddress,
ExternalTypeInfoId)`, populated in `getMetadataTypeInfo`
(`:1126-1160`, look up at `:1130-1131`, insert at `:1160`) — ordinary
"compute once, remember by key" memoization, nothing exotic, but applied
everywhere a lookup could recur.

**The incremental "last-scanned-index" cache — the real O(n²) killer.**
`TypeRefBuilder` holds `ReflectionInfos`, one entry per registered image,
and needs to search across *all* of them for three different things: field
descriptors, builtin-type descriptors (keyed by normalized mangled name), and
capture descriptors (keyed by address). Doing that search from scratch on
every lookup would be O(images) work per lookup, i.e. O(images × lookups)
overall. Instead, each cache remembers how far it has scanned:

- `FieldTypeInfoCache`, guarded by a `ProcessedReflectionInfoIndexes` set —
  `populateFieldTypeInfoCacheWithReflectionAtIndex` returns immediately if
  `Index` is already processed (`stdlib/public/RemoteInspection/TypeRefBuilder.cpp:321-347`),
  and `findFieldDescriptorAtIndex` (`:356-365`) only ever populates the one
  index it needs, not the whole array.
- `NormalizedReflectionNameCacheLastReflectionInfoCache` — a plain integer
  cursor. `getBuiltinTypeInfo`'s loop is `for (;
  NormalizedReflectionNameCacheLastReflectionInfoCache < ReflectionInfos.size();
  NormalizedReflectionNameCacheLastReflectionInfoCache++)` (`:593-595`): each
  call advances the cursor over only the images added since the *previous*
  call, then does its dictionary lookup.
- `CaptureDescriptorsByAddressLastReflectionInfoCache` — identical pattern
  for capture descriptors (`:784-793`).

Total scanning work across the process's entire lifetime is O(total records
across all registered images), full stop — independent of how many times a
name gets looked up. This is the single most important scanning-strategy
fact in the whole codebase and the one most directly transplantable to
swiftdc (see §6, cheap/medium tier).

**A pluggable, persistent external cache.** `remote::ExternalTypeRefCache`
(`include/swift/Remote/ExternalTypeRefCache.h:38-71`) is an abstract
interface an embedder can hand to `TypeRefBuilder`
(`include/swift/RemoteInspection/TypeRefBuilder.h:668-670`,
constructor at `:553`) to persist the *result* of the scan above across
separate invocations. It stores a `FieldDescriptorLocator{InfoID, Offset}`
(`ExternalTypeRefCache.h:41-47`) per mangled name — cheap to serialize,
cheap to validate on read: `getFieldDescriptorFromExternalCache`
(`stdlib/public/RemoteInspection/TypeRefBuilder.cpp:367-399`) looks up the
locator, then re-parses *only that one field record* to confirm the mangled
name still matches before trusting it (`:384-393`) — a cache that can't
silently feed a stale/wrong answer even if the underlying image changed
between runs.

**TypeRef interning.** Every `TypeRef` subclass gets its own
`std::unordered_map<TypeRefID, const Id##TypeRef *>`
(`include/swift/RemoteInspection/TypeRefBuilder.h:505-508`), and every
factory goes through `FIND_OR_CREATE_TYPEREF`
(`include/swift/RemoteInspection/TypeRef.h:41-48`): compute a structural
`TypeRefID`, look it up, return the existing pointer on a hit, otherwise
build and cache. The doc comment explains why (`TypeRef.h:50-60`): "TypeRefs
should be comparable by pointers... This allows for fast identity comparisons
and substitutions" — the same AST-uniquing trick Swift's own type checker
uses for `Type`. Two occurrences of `Foundation.URL` anywhere in the same
image become the same `TypeRef*`, so anything downstream that compares types
does one pointer compare instead of a structural walk.

**Arena allocation for demangle trees.** `Demangle::NodeFactory`
(`include/swift/Demangling/Demangler.h:42-64`) bump-allocates `Node`s out of
doubling slabs (`Allocate<T>`, `:145-194`, doubling policy at `:169-171`) and
supports O(1) rollback via `Checkpoint`/`pushCheckpoint`/`popCheckpoint`
(`:271-287`, impl in `lib/Demangling/Demangler.cpp:556-566`) —
`TypeRefBuilder` wraps this in a scope guard,
`ScopedNodeFactoryCheckpoint` (`TypeRefBuilder.h:535-544`), so a demangle
performed just to answer one query can be thrown away without a single
`free()`. `NodeFactory::clear()` (`Demangler.cpp:532-554`) goes further: it
frees every slab *except* the last (biggest) one and recycles it, with the
comment "the demangling process converges to a single large slab across
repeated demangle-clear cycles" (`:545-547`) — after enough calls, demangling
a name costs zero allocator traffic. `StackAllocatedDemangler<Size>`
(`Demangler.h:755-762`) pushes this to the extreme for the hot runtime path:
`providePreallocatedMemory` seeds the arena from a stack buffer, so a
`swift_getTypeByMangledName` call in the common case (`stdlib/public/runtime/MetadataLookup.cpp:2575-2579`,
`StackAllocatedDemangler<2048>`) touches the heap **zero** times.

**LibPrespecialized: skip scanning entirely.** This is the runtime's
answer to "the shared cache has hundreds of dylibs; don't scan any of them
for a well-known SDK type." `getLibPrespecializedTypeDescriptor`
(`stdlib/public/runtime/LibPrespecialized.cpp:658-674`) and
`getMetadataFromPointerKeyedMap` (`:482-506`) consult a prebuilt hash table —
built by dyld and shipped with the shared cache, queried through
`_dyld_find_pointer_hash_table_entry` (`:486-500`, and the witness-table and
function-type-metadata variants at `:591-656`) — instead of walking any
`__swift5_types` section. `MetadataLookup.cpp`'s `_searchForContextDescriptor`
(`:851-915`) tries this table *first*, and only falls back to the linear
`_searchTypeMetadataRecordsInSections` scan (`:826-841`) over
`SharedCacheSectionsToScan` when the table says "not definitive"
(`:896-905`) — and separately maintains `SectionsToScan` vs.
`SharedCacheSectionsToScan` as two arrays (`:353-379`,
`_registerTypeMetadataRecords` routes each newly-loaded image's section into
one or the other based on `SharedCacheInfo.inSharedCache`, `:337-347,372-377`)
specifically so that a shared-cache-wide scan (when the prebuilt table
doesn't help) doesn't have to re-partition the per-image sections it already
registered. There is no static-image analog of `LibPrespecialized` to mine —
it's generated at OS build time — but the *idea*, a serialized offset-index
built once and reused across runs, is exactly what `ExternalTypeRefCache`
already generalizes for an offline reader (see §6, item 8).

**Pluggable descriptor-finder chain.** `TypeRefBuilder::getDescriptorFinders()`
(`TypeRefBuilder.h:1640-1644`) returns a small vector of abstract
`DescriptorFinder`s (`include/swift/RemoteInspection/DescriptorFinder.h:38-`),
and lookups like `getMultiPayloadEnumDescriptor`
(`stdlib/public/RemoteInspection/TypeRefBuilder.cpp:773-777`, similarly at
`:530,666`) just loop `for (auto *DF : getDescriptorFinders())` and take the
first hit. This is a first-hit-wins strategy chain: the normal
reflection-section finder is one entry, but a prespecialized/precompiled
source can be registered ahead of it with no change to call sites. It
generalizes cleanly to swiftdc: an ObjC ivar source and a Swift `__swift5_fieldmd`
source could be two finders instead of the two hand-merged code paths
`ObjCMetadataIndex.buildFieldMaps` (`Sources/SwiftDecompilerCore/ObjCMetadataIndex.swift:396-435`)
already approximates ad hoc.

## 4. Section-scanning strategy

**One read for the header, one read for all load commands.**
`readMachOSections` (`include/swift/RemoteInspection/ReflectionContext.h:255-410`)
reads `sizeof(Header)` once (`:258-261`), then reads the *entire* load-command
area in a single `readBytes(CmdStartAddress, SizeOfCommands)`
(`:273-274`) — not one read per command. `forEachSegment`
(`:281-304`) then walks that one buffer in memory, bounds-checking each
command's offset against `SizeOfCommands` *before* dereferencing
(`:286,294`) so a truncated/malformed command list stops the walk instead of
reading past the buffer. Each Swift-metadata section is then read exactly
once, at its exact size, in `findMachOSectionByName`
(`:331-350`, the `readBytes(RemoteSecStart, S->size)` at `:340-341`) — eight
sections (`fieldmd`, `assocty`, `builtin`, `capture`, `typeref`, `reflstr`,
`conform`, `mpenum`, enumerated `:353-368`), eight reads, no matter how many
records live inside them.

**Self-describing record iteration, one pass, no rescans.**
`TargetFieldDescriptor::getFieldRecordBufferEnd`
(`include/swift/RemoteInspection/Records.h:195-203`) computes the end of the
record array as `NumFields * FieldRecordSize` — an O(1) arithmetic bound, not
a scan for a terminator — and `TargetFieldRecordIterator::operator++`
(`:138-141`) just advances a pointer by the descriptor's own declared
`RecordSize`. The generic version of the same idea,
`ReflectionSection<Iterator>`/`ReflectionSectionIteratorBase`
(`include/swift/RemoteInspection/TypeRefBuilder.h:46-190`), validates every
record's self-reported stride *before* trusting it — minimum-size check
(`:107-113`), null-record check (`:114-120`), stride-fits-remaining-size
check (`:121-141`) on construction, and the identical three checks again on
every `operator++` (`:151-190`) — and degrades the whole section to empty
(`Size = 0`) rather than reading out of bounds or looping on any failure.
Combined with §3's "last-scanned-index" caches, total work is O(bytes in
every registered section), touched once, ever, regardless of query count.

**Address ownership by pre-recorded range, not re-parse.**
`readMachOSections` records each image's `__TEXT` and `__DATA`/`__AUTH`
ranges once, at `addImage` time (`textRanges.push_back`, `:394`;
`dataRanges.push_back`, `:404`), and `ownsAddress`
(`ReflectionContext.h:1076-1111`) just linearly scans those pre-recorded
ranges (`:1079-1086`) — O(images), not O(re-parse an image's load commands).
Worth noting for calibration: swiftdc's own `CacheSymbolResolver` already
does *better* than this for its own cross-image range check —
`imageIndex(containing:)`
(`/Users/camden/compiler/Sources/SwiftDecompilerCore/CacheSymbols.swift:223-231`)
binary-searches a `[(range, base, image)]` array sorted at
init (`:74-95`), which is O(log images) rather than Apple's O(images). That
one data structure is worth keeping as the template for any *new* per-image
range index swiftdc adds, rather than copying `ownsAddress`'s linear scan.

## 5. Correctness edge cases the reader handles that swiftdc should check

- **Field-record stride mismatch.** If a `FieldDescriptor`'s declared
  `FieldRecordSize` doesn't equal `sizeof(TargetFieldRecord<Runtime>)`, Apple
  treats the section as containing **zero** records rather than guessing a
  stride and walking off into whatever follows
  (`include/swift/RemoteInspection/Records.h:195-199`, comment: "consider it
  to be bad data and walk no records"). This is `swiftdc`'s own
  decline-rather-than-guess rule, independently arrived at.
- **Every reflection-section record is stride-validated before being
  trusted**, not just field records — minimum record size, non-null,
  fits-in-remaining-bytes, on both construction and every advance
  (`TypeRefBuilder.h:104-190`, cited in full in §4). A malformed section
  silently becomes an empty one instead of a crash or an OOB read.
- **Bounded reads against a corrupt/adversarial size field.**
  `MetadataReader::MaxMetadataSize = 1048576` (`MetadataReader.h:202-205`,
  "Anything larger will automatically return failure. This prevents us from
  reading absurd amounts of data when we encounter corrupt values for
  sizes/counts.") — any read whose length comes from an in-binary field is
  capped, not trusted outright.
- **Load-command bounds checking.** `forEachSegment`
  (`ReflectionContext.h:281-304`) checks `Offset + sizeof(load_command) >
  SizeOfCommands` (`:286`) and `Offset + sizeof(SegmentCmd) > SizeOfCommands`
  (`:294`) before dereferencing each command — a truncated or malformed
  `ncmds`/`sizeofcmds` pair stops the walk rather than reading past the
  buffer that was actually fetched.
- **Direct vs. indirect symbolic references need entirely different
  resolution**, not just an extra dereference: indirect means "read a
  pointer-sized value at this address, then ptrauth-strip it"
  (`MetadataReader.h:485-492`); direct means "the address itself is the
  target, run it through `getSymbol`" (`:493-496`). Conflating the two
  produces a plausible-looking but wrong address, not a crash — the
  dangerous failure mode.
- **Ptrauth mask is queried from the target, not assumed.**
  `queryPtrAuthMask` (`MetadataReader.h:440-443`) calls
  `Reader->getPtrAuthMask()`, which itself is cached only after a successful
  target query (`MemoryReader.h:68-84`) — never a hardcoded arm64e constant.
  swiftdc's own arm64e handling is delegated to its pinned `MachOSwiftSection`
  dependency, which already carries dedicated signed-value-witness-table
  handling (`.build/checkouts/MachOSwiftSection/Documentations/Evolutions/0004-arm64e-signed-vwt-pointer-hardening.md`,
  `Sources/MachOSwiftSection/Models/Misc/SpecialPointerAuthDiscriminators.swift`)
  — confirmed present this session; this is not a gap, just worth knowing
  which layer owns it so a future swiftdc-side metadata reader doesn't
  silently drop it.
- **Stripped binaries degrade gracefully, not to failure.** A direct
  symbolic reference resolves through `getSymbol`, whose default
  (`MemoryReader.h:277-281`) falls back to "the raw address, no name" when
  `resolvePointerAsSymbol` (default: `std::nullopt`, `:271-274`) finds
  nothing — the reference itself, and everything it points to, is still
  correctly resolved even with zero symbol-table entries. Symbolication is
  strictly additive on top of address resolution, never a prerequisite for
  it.

## 6. Ranked recommendations for swiftdc

Ranked by confidence (grounded in a specific cited technique) and separated
by effort. "Cheap" = local to one file, no architecture change. "Medium" =
contained refactor within one module. "Larger" = cross-cutting; per
`CLAUDE.md`, needs a nod on where it lives before writing.

**Cheap wins**

1. **Memoize `Disassembler.demangle(_:)` by mangled token string.**
   `Sources/SwiftDecompilerCore/Disassembler.swift:3232-3244` calls
   `demangleAsNode` fresh on every call with no cache — confirmed by
   `grep -n "func demangle(" Sources/SwiftDecompilerCore/Disassembler.swift`
   and reading the body. A large binary calling the same handful of runtime
   symbols (`swift_bridgeObjectRelease`, common protocol witnesses) from
   thousands of call sites re-demangles the same string thousands of times.
   Direct analog: `NormalizedReflectionNameCacheLastReflectionInfoCache`
   (`stdlib/public/RemoteInspection/TypeRefBuilder.cpp:593-609`) — cache by
   the string key, no incremental-index machinery needed for a single-image
   pass. A `[String: String?]` dictionary keyed on the raw token is enough.
2. **Validate record stride before trusting it, everywhere swiftdc hand-walks
   a `__swift5_*` section directly** (rather than through MachOSwiftSection's
   own iterators, if any such direct walk exists or gets added) — mirror
   `Records.h:195-203`'s "unexpected stride → zero records" and
   `TypeRefBuilder.h:104-190`'s min-size/fits-remaining-size checks. This is
   pure insurance against the exact defect class `CLAUDE.md`'s empty-result
   rule already targets, and costs a few bounds checks.
3. **Cap any read whose length is read from an untrusted in-binary field**
   (a record's declared size or count) at a fixed ceiling before allocating,
   mirroring `MaxMetadataSize` (`MetadataReader.h:202-205`). Cheap
   robustness hardening against a corrupted or adversarial size field
   driving an oversized allocation.

**Medium — contained refactors**

4. **Adopt the last-scanned-index pattern the moment swiftdc gets a
   multi-image or multi-invocation lookup that repeats.** Today
   `FieldMapBuilder.build` (`Sources/SwiftDecompilerCore/FieldMap.swift:251-277`)
   and `ObjCMetadataIndex.build` (`Sources/SwiftDecompilerCore/ObjCMetadataIndex.swift:112-150,327-334`)
   are single-image, one-pass — already the right shape, nothing to fix
   there. But the instant a command needs to search across *many* images
   (a whole-framework `interface` dump, or a `--cache`-wide `objc` query),
   copy the cursor pattern instead of re-scanning per query:
   `ProcessedReflectionInfoIndexes`-gated population
   (`stdlib/public/RemoteInspection/TypeRefBuilder.cpp:321-347`) or a bare
   `LastScannedIndex` integer cursor (`:593-609`, `:784-799`). This turns
   O(images × queries) into O(images + queries).
5. **Use `CacheSymbols.swift`'s binary-search range index, not
   `ReflectionContext.ownsAddress`'s linear scan, as the template for any new
   per-image address-ownership check.** swiftdc's own
   `imageIndex(containing:)` (`CacheSymbols.swift:223-231`) is already O(log
   images) against a range sorted once at init (`:74-95`) — strictly better
   than Apple's own `ownsAddress` (`ReflectionContext.h:1076-1111`, O(images)
   linear scan). No new idea needed here, just: don't regress this pattern
   when a new per-image range check gets added elsewhere.

**Larger — cross-cutting, confirm placement before writing**

6. **A `MemoryReader`-shaped `ByteSource` abstraction** (§1): one
   `readBytes(at:count:) -> Data?` / `readCString(at:)` / `resolvePointer(at:)`
   protocol, with a `MachOFile` conformance and a `FullDyldCache` conformance
   replacing the bespoke cross-subcache logic in `CacheSymbols.swift:11-52`.
   Every metadata/field/relative-pointer walk gets written once against the
   protocol. This is the highest-payoff idea in the whole document and the
   most invasive — it touches every file that currently takes a `MachOFile`
   parameter. Land it as its own change, not folded into a feature/fix, per
   `CLAUDE.md`'s "Structure" rule.
7. **A persistent, on-disk, cross-invocation cache for repeated work against
   the same large dyld shared cache**, mirroring `ExternalTypeRefCache`'s
   `{InfoID, byte-offset}` locator design (`include/swift/Remote/ExternalTypeRefCache.h:41-71`)
   with its cheap re-validate-on-read step
   (`stdlib/public/RemoteInspection/TypeRefBuilder.cpp:367-399`). Every
   swiftdc invocation today is a fresh process that reconstructs every index
   from nothing; a research session that runs `swiftdc` repeatedly against
   the same host dyld cache pays full section-scan cost every single time.
   Keying by (cache UUID or image path + mtime, mangled name) → resolved
   locator, invalidated on any mismatch, gets most of `ExternalTypeRefCache`'s
   benefit without needing anything as elaborate as `LibPrespecialized`'s
   OS-built perfect hash table (`stdlib/public/runtime/LibPrespecialized.cpp:482-506,658-674`).
8. **A bump-arena for swiftdc's demangler node trees — only if profiling
   shows it's warranted.** Apple's `NodeFactory` slab allocator with
   checkpoint/pop (`include/swift/Demangling/Demangler.h:42-64,145-194,271-287`)
   and its slab-recycling `clear()` (`lib/Demangling/Demangler.cpp:532-554`,
   "the demangling process converges to a single large slab across repeated
   demangle-clear cycles") are C++-specific memory-management tricks against
   a C++ arena allocator. swiftdc uses `swift-demangling`
   (`.build/checkouts/swift-demangling`), a separate, vendored **Swift** port
   with its own memory model (likely COW/class-based nodes, not a raw
   `malloc`'d slab) — the technique doesn't transplant 1:1, and per
   `CLAUDE.md`'s "measure before optimizing" rule this is flagged lowest-
   confidence on purpose: profile demangling allocation on a large binary
   first (`sample`/Instruments), and only chase this if it's a measured hot
   spot, not an assumed one.

## Verification notes

- Every file:line citation above was read directly from
  `/Users/camden/swift` in this session; none were taken from memory or from
  `docs/research/` notes. `/Users/camden/swift` was not modified.
- The "swiftdc lacks X" claims (no demangle memoization; no shared-cache
  address-space unification needed because it isn't a live process; no
  ptrauth handling *in swiftdc's own code*, delegated to MachOSwiftSection)
  were each checked against `/Users/camden/compiler`'s actual source with
  `grep`/`Read`, not assumed from the architecture description — see the
  specific grep commands quoted inline in §6 items 1 and the arm64e note in
  §5, and the dependency-checkout grep for `ptrauth`/`arm64e` under
  `.build/checkouts` that surfaced MachOSwiftSection's existing signed-VWT
  handling before that item was written.
- No swiftdc source was modified as part of this research.

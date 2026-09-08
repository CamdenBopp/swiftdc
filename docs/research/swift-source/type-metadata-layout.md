# Swift type-metadata and reflection layout: ground truth from the compiler source

Status: mined directly from `/Users/camden/swift` (a local `swiftlang/swift` checkout) on
2026-09-08, for swiftdc's metadata/`FieldMap` path. Every structural claim below carries a
`file:line` citation into that tree. Per the authority hierarchy in `/Users/camden/compiler/CLAUDE.md`,
this document is rank 4 (research documentation) — current swiftdc source and its tests
outrank it if they ever disagree.

**A caveat about the compiler's own docs**: `docs/ABI/TypeMetadata.rst` in the Swift tree is
stale and says so about itself — its "Nominal Type Descriptor" section opens with **"Warning:
this is all out of date!"** (`/Users/camden/swift/docs/ABI/TypeMetadata.rst:349`) and its class
metadata section still says the parent pointer is "currently always null" as a TODO
(`TypeMetadata.rst:268`), which current `Metadata.h` contradicts (`Parent` is a real, resolvable
relative-indirectable pointer, see §3/§4). Every layout fact in this document therefore comes
from the current C++ struct definitions in `include/swift/ABI/*.h` and
`include/swift/RemoteInspection/Records.h`, not from the `.rst`, with the `.rst` cited only for
corroborating narrative where it happens to still be accurate (e.g. class-layout ordering,
generic argument vector).

---

## 1. The `__swift5_*` sections

Two families of section, with different owners in the compiler:

- **Reflection sections** (field/associated-type/builtin/capture/multi-payload-enum records) are
  named by `getReflectionSectionName` in IRGen. On Mach-O the rule is literally
  `"__TEXT,__swift5_" + LongName` (`/Users/camden/swift/lib/IRGen/GenReflection.cpp:1673-1677`),
  and each section's accessor pins the long name:
  `getFieldTypeMetadataSectionName` → `"fieldmd"` (`GenReflection.cpp:1682-1686`),
  `getBuiltinTypeMetadataSectionName` → `"builtin"` (`:1688-1692`),
  `getAssociatedTypeMetadataSectionName` → `"assocty"` (`:1694-1698`),
  `getCaptureDescriptorMetadataSectionName` → `"capture"` (`:1700-1704`),
  `getReflectionStringsSectionName` → `"reflstr"` (`:1706-1710`),
  `getReflectionTypeRefSectionName` → `"typeref"` (`:1712-1716`),
  `getMultiPayloadEnumDescriptorSectionName` → `"mpenum"` (`:1718-1722`).
  The ELF `.def` table lists the same seven plus `swift5_protocol_conformances`
  (`/Users/camden/swift/include/swift/RemoteInspection/ELFReflectionSections.def:17-24`) — Mach-O
  keeps conformances in a separately-named section (next bullet).
- **Metadata/conformance sections** (`__swift5_types`, `__swift5_types2`, `__swift5_protos`,
  `__swift5_proto`) are macro'd directly for Mach-O in the runtime's image-inspection header and
  emitted at those literal section names by `IRGenModule::emit*` in `GenDecl.cpp`:
  `MachOProtocolsSection "__swift5_protos"`,
  `MachOProtocolConformancesSection "__swift5_proto"`,
  `MachOTypeMetadataRecordSection "__swift5_types"`,
  `MachOExtraTypeMetadataRecordSection "__swift5_types2"`
  (`/Users/camden/swift/stdlib/public/runtime/ImageInspectionCommon.h:26-35`), with the emission
  sites at `/Users/camden/swift/lib/IRGen/GenDecl.cpp:4483` (`__swift5_protos`), `:4630`
  (`__swift5_proto`), `:4716-4717` (`__swift5_types` / `__swift5_types2`).

| Section | Element type | Defined at | Holds |
|---|---|---|---|
| `__swift5_types` / `__swift5_types2` | `TargetTypeMetadataRecord<InProcess>` | `Metadata.h:2778-2818` | A relative, `TypeReferenceKind`-tagged reference to each nominal type's context descriptor. This is the entry list a decompiler walks to enumerate every type in the image; `swiftdc` reaches it via `machO.swift.types` (MachOSwiftSection), not by hand-walking the section. |
| `__swift5_protos` | `TargetProtocolRecord<InProcess>` | `Metadata.h:2822-2832` | One relative, int-paired reference to a `TargetProtocolDescriptor` (`Metadata.h:3381` for the descriptor itself) per protocol declared in the module. |
| `__swift5_proto` | `TargetProtocolConformanceDescriptor<InProcess>` | `Metadata.h:2874-2919`+trailing objects | Protocol → conforming-type → witness-table triples: `Protocol` (relative context pointer), `TypeRef` (`TargetTypeReference`), `WitnessTablePattern`, `ConformanceFlags`, plus trailing generic requirements / resilient witnesses. This is what `MetadataSymbolizer.witnessNames` in swiftdc reads to name witness functions (`Sources/SwiftDecompilerCore/MetadataSymbolizer.swift:61-89`). |
| `__swift5_fieldmd` | `TargetFieldDescriptor<InProcess>` + trailing `TargetFieldRecord[]` | `Records.h:189-294` (descriptor), `:85-117` (record) | **The section FieldMap is built from.** One `FieldDescriptor` per class/struct/enum/protocol, holding `Kind`, `NumFields`, `FieldRecordSize`, a mangled `Superclass` name (classes only), and a trailing array of `FieldRecord`s: each is `FieldRecordFlags` + relative pointers to a mangled type name and a field name (`Records.h:86-116`). |
| `__swift5_reflstr` | raw C strings | referenced from `Records.h:91,104,206` etc. | Field/module/type names that field/associated-type records point at via relative pointer. Not independently structured — just a string pool. |
| `__swift5_assocty` | `AssociatedTypeDescriptor` + trailing `AssociatedTypeRecord[]` | `Records.h:359-392` (descriptor), `:298-311` (record) | Per-conformance associated-type witnesses: conforming-type name, protocol name, and a list of (associated-type name → mangled substituted-type name) pairs. Not currently consumed by swiftdc. |
| `__swift5_builtin` | `BuiltinTypeDescriptor` | `Records.h:396-425` | Size/alignment/stride/extra-inhabitant-count and a bitwise-takable flag for builtin types (`Int`, pointers, etc.) referenced from other reflection records — the leaf layout facts `performBasicLayout` (§6) needs for fields whose type is itself builtin. |
| `__swift5_capture` | `CaptureDescriptor` + trailing `CaptureTypeRecord[]` / `MetadataSourceRecord[]` | `Records.h:642-689` | Closure-context layout: `NumCaptureTypes`, `NumMetadataSources`, `NumBindings`, followed by capture typerefs then metadata-source records. Not currently consumed by swiftdc (see §6 recommendations). |
| `__swift5_mpenum` | `MultiPayloadEnumDescriptor` (variable-length `uint32_t[]` after a name pointer) | `Records.h:427-537` | Spare-bit layout for fixed-size multi-payload enums: a size/flags word, then (if `usesPayloadSpareBits()`) a byte-offset/byte-count word and the mask bytes themselves (`Records.h:445-536`). The plain `FieldDescriptorKind::MultiPayloadEnum` field descriptor alone is explicitly **not enough** — Records.h's own comment says support for it is a `FIXME` (`Records.h:160-166`) and that a consumer also needs the builtin descriptor for size/alignment. |

`FieldDescriptorKind` (`Records.h:154-185`) is the tag that says which of these interpretations
applies: `Struct`, `Class`, `Enum`, `MultiPayloadEnum`, `Protocol`, `ClassProtocol`,
`ObjCProtocol`, `ObjCClass`, `COMProtocol`. `isClass()`/`isStruct()`/`isEnum()`/`isProtocol()`
(`:217-262`) are the correct way to dispatch on it — note `ObjCClass` is a *class* for this
purpose (no Swift field records are emitted; ivars come from the ObjC runtime instead, see §5).

---

## 2. Field/associated-type/capture record byte layout (`Records.h`)

**`FieldRecord`** (`Records.h:85-117`), fixed-size, `sizeof == 4 (flags) + 4 (name ptr) + 4 (type ptr) = 12` bytes on every target (relative pointers are always 32-bit, §3):

```
struct TargetFieldRecord<Runtime> {
    FieldRecordFlags Flags;                                   // uint32_t: bit0 IsIndirectCase, bit1 IsVar, bit2 IsArtificial (:32-83)
    TargetRelativeDirectPointer<Runtime, const char> MangledTypeName;  // symbolic mangled name, resolved via __swift5_reflstr / inline
    TargetRelativeDirectPointer<Runtime, const char> FieldName;        // plain C string in __swift5_reflstr
};
```

**`FieldDescriptor`** (`Records.h:189-294`) is the section-record header, followed immediately (`getFieldRecordBuffer() = this + 1`, `:191-193`) by `NumFields` `FieldRecord`s:

```
struct TargetFieldDescriptor<Runtime> {
    TargetRelativeDirectPointer<Runtime, const char> MangledTypeName;  // this type's own mangled name
    TargetRelativeDirectPointer<Runtime, const char> Superclass;       // classes only; mangled superclass name
    FieldDescriptorKind Kind;      // uint16_t
    uint16_t FieldRecordSize;      // must equal sizeof(FieldRecord); anything else is bad data (see below)
    uint32_t NumFields;
    // NumFields x FieldRecord follow immediately
};
```

The record-size guard is the compiler's own instance of swiftdc's "decline rather than guess"
rule: `getFieldRecordBufferEnd()` explicitly says *"We only ever emit FieldRecordSize equal to
sizeof(FieldRecord). If it's anything else, consider it to be bad data and walk no records"*
(`Records.h:196-203`) — i.e. the compiler's own reference reader treats a size mismatch as reason
to yield **zero** records rather than mis-stride through the buffer. Any offline reader must
replicate exactly this check before iterating, not merely `assert` it away.

**`AssociatedTypeDescriptor`** (`Records.h:359-392`): `ConformingTypeName`, `ProtocolTypeName`
(both relative, mangled), `NumAssociatedTypes`, `AssociatedTypeRecordSize`, followed by that many
**`AssociatedTypeRecord`**s (`Records.h:298-311`): `Name` (plain string) + `SubstitutedTypeName`
(mangled).

**`BuiltinTypeDescriptor`** (`Records.h:396-425`): `TypeName` (mangled), `Size`, a packed
`AlignmentAndFlags` (low 16 bits = alignment, bit 16 = bitwise-takable, `:402-416`), `Stride`,
`NumExtraInhabitants`.

**`MultiPayloadEnumDescriptor`** (`Records.h:427-537`): `TypeName` then a trailing
`uint32_t contents[]` whose word 0 packs a content-size-in-words (high 16 bits) and flags (low
16 bits, bit 0 = `usesPayloadSpareBits`, `:437-503`); when spare bits are used, word 1 packs a
byte offset (high 16) and byte count (low 16, `:505-525`), and the mask bytes follow at word 2.
Every accessor is bounds-checked against `getContentsSizeInWords()` before reading a later word
(`:506-521`) — another built-in decline-on-truncation pattern worth mirroring.

**`CaptureDescriptor`** (`Records.h:642-689`): `NumCaptureTypes`, `NumMetadataSources`,
`NumBindings`, followed by `NumCaptureTypes` **`CaptureTypeRecord`**s (`:539-552`, one mangled
type name each) then `NumMetadataSources` **`MetadataSourceRecord`**s (`:584-607`, mangled type
name + mangled metadata-source string).

---

## 3. Relative pointers: encoding and offline resolution

Everything above is glued together with 32-bit relative pointers, defined once in
`/Users/camden/swift/include/swift/Basic/RelativePointer.h` and aliased per-`Runtime` in
`/Users/camden/swift/include/swift/ABI/TargetLayout.h`. There are three distinct shapes; conflating
them is the most likely source of a wrong-address bug in an offline reader.

**Core arithmetic** (`RelativePointer.h:144-179`), used by all three:

```
address = (uintptr_t)&field + (intptr_t)offset      // sign-extended, wrapping
```

`offset` is a **signed 32-bit** value (`Offset = int32_t` is the default template parameter
everywhere in `TargetLayout.h:97-211`) added to the *field's own address* (`this`, not the start
of the enclosing record, not the section base) — `applyRelativeOffset` takes `basePtr = this`
(`RelativePointer.h:146-159`, called from `RelativeDirectPointerImpl::get` at `:445-453` with
`this` as the base). An offline tool must therefore compute, per relative-pointer field: `file
offset of the field itself` + `sign-extend(int32_t stored there)`, then translate that resulting
address back to a file offset through the same segment/section mapping — not through the
record's start, and not through a fixed "section base" that ignores per-field position.

**Three pointer kinds, by how the low bit is used:**

1. **`RelativeDirectPointer<T, Nullable, Offset=int32_t>`** — no indirection bit at all; the
   32-bit value *is* the whole offset, `0` means null when `Nullable` (`RelativePointer.h:420-453,
   488-522`). This is what every `Records.h` field/name/type-name pointer uses
   (`TargetRelativeDirectPointer` resolves to this via `TargetLayout.h:199-201` for `InProcess`).
   **Never treat the low bit specially on these** — `FieldRecord.MangledTypeName`,
   `FieldRecord.FieldName`, `TypeContextDescriptor.Name`, `TypeContextDescriptor.Fields`
   (`Metadata.h:4109, 4120-4123`) are all plain `RelativeDirectPointer`s.
2. **`RelativeIndirectablePointer<T, Nullable, Offset, IndirectType>`** — the low bit of the
   stored offset is a discriminator: clear = direct (dereference once), set = indirect
   (dereference twice, second dereference typed `IndirectType`, `RelativePointer.h:280-300`). The
   offset used to compute the address is `offsetPlusIndirect & ~1` — **mask the low bit off before
   applying the arithmetic**, then branch on it separately to decide single vs. double dereference.
   The context descriptor's **`Parent`** pointer is exactly this kind:
   `TargetRelativeContextPointer<Runtime> = RelativeIndirectablePointer<const
   TargetContextDescriptor<Runtime>, /*nullable*/true, int32_t,
   TargetSignedContextPointer<Runtime, Context>>` (`MetadataRef.h:96-103`), used at
   `TargetContextDescriptor::Parent` (`Metadata.h:3136`). This directly contradicts the stale
   `.rst` claim that the parent pointer is "currently always null" (`TypeMetadata.rst:268`) —
   current source resolves it for real, and `FieldMapBuilder.qualifiedName`'s parent-chain walk
   (`Sources/SwiftDecompilerCore/FieldMap.swift:339-366`) depends on that resolution being correct,
   indirect case included.
3. **`RelativeIndirectPointer<T, Nullable, Offset>`** — *always* indirect, no discriminator bit;
   the resolved address holds a pointer, not the value itself (`RelativePointer.h:186-229`). Used
   less often in the records above; the field/type-name/field-name pointers are not this kind.

There is also `RelativeDirectPointerIntPair<T, IntTy>` / `RelativeIndirectablePointerIntPair`,
which steal a few *more* low bits (beyond the indirect bit) to smuggle a small integer alongside
the pointer — e.g. `TargetTypeMetadataRecord`'s nominal-descriptor pointer packs a `TypeReferenceKind`
this way (`Metadata.h:2781-2793`). The mask for the extra bits is `alignof(Offset) - 1` with the
indirect bit still reserved (`RelativePointer.h:341-349, 588-598`) — do not assume "clear the low
bit" is enough for these; clear `getIntMask()`'s full mask.

**Practical resolution recipe for an offline tool** (no process, no loader): read the little-endian
`int32_t` at the field's file offset; sign-extend to 64 bits; if indirectable, mask bit 0 off
before adding and remember it for the dereference step; add to the field's *runtime address*
(image base + file offset, assuming a non-slid, statically-mapped read, which is what a Mach-O
decompiler always has); convert the resulting runtime address back to a file offset via the
segment/section table; for an indirect result, read a further pointer-sized value at that file
offset and repeat the runtime→file translation once more.

---

## 4. Nominal Type Descriptor layout

All three nominal kinds share a base, then diverge. Current struct order is authoritative over
the `.rst`'s offset numbers (which predate `hasInvertibleProtocols`, canonical-prespecialization
pointers, etc. and are marked stale anyway, `TypeMetadata.rst:349`).

### 4.1 `TargetContextDescriptor<Runtime>` (base of every context, not just types)

`Metadata.h:3129-3201`:

```
struct TargetContextDescriptor<Runtime> {
    ContextDescriptorFlags Flags;                 // uint32_t, see below
    TargetRelativeContextPointer<Runtime> Parent;  // relative-indirectable, nullable
};
```

`ContextDescriptorFlags` (`MetadataValues.h:1883-1963`) packs into one `uint32_t`:

| Bits | Meaning | Accessor |
|---|---|---|
| 0-4 | `ContextDescriptorKind` | `getKind()` (`:1907-1909`) |
| 5 | `hasInvertibleProtocols` | `:1923-1925` |
| 6 | `isUnique` | `:1917-1919` |
| 7 | `isGeneric` | `:1912-1914` |
| 8-15 | reserved | — |
| 16-31 | kind-specific flags (16 bits) | `getKindSpecificFlags()` (`:1929-1931`) |

`ContextDescriptorKind` (`MetadataValues.h:1849-1880`): `Module=0`, `Extension=1`, `Anonymous=2`,
`Protocol=3`, `OpaqueType=4`, then `Type_First=16` through `Type_Last=31` with `Class=16`,
`Struct=17`, `Enum=18`. The `Type_First..Type_Last` band is exactly what
`TargetTypeContextDescriptor::classof` tests (`Metadata.h:4213-4216`) — a fast, ABI-guaranteed way
to answer "is this a nominal type context" without a big switch.

### 4.2 `TargetTypeContextDescriptor<Runtime>` — common to class/struct/enum

`Metadata.h:4105-4217` (exact struct-name line is `4106`), fields **in declared order**
immediately after the `TargetContextDescriptor` base:

```
struct TargetTypeContextDescriptor<Runtime> : TargetContextDescriptor<Runtime> {
    TargetRelativeDirectPointer<Runtime, const char> Name;                    // :4109, never null
    TargetCompactFunctionPointer<...> AccessFunctionPtr;                      // :4116-4117, nullable
    TargetRelativeDirectPointer<Runtime, const FieldDescriptor> Fields;       // :4120-4123, nullable — the __swift5_fieldmd pointer
};
```

`isReflectable() == (bool)Fields` (`:4125`) — a type with no field descriptor (e.g. an
`@objc`-imported class with no Swift field records, or a stripped-of-reflection build) has `Fields
== null`, which is a legitimate **empty** result, not a parse failure; swiftdc's builder already
treats "no descriptor" as a skip (`FieldMapBuilder.build`, `Sources/SwiftDecompilerCore/FieldMap.swift:255-263`
guards on `contextDescriptor(of:)` returning non-nil, and layout emptiness via `!layout.fields.isEmpty`).

`getTypeContextDescriptorFlags()` reinterprets the base `ContextDescriptorFlags`'s 16
kind-specific bits as `TypeContextDescriptorFlags` (`:4131-4133`,`MetadataValues.h:1967-2118`).
Fields meaningful for *every* type kind: `MetadataInitialization` (2-bit enum: none / singleton /
foreign, `:1977-1978, 2048-2064`), `HasImportInfo` (`:1988`),
`HasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer` (`:1993`), `HasLayoutString`
(`:1996`). Class-only bits, all in the top half: `Class_HasDefaultOverrideTable` (bit 6),
`Class_IsActor` (7), `Class_IsDefaultActor` (8), `Class_ResilientSuperclassReferenceKind` (9-11, a
`TypeReferenceKind`), `Class_AreImmediateMembersNegative` (12), `Class_HasResilientSuperclass`
(13), `Class_HasOverrideTable` (14), `Class_HasVTable` (15) (`MetadataValues.h:2000-2041`).

### 4.3 `TargetClassDescriptor<Runtime>` (`Metadata.h:4337-4793`)

Fixed fields, in order, right after the `TargetTypeContextDescriptor` base:

```
TargetRelativeDirectPointer<Runtime, const char> SuperclassType;   // :4433, mangled, nullable-by-convention
union { uint32_t MetadataNegativeSizeInWords;
        RelativeDirectPointer<StoredClassMetadataBounds> ResilientMetadataBounds; };  // :4435-4445
union { uint32_t MetadataPositiveSizeInWords;
        ExtraClassDescriptorFlags ExtraClassFlags; };                                 // :4447-4455
uint32_t NumImmediateMembers;   // :4464 — members ADDED by this class, not inherited
uint32_t NumFields;             // :4478 — stored properties in THIS class only
uint32_t FieldOffsetVectorOffset;  // :4488, private — see §6
```

Both unions are discriminated by `hasResilientSuperclass()`
(`getTypeContextDescriptorFlags().class_hasResilientSuperclass()`, `:4621-4623`): non-resilient
classes store literal negative/positive metadata-size-in-words; resilient ones store a relative
pointer to a `TargetStoredClassMetadataBounds` cache instead (`:4249-4302` for that cache's shape,
including the load-acquire-ordered `ImmediateMembersOffset`).

After the fixed fields, `TargetClassDescriptor` is a `TrailingGenericContextObjects` whose
trailing-object list, in emission order, is (`:4341-4359`): the generic-context header (if
generic) → `TargetResilientSuperclass` (if resilient) → `TargetForeignMetadataInitialization` (if
foreign init) → `TargetSingletonMetadataInitialization` (if singleton init) →
`TargetVTableDescriptorHeader` (if `hasVTable()`) → `TargetMethodDescriptor[VTableSize]` → override
table header/entries → ObjC resilient-stub info → canonical-specialization lists → invertible-
protocol set → singleton-metadata pointer → default-override table/entries. Each block's *presence*
is itself gated by a flag or a previous block's count (`numTrailingObjects` overloads,
`:4496-4568`) — an offline reader must walk them in exactly this order, computing each block's size
before it can find the next block's start, the same way `TrailingObjects` does in-process.

`getVTableDescriptor()`/`getMethodDescriptors()` (`:4625-4636`) expose the vtable region:
`TargetVTableDescriptorHeader` (`:626-654`) holds a private `VTableOffset` (in words, meaning
depends on `hasResilientSuperclass()` exactly like `FieldOffsetVectorOffset` does, `:645-653`) and
a public `VTableSize` (entry count); each `TargetMethodDescriptor` (`:596-618`) is a
`MethodDescriptorFlags` plus a `TargetCompactFunctionPointer`/relative-pointer union selected by
`Flags.isAsync()`/`isCalleeAllocatedCoroutine()`.

### 4.4 `TargetStructDescriptor<Runtime>` (`Metadata.h:4799-4970`) and `TargetEnumDescriptor<Runtime>` (`:4972-5150`)

Both derive from `TargetValueTypeDescriptor` (`:4799-4808`, a marker with no extra fields, just
`classof` for `Struct`/`Enum`). Struct's own two fields (`:4893-4899`):

```
uint32_t NumFields;                // stored properties
uint32_t FieldOffsetVectorOffset;  // 0 == no field offset vector; always absolute (structs never have a resilient-superclass adjustment)
```

Enum's own two fields are shaped differently — enums do not have a field-offset vector at all
(cases aren't laid out like struct fields; payload layout is computed from the case types
directly):

```
uint32_t NumPayloadCasesAndPayloadSizeOffset;  // low 24 bits: payload-case count; high 8 bits: word offset of the payload-size field in instance metadata, 0 = absent (:5058, :5063-5079)
uint32_t NumEmptyCases;                        // :5061
```

Both trail generic-context objects analogous to the class case, minus the vtable/override
machinery (`:4810-4823` struct, `:4972-4985` enum).

---

## 5. Class metadata: field offset vector, vtable, resilient vs. fragile

### 5.1 Locating the field offset vector

For a **struct**, `TargetStructMetadata::getFieldOffsets()` (`Metadata.h:1393-1400`) is the exact
in-process algorithm to mirror offline:

```
offset = description->FieldOffsetVectorOffset;   // words, from the descriptor, always absolute for structs
if (offset == 0) return nullptr;
return (const uint32_t *)((const void * const *)metadataPointer + offset);
```

i.e. word-indexed (not byte-indexed) from the **metadata record's own start**, and each entry is a
**32-bit byte offset** into the instance — `uint32_t`, even on 64-bit targets. `NumFields` entries,
in field-record declaration order (matching `__swift5_fieldmd`'s `FieldRecord` order for that
type).

For a **class**, `TargetClassMetadata::getFieldOffsets()` (`:1118-1126`) is the same shape but the
offset itself is resilience-adjusted first:

```
offset = description->getFieldOffsetVectorOffset();   // NOT the raw stored field — see below
if (offset == 0) return nullptr;
return (const StoredPointer *)((const void * const *)metadataPointer + offset);
```

`getFieldOffsetVectorOffset()` (`Metadata.h:4591-4599`):

```
if (hasResilientSuperclass())
    return bounds.ImmediateMembersOffset / sizeof(StoredPointer) + FieldOffsetVectorOffset;  // relative to resilient superclass's *runtime* size
return FieldOffsetVectorOffset;  // absolute, when the whole hierarchy is fragile
```

This is the single most important fact for a decompiler's class layout: **the raw
`FieldOffsetVectorOffset` stored in the descriptor is only directly usable when
`!hasResilientSuperclass()`.** When the superclass is resilient, the real word offset requires
`bounds.ImmediateMembersOffset`, which comes from `TargetStoredClassMetadataBounds`
(`:4249-4302`) — a value computed **at runtime**, cached in a `std::atomic`, and initialized by
walking the actual (possibly-larger-than-compile-time) resilient superclass metadata
(`getResilientMetadataBounds`, ADL-dispatched, referenced at `:4670-4673`). There is no static file
offset for it in a resilient-ancestry binary; see §6.

### 5.2 Class fields include the superclass prefix, computed at instantiation time, not compile time

The runtime function that fills in a class's field offsets, `initClassFieldOffsetVector`
(`/Users/camden/swift/stdlib/public/runtime/Metadata.cpp:4223-4312`), starts its running `size`
either from the **already-known instance size of the live superclass metadata**
(`super->getInstanceSize()`, `:4242`) or, for a root class, from the heap-object header
(`:4257-4261`) — then lays out this class's own fields by simple sequential
align-place-advance (`:4286-4303`, the same `roundUpToAlignMaskCheckingOverflow` +
`SaturatingAdd` pattern as `performBasicLayout`, `Metadata.cpp:2662-2710`). This confirms and
grounds the comment already in swiftdc's `FieldMap.swift`: *"For classes the offsets already
include the superclass prefix, so a raw `[x0, #N]` displacement maps directly with no
adjustment"* (`Sources/SwiftDecompilerCore/FieldMap.swift:60-61`) — but it also shows *why* that's
only true when the superclass's instance size is itself statically known, i.e. non-resilient. The
call site order in `_swift_initClassMetadataImpl`
(`copySuperclassMetadataToSubclass` then `initClassFieldOffsetVector`,
`Metadata.cpp:4619-4626`) is what copies the superclass's own field slots into the subclass's
vector before appending the new ones.

### 5.3 Vtable region

Already laid out structurally in §4.3. In metadata (not the descriptor), the vtable lives at
`VTableOffset` words from the metadata address point (fragile) or from
`bounds.ImmediateMembersOffset` (resilient) — the exact same resilience-conditional pattern as the
field offset vector (`TargetVTableDescriptorHeader::getVTableOffset`, `Metadata.h:645-653`,
mirrors `getFieldOffsetVectorOffset` at `:4591-4599`). `VTableSize` entries, each a
`TargetMethodDescriptor` from the *descriptor* (not metadata) giving the compact function pointer
— `getMethod(i)` (`:4710-4714`) is the reference accessor. This is what backs swiftdc's
`MetadataSymbolizer.classMethodNames`, indirectly, through MachOSwiftSection/SwiftDump's
declaration reconstruction (`Sources/SwiftDecompilerCore/MetadataSymbolizer.swift:34-57`).

### 5.4 Resilient vs. fragile, summarized

| | Fragile (no resilient superclass) | Resilient superclass |
|---|---|---|
| `FieldOffsetVectorOffset` semantics | absolute word offset from metadata start | word offset **relative to** `bounds.ImmediateMembersOffset` (`Metadata.h:4481-4488, 4591-4599`) |
| Superclass instance size | fixed, known at compile time | only known by loading the *actual* superclass metadata at runtime (`TargetStoredClassMetadataBounds`, `:4249-4302`) |
| `VTableOffset` semantics | same absolute/relative split (`:645-653`) | same |
| Offline recoverability | field byte offsets are statically exact | **not statically knowable** without a live process or a faithful reimplementation of the resilient-bounds computation across every intervening resilient ancestor — decline (§6) |

---

## 6. Where reconstruction MUST decline

Three independent, ABI-grounded reasons a byte offset is not knowable from a single Mach-O file,
each backed by runtime behavior above rather than by inference:

1. **Generic (unspecialized) layouts.** A generic type's descriptor is shared across every
   instantiation (`TypeMetadata.rst:353-354`, corroborated by current code: one `TargetTypeGenericContextDescriptorHeader`
   per descriptor, `Metadata.h:3835-3857`, with a `DefaultInstantiationPattern` pointing at a
   `TargetGenericMetadataPattern` that is executed, not read, to build metadata). The concrete
   field offsets only come to exist when `swift_initStructMetadata`
   (`Metadata.cpp:3358-3407`) or `_swift_initClassMetadataImpl` →
   `initClassFieldOffsetVector` (`Metadata.cpp:4223-4312`) actually runs `performBasicLayout`
   (`:2662-2710`) over the **substituted** generic arguments' `TypeLayout`s — a computation keyed
   on runtime type metadata for `T`, `U`, … that does not exist as static data unless the compiler
   happened to also emit a **canonical specialization** for a concrete binding
   (`getCanonicalMetadataPrespecializations()`, e.g. `Metadata.h:4733-4744` for classes,
   `:4919-4930` for structs). Static analysis of an unspecialized generic's descriptor alone can
   recover field **names, declared types (as mangled strings), and declaration order** — never
   byte offsets. Decline the offset, not the field.
2. **Resilient types whose size isn't statically known.** Covered in full in §5.4: any class whose
   *any* ancestor sets `Class_HasResilientSuperclass`
   (`MetadataValues.h:2031, 2097-2099`) has a `FieldOffsetVectorOffset`/`VTableOffset` that is only
   meaningful relative to a `TargetStoredClassMetadataBounds` value
   (`Metadata.h:4249-4302`) computed by walking the live superclass chain — which, for a
   superclass defined in a *different* resilient-library-evolution module than the one being
   decompiled, is not present in this binary at all. This is exactly the crash mode swiftdc's own
   `FieldMapBuilder.build` doc comment already documents and works around: resolving through
   `ImageUniverse.dependencyClosure` to satisfy a resilient cross-module field (a `Foundation.Date`
   or `UUID`) **traps** with an uncatchable `Fatal error: Not enough bits to represent the passed
   value` (`Sources/SwiftDecompilerCore/FieldMap.swift:245-250`) rather than returning a wrong
   answer — which is the correct instinct (crash/decline over silent wrongness) but the crash
   itself is a robustness bug per this project's priority-3 rule, not an acceptable steady state;
   see recommendation R3.
3. **Foreign / `__C` types.** `TargetForeignClassMetadata`'s own doc comment states the design
   intent directly: *"We assume for now that foreign classes are entirely opaque to Swift
   introspection"* (`Metadata.h:1279-1280`). Its metadata record carries only a `Description`
   pointer, a `Superclass` metadata pointer, and reserved zeroed space (`:1282-1295`) — no field
   offset vector field exists on the type at all, structurally, not just as a runtime-computed
   zero. Detect this by `isCImportedContext()` walking to the module context and comparing against
   `MANGLING_MODULE_OBJC` (`Metadata.h:3207-3212, 3221-3224, 3242-3244`), or equivalently by
   `MetadataKind::ForeignClass` on the metadata record (`Metadata.h:1307-1309`), or by
   `hasForeignMetadataInitialization()` on the type-context flags
   (`MetadataInitializationKind::ForeignMetadataInitialization = 2`, `MetadataValues.h:2059-2078`).
   swiftdc already has a related, narrower signal available: `FieldDescriptorKind::ObjCClass`
   marks a field descriptor whose type "must be obtained from the Objective-C runtime"
   (`Records.h:178-181`) — i.e. **no Swift field records will exist for it even though the type is
   reflectable-shaped**; that's a *different, additional* empty-result cause from "no field
   descriptor at all" and, per this project's diagnostics rule, should not be spelled the same way.

---

## 7. Ranked recommendations for swiftdc's metadata/FieldMap path

Ordered by the project's own priority list (soundness → completeness → robustness →
determinism → …, `/Users/camden/compiler/CLAUDE.md`). swiftdc does not hand-roll ABI parsing —
`FieldMapBuilder`/`StaticLayoutCalculator` delegate to MachOSwiftSection's `SwiftLayout` module
(`.build/checkouts/MachOSwiftSection/Sources/SwiftLayout/StaticLayoutCalculator.swift`), which
already has decline logic for "a cross-module resilient type, an unsupported kind, an
unsubstituted generic" per its own header comment (`StaticLayoutCalculator.swift:10`). The
recommendations below are about **verifying that delegate against the ABI facts above**, not
about reimplementing the ABI — reimplementing a second copy would itself be a soundness risk
(two sources of truth that can silently drift).

1. **[Soundness] Add a resilient-superclass cross-check, not just a crash guard.** §5.4/§6.2 shows
   the *specific* quantity that makes a fragile-looking class actually resilient:
   `Class_HasResilientSuperclass` (`MetadataValues.h:2031`) on **any ancestor**, not just the
   immediate one. Before trusting `FieldOffsetVectorOffset` as an absolute word count, walk the
   full superclass chain via each class descriptor's `SuperclassType`/`Superclass` mangled name
   (`Metadata.h:4433`) and confirm every ancestor is fragile. If `StaticLayoutCalculator` already
   does this walk, add a regression test with a class whose *grandparent* (not parent) is
   resilient (e.g. subclass a type from a system framework two levels removed) — the crash noted
   in `FieldMap.swift:245-250` was found on a *direct* resilient field, so an indirect-ancestor
   case is untested territory and is exactly the kind of "convenient path only" gap this project's
   verification-discipline rule calls out.
2. **[Completeness] Cross-check field-offset-vector reads against `NumFields`/`FieldRecordSize`
   the way the compiler's own reader does.** `Records.h:196-203` — a `FieldRecordSize` that
   doesn't match `sizeof(FieldRecord)` (12 bytes) means "walk zero records," full stop. If
   swiftdc/SwiftLayout instead trusts `NumFields` and strides blindly, a corrupted or
   from-a-newer-compiler field descriptor would silently produce wrong field *names* attached to
   right-looking offsets — worse than an empty result, because it passes the "did I get
   something" smell test. Confirm (with a deliberately-corrupted fixture) that a `FieldRecordSize`
   mismatch surfaces as a `FieldLookupFailure`/decline, not as a truncated-but-silently-accepted
   field list.
3. **[Robustness] Turn the `ImageUniverse.dependencyClosure` fatal trap into a caught, diagnosed
   decline.** `FieldMap.swift:245-250` documents that resolving resilient cross-module fields
   through the shared cache **traps uncatchably**. Per this project's priority order, robustness
   (crashes on unusual input) outranks reconstruction quality — the current single-image
   workaround only avoids *triggering* the trap, it doesn't fix that the trap exists. Worth a
   scoped investigation into whether the trap originates in MachOSwiftSection's own resilient-field
   resolution (candidate: wherever it computes a bit-width for prespecialized generic argument
   packing) and whether it can be replaced with a `throws`/`Result` path, matching this project's
   `DisassembleError.parsedNothing` pattern for the exact same "decline don't crash" reason.
4. **[Robustness/Completeness] Give `ObjCClass` field descriptors (`Records.h:178-181`) their own
   diagnostic, distinct from "no field descriptor at all."** An `@objc` class *has* a field
   descriptor (so `isReflectable()` is true, `Metadata.h:4125`) but *zero* Swift `FieldRecord`s by
   design — its real layout lives in Objective-C ivar metadata instead. If `FieldMapBuilder.build`
   currently treats "layout produced no fields" as one undifferentiated skip
   (`FieldMap.swift:261-263`, `!layout.fields.isEmpty`), a `swiftdc dump`/`layout` user cannot tell
   "this class has no stored properties" from "this class's properties come from ObjC and weren't
   looked up." The `ObjCMetadataIndex.swift` module already in `Sources/SwiftDecompilerCore/`
   suggests the ivar path exists separately — confirm the two are cross-referenced for classes
   whose field descriptor `Kind == ObjCClass`, per this project's rule that an analysis *failure*
   must never be spelled the same as an empty *result*.
5. **[Determinism/Verification] Encode §5.1/§5.2 as a fixture-backed regression test, not just
   documentation.** Build a tiny 3-level class hierarchy fixture (root → fragile mid → fragile
   leaf, all in one module so it stays fragile) with a mix of word-sized and sub-word fields
   spanning an alignment boundary between the mid and leaf class, and assert the leaf's `FieldMap`
   offsets equal `midInstanceSize` (rounded) `+ perFieldOffset` exactly as computed by
   `initClassFieldOffsetVector` (`Metadata.cpp:4286-4303`). This is the "prove a test catches the
   bug" step for the superclass-prefix claim currently asserted only in a code comment.
6. **[Reconstruction quality, lowest priority per the project's own ordering]** `__swift5_capture`
   and `__swift5_assocty` are mined here (§1/§2) but unused by swiftdc today. Associated-type
   records would let `swiftdc interface`-style output show `associatedtype` witnesses for a
   protocol conformance instead of omitting them; capture descriptors would let a future closure-
   context `FieldMap` name captured-variable accesses the same way `FieldMap` already names
   `self.` accesses. Both are real capability gaps, not correctness bugs — flagged last on
   purpose.

---

## Verification notes

- All line numbers were read directly from the files at the stated paths on 2026-09-08; re-check
  with `grep -n` against the same paths before relying on them if `/Users/camden/swift` has since
  moved past this commit (this checkout tracks upstream `swiftlang/swift` and is not itself
  pinned, per `swiftdc build environment` project memory).
- The `docs/ABI/TypeMetadata.rst` narrative was cross-checked against current `Metadata.h`/
  `MetadataValues.h` struct definitions wherever cited; two concrete staleness findings are called
  out inline (§0 preamble, §3 parent-pointer claim) rather than trusted silently.
- Runtime-side claims (§5.2, §6.1) are grounded in the actual field-offset-vector *producer*
  (`Metadata.cpp`'s `swift_initStructMetadata`/`initClassFieldOffsetVector`/`performBasicLayout`),
  not only the ABI header's *consumer*-side accessors — so the "why" behind each decline condition
  traces to the code that would otherwise compute the value, not just to a comment asserting it's
  unavailable.
- This document does not modify or assert conclusions about MachOSwiftSection's actual behavior
  beyond the one header-comment citation in §7 (`StaticLayoutCalculator.swift:10`) and the grep
  evidence for resilient/generic-aware code existing there — a full audit of that dependency was
  out of scope for this pass and is exactly what recommendations R1-R3 ask for as follow-up work.

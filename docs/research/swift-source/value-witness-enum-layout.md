# Value witnesses and enum layout: ground truth from the compiler source

Status: mined directly from `/Users/camden/swift` (a local `swiftlang/swift` checkout, HEAD
`1b7bd8ea` on `main`, 2026-09-07) on 2026-09-08, for swiftdc's `SwiftLayout`/enum-tag-recovery
path. Every structural claim below carries a `file:line` citation into that tree. Per the
authority hierarchy in `/Users/camden/compiler/CLAUDE.md`, this document is rank 4 (research
documentation) — current swiftdc source and its tests outrank it if they ever disagree. It is a
companion to `docs/research/swift-source/type-metadata-layout.md` (nominal descriptors, field
records, relative pointers); this document picks up where that one stops, at the value-witness
table and the two enum tag algorithms.

**A load-bearing finding, not a footnote**: swiftdc's own `Package.swift` already depends on the
`SwiftLayout` product from `MachOSwiftSection` (`Package.swift:135`), and
`Sources/SwiftDecompilerCore/FieldMap.swift:1-4,251-263` already consumes it
(`StaticLayoutCalculator`/`AggregateFieldLayout`) for struct/class field offsets. At the exact
pinned revision (`287886a9`, tag `0.12.0`, resolved in `Package.resolved`), that same package
ships a second product, `SwiftInspection` (not yet a swiftdc dependency), containing
`EnumLayoutCalculator`, `SpareBitAnalyzer`, and `RuntimeEnumCaseProjector` — a from-scratch port
of exactly the algorithms this document mines, with its own comments citing the same
`Enum.cpp`/`EnumImpl.h`/`TypeLowering.cpp` lines independently arrived at here. §7 treats this as
the primary recommendation: adopt and verify, not re-derive. (Caution: the live working tree at
`.build/checkouts/MachOSwiftSection` is 304 commits ahead of the pin, on `main` — read code there
only to understand shape, and cite the pinned commit `287886a9` for anything swiftdc actually
depends on today. This is the same "pinned-to-main" trap the project's memory file already flags
for this dependency.)

---

## 0. Scope

Seven questions, in the order asked:

1. The value witness table: which witnesses layout needs, and how they compose for aggregates.
2. Extra inhabitants: what they are, how many common types contribute, saturation.
3. Single-payload enum layout: extra-inhabitant tag vs. a separate tag byte, and the exact
   crossover rule.
4. Multi-payload enum layout: the spare-bits algorithm.
5. Reference storage (`weak`/`unowned`/`unowned(unsafe)`) widths and takability, including over
   class-bound existentials.
6. Disassembly-side: what tag-extraction code looks like, and where a decompiler must decline.
7. Ranked recommendations for swiftdc.

All numeric ABI constants below are **arm64 Darwin** unless stated otherwise — swiftdc's build
requires Apple Silicon (`/Users/camden/compiler/CLAUDE.md`: "Requires Apple Silicon"). The x86_64
and simulator constants differ and are noted in §2 for completeness, since swiftdc can still be
pointed at an x86_64 Mach-O slice or dyld cache image.

---

## 1. The value witness table

### 1.1 What a value witness table actually is

`TargetValueWitnessTable<Runtime>` is a struct of function pointers plus a trailing four-word
**type layout record** (`TargetTypeLayout<Runtime>`) — `size`, `stride`, `flags`,
`extraInhabitantCount` — laid out so that `getTypeLayout()` can reinterpret a `&size` pointer
directly as a `TargetTypeLayout*` (`ValueWitnessTable.h:227-230`, static-asserted byte-identical
at `ValueWitnessTable.h:323-337`). This four-word record is *the* thing swiftdc's `SwiftLayout`
mirror needs to reconstruct per type; everything else in the VWT is executable code, irrelevant to
static analysis.

The witness list is defined once, as an X-macro, in `include/swift/ABI/ValueWitness.def` and
expanded three ways (`WANT_ALL_VALUE_WITNESSES` / `_ONLY_REQUIRED_` / `_ONLY_ENUM_`) into the two
concrete table shapes:

- **Required witnesses** (every value witness table has these) —
  `initializeBufferWithCopyOfBuffer`, `destroy`, `initializeWithCopy`, `assignWithCopy`,
  `initializeWithTake`, `assignWithTake`, `getEnumTagSinglePayload`,
  `storeEnumTagSinglePayload` (`ValueWitness.def:99-183`), then the four data fields `size`,
  `stride`, `flags`, `extraInhabitantCount` (`ValueWitness.def:185-243`, bracketed by
  `BEGIN/END_VALUE_WITNESS_RANGE(RequiredTypeLayoutWitness, …)` — this is exactly the
  `TargetTypeLayout` subset).
- **Enum-only witnesses**, present only when `flags.hasEnumWitnesses()` is set —
  `getEnumTag`, `destructiveProjectEnumData`, `destructiveInjectEnumTag`
  (`ValueWitness.def:258-292`; the guard is `TargetEnumValueWitnessTable::classof`,
  `ValueWitnessTable.h:271-273`, which literally checks `table->flags.hasEnumWitnesses()`).

`getEnumTagSinglePayload`/`storeEnumTagSinglePayload` are *required* (every VWT has them, even a
non-enum type — they're no-ops or trivial there) because any type can be the payload of an
`Optional`; `getEnumTag`/`destructiveProjectEnumData`/`destructiveInjectEnumTag` are enum-specific
and only appear when the type is itself an enum with `hasEnumWitnesses` set. swiftdc will never
call any of these (it has no target process to call into) — the four data fields are the entire
static surface it needs, and it should treat the function-pointer witnesses purely as "this
symbol/relocation exists" evidence, not as something to interpret.

### 1.2 The four fields, exactly

- `size: StoredSize` — bytes of significant data, **not** padded to alignment
  (`ValueWitness.def:185-190`, doc comment: "not... padded up to the alignment; that value is
  maintained as `stride`").
- `stride: StoredSize` — bytes from one array element to the next; **always ≥ 1**, even for a
  zero-sized type like `()` (`ValueWitness.def:198-204`).
- `flags: TargetValueWitnessFlags<StoredSize>` — packed bitfield, detailed in §1.3.
- `extraInhabitantCount: uint32_t` — see §2.

### 1.3 `TargetValueWitnessFlags` bit layout

`MetadataValues.h:167-317`. The low byte is the alignment mask (so `alignment = (flags &
0xFF) + 1`); everything above that is single-bit flags:

```
AlignmentMask                = 0x000000FF   (low byte: alignment - 1)
IsNonPOD                     = 0x00010000
IsNonInline                  = 0x00020000
HasSpareBits                 = 0x00080000
IsNonBitwiseTakable          = 0x00100000
HasEnumWitnesses             = 0x00200000
Incomplete                   = 0x00400000
IsNonCopyable                = 0x00800000
IsNonBitwiseBorrowable       = 0x01000000
IsAddressableForDependencies = 0x02000000
```
(`MetadataValues.h:173-187`.) Note the **inverted polarity**: `IsNonPOD`, `IsNonInline`,
`IsNonBitwiseTakable`, `IsNonCopyable`, `IsNonBitwiseBorrowable` are all "is-NOT" bits, clear by
default. The doc comment explains why (`MetadataValues.h:169-172`): "chosen so that, when doing
struct layout, the flags of the field types can be mostly bitwise-**or**'d together" — a struct is
non-POD/non-bitwise-takable/non-copyable/non-borrowable the moment *any* field is, so OR-ing the
"non-" bits gives the right answer directly. (In practice `performBasicLayout`, §1.4, computes
these as plain booleans and AND/OR them explicitly rather than literally OR-ing the raw flag
words, but the polarity choice is what makes that composition monotonic in the first place.)

Per-bit semantics, each with its accessor:
- `getAlignmentMask()` / `getAlignment() = mask + 1` (`MetadataValues.h:211-221`).
- `isInlineStorage()`: fits in a 3-word `ValueBuffer` without heap allocation
  (`MetadataValues.h:226`; the actual inline test is
  `canBeInline(isBitwiseTakable, size, alignment) = isBitwiseTakable && size <=
  sizeof(ValueBuffer) && alignment <= alignof(ValueBuffer)`, `ValueWitnessTable.h:79-88` and
  `:153-157`). Non-bitwise-takable types are *always* out-of-line, regardless of size.
- `isPOD()`: memcpy-copyable and no-op-destructible (`MetadataValues.h:234`).
- `isBitwiseTakable()`: memcpy-*take*-able (destructive move; source becomes invalid, no need to
  retain/adjust). The doc comment is the exact rule swiftdc needs for reference storage (§5):
  "Only types with side table references, like `@weak` references, or types with opaque value
  semantics, like imported C++ types, are not bitwise-takable" (`MetadataValues.h:240-245`).
- `isBitwiseBorrowable()`: `isBitwiseTakable() && !IsNonBitwiseBorrowable`
  (`MetadataValues.h:257-266`) — a *subset* of bitwise-takable, added for `Atomic`/`Mutex` in
  Swift 6; a pre-Swift-6 VWT never sets `IsNonBitwiseBorrowable`, so this always equals
  bitwise-takable for anything swiftdc will see from an older toolchain.
- `hasEnumWitnesses()`: gates the three enum-only function witnesses (§1.1).
- `isIncomplete()`: layout not yet published; irrelevant offline (always false in a finished
  binary's static metadata).

### 1.4 How flags/size/alignment compose for a struct or tuple (the aggregate algorithm)

This is the runtime's `performBasicLayout` — sequential field placement plus flag composition —
and it is the single function swiftdc's `SwiftLayout`/`AggregateFieldLayout` mirror must match
exactly, since a one-field error here shifts every later offset (per the project's own stated
risk). Full algorithm, `Metadata.cpp:2662-2721`:

```
size = 0 (or sizeof(HeapObject) for a class's own-field prefix, getInitialLayoutForHeapObject, :2642-2647)
alignMask = 0; isPOD = isCopyable = isBitwiseTakable = isBitwiseBorrowable = true; isAFD = false
for each field, in declaration order:
    size = roundUpToAlignMask(size, field.alignMask)     # insert padding
    field.offset = size                                  # this field's offset
    size = size + field.size                              # (saturating; overflow -> hard error)
    alignMask = max(alignMask, field.alignMask)
    isPOD               &= field.isPOD
    isCopyable          &= field.isCopyable
    isBitwiseTakable    &= field.isBitwiseTakable
    isBitwiseBorrowable &= field.isBitwiseBorrowable
    isAFD               |= field.isAddressableForDependencies
isInline = ValueWitnessTable::isValueInline(isBitwiseTakable, size, alignMask + 1)
stride = max(1, roundUpToAlignMask(size, alignMask))
extraInhabitantCount = 0   # NOT computed here — see below
```
(`Metadata.cpp:2662-2721`, exact line-by-line match to the pseudocode above.) Two things a mirror
must not miss:

1. **Field order matters for offsets but not for the composed flags** — `isPOD`/`isBitwiseTakable`/
   etc. are pure conjunctions (or the one disjunction, AFD), independent of order; only `size`/
   `offset` depend on declaration order, which is exactly why swiftdc's `FieldMap` trust-prefix
   model (stop at the first unresolvable field) is sound for offsets specifically.
2. **`performBasicLayout` always resets `extraInhabitantCount` to 0.** The caller re-derives it
   separately, immediately after: for a struct, "we have extra inhabitants if any element does —
   use the field with the most" (`Metadata.cpp:3389-3401`, inside `swift_initStructMetadata`,
   `Metadata.cpp:3358-3407`):
   ```
   extraInhabitantCount = max over fields of field.extraInhabitantCount
   ```
   This is a **max**, not a sum and not "only the first field" — a struct's extra inhabitants come
   from whichever single field happens to have the most spare/invalid bit patterns (the reflection
   library's independently-arrived-at wording, "inherit XIs from their most capacious member," is
   in `TypeLowering.cpp:420-425`; both describe the same max-over-fields rule).

A tuple uses the identical `performBasicLayout` call (`Metadata.cpp:2776`, `swift_initTupleMetadata`
region) with tuple elements as the field list — structs and tuples are laid out by literally the
same function, differing only in what gets published (a field-offset vector vs. an
element-offset array).

`installCommonValueWitnesses` (`Metadata.cpp:3260-…`) runs after size/flags are finalized and
substitutes specialized POD/non-POD witness function pointers for common (size, alignment,
has-XIs) triples — pure codegen optimization, no layout content, safe for swiftdc to ignore
entirely.

---

## 2. Extra inhabitants

### 2.1 What they are

An "extra inhabitant" is a bit pattern that is the right size and alignment for a type but is
**not** a valid value of it — e.g. a null class pointer, or the addresses `0..<4096` that no
Darwin heap allocation ever returns. The runtime and the enum-layout algorithms (§3, §4) use these
spare, otherwise-illegal patterns to store `Optional`/enum discriminators for free, without
growing the type. `extraInhabitantCount` is the fourth VWT/`TypeLayout` field (§1.2); it saturates
at `ValueWitnessFlags::MaxNumExtraInhabitants = 0x7FFFFFFF` (INT32_MAX) — `MetadataValues.h:189` —
because it is stored as a plain `uint32_t` (`ValueWitnessTable.h:125,294-295`) and the runtime
needs headroom to add 1 without overflow when converting an XI index to a 1-based enum tag
(§3).

### 2.2 Heap-object (class reference) extra inhabitants

This is the single highest-value case: every `AnyObject`/class-typed field, and by extension every
`Optional<SomeClass>`, is built on it.

`heap_object_abi` (`stdlib/public/SwiftShims/swift/shims/HeapObject.h:287-301`) exposes four
platform constants, resolved by architecture/OS macros
(`stdlib/public/SwiftShims/swift/shims/System.h`):

| Constant | arm64 Darwin (incl. sim) | x86_64 Darwin | x86_64 Darwin simulator |
|---|---|---|---|
| `LeastValidPointerValue` | `0x1_0000_0000` (`System.h:143`) | `0x1_0000_0000` (`System.h:107`) | same |
| `SwiftSpareBitsMask` | `0xF000_0000_0000_0007` (`System.h:156`) | `0xFF00_0000_0000_0007` (`System.h:70,112-113`) | same |
| `ObjCReservedBitsMask` | `0x8000_0000_0000_0000` (`System.h:160`) | `0x0000_0000_0000_0001` (`System.h:117`) | `0x8000_0000_0000_0000` (`System.h:119`) |
| `ObjCReservedLowBits` | `0` (`System.h:161`) | `1` (`System.h:118`) | `0` (`System.h:120`) |

`swift_getHeapObjectExtraInhabitantIndex` (`Runtime/Metadata.h:908-927`): a pointer value `v <
LeastValidPointerValue` (Darwin reserves the low 4 GiB of address space, so any such value is
provably not a real allocation) is an extra inhabitant, index `= v >> ObjCReservedLowBits` — with
the low `ObjCReservedLowBits` bits required to be zero first (they're reserved for ObjC tagged
pointers on x86_64; arm64 Darwin has `ObjCReservedLowBits = 0`, so this check is a no-op there).
A value `≥ LeastValidPointerValue` is *not* an extra inhabitant (it's a real or plausible pointer).

`swift_getHeapObjectExtraInhabitantCount` (`Runtime/Metadata.h:944-960`): `LeastValidPointerValue
>> ObjCReservedLowBits`, saturated at `INT_MAX`. On arm64 Darwin: `0x1_0000_0000 >> 0 =
4294967296`, saturated to `INT_MAX = 2147483647 = 0x7FFFFFFF` — i.e. **a class reference's extra
inhabitant count saturates to `MaxNumExtraInhabitants` exactly**, so `Optional<AnyObject>` and
every deeper `Optional<Optional<AnyObject>>` nesting always has room; XI count is never the
limiting factor for class references in practice. Concretely, **XI index 0 is raw pointer value
`0`** — this is *why* `Optional<SomeClass>.none` is represented as a literal nil pointer in
memory: it is not a special case, it falls straight out of this formula.

`swift_getFunctionPointerExtraInhabitantIndex`/`Count` (`Runtime/Metadata.h:964-991`) are the same
shape for a thin/C function pointer, using `LeastValidPointerValue` alone (no ObjC low-bit
adjustment — function pointers aren't ObjC-tagged): index `= v` for `v < LeastValidPointerValue`,
count `= LeastValidPointerValue` saturated at `INT_MAX` (same `0x7FFFFFFF` result on Darwin).

### 2.3 The multi-payload-enum pointer spare-bits mask

`SwiftSpareBitsMask` (table above) is exported as a debugger-visible runtime global,
`_swift_debug_multiPayloadEnumPointerSpareBitsMask = _swift_abi_SwiftSpareBitsMask`
(`stdlib/public/runtime/Enum.cpp:35-37`). This is a **real exported symbol swiftdc can read
directly out of a target binary or the shared cache's `libswiftCore.dylib`** rather than
hardcoding the arm64 constant — the reflection library itself prefers reading this symbol first
and falls back to the static constant only if the read fails
(`include/swift/RemoteInspection/TypeRefBuilder.h:1824-1845`, `getMultiPayloadEnumPointerMask()`).
On arm64 Darwin the two agree: `0xF000_0000_0000_0007` — the top 4 bits (unused address space
above the real 48-bit virtual range) plus the low 3 bits (every heap allocation is 8-byte
aligned). This mask is what §4 uses to compute how many spare bits a pointer-shaped payload
contributes to an enclosing multi-payload enum's tag.

### 2.4 Odd-width integers, `Bool`, and other builtin extra inhabitants

Not the focus of this document (out of the requested source list), but worth naming since
`swiftdc` will see them constantly: `Builtin.Int<N>` stored in a wider byte container exports
`(2^containerBits - 2^N)` extra inhabitants, capped at `MaxNumExtraInhabitants`
(`stdlib/public/RemoteInspection/TypeLowering.cpp:290-351`, `BuiltinTypeInfo`). `Bool` is
`Builtin.Int1` in a 1-byte container: 2 valid values, 254 extra inhabitants. The spare bits for
such a field are its **most-significant** `(containerBits - N)` bits — low bits hold the real
value (`TypeLowering.cpp:344-351`).

---

## 3. Single-payload enum layout

A single-payload enum has exactly one case that carries a payload (possibly zero-sized) and zero
or more empty (no-payload) cases — `Optional<T>` is the canonical example (`.some(T)` +
`.none`).

### 3.1 The exact size/tag-byte rule

`swift_initEnumMetadataSinglePayload` (`Enum.cpp:172-244`):

```
payloadNumExtraInhabitants = payloadLayout.extraInhabitantCount
if payloadNumExtraInhabitants >= emptyCases:
    size = payloadSize                                    # no growth at all
    unusedExtraInhabitants = payloadNumExtraInhabitants - emptyCases
else:
    numTagBytes = getEnumTagCounts(payloadSize,
                                    emptyCases - payloadNumExtraInhabitants,
                                    payloadCases: 1).numTagBytes
    size = payloadSize + numTagBytes                       # hard error if it overflows
    unusedExtraInhabitants = 0
```
(`Enum.cpp:177-195`, `addTagBytesOrTrap` at `:57-72` traps rather than silently wrapping on
overflow — that trap is itself evidence a type is malformed if swiftdc ever needs to reason about
it). **This is the exact crossover rule requested**: a tag byte (or more) is appended *only* when
the payload's own extra inhabitants are insufficient to number every empty case; otherwise the
enum's total size equals the payload's size, unchanged, and the empty cases live entirely inside
the payload's own invalid bit patterns.

`getEnumTagCounts(size, emptyCases, payloadCases)` (`include/swift/ABI/Enum.h:24-49`) — used
throughout §3 and §4 — computes how many distinct tag *values* and how many *bytes* those values
need:
```
numTags = payloadCases
if emptyCases > 0:
    if size >= 4: numTags += 1                              # one tag value covers up to 2^32 cases
    else:
        bits = size * 8
        numTags += ceil(emptyCases / 2^bits)
numTagBytes = numTags<=1 ? 0 : numTags<256 ? 1 : numTags<65536 ? 2 : 4
```
Note `size` here is the *payload* size in bytes, reused as the width of the "extra tag bytes"
region once one is needed — the extra-tag-bytes region packs `2^(8*payloadSize)` distinct values
per tag byte, capped at 4 bytes total (`Enum.h:45-47`; a `numTagBytes` of exactly 0 or 1 also
governs whether the enum needs any extra storage at all).

### 3.2 How the tag is read/written once storage is decided (`EnumImpl.h`)

`getEnumTagSinglePayloadImpl` (`EnumImpl.h:102-139`) — the read side:
```
if emptyCases > payloadNumExtraInhabitants:               # an extra-tag-bytes region exists
    extraTagBits = load(valueAddr + payloadSize, numTagBytes)
    if extraTagBits > 0:                                    # non-payload-page: an empty case
        caseIndexFromExtraTagBits = payloadSize>=4 ? 0 : (extraTagBits-1) << (payloadSize*8)
        caseIndexFromValue = load(valueAddr, payloadSize)
        noPayloadIndex = (caseIndexFromExtraTagBits | caseIndexFromValue) + payloadNumExtraInhabitants
        return noPayloadIndex + 1                            # tag 0 is reserved for "the payload case"
if payloadNumExtraInhabitants > 0:
    return getExtraInhabitantTag(enumAddr, payloadNumExtraInhabitants, payload)  # 0 if valid payload, else 1-based XI index
return 0                                                     # no XIs, no extra tag bytes: only the payload case exists
```
`storeEnumTagSinglePayloadImpl` (`EnumImpl.h:141-190`) is the write-side mirror: `whichCase == 0`
is the payload case (zero the extra tag bytes if any, done); `1 <= whichCase <=
payloadNumExtraInhabitants` stores an extra-inhabitant pattern via `storeExtraInhabitantTag`;
above that, the case index is split between the payload bytes and the extra tag bytes exactly as
in the read path, in reverse (`EnumImpl.h:172-189`).

**Tag numbering convention** (load-bearing for swiftdc's `EnumCaseIndex` if it is ever extended to
payload enums): the *witness-level* tag is `0` for the payload case, `1..payloadNumExtraInhabitants`
for empty cases encoded as extra inhabitants, and `payloadNumExtraInhabitants+1..` for empty cases
that spilled into extra tag bytes — **not** simple declaration order, and **not** the same
`getEnumTag`/case-index numbering used elsewhere (`swift_getEnumCaseMultiPayload`, §4, numbers
payload cases `0..<numPayloads` and empty cases starting at `numPayloads`). A decompiler must
track which numbering a given witness/accessor uses and not conflate them.

### 3.3 Worked consequence: `Optional<AnyObject>`

Payload = a class reference, `payloadNumExtraInhabitants` saturates to `0x7FFFFFFF` (§2.2), vastly
more than `emptyCases = 1` (`.none`). So per §3.1, `size = payloadSize` (no growth — `Optional<T>`
for a class `T` is exactly 8 bytes, same as `T`), and `.none` is XI index 0, which by §2.2 is the
raw bit pattern `0`. This is the concrete chain from ABI constant to the everyday fact "a nil
optional class reference is a nil pointer."

---

## 4. Multi-payload enum layout

This is the hardest part, and the runtime and the *offline* reflection engine implement genuinely
different algorithms for it — conflating them is the most likely way to get this wrong, so read
§4.1 before §4.2.

### 4.1 What `swift/stdlib/public/runtime/Enum.cpp`'s multi-payload path actually does (and does NOT do)

`swift_initEnumMetadataMultiPayload` (`Enum.cpp:442-512`) is the **runtime's dynamic fallback** —
used when a generic or resilient multi-payload enum's layout can't be baked in at compile time and
must be computed at first use, in-process. It does **not** implement spare-bit packing at all:

```
payloadSize = max over payloads of payload.size
alignMask = OR over payloads of payload.alignMask         # union of alignment requirements
isPOD/isBT/isBB          = AND over payloads
isAFD                    = OR over payloads
tagCounts = getEnumTagCounts(payloadSize, numEmptyCases, numPayloads)   # §3.1's helper, reused
totalSize = payloadSize + tagCounts.numTagBytes             # PLAIN trailing tag, always appended
numExtraInhabitants = tagCounts.numTagBytes==4 ? INT_MAX
                     : (2^(8*numTagBytes) - tagCounts.numTags), capped at MaxNumExtraInhabitants
```
(`Enum.cpp:447-500`). The companion accessors (`Enum.cpp:666-808`: `MultiPayloadLayout`,
`storeMultiPayloadTag`/`Value`, `loadMultiPayloadTag`/`Value`,
`swift_storeEnumTagMultiPayload`, `swift_getEnumCaseMultiPayload`) all operate on this same
"payload bytes, then plain trailing tag bytes" shape — `getMultiPayloadLayout` literally computes
`{payloadSize: enumType.payloadSize, numTagBytes: enumType.totalSize - payloadSize}`
(`Enum.cpp:673-679`), no spare-bit mask anywhere. **This is a genuine, important trap**: reading
only `Enum.cpp` gives the impression multi-payload enums never use spare bits. They do — just not
here. This is the "no room for the compiler to prove anything about the payloads" fallback (see
below for exactly when it applies).

`swift_getEnumCaseMultiPayload` (`Enum.cpp:786-808`) is the tag-to-case-index formula for *this*
layout, useful as a template even though the spare-bits version (§4.2) differs in the details:
```
tag = load(payload + payloadSize, numTagBytes)
if tag < numPayloads: return tag                            # a payload case, tag IS the case index
else:
    payloadValue = load(payload, payloadSize)
    if payloadSize >= 4: return numPayloads + payloadValue
    else: return numPayloads + ((tag - numPayloads) << (payloadSize*8)) + payloadValue
```

### 4.2 The real spare-bits algorithm: `stdlib/public/RemoteInspection/TypeLowering.cpp`

This file is the Swift project's own **offline, static, out-of-process** layout engine — it powers
`swift-inspect`/reflection tooling and computes layout by reading Mach-O metadata sections, with
no running target process required. It is architecturally the closest existing analog to what
swiftdc needs, and it is a *structural port* of the same spare-bit algorithm IRGen uses at compile
time (`lib/IRGen/GenEnum.cpp`, not separately mined here since `TypeLowering.cpp` restates it in a
form meant to be read and re-implemented).

**Step 1 — decide the strategy.** `EnumTypeInfoBuilder::build` (`TypeLowering.cpp:2172-2487`)
classifies every case (empty / non-generic-empty-payload / non-generic-non-empty-payload /
generic-payload; `:2227-2278`), then dispatches:
- 0 effective payload cases → `NoPayloadEnumTypeInfo` (a plain 1/2/4-byte tag; `:2329-2360`).
- 1 effective payload case → `SinglePayloadEnumTypeInfo`, using the exact §3.1 formula
  ("Below logic should match the runtime function `swift_initEnumMetadataSinglePayload()`",
  `TypeLowering.cpp:2375-2393`).
- ≥2 effective payload cases with **no static (`__swift5_builtin`) descriptor, or any generic
  payload case** → `TaggedMultiPayloadEnumTypeInfo`: the §4.1 plain-trailing-tag shape, via the
  *same* `getEnumTagCounts` helper (`TypeLowering.cpp:2403-2442`). This is precisely when §4.1's
  runtime fallback is the actual, correct layout — a decompiler seeing a generic or resilient
  multi-payload enum should expect a plain trailing tag, not spare bits.
- ≥2 effective payload cases **with** a static descriptor: compute
  `localSpareBitMask = AND over payload cases of case.getSpareBits()` (`:2462-2470`) — this is
  the actual "gather spare bits across payloads" step. If the mask is all-zero, or any payload
  case is address-only (can't be safely bit-masked in place, e.g. contains a weak reference),
  fall back to `TaggedMultiPayloadEnumTypeInfo` again (`:2472-2479`); otherwise build
  `MultiPayloadEnumTypeInfo` with that mask (`:2480-2486`).

**Per-type spare-bit contribution** (what gets AND-ed together in step 1):
- A class/`AnyObject` reference: the full `SwiftSpareBitsMask` (§2.3) —
  `ReferenceTypeInfo::getSpareBits` (`TypeLowering.cpp:251-254`).
- A `Builtin.Int<N>` in a wider container: its most-significant unused bits
  (`TypeLowering.cpp:344-351`, §2.4).
- A struct/tuple: **bitwise AND**, per field, of that field's own spare-bit mask positioned at the
  field's byte offset, starting from all-ones — `RecordTypeInfo::getSpareBits`
  (`TypeLowering.cpp:434-497`, the loop at `:490-495`, `mask.andMask(submask, Field.Offset)`).
  Padding bytes (touched by no field) stay all-spare. This is the aggregate composition rule for
  spare bits specifically — note it is an **AND positioned per field**, not the flag-composition
  AND/OR of §1.4; a byte is spare in the aggregate only if the one field that owns it leaves it
  spare (two fields never share a byte in a valid layout, so this reduces to "copy each field's
  own mask into its own byte range").
- A fixed-size array (`Builtin.FixedArray<N,T>`): only the **first** element's spare bits (plus
  its trailing stride padding) carry through — later elements hold live per-element data a
  containing enum cannot repurpose (`TypeLowering.cpp:524-537`).
- An existential metatype / class-existential's witness-table words: each pointer-sized word gets
  the same `SwiftSpareBitsMask`, applied per pointer-sized stride across the whole record
  (`TypeLowering.cpp:473-482`); a *class* existential's first word (the object pointer itself) is
  explicitly zeroed out of the mask first — it may be a tagged pointer with no guaranteed spare
  bits of its own (`TypeLowering.cpp:461-470`).

**Step 2 — split the tag between payload spare bits and an extra discriminator byte region.**
`MultiPayloadEnumTypeInfo` (`TypeLowering.cpp:994-1238`):

- `getNumTagBits()` (`:1192-1216`): the number of tag values needed is
  `(NumEffectivePayloadCases - 1)`, **plus**, if there are any non-payload (empty) cases, either
  `+1` (if the *non-spare* payload bits number ≥ 32 — plenty of room, one more tag value suffices)
  or `+ceil(numNonPayloadCases / 2^numPayloadBits)` where `numPayloadBits` is the count of
  **non**-spare bits in the payload area (the bits still available to distinguish empty cases once
  the tag has claimed the spare ones). The tag *bit* count is then just `ceil(log2(tagValues))`.
- `getMultiPayloadTagBitsMask()` (`:1221-1226`): take the accumulated `spareBitsMask`, restrict to
  the payload-sized byte range, and keep only its **most-significant** `getNumTagBits()` set bits
  — the payload's own spare bits absorb as much of the tag as they can hold, preferring the
  high-order spare bits.
- If the tag doesn't fully fit in spare bits, the remainder spills into an **extra discriminator**
  region appended after the payload (`getSize() - getPayloadSize()` bytes) — computed as
  `getNumTagBits() - payloadTagBitsMask.countSetBits()` low-order bits of that region
  (`:1105-1111`, inside `getSpareBits()`, which also excludes both regions from what an
  *enclosing* enum may reuse — spare bits nest, and a used tag bit is not spare to a parent enum).
- **Case projection** (`projectEnumValue`, `:1115-1185`): read the extra-discriminator bits (if
  any) as the *high* part of the tag and the payload's spare tag bits as the *low* part
  (`tagValue = (extraTag << numPayloadTagBits) | payloadTag`, `:1140-1153`). If `tagValue <
  NumEffectivePayloadCases`, that's the answer directly — it identifies which payload case is
  live. Otherwise, the **remaining non-spare payload bits** (`spareBitsMask.complement()`,
  `:1162-1163`) hold the rest of the discriminator for an empty case:
  `caseIndex = ((tagValue - NumEffectivePayloadCases) << occupiedBitCount) | payloadValue +
  NumEffectivePayloadCases` (`:1171-1176`).
- **Extra inhabitants** (`readExtraInhabitantIndex`, `:1020-1096`): unused tag values (beyond
  those needed for real cases) are themselves extra inhabitants exported to an *enclosing* enum,
  numbered from the top of the tag's value range downward (`maxTag - tag`, `:1093-1094`) — the
  same "count down from the max representable tag" convention as `TaggedMultiPayloadEnumTypeInfo`
  (`:912-919`, `maxTag - tag`) and the runtime's mirror-image `getMultiPayloadExtraInhabitantTag`
  (`Enum.cpp:719-729`, `index = ~loadMultiPayloadTag(...)`, i.e. bitwise complement, the same
  "count from the top" idea expressed as a NOT instead of a subtraction).

**Compiler ground truth, when it exists: `__swift5_mpenum`.** IRGen emits a
`MultiPayloadEnumDescriptor` record directly into the `__TEXT,__swift5_mpenum` section
(`include/swift/RemoteInspection/RuntimeHeaders/llvm/BinaryFormat/Swift.def:33`, section name
`"__swift5_mpenum"`) whenever it can determine the enum's spare-bit mask at compile time. Its
layout (`include/swift/RemoteInspection/Records.h:427-537`): a relative pointer to the type's
mangled name, then a packed `uint32_t[]` — a size/flags word (`getSizeFlagsIndex`, `:445`, low 16
bits = flags, high 16 = content word count, `:486-499`), a `usesPayloadSpareBits` flag (bit 0 of
those flags, `:501-503`), and — only if that flag is set — a byte-offset/byte-count word
(`:452-464,505-525`) followed by the raw spare-bit mask bytes themselves
(`getPayloadSpareBits()`, `:527-536`, "mask bytes live in `contents[2...]`"). **When this section
entry exists for a type, it is authoritative and should be preferred over re-deriving the mask
structurally** — it's literally what the compiler computed, not a reconstruction of it. Only fall
back to the §4.2 structural algorithm (or decline) when no `__swift5_mpenum` entry matches the
type, which per the strategy dispatch above is also exactly when the runtime falls back to a
plain trailing tag with no spare bits — i.e. **when the compiler had no `__swift5_mpenum` entry to
emit in the first place, both the runtime and swiftdc should expect the same plain-tag layout**,
which is a useful cross-check.

---

## 5. Reference storage: `weak` / `unowned` / `unowned(unsafe)`

All four ownership kinds — `strong` (default), `weak`, `unowned` (checked), `unowned(unsafe)`
a.k.a. `unmanaged` — are laid out to a **single pointer-sized, pointer-aligned word**. This holds
even for `weak`, which is easy to assume is wider (a value + a side-table pointer) because of how
it's *implemented*, but is not:

- `UnownedReference` (`include/swift/Runtime/HeapObject.h:466-468`): literally `struct
  UnownedReference { HeapObject *Value; }` — one word, no runtime bookkeeping struct wrapping it.
- `WeakReference` (`stdlib/public/runtime/WeakReference.h:156-163`): a union of `atomic<uintptr_t>`
  (native) and `id` (ObjC-interop non-native), statically asserted `sizeof(WeakReference) ==
  sizeof(void*)` and `alignof(WeakReference) == alignof(void*)`
  (`WeakReference.h:388-391`). The "side table" is reached *indirectly*: the stored word is either
  a tagged pointer to a `HeapObjectSideTableEntry` (native case,
  `WeakReferenceBits::getNativeOrNull`, `WeakReference.h:136-143`) or, on ObjC-interop platforms,
  an `id` the ObjC runtime's own weak table tracks by address — the field itself never grows.

The reflection engine's `getReferenceTypeInfo` (`TypeLowering.cpp:1635-1690`) confirms this from
the static-layout side: all four `ReferenceKind`s get the same `size`/`alignment`/`stride` — the
underlying `Builtin.NativeObject`/`Builtin.AnyObject` pointer's — and only *extra inhabitants* and
*borrowability* differ per kind (`:1652-1680`):

| Kind | Width | Extra inhabitants | Bitwise-takable | Bitwise-borrowable |
|---|---|---|---|---|
| `strong` | pointer | full heap-object XI count (§2.2) | yes | yes |
| `unowned` (checked) | pointer | same as underlying (inherits XIs) | yes† | no if `Unknown` refcounting |
| `unowned(unsafe)` / `unmanaged` | pointer | same as underlying | yes | yes |
| `weak` | pointer | **0** (`TypeLowering.cpp:1671`) | **no** | **no** (`:1672`) |

† `unowned` is bitwise-takable per the `MetadataValues.h:240-245` rule (§1.3): it has no side
table (unlike `weak`), so a destructive move is a plain memcpy — only the *destroy*/copy paths
need the special unowned-retain-count runtime calls. `weak` is the one kind the VWT flag doc
comment names explicitly as *not* bitwise-takable, because taking it must also decrement the old
side-table weak count, which a bare memcpy cannot do.

**Comment source note**: swiftdc's own `Sources/SwiftDecompilerCore/FieldMap.swift`'s upstream
dependency (`.build/checkouts/MachOSwiftSection`, `Sources/SwiftLayout/StaticTypeLayoutResolver.swift`
at HEAD `61f06284`, `.weak`/`.unowned`/`.unmanaged` node cases) states the same three facts
independently, in its own words, with its own citations to `IRGen`'s `ALWAYS_LOADABLE_CHECKED_REF_STORAGE`
et al. — cross-checked and consistent with the runtime source above.

**Why extra inhabitants and not `getSize()` differ**: `weak`'s zero-XI rule
(`TypeLowering.cpp:1671`) exists because a weak reference's "null-ish" bit patterns are not stable
enough to serve as an enum discriminator — the stored word can transition to zero asynchronously
when the referent deallocates, concurrently with a reader (see the threading contract at
`WeakReference.h:49-68`), so a spare-bit scheme built on "this exact byte pattern means empty
case" would race. `unowned`/`unmanaged` have no such hazard (no concurrent zeroing) and inherit
the underlying pointer's XIs unchanged.

### Over a class-bound existential

Applying `weak`/`unowned`/`unowned(unsafe)` to a class-constrained existential (e.g. `weak var x:
(some SomeClassProtocol)?`, or `unowned MyProtocol` where `MyProtocol: AnyObject`) does **not**
change the existential container's overall width. The container is a record — one class-reference
word plus one witness-table pointer per protocol requirement — and the storage qualifier attaches
to *only* the "object" field within that record; every witness-table word keeps its ordinary
pointer layout untouched
(`TypeLowering.cpp:2786-2825`, `rebuildStorageTypeInfo`'s `RecordKind::ClassExistential` branch:
"Destructure the existential and replace the 'object' field with the right reference kind" —
`:2791-2812`). So `sizeof(weak MyClassProtocol) == sizeof(strong MyClassProtocol) ==
(1 + witnessTableCount) * pointerSize`; only the semantics (and the extra-inhabitant/
bitwise-takability facts above) of that first word change.

---

## 6. From disassembly: what tag checks look like, and where to decline

This section grounds §3/§4's runtime formulas in what a decompiler actually sees in machine code,
and cross-references swiftdc's existing (no-payload-only) enum handling to show the exact seam
where payload-enum support would attach.

### 6.1 What swiftdc already recognizes (no-payload enums)

`Sources/SwiftDecompilerCore/EnumCaseIndex.swift` builds a `simple name → [case names in tag
order]` map straight from `__swift5_fieldmd`, restricted to `descriptor.numberOfPayloadCases ==
0` (`EnumCaseIndex.swift:59-62`) — for a no-payload enum the tag *is* the declaration index, no
witness-level indirection at all, so the map is a direct lookup. `Disassembler.swift` already
recognizes the corresponding machine-code idiom: a masked byte compared against a small constant
is an enum-tag check, not a boolean test —
```swift
// A masked value `(X & 0xff)` is a byte / no-payload-enum-tag extraction,
// not a Bool: `(tag & 0xff) == 1` is an enum-case check (`d == .green`)
```
(`Disassembler.swift:1564-1574`, `isMaskedByte`/`isTruthinessTest`). The abstract-value layer
already models exactly the primitives §3/§4's formulas need — `AbstractBinaryOperator` has
`.bitAnd`, `.bitOr`, `.shiftLeft`, `.shiftRight` cases (`ValueTracking.swift:13-17`) — so the gap
for payload enums is entirely in the **semantic mapping** (tag value → case index, per §3.2/§4.2's
numbering), not in the IR's ability to represent the mask/shift/compare sequence itself.

### 6.2 What a single-payload enum's tag check looks like

Two shapes, depending on whether §3.1 added a tag byte:

- **No tag byte** (payload XIs ≥ empty cases, e.g. `Optional<AnyObject>`): the check *is* the XI
  test, phrased in payload terms — for a class reference, `cmp x0, #0` / `cbz x0, …` (nil check)
  **is** the enum-tag check; there is no separate tag field to find. A decompiler that already
  renders `if let x = optionalClass` from a null check is, without knowing it, already doing exact
  single-payload-enum tag recovery for this common case.
- **Tag byte present** (e.g. `Optional<SomeStructWithNoXIs>` with ≥1 more empty case than the
  payload has XIs): a load from `self + payloadSize`, width `numTagBytes`, compared against `0`
  (payload case) or `> 0` (an empty case, further decoded per §3.2's `caseIndexFromExtraTagBits |
  caseIndexFromValue`). The load offset is a fixed function of the payload's *own* statically-known
  size — recoverable from `SwiftLayout`'s per-type size, not from the instruction stream alone.

### 6.3 What a multi-payload enum's tag check looks like

- **`TaggedMultiPayloadEnumTypeInfo` shape** (§4.1/§4.2's plain-trailing-tag case — generic or
  resilient payloads): load `numTagBytes` at `self + payloadSize`, then `switch`/cascade compare
  against `0 ..< numPayloads` for payload cases, `≥ numPayloads` for empty cases. This is
  structurally identical to the no-payload case's tag switch, just at a nonzero base offset —
  `Disassembler.swift`'s existing `resolveSwitchSelects` N-arm cascade recognition
  (per `docs/research/swift-source/type-metadata-layout.md`'s companion pipeline description) is
  the right place to hang a payload-aware case-name lookup onto, once the tag *offset* and *base*
  are known from layout rather than assumed to be 0.
- **`MultiPayloadEnumTypeInfo` shape** (real spare bits): the compiled tag-extraction sequence
  masks the payload with `spareBitsMask` (an `and`/`ubfx`-style bitfield extract at a fixed
  bit position, per §4.2's "most-significant N spare bits"), optionally ORs in a shifted extra
  discriminator byte, then compares/switches on the combined value. On arm64 this typically
  compiles to `ubfx`/`and`+`lsr` sequences rather than a byte-aligned load — **the mask is almost
  never byte-aligned**, unlike the no-payload and tag-byte cases above, so the existing
  `isMaskedByte` heuristic (`mask <= 0xff`, byte-shaped) will *not* fire correctly here and needs
  its own recognizer keyed to the enum's known `spareBitsMask` (from `__swift5_mpenum` or the
  structural computation) rather than a generic small-mask heuristic.

### 6.4 Where a decompiler must decline

Per the project's core rule (decline rather than guess), payload-enum tag recovery has two
genuinely different failure modes that must render differently, matching the project's existing
"don't spell an analysis failure the same as an empty result" discipline:

1. **The layout itself is unknown** — a generic payload with no concrete instantiation, a resilient
   cross-module payload type, or a payload type `SwiftLayout` gave up on mid-prefix (the same
   "trusted prefix" failure `FieldMap` already models for struct fields). Here swiftdc cannot even
   compute *how many* tag bits/bytes exist, so it must decline the whole tag comparison and print
   the raw mask/compare as an unlabeled expression — the same posture `.unknown` already gets
   elsewhere in the disassembler.
2. **The layout is known, but the *specific extra-inhabitant byte pattern* for one empty case is
   not** — this is a real, separate gap even when size/tag-bit-count are fully known. Per
   `RuntimeEnumCaseProjector`'s own design note (found while cross-checking the vendored
   dependency, §7): "a single-payload enum stores its empty cases as the payload's extra
   inhabitants — invalid bit patterns whose concrete bytes depend on the payload type... No
   formula over 'how many' extra inhabitants can recover 'which bytes'." A class reference's XI
   #0 is provably `0` (§2.2's formula is exact and closed-form), but an arbitrary struct's or
   `String`'s XI encoding is type-specific and not derivable from `extraInhabitantCount` alone.
   swiftdc should maintain a small closed table of **known** XI encodings (pointer/class → `index`,
   `Bool`/odd-width integers → `maxValid + 1 + index`, per §2.4) and decline — render the numeric
   tag, not a fabricated case name — for anything outside that table, exactly mirroring
   `EnumCaseIndex`'s existing "unknown/ambiguous → nil, caller declines" contract.

---

## 7. Ranked recommendations for swiftdc

1. **Adopt, verify, don't re-derive.** swiftdc's pinned `MachOSwiftSection` dependency
   (`Package.resolved`: `287886a9`, tag `0.12.0`) already ships `SwiftInspection.EnumLayoutCalculator`,
   `SwiftInspection.SpareBitAnalyzer`, and `SwiftInspection.RuntimeEnumCaseProjector`, plus
   `SwiftLayout.EnumLayoutBridge` wiring them into the same `StaticTypeLayoutResolver`/
   `TypeLayoutInfo` pipeline `FieldMap.swift` already consumes for structs/classes
   (`Sources/SwiftDecompilerCore/FieldMap.swift:1-4,251-263`; `Package.swift:117-138` already
   lists `SwiftLayout` as a dependency but not its sibling `SwiftInspection`). These are
   independent ports of the exact same `Enum.cpp`/`EnumImpl.h`/`TypeLowering.cpp` algorithms mined
   above, arrived at with their own citations to the same lines. The highest-leverage next step is
   adding `.product(name: "SwiftInspection", package: "MachOSwiftSection")` to
   `SwiftDecompilerCore`'s dependencies and writing a differential test that runs
   `EnumLayoutCalculator`/`SpareBitAnalyzer` against this document's hand-derived expected values
   for a handful of fixture enums (no-payload, XI-covered single-payload, tag-byte single-payload,
   spare-bit multi-payload, generic/tagged multi-payload) — proving the dependency's behavior
   before building anything on top of it, per the project's verification discipline. **Caution**:
   verify against the pinned commit's actual source (`git show 287886a9:Sources/...`), not the
   live `.build/checkouts` working tree, which sits 304 commits ahead on `main` — the same
   pinned-to-main risk flagged in the project's memory index for this exact dependency, this time
   confirmed to be a fast-forward (not an orphaned/rebased commit) but still worth re-verifying
   before bumping the pin.

2. **Prefer `__swift5_mpenum` over structural recomputation whenever both are available.** §4.2's
   last paragraph: when the compiler emitted a `MultiPayloadEnumDescriptor`
   (`Records.h:427-537`), it is exact, compiler-computed ground truth — read it directly rather
   than re-running the AND-across-payloads spare-bit gather. Use the structural algorithm only as
   the documented fallback (generic/resilient payloads, no builtin descriptor), which is also
   exactly when the runtime itself falls back to a plain trailing tag (§4.1) — a decompiler that
   sees no `__swift5_mpenum` entry for a type should *expect* a plain tag and can cross-check its
   own structural computation against that expectation.

3. **Extend `EnumCaseIndex`'s decline contract to payload enums, in two tiers, not one.** §6.4
   identifies two distinct failure modes (layout-unknown vs. specific-XI-pattern-unknown) that
   the project's own diagnostics discipline ("never emit one message for several causes") says
   must render differently. Build the closed table of known extra-inhabitant encodings (class
   references first — the highest-value, fully closed-form case per §2.2/§3.3) before attempting
   struct/`String` payload XI decoding, which needs a type-by-type table with no general formula.

4. **Give the multi-payload spare-bits tag-extraction pattern its own recognizer, separate from
   `isMaskedByte`.** §6.3: the existing `mask <= 0xff` heuristic
   (`Disassembler.swift:1568-1571`) is correctly scoped to no-payload/tag-byte enums (byte-aligned
   masks) and will not fire on a genuine spare-bits `ubfx`/shifted-mask sequence, which is
   typically *not* byte-aligned. Key the new recognizer off a specific enum type's known
   `spareBitsMask` (from `__swift5_mpenum` or `SpareBitAnalyzer`) rather than a generic bit-count
   threshold, so it never misfires on an unrelated bitfield extraction that happens to be enum-tag
   shaped.

5. **Do not use `RuntimeEnumCaseProjector` in the static analysis path.** It works by loading the
   target's metadata into the *analyzing* process and driving the enum's own
   `destructiveInjectEnumTag`/`getEnumTag` witnesses live (its own doc comment,
   `RuntimeEnumCaseProjector.swift:1-40` at the pinned commit) — appropriate for swiftdc's existing
   `dlsym`-based differential-oracle *tests* (`docs/PRODUCTION-READINESS.md:787,790` already
   describes exactly this kind of execution-based verification, used "in tests" only), but a
   correctness- and safety- mismatch for the main disassembly pipeline, which must stay
   non-executing and work on arbitrary/foreign binaries per the project's stated architecture.
   Reserve it for building the fixture ground-truth table in recommendation 3, and for the
   differential oracle in recommendation 1 — not for anything that runs during ordinary
   `swiftdc disasm`/`layout`.

6. **Reference-storage width fix, if any exists today.** No current swiftdc code was found
   computing `weak`/`unowned` field widths independently of `SwiftLayout` (a repo-wide grep for
   reference-storage-specific size logic in `Sources/` found none), so this is preventive rather
   than a fix: if/when swiftdc ever hand-computes a reference-storage field's width instead of
   deferring to `SwiftLayout`, §5's table (all four kinds are one pointer word; only XI
   count/bitwise-takability differ, and `weak` is the one kind that is genuinely not
   bitwise-takable) is the reference to check it against — a hand-rolled "weak is two words"
   assumption would be exactly the kind of one-word aggregate error the project's CLAUDE.md calls
   out as the highest-severity mistake class.

---

## Verification notes

- **Reproduce the arm64 Darwin ABI constant table (§2.2)**: grep
  `/Users/camden/swift/stdlib/public/SwiftShims/swift/shims/System.h` for
  `SWIFT_ABI_DARWIN_ARM64_LEAST_VALID_POINTER`, `SWIFT_ABI_ARM64_SWIFT_SPARE_BITS_MASK`,
  `SWIFT_ABI_ARM64_OBJC_RESERVED_BITS_MASK`, `SWIFT_ABI_ARM64_OBJC_NUM_RESERVED_LOW_BITS` — values
  are literal `#define`s, not computed, so a direct read is a full proof, not a sample.
- **Reproduce the `performBasicLayout` aggregate-composition claim (§1.4)**: read
  `/Users/camden/swift/stdlib/public/runtime/Metadata.cpp:2662-2721` end to end; every accumulator
  (`isPOD`, `isCopyable`, `isBitwiseTakable`, `isBitwiseBorrowable`, `isAddressableForDependencies`,
  `alignMask`, `size`) is a single `for` loop with no branches that could special-case an unusual
  field — the pseudocode in §1.4 is a direct transcription, not a summary.
- **Reproduce the single-payload crossover rule (§3.1)** with a live compiler: `swiftc -emit-sil`
  on `enum E { case a(SomeXIExhaustedType); case b; case c }` for a payload with 0 XIs and 2 empty
  cases should show a tag byte; the same shape with a class payload and 1 empty case should not.
  `docs/PRODUCTION-READINESS.md:787` already documents this SIL-based confirmation technique as
  used once, manually, for a related claim (`rank` lowering) — the same technique applies here.
  Not run as part of this pass; flagged for whoever implements recommendation 1's differential
  test.
- **Verify the "already vendored" claim (§0, §7.1)** without trusting this document: `cd
  /Users/camden/compiler && grep -n SwiftLayout Package.swift` (expect line 135) and `cd
  .build/checkouts/MachOSwiftSection && git show 287886a9:Package.swift | grep -n
  'library(.SwiftLayout\|SwiftInspection ='` (expect both products declared at the pinned
  commit). Re-run before relying on it — dependency pins move.
- **What this document does not cover**: `lib/IRGen/GenEnum.cpp` (the compiler-side codegen that
  *emits* the spare-bit mask into `__swift5_mpenum` in the first place) was not read directly —
  `TypeLowering.cpp` was treated as authoritative for the algorithm on the strength of its own
  "ported from GenEnum.cpp" framing and its agreement with the runtime's independently-written
  formulas (`getEnumTagCounts`, the single-payload crossover) everywhere they overlap. If a future
  discrepancy surfaces between `__swift5_mpenum`'s actual emitted bytes and this document's
  structural algorithm on a real binary, `GenEnum.cpp` is the next place to read, not this file.
  `docs/ABI/TypeLayout.rst` was read (302 lines) but is narrative/introductory and added no claim
  not already sourced from the header/source files above; not cited further since every fact it
  states is more precisely re-derivable from the code itself.

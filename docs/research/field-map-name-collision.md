# Field-map name collision fabricates wrong field names (correctness bug)

> Found while probing the `--structured` raw-register conditions (which turned out
> coverage-bound — see the bottom of this note). **FIXED with the decline-on-
> collision stopgap at `c7d8be1`** (scope + result at the end); qualified keys
> remain the precise follow-up.

## Symptom

`InterfaceReconstructor.Options.showCImportedTypes.getter` renders

```swift
return (self.rawValue & 1)
```

But `InterfaceReconstructor.Options` is a plain `struct … : Sendable` with `Bool`
stored properties (`showCImportedTypes` at offset 0, `fieldOffsets` at offset 1) —
**there is no `rawValue`**. The correct render is `self.showCImportedTypes`. The
name `rawValue` is a **fabrication**.

## Root cause — bare-name keying collides across types

`FieldMapBuilder.build` (FieldMap.swift:263) keys every type by its **bare** name:

```swift
let name = Self.name(of: type, in: machO)   // descriptor.name(in:) — bare, e.g. "Options"
maps[name] = FieldMap(typeName: name, layout: layout)
```

`maps` is `[String: FieldMap]` keyed by simple name, so **two types with the same
last component overwrite each other** — last writer wins. The self-host has a
dependency OptionSet keyed bare `Options` (`rawValue: Su` @ 0x0, size 8), which
wins the key over `InterfaceReconstructor.Options` (whose own small packed-`Bool`
layout the calculator couldn't resolve anyway, so it has no map of its own).

`namedFieldMap` then makes it worse with a bare-last-component fallback:

```swift
fieldMaps[typeName] ?? typeName.split(separator: ".").last.flatMap { fieldMaps[String($0)] }
```

So `InterfaceReconstructor.Options` → `fieldMaps["Options"]` → the wrong OptionSet →
offset 0 names `rawValue`. Any type sharing a simple name with another indexed type
is exposed to this.

## Fix directions (for the next iteration — verify before shipping)

1. **Qualify the keys.** Key `maps` by the fully-qualified name (module + nesting),
   and resolve `namedFieldMap` against the qualified self-type name. Most correct,
   but touches every field-map lookup.
2. **Decline on collision (minimal, decline-over-guess).** At build time, if a bare
   name is about to be set to a *different* layout than an existing entry, mark it
   ambiguous and remove the key — so a colliding name resolves to nothing and the
   getter declines (blank) instead of naming the wrong field. Cheaper; costs the
   (correct) resolution of the winning type on collided names only.
3. Drop / tighten the bare-last-component fallback in `namedFieldMap` (it converts a
   qualified miss into a bare-name collision).

Recommended: **(1)** if the qualified name is cheaply available from the descriptor
context, else **(2)** as a safe stopgap. Add a positive fixture (two types with the
same simple name, distinct fields — each getter names its own field) and an
adversarial one (the collision must not fabricate). Sweep the self-host for other
`self.rawValue`/wrong-field renders before and after.

## Shipped: decline-on-collision stopgap (`c7d8be1`)

Chose **(2)**: qualified keying needs a coordinated refactor of the *lookup* names
too (they come inconsistently bare / qualified from `selfTypeFromDemangledName` and
`swiftValueTypeSelfFields`), a broad regression risk — so it stays the follow-up.

`FieldMapBuilder.build` now tracks the layout signature each simple name resolves
to; a name that receives **two different layouts is dropped** from the map, so an
ambiguous self-type declines instead of naming the wrong claimant's fields.

**Scope measured on the self-host:** of 1,954 nominal types / 1,534 simple names,
**95** names are claimed by >1 type and **38** by >1 with *distinct* layouts
(`Options`, `Layout`, `Storage`, `Iterator`, `Index`, `Node`, `Element`, `State`,
`Section`, `Symbol`, …). Clean same-target `--pseudo`: `self.rawValue` fabrications
26 → 17, **+222 bodies decline**. Those declines are overwhelmingly *fabrications*,
not correct renders — verified: the same field name was printed across many
unrelated owners (`self.tableSize` appeared on `AsyncMerge2Sequence.Iterator`,
`DequeModule.Deque.Iterator`, `_UnsafeBitSet.Iterator`, none of which have it). So
the guard is net strongly correctness-positive. `--structured` also un-folds the
raw calls (`os_unfair_lock_lock()`) that were previously hidden inside a fabricated
`self.field = …` — more honest.

**Residual for the follow-up:** the stopgap also drops the *one* claimant that
legitimately owned each collided name (it wins the key, renders correctly today).
Qualified keys would keep those while still declining the rest. It also does not
catch a name with a single *mapped* claimant plus layout-less claimers that fall
back onto it (only distinct *mapped* layouts trigger the guard) — qualified keys
fix that too.

## Qualified keys — increment 1 shipped (`0237af1`)

The earlier "too risky" verdict was re-examined and the *feasible* part shipped.
`FieldMapBuilder.qualifiedName` walks the descriptor's parent chain to the module
(`descriptor.parent(in:)` → `SymbolOrElement<ContextWrapper>`, naming each `.type`
via `name(of:)` and the `.module`; bailing to the simple name on a symbol /
extension / anonymous / opaque link). Verified the output matches the lookup format
for the register-decomposition path: `SwiftDecompilerCore.AnalysisReport`,
`MachOObjCSection.EntrySizeListHeader.Layout`, etc. — exactly what
`swiftValueTypeSelfFields` extracts.

The builder now **also indexes every type by its qualified name** (unique, so no
collision). A caller that already resolved a qualified self-type finds its OWN map
even when the simple name collided and was dropped — recovering the correct fields.
`HolderA.Pair.sum` → `self.alpha + self.beta` and `HolderB.Pair.total` → its own
fields, instead of declining. Self-host: blank 22,841 → 22,834, all changed lines
are recoveries, zero new fabrications.

## Increment 2 shipped (`1ec5872`) — feature complete

The class/pointer path resolved its self type via `selfTypeFromDemangledName` (a
*bare* last component), so it could not reach the qualified keys. Added
`qualifiedSelfTypeFromDemangledName` (same components joined from the module) beside
it over a shared `selfTypeComponents`, plus `selfFieldMap`, which prefers the
qualified key and falls back to the simple one — requiring the qualified name to
denote the SAME simple type, so a mismatch can never substitute another type's map.

`selfType` still returns the SIMPLE name (`vtableIndex` is keyed by it — changing
this would have broken vtable/self-accessor resolution); only its *resolution test*
widened to "either key reaches a layout", so a collided type is seeded as `self`
again instead of declining. `SelfTypeIndex` bindings were checked and are bare, but
need no change since the qualified name comes from the demangled name.

**Result — the collision thread is fully resolved, coverage *and* correctness:**

| metric | pre-collision | stopgap | +inc 1 | +inc 2 |
|---|---|---|---|---|
| blank bodies | 22,619 | 22,841 | 22,834 | **22,597** |
| getter field≠property mismatches | 135 | — | — | **95** |
| `self.rawValue` | 26 (9 fake) | 17 | 17 | **17** |

Blank bodies land *below* the original baseline: every over-decline recovered, plus
~22 types that previously resolved to the WRONG map. The original fabrication is
gone outright — `self.tableSize`, once printed across AsyncAlgorithms / DequeModule /
`_UnsafeBitSet` / MachOKit iterators that have no such field, now has **zero**
owners — and 40 further wrong-field getter renders became correct.

Regression tests: two nested `Pair` structs (register-decompose path) and two nested
`Holder` classes (class/pointer path) each resolve to their OWN fields, plus the
`FieldMap` collision unit tests on the guard itself.

## (Historical) qualified keys are too risky to force now

Checked feasibility. The descriptor exposes `parent(in:)`, but it returns a
`SymbolOrElement<ContextWrapper>` across type/protocol/anonymous/extension/module
cases — a real walk. The blocker is the *lookup* side: the names that reach
`namedFieldMap` are **inconsistent** — `selfTypeFromDemangledName` returns a single
bare component, while `swiftValueTypeSelfFields` returns a dotted qualified string,
and `SelfTypeIndex` bindings are their own thing. Qualified keys would require
normalizing every one of those to a single qualified format that matches a
parent-walk — a broad, regression-prone refactor. Per the loop's own guidance, do
NOT force it; it stays an open follow-up.

## Post-fix correctness sweep (this iteration, no new code)

Swept the fixed self-host for getters whose rendered `return self.X` field ≠ the
accessor's property name (the general fabrication signature). Findings:

- **rawValue fabrication fully fixed** — the 17 remaining `self.rawValue` renders
  are all legitimate rawValue owners (`ExitCode`, `DemangleOptions`, the `*Flags`
  OptionSets, `MetadataRequest`). No residual there, so the **stricter count-based
  guard (residual-(b)) is not warranted** — it would over-decline the winning
  claimants with no confirmed fabrication to fix.
- **`X → self.layout` (~40 getters)** — a *different, pre-existing* class:
  LayoutWrapper structs (`MachHeader` is `layout: mach_header` spanning all 28
  bytes) whose property reads `self.layout.<subfield>`, but the backing `__C`
  struct has no Swift field metadata, so the sub-field can't be named and the whole
  `self.layout` is rendered. Imprecise (wrong value/type), but a *real field name*,
  not a fabricated one. Fixing it needs C-struct field data (a feature).
- **Metadata union/offset mismatches** (`singletonMetadataInitialization →
  self.foreignMetadataInitialization`) — Swift context-descriptor union members
  that share (or neighbour) an offset; subtle, low-severity.

**Verdict:** the one clear *fabrication* class (collision) is fixed; the remainder
is imprecision/limitation, not wrong names. Correctness is in good shape. Next
target: the goto/structuring dimension (3,384 gotos), or the C-struct nested-field
resolution behind `→ self.layout`.

## Why this note exists: the conditions probe hit a plateau

The `--structured` raw-register conditions (73,977, ~70% of all `if (`) are **not** a
tractable naming slice:

- **~70% are compiler plumbing** — `getEnumTagSinglePayload`/`storeEnumTagSingle`
  value witnesses (3,114), generic `specialization` (6,988), `type metadata` (567),
  Codable machinery (`Decode`/`CodingKeys`/`encode`, ~1,000+). These manipulate raw
  enum tags by design; there is no source-level named value to recover.
- **Real typed-argument switches already render named** — `if (arg0 ==
  MemberCategory.functions)`, `if (arg1 == CPUType.arm)`. The enum-tag path
  (`ea788b0`) fires for arguments with a known enum type.
- **Real enum switch-on-`self` compiles to branchless code** — `isComparison`,
  `signedForm` lower to range checks / `csel`, so they render blank, not `if (w8 ==
  N)` chains.

So the remaining raw-`w8` conditions are diffuse value-coverage holes (the tracer
left the compared register unnamed) with no dominant tractable pattern — matching
`value-unknown-causes.md`. **The condition-naming frontier is coverage-bound; accept
it as a plateau.** The higher-value next work is the correctness bug above: a wrong
render outranks an unnamed one.

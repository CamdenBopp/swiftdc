# Swift name-mangling grammar — ground truth for swiftdc symbol classification

> Research artifact. Not production code. Every claim below cites a `file:line` in the
> canonical `swiftlang/swift` checkout at `/Users/camden/swift` (read-only; not modified by
> this pass) or in swiftdc itself. Per the project's authority hierarchy, this document is
> rank 4 (research documentation) — verify against current source before acting on it, and
> update this file in the same change if it drifts.

## 0. Scope and pinned revisions

| Repo | Revision | Scope studied |
|---|---|---|
| `swiftlang/swift` (canonical, read-only) | `1b7bd8eaf460396047c2644d1d69afb4a404b13d` (`main`, 2026-09-07) | `docs/ABI/Mangling.rst`, `lib/Demangling/{Demangler,Remangler,NodePrinter}.cpp`, `include/swift/Demangling/{Demangle.h,DemangleNodes.def,Demangler.h,ManglingMacros.h}` |
| swiftdc (this repo) | `a711f4e729fb814ea33b32eb66bd42dacc464305` (`research/swift-source-mining`) | `Sources/SwiftDecompilerCore/Disassembler.swift`, `Pseudo.swift`, `Package.swift` |
| vendored demangler swiftdc actually links | `MxIris-Reverse-Engineering/swift-demangling` at `.build/checkouts/swift-demangling` | spot-checked only, to confirm swiftdc's dependency exposes the same `Node.Kind` vocabulary and printed wording as canonical `NodePrinter.cpp` |

**Important caveat up front**: swiftdc does not link Apple's C++ demangler. Per
`/Users/camden/compiler/Package.swift:57,137`, it depends on the third-party Swift
reimplementation `swift-demangling`, and its one call site is
`Sources/SwiftDecompilerCore/Disassembler.swift:3241-3243`:

```swift
guard let node = try? demangleAsNode(s) else { return nil }
let printed = node.print(using: preset.options)
```

Everything cited below is grammar/semantics from the *canonical* compiler, which is the
correct ground truth for what a mangling **means**. Whether the vendored port implements
every construct identically has to be verified independently for the specific construct
in question — one spot check (§5.1) found matching wording; that is not a blanket
guarantee.

---

## 1. Top-level mangling structure

```
mangled-name ::= '$s' global   // Swift stable mangling
mangled-name ::= '_T0' global  // Swift 4.0
mangled-name ::= '$S' global   // Swift 4.2
mangled-name ::= '$e' global   // Embedded Swift (unstable)
mangled-name ::= async-main-entry-point
```
— `swift/docs/ABI/Mangling.rst:11-16`.

A Mach-O symbol table additionally prefixes a leading `_` (the platform's C symbol
convention), so what swiftdc actually sees on disk is `_$s...`, `_$e...`, or bare
`$s...` depending on how the reader strips the leading underscore. The compiler's own
prefix table, used by every prefix-detection entry point, is:

```cpp
llvm::StringRef prefixes[] = {
  /*Swift 4*/   "_T0",
  /*Swift 4.x*/ "$S", "_$S",
  /*Swift 5+*/  "$s", "_$s",
  /*Swift 5+ Embedded Swift*/  "$e", "_$e",
  /*Swift 5+ for filenames*/ "@__swiftmacro_",
};
```
— `swift/lib/Demangling/Demangler.cpp:185-191`, consumed by
`getManglingPrefixLength` (`Demangler.cpp:182-200`) and `isSwiftSymbol`
(`Demangler.cpp:217-225`). The stable-mangling literal `$s` is also `#define`d as
`MANGLING_PREFIX` at `swift/include/swift/Demangling/ManglingMacros.h:24-25`.

**The one prefix-free symbol**: `async_Main`, the entry point that runs a program's
top-level `async` code, carries no prefix at all (`Mangling.rst:24-27`; the literal is
`#define ASYNC_MAIN_ENTRY_POINT_NAME "async_Main"` at `ManglingMacros.h:101`). It is
still treated as a mangled name everywhere a mangled name is expected, because its async
funclets append the ordinary funclet suffixes (`async_MainTY1_`, `async_MainTQ0_`,
`async_MainTu`, …) — `Mangling.rst:29-30`, and `getAsyncMainEntryPointNameLength`
(`Demangler.cpp:206-215`) explicitly handles the Mach-O leading-underscore variant
`_async_Main`.

**How a global symbol is built.** After the prefix, mangling is a postfix-order sequence
of "operators": `4Test3FooC` means identifier `Test`, identifier `Foo`, then the trailing
operator `C` says "the thing built from those two identifiers is a class" —
`Mangling.rst:32-43`. The grammar bottoms out through:

```
global   ::= entity | (many operator-suffixed forms of "global" / "type" / "nominal-type" / "protocol-conformance")
entity   ::= nominal-type | context entity-spec static? curry-thunk?
context  ::= module | entity | entity module generic-signature? 'E'
```
— `Mangling.rst:369-370` (entity), `Mangling.rst:492-494` (context). The recursive-descent
parser mirrors this exactly: `Demangler::demangleOperator()`
(`swift/lib/Demangling/Demangler.cpp:1110-1218`) is the single dispatch point every
mangled character stream feeds through; `'T'` routes to
`demangleThunkOrSpecialization()` (`Demangler.cpp:1173`, implemented at
`Demangler.cpp:3024-3300+`), `'W'` routes to `demangleWitness()` (`Demangler.cpp:1175`,
implemented at `Demangler.cpp:3773-...`), and `'M'` routes to `demangleMetatype()`
(`Demangler.cpp:1165`, implemented at `Demangler.cpp:2640-2739`). Every classification
construct in §2 is a leaf of one of these three dispatchers (or of `demangleAccessor`,
§2.3). A control byte in `0x01-0x0C` is intercepted even earlier, before falling into any
of these — see §3.

---

## 2. Suffix / classification reference table

This is the table swiftdc should maintain as its own internal `enum` (see §5). Each row
cites where the *grammar* declares the operator, where the *parser* recognizes it (which
`Node::Kind` it becomes — this is the value a classifier should switch on, not the
printed string), and where the *printer* renders it (useful only for knowing what text a
human sees; **not** a stable classification surface — see §5.1).

### 2.1 Dispatch, bridging, and protocol-witness thunks

| Suffix | Meaning | Decoded implication | Grammar | Parser → `Node::Kind` | Printer text |
|---|---|---|---|---|---|
| `Tj` | Resilient method dispatch thunk | The symbol is *not* the method body; it's a stable ABI entry point that indirects through a class/protocol's dispatch mechanism so the real implementation can move between library versions. A decompiler should attribute the call, not the logic, to this symbol. | `Mangling.rst:244` | `case 'j': DispatchThunk` — `Demangler.cpp:3036` | `"dispatch thunk of "` — `NodePrinter.cpp:1459-1462` |
| `Tq` | Method descriptor | Not executable code at all — a runtime *data* record (`MethodDescriptor`) used for resilient dynamic dispatch lookups. If a decompiler finds this symbol at a call site or as a function, it must not treat it as a callable function body. | `Mangling.rst:245` | `case 'q': MethodDescriptor` — `Demangler.cpp:3037` | `"method descriptor for "` — `NodePrinter.cpp:1463-1466` |
| `To` | Swift-as-ObjC thunk | An Objective-C-callable shim wrapping a Swift method — the real Swift calling convention differs (register/ARC differences); `self` arrives via the ObjC convention (`x0`), not Swift's `self`-in-`x20` convention. **Does not get its own "thunk" node** — it's modeled as an attribute (`ObjCAttribute`) decorating the wrapped entity, and prints as an `@objc ` prefix, not as "thunk of …". | `Mangling.rst:248` | `case 'o': ObjCAttribute` — `Demangler.cpp:3038` | `"@objc "` — `NodePrinter.cpp:1863-1865` |
| `TO` | ObjC-as-swift thunk | The inverse bridge: an ObjC method exposed with a Swift-convention entry point. Also modeled as an attribute, not a thunk node. | `Mangling.rst:247` | `case 'O': NonObjCAttribute` — `Demangler.cpp:3039` | `"@nonobjc "` — `NodePrinter.cpp:1860-1862` |
| `TW` | Protocol witness thunk | The function that satisfies one protocol requirement for one conforming type in one conformance — i.e. a witness-table slot's actual implementation (or a thunk to it). Two identities are packed in: the requirement being satisfied and the conformance it's satisfying it under. | `Mangling.rst:263` | `case 'W': ProtocolWitness` (children: conformance, entity) — `Demangler.cpp:3081-3085` | `"protocol witness for " <entity> " in conformance " <conformance>` — `NodePrinter.cpp:2107-2112` |
| `TS` | Protocol self-conformance witness thunk | Same idea as `TW`, but for a protocol that is asserting conformance to itself (`P: P`) — a narrower, historically newer case worth distinguishing from an ordinary witness. | `Mangling.rst:264` | `case 'S': ProtocolSelfConformanceWitness` — `Demangler.cpp:3086-3088` | `"protocol self-conformance witness for "` — `NodePrinter.cpp:2102-2105` |
| `TD` / `Td` | Dynamic dispatch thunk / direct method reference thunk | Class-dispatch cousins of `Tj`/method-ref thunks; same "not the real body" implication. | `Mangling.rst:249-250` | `DynamicAttribute` / `DirectMethodReferenceAttribute` — `Demangler.cpp:3040-3041` | `"dynamic "` / `"super "` — `NodePrinter.cpp:1866-1871` |

### 2.2 Witness-table and associated-type accessors

| Suffix | Meaning | Decoded implication | Grammar | Parser → `Node::Kind` | Printer text |
|---|---|---|---|---|---|
| `Wl` | Lazy protocol witness table accessor | A runtime-callable function (not data) that lazily materializes/caches a witness table for `(type, conformance)` the first time it's needed. Its presence signals resilient/lazy conformance — the vtable isn't statically laid out. | `Mangling.rst:206` | `case 'l': LazyProtocolWitnessTableAccessor` (children: type, conformance) — `Demangler.cpp:3813-3818` | `"lazy protocol witness table accessor for type " <type> " and conformance " <conf>` — `NodePrinter.cpp:2055-2060` |
| `Wt` | Associated type metadata accessor (**HISTORICAL** — the grammar itself marks this obsolete) | Returns the metadata for one associated type of one conformance. Being HISTORICAL, live binaries built by current compilers should rarely emit it; seeing it implies an old codegen path or an old dependency. | `Mangling.rst:203` | `case 't': AssociatedTypeMetadataAccessor` — `Demangler.cpp:3828-3833` | `"associated type metadata accessor for " <name> " in " <conf>` — `NodePrinter.cpp:2576-2581` |
| `WT` | Associated type witness table accessor | The current (non-historical) mechanism: returns the witness table for one associated type's own conformance to a further protocol. Three identities packed in: conformance, the associated-type path, and the protocol being witnessed. | `Mangling.rst:204` | `case 'T': AssociatedTypeWitnessTableAccessor` (children: conf, associated-type path, protocol type) — `Demangler.cpp:3834-3840` | `"associated type witness table accessor for " <path> " : " <proto> " in " <conf>` — `NodePrinter.cpp:2592-2599` |
| `Wa` | Protocol witness table accessor (**HISTORICAL**) | Predecessor of `Wl`; same "returns a witness table pointer, not a value" implication. | `Mangling.rst:195` | `case 'a': ProtocolWitnessTableAccessor` — `Demangler.cpp:3825-3827` | `"protocol witness table accessor for "` — `NodePrinter.cpp:2071-2074` |
| `Wb` | Base protocol witness table accessor | Retrieves the witness table for a protocol's inherited (base) protocol requirement, given a derived conformance. | `Mangling.rst:205` | `case 'b': BaseWitnessTableAccessor` — `Demangler.cpp:3841-3846` | `"base witness table accessor for " <proto> " in " <conf>` — `NodePrinter.cpp:2600-2605` |

### 2.3 Metadata accessors and descriptors

| Suffix | Meaning | Decoded implication | Grammar | Parser → `Node::Kind` | Printer text |
|---|---|---|---|---|---|
| `Ma` | Type metadata access function | A **function**, not the metadata itself — call it (idempotently) to get/instantiate the type's metadata pointer at runtime. Its presence in a call graph is compiler-inserted generic plumbing, not source logic. | `Mangling.rst:146` | `case 'a': TypeMetadataAccessFunction` — `Demangler.cpp:2642-2643` | `"type metadata accessor for "` — `NodePrinter.cpp:2528-2531` |
| `MU` | ObjC metadata update callback function | A callback the ObjC runtime invokes to fix up a class's metadata layout at class-realization time (used for classes with resilient/ObjC-visible layout). | `Mangling.rst:158` | `case 'U': ObjCMetadataUpdateFunction` — `Demangler.cpp:2727-2728` | `"ObjC metadata update function for "` — `NodePrinter.cpp:1471-1474` |
| `Mn` | Nominal type descriptor | **Data**, not code: the canonical runtime descriptor record for a struct/enum/class — field counts, generic parameter counts, access-function pointers, etc. A decompiler should render this as a data symbol / type-metadata table entry, never as a function body. | `Mangling.rst:153` | `case 'n': NominalTypeDescriptor` — `Demangler.cpp:2701-2702` | `"nominal type descriptor for "` — `NodePrinter.cpp:2614-2617` |
| `Mp` | Protocol descriptor | Same idea as `Mn`, for a protocol. | `Mangling.rst:166` | `case 'p': ProtocolDescriptor` — `Demangler.cpp:2708-2709` | (analogous "protocol descriptor for") |

### 2.4 Property/subscript accessors — correcting the task's shorthand

The task description's `fg`/`fs`/`fm` shorthand does not match the current grammar
literally. There is no `f`-prefixed accessor operator; accessors are the **`ACCESSOR`**
production appended directly after the entity-spec's own marker letter — `'v'` for a
variable, `'i'` for a subscript:

```
entity-spec ::= label-list type file-discriminator? 'i' ACCESSOR   // subscript
entity-spec ::= decl-name label-list? type 'v' ACCESSOR            // variable
```
— `Mangling.rst:402-403`. So a variable getter mangles as `...v` + `g` (i.e. the
substring `vg`, e.g. the tail of `...3fooSivg`), a subscript setter as `...i` + `s`
(`is`), and so on:

```
ACCESSOR ::= 'm'  // materializeForSet     ACCESSOR ::= 'r'  // _read
ACCESSOR ::= 's'  // setter                ACCESSOR ::= 'M'  // _modify (temporary)
ACCESSOR ::= 'g'  // getter                ACCESSOR ::= 'x'  // modify
ACCESSOR ::= 'G'  // global getter         ACCESSOR ::= 'y'  // yielding borrow (was 'read')
ACCESSOR ::= 'w'  // willSet                ACCESSOR ::= 'b'  // borrow
ACCESSOR ::= 'W'  // didSet                 ACCESSOR ::= 'z'  // yielding modify (was 'mutate')
```
— `Mangling.rst:410-424`. The parser confirms this is one shared accessor-suffix
dispatcher used by both variables and subscripts:

```cpp
NodePointer Demangler::demangleAccessor(NodePointer ChildNode) {
  switch (nextChar()) {
    case 'm': Kind = Node::Kind::MaterializeForSet; break;
    case 's': Kind = Node::Kind::Setter; break;
    case 'g': Kind = Node::Kind::Getter; break;
    ...
    case 'M': Kind = Node::Kind::ModifyAccessor; break;
    ...
```
— `Demangler.cpp:4241-4285`, called from `demangleVariable()` (`Demangler.cpp:4388-4390`,
appends after `'v'`) and `demangleSubscript()` (`Demangler.cpp:4393-4410`, appends after
`'i'`). Printed forms are single words: `"getter"`, `"setter"`, `"modify"`,
`"materializeForSet"`, `"willset"`, `"didset"`, `"read"`, `"yielding_mutate"`, …
(`NodePrinter.cpp:2800-2829`, via `printAbstractStorage`). Two accessor codes for the
coroutine-based modify convention coexist — `M` (`ModifyAccessor`, printed `"modify"`)
and `x` (`YieldingMutateAccessor`, printed `"yielding_mutate"`) — reflecting a mangling
that evolved as the modify-accessor calling convention changed;
**decoded implication for a decompiler**: a getter/setter pair changes nothing about a
function's *signature shape* (still `() -> T` / `(T) -> ()`), but `_read`/`_modify`
accessors are **coroutines** — they yield an address/reference mid-execution rather than
returning a value, which is a fundamentally different control-flow shape a decompiler
must not conflate with an ordinary return.

### 2.5 Partial-apply forwarders

| Suffix | Meaning | Decoded implication | Grammar | Parser → `Node::Kind` | Printer text |
|---|---|---|---|---|---|
| `TA` | Partial application forwarder | The trampoline a closure-capturing call site jumps through: it has already bound some arguments (captured in a context object) and forwards the rest to the real function. Its own "signature" is a lie about the source-level function's arity. | `Mangling.rst:183` | `case 'A': PartialApplyForwarder` — `Demangler.cpp:3045` | `"partial apply forwarder for "` (or `"partial apply"` when `Options.ShortenPartialApply`) — `NodePrinter.cpp:2114-2124` |
| `Ta` | ObjC partial application forwarder | Same, bridged for ObjC block/selector calling convention. Also the literal spelled out as `#define OBJC_PARTIAL_APPLY_THUNK_MANGLING Ta` at `ManglingMacros.h:52,94-95`. | `Mangling.rst:184` | `case 'a': PartialApplyObjCForwarder` — `Demangler.cpp:3044` | `"partial apply ObjC forwarder for "` — `NodePrinter.cpp:2125-2135` |

### 2.6 Reabstraction thunks

| Suffix | Meaning | Decoded implication | Grammar | Parser → `Node::Kind` | Printer text |
|---|---|---|---|---|---|
| `TR` | Reabstraction thunk (current) | Converts a function value between two different SIL representations of the *same* logical function type (e.g. a generic closure passed where a concrete one is expected, or vice versa) — no source-level semantic change, purely an ABI-shape adapter. Both "from" and "to" types are carried (`Mangling.rst:301-302`). | `Mangling.rst:270` | `case 'R': ReabstractionThunkHelper` — `Demangler.cpp:3089-3096` | `"reabstraction thunk "["helper "] "from " <T1> " to " <T2>` — `NodePrinter.cpp:2199-2220` |
| `Tr` | Reabstraction thunk (obsolete mangling) | Same meaning, legacy spelling. Seeing it implies old codegen. | `Mangling.rst:274` (obsolete), also `Mangling.rst:296-297` REABSTRACT-THUNK-TYPE `'r'` | `case (default, i.e. neither 'R' nor 'y'): ReabstractionThunk` — `Demangler.cpp:3089-3096` | same shape, kind `ReabstractionThunk` |
| `Ty` | Reabstraction thunk with dynamic `Self` capture | A reabstraction thunk that additionally closes over a dynamic `Self` type — relevant when the wrapped function is a method on a class that can be subclassed. | `Mangling.rst:273` | `case 'y': ReabstractionThunkHelperWithSelf` — `Demangler.cpp:3089-3104` | `"reabstraction thunk "` + self type — `NodePrinter.cpp:2228+` |

### 2.7 Optimizer specializations (`Tf`/`Tg`/`Ts`/…)

These are **not** a single suffix; they are a family under the shared `specialization`
production, and the exact letter encodes *which* specialization was performed and *which
SIL optimizer pass* produced the clone:

```
specialization ::= type '_' type* 'T' dropped-arg* 'g' SPEC-INFO   // generic re-abstracted specialization  → "Tg"
specialization ::= type '_' type* 'T' dropped-arg* 'G' SPEC-INFO   // generic, not re-abstracted             → "TG"
specialization ::= type '_' type* 'Ts' SPEC-INFO                    // generic re-abstracted prespecialization
specialization ::= type '_' type* 'Ti' SPEC-INFO                    // inlined function with generic substitutions
specialization ::= spec-arg* 'Tf' SPEC-INFO ARG-SPEC-KIND* '_' ARG-SPEC-KIND  // function-signature specialization
```
— `Mangling.rst:1349-1371`. Parser dispatch for all of these lives in
`demangleThunkOrSpecialization`'s `'g'`/`'G'`/`'B'`/`'t'`/`'s'`/`'i'`/`'p'`/`'P'`/`'f'`
cases (`Demangler.cpp:3105-3136`). Every one of them ends up printed via
`printSpecializationPrefix(Node, "<english label>", depth)` — e.g. `"generic
specialization"`, `"generic pre-specialization"`, `"function signature specialization"`,
`"inlined generic function"` (`NodePrinter.cpp:1875-1899`).

**The decoded implication that matters most for swiftdc**: `SPEC-INFO` embeds a
`PASSID` digit naming the exact SIL optimization pass that produced the clone —

```
PASSID ::= '0' AllocBoxToStack   '5' GenericSpecializer
PASSID ::= '1' ClosureSpecializer '6' MoveDiagnosticInOutToOut
PASSID ::= '2' CapturePromotion   '7' AsyncDemotion
PASSID ::= '3' CapturePropagation '8' PackSpecialization
PASSID ::= '4' FunctionSignatureOpts '9' EmbeddedWitnessCallSpecialization
```
— `Mangling.rst:1383-1392`. This means a symbol like `...Tf4...` is *provably* a clone
generated by `FunctionSignatureOpts`, with specific arguments constant-folded, boxed, or
exploded per `ARG-SPEC-KIND` (`Mangling.rst:1399-1410`, e.g. `'p' CONST-PROP` for a
constant-propagated argument, further broken down into function-symbol / global-symbol /
integer / float / string-literal / keypath constants at `Mangling.rst:1412-1418`). A
decompiler that decodes this can report *why* a function's signature looks unlike the
original source (e.g. "this parameter was constant-propagated away by
`FunctionSignatureOpts`; the source-level function took N arguments") instead of just
rendering a mangled specialization tail as noise.

**Naming collision to flag explicitly**: "specialization" here (an optimizer-pass clone,
`isFunctionAttr`-classified, `Demangler.cpp:124-163`) is a *different concept* from
"specialized" in `Demangle::isSpecialized(Node*)` (`swift/lib/Demangling/Remangler.cpp:4293-4349`),
which asks whether a **generic type/declaration is bound to concrete generic arguments**
(`BoundGenericClass`, `BoundGenericStructure`, …). Both are real, both matter to a
decompiler, and they are unrelated axes — don't conflate a "this is a generic
specialization pass clone" fact with a "this type has bound generic parameters" fact.

### 2.8 Key-path thunks

| Suffix | Meaning | Decoded implication | Grammar | Parser → `Node::Kind` |
|---|---|---|---|---|
| `TK` | Key path getter thunk | Backs a `\Type.property` key path's read access. Signature is the key-path-runtime calling convention (root pointer in, value out via indirect result), not the property's own accessor signature. | `Mangling.rst:275` | `case 'K': KeyPathGetterThunkHelper` — `Demangler.cpp:3137-3181` |
| `Tk` | Key path setter thunk | Backs a writable key path's write access. | `Mangling.rst:276` | `case 'k': KeyPathSetterThunkHelper` — `Demangler.cpp:3137-3181` |
| `Tkmu` | Key path unapplied method thunk | Backs `\Type.method` (an unapplied method reference used as a key path). | `Mangling.rst:277` | `nextIf("mu") → KeyPathUnappliedMethodThunkHelper` — `Demangler.cpp:3140-3141` |
| `TkMA` | Key path applied method thunk | Backs a curried/applied method reference used as a key path. | `Mangling.rst:278` | `nextIf("MA") → KeyPathAppliedMethodThunkHelper` — `Demangler.cpp:3142-3143` |

Printed as `"key path getter for "` / `"key path setter for "` / `"key path unapplied
method "` / `"key path applied method "` (`NodePrinter.cpp:2136-2149`); `Node::Kind`
entries confirmed at `swift/include/swift/Demangling/DemangleNodes.def:168-169`.

---

## 3. Symbolic references — the in-binary control bytes

Swift-emitted metadata (not ordinary function symbols in the symbol table, but mangled
names *embedded inside other metadata structures* — field descriptors, protocol
conformance records, etc.) can splice in a raw pointer instead of spelling out a nested
mangled name. This is a **binary-only** construct: it does not appear in symbol-table
names, only in mangled-name bytes read directly out of a loaded/mapped image.

```
symbolic-reference ::= [\x01-\x17] .{4}   // relative symbolic reference (4-byte offset)
symbolic-reference ::= [\x18-\x1F] .{8}   // absolute symbolic reference, 64-bit pointer
```
— `Mangling.rst:76-81`. A `\xFF` byte anywhere in this range is alignment padding and
must be skipped, not treated as data (`Mangling.rst:125-127`).

The currently defined kinds (`Mangling.rst:88-123`):

| Byte | Kind | Directness | Status |
|---|---|---|---|
| `0x01` | context descriptor (any generic type / protocol / opaque-type decl name) | direct | implemented |
| `0x02` | context descriptor | indirect | implemented |
| `0x03` | protocol conformance descriptor | direct | **NOT IMPLEMENTED** (grammar says so explicitly) |
| `0x04` | protocol conformance descriptor | indirect | **NOT IMPLEMENTED** |
| `0x05` | dependent associated conformance | direct | **NOT IMPLEMENTED** |
| `0x06` | dependent associated conformance | indirect | **NOT IMPLEMENTED** |
| `0x07` | associated-conformance access function, relative to protocol | direct | implemented |
| `0x08` | associated-conformance access function, relative to conforming type | direct | implemented (grammar wording only — see parser table below) |
| `0x09` | metadata/**accessor** function reference | direct | implemented (Swift ≥ 5.1) |
| `0x0A` | extended existential type shape (unique) | direct | implemented (Swift ≥ 5.7) |
| `0x0B` | extended existential type shape (non-unique) | direct | implemented (Swift ≥ 5.7) |
| `0x0C` | Objective-C protocol reference | direct | implemented |

The **parser's actual switch disagrees slightly with the doc's per-byte implemented/not
table** — worth flagging since the doc is rank-4 and the parser is rank-1 in this
project's authority hierarchy. `Demangler::demangleSymbolicReference`
(`swift/lib/Demangling/Demangler.cpp:1001-1069`) only recognizes:

```cpp
case 0x01: kind = Context, direct = Direct;
case 0x02: kind = Context, direct = Indirect;
case 0x09: kind = AccessorFunctionReference, direct = Direct;
case 0x0a: kind = UniqueExtendedExistentialTypeShape, direct = Direct;
case 0x0b: kind = NonUniqueExtendedExistentialTypeShape, direct = Direct;
case 0x0c: kind = ObjectiveCProtocol, direct = Direct;
case 0x03: case 0x04: case 0x05: case 0x06: case 0x07: case 0x08:
default:
  return nullptr;   // "These are all currently reserved but unused."
```
— `Demangler.cpp:1014-1047`. So **bytes 0x03–0x08 always fail to demangle** at HEAD,
regardless of what a resolver is supplied (the switch returns `nullptr` before ever
calling the resolver). This directly contradicts the doc's claim that `0x07`/`0x08`
(associated-conformance access function) are implemented — at this revision they are
not. **This is exactly the kind of doc/code drift this project's own authority hierarchy
warns about**; flag it if this doc is ever synced upstream, but for swiftdc's purposes,
trust the code: `0x03`–`0x08` are dead in the current parser.

**Which byte values even reach this switch at all.** The outer operator dispatcher only
special-cases `0x01`–`0x0C`:

```cpp
case 1: case 2: case 3: case 4: case 5: case 6: case 7: case 8:
case 9: case 0xA: case 0xB: case 0xC:
  return demangleSymbolicReference((unsigned char)c);
```
— `Demangler.cpp:1118-1120`. Bytes `0x0D`–`0x1F` (the rest of the doc's declared control
range, including the entire 8-byte "absolute reference" range `0x18`–`0x1F`) fall to the
switch's `default:` case, which pushes the byte back and calls `demangleIdentifier()`
(`Demangler.cpp:1214-1216`). `demangleIdentifier()` immediately rejects any non-digit
leading byte (`if (!isDigit(c)) return nullptr;` — `Demangler.cpp:1364-1365`), so those
bytes cause a **clean demangling failure**, not silent corruption or a crash. Only the
length-skipping helper `makeSymbolicMangledNameStringRef`
(`Demangler.cpp:165-180`) treats the full `0x01`–`0x1F` range generically (4-byte skip
for `0x01`-`0x17`, 8-byte skip for `0x18`-`0x1F`) — it is used purely to find where a
symbolic-reference-bearing string *ends*, not to interpret what the reference means.

### 3.1 What "resolved" requires, and why kind `0x09` is categorically different

The resolver hook is explicit about failing closed:

> "A function invoked to resolve symbolic references in the string. If null, then
> symbolic references will cause the demangle to fail."
— doc comments on `Demangler::demangleSymbol` / `demangleType`,
`swift/include/swift/Demangling/Demangler.h:725-726,740-741`. With no resolver installed
(the default — both overloads default the parameter to `nullptr`,
`Demangler.h:732-734,747-749`), **any** mangled name containing **any** symbolic
reference fails to demangle *in its entirety* — not just the referenced portion.

Given a resolver, the kinds differ fundamentally in what "resolve" can mean:

- **`Context` (`0x01`/`0x02`)**: the referenced bytes are the address (direct) or a
  pointer-to-the-address (indirect) of a **context descriptor** — a static data
  structure already sitting in the binary's read-only metadata section. Resolving this
  offline is a *read*, not an *execution*: given the base image and the 4-byte relative
  offset, an offline tool can locate and parse the referenced context-descriptor bytes
  itself, the same way the runtime does, with zero code execution.
- **`AccessorFunctionReference` (`0x09`)**: per its own doc comment, this is "a symbolic
  reference to an accessor function, **which can be executed in the process** to get a
  pointer to the referenced entity" — `swift/include/swift/Demangling/Demangler.h:434-436`
  (enum `SymbolicReferenceKind`, `Demangler.h:430-443`). There is no static data to read;
  the only way to get the real value is to **call the function pointer** and observe its
  return value at runtime (this is how the Swift runtime resolves, e.g., a lazily-emitted
  generic-metadata accessor embedded in a mangled name). Confirming this is not merely
  inference from the comment: even the canonical printer, when it does successfully
  resolve/construct an `AccessorFunctionReference` node, renders it as an **opaque
  numeric index**, not a name — `Printer << "accessor function at " << Node->getIndex();`
  (`swift/lib/Demangling/NodePrinter.cpp:3394-3396`). There is no code path anywhere in
  `NodePrinter.cpp` that turns kind `0x09` into a decoded declaration name.
- **`UniqueExtendedExistentialTypeShape`/`NonUniqueExtendedExistentialTypeShape`
  (`0x0A`/`0x0B`)** and **`ObjectiveCProtocol` (`0x0C`)**: like `Context`, these point at
  static runtime-shape data structures, in principle offline-readable given the binary
  and its section layout — but swiftdc would need to independently implement the layout
  parse (existential-shape records, ObjC protocol records) to do so; this document does
  not certify that swiftdc's Mach-O reader currently does.

**Bottom line for an offline tool**: `Context`/`0x0A`/`0x0B`/`0x0C` are *theoretically*
resolvable without executing anything, provided the tool independently parses the target
runtime record's binary layout. `AccessorFunctionReference` (`0x09`) is **not**
resolvable offline under any circumstance — the referenced value literally does not
exist as static data; producing it requires running the referenced code. `0x03`-`0x08`
are dead code at this revision (§3, above) regardless of directness.

---

## 4. Constructs swiftdc should render as unresolved, never fabricated

Per this project's core rule (declining rather than guessing), the following are
hard "must decline" cases grounded in the citations above, not judgment calls:

1. **Any symbolic reference of kind `AccessorFunctionReference` (control byte `0x09`)**
   encountered while reading a mangled name directly out of binary metadata. There is no
   static value to recover (§3.1). Render as `?` / "unresolved accessor reference",
   never as a guessed symbol name, and never as the numeric index alone dressed up as if
   it meant something to a reader (`"accessor function at " <index>` is the canonical
   demangler's own answer, and it is intentionally opaque —
   `NodePrinter.cpp:3394-3396`).
2. **Symbolic references with control byte `0x03`–`0x08`** — dead in the parser at this
   revision (`Demangler.cpp:1039-1047`); any name containing one fails to demangle by
   construction. Do not attempt a hand-rolled interpretation of the doc's grammar
   comment for these bytes; the implementation, not the doc, is the ground truth here,
   and the implementation refuses.
3. **A stripped or truncated symbolic reference** (fewer than 4 bytes remaining after the
   control byte for `0x01`-`0x17`, or fewer than 8 for `0x18`-`0x1F`) — the canonical
   parser bounds-checks this and returns `nullptr` rather than reading past the buffer
   (`if (Pos + 4 > Text.size()) return nullptr;` — `Demangler.cpp:1004-1005`). swiftdc's
   own binary reader must apply the same bound before slicing bytes out of a `LC_...`
   section, or it risks reading past a section boundary on truncated/corrupted input.
4. **Historical-only operators encountered on a modern binary** (`Wa`, `Wt`, `Tr`,
   `WG`/`Wr` and similarly marked `HISTORICAL`/`obsolete` in the grammar, e.g.
   `Mangling.rst:195,203,274,197,199`). These are still *parseable and printable*
   (nothing here says decline), but a decompiler that treats their presence as evidence
   of "current toolchain, standard codegen" is asserting something the grammar
   contradicts; the classification layer should carry a `historical: Bool` flag alongside
   the decoded kind rather than silently normalizing it away.
5. **Bytes `0x0D`–`0x1F`** appearing where a symbolic reference control byte is
   grammatically possible: the grammar reserves the full `0x01`-`0x1F` range
   (`Mangling.rst:67-68`) but the parser implements nothing above `0x0C`
   (`Demangler.cpp:1118-1120`) and any occurrence there is routed into
   `demangleIdentifier`, which rejects it (`Demangler.cpp:1364-1365`). Treat a name
   containing one of these bytes as "this binary encodes a symbolic-reference kind newer
   than what current tooling (and the current Apple demangler at this pinned revision)
   understands" — an honest "unresolved, future construct" diagnostic — not a demangling
   bug to paper over.

---

## 5. Recommendations for swiftdc, ranked

### 5.1 Classify on `Node.Kind`, not on the printed English string (highest priority)

swiftdc currently classifies demangled output by pattern-matching the **rendered text**
in at least two places:

- `Sources/SwiftDecompilerCore/Disassembler.swift:1413-1419` — `nonInstanceMarkers`,
  an array of literal strings (`" for "`, `" of "`, `"@objc "`, `"static "`, …) used to
  decide whether `x20` at a call site is a real `self` instance.
- `Sources/SwiftDecompilerCore/Pseudo.swift:418-465` (approx.) —
  `isGenericPlumbingCallee` / `isGenericPlumbingArgument`, matching prefixes like
  `"type metadata accessor for "`, `"lazy protocol witness table accessor "`,
  `"protocol witness table accessor "` against `node.print(using:)` output.

This works today (a spot check in §0 confirmed the vendored `swift-demangling` port's
`NodePrinter.swift:1003` matches the canonical wording for at least the lazy-witness-
table case), but it is coupled to a presentation detail two layers removed from swiftdc's
control: the canonical Swift compiler's own English phrasing (which this document shows
changes per `Node::Kind` — e.g. `"@objc "` carries *no* substring in common with "thunk"
even though `To` **is** a thunk per the grammar, `Mangling.rst:248` vs
`NodePrinter.cpp:1863-1865`), *and* the third-party port's independent reimplementation
of that phrasing. `nonInstanceMarkers` matching `"@objc "` but not `"@nonobjc "`
(`Disassembler.swift:1413-1419` vs. `NodePrinter.cpp:1860-1862`) is exactly the shape of
gap this produces: `TO`-thunked calls (ObjC-as-swift) are currently invisible to that
non-instance check, silently, because the check is string-shaped instead of
kind-shaped.

The vendored port's `Node.Kind` enum (`Sources/Demangling/Node/Node+Kind.swift` in the
`swift-demangling` checkout) mirrors the canonical `Node::Kind` cases named throughout
§2. **Recommendation**: add a classification pass that walks the `Node` tree returned
alongside (or instead of) the printed string, and switches on `.kind`. This is
categorically more stable than string matching and gives swiftdc, for free, every
implication column in §2's tables — "is this a thunk", "is this data not code", "does
this change the recovered argument count" — without depending on any particular English
rendering.

### 5.2 Build the classification enum directly off `isFunctionAttr`

The canonical compiler already ships the exact list swiftdc needs for "does this suffix
change what a function *is*, as opposed to just being part of its name":
`swift::Demangle::isFunctionAttr(Node::Kind)` (`Demangler.cpp:124-163`) enumerates every
`Node::Kind` that represents a specialization, ABI thunk, or dynamic-replacement marker —
`FunctionSignatureSpecialization`, `GenericSpecialization` (+5 variants),
`ObjCAttribute`/`NonObjCAttribute`, `PartialApplyForwarder`/`PartialApplyObjCForwarder`,
`MergedFunction`, `DistributedThunk`/`DistributedAccessor`,
`DynamicallyReplaceableFunctionImpl`/`Key`/`Var`, `AsyncFunctionPointer`,
`BackDeploymentThunk`/`Fallback`, `CoroFunctionPointer`, `DefaultOverride`, etc. This is
literally the compiler's own definition of "function attribute node" — mirroring it in
swiftdc's classifier (rather than re-deriving a similar list by hand) means swiftdc's
notion of "this symbol is a modified/derived function" tracks the compiler's own
definition, including future additions if swiftdc re-syncs this table against a newer
`swift` checkout.

### 5.3 Table to maintain, in priority order of "changes the recovered signature/role"

Ranked by how much a decompiler's *recovered signature or role* is wrong if it ignores
the suffix (highest-impact first — these are the ones "decline rather than guess" should
gate on):

1. **`_read`/`_modify` accessor kinds (`vr`, `vM`/`vx`/`vy`/`vz`/`vb`)** — control-flow
   shape (coroutine, not return) is wrong if misclassified as an ordinary
   getter/setter (§2.4).
2. **`Tf` function-signature specialization** — recovered parameter *count and types* are
   provably wrong versus the source-level function unless the `ARG-SPEC-KIND`/`PASSID`
   payload is decoded (§2.7); this is the single highest-value decode for "readable,
   source-like" output (priority 9 in `docs/PRODUCTION-READINESS.md`'s ordering) because
   it explains *why* a recovered signature doesn't match intuition.
3. **`TA`/`Ta` partial-apply forwarders** — recovered arity is a lie about the source
   function; the forwarder's own type is not the closure's logical type (§2.5).
4. **`Tq`/`Mn`/`Mp` and other descriptor suffixes** — these are not functions at all;
   treating them as callable is a category error, not just an imprecision (§2.1, §2.3).
5. **`To`/`TO` ObjC bridging** — calling convention (which register holds `self`) differs;
   directly affects any argument-recovery pass keyed on register position, as
   `Disassembler.swift`'s existing (string-based) `nonInstanceMarkers` check already
   demonstrates the *need* for, just not yet completely (§5.1).
6. **`TW`/`TS` witness thunks and `Wl`/`WT`/`Wa`/`Wb` accessors** — role (which
   conformance, which requirement) is recoverable and valuable for annotation, but a
   miss here degrades readability, not correctness of a signature.
7. **`TR`/`Tr`/`Ty` reabstraction thunks and `TK`/`Tk`/`Tkmu`/`TkMA` key-path thunks** —
   same tier: valuable annotation, calling convention is specialized
   (indirect/exploded), but getting it wrong is a readability defect, not a fabricated
   value.

### 5.4 Verification notes

- Every citation in this document was read directly from the pinned `swift` revision in
  §0; none are carried over from memory or from `docs/research/` prose. Re-run
  `git -C /Users/camden/swift rev-parse HEAD` before trusting a line number against a
  newer checkout — Demangler.cpp/NodePrinter.cpp line numbers drift across commits.
- The `0x03`-`0x08` doc/parser disagreement (§3) is itself a reproducible check: grep
  `Mangling.rst` for `NOT IMPLEMENTED` (lines 102-109) and compare against the `default:`
  fallthrough list in `Demangler::demangleSymbolicReference`
  (`Demangler.cpp:1039-1047`). Anyone can re-run this diff against a newer `swift`
  checkout to see whether Apple has since implemented associated-conformance symbolic
  references.
- This document does **not** verify that swiftdc's vendored `swift-demangling` port
  implements every `Node::Kind` and every printed string identically to canonical
  `NodePrinter.cpp` — only one case (`LazyProtocolWitnessTableAccessor`'s wording) was
  spot-checked (§0, §5.1). A full parity audit of the vendored port against this
  document's tables is unstarted work, not a claim made here.

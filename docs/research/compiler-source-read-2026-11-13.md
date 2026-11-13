# Reading the compiler against swiftdc, 2026-11-13

Thirty read-only agents, in two rounds of ten and twenty, each took one area of the Swift compiler checkout
(`swiftlang/swift`, the IRGen, SILGen, stdlib and runtime sources) and
compared what the compiler does with what swiftdc assumes. Each finding
names the compiler source line that states the rule, the swiftdc line
that differs, and a small source the agent compiled and rendered with
swiftdc da1 (0f1f69b).

Read the tables with this in mind. The findings are the agents' reports.
Two were reproduced by hand before this was written: the trap on a
top-bit bind addend (fixed in b814bc0) and the resilient struct rendered
from its fields. The rest are leads with a stated reproduction, not
measured facts. A fix lands only with its own fixture and a test seen
failing.

Paths are relative to the compiler checkout unless they start with a
swiftdc file name.

## Round one: wrong renders and crashes

These show something false, or stop the run. Ordered by how much real
code each touches.

| # | Area | The compiler's rule | What swiftdc showed | State |
|---|---|---|---|---|
| 1 | Runtime | The direct retain/release runtime binds `__swift_retainRelease_slowpath_mask_v1 + 0x8000000000000000` (`stdlib/public/SwiftDirectRuntime/RetainRelease.s:56`), a 64-bit import addend with the top bit set | SIGTRAP in every `disasm` view, `xrefs` and `analyze`: MachOKit's `addend` converts the field to `Int` | fixed, b814bc0 |
| 2 | Layout, arguments | In a library-evolution module every public non-`@frozen` struct and enum is address-only at every function boundary (`lib/SIL/IR/TypeLowering.cpp:2663`) | The struct is read out of registers by field: `f(_ s: RS, _ k: Int) { k &* 3 }` rendered `return (arg0.b + (arg0.b << 1))` | reproduced, open |
| 3 | Layout | A `$sBiN_WV` value witness table proves size and alignment, not that the value is an integer (`lib/IRGen/GenValueWitness.cpp:1479`) | A `swift_wrapper(struct)` typedef of `float` (the shape of `UIFont.Weight`) is placed in x0: `return (arg0 * 13)` for a function whose integer is in x0 and float in s0 | open |
| 4 | Interop | A value-type method's multi-word `self` follows its formals, and nothing is passed after it (`lib/IRGen/GenCall.cpp:1890`, `hasSelfContextParameter`) | `String._bridgeToObjectiveC("x", arg2)`: x2 is a stale entry value | open |
| 5 | Coroutines | A yield-once ramp's first parameter is its frame buffer, formals after it (`GenCall.cpp:1994`); a resume function takes only the buffer and a flag (`GenCall.cpp:910`) | `subscript.modify` rendered `mem64[arg0 + 0x8] = x1`; the resume funclet is seeded with x0 = arg0 and x20 = self | open |
| 6 | Accessors | A subscript setter is `(newValue, indices…, self) -> ()` | `self.a = …; return arg0` for a void setter | open |
| 7 | Results | A call to a `-> Never` callee ends its block; at -O no `brk` follows the `bl` (`lib/IRGen/IRGenSIL.cpp:4496`) | Two disjoint paths joined: `die2(arg1, 4); loc: die(?)` | open |
| 8 | Results | With a direct typed error, x0 is the result or the error (`GenCall.cpp:430`) | The error enum compared as if it were the result: `let r0 = f(arg0); if (error != nil) { …(r0 & 0xffffffff)… }` | open |
| 9 | Results | (swiftdc's own rule) a module named one capital letter is taken for a generic parameter | `return (R.p2(arg0) + 2)` for `p2(x).a + 2` | open |
| 10 | Specialization | A merged (`Tm`) function keeps its first function's substituted layout plus appended constants (`lib/LLVMPasses/LLVMMergeFunctions.cpp:899`) | A merged specialization for `Double` drops the d0 argument and shows the `Int` first | open |
| 11 | Specialization | Key path thunks have fixed shapes: getter (result, base, indices, size) (`GenCall.cpp:1929`) | The getter's x0 seeded from the printed subscript list; it is the base address | open |
| 12 | Runtime | `swift_retain_xN`, `swift_release_xN` and the bridge-object pair take their object in xN | `swift_retain_x21  args(arg0)`; only `objc_retain_xN` is modelled | open |
| 13 | Runtime | `swift_getWitnessTable` returns the table | A lazy accessor's store keeps the raw register: `if (x0 == 0) { mem64[…] = x0 }` | open |
| 14 | Stdlib | A small string's bytes from its count to 15 are zero (`stdlib/public/core/SmallString.swift:162`) | Two plain integers passed as a pair rendered `"CBA"` | open |
| 15 | Stdlib | An interpolation is one run from `init(literalCapacity:interpolationCount:)`; a nested one opens its own builder | `"a\("b\(x)c")d"` lost its outer `a`; `appendInterpolation` printed the builder as `self:`; `default:` dropped | open |
| 16 | Interop | A vtable slot names a requirement; a subclass's override table replaces it (`lib/IRGen/GenMeta.cpp:2363`) | A dynamic `blr` through the slot rendered as the base method by name, the same as a direct call, though a subclass in the image overrides it | open |
| 17 | Interop | Conformance flag bit 7 marks a conformance the Clang importer synthesized | `interface` prints it as module source: `extension __C.NSFileAttributeKey: @retroactive Swift.RawRepresentable` | open |

Item 2 has a hard limit worth stating now. A resilient module has the
same symbol names as a non-resilient one. The evidence is in the data:
a property descriptor (`MV`) holding a stored struct or class component
(tag 1 or 3) is emitted only under library evolution, as are `enum case
for …` (`WC`) symbols and method descriptors (`Tq`). A nonzero `MV` alone
proves nothing: a non-resilient class with `public private(set) var`
gets a computed component. So the fix can decline in an image that shows
that evidence, and a resilient image whose public types have no public
stored property, enum or class stays undetectable: a recorded
assumption.

## Round two: wrong renders

Twenty more areas. Several agents reached the same defect from different
sides; those are grouped, since one fix covers the group.

### A storage entity's type parsed as a parameter list

swiftdc splits a printed name at its first ` -> ` to get the parameters.
A storage entity prints `name.accessor : Type`
(`lib/Demangling/NodePrinter.cpp:3661`), and when the type is a function
type the arrow belongs to the type. Reported from the symbol-kinds,
globals, properties, errors, key path and round-one coroutine reads:

- `C.h.setter : (Int, Int) -> Int` is seeded with two integers and
  renders `self.h[0..<8] = arg0; self.h[8..<16] = arg1`. It takes a
  function value and self.
- A static property's addressor called from another module shows
  arguments (`S.limit.unsafeMutableAddressor(arg0, arg1)`); it takes
  none.
- A key path getter or setter for a function-typed property is seeded
  from the property's type.
- A throwing getter or subscript is judged non-throwing because the
  storage type's text has no `throws`. The error test after the call
  then folds to a constant: `return ((0 != 0) ? -8 : (r0 + 100))`. A
  `@_silgen_name` function (no dot in its name) fails the same way.

Rule: a top-level ` : ` before the first top-level ` -> ` means storage.
Seed nothing from that list, at entries and at call sites, and decide
"may throw" from the entity kind.

### Stores and calls hidden as runtime noise

Every callee whose name starts `outlined ` is hidden
(`Pseudo.swift`), as is every `boxed_opaque_existential` helper. Some of
them are the statement. Reported from the ARC, outlined-helper,
existential and class reads:

- `outlined init/assign with copy/take` are `(src, dest, metadata…) ->
  dest` (`lib/IRGen/Outlining.cpp:498`). A setter that stores through
  one renders `// no non-runtime calls (leaf / pure computation)`.
- `__swift_assign_boxed_opaque_existential_N(dest, src)` is `a = b` for
  an `inout any P`; the function renders empty.
- A subclass deinit's call to its superclass deinit disappears at
  -Onone, because the hidden consumer was what kept it visible.
- The empty-body message covers two causes: nothing there, and
  everything hidden.

Rule: one table classifying each hidden helper as identity, void
reference count, store or query, and hiding only the first two.

### Overflow-guard folding hides preconditions

`Structurer.swift` folds a branch to a trap on V or carry flags as the
compiler's overflow check, without checking the condition's sense, the
instruction that set the flags, or that they are integer flags:

- `precondition(a < b); return a &- b` (`subs; b.hs trap`) renders
  `return (arg0 - arg1)`.
- `precondition(!x.isNaN)` (`fcmp; b.vs trap`) vanishes: V after a float
  compare means unordered.
- A guard is folded when any `adds`/`subs` appears earlier in the block,
  even after a later `cmp` reset the flags. This is the likely mechanism
  of the open "bounds check dropped inside a loop" item.
- A tail branch to a merged body that can trap renders `return arg0`.

Rule: fold only when the last flag writer is the `adds`/`subs`/`negs`
itself and the trap edge is VS (or HS after an add, LO after a
subtract). Everything else is `if (cond) trap()`.

### Captures of a local function

A local function takes its captures after its formals, as a closure does
(`lib/SIL/IR/SILFunctionType.cpp:3017`). swiftdc bounds a call by the
callee's body only for names starting `closure #`. `$defer #1 ()` and a
named local function get a stale argument (`$defer #1 (arg0)`) or lose
their captures (`mix #1 (arg0)` for three arguments). Three agents hit
it.

### Others

| Area | The compiler's rule | What swiftdc showed |
|---|---|---|
| Concurrency | A `nonisolated(nonsending)` async function takes a hidden two-word isolation parameter before its formals (`SILFunctionType.cpp:1969`). The symbol does not record it, and under `NonisolatedNonsendingByDefault` every nonisolated async function has it | Formals seeded from x0: `await inner(?, (arg1 & 0xcfffffffffffffff))` for `inner(b, a)` |
| Concurrency | A `TQ`/`TY` funclet takes the context and the awaited callee's results | Seeded from its parent's formals when the chain is not recovered |
| Outlining | A machine-outlined fragment that only moves registers writes no x0 | Traced as a call whose result is x0 (`let r0 = OUTLINED_FUNCTION_11(?, ?)`), though the body summary proves x0 unwritten: the fact is read for tail branches only. This is the open "outlined helper given a false x0 result" |
| Outlining | x8 in an outlined fragment is caller scratch | Rendered `&result`, from x8 being seeded in every function |
| Metadata | A generic type's metadata accessor takes the request and at most three key arguments (`lib/IRGen/MetadataRequest.cpp:2595`) | Seeded from its body, undefined registers included: `__swift_instantiateGenericMetadata(arg0, arg1, arg3, arg3, …)` |
| Calls | A thick metatype formal is an ordinary argument | Stripped as generic plumbing: `sink(One<String>.self)` renders `sink()` |
| Casts | A cast to a generic type passes the accessor's arguments | The type is cut at the first parenthesis: `a as? Gen<T>` renders `as? C7.Gen`, `a is [T]` renders `as? Swift.Array` |
| Tail calls | `bl f; b swift_retain` is one call | Printed twice: `X(arg0)` then `return swift_retain(X(arg0))` |
| Errors | Cleanups run after `swift_willThrow`, merged at -O into the shared return block | The throw ends at its predecessor, so a `defer` store shows on the normal path only |
| Results | An indirect result beside a direct one is a leading pointer in x0, not x8 (`lib/IRGen/GenCall.cpp:1114`): `(some P, Int)`, `Box<T>.both() -> (T, Int)` | x0 seeded as the first formal |
| Witness calls | A witness takes formals, then Self metadata and Self table | The metadata word shown as an argument on a class-bound existential: `…witness for arg0(arg1, swift_getObjectType(arg0))` |
| Existentials | The assign helper overwrites the metadata word before using the old one | A load keeps its name after the store that replaced it |
| Collections | A specialized mutating method with no formals takes only self in x20 | Positional fallthrough: `Array._makeUniqueAndReserveCapacityIfNotUnique(self: arg0, arg0, arg1)`. The open -Osize Array item; the branch marks a call unproven only when its printed list is non-empty |
| Key paths | `swift_getKeyPath`'s second argument is undefined unless the pattern has arguments | Always shown |
| Reflection | "Reflection Metadata Level: without names" zeroes field names and keeps types (`lib/IRGen/GenReflection.cpp:949`) | Field types are keyed by name, so they collapse: `layout` shows a wrong type, renders print `self. = …`, every enum case reads "unavailable at run time" |
| ObjC sends | A struct argument of 9 to 16 bytes takes two registers | An untyped selector is laid out one register per colon: `[arg0 span:arg1 k:4]` for `span:{arg1, 4} k:9` |
| ObjC sends | Integers keep their registers after a float or generic parameter | Matched by parameter index: `[arg0 scale:arg3 at:?]` for `scale:arg2 at:arg3` |
| Bool | A Swift `Bool` has only bit 0 defined | `b ? 1 : 0` (`and x0, x0, #1`) renders `return arg0` |
| Deinit | A noncopyable struct's deinit takes a loadable self in x0 | Seeded in x20 |

## Round two: declines worth closing

- **Globals by name.** Absolute memory has a symbol (`…vp`, `…vpZ`), and
  an addressor returns that address. `mem64[0x80f8] = …` and `return ?`
  become the variable. Two agents named this first.
- **Closure contexts.** `swift_allocObject`'s metadata for a context is
  a `HeapLocalVariable` record pointing at a capture descriptor in
  `__swift5_capture`, which types every slot from +0x10. At -O an
  escaping closure's body is inlined into its partial-apply forwarder,
  which reads the context from x20: all of these render `return ?`
  today. Three agents named this.
- **Class initializers.** `init` is listed as an accessor suffix, so the
  self type never resolves and every initializer body renders
  `mem64[x20 + 0x10] = arg0 … return ?`. An initializing init has self
  in x20 and returns it; an allocating init has the metatype there.
- **Generic witness calls in apps.** They are named through method
  descriptors, which only resilient modules have. The existential path
  already falls back to protocol, index and kind.
- **Array, Dictionary and Set headers.** Count at +0x10, capacity at
  +0x18, elements from +0x20; the dictionary and set storage fields are
  in `shims/GlobalObjects.h`. Nothing is modelled, so `a.count`, bounds
  checks and every for-in body render `?`.
- **Payload enums in registers**, as parameters and as results of 17 to
  32 bytes: typed payload chunks, then the tag
  (`lib/IRGen/GenEnum.cpp:1558`).
- **A jump table's scrutinee** is the register its bounds check
  compared; the render says `switch (?)`.
- **Key path patterns**, decodable at each `swift_getKeyPath` site.
- **Throw sites**: `swift_willThrow`'s operand is the thrown error
  whatever produced it.

Confirmed matches in round two: multi-payload enum case encodings (16
returns over 11 enums), `swift_dynamicCast` argument order and flags,
exclusivity markers, the 15 read-through reference-counting entries,
ownership conventions never moving a register, witness table slot
numbering, default-actor storage, vtable and back-deployment thunks.

The per-area reports and a table of symbol kind against real signature
and swiftdc's behaviour were working files and are not in the
repository; each row above names the compiler source that states its
rule.

## Round one: declines worth closing

No false output, but the compiler's rule is simple and the case is
common.

- **Specialized methods of generic types.** A `Tg5` of a member of a
  generic nominal binds the context's parameters and `self` turns
  direct (`lib/SILOptimizer/Utils/Generics.cpp:869`). swiftdc needs a
  function-level generic signature, so every such method declines.
  These dominate -O binaries.
- **Witness tables after a struct formal.** Only a class instance or a
  thick metatype is a metadata source (`lib/IRGen/GenProto.cpp:411`). A
  formal such as `UnsafePointer<A>` or `[A]` fulfils nothing, so the
  tables still follow. swiftdc stops seeding tables there, and the
  witness call renders `indirect_call(?)`.
- **Class-constrained generics** are passed and returned directly
  (`GenProto.cpp:444`): `idc<A: AnyObject>(A, Int) -> A` renders
  `return ?`.
- **Async.** The context header's resume slot `[ctx+8]` cannot be
  aliased by a heap store, so the return through it stays provable
  (`GenCall.cpp:6664`). An async entry never uses x8: an indirect
  result's buffer is x0. The resume carries every result component, not
  one register. A default actor's executor is `(actor, 0)`.
- **Optionals by extra inhabitant.** `Bool?` is one byte with nil = 2,
  an optional no-payload enum's nil is its case count
  (`lib/IRGen/GenEnum.cpp:1237`), `String?` nil is `(0, 0)`.
- **Multi-register results.** Up to four components use x0…x3 and
  d0…d3 as independent banks (`GenCall.cpp:1107`).
- **Runtime entries.** `swift_getAtPartialKeyPath`,
  `swift_getAtAnyKeyPath`, `swift_continuation_await`, the two-word
  `SerialExecutorRef` in six signatures, the two-word result of the
  three key path coroutine ramps, and 30 first-parameter-returned
  entries that are not read through.
- **Blocks.** The literal's layout (invoke at +0x10, captures after the
  descriptor) and the invoke convention (x0 is the block).
- **Class vtables.** A subclass's table is its superclass's entries then
  its own; with a resilient superclass the offset is relative to the
  class's own members and needs a guard that is missing today.
- **Constant arrays at -O** are static objects with a known header
  (`lib/IRGen/GenConstant.cpp:491`).

## Confirmed matches

Checked against source and found to agree: argument order for generic
functions (formals, metadata, tables, self, error); `@objc` thunk
entries across 23 thunks at three optimization levels; struct, tuple and
class field layout (a 36-field struct equals `MemoryLayout.offset`);
enum field-record order and case numbering; value witness slots; opaque
existential layout; `swift_willThrow` taking its error in x21; arity and
void-ness of all 351 entries of `RuntimeFunctions.def` (diffed
mechanically; the `.def` itself is stale for `swift_unexpectedError` and
`swift_release_n`, and swiftdc has the header's version); async resume
kinds (`TQ`, `TY`); small-string discriminators and immortal large
literals.

## Oracles this turned up

Each is a closed set or an executable check that can give a fix a
denominator.

- `swiftc -emit-ir` `define` lines, already used by
  `Tools/ghidra-compare/interface_oracle.py`. They also carry
  `swiftcoro`, the return struct (the result registers) and the
  parameters after `swifterror` (an indirect typed error), none of which
  the tool reads yet.
- `clang -E` over `include/swift/Runtime/RuntimeFunctions.def` with a
  one-line `FUNCTION` macro: 351 rows of name, result and arguments.
  Cross-check the headers, since the `.def` is stale in two places.
- `include/swift/ABI/ValueWitness.def` and the flag enums in
  `MetadataValues.h` as the slot and bit tables for descriptor decoding.
- The `_invariantCheck` bodies in `StringObject.swift` and
  `SmallString.swift`: predicates a decoded string word pair must pass.
- `MemoryLayout<T>.offset(of:)` printed by a test program and diffed
  against `swiftdc layout`.
- `test/Demangle/Inputs/manglings.txt` and `DemangleNodes.def` as the
  set of thunk and specialization kinds.
- The FileCheck'd IRGen tests (`typed_throws_abi.swift`,
  `yield_once*.sil`, `async/`, `enum_resilience.swift`,
  `struct_resilience.swift`, `class_resilience.swift`) as ready-made
  corpora with the expected lowering written beside the source.

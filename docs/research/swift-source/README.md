# Swift compiler source mining

Ground-truth notes for [swiftdc](../../..), mined from the official
`swiftlang/swift` checkout at `/Users/camden/swift` (full clone, `main` at
`1b7bd8ea`, 2026-09-07). Every claim in these docs carries a
`/Users/camden/swift` `file:line` citation, so they sit at rank 4 of the
[authority hierarchy](../../../CLAUDE.md): hypotheses about the source, not the
source itself. Re-verify against HEAD before acting, and fix the doc in the same
change when a citation goes stale.

Generated 2026-09-08 by a seven-agent pass, one doc per area.

## The docs

| Doc | Covers | Sharpest swiftdc takeaway |
|---|---|---|
| [optimized-binary-lowering.md](optimized-binary-lowering.md) | `-O` transforms: specialization, function-signature-opt, outlining, reabstraction thunks, and identical code folding | ICF is a linker behavior the compiler *feeds* with `linkonce_odr` helpers; measured 16 distinct symbols on one `ret` address in `sample.release`. Name-by-nearest-symbol is unsound — detect same-address collisions first. |
| [mangling-grammar.md](mangling-grammar.md) | The mangling grammar, thunk/accessor/specialization suffixes, symbolic-reference control bytes | swiftdc classifies roles by matching *printed English*; move to `Node.Kind`. Symbolic refs `0x03–0x08` fail in the demangler and `0x09` is unresolvable offline: render `?`. |
| [type-metadata-layout.md](type-metadata-layout.md) | `__swift5_*` sections, nominal type descriptors, relative pointers, class field-offset vectors | Give `FieldDescriptorKind.ObjCClass` its own diagnostic; revisit the `dependencyClosure` trap on 0.19.0. Corrects a stale claim in Swift's own `docs/ABI/TypeMetadata.rst`. |
| [value-witness-enum-layout.md](value-witness-enum-layout.md) | Value-witness composition, extra inhabitants, single/multi-payload enum tag algorithms | The MachOSwiftSection dependency already ships the spare-bits engine as `SwiftInspection` (a 0.19.0 product swiftdc doesn't yet pull). Adopt-and-verify, don't re-derive. |
| [calling-convention.md](calling-convention.md) | Swift native CC on arm64, aggregate register lowering, ownership, returns | Confirms x20/x21/x22/x8 model. The "typed throws skips x21" gap was measured false (x21 stays the threw flag; only the payload moves to x0). Async results don't come back in x0 (now declined). |
| [async-coroutine-lowering.md](async-coroutine-lowering.md) | Async ABI, task runtime calls, `yield_once`/`yield_many` coroutine accessors, funclet naming | Three symbol-independent sections — `__TEXT,__swift_as_entry/_ret/_cont` — enumerate async funclets without the symbol table. `Tu`/`TQ`/`TY`, not `Ta`, are the async family. |
| [remote-mirror-and-speed.md](remote-mirror-and-speed.md) | Apple's out-of-process metadata reader (`MetadataReader`/`MemoryReader`) and its speed techniques | A ~2-method `MemoryReader` interface serves live process *or* static image. Cheap win: `Disassembler.demangle` has zero memoization. Cross-image lookups use "last-scanned-index" caches to stay linear. |

## A recommended ordering for acting on this

Ranked by the project's own priority ladder (soundness first, then completeness,
robustness, speed), and by cost:

1. **Same-address symbol-collision guard before naming** (soundness). The ICF
   measurement proves the current failure mode; the 0.19.0 vtable-by-descriptor
   fix is the upstream half. Cheap, high-leverage.
2. **Classify symbol roles on `Node.Kind`, not printed text** (soundness +
   robustness). Fixes the `Wy`→`WOy`-style staleness and the `@objc`/`@nonobjc`
   gap, and de-risks the just-completed swift-demangling 0.4→0.6.3 move.
3. ~~**Gate the x21 swifterror heuristic on typed-throws and async**~~ (soundness). Typed throws keeps x21 (measured); the real typed-throws defect was the signature parse, fixed with async return declines on 2026-10-09.
4. **Wire in `SwiftInspection`** for enum spare-bits layout and arm64e-verified
   case projection (completeness + correctness), now that 0.19.0 exposes it.
5. **Memoize `Disassembler.demangle`** (speed). Zero-caching today; a cheap win.
6. **Async-funclet enumeration via `__swift_as_*` sections** (completeness).
   Larger, but the payoff is naming async bodies the symbol table can't.
7. **A `MemoryReader`-shaped `ByteSource`** to unify file/cache readers, and a
   persistent cross-invocation cache (speed). The largest refactor; do last.

None of these is done here — this pass is research, not implementation. Each
item needs its own change, proven against a real fixture, per the verification
discipline.

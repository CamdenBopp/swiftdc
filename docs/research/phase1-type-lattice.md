# Phase 1 — a minimal per-value type lattice (guiding doc)

> One of the "guiding light" task docs. Scope, invariants, and evidence rules for the first
> architectural phase from `decompiler-comparison.md` §9. Companion to that study; cite it for *why*.
> Motivating defect: **U1** — an optimized signed range check (`x >= 0 && x < N`) lowered to an
> *unsigned* compare (`UInt(x) <ᵤ N`) was rendered as a *signed* `(x < N)` because ARM64
> condition-code signedness was discarded (`ValueTracking.swift` `comparisonOperator`).

## Goal (and explicit non-goals)

**Goal:** give values a small, conservative *type* so semantic facts travel with them, and use it to
render comparisons only when their Swift meaning is justified — fixing U1 generally.

**Non-goals this phase** (would be a rewrite; deferred, but the lattice is designed to receive them):
the full explicit-phi redesign, a loop structurer, the Optional model, and a *fully flowing*
type-state propagated through every instruction. Phase 1 establishes the **lattice type** and the
**two lowest-uncertainty evidence sources** (instruction cc + ABI signature); mid-body propagation
(sign/zero-extend/truncate/load/call producing typed results, met through the transfer function) is
Phase 2 and plugs into the same `ValueType.meet`.

## The type representation

```
struct ValueType {
    enum Category { integer, boolean, floatingPoint, pointer, enumeration, optional, unknown }
    enum Signedness { signed, unsigned, unknownSign }   // meaningful only for .integer
    var category: Category
    var width: Int?          // bits: 8/16/32/64, or nil = unknown width
    var signedness: Signedness
}
```

- `.unknown` category / `nil` width / `.unknownSign` are all **first-class** — the lattice bottom is
  "we know nothing" and every fact is optional. Conflicting evidence resolves *down* to unknown, never
  to an arbitrary pick.
- `meet(a, b)` (the join operation, used at CFG merges and to combine evidence): category agrees or
  → `.unknown`; width agrees or → `nil`; signedness agrees or → `.unknownSign`. "Preserve only facts
  supported by both." Idempotent, commutative, associative; `meet(x, unknown) = ` (x with facets the
  unknown side doesn't contradict) — concretely `meet` never *adds* a fact.

## Where each type fact comes from (evidence provenance — do not conflate these)

| Fact | Evidence | Trust |
|---|---|---|
| A parameter is `Swift.Int` → `integer, w64, signed` | **ABI/signature** (demangled type) | High — the source-level type |
| A parameter is `Swift.UInt`/`Swift.UInt32` → `unsigned` | **ABI/signature** | High |
| A comparison is unsigned (`<ᵤ`) | **Instruction** (ARM64 cc LO/HS/HI/LS) | High — the machine's own operation |
| A comparison is signed (`<`) | **Instruction** (cc LT/GE/GT/LE) | High |
| An immediate's category is integer | **Instruction/structure** | High for category; **signedness UNKNOWN** |
| A no-payload enum value | **Swift metadata** (`EnumCaseIndex`) | High |
| Small positive immediate "looks non-negative" | **Heuristic** | Low — never upgrade `.unknownSign`→`.signed` from this alone |

**Hard rule (stated because it is the trap):** an ARM64 register holding an integer-shaped value does
**not** tell us Swift's source-level signedness. Register shape ⇒ `integer`, width; it does **not** ⇒
`signed`. Signedness comes only from the signature (a typed parameter/return), from a signedness-
encoding instruction (sign/zero-extend, signed/unsigned compare/divide), or stays `.unknownSign`.

## What Phase 1 implements

1. `ValueType` + `meet` (representation; used by everything later).
2. `argumentTypes(of:) -> [Int: ValueType]` — computed **once** in analysis from the demangled
   signature, replacing the scattered render-site signature parsers (`swiftBoolArgumentIndices`,
   `swiftFloatArgumentInfo`, and the integer/pointer classification) with one typed source. This is the
   "stop rediscovering types from signatures in the renderer" move for the argument case.
3. `typeOf(AbstractValue, arguments:) -> ValueType` — structural: `.argument(i)` → `arguments[i]`;
   `.immediate` → `integer` with width by magnitude and **`.unknownSign`** (unless it is a comparison
   against a signed operand, resolved at the compare); `.binary(compareOp,…)` → `boolean`;
   `.unary(.negate,…)` → `signed`; float ops → `floatingPoint`; otherwise `.unknown`.
4. **Comparison operation signedness carried on the value:** add unsigned comparison operators
   (`.unsignedLess/.unsignedLessEqual/.unsignedGreater/.unsignedGreaterEqual`) to
   `AbstractBinaryOperator`; `comparisonOperator(cc)` returns the unsigned variant for LO/HS/HI/LS
   instead of collapsing onto the signed set. Signedness now *travels with the comparison value*.
5. **Render decision for an unsigned comparison** `x <ᵤ y` (in the boolean-simplification path — the
   one place comparison interpretation moves out of raw text assembly):
   - operand proven **signed** integer AND other side a **non-negative constant** `N` →
     recover the proven range idiom `((0 <= x) && (x < N))` (and `<=` → `x <= N`). This is the *only*
     high-level reconstruction, and it is provably equivalent (`x <ᵤ N ⇔ 0<=x && x<N` for `N < 2^63`).
   - operand proven **unsigned** → render normal `(x < y)` (correct for `UInt`).
   - signedness **unknown**, or a non-constant bound over a signed value → **expose the unsigned
     operation** honestly: `(UInt(bitPattern: x) < y)`. Never a bare signed `(x < y)`.
   - **signed** comparisons (LT/GE/GT/LE) render `<`/`>=`/`>`/`<=` exactly as before — unchanged.

## What is intentionally NOT raised (stays low-level / declines)

- Unsigned comparisons whose operand signedness we cannot establish → exposed as
  `UInt(bitPattern:)` comparisons, not silently signed.
- Mid-body sign/zero-extension and truncation of *non-argument* values (Phase 2 flowing state).
- Everything already declined (payload enums, tagged Optionals, structs, loops, …).

## Validation (semantic, not cosmetic)

- Fixtures: signed/unsigned comparisons near zero; the `x>=0 && x<N` idiom; Int8/UInt8/Int32/UInt32
  arguments (ABI sign/zero extension); a value whose signedness is unknown (must expose/decline).
- **Differential testing:** compile the fixture, evaluate the *original* and the *recovered*
  expression over `{Int.min, -1, 0, 1, N-1, N, N+1, Int.max}` and random inputs; assert equality.
  (This is the test that would have caught U1 — any negative input distinguishes `(x<10)` from the
  range check.)
- Regression: all existing boolean/enum/switch/ternary reconstructions must be byte-stable.
- Debug/`-O`/stripped; full suite; self-host crash + **over-firing scan** (count unsigned-compare
  renderings and spot-check against disassembly — a stable count is necessary, not sufficient).

## Forward compatibility (why this is not throwaway)

`ValueType.meet` is the merge a real **phi** will use at joins; `typeOf` is what a **simplification-
rule pool** will consult; `argumentTypes` is the seed a **flowing type-state** will propagate; the
unsigned operators are exactly what **stack-variable promotion** and **Optional modeling** need to
avoid re-deriving signedness. Nothing here is render-only.

## Stop condition

If the render decision cannot be made correctly with {argument types + operation signedness} — i.e.
if fixing U1 for the intended cases genuinely requires the flowing mid-body type-state — **stop and
report that evidence** rather than adding a narrower render patch.

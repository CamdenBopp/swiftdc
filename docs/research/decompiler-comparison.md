# swiftdc — Comparative Architecture Study vs Ghidra, Malimite, LittleSwift

> Research artifact. Not production code. Evidence-linked; conclusions cite source files,
> disassembly, SIL, or reproducible commands. Reproduce against the pinned revisions below.

## Reproducibility — pinned revisions

| Project | Revision | Scope studied |
|---|---|---|
| swiftdc (this repo) | `36a08da` | whole tree |
| Ghidra (decompiler C++ only, sparse) | `13a308a8f949010b64dd2799553e165136fefba6` | `Ghidra/Features/Decompiler/src/decompile/cpp` |
| Malimite | `f25b0a6267a2ae069cfac758362cd18b2072a276` | whole tree |
| LittleSwift | `952240c3605242ad5d32f88b9f8c139151ab060d` | `Sources/LittleSwift` |
| Swift toolchain | `xcrun swiftc` (Swift 6.3), arm64e-apple-macos | ground truth (SIL/asm) |

External repos live at `/Users/camden/decompiler-research/{ghidra,malimite,littleswift}` and the
comparison probe at `/Users/camden/decompiler-research/probes/constructs.swift`. They are **not**
vendored into this repo and are **not** runtime dependencies — research references only.

Ghidra was studied by reading its C++ decompiler source (a sparse checkout of just
`decompile/cpp`), not by running it: building/running full Ghidra headless (SLEIGH specs, Java,
Gradle) was out of scope for this pass, so Ghidra comparisons here are **architectural**, drawn from
its source, not from running it on our binaries. Malimite was studied likewise from source; running
it also requires a full Ghidra install. This is a real limitation of the comparison and is called
out where it matters. Our tool and the Swift compiler (SIL/asm) *were* run directly.

---

## 1. What swiftdc is today — the actual pipeline

swiftdc is a ~9,000-line Swift package. The reconstruction pipeline, per file:

```
Mach-O (MachOKit / MachOSwiftSection)
  │
  ├─ Capstone.swift / MachineDetail.swift   decode ARM64 → StructuredInsn (Capstone operands)
  ├─ CFG.swift                              basic blocks + successors from control flow
  │
  ├─ ValueTracking.swift  (ValueTracer)     ABSTRACT INTERPRETATION over the CFG:
  │     · AbstractValue lattice (indirect enum, ~20 cases)
  │     · per-block register/stack State, forward fixpoint with a `meet`
  │     · resolveDiamondSelects  → 2-arm CFG merge → .select
  │     · resolveSwitchSelects   → N-arm tag cascade → nested .select
  │     · FunctionAnalysis: callSites, exitValues, branchConditions, selfFieldAccesses, arrayElements
  │
  ├─ Metadata indexes (survive stripping):
  │     · FieldMap / FieldMapBuilder   byte offset → stored property (__swift5_fieldmd + SwiftLayout)
  │     · SelfTypeIndex                impl address → self type (class vtables)
  │     · VTableIndex                  (class, offset) → method address
  │     · EnumCaseIndex                no-payload enum → case names in tag order
  │     · MetadataSymbolizer           witness/metadata addresses → Type: Protocol.kind
  │     · ObjCMetadataIndex            ObjC classes/ivars/selectors
  │
  ├─ Disassembler.swift  (enrichCallArguments, 2,782 LOC — the largest file)
  │     · renderValue / renderBoolean  AbstractValue → Swift-ish TEXT
  │     · all the recent "folds" live here: enum case naming, ==/!=, &&/||, !, ternary,
  │       constant typing, negation, operand normalization, casts, array literals
  │
  ├─ Structurer.swift                  CFG → if/else/while (text back-substitution + baked cond notes)
  └─ Pseudo.swift / SwiftIdioms.swift  statement assembly, idiom folding, final --pseudo / --structured
```

The `AbstractValue` lattice (ValueTracking.swift:65-133) is the core representation:
`immediate, address, callResult, argument, loaded, selfField(offset), selfFieldValue(offset),
selfVTableMethod(offset), argumentField(arg,offset), select(cond,whenTrue,whenFalse),
arrayLiteral(site,count), binary(op,a,b), unary(op,a), aggregate([…]), frame(offset), unknown`.

**Key structural observation (returned to throughout this document):** swiftdc has *the beginnings of
an IR* — `AbstractValue` is a value graph, `.select` is a phi-like merge, the tracer is a real
abstract interpreter with a fixpoint. But **semantic analysis and textual rendering are not
separated**. Almost all recent higher-level recovery (enum naming, `&&`/`||`, negation folds,
constant typing, comparison normalization) lives in `renderValue`/`renderBoolean` inside the
2,782-line `Disassembler.swift`, i.e. it is performed *while emitting text*, bottom-up, with no
intermediate typed/simplified representation and no place to attach type, provenance, or confidence.
This is the central architectural tension the comparison illuminates (§7–§9).

---

## 2. Empirical comparison matrix

Probe: `/Users/camden/decompiler-research/probes/constructs.swift`, built `-Onone` and `-O`.
Command: `swiftdc disasm libC.dylib --pseudo -f <fn>`. Verdicts checked against disassembly and SIL.

| Construct | swiftdc (`-Onone`) | Verdict |
|---|---|---|
| `arith` a*b+a-3 | `(((arg0 * arg1) + arg0) - 3)` | ✅ correct |
| `clamp` x<0?0:x | `((arg0 >= 0) ? arg0 : 0)` | ✅ correct (ternary) |
| `maxOf` a>b?a:b | `((arg1 >= arg0) ? arg1 : arg0)` | ✅ semantically eq (= max) |
| `inRange` x>=0 && x<10 | `((arg0 >= 0) && (arg0 < 10))` | ✅ (`-Onone`); ⚠️ see U1 at `-O` |
| `either` a \|\| !b | `(arg0 \|\| !arg1)` | ✅ correct |
| `makeGreen` .green | `C.Color.green` | ✅ **differentiator** (enum case) |
| `isRed` c == .red | `(arg0 == C.Color.red)` | ✅ **differentiator** |
| `rank` switch c | `((arg0==.red)?1:((arg0==.green)?2:3))` | ✅ **differentiator**, SIL-confirmed |
| `locals` (var/let chain) | `((arg0 + 1) + ((arg0 + 1) * 2))` | ✅ value correct; ⚠️ locals inlined (L1) |
| `isEof` if case .eof (payload) | *declines* | ✅ honest |
| `orZero` x ?? 0 (Int?) | *declines* | ✅ honest (tagged optional) |
| `refOrNil` r != nil (class?) | *declines* | ⚠️ tractable gap (O1) |
| `dot` Point,Point (HFA) | *declines* | ⚠️ struct-param gap (S1) |
| `sum` Pair (GPR struct) | *declines* | ⚠️ struct-param gap (S1) |
| `sumArray` for-in | `makeIterator()` … (unstructured) | ❌ loop gap |
| `countUp` for _ in 0..<n | range-precondition assert (unstructured) | ❌ loop gap |
| `makeAdder` closure | `partial apply forwarder for closure #1 …` | ❌ closure gap (named, not reconstructed) |
| `applyTwice` f(f(x)) | `unresolved call ?` | ❌ closure-call gap |
| `totalArea` existential | `unresolved call ?` | ❌ protocol dispatch gap |
| `totalAreaG` generic <T:Shape> | `unresolved call ?` | ❌ witness dispatch gap |
| `mightThrow` throws | `swift_willThrow(swift_allocError(…))` | ❌ throw not structured (low-level, honest) |
| `fetch` async | `swift_task_switch(…)` | ❌ async not structured (low-level, honest) |

`-O` (optimization changes lowering): `maxOf → ((arg1 > arg0) ? arg1 : arg0)` ✅; `isRed` survives ✅;
`clamp`/`makeGreen`/`rank` decline (inlining/ICF) — honest; **`inRange → (arg0 < 10)` — DEFECT U1.**

### Cross-tool reading of this matrix

- **Plain Ghidra** on the same binaries would produce C: `local_8 = param_1 * param_2 + param_1 + -3;`
  and, crucially, would show `rank`/`isRed`/`makeGreen` as integer tag comparisons/returns
  (`if (param_1 == 1)`, `return 1`) with **no enum names**, because Ghidra has no Swift metadata
  model. It would structure the loops (`sumArray`) into real `while` loops (Ghidra's strength; our
  gap) and promote stack locals into named variables (`locals`, our L1 gap). It would show the
  throwing/async runtime calls as opaque C calls, like us but in C shape.
- **Malimite** (rev f25b0a6) would show *the same Ghidra C*, optionally class-namespaced and
  optionally passed through an LLM "translate to Swift" prompt — i.e. either Ghidra C or a
  non-deterministic model guess. It performs **no** Swift-metadata reconstruction of its own (§4).

So the matrix already frames the headline: **we win decisively on Swift-*value*-semantics (enums,
equality, Optionals-when-single-register, casts, field names), and lose decisively on control-flow
structuring (loops, switch-as-statement) and variable promotion**, which are precisely Ghidra's
mature, general strengths.

---

## 4. Malimite (rev f25b0a6) — findings

Full study in `findings-scratch.md`. Malimite is a **Java Swing GUI that orchestrates headless
Ghidra** (`analyzeHeadless` + a `DumpClassData.java` post-script streaming JSON over a TCP socket)
into a **SQLite** store, with an optional **LLM** "translate/summarize/find-vulns" pass
(`AIBackend.java`). Evidence for the claims that matter to us:

- **No Swift metadata parsing.** No reads of `__swift5_*` anywhere; no reconstruction of Swift
  types/enums/protocols/witness tables/existentials/generics/async/throwing. The only Swift-runtime
  awareness is `RuntimeMethodHandler.java` — a static list of `_swift_*`/`_objc_*` names used purely
  for **syntax highlighting**, driving zero reconstruction.
- **Demangling is a naive length-prefix splitter** (`DemangleSwift.java`): drops `_$s`, takes the
  first length-prefixed identifier as "class", concatenates the rest as "method". No types, labels,
  generics, or accessors; invokes neither `swift-demangle` nor Ghidra's demangler.
- **Mach-O parsing is minimal** (`Macho.java`): fat header + slice extraction only; no load
  commands/sections/symtab — all delegated to Ghidra. ObjC = Ghidra's analyzer output (namespaces).
- **Output is annotated Ghidra C** (comment headers, renamed classes, colored runtime calls, an
  ANTLR-derived xref table over the C text). The only Swift-*shaped* output is the LLM guess.

**Conclusion:** For Swift *semantics*, Malimite is essentially **not prior art** — it is orchestration
+ presentation + LLM around Ghidra. This makes swiftdc's metadata-driven Swift recovery genuinely
ahead of the leading public Swift/ObjC RE tool. **Worth borrowing** (all orchestration, not
reconstruction): headless-Ghidra-as-a-service with a scripted back-channel; SQLite as the queryable
analysis substrate; library/framework skip-by-namespace-prefix; parsing the decompiler's own output
with a real grammar to derive xrefs when richer IR is absent; an explicit, prompt-driven LLM
readability layer kept *separate* from deterministic analysis.

---

## 5. LittleSwift (rev 952240c) — findings for IR design

Full study in `findings-scratch.md`. LittleSwift compiles a strict *subset* of Swift (no
classes/structs/protocols/generics/enums/closures/collections/optionals/loops/comparison-or-logical
operators; only `+ - * /`). Its value as prior art is as a **destination-shape** reference, read
against the fact that a compiler has complete typed source and a decompiler has lossy machine code.

Key structural facts and their lessons:

- **The AST is an OPEN protocol hierarchy** where `Expression` is the universal supertype of
  literally everything — types, statements, declarations all conform. Dispatch is a runtime
  `as?`-ladder repeated in Sema/IRGen/Interpreter with **no exhaustiveness** (a missing node kind
  silently falls through). *Lesson: a decompiler IR must be the opposite — a **closed, exhaustive sum
  type** so the compiler forces every pass to handle every node, since ~most input is uncertain.*
- **Types live only on declarations, recomputed structurally, compared by string name**; literals
  are exact typed values (`Int → i32`, no width/signedness). *Lesson: exactly the unjustified
  certainty to avoid. A decompiler needs a **per-value type lattice** (`known(T) | oneOf([T]) |
  unknown`) carrying width and **signedness** — the same missing signedness that causes defect U1.*
- **AST lowers straight to LLVM with no intermediate IR.** *Lesson: the single thing NOT to imitate —
  a decompiler is all about the intermediate layers; having none is a property of starting from valid
  typed source.*
- **No provenance on any node.** *Lesson: provenance (originating address range + which recovery
  pass + confidence) must be a cross-cutting field on every IR node.*

**The proposed decompiler-IR node set** (LittleSwift's clean node *granularity*, its three
foundational choices inverted): a closed `enum Node` where every node carries
`{ type: TypeLattice, provenance: AddrRange+pass, confidence }`, with kinds — `Const`(raw
bits+width+candidate interpretations), `ValueRef`(SSA id + optional recovered name), `BinOp`(arith /
compare / logical / bitwise / shift — a superset of LittleSwift's four), `UnOp`, `Call`(target =
`direct | indirect(Expr) | unresolved(candidates)`), `MemberAccess`(base + field-or-offset),
`Load`/`Store`(raw memory, no source meaning yet), `Phi`/`Select`, **`RawOp`/`Unknown`** (the critical
escape hatch — always able to say "structure recovered, meaning not"), `Assign`/`Def`(+mutability tag
+ revisable inference cell), `If`(cond may be unknown + then + **else**), `Loop`(generic
header/body/latch/exits, **not** pre-classified as while/for), `Return`, `Block`, `FuncDecl`+`Signature`,
and a **separate** `TypeDescriptor` lattice never conflated with `Const`.

This node set is the backbone of the proposed evolution in §9.

---

## 3. Ghidra decompiler (rev 13a308a) — findings

Studied from the C++ source (`.../decompile/cpp`). The two files to read together are `docmain.hh`
(a prose spec of the 14-step pipeline, `\mainpage`, lines 16–423) and `coreaction.cc:5677`
(`ActionDatabase::universalAction` — the actual, ordered, executable pass list).

**Pipeline (14 steps).** (1) entry; (2) **raw p-code** — SLEIGH maps each instruction to a short
p-code sequence, control flow followed *off the p-code* via a work-list (`flow.cc`
`FlowInfo::generateOps`); (3) basic blocks/CFG on the p-code (`generateBlocks`); (4) sub-function
prototype recovery; (5) **make all effects explicit** — inject COPYs, call-effect p-code, `INDIRECT`
ops where a call's effect is unknown, rewrite RETURN to carry its value; (6) **the main
simplification loop** (repeat-to-fixpoint): 5a SSA (`ActionHeritage`), 5b bit-level dead-code, 5c
type propagation (`ActionInferTypes`), 5d term rewriting (the Rule pool), 5e CFG cleanup, 5f
structuring probe; (7) final p-code readability transforms; (8) **exit SSA / merge** low-level vars
into HighVariables; (9) explicit-vs-implicit expression decision; (10) casts to legalize;
(11) prototype/param ordering; (12) naming; (13) final structuring + emit C tokens.

**P-code** (`op.hh:63`, `opcodes.hh:37-132`): ~74 ops, each RTL op has ≤1 output, N inputs, explicit
sizes; philosophy = "one version of any operation, completely explicit about all effects" so the
data-flow engine sees flag-setting and sub-register writes as ordinary ops. Architecture is isolated
in three layers: **SLEIGH** (bytes→p-code, the only arch-specific path), `Translate::oneInstruction`
(the core never sees encodings), and **`TypeOp`/`OpBehavior`** (`typeop.hh:32-116`) which defines each
opcode's semantics *once*, reused for constant-folding, jump-table emulation, and printing. Key
internal (analysis-introduced, not translated) ops: `MULTIEQUAL`(60, φ), `INDIRECT`(61,
unknown-effect copy), `PIECE`/`SUBPIECE`(concat/truncate), `CAST`, `PTRADD`/`PTRSUB`(`[]`/`->`).
Booleans are **first-class** ops (`BOOL_NEGATE/XOR/AND/OR`, 37-40), separate from bitwise INT ops.

**SSA / heritage** (`heritage.hh:172-339`): textbook Bilardi–Pingali φ placement + Cytron renaming.
A φ is `CPUI_MULTIEQUAL`, and **input slot *i* corresponds to CFG in-edge *i*** — the
predecessor→value mapping. Built **incrementally**: registers heritaged first; stack slots discovered
later by rewrite rules, promoted to first-class Varnodes, then re-heritaged on a subsequent pass
(`LocationMap` records which pass each range entered SSA). **This edge-indexed φ is exactly the
information a `.select`/ternary discards.**

**Data-flow vs local interpretation:** cleanly split. Local per-instruction semantics live only in
SLEIGH and `TypeOp`; *all* cross-block reasoning is Action/Rule passes over the SSA graph. Because
every instruction's meaning (incl. flags) is already explicit p-code, global passes need no hidden
per-instruction knowledge. The jump-table emulator reuses the same `OpBehavior`, so local semantics
are defined exactly once.

**Stack & aliasing** (`heritage.hh`, `merge.hh`): a stack slot is just a Varnode in the `stack`
address space. Promotion is **deferred + incremental** — `RuleLoadVarnode`/`RuleStoreVarnode`
rewrite LOAD/STORE at a resolved offset to direct Varnode access, `ActionRestructureVarnode` makes
them first-class, next `ActionHeritage` SSAs them. A **HighVariable** is the *set* of SSA Varnodes
that hold one variable across registers/stack over its life. **Aliasing blocks promotion via explicit
data:** `INDIRECT` ops mark "value changed by an unknown effect"; `LoadGuard`/`storeGuard`
(`heritage.hh:137-170`) keep a `[min,max]` possibly-aliased stack range (refined by value-set
analysis) that prevents DCE/promotion; `StackAffectingOps` gates merges. Unknown effects are *ops in
the graph the passes must respect*, not silent assumptions.

**Constant/type propagation, DCE, simplification — the Rule system** (`action.hh:194-285`): every
simplification is a *named* `Rule` subclass advertising the opcodes it cares about
(`getOpList`); `coreaction.cc:5726-5864` registers ~150 of them into one `ActionPool` indexed
per-opcode (`perop[CPUI_MAX]`) and swept to fixpoint. Adding/removing a simplification = adding a
named class to one list — *no scattered special-cases*. Dead code is **bit-level** (each Varnode
carries `consumed` + `nzm` known-zero masks, `varnode.hh:156-157`) — undoes wide-register-holds-narrow
patterns. Type propagation (`ActionInferTypes`, `coreaction.cc:5589-5631`) is a **meet-semilattice
fixpoint bounded at 7 passes** with an explicit "not settling" warning rather than forcing a result.

**Condition recovery & selects** — the key answer for our `.select` question: Ghidra does **not**
eagerly ternary-ize joins. `get_booleanflip` gives complementary comparisons + operand reorder;
CBRANCH carries a `boolean_flip` polarity flag (branch polarity is data, not structure); named Rules
(`RuleBoolNegate`, `RuleLess2Zero`, `RuleEqual2Zero`, …) normalize comparison forms;
`ConditionalExecution` (`condexe.hh`) removes a redundant join CBRANCH while **pushing the affected
MULTIEQUALs into the correct successor** (preserving predecessor info). A ternary is manufactured in
exactly **one** place — `RuleConditionalMove` (`ruleaction.cc:9373-9500`) — which triggers *on a
`CPUI_MULTIEQUAL`* and only when both arms are provably side-effect-free single-use expressions; even
then it prefers to collapse to arithmetic/boolean (`zext(cond)`, `cond||other`). **The ternary is a
late, guarded, pattern-matched collapse of a φ — never the default join representation.**

**Control-flow structuring** (`block.hh`, `blockaction.hh`): the recovered structure is a **tree of
blocks** (`FlowBlock` with `block_type` = basic/goto/ls/condition/if/whiledo/dowhile/switch/infloop).
`CollapseStructure` repeatedly matches a structure template and collapses the subgraph to one node;
if stuck it deletes an edge and marks it unstructured — a **graph-collapse algorithm on arbitrary
reducible CFGs, not a lowering pattern-matcher**. Loops are found by back-edge analysis (`LoopBody`)
and labeled *before* structuring (innermost-first); `for` is a late transform on a `BlockWhileDo`;
unstructurable edges become explicit `goto`/labels chosen by `TraceDAG` bad-edge scoring.

**Jump-table / switch recovery** (`jumptable.hh`): **general and compiler-agnostic** — a `JumpTable`
tries a family of `JumpModel`s (`JumpBasic`, `JumpBasic2`, `JumpAssisted`, …). It recovers the switch
variable by **backward data-flow slicing** (`PathMeld` collects all p-code paths from the switch
Varnode to the BRANCHIND, finds common Varnodes), recovers its guarded value range, then **emulates**
the recovered computation (`EmulateFunction`, reusing `OpBehavior`) over each value to build the
address table. Because it emulates recovered arithmetic rather than matching a code shape, it handles
table-of-addresses, table-of-offsets, range guards, and multi-stage indices uniformly.

**Semantic vs pretty-printing** — a sharp, semantic-heavy/text-thin boundary. By print time the IR is
fully decided (HighVariables merged, explicit/implicit marked, casts inserted, names assigned, block
tree built). `PrintLanguage` (`printlanguage.hh`) walks the block tree (blocks
`emit()` themselves polymorphically) and an RPN `push`/`emit` stack handles expression precedence and
parentheses — *that* is the only genuinely textual work. `PrintC` is one back-end behind a
`PrintLanguageCapability` factory — **the natural seam to swap in Swift-shaped output.** So: control
shape, types, casts, variable identity = semantic (fixed before printing); parentheses, indentation,
keyword spelling = textual.

**Preserving "I don't know":** opaque instructions become `CALLOTHER` intrinsics printed as
functional `opname(args)` (`printc.cc:692-711`), not invented constructs; unknown memory effects are
explicit `INDIRECT`/guard ranges; type propagation can leave `TYPE_UNKNOWN`; unstructurable flow
becomes explicit `goto`/labels rather than a fake loop; bounded passes emit "not settling" rather
than forcing a result. **When it can't raise something, it prints the lower-level construct
literally.**

---

## 6. Confirmed strengths of swiftdc (verified, not assumed)

1. **Swift-metadata-driven value semantics that Ghidra and Malimite do not have.**
   - Enum case naming from `__swift5_fieldmd` tag order — `makeGreen → C.Color.green`, verified
     against SIL (`switch_enum` case order red→1/green→2/blue→3, EnumCaseIndex.swift). Neither Ghidra
     (no Swift model) nor Malimite (no metadata parse) does this.
   - Enum equality / no-payload switch as named ternaries (`rank`), stripping-survivable (field
     metadata isn't stripped).
   - Field names from offsets (`FieldMap`) surviving `strip` — `[x20,#0x10] → self.breed`.
   - `self`-type recovery from class vtables on **stripped** binaries (`SelfTypeIndex`).
2. **A conservative "decline, don't fabricate" discipline that actually holds at scale.** The matrix
   shows honest declines for payload enums, tagged Optionals, struct params — no manufactured Swift.
   Self-host `--pseudo` over ~338k lines is crash-marker-free.
3. **Faithful arithmetic/boolean value recovery**, including source-order recovery (operand
   normalization, `0-x → -x`, `&&`/`||`, `!`) gated to decline when evidence is insufficient
   (adversarial tests: `clampLow`/`maxOf`/`pickInc` do not fold to `&&`/`||`).
4. **A genuine abstract interpreter with CFG merge**, not just peephole pattern-matching — `.select`
   from diamonds and N-way tag cascades is a real (if narrow) data-flow result.

## 7. Confirmed weaknesses / unsound assumptions (verified)

- **U1 — unsigned comparisons render as signed (correctness defect).** `cset w_, lo` (unsigned
  lower-than) renders `(arg0 < 10)`. `comparisonOperator` (ValueTracking.swift:1447-1453)
  deliberately merges signed+unsigned condition codes. For `x >= 0 && x < 10` (compiled to unsigned
  `UInt(x) < 10`), our output evaluates differently from the machine at negative inputs — a
  manufactured signed reading. **This is a type-information defect**: signedness is a type property
  and `AbstractValue` carries no type on values.
  **✅ FIXED in Phase 1 (commit `2be9e31`, `docs/research/phase1-type-lattice.md`):** a `ValueType`
  lattice now carries signedness; `comparisonOperator` preserves the unsigned distinction (new
  unsigned operators); a signed operand compared unsigned against a non-negative constant recovers
  the range idiom `(0 <= x) && (x < N)` (differential-proven equal to the machine), a proven `UInt`
  renders `<`, and unknown signedness EXPOSES `x <ᵁ y` — never a fabricated signed compare. Real
  win found on self-host: a Mach-O magic check `self.magic <ᵁ 0xfffffffffade0000` (wrong as signed).
- **L1 — no variable promotion.** Stack locals are inlined bottom-up (`locals → ((arg0+1)+((arg0+1)*2))`,
  `(arg0+1)` recomputed) rather than promoted to named locals with a single definition. We have no
  HighVariable/SSA-name concept. Ghidra's HighVariable/merge is the mature answer.
- **S1 — struct parameters decompose only for instance methods.** HFA (`dot`) and GPR (`sum`) struct
  *parameters* of free functions decline; decomposition fires only in the value-self path. Real
  limitation.
- **O1 — single-register (nil-pointer) Optionals are not seeded.** `refOrNil (Ref?) → declines`,
  though `r != nil` is just `(arg0 != 0)`. `scalarParameterClass` treats only `Unsafe*` pointers as
  single-register; class/reference optionals (nil==0) are tractable to add (analogous to the pointer
  nil-coalescing already shipped).
- **Structural gaps (large):** loops/iterators, closures/captures, protocol/witness/existential
  dispatch, throwing structure, async state machines — all decline or stay low-level. Honest, but
  these are where a mature decompiler's general machinery (Ghidra) is far ahead.

## 8. Architectural debt exposed by the comparison

1. **Semantic analysis is entangled with text rendering.** The higher-level recovery lives in
   `renderValue`/`renderBoolean` (Disassembler.swift, 2,782 LOC), performed while emitting strings.
   There is no typed/simplified IR between `AbstractValue` and text, so: (a) each new construct is a
   new rendering special-case rather than a pass over a representation; (b) there is nowhere to
   attach type/signedness/provenance/confidence; (c) folds interact by ordering inside one giant
   function rather than as composable passes. U1 is a direct symptom (no place for signedness).
2. **`.select` is a phi that only exists for 2-arm diamonds and tag cascades.** It is not a general,
   predecessor-aware merge over SSA. It is reconstructed by two special-purpose CFG passes
   (`resolveDiamondSelects`, `resolveSwitchSelects`) rather than falling out of a heritage/SSA
   construction. This is exactly the "accumulation of special cases vs a coherent IR" risk the brief
   named — it is trending toward the former.
3. **Values have no type.** Signedness (U1), width, Optional-ness, enum-ness are recovered ad hoc at
   render sites (via signature parsing helpers: `boolArguments`, `floatInfo`, `enumCaseIndex`) rather
   than as a type lattice on values that passes can read and refine.
4. **No variable model.** No HighVariable / named-local / single-definition concept ⇒ L1, and a
   blocker for readable loops and closures.

---

## (sections 9–11 and the candid 7-point assessment follow once the Ghidra study lands)

---

## 9. Concepts worth adapting / not adapting, and a proposed evolution

### 9.1 Concepts worth adapting (in simplified form)

| From Ghidra | Adapt as | Why it fits swiftdc |
|---|---|---|
| Explicit, fully-effect op IR | Keep `AbstractValue` but make **effects explicit** (flags already are via `nzcv.flags`; make it a first-class value, not a state-key string) | Removes hidden per-instruction knowledge; U1's signedness would live on the op |
| **MULTIEQUAL φ, edge-indexed** | Replace `.select` *as the join representation* with a `phi([(pred, value)])`; derive `.select` only late, from a φ whose arms are pure + single-use | Directly answers the brief. `resolveDiamondSelects`/`resolveSwitchSelects` are re-inventing φ collapse as two special cases |
| Named-Rule fixpoint pool (`ActionPool`) | Move the `renderValue`/`renderBoolean` folds out of the printer into a **pool of named simplification rules over the value graph**, run to fixpoint before rendering | Fixes debt #1/#8. Each fold (enum-eq, `&&`/`||`, `0-x`, negation, operand-normalize, truthiness-peel) becomes a named rule, not an ordering-sensitive branch in a 2,782-line function |
| Bit-level DCE (`consumed`/`nzm`) | A known-zero/consumed-bits lattice on values | ARM64's `w`/`x` 32/64-bit register aliasing produces exactly the narrow-in-wide patterns this cleans; also the honest basis for width recovery |
| Bounded meet-semilattice type propagation | A **value type lattice** (`known(T) | oneOf | unknown` + width + **signedness** + enum/Optional/pointer facets), propagated with a hard pass cap | Fixes debt #3 and defect U1 at the root; unifies the ad-hoc `boolArguments`/`floatInfo`/`enumCaseIndex` signature helpers into one typed inference |
| Graph-collapse structuring + `LoopBody` | A block-tree structurer (`if`/`while`/`switch` as *objects*), loops labeled before structuring | The path to loops/switch-as-statement — our current `Structurer` is text back-substitution, not a block tree |
| Emulation-based jump-table recovery | Backward slice + reuse our own value evaluator to resolve `br`-through-table | Generalizes switch recovery beyond the two lowerings we hard-code today |
| `PrintLanguageCapability` seam | Keep a **thin Swift emitter** that walks a decided IR; move *all* semantic decisions out of it | The single most important structural move for us |
| Uncertainty as data (CALLOTHER, INDIRECT, TYPE_UNKNOWN, explicit goto) | A first-class `RawOp`/`unknown` that always lets the IR say "structure yes, meaning no" | We already *behave* this way (declines); make it a representable value, not the absence of output |

### 9.2 Concepts NOT to adapt (they assume C-shaped output)

- **C-precedence RPN expression model + C operator set** — Swift optionals (`?`/`!`/`if let`/`guard`),
  enum-payload matching, trailing closures, labeled args are not operator-precedence tokens.
- **`PTRSUB→->` / `PTRADD→[]` aggregate drill-down** — Swift value types, existential/witness tables,
  ARC class layout, and the pervasive runtime calls (`swift_retain/release/allocObject`, metadata /
  witness accessors) must surface as **Swift semantics**, not C pointer arithmetic or bare intrinsics.
- **Cast-to-legalize-C** — Swift casts are semantic (`as?`/`as!`/`is`), not a final print patch.
- **Register-coloring HighVariable merge tuned for C locals** — Swift's ARC/value-semantics mean "same
  variable" is often an ownership/lifetime fact; C merge heuristics will fuse semantically-distinct
  Swift values. Adopt the *concept* of a variable-as-a-set-of-defs, but not the merge scoring.
- **C metatype system and C-ABI prototype recovery** — Swift's `self`=x20, error=x21, `swiftcall`,
  indirect returns, and generic metadata/witness parameters need Swift-ABI models (which is exactly
  the MachOSwiftSection/ABI work swiftdc already leans on — a genuine advantage).

### 9.3 Proposed evolution of the internal representation and pass structure

The current shape (`AbstractValue` → `renderValue`/`renderBoolean` text) is a viable *foundation* but
is **one refactor away from a coherent IR and one refactor away from a pile of rendering
special-cases** — and it is currently drifting toward the latter (debt #1, #2, #8). The proposed
target keeps swiftdc's Swift-semantic strengths while adopting Ghidra's analysis invariants:

```
Layer 0  Decode        StructuredInsn (Capstone)                     [exists: MachineDetail/Capstone]
Layer 1  Op IR          explicit-effect ops incl. flags-as-value      [evolve ValueTracker's transfer fn]
Layer 2  SSA            edge-indexed phi([(pred,value)]) at joins      [replace .select-as-join]
Layer 3  Value graph    typed values: TypeLattice{known|oneOf|unknown,
                        width, signedness, enum/Optional/ptr facets}  [NEW — fixes U1, unifies helpers]
Layer 4  Simplify       named-rule pool → fixpoint (all current folds
                        move here as rules; bit-DCE; const/copy prop)  [move OUT of renderValue]
Layer 5  Structure      block tree if/while/switch (graph-collapse);
                        loop labeling; jump-table by slice+emulate     [evolve Structurer]
Layer 6  Swift raise    Swift-native semantic pass: enum cases,
                        Optional ops, casts, ARC elision, witness/vtable
                        dispatch, self/field naming                    [the differentiator; keep+grow]
Layer 7  Render         thin Swift emitter over a decided IR           [shrink Disassembler/Pseudo]
```

Every Layer-2+ node carries `{ type: TypeLattice, provenance: AddrRange + producing-pass,
confidence }`. The **critical invariants**: (a) joins are φ until Layer 5/6 decides expression-vs-
control; (b) no semantic decision happens in Layer 7; (c) an `unknown`/`RawOp` value is always
representable so any layer can decline into the next without fabricating.

This is an **evolution, not a rewrite**. Sequencing that pays its own way at each step:
1. **Introduce a value `TypeLattice`** (even minimal: width + signedness + {enum, Optional, bool,
   float, pointer, int} facet). Immediately fixes U1 and lets the signature helpers
   (`boolArguments`/`floatInfo`/`enumCaseIndex`) become type facts instead of render-site lookups.
2. **Lift the `renderValue`/`renderBoolean` folds into a named-rule pool** over the value graph, run
   to fixpoint pre-render. Mechanical, high-value: shrinks the 2,782-line file, makes folds
   composable and testable in isolation, kills ordering bugs.
3. **Replace `.select`-as-join with edge-indexed φ**; keep `.select` only as a *derived* Layer-6
   node. `resolveDiamondSelects`/`resolveSwitchSelects` become one φ-placement + one "φ→select when
   arms pure/single-use" rule (Ghidra's `RuleConditionalMove` shape).
4. **Only then** attempt loops (needs the block-tree structurer of Layer 5 + variable model) and
   Optionals/closures/existentials (need the type lattice + Swift-raise layer). These are the
   deferred items — attempting them on the current text-rendering foundation would deepen the debt.

## 10. High-value validation methods & regression tests

- **Semantic-equivalence, not textual-match, as the bar.** The `maxOf` case (`(arg1>=arg0)?arg1:arg0`
  ≠ source `a>b?a:b` but = `max`) shows text-diffing under-credits correct output. Add a harness that,
  for a fixture, evaluates the *recovered expression* and the *original function* over sampled inputs
  and asserts equality (differential testing). This would have caught U1 automatically (any negative
  input distinguishes `(x<10)` from `x>=0 && x<10`).
- **Adversarial "must-decline" tests are as important as "must-fire".** Already practiced
  (`threeWay`, `pickInc`, payload-enum); make it a standing rule that every raising feature ships a
  negative test proving it declines on the adjacent-but-unsupported shape.
- **Cross-optimization invariance.** Run each fixture at `-Onone`/`-O`/stripped and assert the
  recovered *semantics* agree (not the text). The `inRange` -Onone/-O divergence is exactly the class
  of bug this catches.
- **SIL/asm as ground truth for ABI assumptions.** Confirm every ABI rule (enum tag=decl index,
  Optional layout, self=x20, error=x21, HFA/GPR struct passing) against `swiftc -emit-sil`/`-S` before
  relying on it — resilience/payload/opt-level/version can change lowering. (Done here for enum tags.)
- **Signedness/width property tests.** Once the type lattice exists, property-test that unsigned
  machine comparisons never render as signed and vice-versa.
- **Scale + over-firing checks.** Self-host + a large framework `--pseudo`, crash-marker-free, is
  necessary but not sufficient; add "suspicious over-firing" scans (e.g. count enum-named returns,
  `&&`/`||`, selects, and spot-check a sample against disassembly, as done this session).

## 11. Open questions where evidence is insufficient

- **Does the type lattice pay for itself before loops/closures?** Strongly indicated (U1, the
  render-site helper sprawl), but not proven that step-1 alone yields enough to justify the churn
  before a second consumer exists.
- **Swift ARC modeling.** How aggressively can `swift_retain/release`/`bridgeObject` calls be elided
  from output without hiding real effects? Needs its own study (Ghidra's INDIRECT/unknown-effect
  model is the template, but ARC has known semantics we could exploit).
- **Witness/existential dispatch naming.** Whether a witness-table offset → protocol-requirement
  *name* is reliably recoverable from `__swift5_proto`/protocol descriptors (requirements don't
  obviously carry names) — needs a metadata deep-dive before committing.
- **Ghidra/Malimite actual output on our binaries.** This pass compared *architecture* (from source);
  a full headless-Ghidra run on the probe binaries would let us grade concrete output and quantify
  the loop/variable-promotion gap. Deferred (build weight).
- **Whether a block-tree structurer can be added without destabilizing the working text `Structurer`.**
  Unknown until prototyped on the loop fixtures.

---

## Candid assessment (plain English)

**1. What swiftdc does better than plain Ghidra and Malimite.**
Swift *value* semantics driven by Mach-O metadata, verified: naming enum cases
(`makeGreen→Color.green`), enum equality and no-payload switches as named ternaries, `FieldMap`
offset→property names that survive `strip`, `self`-type recovery from vtables, `as?`/`as!` casts,
homogeneous array literals, `&&`/`||`/`!`/ternary boolean recovery, and source-order arithmetic. Plain
Ghidra has no Swift model and shows these as integer tag comparisons and C pointer math; **Malimite
does no Swift-metadata reconstruction at all** (it is headless-Ghidra orchestration + optional LLM),
so its Swift output is either Ghidra C or a model guess. For Swift *semantic naming*, swiftdc is ahead
of the leading public Swift/ObjC RE tool. And it holds a genuine "decline, don't fabricate" line at
scale.

**2. What Ghidra/Malimite handle much more robustly.**
Everything *control-flow and variable* shaped, which is Ghidra's mature core: real SSA with
predecessor-indexed φ, bit-level dead-code, meet-semilattice type propagation, promotion of stack
slots to named variables with alias safety (INDIRECT/LoadGuard), graph-collapse structuring into
`if`/`while`/`switch` with `goto` fallback, and general jump-table recovery by slice+emulation. swiftdc
today inlines locals instead of promoting them (L1), has no loop/switch-*statement* structuring, and
recovers joins only for 2-arm diamonds and tag cascades. Malimite inherits all of Ghidra's robustness
for free by delegating.

**3. Which parts of our design are sound.**
The abstract-interpreter-with-CFG-fixpoint core, the metadata index suite (`FieldMap`, `SelfTypeIndex`,
`VTableIndex`, `EnumCaseIndex`, `MetadataSymbolizer`) that makes stripping-survivable recovery work, and
the conservative decline discipline. `AbstractValue` is a legitimate value-graph seed for a real IR.

**4. Which parts are likely to become dead ends.**
(a) Performing semantic recovery inside `renderValue`/`renderBoolean` while emitting text — this is
already a 2,782-line file accreting ordering-sensitive special cases and has no room for
type/provenance/confidence (it *caused* U1). (b) `.select` as the join representation — it discards the
predecessor mapping that copy propagation, type meet, and structuring all need, and it is being
extended by hand (`resolveDiamondSelects`, `resolveSwitchSelects`) instead of falling out of SSA.
(c) The signature-parsing render-site helpers (`boolArguments`, `floatInfo`, `enumCaseIndex`) as the
type mechanism — they should be one type lattice.

**5. The most important architectural investment to make next.**
A **value type lattice** (width + signedness + a Swift-facet: int/uint/bool/float/enum/Optional/ptr,
each `known|oneOf|unknown`) carried on every value, plus **moving the render-time folds into a named
simplification-rule pool run to fixpoint before a thin renderer**. These two together fix the confirmed
defect (U1), collapse the helper sprawl, shrink the giant file, and — critically — create the place
where loops/Optionals/closures can be built without deepening the debt. This is evolution, not rewrite.

**6. The best deliberately-scoped next feature after that foundation.**
Edge-indexed **φ replacing `.select`-as-join**, with `.select` derived only from a pure/single-use φ
(Ghidra's `RuleConditionalMove` shape). It is the prerequisite for both correct value-merging at joins
*and* the block-tree structurer that loops need — and it directly retires the two hand-written CFG-merge
passes. After that, **single-register (nil-pointer/class) Optional seeding** (O1) is a small, correct,
high-value win that the type lattice makes clean.

**7. How far from dependable Swift-body reconstruction.**
For *straight-line and branch/boolean/enum value code at `-Onone`* it is already dependable and, for
Swift naming, ahead of public tools. For *general function bodies* — anything with loops, closures,
Optionals across registers, protocol/existential dispatch, throwing structure, or async — it is **not
close**, and closing that gap is blocked on foundational work (type lattice, real φ, a variable model,
a block-tree structurer) that this comparison shows are well-understood, adaptable-in-simplified-form,
and worth doing in the order above rather than as more render-layer special cases. Realistically:
a few focused iterations to the type-lattice + rule-pool + φ foundation; then loops and single-register
Optionals become tractable; closures/existentials/async remain larger, later efforts that should not be
attempted until the foundation exists.

---

## Addendum (repo `9a15e35`) — correction from the Phase-4 probe

Phases 1–3 shipped: type lattice (§ assessment #5 first half), U1 fix, typeOf
precision, and O1 single-register reference-Optional nil checks (§ #6). Two
premises above were then **overturned by evidence** (see
`phase4-unify-value-and-structure.md`); recording the correction so this study
does not carry a falsified roadmap:

1. **A loop / block-tree structurer already exists.** #6/#7 treat "the block-tree
   structurer that loops need" as unbuilt. In fact `renderStructured` →
   `ControlFlowStructure` (Structurer.swift) already does natural-loop detection
   (back-edges + post-dominators) and emits `while`/`break`/`continue`/`goto`.

2. **The real gap is not "add loops" but two disjoint reconstruction layers.**
   The rich value reconstruction (`renderPseudo`/`AbstractValue`, what phases 1–3
   improved) and the control-flow structurer (`renderStructured`) are almost
   fully separate (`ControlFlowStructure` calls `renderValue` **0** times). A loop
   renders as a correct *shape* with an **empty body** — no `total += i`, raw
   `x9 >= x10` conditions, value-less `return`, overflow-trap noise. The pseudo
   path declines loops outright.

**Revised #5 / #6:** the next architectural investment is to **widen the one
existing value↔structure seam** (the `cond:` note that already lets a forward
`if` read `arg0 >= arg1`) to carry loops — represent loop-carried values (φ finds
its real consumer here), emit body updates, name loop conditions, and fold the
checked-arithmetic trap idiom. This is the "unified IR, not two rendering passes"
point (§8) made concrete. #7's bottom line is unchanged: general bodies (loops,
closures, existentials, async) remain far from dependable, and this is the
blocking foundational work — but the ordering is now "unify the layers," not
"build a structurer that already exists."

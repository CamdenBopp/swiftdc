# Investigation scratch notes (raw evidence — folded into the main doc)

Revisions:
- swiftdc project: 36a08da (HEAD at investigation start)
- ghidra (decompiler cpp, sparse): 13a308a8f949010b64dd2799553e165136fefba6
- malimite: f25b0a6267a2ae069cfac758362cd18b2072a276
- littleswift: 952240c3605242ad5d32f88b9f8c139151ab060d
- Swift toolchain: xcrun swiftc (Swift 6.3), arm64e-apple-macos

## Empirical matrix — our tool on /Users/camden/decompiler-research/probes/constructs.swift (-Onone)

STRONG (Swift-semantic recovery, verified):
- arith         return (((arg0 * arg1) + arg0) - 3)
- clamp         return ((arg0 >= 0) ? arg0 : 0)
- maxOf         return ((arg1 >= arg0) ? arg1 : arg0)      [= max(a,b), semantically eq to source a>b?a:b]
- inRange       return ((arg0 >= 0) && (arg0 < 10))         [-Onone form OK]
- either        return (arg0 || !arg1)
- makeGreen     return C.Color.green                        [DIFFERENTIATOR — enum case name]
- isRed         return (arg0 == C.Color.red)                [DIFFERENTIATOR — enum equality]
- rank          return ((arg0==.red)?1:((arg0==.green)?2:3)) [DIFFERENTIATOR — switch→ternary, SIL-confirmed]
- locals        return ((arg0 + 1) + ((arg0 + 1) * 2))      [locals INLINED, not promoted — see finding]

HONEST DECLINES (no fabrication — good):
- isEof (payload enum if-case)     -> declines
- orZero (Int? ?? 0, tagged)       -> declines
- refOrNil (class? nil-check)      -> declines
- dot (Point HFA free-function)    -> declines  [HFA decompose is METHOD-only; free fn not covered]
- sum (Pair GPR struct param)      -> declines

GAPS (low-level / unresolved — honest but incomplete):
- suitRaw    -> C.Suit.rawValue.getter : Swift.Int(arg0)  [names getter, awkward]
- sumArray   -> makeIterator() ... (loop body not structured)
- countUp    -> assertionFailure(range precondition) (loop not structured)
- makeAdder  -> partial apply forwarder for closure #1 ... (closure not reconstructed)
- applyTwice -> unresolved call ?
- totalArea / totalAreaG (protocol/existential/generic dispatch) -> unresolved ?
- mightThrow -> swift_willThrow(swift_allocError(...)) (throw not structured)
- fetch (async) -> swift_task_switch(...) (async not reconstructed)

## -O (optimization changes lowering)
- maxOf   -> ((arg1 > arg0) ? arg1 : arg0)            [OK]
- arith   -> (((arg0*arg1)+arg0)-3)                    [OK]
- isRed   -> (arg0 == C.Color.red)                     [OK — survives -O]
- clamp/makeGreen/rank/orZero/refOrNil -> no output   [ICF/inlining — honest decline]
- inRange -> (arg0 < 10)   ***DEFECT*** (see Finding U1)

## Ground truth (SIL)
- rank switch_enum: case #Color.red->1, green->2, blue->3. CONFIRMS tag=declaration index, our rank output correct.

## FINDING U1 — unsigned comparisons render as signed  (CONFIRMED DEFECT)
inRange -O disasm:  cmp x0,#0xa ; cset w0, lo ; ret     (lo = unsigned lower-than)
Our output: return (arg0 < 10)     — renders unsigned `<u` as signed `<`.
Root cause: comparisonOperator (ValueTracking.swift:1447-1453) intentionally MERGES signed+unsigned
condition codes onto one symbol set (LT|LO|MI -> .less, GE|HS|PL -> .greaterEqual, GT|HI -> .greater,
LE|LS -> .lessEqual). Comment at ValueTracking.swift:20 acknowledges the merge "for display".
Why it's wrong: `x >= 0 && x < 10` compiles to UInt(x) <u 10. For arg0 = -5, our `(arg0 < 10)` is TRUE
(signed) but the machine's `-5 <u 10` is FALSE. So the rendered expression is not semantically supported
by the binary — a manufactured signed reading of an unsigned test.
Smallest general correction: track comparison signedness; render unsigned comparisons distinctly (e.g.
`(arg0 <u 10)` or a UInt cast) so the output stays semantically faithful. Protect with positive (unsigned
range check) + adversarial (signed comparison must stay signed) tests.

## FINDING L1 — stack locals inlined, not promoted
`locals(x){var s=0; let a=x+1; let b=a*2; s=a+b; return s}` -> `((arg0+1)+((arg0+1)*2))`.
Correct value, but `(arg0+1)` recomputed; no `let a`/`let b`. We have no HighVariable/named-local concept;
values are inlined bottom-up. Ghidra promotes stack slots to named locals (HighVariable + merge). Design gap.

## FINDING S1 — struct-param decomposition is method-only
`dot(p:Point,q:Point)` (HFA) and `sum(p:Pair)` (GPR) decline. HFA decompose only fires in the value-self
(instance-method) path; free-function struct params and GPR structs are unseeded. Real limitation, honest decline.

## Optional representations (ground truth, -O)
- orZero (Int? ?? 0):  and w8,w1,#0xff ; cmp w8,#1 ; csel x0,xzr,x0,eq ; ret
  => TAGGED optional: payload in x0, TAG BYTE in a SEPARATE register w1. tag==1 => .none.
  csel = (tag==1)?0:payload = payload ?? 0. We DECLINE (multi-register, tag not modeled). Reconstructable
  with a proper two-register Optional value; currently honest decline.
- refOrNil (Ref? != nil):  cmp x0,#0 ; cset w0,ne ; ret
  => NIL-POINTER optional: class ref is ONE register, nil==0. r != nil = (arg0 != 0). We DECLINE — arg0
  (Ref?) not seeded because scalarParameterClass only treats Unsafe* pointers as single-register, not class
  refs. TRACTABLE gap: extend single-register-optional seeding to class/reference optionals (nil==0),
  analogous to the pointer nil-coalescing already done.

## Malimite (rev f25b0a6) — key finding
Malimite = Java GUI orchestrating headless Ghidra (analyzeHeadless + DumpClassData.java post-script over a
TCP socket) + SQLite store + optional LLM "translate to Swift" pass. It parses NO Swift metadata
(__swift5_*), reconstructs NO Swift types/enums/protocols/witness tables/existentials/generics/async/throw.
Its "demangler" is a naive length-prefix splitter (DemangleSwift.java) — not real demangling. ObjC = whatever
Ghidra's analyzer produced (namespaces). Output = annotated Ghidra C, or a non-deterministic LLM guess.
=> DIFFERENTIATOR CONFIRMED: our metadata-driven Swift recovery (enum case names, FieldMap, vtable/witness
naming from __swift5_*/reflection) is genuinely ahead of the leading public Swift/ObjC RE tool for Swift
SEMANTICS. Worth borrowing from Malimite: the headless-Ghidra-as-a-service pattern, SQLite substrate,
library-skip-by-namespace, ANTLR-parse-the-C-output for xrefs, explicit LLM readability layer.

## LittleSwift (rev 952240c) — key finding for IR design
Compiler AST = OPEN protocol hierarchy (Expression is universal supertype of EVERYTHING incl. types/stmts),
downcast-driven, NON-exhaustive (silent as?-ladder fall-through). AST -> LLVM directly, NO intermediate IR.
Types are decl-only, recomputed structurally, string-name equality. Literals are exact typed values (Int->i32,
no width/signedness) = exactly the unjustified certainty to avoid.
Proposed decompiler-IR node set (from agent, strong basis): closed exhaustive `enum Node`; EVERY node carries
{ type: TypeLattice(known|oneOf|unknown incl width+signedness), provenance: AddrRange+pass, confidence }.
Kinds: Const(raw bits+width+candidates), ValueRef(ssa id + optional name), BinOp(arith/compare/logical/
bitwise/shift), UnOp, Call(direct|indirect|unresolved candidates), MemberAccess(base+field, field may be
offset), Load/Store (raw mem, no source meaning yet), Phi/Select, RawOp/Unknown (ESCAPE HATCH — always able
to say "structure recovered, meaning not"), Assign/Def(+mutability tag+inference cell), If(cond may be
unknown + then + ELSE), Loop(generic header/body/latch/exits, NOT pre-classified while/for), Return, Block,
FuncDecl+Signature, TypeDescriptor (separate lattice, never conflated with Const).
INVERT 3 LittleSwift choices: (1) closed/exhaustive sum (not open supertype) so passes must handle every kind;
(2) type = per-value lattice slot (not decl-only recomputed); (3) provenance+confidence+RawOp on every node.
CONNECTION TO U1: signedness is a TYPE property; our AbstractValue has NO type on values; the unsigned-compare
defect is a SYMPTOM of missing value types. Proper fix = the type-lattice IR, not a band-aid.

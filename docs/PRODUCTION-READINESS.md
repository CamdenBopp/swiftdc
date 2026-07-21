# Production readiness

What stands between swiftdc and a decompiler whose output can be trusted without
hand-checking it. Organised by **risk**, not by feature appeal.

Each item is `[status] claim — evidence`. Status is one of **OPEN**, **FIXED**,
**MITIGATED**, or **UNKNOWN**. *UNKNOWN means nobody has measured it* — it is not
a synonym for "probably fine", and an UNKNOWN in Soundness or Completeness
outranks an OPEN in Reconstruction quality.

Every claim here should carry either a commit, a file:line, or a command you can
re-run. Claims without one are marked UNKNOWN by definition.

Last audited: 2026-07-21, at commit `d1bc5a3`.

---

## 1. Soundness — can it fabricate or misattribute semantics?

The highest-severity category. A wrong render is worse than a missing one,
because it cannot be distinguished from a right one by reading the output.

- **FIXED — unsigned comparisons rendered as signed.** `cset w0, lo` (unsigned)
  used to render `(arg0 < 10)`, which evaluates differently from the machine at
  negative inputs. Fixed in `2be9e31` via a per-value type lattice carrying
  signedness. Verified at HEAD: `x >= 0 && x < 10` at `-O` renders
  `((0 <= arg0) && (arg0 < 10))`; a genuinely signed `x < 10` renders
  `(arg0 < 10)`. Unknown signedness renders an explicit `<ᵁ` rather than
  guessing.
- **FIXED — field-map name collisions fabricated fields.** Two types sharing a
  simple name let one type's layout name the other's fields. Ambiguous simple
  names are now dropped, and qualified keys recover the precise layout
  (`0237af1`, `1ec5872`, `f423666`).
- **MITIGATED — the decline-rather-than-guess rule.** Verified as systematic, not
  incidental: `.unknown` renders `?` (`Disassembler.swift:2322`); the structurer
  refuses to structure an unprovable branch (`Structurer.swift:214`); `clobber`
  is deliberately over-pessimistic because under-clobbering "leaves a stale value
  that renders as a confident, fabricated" one (`ValueTracking.swift:1583`);
  fixed-ABI callee args are clamped to real arity so a stale register cannot
  surface as a trailing argument.
- **MITIGATED — `self` is conservative.** x20 is read as `self` only for a
  Swift-mangled callee and only when freshly written (`Disassembler.swift:2847`,
  `ValueTracking.swift:636`). Deliberate false-negative-over-false-positive.
- **MITIGATED — field naming requires two independent halves.** Receiver type
  known AND offset inside the type's trusted prefix; the `isInstance` flag
  refuses metatypes. Consulting the symbol first (which lacks that flag) produced
  a real `swift_allocObject(self, …)` fabrication before the ordering was fixed.
- **OPEN — `X → self.layout` imprecision.** LayoutWrapper structs over `__C`
  types render the whole `self.layout` because the backing C struct has no Swift
  field metadata. A *real* field name at the wrong granularity — imprecise, not
  fabricated. Needs C-struct field data.
- **MITIGATED — a differential oracle now exists** (`DifferentialOracleTests`).
  Every other soundness test compares recovered pseudocode against a string
  someone wrote down, which cannot catch a plausible-but-wrong render: the
  expectation was written by the same reasoning that produced the bug. U1
  survived exactly that way.

  This harness compares against the **binary** instead. It recovers the
  expression swiftdc renders, parses it (the output is fully parenthesized, so
  no precedence table is needed), evaluates it over chosen inputs, calls the
  **real compiled function** via `dlsym`, and asserts they agree. Ground truth
  is resolved from swiftdc's *own reported symbol*, so the oracle cannot drift
  onto a different function than the one it analysed.

  Currently **636 comparisons — 318 at `-Onone` and 318 at `-O`**, 13 functions
  at each level: comparisons, ternaries, arithmetic, bit operations, and the
  signed-range idiom, at edge inputs including `Int.min`/`Int.max`.

  The `-O` half is the part that matters most, because optimized lowering is
  where U1 lived. It executes the recovered idiom
  `((0 <= arg0) && (arg0 < 100))` against the machine's single unsigned compare
  (`cmp x0, #100; cset w0, lo`) at `Int.min`, `-1`, `0`, `100` and `Int.max`.
  **That is the first execution-based confirmation the U1 fix is correct** — it
  had previously only been reasoned about. `-O` also covers a `csel` cascade
  (`threeWay`) that `-Onone` cannot recover at all, and commuted operands
  (`(arg1 & arg0)`) that `-Onone` renders in source order.

  The two fixtures are separate builds of the same source, so they export
  **byte-identical mangled symbols**. Resolved pointers are therefore verified
  with `dladdr` to lie in the intended image; without that, `dlsym` collapsing
  onto the first-loaded library would make the `-O` half silently re-test
  `-Onone` code while reporting optimized coverage. Confirmed live: the same
  symbol resolves to distinct addresses in distinct owners.

  Proven sensitive, not merely green: injecting U1's shape (`((arg0 >= 0) &&
  (arg0 < 100))` → `(arg0 < 100)`) fails at exactly the negative inputs where
  that defect manifests. The first injection attempt was a **no-op** — it
  targeted the `-O` spelling, which the `-Onone` fixture never emits — and
  passed misleadingly.

  The guards that came out of that: a per-fixture comparison floor, and a
  **named list of cases that must not be skipped** at each level. The named list
  is not redundant with the count — simulating a loss of `-O` `rangeCheck`
  recovery leaves 309 comparisons, which clears the floor of 200 while removing
  the single case the oracle exists for. Only the named check catches it, and it
  was confirmed firing.
- **MITIGATED — the oracle covers floating point too.** A further **628
  comparisons** (314 per optimization level) over six functions: `Double` and
  `Float` arithmetic, an intrinsic (`sqrt`), a literal-returning function, and
  the mixed-register ABI. Zero skips at either level.

  Doubles are compared **bit-exactly**, not approximately — that is the point.
  A rendered constant like `3.14` is a claim about *which* of ~2^64 doubles the
  binary holds, and an approximate comparison would accept a rounded or
  truncated decimal. Proven at that resolution: injecting a **one-ULP**
  perturbation (`3.14` → `3.1400000000000006`, a difference of 4.4e-16) fails at
  both levels. So swiftdc's decoded constants round-trip exactly.

  Edge inputs are the ones that break floats and not integers: signed zero,
  subnormals (`leastNonzeroMagnitude`), both infinities, and NaN — with NaN
  treated as agreeing with NaN, since NaN is not bit-stable across a
  computation.

  `floatMath` is `Float`-typed, so the oracle rounds every intermediate to
  `Float` precision. Evaluating it in `Double` would disagree wherever the two
  round differently and would have looked like a swiftdc defect rather than an
  oracle defect.

  `interleaved(Int, Double, Int, Double)` renders `(arg1 + arg3)`, which is an
  **ABI claim** — integers in `x0`/`x1`, doubles in `d0`/`d1`, with `argN`
  indexing source position rather than register order. Executing it confirms the
  mapping rather than assuming it.
- **OPEN — the oracle's remaining domain gaps.** Strings, enums with payloads,
  memory effects, and anything with side effects are still uncovered, and it
  samples rather than proves. Both optimization levels and both numeric domains
  are now covered; what remains is aggregate and effectful values.
- **FIXED — a declined return value rendered as a bare `return`.** A function
  whose return value was not recovered printed `return` with no operand even when
  its signature said `-> Swift.Int`, reading as "returns nothing" rather than
  "we did not recover this". Not a fabrication, but a declined value described
  misleadingly — and it contradicted the contract that unprovable values render
  `?`. Not a corner case either: bare returns were **~45% of all returns** in the
  fixture (121 bare vs 143 with a value).

  Now `return ?`, but **only where the signature proves a value exists**. The
  rule is one-sided by design, since over-claiming would assert a value that is
  not there:

  - **Void functions keep the bare form** — a void return really is just
    `return`. Measured: 7 in the fixture, all correct before and after.
  - **Unrecognisable signatures keep it too** (`sub_<addr>`, thunks, witness
    accessors — 98 of them). Declining is the house rule.
  - **Throwing functions keep it.** A throwing function's error exit genuinely
    yields no value (the result travels in x21), and whether a given exit is the
    error path is not known per-block, so asserting a missing value on a throw
    path would be wrong. Where the normal exit *is* recovered it already prints
    `return <expr>`, so little is lost.

  Two emission sites had to change, not one; the second was found only by
  re-measuring the whole fixture after fixing the first and noticing a throwing
  function still classified oddly.

  Both directions are proven. Reverting the fix fails the value-side tests
  (including a floor that reported "only 0 function(s) rendered `return ?`");
  over-applying it fails the void and throwing guards, with the population check
  naming the four void functions it would have corrupted.
- **FIXED — an ObjC method's unrecovered return rendered a bare `return`.**
  Closing the "unit-tested only" gap on the classifier's ObjC branch — by
  auditing real system methods rather than the fixture — surfaced a genuine
  integration bug, exactly the kind a unit test could not see.

  The structurer's `usesSwiftError` heuristic treats a body that clears x21
  (`mov x21, #0`) as threading the Swift error register, which suppresses
  `return ?` on the unrecovered path (rendering a bare `return`). But ObjC does
  not use that ABI — its errors bridge through an `NSError**` out-parameter — so
  an ObjC method that merely zeroes x21 while computing a `BOOL` (routine in
  `isEqual:`) was misclassified. Confirmed by disassembly: the offending
  `-[UNNotificationTopicRequest isEqual:]` contains `mov w21, #0`; a
  near-identical `-[UNNotificationCategory isEqual:]` that does not clear x21
  rendered `return ?` correctly. Measured on UserNotifications: **7 non-void ObjC
  methods** rendered a bare `return` purely for this reason.

  Fixed by never setting `usesSwiftError` for an ObjC method (the same gate also
  stops an incidental `x21 == 0` being mis-named `error != nil`). Verified both
  directions: `ObjCValuelessReturnTests` (a population property over real system
  ObjC methods: zero bare returns under a non-void signature, ≥10 `return ?` so
  it is not vacuous) was observed failing without the gate, naming all 7 methods;
  and the existing `aThrowingFunctionsErrorExitKeepsItsBareReturn` confirms a
  genuine Swift `throws` error exit still renders a bare `return`.
- **FIXED — the same misfire hit *Swift* functions too, and the heuristic itself
  was wrong.** Auditing real Swift methods (Combine) for the analogous defect
  confirmed it: **10 non-throwing, value-returning Swift functions** — Publisher
  constructors like `compactMap`, `reduce`, `min(by:)`, `output(at:)` — rendered
  a bare `return` because they zero x21 as incidental scratch. The ObjC `!ObjC`
  gate could not help here (Swift functions genuinely can thread swifterror).

  The real defect was the heuristic: "the body clears x21" is not swifterror
  threading. Genuine threading **clears x21 before a throwing call *and* tests it
  (`x21 == 0`) after** to catch the throw; a function that only zeroes x21 and
  never reads it back is not error-checking. The heuristic now requires **both**,
  which is also why it subsumes the ObjC case — `isEqual:` tests `cmp x21, x0`,
  against a register, not zero.

  This partitions cleanly on real code, measured on Combine: 28 functions that
  clear *and* test x21 (genuine — the "Try" operators catching a closure's
  throw) keep `usesSwiftError`; the 10 that clear without testing flip to
  `return ?`. Both directions proven: the discriminators
  (`clearsSwiftErrorRegister`/`testsSwiftErrorRegister`) are unit-tested
  including the `cmp x21, x0`-is-not-a-zero-test case, and reverting the "and
  tests" requirement was observed regressing exactly those 10 Combine functions
  back to a bare `return` while a `throws` function (`mightFail`) stays bare via
  the `isThrowing` override.

  Along the way the audit *harness* was wrong twice before the tool was — a
  return-type regex that read a parameter's `(A) -> Bool` as the return type, and
  bare-return attribution across `merged` headers — each corrected before
  trusting the count (18 → then a name-parse-free raw-disasm oracle → 10).

## 2. Completeness — what does it silently omit?

Silent omission is the worst failure mode: it is indistinguishable from a
correct empty answer. See the empty-result rule in `CLAUDE.md`.

- **FIXED — whole-binary disassembly returned nothing on most dylibs.**
  llvm-objdump right-aligns its address column; the parser required
  `allSatisfy(isHexDigit)` on everything before the first colon, so every
  instruction line of a low-based binary was dropped. Reported
  `// No functions matched.` — 0 functions where the binary had 446 (`d1ca94f`).
- **FIXED — the guard against that class.** An empty parse is now cross-checked
  against `LC_FUNCTION_STARTS` and throws `DisassembleError.parsedNothing` with
  both counts rather than returning `[]`.
- **FIXED — the Capstone whole-image decode stopped at the first undecodable
  byte.** `cs_disasm` halts at the first byte sequence it cannot decode and
  returns the count so far; the engine called it *once* and took that as the
  decode. `__text` is full of things that stall it — inline data, alignment
  padding, jump tables, unknown arm64e forms — so every whole-image decode
  truncated at the first one.

  The prior entry here recorded "~285 functions" as a modest shortfall. Adding
  the coverage metric reframed it: **285 of 105,647 declared functions, 0.27%**,
  decoding 4,040 instructions over 16,160 contiguous bytes before stopping
  silently. The listing looked entirely normal. ARM64's fixed 4-byte width makes
  recovery exact rather than heuristic — on a stall, skip one instruction slot
  and resume — so the fix carries no realignment guesswork.

  Confirmed at full scale: SwiftUI now recovers **105,644 of 105,644 declared
  functions (100%)** and 5,654,282 instructions, up from 285 and 4,040 — 371×
  more functions, 1,400× more instructions.

  This entry previously read "105,644 of 105,647 … the three unrecovered
  functions are worth a look". There were never three: the denominator was
  inflated by `LC_FUNCTION_STARTS` padding (see the oracle fix in Completeness).
  A residue reported against a wrong denominator is a phantom, and chasing it
  would have been wasted work.

  Covered by `CapstoneResyncTests`, which pins the resync *stride* (a
  wrong-sized skip still yields the right instruction count at wrong addresses),
  and was observed failing against the single-call decode before being trusted.
- **OPEN — names for statically-dispatched Swift on stripped binaries.** Free
  functions, closures, thunks, and struct/enum non-protocol methods render
  `sub_<addr>`. Boundaries recover; names have no metadata record to recover
  *from*. Partly inherent.
- **OPEN — unresolved indirect call edges.** Generic witness tables, unknown
  receiver vtables, and block pointers stay unresolved. `xrefs` reports the
  count, so this is *disclosed* rather than silent — but `--unreferenced` is
  therefore not a dead-code proof.
- **FIXED — the completeness oracle itself over-counted.**
  `declaredFunctionCount` is what the empty-result rule compares against: an
  empty parse throws when it disagrees, and an unfiltered run warns below 50% of
  it. It was inflated. `LC_FUNCTION_STARTS` is a ULEB128 list of *deltas*,
  zero-padded to alignment, and each padding byte decodes as a delta of zero —
  "another function at the same address as the last". The raw list therefore ends
  in a run of repeats.

  Measured: 453 raw vs 449 distinct, 182 vs 176, 172 vs 171 — and the distinct
  count matches `dyld_info -function_starts` **exactly** in every case. Now
  deduped at the source. Boundary callers were always unaffected (they wrap it in
  a `Set`), so the change moves counts only — verified by enumerating all five
  call sites rather than assuming.

  The visible consequence was a phantom: SwiftUI read as "105,644 of 105,647
  recovered", and the missing three were padding entries, not functions.
- **MITIGATED — recovery coverage is now reported.** An unfiltered run that
  recovers under half of what `LC_FUNCTION_STARTS` declares warns on stderr with
  both counts and a percentage (stdout stays pipeable). This is the
  "unusually small" half of the empty-result rule; the empty case throws.
  It is what turned the SwiftUI shortfall from a vague "~285" into a diagnosis.
- **MITIGATED — byte-level coverage measured; no truncated bodies found.**
  Function-count coverage could not distinguish a fully-decoded function from one
  recovered with a truncated body. Measured two ways, against
  `dyld_info -function_starts` as an independent extent source:

  - **Every declared 4-byte slot decodes**: 100.000% on `libReconstruction.dylib`
    (7,624 slots) and `sample.release` (2,291) via the objdump path.
  - **No holes inside recovered bodies**: 0 hole-bytes across the fixtures and
    across `UserNotifications` (1,391 functions, 52,071 instructions) via the
    Capstone path — the one that carried the resync truncation.

  The first attempt at this measurement was **vacuous** and is worth recording:
  it compared each function's decoded end against the *next recovered function's*
  start, both of which come from the same decode. It reported a flawless 100%
  with zero gaps across 1,391 functions — implausible, since real binaries have
  alignment padding between functions. Comparing a decoder against itself proves
  nothing; the numbers above use an external tool.

## 3. Robustness — what breaks it?

- **FIXED — malformed input crashed the process.** The audit recorded this as
  one case (a truncated Mach-O). Surveying nine hand-written malformed inputs
  found **seven crashed** — six SIGTRAP, one **SIGSEGV** — including an *empty
  file* (`MachOKit/FileHandle+.swift:188: Precondition failed: Invalid Data
  Size`). Four distinct trap sites across MachOKit and `FileIOBinary`, all
  `try!`/`precondition`, all in dependencies, therefore all uncatchable.

  Fixed by `MachOPreflight`, a structural validator run before the file reaches
  MachOKit. Every check compares two numbers the file itself declares — header
  size vs file size, `sizeofcmds` vs bytes available, `ncmds` vs the 8-byte
  minimum command, fat slice extents vs file length — so it encodes no
  heuristic about what binaries "normally" look like. Nine of nine inputs now
  exit 1 with a specific message; zero crash.

  The over-rejection risk is guarded explicitly, because a validator that
  refuses real binaries would be worse than the crash: tests assert acceptance
  of well-formed headers, headers whose load commands extend past the read
  prefix, every built fixture, and real fat system binaries (`/bin/ls`,
  `/usr/lib/dyld`). Non-Mach-O files (a PNG) fall through to the existing
  "Not a Mach-O file" path rather than being called malformed.

  The end-to-end guard runs the CLI as a **subprocess** and asserts it exited
  rather than died by signal — the crash cannot be observed in-process, since a
  trap would take the test runner down with it.
- **MITIGATED — other malformed inputs degrade cleanly.** Random bytes →
  `Error: Not a Mach-O file`, exit 1. A truncated-but-parseable binary →
  `llvm-objdump failed: …`, exit 1. Both correct.
- **FIXED — malformed load-command PAYLOADS crashed four subcommands.** The
  header survey above was recorded FIXED while this entire class was still live,
  because it exercised `disasm` — which shells out to llvm-objdump, and
  llvm-objdump rejects a bad file before MachOKit ever parses it. `dump`,
  `layout`, `interface` and `objc` reach MachOKit directly.

  Mutating a real fixture's load-command payloads produced **12 SIGTRAPs**: a
  segment `fileoff` past EOF killed all four subcommands, and each of the four
  `LC_SYMTAB` range fields (`symoff`, `nsyms`, `stroff`, `strsize`) killed `dump`
  and `interface`. The process died **silently — empty stderr**, so it vanished
  with no diagnostic at all. Some cases also emitted partial stdout before dying.

  Fixed in `ae66f3e` by extending `MachOPreflight` to the payloads: segment
  `fileoff`/`filesize`, per-section `offset`/`size`, and the `LC_SYMTAB` symbol
  and string ranges must lie inside the file. Same philosophy as the header
  checks — every comparison is between two numbers the file declares about
  itself. Zero-fill sections (`S_ZEROFILL`, `S_GB_ZEROFILL`,
  `S_THREAD_LOCAL_ZEROFILL`) are exempt because their `size` is a memory extent,
  legitimately larger than the binary; bounds-checking them would reject real
  `__bss`. 64-bit fields are clamped rather than converted, since `Int(_:)` traps
  above `Int.max` — the exact hostile input this code exists to survive.

  All 12 now exit 1 with a field-level diagnostic naming the segment or table,
  the bytes claimed and the file size, and emit no stdout. Verified by
  `MachOPreflightTests` (28 tests): 8 unit tests over the pure validator plus an
  end-to-end test that mutates a real fixture and drives the CLI as a subprocess
  across all four subcommands. Every one was observed failing against the
  pre-fix validator — the end-to-end test on both `terminationStatus == 1` and
  `stdout.isEmpty`.

  Over-rejection re-checked: every fixture, `/bin/ls`, `/usr/lib/dyld` and an
  object file still analyse normally.
- **OPEN — a structurally VALID Mach-O missing an expected segment still traps.**
  Found by fuzzing (below), then isolated: renaming `__TEXT` to `__TEXTX` — valid
  ASCII, a structurally legal Mach-O — SIGTRAPs with empty stderr. Setting a load
  command's `cmd` to an unrecognised value, so `__LINKEDIT` is no longer found,
  SIGBUSes.

  **This cannot be safely contained by structural validation**, and the reason is
  worth recording rather than retrying: nothing about these files is
  inconsistent, so there is no pair of self-declared numbers to compare. The
  obvious guard — require a segment named `__TEXT` — would reject **object
  files**, which carry a single *empty*-named segment and which swiftdc analyses
  correctly today (verified: a built `.o` dumps at exit 0). Rejecting a real,
  currently-working input class to prevent a crash on a hand-corrupted one is the
  wrong trade under this project's own stated rule. Closing it needs either a
  MachOKit fork or an upstream fix.
- **MITIGATED — a bounded fuzz now exists, and its yield is measured.** 120
  random mutants over the load-command region (fixed seed): **83 accepted, 34
  clean nonzero exits, 3 crashes (2.5%)** — 2 SIGTRAP, 1 SIGBUS, all three
  reducing to the uncontainable class above. Before the payload fix the same
  class of input crashed on every mutation that touched a segment or symtab
  range. This is a harness run by hand, not a CI gate.
- **FIXED — the `--cache` entry point trapped on a short file.** The recorded
  reasoning ("the system cache is not attacker-supplied") held only for `--cache`
  *omitted*; an extracted cache passed by path is user-supplied, and that
  assumption was tested rather than trusted. `FullDyldCache(url:)` reads a whole
  `dyld_cache_header` at offset 0 **before** checking the magic, via a `try!`, so
  any file shorter than that struct trips
  `precondition(data.count >= layoutSize)` and aborts — exit 133, empty stderr,
  the same uncatchable-dependency class as the Mach-O path.

  Probed: **5 of 7** malformed caches crashed, every one shorter than the header
  (`MachOKit/DyldCache.swift:82`). And the residue is *zero*: every file at least
  header-length — including valid-magic files with lying mapping/image
  offsets — declines cleanly through MachOKit's own magic and cpu-type checks. So
  the entire class closes with **one size guard** on the `cachePath` branch of
  `openDyldCache`, throwing when the file is shorter than `DyldCacheHeader.layoutSize`
  (read from the type, 552 bytes today, so it tracks the struct rather than
  hardcoding it). The host-cache branch is left unguarded — it is the running
  system's cache, not a user path.

  Both directions proven. The end-to-end test drives the CLI as a subprocess and
  was observed failing without the guard ("empty: killed by signal 5"); the
  over-rejection test pins the one-byte boundary — a file of `layoutSize - 1` is
  rejected *by the size guard* (which names the size), while `layoutSize` exactly
  passes the guard and is declined *by MachOKit* on content. A real 737 KB
  extracted cache still dumps Foundation through the guarded branch.
- **FIXED — structurer stack overflow on deep CFGs** (`ca82d6f`).
- **FIXED — spurious dyld-cache markers trapped ObjC index construction**
  (covered by `buildsObjCIndexWithoutTrappingOnSpuriousCacheMarkers`).
- **MITIGATED — `MachOFile.symbols` fatalErrors on cache images** whose
  `__LINKEDIT` sits in another subcache. Uncatchable; avoided by reading the
  export trie instead, which is also semantically correct.
- **PARTLY FIXED — metadata parsing crashes on corrupted `__swift5_*` /
  `__objc_*` contents.** The flat relative-pointer tables are now validated;
  the structured sections are not. Details of the fix are below the measurement. The prediction that the `try!`-in-a-dependency class would recur
  has now been tested a **third** time and held again. `MachOPreflight` validates
  the Mach-O *container*; it says nothing about section *contents*, which
  MachOSwiftSection / MachOObjCSection parse.

  Measured with `Tools/metadata-fuzz.py` (seeded, deterministic —
  `libSample.dylib`, 100 mutants, seed 1234): **49 crashes in 800 runs, 6.1%**,
  versus 2.5% for the container fuzz. All die with **empty stderr**:

  | section | signal | subcommands killed |
  |---|---|---|
  | `__swift5_protos` | SIGTRAP | **all eight** — no entry point survives (now contained) |
  | `__swift5_assocty` | SIGTRAP + SIGSEGV | dump, interface, analyze |
  | `__objc_methlist` | SIGSEGV | objc, objc --methods, disasm, xrefs, analyze |

  `disasm` is among them. Container corruption never reached it because
  llvm-objdump rejects the file first, but metadata is parsed in-process, so that
  shield does not apply here.

  **At least five sections are affected, not three.** A second seed (20 mutants,
  seed 999) found `__swift5_types` — again killing all eight subcommands — and
  `__swift5_fieldmd`, neither of which the first seed reached. Its yield was
  21.9%, though on a much smaller sample. The section list below is therefore a
  lower bound on the blast radius, not an inventory; whichever sections a seed
  happens to hit is what it reports.

  Two distinct dependency defects, from backtraces:

  1. **A negative resolved offset traps instead of being rejected.**
     `MangledName.resolve` → `MachOFile.readElement(offset:)` → `numericCast` →
     `Negative value is not representable`. The bounds check *already exists* —
     it is simply performed after an unsigned conversion. Proven by a controlled
     test on one relative pointer: `+32767` (out of range) returns
     `Error: offsetOutOfBounds` and exit 1, while `-32767` SIGTRAPs. Note the fix
     is **not** "reject negative": `-1024` resolves in-bounds and exits 0,
     because relative pointers legitimately point backwards. The check must
     happen on the resolved absolute offset, before conversion.
  2. **An unbounded string read walks off the mapping.**
     `ObjCMethodList.indirectMethod` and `AssociatedTypeRecord.name` →
     `readString(offset:)` → `strlen` → SIGSEGV.

  **Contained for the flat pointer tables.** `MachOPreflight` now validates
  `__swift5_protos`, `__swift5_proto`, `__swift5_types` and `__swift5_types2`:
  each is a bare array of 4-byte relative pointers, so `target = pointerOffset +
  value` must land inside the file. No record layout is modelled, and sign is not
  the test — every entry in every real fixture is *negative*, pointing backwards
  into `__TEXT`, so a validator that rejected negative deltas would refuse every
  Swift binary in existence.

  Measured across three seeds, before → after:

  | seed | mutants | before | after |
  |---|---|---|---|
  | 1234 | 100 | 49 crashes (6.1%) | **22 (2.8%)** |
  | 999 | 20 | 35 (21.9%) | **8 (5.0%)** |
  | 424242 | 40 | 14 (4.4%) | 14 (4.4%) — hit only uncovered sections |

  Sections are read individually rather than from the 1 MiB header prefix:
  metadata sits after the code, so in any real app it lies far beyond that
  window, and validating only the prefix would leave exactly the large binaries
  unprotected. Verified on a 36 MB binary whose tables hold 4,033 entries.

  **The covered list was not widened by measurement, though it was tempting.**
  On real binaries `__swift5_assocty` and `__swift5_capture` also have every
  int32 resolve in-file, which looks like the same flat shape. They are
  structured records, and some of those int32s are *counts*, not pointers — they
  resolve in-file here only because the counts are small and the sections sit far
  into the file. A large count in a small binary would be rejected as an
  out-of-range pointer, refusing a valid input.

  **Still OPEN**, and the residue was measured rather than estimated. Across
  four seeds (220 mutants) the sections still crashing are `__swift5_assocty`
  (20), `__objc_methlist` (10), `__swift5_fieldmd` (8), `__swift5_builtin` (6)
  and `__objc_const` (5) — **five sections, and more would surface with more
  seeds**. Extending the section-by-section approach is therefore a treadmill
  with no defined end, which is why it was not continued.

  **The one-guard upstream fix was tested, not assumed.** Applying
  `guard offset >= 0 else { throw ReadingError.invalidAddress(offset) }` to the
  seven read entry points of `MachOSwiftSection` (via `swift package edit`, then
  reverted) removes **49 → 21 crashes, ~57%**, with no regression on any fixture
  or on a 36 MB real binary:

  | seed | mutants | before | with the guard |
  |---|---|---|---|
  | 1234 | 100 | 22 (2.8%) | 10 (1.2%) |
  | 999 | 40 | 8 (2.5%) | **0 (0.0%)** |
  | 424242 | 40 | 14 (4.4%) | 6 (1.9%) |
  | 7 | 40 | 5 (1.6%) | 5 (1.6%) |

  Written up as [docs/upstream-negative-offset.md](upstream-negative-offset.md),
  ready to file. Not fixed in-tree: the fix belongs in the dependency, and
  forking would take swiftdc off upstream — a maintainer's decision, not a side
  effect of a bug hunt.

  The residue after that guard is two further defects, both distinct: an
  **unbounded `strlen`** in `readString(offset:)` (SIGSEGV, needs a length bound
  rather than a sign check), and **`MachOObjCSection`**, which has the same
  unsigned-conversion shape and was not patched — every surviving SIGTRAP is in
  `__objc_methlist` or `__objc_const`, which it parses.
- **MITIGATED — metadata fuzzing is now repeatable, not hand-run.**
  `Tools/metadata-fuzz.py` is seeded and deterministic for a given
  (binary, mutants, seed), covers all eight metadata-reading subcommands, and
  exits nonzero when any mutant kills the CLI — so it can become a gate the
  moment the class above is contained. It is not yet wired into CI.
- **OPEN — fuzzing is bounded and manual; metadata parsers are unprobed.** The
  prediction that the `try!`-in-a-dependency pattern would recur in load-command
  payloads was tested and **held** — 12 crashes across four subcommands, now
  fixed. A 120-mutant fuzz over the load-command region has since been run
  (2.5% crash yield, all in the uncontainable class). `__swift5_*` and
  `__objc_*` **metadata** parsing has since been probed and is crashing — see the
  metadata entry above (6.1% yield, three sections, one of which kills every
  subcommand). **Fat slice thin headers** — flagged here as unprobed — were then
  probed and **crashed**: a slice whose *extent* is in-bounds but whose thin
  Mach-O header lies (`sizeofcmds` claiming load commands past the slice) passed
  preflight and trapped in `MachOKit/MachOFile.swift:61` when `fat.machOFiles()`
  parsed it. Confirmed by corrupting a real fat binary (`/bin/ls`). **Now
  fixed**: `MachOPreflight` validates each slice's thin header against the
  *slice* size, with the same two consistency checks `validateThin` applies to a
  top-level header (`FatSlicePreflightTests`; both directions proven — the crash
  test observed "killed by signal 5" without the fix, the over-rejection test
  observed a valid `/bin/ls` slice being refused when the check was made
  over-eager). Still unprobed: anything beyond the 1 MiB preflight read prefix
  that is not a fat slice or a validated relative-pointer table. Nothing runs in
  CI.
- **MITIGATED — behavior across optimization levels.** The differential oracle
  now runs at both `-Onone` and `-O` (318 comparisons each), executing the
  recovered expression against the real compiled function at each level. This is
  the level where lowering genuinely diverges: `-O` turns a signed range check
  into one unsigned compare, folds branches into `csel`, commutes operands, and
  optimizes some functions away entirely. Scoped to the scalar domain the oracle
  covers — it says nothing about optimized lowering of strings, payload enums,
  or side-effecting code.

## 4. Determinism

- **MITIGATED — output is stable across runs.** Three consecutive
  `disasm --structured` runs over the fixture hash identically:
  `for i in 1 2 3; do swiftdc disasm Fixtures/Sample/libReconstruction.dylib --structured | shasum; done`
  Tests additionally pin a shared symbol-index store (`withStableDependencies`),
  which suggests dependency-injection order once mattered.
- **MITIGATED — determinism is enforced across processes, and the stated risk
  was wrong.** This entry used to blame concurrency: "the pipeline is `async` …
  scheduling varies more". Checked at HEAD: the decompiler has **no concurrent
  fan-out at all** — no task groups, no `async let`, no `Task {}`, no
  `concurrentPerform` — and the single large-stack worker thread is joined before
  its result is read. `async` here is sequential I/O, not parallelism, so
  scheduling is not a source of variation.

  The actual dependency is **~16 explicit `.sorted()` calls** placed where an
  unordered collection reaches output. Nothing enforced them, so emitting
  straight from a `Dictionary` or `Set` in a future change would reorder output
  silently.

  `DeterminismTests` now compares four runs of six subcommands — Swift metadata,
  the ObjC index, field layout, the call graph, and structured disassembly.
  It must run them as **subprocesses**: Swift seeds `Hasher` per process, so
  `Set`/`Dictionary` order is permuted *between* runs but constant *within* one.
  Repeating a call in-process would reuse the seed, reorder nothing, and prove
  nothing.

  Proven to have power, not merely green. Deleting the real `.sorted()` from
  `CallGraph.unreferenced()` fails it immediately, with the signature that
  identifies reordering rather than a content change:

      xrefs --unreferenced: run 2 differs from run 1 (29537 vs 29537 bytes)

  A companion test asserts the premise itself — that iteration order really does
  vary between processes on this toolchain. If a future toolchain made hashing
  deterministic by default, the guard would keep passing while having lost all
  of its power, and that should be visible rather than silent.

## 5. Performance and memory on large frameworks

- **OPEN — whole-image decoding does not scale to the largest frameworks.**
  Measured after the resync fix: `disasm --image UserNotifications` recovers
  1,391 functions / 52,103 instructions in **19s**, with no coverage warning.
  SwiftUI, at 105,644 recovered functions and 5.65M instructions, took
  **6m03s** before streaming — now **2m37s** (streaming no longer thrashes swap),
  but still slow for interactive use. Streaming fixed the *memory* (see the FIXED
  entry below), not the decode/analysis *time*.

  This cost was previously *hidden by the truncation bug*: stopping after 4,040
  instructions made SwiftUI look fast. Fixing completeness exposed the real
  workload, which is the correct trade (a fast wrong answer is worth nothing)
  but leaves unfiltered runs on the largest images slow.

  Not pathological — the resync loop was checked for a degenerate
  one-call-per-4-bytes case on a large data region and UserNotifications shows
  none. It is the per-instruction analysis pipeline, run over ~75× more code.
  `--function` remains fast on any image, since it decodes only matched ranges.
- **FIXED (memory) — whole-image text output is now streamed, ~8–10× less peak
  memory, and the largest frameworks fit in RAM.** `disasm --image X` in the
  text/`--structured`/`--pseudo`/`--cfg` modes now decodes, analyses, renders and
  **releases one function at a time** (`disassembleStreamingRender`), instead of
  holding the whole image's decoded instructions at once. Measured before → after
  (`/usr/bin/time -l`, release, peak footprint):

  | image | instructions | before | after | factor |
  |---|---|---|---|---|
  | CoreLocation | 473,670 | 1,192 MB | **117 MB** | 10× |
  | SwiftUI | 5,654,282 | 13,794 MB | **1,633 MB** | 8.4× |

  SwiftUI **no longer exceeds a 16 GB host** — 1.6 GB fits in RAM, and it also
  ran *faster* (2m37s vs 6m03s) because it no longer thrashes swap. The residual
  is O(function count), not O(instructions): the cross-function name index
  (~105 k demangled names + resolver for SwiftUI) is what remains resident, and
  `--json`/`xrefs`/`analyze` — which genuinely need every function — keep the
  array path and its old footprint (verified unchanged: CoreLocation `--json`
  still 1,241 MB, the control).

  Output is **byte-identical** to the array path — verified on
  `disasm --image UserNotifications` across all five modes (text, structured,
  pseudo, cfg, json) against pre-refactor golden hashes — because the streaming
  path reuses the same `makeFunction` naming and the same `analyzeFunction`
  analysis, and boundaries are instruction-aligned so its spans are exactly the
  functions `segment` cuts. The foundation (extracting `analyzeFunction`, so both
  paths share one code path rather than a parallel reimplementation) landed
  separately in `09d9026`, itself golden-verified.

  How the cause was localised, for the record (an earlier version of this entry
  reasoned it was `detail`; that was measured false). Four candidates ruled out
  on CoreLocation, each leaving 1,192 MB unchanged: stripping `detail` at decode;
  the rendered output (only 16 MB); skipping value-tracking; and returning the
  raw decoded list with no `assemble` at all — the last proving the entire peak
  is present the instant `__text` is decoded. The held whole-image instruction
  list was the cost; streaming holds one function's worth.

  Reproduce:
  `/usr/bin/time -l swiftdc disasm --image CoreLocation >/dev/null` (streamed) vs
  `… --json >/dev/null` (array) — read `peak memory footprint`.
- **OPEN — time, and the array modes, still scale with the whole image.**
  Streaming fixed peak *memory* for text output but not *time*: CoreLocation
  still takes ~23 s (the decode + per-function analysis work is unchanged, just
  no longer all resident). And `--json`/`xrefs`/`analyze` still materialise every
  function, so their memory is unchanged by design — a streaming JSON writer, or
  chunking the array modes, is the remaining scale work.
- **MITIGATED (memory) — a whole-image memory regression guard now exists**
  (`MemoryRegressionTests`). The memory limit above is now FIXED by
  streaming, but nothing stopped it regressing meanwhile, and it still guards the
  array path (`--json`) that keeps the old footprint: an
  added held field on `Instruction`, or an extra retained copy of the list,
  would balloon per-instruction memory silently. The guard runs
  `disasm --image UserNotifications --json` under `/usr/bin/time -l` — an
  **external** oracle, process accounting rather than any number swiftdc reports
  about itself — and asserts `peak footprint ÷ instruction count` stays under
  **5,632 B** (~1.6× the measured ~3,400 B/instruction baseline, so it trips on a
  doubling-class regression, not the ~4% run-to-run variance).

  Proven to have teeth, and the proof taught the boundary. A first injection —
  two extra `map { $0 }` copies of the instruction list — did **not** trip it,
  because `Instruction`'s String/`detail` heap buffers are copy-on-write, so the
  copies shared bytes rather than allocating them. That is correct: retaining
  references to the same instructions is not a memory regression. Injecting a
  genuine per-instruction allocation (3 KB of fresh bytes each) did trip it, at
  6,025 B/instruction. So the guard catches the realistic regression — a new
  held field carrying heap data — while ignoring reference retention.

  Host-gated: it needs a system dyld cache image and skips cleanly without one
  (a skip is instant; the passing run takes ~18 s, which confirms it measured).
  It was the **before/after oracle for the streaming refactor** (measured
  10× on CoreLocation); it now guards the `--json` array path against regression.
- **MITIGATED (memory) — the streaming text path has its own guard**
  (`streamingWholeImageMemoryStaysLowIfPresent`). The `--json` guard above bounds
  the array path; this bounds the path the refactor created —
  `disasm --image CoreLocation` (no `--json`), which decodes, analyses, renders,
  and **releases** one function at a time. Same external oracle
  (`/usr/bin/time -l`), an absolute ceiling of **200 MB** on peak footprint.

  The bound is calibrated by injection, not guesswork, and the calibration
  corrected a wrong first threshold. Measured on CoreLocation (debug): clean
  streaming **123 MB**; accumulating every analysed `DisassembledFunction` instead
  of releasing it — the realistic regression — **261 MB**; the `--json` array path
  **1,192 MB**. The array-path figure is a red herring here: it is dominated by
  `JSONSerialization` boxing every field, *not* by held function objects, so a
  "well under 1,192" bound (e.g. 500 MB) would sail past the actual failure mode,
  which tops out at 261 MB. 200 MB splits the two — ~1.6× over the 123 MB baseline,
  under the 261 MB a hold-every-function regression reaches. Proven both
  directions: the injection trips it (262 MB), the clean path clears it (123 MB).
  Host-gated on CoreLocation; ~60 s, skips cleanly without the cache.
- **UNKNOWN — no wall-time regression guard.** The memory guard above covers
  allocation; nothing guards decode *time*, which is deliberately left to a
  measured OPEN rather than a test — wall time is too machine- and load-dependent
  to assert as a stable bound without flaking.

## 6. Usability — are commands, diagnostics, and docs accurate?

- **FIXED — three README defects.** A documented command that errors
  (`--sections types,protocols` is space-separated); an entire undocumented
  subcommand (`layout`, including the `--self-index` flag that produces numbers
  the README cited); a stale measurement (49/33 → re-measured 60/39). `f549857`.
- **FIXED — the ambiguous empty-result message.** `// No functions matched.`
  covered three distinct causes including a parser failure. Now distinguishes
  "no function matched `<filter>`" from "this binary contains no recoverable
  functions", and an analysis failure throws instead.
- **FIXED — two stale doc artifacts.** A fixed defect still headlined
  `CONFIRMED DEFECT`; a shipped feature still described as "a scoped follow-up".
- **MITIGATED — exit codes are correct** except the crash above: success 0,
  bad input 1, filter-miss 0.
- **MITIGATED — whole-image `disasm` shows live progress.** A `disasm --image X`
  run is minutes long on a large framework and used to be silent, reading as a
  hang. The streaming path now reports `decompiling <done>/<total> functions…` on
  stderr, updated in place, and erases the line when done. Gated on
  `isatty(stderr)`: a redirected or piped stderr stays clean for scripting
  (verified: 0 stderr bytes when piped), and **stdout is untouched** (golden
  hashes unchanged across all five modes). Verified through a pty that the line
  advances to the total and clears. The other slow paths (`objc --image
  Foundation`, and the array `disasm` modes) do not yet report progress — this
  covers the streamed whole-image text modes only.

## 7. Reconstruction quality — how source-like is the output?

Real, but last. Everything above must hold first.

- **OPEN — L1: locals are inlined, not promoted.** `let a = x+1; let b = a*2;
  return a+b` renders `((arg0 + 1) + ((arg0 + 1) * 2))` — value-correct, but
  subexpressions are recomputed and no named locals exist. Ghidra promotes stack
  slots to `HighVariable`s. A design gap, not a bug.
- **OPEN — S1: struct-parameter decomposition is method-only.** Small integer
  structs decompose in getters (`e1a3b6a`, `73eaf73`); free-function HFA params
  (`dot(p: Point, q: Point)`) still decline.
- **OPEN — closures, existentials, generic witnesses, `throws`, `async`** render
  as low-level runtime calls rather than reconstructed control flow. Honest
  declines; large surface.
- **PLATEAU — condition naming.** ~70% of raw-register conditions are compiler
  plumbing (value witnesses, generic specializations, Codable machinery) with no
  source-level named value to recover. Investigated and documented as
  coverage-bound in `docs/research/field-map-name-collision.md`. Not a tractable
  slice; do not re-mine it without new evidence.

## 8. Validation — what independent oracle checks each subsystem?

The meta-category. Every gap here weakens confidence in every claim above.

| Subsystem | Oracle | Status |
|---|---|---|
| Function boundaries | `LC_FUNCTION_STARTS` | **Enforced** — throws on empty parse, warns below 50% recovery. The count is deduped and cross-checked against `dyld_info` in tests |
| Byte-level decode coverage | `dyld_info -function_starts` extents | **In tests + measured by hand** — 100.000% of declared slots decode; no holes inside bodies on either decoder |
| Peak memory | `/usr/bin/time -l` peak footprint | **Measured + guarded** — linear ~2.5 KB/instruction; SwiftUI 13.5 GB exceeds a 16 GB host; `MemoryRegressionTests` bounds per-instruction footprint |
| Instruction decode | `llvm-objdump` vs in-process Capstone | Two independent decoders exist; **nothing cross-checks them**. Both silent-truncation bugs found so far were in whichever decoder the other wasn't covering |
| Enum tag → case index | SIL (`swiftc -emit-sil`) | Used once, manually, to confirm the `rank` lowering |
| Field offsets | `__swift5_fieldmd`, computed offline | Runtime-exact by construction |
| Cross-image symbols | export trie | Used as the primary source |
| Recovered semantics | the compiled function itself, called via `dlsym` | **In tests** — 1,264 comparisons at both `-Onone` and `-O`: 636 integer/boolean (catches an injected U1) and 628 floating point (catches a one-ULP constant error). Narrow: no strings, payload enums, or side effects |
| Malformed-input handling | the CLI's own exit status, checked from a subprocess | **In tests** — 9 header-shaped inputs; no fuzzer, no malformed metadata |
| Whole-binary output | — | **None.** No golden-output corpus, so a silent regression on a real framework would not be noticed |

The two decoders being cross-checkable against each other is the cheapest
unexploited oracle in the project: the objdump path and the Capstone path decode
the same bytes, and the bug in `d1ca94f` existed precisely because only one of
them was ever exercised end to end.

---

## How to use this document

Pick the highest-risk **OPEN** or **UNKNOWN** item you have evidence to move.
Update its status in the same commit that changes the behavior, and record the
evidence — a command, a commit, or a file:line. An item may only be marked FIXED
if a test was observed to fail without the fix.

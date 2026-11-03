# Production readiness

What stands between swiftdc and a decompiler whose output can be trusted without
hand-checking it. Organised by **risk**, not by feature appeal.

Each item is `[status] claim — evidence`. Status is one of **OPEN**, **FIXED**,
**MITIGATED**, or **UNKNOWN**. *UNKNOWN means nobody has measured it* — it is not
a synonym for "probably fine", and an UNKNOWN in Soundness or Completeness
outranks an OPEN in Reconstruction quality.

Every claim here should carry either a commit, a file:line, or a command you can
re-run. Claims without one are marked UNKNOWN by definition.

Last audited: 2026-10-12, unified merge of all feature branches (MachOSwiftSection
0.22.0, Capstone 6, x8 indirect returns, arm64e preflight, async funclets), then a
sweep of every subcommand over 7 large apps and 5 dyld-cache frameworks (partial
when written: Prime Video, Fiery Feeds, part of Swiftcord). Re-audited the same
day against HEAD by an agent that read this file, `handoff.md` and the research
docs against the source; its stale-claim findings are corrected below.

The 2026-10-12 semantic follow-up (`0ace2da`…`4140b8c`) ends at **485
passing tests with fixture presence enforced**, including 217,728 native CCMP
comparisons and 486 native CSETM executions. Each fix's test was seen red with
that fix disabled. This is measured regression coverage of the reductions; no
overall decompilation-accuracy percentage is claimed.

The 2026-10-12 validation follow-up adds native Swift scoring and replaces
all repository Python scripts. Scoring separates agreement from coverage,
rejects duplicate analyses and ambiguous exits, and checks an optional image
UUID before reporting. The width fixture's 1,174 cases and seven independent
Swift integer-return samples all agree in live/trace checks. This is an integer
sample corpus, not an app-wide accuracy estimate. Commands and public defaults
are in [INSTRUMENTATION.md](INSTRUMENTATION.md).
Verification: `SWIFTDC_REQUIRE_FIXTURES=1 swift test` passes 530 tests in 11
suites. Signedness and duplicate-analysis scoring tests were each seen failing
under an isolated mutation, then rebuilt and passed after restoration. CLI
tests cover verified/refuted/incomplete/invalid-data exits and explicit
incomplete allowance. The Swift tooling smoke checks cover 21 fuzz subcommand
runs, the quick benchmark matrix, and identical regenerated fixture assembly
apart from its generator header.

The fuzz harness is now `swift Tools/fuzz.swift container|metadata ...`; its
`splitmix64-swift/1` sequence differs from the historical harness referenced
below. Historical seed/mutant counts remain historical evidence. The new
harness reports timeouts separately from crashes and counts subcommand runs.
The Swift benchmark checks every repeat's output and exit status. Its smoke
results do not replace previously recorded release performance measurements.

---

## 1. Soundness — can it fabricate or misattribute semantics?

- **FIXED — a structured sink without a `ret` read as falling through
  into the next label.** A block that leaves the function by a tail call
  (`b C`), or by a call with no instruction after it (`bl abort`), printed
  its call and stopped. The drain appends unvisited blocks as labels after
  the main walk, so `s9` in `tailcallsinks.c` read `C()` then
  `loc_570: B(r0)`, and -Osize `Direction`'s store-tag witness ran
  `OUTLINED_FUNCTION_33(?)` into `loc_2034: mem16[x0 + 0x1] = 0`. Neither
  happens. Every such sink now ends visibly:
  - a synchronous direct tail call, and an async function's proven return
    `br`, with `return` (`return ?` where the signature has a value);
  - anything that proves no return with `// no fall-through`: a call at the
    end of the function's code (`abort`, `__stack_chk_fail`, a `.cold`
    split), an async tail call, a suspension or executor hop, and a
    synchronous register branch nothing explains;
  - a trap (`trap()`), an `indirect_jump(…)` and an already proven exit
    (`return D.work(…)`, `throw`) unchanged.

  Blast radius against origin/dev (fixtures plus the four swift-syntax
  dylibs, structured only; pseudo, listing and JSON byte-identical): 54
  files, 804 lines. 505 `return`, 47 `return ?` and 48 `// no fall-through`
  added; 130 `} else {` and 35 flipped conditions where an arm that printed
  nothing (a hidden runtime tail call) now prints its `return`, so the
  `if` is no longer inverted around an empty arm. In unstripped inputs, 11
  sinks sat directly on a label: 6 in Reconstruction -Osize, 4 in
  SwiftIfConfig, 1 in the fixture. Others sat after a `}`. Fixture
  `tailcallsinks.c` (-O2) and `.swift` (-O); `SinkTerminatorTests`.
- **FIXED — a setter dispatch folded into an assignment of x0 whatever
  the property's type.** A vtable call to self's own setter renders as
  `self.property = value`, and the value was x0. A String is two words, so
  `label = ""` read `self.label = 0`. A Double travels in d0, so `scale =
  0.5` read `self.scale = <the setter's own address>`. The value is now
  the parameter as its type travels: one integer register, one float
  register (a constant at the type's width), or a String's two words as a
  literal, a String call result or a String field. Anything else is not
  folded. Fixture `setterfold.swift`.
- **FIXED — a stripped binary's vtable accessor named its type as the
  property.** Metadata names a vtable accessor by its kind alone,
  `Reconstruction.Counter.getter`. Read as `Owner.property.getter`, its
  type became the property: `self.Counter = (r0 + r1)` in the stripped
  Reconstruction fixtures, `self.Animal.getter()`, `self.Box.getter()`.
  An accessor whose name is its owner and its kind now reads
  `self.(unknown).getter()` and `self.(unknown).setter(v)`, and is never
  folded into a property access.
- **FIXED — a value-witness call took the registers around it as
  arguments.** A call through a value-witness table (`destroy value
  witness for X`) had no signature, so its arguments were laid out
  positionally. They gained stale registers (`genericwitness.swift`'s
  `pick` read `initializeWithCopy value witness for A(&result, …, type
  metadata for A, type metadata for A)`) or lost trailing ones (`destroy
  value witness for Swift.Optional(?)`). Each slot now takes its
  ValueWitness.def signature: destroy 2, the copies and takes 3,
  getEnumTagSinglePayload 3, storeEnumTagSinglePayload 4, getEnumTag 2,
  destructiveProjectEnumData 2, destructiveInjectEnumTag 3. Blast radius:
  30 files, 205 witness calls at their exact arity.
- **FIXED — `CalleeRegisterSummary.readsSelfRegister` was wrong
  both ways.** Its forward pass tracked writes to x0-x7, x29 and x22, but
  not x20, so a body that overwrites x20 before using it counted as
  reading its caller's x20, and the caller showed a `self:` that is no
  argument. Tracking x20 as a write was not enough: `uses` ignored any
  store of x20 to an sp-based slot as a register save, and -Onone spills
  the incoming `self` that way (`Reconstruction.Dog.init`: `str x20,
  [sp, #8]; ldr x20, [sp, #8]; bl Animal.init`). A spilled `self`
  reloaded into another register was missed outright. Now
  `Preservation.selfRegisterFlow` is a may-analysis of where the incoming
  x20 lives: registers through 64-bit moves, frame slots (offsets from
  entry sp, via `Preservation`'s sp/x29 tracking) through spills and
  reloads, unions at joins. Any other use, a store it cannot place, a
  call input, a `ret` with it in x0-x7 (`Animal.init` returns its self),
  an unplaceable load or a call while an escaped frame address may reach
  a slot holding it, is a read. Blast radius (`Tools/blast-radius.sh
  --real`): structured 6 files, 104 lines; 18 `self:` arguments dropped
  from in-image callees that load x20 before using it (`Tree.sum` on a
  by-value enum, `childNameForDiagnostics`, `resolveLexicalContext`,
  specializations of `Sequence.contains`, `_copySequenceContents`,
  `_copySequenceToContiguousArray` and the allocating and region-visitor
  inits), each checked against its body; `Dog.init(self:
  swift_allocObject(…))` and `Animal.init(self: …)` keep it.
- **FIXED — x20 was named `self` for a frozen system struct's
  non-mutating member.** Swift passes a loadable `self` as its words after
  the formals and uses x20 (`swiftself`) only for an address: an
  address-only or resilient type, or a mutating member. Read from the IR:
  `One<T>.get()` is `(i64, ptr T)`, `Date.timeIntervalSince1970` is
  `(ptr swiftself)`, and `Duration.components` is `(i64, i64)`. Only a
  hand-listed set of standard-library structs had the rule, so the
  stripped plugin library read `_ArrayBuffer._isNative.getter(self: arg0,
  …)`, the caller's x20. `SDKFrozenTypes` is generated from the SDK's
  266 macOS module interfaces: 920 `@frozen` or `@_fixed_layout` value
  types, with the methods each type or extension declares `mutating`. A
  member of one, other than a mutating method, a setter, a modify
  accessor or an addressor, takes x20 only when it holds an address.
  A resilient type such as `Date` keeps x20. Fixture `frozenself.s`.
  Blast radius: 5 files, 7 calls, among them three in-image
  `_ArrayBuffer._consumeAndCreateNew` specializations whose `self` is in
  x3 and whose x20 is only saved. Still open: a large frozen struct such
  as `Hasher` passes a non-mutating `self` by address in x20, and an
  incoming argument holding that address is not provably one, so the
  `self` is dropped rather than shown.
- **FIXED — a generic system type's metadata accessor took every live
  register.** An accessor takes the metadata request, then the type's key
  generic arguments, up to three directly and past three one pointer to
  them all (swift/lib/IRGen/MetadataRequest.cpp). Only non-generic system
  accessors had an arity, so `accessorarity.swift`'s
  `optionalType(_:_:_:_:)` read `type metadata accessor for
  Swift.Optional(0, type metadata for A, arg2, arg3, type metadata for
  A)`. `SDKMetadataAccessors` replaces `NonGenericMetadataAccessors`. It
  is a generated table of each exported accessor's key-argument count,
  `NumKeyArguments` from the `…Mn` descriptor's generic header: 17,840
  types from 205 images of the macOS 27.2 cache. `Optional` is 1,
  `KeyedDecodingContainer` 2, `Dictionary` 3, and 282 types are 4.
  Blast radius: 6 files structured, 11 listing. 45 Optional, 18 Array and
  6 Dictionary accessor calls now show exactly their arity, both gaining
  (`Optional(0)` → `Optional(0, ?)`) and losing (`Optional(0, ?, arg2,
  arg3, arg4)` → `Optional(0, ?)`, `Array(0, arg1, arg2)` → `Array(0,
  arg1)`).
- **FIXED — an untyped ObjC send after a call returning a double read by
  position.** `[o put:f() at:7]` rendered `[o put:7 at:?]`, with the 7 in
  the Double's place. The float guard stopped at the call instead of
  asking whether the call left its result in d0. Now a call counts as
  setting the send's d0 unless one of these proves it returns no float:
  its signature, its C prototype, its known C arity, or its in-image body
  (`mayWriteFloatResult`: the body writes v0 nowhere and calls out
  nowhere). `takeAfterCall` and `-[Relay relayAfterCall:to:]` now decline
  their `take:3 and:4`. `useDouble`'s body leaves `fcvtzs d0, d0` in d0,
  exactly as a function returning a double would. Fixture
  `objc_untyped_float.m`. Blast radius against d33e29b: 3 files,
  16 lines.
- **FIXED — a printf integer argument rendered its whole slot.**
  `printf("%d %hd %hhd …", -1, -2, -3, …)` read `0xffffffff, 0xfffffffe,
  0xfffffffd`. Each integer conversion now types its slot: `%d` as Int32,
  `%hd` as Int16, `%hhd` as Int8, `%ld` as Int, and the unsigned
  conversions as the UInt of that width. A Double keeps its own typing.
  Fixture `cformat.c`. Blast radius: one line.
- **FIXED — a narrow C integer argument rendered its whole register.**
  `close(-1)` read `close(0xffffffff)`. The caller writes `mov w0, #-1`,
  and the SDK table recorded only that an `int` travels in an x register.
  The generator now records a parameter narrower than a register by width
  and signedness. Of 20,279 declarations, 6,300 change, and only in those
  codes. The typed-constant rendering reads each at its type: `close(-1)`,
  `usleep(0xee6b2800)`. Fixture `cnarrowargs.c`. Blast radius: one line.
  A variadic argument's width comes from its format conversion, which is
  still open.
- **FIXED — a computed narrow integer result rendered its whole
  register.** `add16(_ x: UInt16) -> UInt16 { x &+ 72 }` read `return
  (((arg0 & 0xffffffff) + 72) & 0xffffffff)`, which is 0x10047 for 0xffff,
  where the function returns 0x47. A computed result of Int8, Int16,
  Int32, UInt8, UInt16 or UInt32 now renders at its type's low bits and
  signedness: `& 0xffff` unsigned, `((… << k) >>ˢ k)` signed. An argument
  or call result is that type already and is left as it is. Fixture
  `narrowreturns.swift`. Blast radius against b65c05b: 1 file, the
  fixture's four returns.
- **FIXED — a signatureless callee's float parameters were invisible.**
  Body-read arity counted x0-x7 only. A C callee that takes doubles
  rendered `takef3()` and `CGRectMake()`. A mixed callee rendered
  `mixed(?, 7)`, with the 7 in its Double's place. The summary now records
  the v0-v7 reads the body's own instructions make before writing them,
  and the width each is read at. A float-only callee shows its v
  arguments in order, constants typed (`takef3(?, 2.5, 4.0)`,
  `CGRectMake(1.5, 2.5, 3.5, 4.5)`). A callee with both kinds shows one
  `?` per parameter, since the body does not say how the two counters
  interleave. A float only passed on to another call is still not
  counted. Fixture `floatreads.c`. Blast radius against 8afb235,
  structured view: 13 files, 314 lines.
  - 7 calls gain their float arguments.
  - 6 outlined fragments gain theirs.
  - 145 lines are Go runtime hash helpers, whose AES bodies read vector
    registers and now show `?` parameters.
- **FIXED — a frozen standard-library struct's method took x20 as
  `self`.** A non-mutating method of a struct at most four words long takes
  `self`'s words after its formals, and an initializer or static method
  takes a thin metatype. So a scalar the caller parked in x20 printed as
  the receiver: `String.UTF16View.index(self: ((arg0 >>ᵁ 14) & 3), 15, …)`,
  `Dictionary.init(self: r0, …)`, `Double.significandWidth.getter(self:
  r0, r0)`. Now x20 is `self` for these only when it is provably an
  address: a frame slot, a static address, the function's own `self` or a
  field of it, or an `inout` parameter. A mutating member the stdlib
  declares (`append`, setters, `modify`) keeps x20 whatever it holds, and
  so does Hasher, which is passed by address. Fixture `stdself.swift`.
  Blast radius against b26d282, structured view: 9 files, 62 lines, every
  one a removed `self:`.
- **FIXED — a struct, SIMD or closure parameter was read by position.**
  `fMix(Mix(i: k, d: 1.5, j: 7), 2.0)` rendered `fMix(arg0, 7)`, with the 7
  shown as the Double. `fPt(Pt(x: a, y: 3.0), k)` rendered `fPt(arg1)`,
  with `k` shown as the Pt. `W(v: 9).take(Mix(…))` rendered
  `take(arg0, 3, 9)`, where the 9 is `self`. The layout declined the whole
  call, and the positional snapshot took its place. Now a parameter whose
  registers its type does not give, and every parameter after it, render
  `?`, while the ones before it keep their values (`fLead(arg0, ?)`). For a
  value type's method, nothing after an unplaced formal is shown as
  `self`'s words. Fixture `structargs.swift`. Blast radius against
  69bbad8, structured view: 20 files, 3,331 lines.
  - 398 values declined to `?`.
  - 350 arities corrected (`subscript.getter()` → `(?)`).
  - 234 misplaced trailing values removed.
  - The rest are nesting and binding changes that follow from these.
- **FIXED — the text path and the tracer each kept their own instruction
  semantics.** They drifted (the text path read `ubfx` as a copy while the
  tracer did not model it). `InstructionSemantics` now states a
  data-processing instruction's result once, as a term over its operands;
  the tracer evaluates it (3bfcddf, byte-identical) and the text path
  renders it. The text path gains `mul`, `eor`, `mvn`/`orn` and the zero
  extends, takes a register shift amount mod the width, and folds
  constants; it declines a division, a high multiply and a sign extension
  into a wider result. Fixtures: 54 structured lines in 8 files, each
  showing what the tested register held (Swift's overflow test `x9 != ((x1
  * x0) >>ˢ 63)`, `(x13 << (x11 & 0x3f))`, `xzr | 0x10` → `0x10`). `mov`
  keeps its own handling (the saved call result).
- **Harness — the text path's branch conditions are proven against the Arm
  ARM.** `Tools/semantics/conditions.py` renders 12,644 `definition; test;
  branch` sequences through the structurer's text path and asks z3 whether
  the text, read under the README's stated grammar, can disagree with the
  branch's NZCV. At its first run: 9,287 verified, 1,871 refuted, 212
  unparsed, in four classes fixed below. Now: 9,936 verified, 2,708
  declined, 0 refuted, 0 unparsed.
- **FIXED — a narrow integer constant rendered as its whole register.**
  `takeNarrow(-1, -2, -3, …)` (Int8, Int16, Int32) rendered
  `takeNarrow(255, 0xfffe, 0xfffffffd, …)`: right-looking, wrong values,
  found by the calling-convention study on the audit branch. A constant of
  a declared Int8/16/32 or UInt8/16/32 now reads its low bits at that
  signedness, for arguments and typed returns (`minusOne32() -> Int32`
  returns -1). No existing fixture render changes.
- **FIXED — a function without a signature had no argument values.** A
  stripped `sub_…` or a C symbol was seeded with nothing, so every value
  built from its inputs was `?` (callers passed `(?, ?)`). Such a function
  is now seeded with x0 through the highest register its own body reads
  before writing (CalleeRegisterSummary.provenArgumentCount), named argN.
  argN there is the Nth integer argument register at entry: in a stripped
  Swift function it may carry generic metadata, a witness table or a
  closure context rather than a source parameter. Registers a body only
  passes on to a call prove nothing and stay unseeded. With values now
  known, a value-type method call kept the caller's leftover registers as
  more arguments (`append(self: arg0, ?, arg2, arg3, arg4)`); a call whose
  self is proven in x20 now takes none after its formal parameters.
  Audit (stripped): tracer x0 at ret verified 0 -> 67 of 189, condition
  notes verified 0 -> 21, structured entry conditions verified 51 -> 70,
  0 refuted. Cost: enum-tag value witnesses print their computed
  condition, an unknown term inside, where a register printed before.
  OPEN: `[? put:7 at:?]` for `[o put:x at:7]` (a double in d0) at -O2 in
  libObjCUntypedFloat predates this and misplaces the integer argument.
- **FIXED — a function that wrote memory could render empty.** The
  compiler-grounded audit found 320 of 4,165 stripped swift-syntax functions
  rendering `{ return }` or no statements while their code stored outside
  the frame (setters, indirect results, caches). A store no other fact
  describes now renders as the write it is, `memN[base + off] = value`,
  N the bits it stores; an unproven part names the instruction's register,
  a call result is named by its register (not spelled again), and a store
  the tracer proves lands in the frame (sp or a register followed from it),
  an async context (including linking a callee's context to the function's
  own), an array literal or a signature-described indirect result stays
  hidden. `render.memory-write` classifies every plain store. Swift-syntax
  stripped: 13,933 frame or context, 311 described results, 7,769 shown,
  44 semantic, 0 unresolved, 0 unanalysed; 297 of the 320 now show their
  writes (23 OPEN: getters whose indirect result has a known signature but
  no rendered return). Cost: functions with a goto 542 -> 572, since a
  shared tail that now writes cannot be dropped.
- **FIXED — a function with no signature reported a `void` return.** The
  `render.return-outcome` status was `void` whenever the signature did not
  say the function returns a value, including when there was no signature:
  the compiler-grounded audit found all 109 value-returning stripped
  functions in its corpus labelled `void`. Those now report
  `no-signature`; `void` is kept for a signature that says so.
  libReconstruction -O stripped: 116 outcomes move to `no-signature`.
  Probe only: no render changes.
- **FIXED — the tracer did not model `cinc`, `cneg` or `cinv`.** The
  compiler-grounded audit (branch audit/compiler-grounded) found `absSafe`
  (`cneg; csinv`) and `classify` (`cinc` in a select chain) returning `?`:
  the aliases have two operands and fell to clobber while `csinc`, `csneg`
  and `csinv` were modelled. Each is now `cc ? f(n) : n`, its condition as
  printed (a polarity mutation gives 251 native mismatches). Fixtures:
  Reconstruction.polarity at -O and -Osize returns `((arg0 != 0) ? ((arg0 ==
  1) ? -2 : -3) : -1)` for its `switch`. Real binaries: one swift-syntax
  call argument; gamepolicyd unchanged.
- **FIXED — the tracer did not model `clz`, `cls` or `rbit`.** Each
  cleared its destination, so Swift's `leadingZeroBitCount` (and
  `trailingZeroBitCount`, `rbit` then `clz`) read `return ?`. New unary
  operators `leadingZeros`, `leadingSignBits` and `bitReverse` carry them,
  folded on constants and exported to `swiftdc-value/1`. z3: 58,514
  verified, 0 declined but the sampled `sdiv w`, 0 refuted. Fixtures:
  libUnknownReturn now reads `return leadingZeros64(arg0)` (the fixture moved
  to a popcount to keep its unknown), goProgram gains `((64 -
  leadingZeros64(r0)) * 0x13441)` as an argument, and libFixpointOrder's
  hidden target reads `bitReverse64(bitReverse64(0x364))`, still unfollowed.
- **FIXED — the tracer did not model `ror` by a register.** Capstone 6
  gives `ror x0, x0, x1` two operands, the amount as a ROR_REG shift on
  the source, which `unfoldShiftAlias` did not restore as it does for
  `lsl`/`lsr`/`asr`. The tracer now reads it as `(n >> (m & (W-1))) | (n
  << ((W - m) & (W-1)))`. z3: 58,508 verified, 6 declined (`rbit`, `clz`,
  `cls`). No fixture or real-binary line changed.
- **FIXED — the text path named a written argument register as the
  argument.** In an ObjC method it named x2–x7 `arg0`–`arg5` wherever they
  appeared: `add x2, x9, #1; cmp x2, #0` rendered `arg0 == 0`, as did a
  test of x2 after a call. A forward may-write analysis over the blocks
  now names one only where no path from entry can have written it. No
  fixture or real-binary line changed: the tracer bakes most ObjC
  conditions before the text path runs.
- **FIXED — a word-sized call result lost to the width rule.** After
  dcb4ad9, `mov x26, x0; cmp w26, #1` following
  `swift_getEnumCaseMultiPayload` read `w26 != 1`. A word test of a saved
  result now reads the call when its declared type fits in a word: the
  runtime's `unsigned` and `bool` entry points (Enum.h, HeapObject.h,
  Concurrency.h), the tag value witnesses (`UINT_TYPE`), and Swift
  signatures returning Bool or an 8- to 32-bit integer.
  ManagedBackgroundAssetsXPC: 35 lines restored; the compiler plugin
  library: 2. ObjC sends and `sub_` callees, whose result type is unknown,
  keep the register.
- **FIXED — a definition substituted at the other width.** `eor x8, x0,
  x1; cmp w8, #7` rendered `(x0 ^ x1) == 7`, and sample.debug's `mov w8,
  #-1; cmp x8, x9; b.hs` rendered `-1 >=ᵁ x9` (x8 is 0xffffffff). A
  definition of the other width keeps the register unless its value
  cannot differ (proven in [0, 2^31) where nothing else sets the width, or
  a bit test below 32); a 32-bit operand folding to constants keeps its
  register unless one number in [-2^31, 2^31). z3: refuted 746 → 0;
  goProgram 81 lines, sample.debug 5.
- **FIXED — a cmn's order read as a comparison with the negation.** `cmn
  w0, #0; b.hs` is never taken but rendered `w0 >=ᵁ -0`; with w1 =
  0x80000000, `cmn w0, w1; b.ge` disagrees with `w0 >= -w1`. An order
  renders only against an immediate (nonzero when unsigned). z3: refuted
  1,507 → 746; goProgram one line.
- **FIXED — a tst's flags read as an unsigned comparison.** `tst w0, #0xff;
  b.hs` (never taken: tst clears C) rendered `(w0 & 0xff) >=ᵁ 0`, always
  true, and `b.mi` printed `(w0 & 0xff) < 0 // 0`. Signed orders compare
  the masked value with 0, mi/pl test its sign, carry and overflow
  conditions decline. z3: refuted 1,871 → 1,507, unparsed 212 → 0.
- **Harness — the tracer's integer semantics are proven against the Arm
  ARM.** `Tools/semantics` (z3, dev host only) traces 58,515 encodings of
  the integer data-processing instructions and asks z3 whether any input
  makes the traced x0 differ from the Arm pseudocode written from the
  encoding fields. At this commit: 54,946 verified for all inputs, 1
  sampled (`sdiv w`, beyond the solver), 3,568 declined, 0 refuted. Every
  decline is an unmodelled instruction: `bic`/`bics`/`eon`, a ROR-shifted
  operand, `negs`, `mneg`, `movn`, `rbit`, `clz`, `cls`.
- **FIXED — the tracer did not model `bic`, `bics`, `eon`, `negs`, `mneg`,
  `movn` or a ROR-shifted operand.** Each left its destination unknown:
  Swift's `-O` `!flag` (`bic w0, w8, w0`) and `max(n, 0)` (`bic x0, x0, x0,
  asr #63`) rendered `return ?`. z3 check: 58,506 verified, 8 declined
  (`rbit`, `clz`, `cls`, register `ror`), 0 refuted. Fixtures: two returns
  in libReconstruction -O and -Osize. libSwiftUIMacros: nine lines, the
  capacity clamp `(r & ~(r >>ˢ 63))` and `!=` as `1 & ~(==)`.
- **FIXED — the tracer did not model the bitfield moves or `neg`.**
  `ubfx`, `sbfx`, `ubfiz`, `sbfiz`, `bfi`, `bfxil` and `neg` left their
  destination unknown. Each is now a table entry, checked against the
  hardware: `libBitfield.dylib` (`bitfield.s`, 23 functions) is called
  natively on edge inputs and every result matches the tracer's expression
  (`bitfieldMovesMatchNativeInstructionsIfPresent`). Fixtures: only
  goProgram changes (8 files), each line read back to its instruction: six
  conditions read `0 - xN`, a `ubfiz` reads `((x4 & 0x7fff) << 1)`, and
  call arguments gain the values these produce. Real binaries
  (gamepolicyd, ManagedBackgroundAssetsXPC, libSwiftUIMacros): Swift's
  `swift_task_create` flags now read `0x1c00 | (priority & 255)` from
  `bfxil`, and `Bool._bridgeToObjectiveC` gets its extracted bit.
- **FIXED — a text condition re-applied a definition that overwrote its
  own source.** `lsl x0, x0, #1; cmp x0, x8` (libReconstruction -O and
  -Osize) rendered `(x0 << 1) < x8`, shifting the result again: the
  survival check covered the instructions between definition and test, not
  the definition's own write. Such a definition now keeps the tested
  register, unless it is idempotent (`and`, `orr`, `mov`, a `ubfx` at bit
  0), where re-applying it changes nothing. Fixtures: 38 structured lines in
  6 files, each a shift or a `ubfx` above bit 0 of its own destination.
- **FIXED — a frame of 4 KiB or more was laid out at its unshifted size.**
  `ValueTracer.frameLayout` parses its prologue from text and read `sub sp,
  sp, #0x1, lsl #12` as `sp -= 1`, so every later sp-relative local sat
  4,095 bytes off and the regions that bound an escaped address's writes
  were misplaced. It now folds `lsl #n` and treats any other trailing
  operand as an unknown delta. The perf set has such frames in CoreGraphics
  (56), AppleMediaServicesKit (28), assetutil (27) and others; no fixture
  has one, and no fixture render changes.
- **FIXED — the frame layout kept a stale sp or x29 and read a register
  delta as zero.** It ignored any write of sp it did not model, so after
  Swift's dynamically sized allocation of a generic value's stack buffer
  (`sub x8, sp, x9; mov sp, x8`) every sp-relative local was placed at its
  pre-allocation offset; it ignored an `ldp`/`mov` that reloads x29; and
  `add x0, sp, x1` claimed a local at sp itself. Each misplaced boundary
  narrows how far an escaped write is assumed to reach. Once sp or x29 is
  written in a way the scan cannot follow (by Capstone's written
  registers), it claims nothing more through it, and a non-immediate delta
  is unknown. The perf set has 13,033 `mov sp, xN` (RealityFoundation
  3,292, SourceEditor 2,224, notarytool 2,154, libSwiftUIMacros 1,442,
  AppIntentsMetadataExtractor 1,236). No fixture render changes.
- **FIXED — a text-path condition named a register its value had left.**
  When the tracer bakes no condition, the structurer substitutes the tested
  register's definition (`and`, `orr`, shifts, `ubfx`, `mov`) and prints its
  source registers, which read as their values at the test. Nothing checked
  that they still held them: `and w8, w0, #0xff; add w0, w0, #1; cmp w8,
  #7` rendered `(w0 & 0xff) == 7`, and StringArity.takeOptString's `mov
  x20, x1; bl swift_bridgeObjectRetain; cbz x20` rendered `x1 != 0` with x1
  clobbered by the call. A substitution now declines when an instruction
  between writes a source (Capstone's written registers; a call clobbers
  x0–x18 and x30; an instruction without detail may write anything). A copy
  of x0 still resolves to the call it saved. Fixtures, structured view: 7
  files change, every line a previously wrong condition now reading the
  tested register (MangledTypes ×2, RuntimeArity, StringArity,
  RetainRegister, the Go float check `ubfx x13, x12, #23, #8; and x12, …;
  cmp x13, #0xff`, which read `x12 != 0xff`).
- **FIXED — a text condition dropped its operand's shift.** Capstone
  prints a shifted or extended operand as a trailing operand (`cmp x21,
  x8, lsr #1`, `cmp x0, #0x1, lsl #12`), and the text path read only the
  register or immediate: those rendered `x21 >=ᵁ x8` and `x0 == 1` (it
  compares with 4096). The compare's second operand, `tst`/`ands` masks
  and `and`/`orr` definitions now apply `lsl`, `lsr` and `asr`, fold a
  shifted immediate, and decline an extend or a rotate. Fixtures: 18
  structured files, 363 lines, each gaining the shift it lacked: Swift's
  multiply-overflow test `cmp x8, x9, asr #63` read `x8 != x9`, the array
  capacity test `cmp x21, x8, lsr #1` read `x21 >=ᵁ x8`, Go's `cmp x6,
  #0x100, lsl #12` read `>=ᵁ 0x100`. No line became `?`.
- **FIXED — the text path printed a logical and an arithmetic shift
  alike.** `lsr` and `asr` both rendered `(x0 >> 3)`, which differ on a
  negative value. They now print `>>ᵁ` and `>>ˢ`, as the tracer's
  expressions do. Fixtures: 10 structured files, 208 `>>` → `>>ᵁ`, the
  glyph the only change.
- **FIXED — the text path read a bitfield extract as a copy.** `ubfx w8,
  w0, #3, #5; cmp w8, #7` rendered `w0 == 7`. `ubfx` now renders its
  field, `((w0 >>ᵁ 3) & 0x1f)`, and `sbfx`, whose sign extension no
  operator spells, keeps the tested register. Fixtures: goProgram and its
  stripped copy change 129 conditions each, all wrong before: Go
  zero-extends a byte with `ubfx x, x, #0, #8` (250 of its 515 `ubfx`),
  so `x5 != w6` is now `(x5 & 0xff) != w6`; `sbfx x5, x5, #4, #28; cmp
  w5, #1` read `x5 == 1`. Every other fixture is byte-identical.
- **FIXED — the text path's definition search skipped a write that was
  not a first operand.** `mov x8, x1; ldp x9, x8, [sp]; cmp x8, #7`
  rendered `x1 == 7`: the walk accepted a definition only where the tested
  register was operand 0, so `ldp`'s second destination and a writeback
  base were read as not writing it. The walk now stops at any instruction
  whose written registers include it, and at one without detail. No
  fixture render changes (the previous fix had already declined the one
  fixture case, RetainRegister.enroll).
The highest-severity category. A wrong render is worse than a missing one,
because it cannot be distinguished from a right one by reading the output.

- **FIXED (`13dcbcc`) — a reloaded async context alias was lost across a
  branch or backedge while proving slot constants.** `ee37e08` scanned aliases
  linearly: one branch overwrote x19, another passed x19 + 16 to a mutating
  callee, and the latter path could be overlooked. The new bounded MAY analysis
  unions aliases across CFG predecessors and catches paired context loads.
  Missing detail, unresolved indirect flow, writeback and a convergence cap
  decline all slot proofs. `AsyncContextEscapeTests` exercises each case;
  this does not establish a complete spill/memory-alias model.

- **FIXED (`5a95c31`) — imported reference types required a direct class
  symbol to seed scalar parameters.** Qualified class/struct/enum evidence
  now comes from already-demangled trees as well as local metadata and ObjC
  symbols. Conflicting value evidence declines, including simple-name
  collisions. The imported Foundation fixture has no NSObject class symbol:
  ordinary and optional object parameters recover `note(n)`, while CGPoint
  remains a value type. `ImportedClassTests` covers AST evidence, scalar ABI,
  the compiled fixture and streaming parity. Type-kind evidence proves
  reference classification; it does not invent foreign layouts or vtables.

- **App audit, 2026-10-12.** Five independent audits ran against four of
  the author's iOS apps, each built at a recorded revision at -Onone and -O,
  each finding checked against objdump, DWARF, the source, SIL or a run of
  the reduced program. The harness is [Tools/audit](../Tools/audit/README.md);
  the full report stays local because it quotes the apps' code. Fixed so
  far: the entries below dated 2026-10-12. The remaining confirmed
  semantic errors follow as OPEN entries.
- **FIXED (`2d71612`) — a branch condition came from the wrong compare.**
  The structurer's text path stepped over flag setters it does not model
  (ccmp, ccmn, fcmp, fccmp, sbcs, ngcs, ands, bics) to an earlier `cmp`.
  - Every Swift String `==` fast path compared one word.
  - A range check compared one bound.
  - Three fixtures were rendering false claims: -Osize `intDivide`'s
    `if (x0 == Int.min) trap()` (the trap also needs x1 == -1),
    `_consumeAndCreateNew`'s `x21 >= x19`, and `flagProbe1060`'s
    `return 1` (an `msr NZCV` zeroes the flags; it returns 0).
  - The tracer invalidated flags from a list that missed ngcs and negs; it
    now uses Capstone's update_flags.
  - Such branches decline (`?`): 237, 705 and 430 on three release apps.
  - **FIXED (`fd6b868`) — bounded CCMP chains** preserve the conditional
    compare and its literal fallback NZCV, with 32/64-bit width, unsigned
    conditions and signed overflow. `ConditionalCompareOracleTests` checks
    217,728 evaluations against native ARM64. An unproven incoming condition
    or an expression past the depth bound still declines. CCMN and floating
    comparisons (FCMP/FCMPE/FCCMP/FCCMPE) remain OPEN for completeness.
- **FIXED (`a17906e`) — carry-flag branches rendered as signed
  comparisons.** b.hi/hs/lo/ls read as `> >= < <=`, so a `sub; cmp; b.hi`
  range check was false for every input below the range. They now render
  `>ᵁ >=ᵁ <ᵁ <=ᵁ`.
- **FIXED (`2292132`) — the value tracer replayed an unconverged state.**
  - Found by the first probe run: `values.fixpoint-cap` on one app function
    (20 blocks, past 1,296 iterations).
  - Cause: an unknown register is spelled both `.unknown` and absent, and
    a literal state comparison saw x9 flip between them forever.
  - Past the bound, the snapshot pass replayed optimistic meets as proof.
  - The convergence test now compares facts, and past the bound the
    analysis claims nothing.
- **FIXED — long Swift string literals render as a different literal.**
  The object word's literal is read 32 bytes past its address, the
  count-and-flags word folds in when its count is the literal's length, and
  an object word with no string there stays raw hex. On three release apps
  the 125, 89 and 83 wrong renders are gone; 37 object words stay hex. Was:
  - At -O a literal of 16 bytes or more is passed as
    `(address − 32) | 1<<63`, and swiftdc quotes the C string at
    `address − 32`.
  - A compare against one literal rendered whichever literal the linker
    placed 32 bytes earlier.
  - In one app, 0 of 151 sites rendered the true literal.
- **FIXED (`0ace2da`) — an indirect tail call or indirect await produces no statement.**
  Unresolved register branches now render `indirect_jump(target)` or a proven
  `await indirect_call(target)`; recovered jump tables and async returns keep
  their own semantics. `AuditSemanticTests` exercises closure, witness and
  class awaits, C tail transfers, and a call-produced target evaluated once.
  Previously, `callStatement` returned nil for an unresolved `br`. An `await` through a
  closure, witness or class method disappears (0 of 15, 0 of 42 and 0 of 16
  rendered in three binaries), and a function whose only call is `br x1`
  is labelled a leaf.
- **FIXED (`857c3c3`) — a single-use call result is printed at its use, across other
  calls or a branch.** `let a = next(); log(); return a` renders `log()`
  then `return next()`. Across a branch, the call disappears from one path.
  Results now bind at the original call whenever inlining crosses a block,
  another call, a store outside the frame, or an unknown instruction. Loads
  are not effects: counting the epilogue's `ldp` bound 158 fixture returns
  (`return _finalize()` became `let r0 = …; return r0`). `AuditSemanticTests`
  checks call count and order; exact literal conversions remain foldable.
- **MITIGATED (`c2ee3e1`) — a call that returns nothing still "returns" x0.** Only a
  demangled `-> ()` marks a call void, so a `.setter` or an ObjC `set…:`
  send produces a value that becomes another call's argument. Swift setters
  now invalidate x0/v0, including newly resolved vtable setters. Objective-C
  sends do the same when a proven receiver's metadata declares a void result;
  selector spelling alone does not decide it. `VoidCallResultTests` includes a
  compiled void send whose unspecified x0 previously rendered as its value.
  Callees without a proven return convention remain unknown.
- **OPEN — arguments a callee does not take.** Getters, private methods
  and value-type methods have names that decline the signature layout but
  parse, which skips the body-reads bound. The parked-x20 `self:` on an
  ordinary qualified Swift free function is fixed (`49f42ce`). Getters of
  static, class and global properties (specializations included) now take
  no arguments, and private `(name in _HASH)` callees get the signature
  layout. Getters printed with an argument fell from 605 to 531, 321 to
  251 and 816 to 785 on three release apps. A value type's method takes
  its formal parameters from x0 whether or not it is mutating, so they
  are now laid out from its signature and the registers after them kept
  as found (`swift-leading`): GoodLinks `String.append()` 308 → 2,
  `Hasher._combine()` 192 → 0, `String.hash()` 312 → 0, and
  `append(10, 0xe100000000000000)` reads `append("\n")`. Still open: a
  non-mutating method's `self` words print unlabelled after the
  parameters, and a value-type getter, which has no formal parameters,
  stays positional.
- **FIXED (soundness) — a signature with parameters on the stack read
  x0-x7 as its arguments.** A Swift signature needing more than eight
  integer (or float) registers declined whole, so the call was
  positional: `fatalError(m)` read `_assertionFailure("Fatal error", 11,
  2, ?, ?, "StaticText/statictext.swift", 19, 2)`, the count and flag
  words of two StaticStrings as arguments. The parameters that fit are
  now laid out and each one on the stack renders `?`; a StaticString
  whose first word is in a register keeps its text:
  `_assertionFailure("Fatal error", ?, "StaticText/statictext.swift", ?,
  ?)`. GoodLinks: all 494 such calls. The stack parameters are now read
  from the call's stores at their packed offsets (Apple arm64 aligns each
  word to its own size), a word only from a store of its own width:
  `("Fatal error", ?, "StaticText/statictext.swift", 14, 0)`, and in
  GoodLinks `("Fatal error", "init(coder:) has not been implemented",
  "GoodLinks/MainSplitViewController.swift", 37, 0)`.
- **FIXED (soundness) — a StaticString parameter read as three
  arguments.** A StaticString is a start pointer, a code-unit count and a
  flags byte, and with no layout for it the call fell back to one register
  per argument: `note("ready", 3)` read `note("ready", 5, 2, 3)`, and
  GoodLinks' 47 `_assertionFailure(_:_:flags:)` calls read
  `("Fatal error", 11, 2, ?, ?, 0)`, now `("Fatal error", ?, 0)`
  (`statictext.swift`).
- **FIXED (soundness) — Swift runtime entry points without a table
  arity printed positional arguments.** `swift_endAccess`,
  `swift_isUniquelyReferenced_nonNull_native`, `_Unwind_Resume` and others
  with nothing tracked read as calls that take nothing; the stack probe
  `__chkstk_darwin`, which takes its size in x9 or x15, read a stale x0
  (`__chkstk_darwin(type metadata accessor for ABIOneWord(0))`); and an
  in-image function that only forwards a register to such a call was
  summarised as reading it, so its callers showed a stale value there.
  23 entry points now have their header arity. GoodLinks: 508 changed
  lines (`swift_initClassMetadata2`, `_Unwind_Resume`, and 25 `sub_` call
  sites whose stale trailing values became `?`).
- **FIXED (completeness) — a getter's String result lost its second
  word.** The tracer marks x1 as a call's String high word only for a
  callee whose signature returns a String, and a getter prints its type
  after ` : ` with no arrow. A String parameter filled by
  `name.getter : Swift.String` read `?` (`count(?)`), now
  `count(dispatch thunk of GaugeKit.Gauge.name.getter(self: g))`. 26
  changed lines in GoodLinks (`CodingKey.init(stringValue:)`,
  `Transcript.TextSegment.init`); no fixture changes beyond
  `gaugeclient.swift`'s new `label`.
- **FIXED (soundness) — a call through a dispatch thunk took the
  requirement's metadata for arguments, or dropped its own.** A dispatch
  thunk takes `self` in x20 and its formal parameters from x0, and a
  protocol requirement's Self metadata and witness table come after them.
  Laid out positionally, `Actor.unownedExecutor.getter` read
  `(type metadata accessor for Swift.MainActor(0), …)` (800 sites in
  GoodLinks), and `scaled(by: f)` with f untracked read
  `scaled(self: g)`. Dispatch-thunk getters now take no arguments, and
  other dispatch thunks take their signature's parameters: `next()`,
  `scaled(self: g, ?)`, `TextOutputStream.write(self: s, "\n")` (was
  `write(self: s, 10, 0xe100000000000000)`). Fixtures `gaugekit.swift`
  and `gaugeclient.swift`.
- **FIXED (completeness) — an imported C enum or option set parameter was
  not seeded.** `describe(_: ComparisonResult)`, which returns its
  argument, read `return ?`: the type's width is not in its name. A
  foreign type's metadata candidate starts with its value witness table,
  which for an `NS_ENUM` or `NS_OPTIONS` the loader binds to the builtin
  integer's (`_$sBi64_WV`), so the image proves it one 64-bit register;
  `EnumCaseIndex` now records those, keyed by the C name a signature
  demangles to. `return arg0`, `if ((arg0 + 1) >=ᵁ 3)`
  (`importedenum.swift`). Standalone images with chained fixups only.
  No change to any other fixture or to GoodLinks, whose functions are
  stripped.
- **FIXED (completeness) — a subscript getter's index was dropped.** The
  no-arguments rule for static and class getters took
  `Grid.subscript.getter : (Swift.Int) -> Swift.Int` for a property, so
  `g[i]` read `Grid.subscript.getter(self: arg0)`, and Combine's
  `static Published.subscript.getter(_enclosingInstance:wrapped:storage:)`
  read `()` (178 sites in GoodLinks). A subscript is now excluded, and a
  class subscript getter is laid out from its function type like a
  method: `subscript.getter(self: arg0, arg1)`
  (`subscriptgetter.swift`).
- **FIXED — `objc_retain_xN` is modelled as returning x0.** It returns xN;
  in `@objc` thunks that named the wrong receiver. Identity runtime calls
  now match by exact name, and `objc_retain_xN` yields xN's pre-call value.
  On OpenMHz -O (396 such sites) `[r0 deselectRowAtIndexPath:…]` reads
  `[arg0 …]`, the table view; 23 receivers loaded through unknown pointers
  now decline where the stale x0 was printed.
- **FIXED — a rethrow after a cleanup call renders `return`.** The async
  throw check treated every call as overwriting x20, which is callee-saved;
  a call now writes it only when its callee summary says so. OpenMHz -O
  shows 45 throws, up from 42: the three sites the audit found.
- **FIXED — 32-bit flag setters, selects and shifts read the wrong word.**
  A W register is the low word of its X register. The tracer:
  - read W operands as the whole value (`cmp w8, w9` of 0x1_0000_0001
    compared the high bit too);
  - took `cmn`/`tst` carries from a comparison against zero;
  - left `csinc`/`csinv`/`csneg` arms unfolded and 64-bit;
  - shifted a 32-bit `asr` operand as a positive 64-bit number.
  Run natively, 367 of 1,061 constant probes in a local width-probe library
  rendered a wrong return value; after the fix, 0, with 3 declined.
  `widthflags.s` (generated by `widthflags.swift`, 1,174 probes) holds the
  line through `thirtyTwoBitFlagsAndSelectsAgreeWithNativeIfPresent`.
- **FIXED — a non-Bool call result compared with 1 is folded to
  truthiness.** `if case .paused = state` (tag 1) rendered
  `if (swift_getEnumCaseMultiPayload(?))`. Comparing with 1, or testing
  bit 0, now folds only for a proven Bool: a call declaring `Swift.Bool`
  or `Builtin.Int1`, a runtime uniqueness check, a metadata BOOL field, or
  an existing negation. Comparing with 0 stays a truth test. On three
  release apps, 60, 435 and 176 bit-0 tests and 14, 41 and 26 `== 1`
  comparisons are now explicit.
- **FIXED — a context slot changed through a reloaded context pointer kept
  its stale value.** A resume funclet reloads its own context
  (`ldr x19, [x22]`) and passes a slot's address from that copy; the
  chain-slot proof watched only addresses computed from x22 (audit B4:
  `return (7 + awaited1)` for a program returning 24). A register loaded
  from a context register's first word is now a context register too. No
  fixture or OpenMHz render changed.
- **FIXED — a typed-throws error was named as the await's result.** A
  callee declared `async throws(Code)` returns its thrown payload in x0
  (x20 = 1), and both paths resume in one funclet, so `awaited1` named the
  error in the catch block (audit B3: `TT.onError((awaited1 + 1000))`). An
  await of a typed-throws callee now binds no result; plain `throws` keeps
  `let awaitedN`.
- **FIXED (`756f27e`) — an -O `for x in array` renders as an infinite loop.**
  Return blocks are retained as loop exits, and edges to a join pass through
  the loop's transfer handler before being suppressed. The compiled
  `AuditSemantics.walk` reduction now retains its conditional `break`. With
  return blocks as exits, a loop rotated on its overflow `b.vs` printed its
  normal exit as `break` into the `trap()` after it (`accumulate`); a
  trivial tail now rotates a loop only when it has no other exit.

- **FIXED (`4140b8c`) — long literal recovery declined Unicode and NUL.**
  The counted representation now reads complete, strictly valid UTF-8 from
  `__cstring` or read-only `__TEXT.__const`, checks its terminating byte and
  section bounds, and escapes controls and backslashes. No character-count
  assumption or display truncation changes the recovered literal. The tests
  cover combining marks, emoji/CJK, embedded NUL and repeated/pooled literals.
  On three release apps, all 37 object words left as hex now render.
  Reproduce these entries with
  `Tools/audit/semantic-regressions.sh`; the corpus has independent native
  flag oracles and objdump evidence, and does not establish an app-wide
  decompilation-accuracy percentage.

- **FIXED (`ed4f157`, `0c92a85`) — Objective-C arguments were read positionally
  from x2–x7.** A `double` shifted every later argument: `[self whole:11
  fraction:2.5 object:nil tail:33]` rendered `fraction:0 object:33`, and a
  method stored its `tail` from the wrong register. Arguments now follow the
  type encoding's x/v banks at entry and at sends to self or a typed ivar; a
  conflicting or unknown receiver renders `?`.
- **FIXED (`8014828`, `2ee0578`) — a qualified type borrowed a same-named local
  type's facts.** Case names (`EnumIdentityExternal.Shade.amber`), payload
  encodings, class-ness and field names (`arg0.wrongFirst`) came from a local
  type sharing only the simple name.
- **FIXED (`096868b`) — any nominal return type read x0 as its result.** A
  one-Double struct returns in v0 and a multi-word struct in x0/x1 or x8; every
  memberwise init of a two- to four-word struct rendered `return arg0`. x0/v0
  is now read only for proven single-register types (ABISource native oracle).
- **FIXED (`096868b`) — an HFA value self was seeded before the float formals.**
- **FIXED (`e26feb7`) — variadic stack arguments slid into fixed positions.**
  `[NSArray arrayWithObjects:a, b, nil]` rendered `arrayWithObjects:0`.
- **FIXED (`ea5e58e`, `c6f23b2`, `7e9a8c7`)** — a landing pad inherited the
  entry's `self` (`Unwind_Resume(self)`); a field snapshot rendered as the
  field after a store through self; a field was named from an access's first
  byte only. Recovered from the pre-merge stash.
- **FIXED — `udiv` rendered as the signed `/`, and signed constants folded
  unsigned.** sdiv and udiv were one operator, `.divide`, folded on raw bit
  patterns: `Int(bitPattern: UInt(bitPattern: a) / UInt(bitPattern: b))`
  rendered `(arg0 / arg1)`, wrong at every negative dividend, and -7 / 2 folded
  to 0x7ffffffffffffffc. `udiv` is now `.unsignedDivide`, rendered `/` only for a
  proven UInt dividend and `/ᵁ` otherwise; `.divide` folds with sdiv semantics
  (`22df212`). The oracle's `unsignedQuotient` / `unsignedRemainderOf` failed on
  every negative input before it.
- **FIXED — the tracked flags survived a call.** `cmp; bl; cset` read the
  pre-call comparison although AAPCS64 does not preserve NZCV (`3fbbff5`,
  `FlagsAcrossCallTests` seen red). No compiled fixture reads flags across a
  call; the exposure is hand-written input.
- **FIXED — a stripped body two classes share was named after one.** At -O
  function merging gives identical methods one body; metadata named it after the
  first class read. An address claimed by two owners now goes to the existing
  fold path (`sub_…`, "N symbols folded … none can be attributed") (`e3ed073`,
  `MetadataNameOracleTests`, red with first-claim-wins restored).
- **FIXED — a call to a folded address took one candidate's name and
  argument layout.** The heading at a folded address already declined, but
  `referenceIndex` still named the address after one symbol, and a call
  laid out its arguments from that symbol's signature. libFoldedCalls -O:
  `callBox(_:)`, which is `b.plus(6)`, rendered `pairPlus(6)` and lost
  `self.a` in x1; `callPair()` named a function it does not call; the
  calling-convention study saw `takeTuple((3, 2.5), 4)` render
  `M.S2.consume(3, 4)`. A folded address is now named `sub_<addr>` for
  calls, tail calls and operand references on both front-ends (objdump's
  in-text symbol is replaced too), and a call there lays out what the
  body reads: `sub_600(6, ?)`. Kept where an owner proves the candidate:
  a vtable dispatch on self picks the one member of self's type (two
  members folded together now decline), and a load from a symbolized
  witness table picks the one candidate that is that conformance's
  witness. Candidates that all demangle to one name keep it. Fixtures:
  64 structured and 64 pseudo lines in 10 files, 328 listing lines in
  30, all a candidate's name becoming `sub_<addr>` or a witness dispatch
  naming the witness instead of the method. `FoldedCallTargetTests`.
- **OPEN — a call to a folded address loses a result every candidate
  agrees on.** libIndirect -O `wideSum` read `let r0 = Wide5.init(…);
  return (r0.a + r0.e)` (the call is `makeWide`, folded with
  `Wide5.init`); it now reads `sub_958(arg0, …, arg4)` and `return ?`.
  Both candidates return `Wide5` indirectly, so a result type all
  candidates share could be laid out without naming one. Same for
  argument layouts that agree.
- **OPEN — a body that returns an argument unchanged reads no argument.**
  libCallArity -O `callGen` calls a folded `ret` and renders `sub_3e0()`:
  the body summary does not count x0 passed through to the return as a
  read, so its argument is dropped. True of any signatureless identity
  function, folded or not.
- **OPEN — a metadata name cannot see a fold partner that has no metadata
  record.** libReconstruction -O: `Counter.value.getter` shares its body with the
  accessors of the `final` classes `BoxA.Holder` / `BoxB.Holder`, which have no
  vtable entries, so a stripped binary keeps no trace of them and the address is
  named `Counter.getter`. True of the body (the bytes are identical), but a call
  from `Holder` code reads as a `Counter` call. No metadata-only fix exists.
- **FIXED (`6018c78`) — other first-writer-wins maps at folded
  addresses.** Reproduced: `FoldRight.twiceTotal()` rendered `self.count`. `SelfTypeIndex` (`bindings[address] == nil`) and the vtable
  dispatch naming in `resolveVTableMethod` keep whichever owner reaches an
  address first, so a folded getter can bind `self` to the wrong class's fields.
  Same fix as `e3ed073`: collect every claim and decline on disagreement.
- **FIXED (`6621442`) — a `self` vtable dispatch became a proven call edge.**
  It now renders `self.member(…)` and its edge is marked self dispatch; edges
  to overrides are still absent. `Disassembler.swift` (around 1688–1706) sets `branchTarget` to
  the receiver class's own slot, but a subclass override in the image can run
  instead, and `CallGraph` records the edge as proven. Should be a possible
  edge unless the class or method is final.

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
- **FIXED — an async resume funclet's registers were seeded from its parent's
  signature.** The funclet's symbol demangles to the parent's full signature,
  so x0 at its entry was labelled `arg0`; it holds the awaited callee's result,
  and no parameter is in any register there (every live value is spilled to
  the async context, and the ABI preserves no callee-saved register across a
  suspension). It rendered: `twoAwaits`'s second await printed
  `fetchOther(arg0)` for a call whose argument is the first await's result.
  A grouped resume funclet now gets no signature-derived convention
  (`86b35be`); `resumeFuncletsDoNotInheritTheSignatureArgumentsIfPresent`
  was seen red with the seeding restored.
- **FIXED — an optional return of a value type was read from x0 alone.** Its
  nil lives elsewhere: a tag in w1 for `Int?`, an extra inhabitant for an
  enum's optional. `return ((arg0 == 0) ? 0 : (arg0 + 1))` printed nil as 0,
  and a `Tier?` printed nil as its raw tag `3`. An optional return is one
  register now only for a pointer or class payload (`8feed90`), in both the
  `Swift.Optional<T>` and `T?` spellings. `declinesTaggedOptionalReturnIfPresent`
  was seen red.
- **FIXED — int/float conversions were dropped.** `scvtf`/`ucvtf`/`fcvt`/
  `fcvtzs` passed the value through, so `Double(n) * 1.5` rendered
  `(arg0 * 0x3ff8000000000000)`, which executes as n times 4.6e18 (`b3a8510`).
  Conversions render as `Double(x)`/`Float(x)`/`Int(x)`, anchor float context
  for the constant beside them, and the int-to-float fixed-point form
  (`ucvtf d0, x0, #2`) renders `(Double(arg0) / 4.0)`.
  `recoveredConversionsAgreeWithTheCompiledCode` executes five -O conversions
  bit-exactly and was seen red.
- **FIXED — a vtable dispatch named another class's method.** The vtable index
  is keyed by simple name, so `Alpha.Node` and `Beta.Node` shared one slot table
  and `Beta.Node.work()` rendered `return (Alpha.Node.launchMissiles() +
  self.count)`. A colliding simple name now declines (`d6d0e90`);
  `doesNotDispatchThroughAnotherClassesVtableIfPresent` was seen red. Keying by
  qualified name would recover the names (needs the qualified self type).
- **FIXED — an async context slot whose address escaped was still "proven".**
  `var n = a &* 3; await Task.yield(); syncBump(&n); return n` rendered `return
  (arg0 + (arg0 << 1))` for 3a + 11: the slot's address (`add x0, x22, #0x10`)
  went to an `inout` callee. Slots from the lowest escaped offset up are no
  longer proven (`f403603`); `declinesAnEscapedContextSlotIfPresent` was seen red.
- **FIXED — `cmn` was read like `cmp`.** The structurer's text path rendered
  `if x == -1` (`cmn x0, #1; b.eq`) as `if (x0 == 1)`, and `b.mi`/`b.pl` as
  `lhs < 0 // rhs`. `cmn`/`adds` now compare with the negated operand and
  `b.mi`/`b.pl` render the sign of the difference or sum (`5d6c7b7`); both seen
  red.
- **MITIGATED — a Swift callee's arguments are not capped at its demangled arity.**
  Since `c18e6b4`, a callee whose every parameter is a proven one-register
  scalar is laid out from its signature (stale registers dropped, float slots
  from v0–v7); everything below still holds for callees outside that layout
  (String, unproven aggregates, generic and unproven optional footprints).
  `ABISourceLoweringTests` now covers proven scalar/HFA value-type self layout;
  Objective-C's typed argument banks have their own layout and tests.
  Leftover registers show up as arguments: `static Alignment.center.getter`
  (no parameters) renders `Alignment.center.getter(SwiftUI.Text.init(…))`,
  `sink(Int)` renders `P.sink(arg0, arg1)`, and a non-generic metadata accessor,
  whose body never reads x0, renders `type metadata accessor for P.Box(arg0)`.
  The demangled signature gives the count; plain float parameters (d0–d7) and
  `T?` pairs (payload, isNil) also need laying out from it, which is why
  `.frame(width: 120)` shows `_FrameLayout.init(0x405e…, 0, …)` and
  `takeOpt(nil, 420, nil)` shows six arguments. **A count cap is unsound**: it
  was tried on 2026-10-12 and reverted after a reproduction. A `String` takes x0
  and x1, so capping `sink(_: String, _: Int)` at two registers dropped the Int
  in x2 (`sink(String.init(…), ?)` instead of `sink(…, ?, arg0)`). The cap has
  to be the summed register footprint of each parameter (lib/IRGen/GenCall.cpp:
  indirect conventions 1 GPR, loadable values one register per scalar, Float and
  Double in FPRs on an independent counter, `Int?` 2 GPRs, closures 2), then
  generic metadata and witness tables, with self in x20 only for class or thick
  metatype self, and declined for any parameter whose footprint is unproven.
  The plan is in `handoff.md` section 8.
- **FIXED at -O — an async function's throw rendered as a bare `return`.** It
  returns through ResumeParent with its error in x20, zero for none. An exit
  where x20 is `swift_allocError`'s result or a non-zero constant (typed throws
  return a flag there) is a throw, and so is one reached only through the
  non-zero edge of `cbz`/`cbnz x20` with nothing writing x20 since (a resume
  passing on the error it received). `fetchOrThrow` now reads `if (arg0 < 0) {
  …; throw ? } else { return arg0 }` and `awaitThrowing`'s resume `if (x20 == 0)
  { return (awaited1 << 1) } else { throw ? }`; 24 bare returns in
  libswift_Concurrency became throws. `asyncThrowsRenderAsThrowsIfPresent` was
  seen red. At -Onone a funclet stores x22 into a slot of its own context and
  reaches ResumeParent through it at each exit; the tracer now forwards that
  store to the load (cleared at a call handed the context), so `oneAwait`'s
  resume reads `return (awaited1 + 1)` and `fetchOrThrow` both its exits
  (`ononeAsyncExitsAreProvenThroughTheContextSlotIfPresent`, seen red). Still
  open at -Onone: an exit reached through a pointer *into* the context
  (`str x9, [x8, #0x10]!` spilling `ctx + 0x10`, as `awaitThrowing`'s resume
  does), which needs a context-plus-offset pointer value.
- **FIXED — a throw merged into the normal epilogue rendered as a return.**
  At -O a throwing path can fall into the shared epilogue, one `ret` for both
  outcomes, so the merged x21 proved nothing and the path read `if (r0 < 0) {
  swift_willThrow(…) }; return r0`. The value tracer now records x21 at a
  multi-predecessor `ret` along each path; a path where it is a fresh
  `swift_allocError` box or a non-zero flag (typed throws, including the
  `str x21, [x19]; mov w21, #1` copy-out) ends `throw ?` after its last
  statement, and a `ret` every path throws to is a throw exit. Fixture
  `libMergedThrow.opt`; also `typedPick`'s shared throw block and
  `Validator.validate()`; 8 sites in libswift_Concurrency.
  `aThrowMergedIntoTheEpilogueStillThrowsIfPresent` was seen red. (The
  `return ((arg0 < 0) ? swift_willThrow(…) : …)` select form from the original
  probe no longer reproduces at HEAD.)
- **FIXED — a call into a merged (`Tm`) function named whichever type LLVM
  kept.** Function merging keeps one body for functions that differ only in
  constants and names it after one of them, so `storeEnumTagSinglePayload
  value witness for Reconstruction.OuterX.Wide` rendered a call to `merged
  storeEnumTagSinglePayload value witness for Reconstruction.IntQuad()`, and
  a merged `…WOcTm` printed one VStack type for every caller. A call site now
  keeps the kind and drops the type: `merged storeEnumTagSinglePayload value
  witness for …()`, `merged ….hashValue.getter : Swift.Int()`, `in
  conformance … : Swift.Hashable`. The merged function's own header keeps its
  symbol. Blast radius over every fixture's `--structured`/`--pseudo`, the
  plain listing and three filtered runs: only those call lines.
  `aCallIntoAMergedFunctionNamesNoTypeIfPresent` and
  `aMergedCalleeDoesNotNameItsRepresentativeType` were seen red.
- **FIXED (`096868b`) — `awaitedN` was bound for a generic or indirect async
  result.** The result is written into a buffer the caller passes in x0, so
  x0 at the resume is not it. This entry was written hours before `096868b`
  made the result register proof-based (`SwiftLowering`), which declines a
  generic `A`, a struct, `String` and `Int?` for an await as for a call; no
  test pinned the await path. Fixture `libAwaitResults` (-O and -Onone)
  awaits each shape plus `Task.value` and two `async let`s: all render a bare
  `await`, and only the `Int` control binds `let awaited1`.
  `anAwaitNamesOnlyAOneRegisterResultIfPresent` (unfiltered and filtered)
  was seen red with the type rule defaulting to x0. One gap was left: a
  closure's name prints its source type, not its convention. The `async
  let` child `implicit closure #1 @Sendable () async -> Swift.Int in
  ….useAsyncLetReturning(…) async -> Swift.Int` takes an indirect buffer in
  x0, and the name's last arrow (the enclosing function's) read as one
  register. An awaited closure now binds no result
  (`anAwaitedClosureNamesNoResult`, seen red). No render changed: that
  forwarder's branch is not yet recognised as a suspension. The system
  libswift_Concurrency binds one await result before and after
  (`AsyncSequence.contains(where:)`, a Bool in x0).
- **OPEN — an awaited result that crosses an executor hop is not followed.**
  In `libAwaitResults` each nonisolated async function hops back to the
  generic executor after its await, so the resume that receives x0 spills it
  (`str x0, [x9, #0x18]`) and the next funclet reads the slot. The chain-slot
  proof takes stores from the entry funclet only, so even `useInt` renders
  `AwaitResults.sink(?)` where `sink(awaited1 + 2)` is true. An indirect
  result needs the same, plus the buffer the caller passed (`add x0, x22,
  #0x10`): `useGeneric` reads its Int back from `[x22, #0x10]`.
- **OPEN — a closure's demangled name is read as its signature elsewhere.**
  A closure emitted at a generic abstraction returns through a buffer
  whatever its printed type, and `swiftReturnRegister(forDemangledName:)`
  returns `.integer` for the async-let closure above. Only the await path
  declines closures; the synchronous call-result and async-return paths
  still read their names. Unmeasured: how a closure whose type and
  enclosing result differ parses, and whether any render is wrong.
- **FIXED — one call could read as two.** A call consumed by both a branch
  condition and the return printed in both: `if ((Compares.sink(arg0) + …) <
  0) { trap() } else { return (Compares.sink(arg0) << 1) }` for one `bl sink`.
  A direct result rendered in more than one place is now bound like an
  indirect one (`let r0 = Compares.sink(arg0)`), its `let` spelled as the use
  would have been (`let r0 = (? as? Dog)`), and a bit-0 test of the name reads
  as the `Bool` it is (`if (r0)`). Synthesized `==` (`__derived_enum_equals`)
  stays inline: it is pure, and renders as a comparison before any binding is
  read. Measured: 8 fixture dylibs change (each a duplicate collapsing to one
  `let`); the system libswift_Concurrency gains 184 bindings, of which 8
  (`--structured`) are never read by name because the structurer's text path
  renders their uses as registers: one evaluation either way.
  `aReusedCallResultIsEvaluatedOnceIfPresent` was seen red.
- **FIXED — an ARC factory read as two allocations.** `X *x = [[X alloc]
  init]; x.limit = v; return x;` (`objc_factory_return.m`, -O2) rendered
  `[[[self alloc] init] setLimit:arg0]` then `return [[self alloc] init]`.
  An ARC method returning an object exits through a tail `b
  objc_autoreleaseReturnValue`, not a `ret`, and the use counter counted
  the ObjC return only at a `ret`. The configured object had one counted
  use, inlined, and the return printed the allocation again. It reproduced
  for `objc_alloc_init`, a custom `initWithLimit:` send, `objc_opt_new` and
  `alloc` + `initWithCapacity:`. The counter and the renderer now ask one
  predicate (`objcPassthroughReturnValue`) whether a tail branch to a
  `passthroughReturnHelpers` callee returns x0, so a rendered return is
  always a counted use: `let r0 = [[self alloc] init]`, `[r0 setLimit:arg0]`,
  `return r0`. The other tails were checked: a non-noise tail call renders
  its arguments, which were already counted; no `objc_retain`,
  `swift_retain`, `objc_release` or `swift_release` tail renders a return
  value (0 of 189 in the fixture listings). Blast radius against origin/dev (`20dcc5d`), every fixture
  and the swift-syntax dylibs: 8 files, 89 structured lines. The four
  factories collapse to one allocation each. Every other change is a
  tail-returned send that crosses its own `objc_claimAutoreleasedReturnValue`
  (or, at -O0, an `objc_storeStrong` release) and is now bound by the
  existing crossing rule: `let r0 = [arg0 stringByAppendingString:…]; return
  r0` in Sample, `_bridgeToObjectiveC()` in Sample's @objc thunks, `-[SDSDKSender
  fetch:at:]` (-O0, where the send runs before the release that the old
  inline return read as preceding it). `anObjCFactoryReturnsTheObjectItConfiguredIfPresent`
  was seen red with the tail branch not counted, and
  `anObjCFactoryWithOneUseStaysInlineIfPresent` red with it counted twice.
- **FIXED — the uniqueness check was read as the object it checks.**
  `swift_isUniquelyReferenced_nonNull_native` (the lowering of
  `isKnownUniquelyReferenced`) returns a Bool, but the renderer read every
  `isRuntimeNoise` call's result as its argument: a `-> Bool` CoW method
  rendered `return self.storage`, and the CoW branch tested a bit of the storage
  pointer. Only the retain/autorelease family is read through now; a uniqueness
  check renders `isKnownUniquelyReferenced(x)`, any other runtime result `?`
  (`07ec716`). `rendersTheUniquenessCheckAsABoolIfPresent` was seen red.
- **FIXED — an async return could print a two-register or indirect result.**
  An async function returns by branching through its context's ResumeParent,
  and the result is in x0 there only for a type proven to travel in one
  register; an indirect result arrives as a buffer pointer in x0 and the
  compiler branches through x0 itself (`7b20cfc`).
  `declinesTwoRegisterAsyncReturnIfPresent` was seen red on the `Int?` case.
- **FIXED (`a00dbe3`) — a call into a linker-deduplicated function was named
  after an arbitrary alias.** ld folds identical functions by default in a
  release link, so one address carries every folded symbol. In an -O probe
  (`func optK(_ k: K?) -> K? { k }` beside struct accessors), 11 symbols share
  one bare `ret`, and the call to it rendered `Sync3.pair(arg0)` under
  `--pseudo` and `Sync3.P2.a.modify … .resume.0` under `disasm`. The decision
  taken is decline: the call names `sub_<addr>`, as the heading does, on both
  front ends. See "a call to a folded address took one candidate's name and
  argument layout" for the fixture and tests.
- **FIXED — an unknown-arity call was shown consuming the previous call's
  result.** A callee with no signature rendered x0 left over from the last call
  as its argument: `bump(printf(…))` for `long bump(void)`. Three causes, three
  fixes. An in-image callee with no Swift signature takes the argument
  registers its body may read before writing them (`CalleeRegisterSummary`, a
  must-write dataflow over its CFG; a call or tail call inside reads them all);
  the filtered path now decodes tail-branch callees for it. A Swift callee
  returning `()` leaves x0 unknown: every synthesized `hashValue` rendered
  `Hasher._finalize(Hasher._combine(0))`. And a call counts as consumed only by
  arguments that render: once `bump` stopped taking the stale x0, `pick(twice(x),
  7, x)` was printed nowhere. In libswift_Concurrency, `swift_task_getCurrent(r0)`
  is now `swift_task_getCurrent()`. Fixture `libCallReads.{O0,O1}`;
  `aCalleeWithoutASignatureTakesWhatItsBodyReadsIfPresent`,
  `aVoidCalleesResultFlowsNowhereIfPresent` seen red. An external callee with
  no signature still shows every live argument register.
- **OPEN — `-Osize` outlined fragments render as calls.** LLVM's machine
  outliner (Swift `-Osize`, C `-Oz`) moves repeated sequences into
  `OUTLINED_FUNCTION_n` fragments reached by `bl` that keep no calling
  convention: inputs in w8, results in x1, x19/x20/x29 rewritten, a caller's
  epilogue popped. The Reconstruction fixture at -Osize has 39; 10 write a
  callee-saved register. Fixed for soundness: a callee-saved register a callee
  does not provably hand back (its entry value at every `ret` and tail branch
  out, tracked through moves, sp/x29 arithmetic and stack saves and reloads) is
  forgotten after a call to it (the tracer kept `self` in x20 across `add x20,
  sp, #8`), and the arity and Void rules above stop invented data flow. On the
  system libswift_Concurrency it flags 23 of 3,079 non-async functions (x21 for
  swifterror, C++ adapters on the swiftasync convention, the dylib's own
  `OUTLINED_FUNCTION`s); async funclets are flagged too but are never `bl`ed. In
  -Osize code a function whose epilogue is itself a fragment (`b
  OUTLINED_FUNCTION_9` restores x19/x20) is flagged as well: sound, imprecise,
  and fixed by following fragments (below). Not fixed: readability. `ReconError.hashValue` reads
  `OUTLINED_FUNCTION_36(); Hasher._combine(0); OUTLINED_FUNCTION_9(
  OUTLINED_FUNCTION_35())` where the source is `Hasher(_seed: 0)`, `_combine`,
  `_finalize`; inlining each fragment's few instructions into its caller would
  read as source. Fixtures `libReconstruction.osize{,.stripped}.dylib`.
- **FIXED for the printf family — a variadic call's stack arguments were
  dropped, and a scratch x1 read as one.** `printf`, `fprintf`, `dprintf`,
  `sprintf`, `snprintf`, `asprintf`, `syslog`, `NSLog` and
  `CFStringCreateWithFormat` now take their fixed arguments from registers and
  one stack slot per format conversion, counted from the format's own bytes
  (a `\n` kept the display resolver from rendering it); an unreadable format
  shows the fixed arguments and `…`. Fixture `libCallReads` (`printTwo`);
  `aPrintfCallShowsOneArgumentPerConversionIfPresent` seen red. The values of a
  C function's own parameters still render `?`: without a signature, x0 is the
  first integer argument, not necessarily source argument 0, so they are not
  named. Other variadics (`open`, `fcntl`, `ioctl`) are untouched. Original: Apple's arm64 ABI passes variadic arguments on the stack. On
  the TinyCC probe, `printf("%s %ld %ld\n", greet(), add3(1,2,3), sum_to(10))`
  renders `printf(0x100004020, greet())`: x1 held `greet()` only on its way to
  `[sp]`, and the `add3`/`sum_to` calls vanish from the structured view.
- **FIXED — `-f` cannot select a folded function, and its callers ignore the
  fold.** Selection: every symbol folded onto an address, raw or demangled,
  selects it, on both the range matcher and the final filter
  (`everyFoldedSymbolSelectsItsFunctionIfPresent`, seen red; five fixture
  symbols had printed "No function matched"). Callers: a direct call into a
  folded address names `sub_<addr>` and lays out what the body reads
  (`a00dbe3`, `FoldedCallTargetTests`). Original: the definition declined as
  `sub_5d8` with its candidates (`foldedByAddress`), but call sites named an
  arbitrary alias, and `disasm -f '$s1P7secondsySiAA7SecondsVF'` printed "No
  function matched" for a symbol in the export table.
- **FIXED — `xrefs --function` could not select a folded function.** The
  call graph names a folded address `sub_<addr>`, and `xrefs` matched only
  graph names, so `xrefs libFoldedCalls.dylib --function Box.plus` (and
  `_add3` on libMarkerSymbols) printed "No function matched" for a symbol
  the binary exports, while `disasm -f Box.plus` found it. `xrefs` now also
  selects a function whose folded symbols match, raw or demangled, with the
  matcher `disasm -f` uses (`foldedSymbolMatches`):
  `sub_600  0x600` with its four callers
  (`xrefsSelectsAFoldedFunctionByAnyOfItsSymbolsIfPresent`). Every folded
  text symbol in the fixtures (1,318 in 62 dylibs): 1,317 unmatched before,
  0 after.
- **FIXED (`a00dbe3`) — a call to an address that also
  carries linker marker symbols was named after the marker.** TinyCC places
  `__start_text`, `__init_array_start` and friends on `add3`'s address; the
  function header declined (`sub_100001000`) but the call was annotated
  `→ _init_array_end`. A marker is one more symbol at the address, so the
  folded-call decline covers it: fixture `markersymbols.s` (the TinyCC shape,
  hand-written) reads `sub_288(1, 2, 3)` in every view and `→ sub_288
  args(1, 2, 3)` in the listing, unfiltered and filtered
  (`aCallToAnAddressCarryingMarkerSymbolsTakesNoMarkersNameIfPresent`).
- **OPEN (reconstruction quality) — a marker symbol hides the one function
  name at its address.** `add3` and its markers decline to `sub_288`, which is
  sound but loses `add3`. A marker looks like any other `T` symbol in the
  table; ranking `add3` above it would need evidence the binary carries, not
  a guess from the marker's spelling.
- **FIXED — a float argument to a call was not tracked.** -Onone
  `Double(f) * 1.5` rendered `(Swift.Double.init() * 1.5)`: the Float argument
  is in s0 and call sites read only general registers. Call sites now snapshot
  v0–v7, and a Swift callee whose parameters are proven one-register scalars
  takes its float slots from them (`Swift.Double.init(arg0)`,
  `mixed(arg0, 2.5, arg1)`; `CallArityTests`). Callees outside that layout
  (unprototyped C functions and unproven multi-register parameters) still use
  general-register recovery. Typed Objective-C sends use independent integer
  and floating banks (`ObjCOutgoingABITests`, `ObjCNonselfOutgoingABITests`).
- **MITIGATED — the decline-rather-than-guess rule.** Verified as systematic, not
  incidental: `.unknown` renders `?` (`Disassembler.swift:2322`); the structurer
  refuses to structure an unprovable branch (`Structurer.swift:214`); `clobber`
  is deliberately over-pessimistic because under-clobbering "leaves a stale value
  that renders as a confident, fabricated" one (`ValueTracking.swift:1583`);
  the C runtime helpers in the hand list `knownCArity` (`Pseudo.swift`) are
  clamped to their arity. Swift callees and every other C callee are not: see
  the OPEN arity entries above.
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

  Currently **979 comparisons — 493 at `-Onone` and 486 at `-O`**, 17 functions
  at `-Onone` and 16 at `-O`: comparisons, ternaries, arithmetic, bit operations,
  the signed-range idiom, **integer division/remainder**, and **multi-branch
  switches**, at edge inputs including `Int.min`/`Int.max`.

  Division and remainder are the sharpest arithmetic additions: `a / b` is
  non-commutative, so operand order is executed rather than assumed, and a `udiv`
  mistaken for `sdiv` renders the same `/` yet disagrees at negative dividends —
  the U1 fabrication class, one operator over. Inputs are curated to the
  non-trapping domain (`sdiv` traps on a zero divisor and on the single
  `Int.min / -1` overflow), but deliberately keep `Int.min`/`Int.max` dividends
  against small divisors, where a signedness confusion would surface. Proven
  sensitive: an injected operand swap (`(arg1 / arg0)`) fails at every asymmetric
  input, and an injected operator confusion (`/` ↔ `%`) fails at both levels for
  both cases — before the injection, neither the `/` nor the `%` render had ever
  been executed (the evaluator's division path existed but no case reached it).

  The multi-branch switches (`gradeOf`, `polarity`) are where the two
  optimization levels tell different stories the oracle must reconcile against the
  same binary. At `-Onone` they recover as a chain of `==` ternaries; at `-O` the
  optimizer collapses `gradeOf`'s dense cases into the **U1 unsigned-range idiom
  plus arithmetic** — `((0 <= arg0) && (arg0 < 3)) ? (10 + (arg0 * 10)) : 99` — a
  jump-table→arithmetic transform whose equivalence to the original switch had
  only been reasoned about. Executed across every case value (0,1,2), the first
  default (3), and the signed edges, it now agrees with the compiled switch at
  each. Proven sensitive: corrupting the default arm (`99`→`98`) fails at both
  levels; `polarity`'s negative-constant default (`-3`→`-4`) fails at `-Onone`
  (it does not recover at `-O`, so it is required there alone).

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
    `return <expr>`, so little is lost. *Superseded 2026-10-15:* exits are now
    classified per exit, and an unproven one renders `machine_return()`; see
    "2026-10-15: Swift error exits" below.

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

- **FIXED — signature parsing read the wrong parameter list and result type.**
  Nine readers (argument registers, argument/enum/Bool/float types, the return
  register, `returnsValue`, `isThrowing`) took the *last* ` -> ` and the *last*
  `(...)` group. Three real demangled shapes defeat that:
  `f(Swift.Double, Swift.Int) throws(M.E) -> Swift.Double` (the typed-throws
  group read as one `M.E` parameter: x0, really the second argument, rendered
  `arg0`, and `0` rendered `M.E.negative`); `f(Swift.Int) -> (Swift.Double) ->
  Swift.Double` (the closure's types read as the function's; `return arg0`
  printed a stale `d0`); and `closure #1 (…) -> () in g() -> Swift.Never` (the
  enclosing function's result read as the closure's, so `return ?` on a Void
  closure). `DisassembledFunction.splitSignature` now splits at the first
  depth-0 arrow, cuts ` in <context>`, and strips `async`/`throws`/`throws(E)`.

  Reading the *real* result type exposed results that never come back in x0:
  a closure reabstracted to a generic convention returns through the x8 buffer,
  and an async function delivers its result through its context. Both now
  decline (`readsIncomingIndirectResult`, the async check in
  `swiftReturnRegister`). That also removed older fabrications on ordinary
  indirect returns, e.g. `OuterY.Wide.init` (40 bytes) printing `return arg0`,
  `ObservationRegistrar.init()` printing `return _ManagedCriticalState.init(…)`
  when it stores a different value through x8, and `-> String` witnesses
  printing `return 0`.

  The decline is now the fallback, not the answer (`3dc93d0`): x8 use is
  classified on the CFG from Capstone's operand roles (`IndirectResultUse`),
  the tracer follows the stores through the incoming x8 (and through
  `memcpy`/`memset` and the outlined copies into it), and a `ret` renders
  `return Type(field: value, ...)` only when the stores cover the result
  type's complete layout exactly, `return callee(args)` when a callee proven
  to read its own x8 filled the buffer, and nothing at all when the pointer
  escaped or a field is stored on one path only. See the Completeness entry.

  Measured old→new with `disasm --structured` on four cache images:
  libswift_RegexParser 102/2734 functions changed, libswiftObservation 38/713,
  libswiftDistributed 4/367, SwiftData 0/6506. Every change was reviewed;
  the one lost-looking label (`tryEat(self: arg0, …)` → `tryEat(…)`) had been
  derived from the *enclosing* function's `(Bool, Bool)` parameters, so its
  correctness was luck. Guarded by `SignatureSplitTests` (each of the four
  guards injected back to the old behaviour and watched fail).

  The typed-throw exit that rendered `return 0` is FIXED below.

- **FIXED — the swifterror arming value read as the callee's error.** A caller
  arms swifterror by loading x21 with its current error (zero, or a saved copy
  of the error it was handed) before a throwing call, then tests x21 after. The
  do/catch fix (`e39f64b`) invalidated x21 only when the callee's demangled name
  said ` throws`, and only in the tracer. Two consequences, both measured in
  SwiftData (`disasm --structured`/`--pseudo --image-path …/SwiftData`):
  an `@objc` thunk calling a stripped throwing method rendered `if (0 != 0)`,
  `return 1` (really `return (error == nil)`) and `swift_errorRelease(0)`; and
  the structurer's text walk-back crossed *every* call for x21, so 164
  functions rendered a post-call `cbz x21` as a test of the register x21 was
  re-armed from (`x19 != 0`), even for callees named ` throws`.

  Now the tracer invalidates an armed (zero) x21 at any callee not
  `provablyDoesNotThrow` (a C-level symbol, a value-witness/metadata helper,
  or a full Swift signature without `throws`; an unnamed callee, a
  signature-less metadata label like `Type.method`, and an accessor, whose
  demangling never shows `throws`, all may throw). The structurer stops its
  x21 walk at the same callees, except when x21 holds a call's result
  (`bl f; mov w21, w0`), which an armed x21 never is. 181 SwiftData functions
  changed in `--structured`, 10 in `--pseudo`; the other three cache images and
  every fixture are unchanged. Guarded by `SwiftErrorCalleeTests` against a new
  fixture, `Fixtures/Sample/swifterror.swift` (`-O`, plain and `strip -x`).

  The `(0 != 0)` that remains in `-Onone` value witnesses
  (`getEnumTagSinglePayload`) is faithful: the compiler emitted
  `mov w8, #0; cbnz w8`. Folding it would be a readability change.

- **FIXED — a throw exit rendered as a successful return.** A throwing
  function returns its error in x21; x0 at that `ret` is not a result. For a
  small typed error it is the error's payload, so `throw .negative` rendered
  `return 0`. Untyped throws rendered `return swift_willThrow(…)`, and a typed
  forwarder's `-Onone` error path rendered `return (typedPick(arg0) & 255)`.
  The tracer now records x21 at each `ret`. An exit is a throw only where x21
  is *proven* set: a non-zero constant (typed throws sets `w21 = 1`) or a fresh
  `swift_allocError` box. A normal exit leaves x21 as it came in, which the
  tracer never knows. It renders `throw <E.case>` when the typed error is a
  no-payload enum whose tag is in x0, else `throw ?`. A merged exit
  (`csel x21, x21, x8, eq`) proves neither and keeps its `return`. Guarded by
  `SwiftErrorCalleeTests` (two cases, so the tag→case mapping is pinned).

  Coverage gap, declined rather than guessed: an error built by a helper
  (`mov x21, x0` after `sub_…`) proves nothing, so SwiftData's throw paths
  are unchanged (0/6506 functions). Strict and loose classification
  ("any known x21") could not be told apart on any measured binary; the
  strict form is kept because it cannot over-claim.

- **FIXED — negating a branch condition by text replacement.** When the arm
  it renders is the fall-through, the structurer negates the condition. It
  did that by replacing the first operator text it found, everywhere in the
  string. Three measured failures: the `-O` range guard
  `(0 <= x) && (x < 101)` negated to `(0 > x) && (x < 101)`, never true where
  the `throw .tooBig` it guards runs; a ` == ` inside a demangled generic
  clause was rewritten (`where A.Element == Swift.String` → `!=`, SwiftData);
  and in 6 RegexParser functions that rewrite *replaced* the real negation, so
  `if (!starts<… == …>(…))` kept its `!` with a corrupted name, inverting the
  branch. `ControlFlowStructure.inverted` now rewrites an operator only for a
  single comparison at paren and generic depth zero, and wraps anything else
  as `!(…)`. Measured against `36b611e`: RegexParser 24/2734, Observation
  16/713, Distributed 5/367, SwiftData 90/6506 functions changed; besides the
  fixes above, every change is a precedence-correct wrap
  (`!x23 overflow 1` → `!(x23 overflow 1)`). Guarded by
  `ConditionInversionTests`.

- **FIXED — `swift_willThrow`'s operand read from x0.** The runtime takes the
  thrown error in x21 (`SWIFT_ERROR_RESULT`, swift/include/swift/Runtime/
  Error.h:71) and nothing in x0, so the rendered argument was whatever x0
  last held: `swift_willThrow(0)` 20 times in SwiftData, and
  `swift_willThrow(swift_errorRelease(?))` in RegexParser, where a release ran
  between boxing the error and throwing it. It now shows x21, or nothing when
  x21 is unknown. SwiftData's throws now read
  `swift_willThrow(swift_allocError(…))` (4 → 55) or the converted NSError.
  Guarded host-gated by `willThrowShowsTheErrorInX21NotX0IfAvailable`.

- **FIXED — a local passed by address kept its pre-call value.** A call that
  receives a local's address may write it, but the tracer kept the value
  stored before the call. Measured: an NSError out-parameter rendered a
  failure's error as `_convertNSErrorToError(0)` (20× in SwiftData); a value
  mutated in place through `self` in x20 rendered as its original
  (`Stack.count.getter(Stack.init())` after pushes; `String.append("Optional")`
  for a string already extended to `"Optional {"`; `self.entries =
  self.entries` across an `inout` call). A call now forgets each escaped
  local (any frame address in x0–x8, x20, or an outgoing stack argument) up to
  the next local whose address the function takes separately
  (`ValueTracer.addressTakenFrameOffsets`), never the incoming stack
  arguments, and not for `__swift_project_boxed_opaque_existential_1`, which
  only reads its container. Measured against `0c3bb54` (`--pseudo`):
  RegexParser 35/2734, Observation 3/713, Distributed 12/367, SwiftData
  250/6506 functions changed; a token scan found no changed function gaining
  a new value, only stale values removed or declined. Known imprecision: a
  spill slot inside an escaped extent that is not separately address-taken
  is also forgotten (`self: self` lost in `Event.cancel`), a decline.
  Guarded by `EscapedLocalTests` and `resolvesConcreteWitnessTableDispatch`.

## 2. Completeness — what does it silently omit?

- **FIXED — a call through a generic class's protocol witness table was
  unresolved.** A method of `Gauge<M: Meter>` calls `m.reading()` as
  `ldr x1, [isa, #0x58]; ldr x8, [x1, #8]; blr x8`: the witness table
  that follows M's metadata among self's generic arguments, word N+1
  being requirement N. VTableIndex now records, for a top-level generic
  class with only plain type parameters, each key conformance
  requirement's subject parameter and in-image protocol descriptor
  (checked against the header's key-argument count). The resolver reads
  the requirement from the protocol descriptor (24-byte header, 12 bytes
  per requirement-signature entry, 8 per requirement; Metadata.h) and
  names it only when the slot is a synchronous method, initializer,
  getter or setter and its address carries exactly one `method
  descriptor for <the protocol>.…` symbol. The call renders
  `Meter.scaled(by:) witness for A(arg0)` and takes the requirement's
  dispatch-thunk layout, so the Self metadata and table in x0 and x1 are
  no arguments; a requirement whose formals it cannot place shows `(…)`.
  libSwiftCompilerPluginMessageHandling structured, unstripped and
  `strip -x`: unresolved calls 292 → 289, the three calls of
  `handleNextMessage` named (MessageConnection.waitForNextMessage,
  PluginMessageHandler.handleMessage, MessageConnection.sendMessage).
  Fixture `classprotowitness.swift`.
- **OPEN — protocol witness calls left unresolved.** Measured on the
  plugin library and the fixture:
  - a protocol from another image (`K: Hashable`): its requirements need a
    generated table like `SDKMetadataAccessors`;
  - a non-resilient protocol has no `method descriptor` symbols, so a
    fragile build names nothing;
  - a generic function's witness tables passed after its metadata
    arguments (`genericMetadataRegisters` seeds only the metadata);
  - a table reached through a base-protocol slot (`P: Precise` calling
    Meter's requirement) or an associated conformance;
  - `CompilerPluginMessageListener.main`: x22 holds self's isa from
    before the loop, and the loop header's join of `selfFieldValue(0)`
    (entry) and `selfIsaSnapshot` (back edge) drops it, so the call
    through `[x22 + 0x68]` has no proven table;
  - an image in a dyld cache: the descriptor reads use file offsets.

- **FIXED — a class inheriting from Objective-C read its metadata through
  a masked isa the tracer did not follow.** `ldr x8, [x20]; ldr x9,
  [swift_isaMask@GOT]; ldr x9, [x9]; and x8, x9, x8` is self's class
  metadata, and every vtable call and generic-argument witness call
  through it was unresolved. The tracer now takes the isa masked with a
  slot bound to `swift_isaMask` as self's metadata. GoodLinks
  `-f ViewController` (483 indirect calls): unresolved 313 → 273, value
  witnesses named 58 → 80. Fixture `isamask.swift`.
- **FIXED — a dynamic allocation's address lost its bound at a join.** A
  register holding an allocation's address on one path and none on the
  other, and sp itself after allocations on two paths, became a frame
  alias of unknown offset, and the next call or store through it forgot
  every saved register. A join now keeps an allocation's bound: for an
  escape, as the allocation the register may point into, and for a value,
  as the higher of two bounds. Functions summarized as clobbering x29: 41
  → 30 (plugin library), 41 → 39 (libSwiftParserDiagnostics). The rest
  pass a call an address inside a saved register's slot (a dead `x8 =
  x29 - 0x10` from an earlier store) or one whose offset arithmetic the
  pass does not follow.
- **FIXED — a local inside the register save area escaped every save.**
  Swift keeps byte locals in gaps of the save area, such as the padding
  word `str x28, [sp, #-0x60]!` leaves at sp + 8. Their addresses go to
  `KeyedDecodingContainer.decode(_:forKey:)` and its kin, and counted as
  pointing at the saves. An escaped address now reaches the object it
  points at, up to the next saved value above it; only an address inside
  a saved value escapes them all. Escapes in different places keep
  separate ranges. Functions summarized as clobbering x29: 63 → 41
  (plugin library), 18 → 16 (libSwiftIfConfig), 52 → 41
  (libSwiftParserDiagnostics). Raw `mem[x29 …]` stores: plugin library
  15 → 1, libSwiftParserDiagnostics 419 → 325.
- **FIXED — a frame alias whose offset a join lost escaped every saved
  register.** x1 is `sub x1, x29, #0x48` on one path into a block and no
  frame address on the other. The join kept x1 as a possible alias but
  lost its value, and the call that received it forgot every save. That
  was the plugin library's JSONMapValue.equals(to:), whose x29 clobber
  took its callers' spilled values with it. A join now keeps the frame
  offsets such a register may hold, `mov` carries them, and an escape
  bounds them like a known local. Together with eb834b9 and b4f2968:
  functions summarized as clobbering x29, 89 → 63 of 1,519 (plugin
  library), 33 → 18 (libSwiftIfConfig), 94 → 52 of 1,594
  (libSwiftParserDiagnostics). libSwiftCompilerPluginMessageHandling:
  unresolved calls 397 → 292, value witnesses named 416 → 521, raw
  `mem[x29 …]` stores 70 → 15. libSwiftParserDiagnostics raw stores 570
  → 419.
- **FIXED — a callee that handed a local's address to a call was read as
  clobbering every register it saved.** Preservation, the pass that proves
  a callee restores x19-x29, forgot every saved slot once a frame address
  reached a call: `__swift_project_boxed_opaque_existential_1`,
  `swift_beginAccess`, `Hasher._seed` and a result buffer passed to an
  initializer all do that. The summary then claimed x29 clobbered for 204
  of the plugin library's 1,519 functions and 138 of libSwiftIfConfig's
  742, and every caller lost its frame pointer, and with it every spilled
  value, across each call. An escaped address strictly below the register
  save area now reaches only the locals under it, the extent the tracer's
  `escapedReach` gives a local. Together with the two commits before it
  (dynamic allocations, a call's real inputs): x29 clobbers 204 → 89 and
  138 → 33. libSwiftCompilerPluginMessageHandling: unresolved calls 415 →
  397, value witnesses named 394 → 416, raw `mem[x29 …]` stores 136 →
  71. libSwiftIfConfig: unresolved 126 → 119, raw stores 223 → 132.
  -Onone `wideSum` now reads `return (r0.a + r0.e)`.
- **FIXED — a dynamic allocation of unknown size escaped the whole
  frame.** `mov x9, sp; sub x9, x9, x8; mov sp, x9` with x8 unknown (a
  value-witness size read through unseeded metadata) folded `frame -
  unknown` to unknown. A frame address transformed past the tracer's
  arithmetic escapes every slot, so each later call forgot every spill.
  The tracer now keeps `frame - unknown` symbolic. It is an allocation
  below the frame (`allocationBase`, `.frameDynamic`) once sp takes it,
  and a plain escape otherwise. Fixture `unknownalloca.s`: `keptLocal`
  reads its local back (`return 5`), and the control writing through the
  allocation at an unknown index still declines. Blast radius: 6 files,
  mostly spilled arguments read back after an allocation in the
  swift-syntax libraries.
- **FIXED — a result-buffer store was hidden when no return rendered
  it.** The renderer left an indirect-result write to the return whenever
  a signature named the result. A return it could not rebuild, a type
  with no layout or a buffer a later call overwrites, read `return ?`,
  and the stores were silently dropped. `resultbuffer.s`'s
  `staleAfterKeyPath` stores five 7s that `swift_getAtKeyPath` then
  overwrites, and read only `swift_getAtKeyPath(); return ?`. The stores
  now show (`mem64[&result] = 7`) unless every exit renders the result.
  Blast radius: 40 files, 1,116 stores shown, none removed.
- **FIXED — `___chkstk_darwin` was read as an ordinary call, and a
  dynamic stack allocation after it escaped the whole frame.** A generic
  -O function sizes each buffer from a value-witness size: `mov x9, x8;
  blr x16` (the probe), `mov x9, sp; sub x8, x9, x8; mov sp, x8`. The
  probe's body (libsystem_pthread, read from the dyld cache) saves and
  restores x10 and x11 and writes only x9, the flags, and the 16 bytes
  below sp. As a call, it forgot x8, so the buffer's address was an
  unknown frame offset, and every later call forgot every frame slot. A
  value-witness table spilled to the frame and reloaded for a `destroy`
  was lost that way. The tracer now models the probe exactly, by name or
  by the GOT slot bound to it. An allocation of unknown size renders `?`;
  one of known size still renders its address. Fixture
  `chkstkwitness.swift`, a synthesized `Decodable` enum: 10 container
  destroys named. libSwiftCompilerPluginMessageHandling: unresolved calls
  430 → 415, value witnesses named 379 → 394. Seven stripped-binary sites
  now show the positional-argument limit (below): the probe used to erase
  the caller's argument registers, and an unproven external callee lists
  them, as in `type metadata accessor for Swift.Optional(0, ?, arg2, arg3,
  arg4)`.
- **FIXED — an isa kept in a register across a call lost its meaning.**
  Any call but a retain forgets every alias of a `self` field, the isa
  included, so `ldr x27, [x20]; bl ___chkstk_darwin; ldr x23, [x27,
  #0x58]` no longer read the class's generic argument B. The register
  still holds the word, and metadata never changes, so a bare `self[0]`
  alias now becomes an isa snapshot: unknown as a value, but still the
  base of vtable and generic-argument reads. Fixture `spillwitness.swift`.
  Blast radius: 4 files. Value-witness calls named in
  libSwiftCompilerPluginMessageHandling 375 → 379, unresolved calls 434 →
  430.
- **FIXED — a generic class's value-witness calls on its own type
  parameters were unresolved.** A method reads the metadata from `self`'s
  isa at the class descriptor's generic-argument offset (the
  immediate-members offset, for a class without a resilient superclass).
  `ldr x21, [x20]; ldr x2, [x21, #0x58]` is Holder<A, B>'s B. `self.b = x`
  now reads `assignWithCopy value witness for B(…)`. A class nested in a
  generic type, whose own parameters print as A1 and so on, is not named
  by position. Fixture `classwitness.swift`. Blast radius: 5 files, 17 calls
  named. Most swift-syntax sites of this shape reload the table from a
  frame slot after calls, and stay unresolved.
- **FIXED — value-witness calls on GOT-loaded metadata were unresolved.**
  `adrp x2, _$sSiN@GOTPAGE; ldr x2, [x2, …]; ldur x8, [x2, #-0x8]; ldr x8,
  [x8, #0x10]; blr x8` is Int's initializeWithCopy. The tracer follows
  the load one hop further. A slot the loader binds to `type metadata for
  X` names the call; a writable slot does not. Fixture `gotwitness.s`.
  Blast radius: 9 files, 37 calls named. Unresolved calls in IfConfig
  fell from 141 to 126, and in ParserDiagnostics from 121 to 112.
- **FIXED — value-witness calls on a demangling cache variable's metadata
  were unresolved.** Codable code fetches `KeyedEncodingContainer<CodingKeys>`
  through `__swift_instantiateConcreteTypeFromMangledName(cache)` and
  destroys it through that metadata's table. Before its first use the
  cache variable holds the relative address of the mangled name and the
  name's length negated (swift/lib/IRGen/MetadataRequest.cpp), so it names
  its type statically: `destroy value witness for
  Swift.KeyedEncodingContainer<CodableWitness.Point.(CodingKeys in …)>(?)`.
  V2's name pair is read the same way. Fixture `codablewitness.swift`. In
  the swift-syntax CompilerPluginMessageHandling dylib, unresolved calls
  fell from 504 to 440. Blast radius: 5 files, 154 calls named, nothing
  else changed.
- **FIXED (partly) — a generic function's value-witness calls on its
  own type parameter were unresolved.** An unspecialized generic free
  function receives each type parameter's metadata right after its
  formals. `pick<T>(Int, T, T) -> T` is `(sret, i64, ptr, ptr, ptr %T)`.
  Entry seeding now names those registers (`.genericMetadata`), and a call
  through `[[T - 8] + k]` is `<slot> value witness for A`:
  `load<T>(_:_:)` reads `initializeWithCopy value witness for A(&result,
  ?)`. Fixture `genericwitness.swift`. In the listing, a call taking T's
  metadata shows it as `type metadata for A`. For a callee of unknown
  arity, a stale copy could follow (`Optional`'s accessor read `args(0, ?,
  type metadata for A)`), fixed since by `SDKMetadataAccessors`. A
  function whose formals include a generic value is now seeded too, as
  that value's address: `pick` reads `initializeWithCopy value witness for
  A(&result, ((arg0 > 0) ? arg1 : arg2))`, and `gen<T>(_ a: Int, _ t: T)
  -> Int { a }` reads `return arg0`, where it read `return ?`. A tuple
  result with a generic element takes x0 and x1 for its buffers and is not
  seeded.
- **FIXED — a value-witness call on a metadata accessor's result was
  unresolved.** `bl type metadata accessor for Foundation.URL; ldur x8,
  [x0, #-0x8]; ldr x9, [x8, #k]; blr x9` rendered `/* unresolved call */`.
  The tracer now carries a load through a call's result, and through one
  load of it (`.loadedFrom`). A call through `[[accessor() - 8] + k]` is
  named `<slot k/8> value witness for X`, for the eight function slots of
  ValueWitness.def. An ordinary call's result proves nothing and stays
  unresolved. Fixtures: `accessorwitness.swift`, `staticwitness.s`. Blast
  radius against 80ccc13, structured view: 7 files, 136 lines. The
  unresolved calls in the swift-syntax CompilerPluginMessageHandling dylib
  fell from 523 to 504.
- **FIXED — a call through two pointers the image fixes was unresolved.**
  `ldur x8, [meta, #-0x8]; ldr x8, [x8, #0x28]; blr x8` calls slot 5 of a
  type's value-witness table, and it rendered `/* unresolved call */`. The
  tracer now carries a word read through a loaded pointer
  (`.loadedThrough`). The resolver follows both pointers when each is a
  rebase in read-only memory, and names the target:
  `assignWithTake value witness for CompilerSwiftOperators.PrecedenceGroup(arg1,
  arg0, 0x18da8)`. Either pointer in writable memory declines. Fixture
  `staticwitness.s`. In the swift-syntax dylibs this covers the
  static-metadata sites only. Metadata from an existential's type word or
  a generic argument is still unresolved, which is most of the 187.
- **FIXED — a struct argument this image lays out now takes its fields'
  registers.** Since b26d282 a struct parameter, and everything after it,
  rendered `?`. `SwiftLowering.aggregateRegisters` now computes a fully
  laid-out struct's registers from its field records, by the rules the
  struct-lowering oracle measured (ABI-INVARIANTS.md):
  - integer data merges per 8-byte chunk;
  - each float or double takes its own v register;
  - an Optional's tag takes its own register;
  - an empty or zero-sized field takes none;
  - more than four registers go by address.

  `fMix(?, ?)` now reads `fMix(?, 2.0)`, and each of the 17 oracle shapes in
  `structlowering.swift` places the Int after the struct. A value method
  whose receiver has float fields no longer shows an x register as part of
  `self`: `ABIVec2.scaled(5.0, sub_…())` reads `scaled(5.0)`, and
  `MD.f(3, …)` reads `MD.f(3)`. An empty struct has no field map here and
  stays unplaced. Blast radius against e2c837b, structured view: 5 files,
  52 lines.
- **FIXED — generic and class metatype parameters were not placed.**
  `container<A where A1: CodingKey>(keyedBy: A1.Type)` read `container(?)`,
  and `classMeta(Base.self, k)` read `classMeta(?, ?)`. A generic
  parameter's metatype is its metadata pointer, and a class's metatype is
  thick, one word each. A member's own generic parameters, which the
  demangler names only in the `where` clause (`A1`), now count as generic.
  A metatype slot shows a value only when it is metadata (a static
  address, a load, or an accessor result), because a callee that ignores
  its `t` leaves the caller's `k` in x0 (`describe<A>(?, arg0)`). A
  generic value-type method shows nothing past its formals, since its
  metadata follows `self` there. Fixture `metatypeargs.swift`. Blast
  radius against dc7e2c1, structured view: 8 files, 486 lines; 176
  recover values.
- **FIXED — a closure-propagated specialization's signature did not
  parse.** The demangler prints its clause with an unclosed `[`, which hid
  the arrow, so a tail call to one rendered as a bare statement, and the
  specialization's own body had no signature. The signature after `> of `
  now parses. A tail call to a function signature specialization with no
  `Return =` entry, for the same result, is a `return`. Fixture
  `closprop.swift`. Blast radius against the nested-clause fix,
  structured view: 8 files, 369 lines, all in closure-propagated
  specializations and their callers. They gain `return`, `error` for
  `x21`, `return ?` for leaves that computed an unrendered value, and
  reordered branch arms.
- **FIXED — a C string literal with a newline rendered as its address.**
  `printf("%d\n", x)` read `printf(0x1000004bc, x)`. The literal gate
  accepted printable ASCII only, and most format strings end in `\n`.
  Tab, newline and carriage return are now accepted and rendered escaped.
  They are text in a `cstring_literals` section. An earlier note blamed
  the image's first page for a dylib's `printf(0x48c, …)`; the newline was
  the cause there too. Fixture `cformat.c`.
- **FIXED — variadic, `String.Index`, string-guts, `Any.Type` and owned
  parameters were not laid out.** A call taking one fell back to reading
  registers by position. The stdlib fixes each layout:
  - `T...` is passed as its Array, one word.
  - `String.Index` is `_rawBits: UInt64`.
  - `_StringGuts` is String's own two words.
  - `_StringComparisonResult` is `case equal, less`.
  - An `Any` existential metatype is its metadata pointer alone.
  - `__owned`, `__shared`, `consuming` and `borrowing` say who releases a
    value, not how it travels.

  `print(r0, " ", 10, 0xe100000000000000)` now reads `print(r0, " ", "\n")`,
  and `_stringCompareWithSmolCheck(self.status[0..<8],
  self.status[8..<16], ?, ?, 0)` now reads
  `_stringCompareWithSmolCheck(self.status, ?, 0)`. Blast radius against
  cc1a7d5, structured view: 26 files, 2,344 lines.
  - 757 lines recover values.
  - 158 lines gain the parameters their arity was missing.
  - 195 lines are `UTF16View.index(self: …)`, where a laid-out call now
    exposes the open out-of-image value-method `self` defect (§1, ABI
    invariant 5) instead of hiding it behind a wrong arity.
  - The rest are bindings and nesting that follow from these.
- **FIXED — a stripped value witness was an anonymous `sub_`.** A
  struct's or enum's metadata record is its value witness table pointer,
  its kind and its descriptor, so the record is found by the rebase that
  points at the descriptor, and each witness by its table slot; it is
  named as its symbol demangles (`destroy value witness for
  Sample.Tree`). A function several types share is a fold and declined,
  and so is one whose body is the shape of IRGen's shared helpers (only
  copying x1 to x0, or a short straight-line body through x0, x1 and
  their copies: `__swift_memcpy40_8`, `__swift_destroy_strong`), which
  first named 358 helpers for the one type an image used them for.
  Stripped-name oracle: 190,334 → 235,241 recovered names, 0 conflicts.
  GoodLinks: 2,523 witnesses named, `sub_` functions 52,405 → 49,882.
  The cost of the shape rule: a type's own destroy that only loads one
  reference and releases it is indistinguishable from
  `__swift_destroy_strong` and stays unnamed (`sharedwitness.swift`). The
  strong helpers themselves are in that fixture too: a single-case enum
  over one reference (`enum Boxed { case one(Ref) }`) takes them.
- **FIXED — a stripped type metadata accessor was an anonymous `sub_`.**
  Each type's descriptor points at its metadata accessor
  (`accessFunctionPtr`), and `strip -x` removes a local type's `…Ma`
  symbol: libSample.stripped named 4 of its 11 accessors. They are now
  named from the descriptor, as the symbol demangles (`type metadata
  accessor for Sample.Dog`), with a local or private type's dropped
  context marked as `dump` marks it, an extension's where-clause left
  out, and imported (`__C`) types, whose descriptors do not carry the
  symbol's name, declined. Stripped-name oracle, 472 binaries: 174,029
  → 190,334 recovered names, 0 conflicts. GoodLinks: 2,806 accessors
  named, `sub_` functions 55,211 → 52,405.

- **FIXED — a stripped binary's mangled-name metadata helper was an
  anonymous `sub_`.** IRGen emits `__swift_instantiateConcreteTypeFromMangledNameV2`
  privately into every image, so stripping leaves it unnamed, and it is
  among the most-called functions: 14,770 `sub_100008a20(…)` in GoodLinks.
  Its 20-instruction body has one fixed shape (lib/IRGen/MetadataRequest.cpp),
  and an unnamed function whose body is exactly that shape, whose branch
  goes to the epilogue and whose one call is
  `swift_getTypeByMangledNameInContext` (or `…2`), is now named for it,
  marked `[recognized by its body: a helper IRGen emits]`, and treated as
  the metadata plumbing it is. GoodLinks `--pseudo`: 14,770 → 0
  references to `sub_100008a20`, 512,227 → 504,342 lines;
  `libSample.stripped`'s helper calls now match `libSample`'s exactly.
  The recogniser is now a table of helper bodies taken from the fixtures'
  own symbols (`helperShapes`): the mangled-name helper's -O and -Onone
  forms, `__swift_instantiateGenericMetadata`, and the project, destroy
  and allocate boxed-existential helpers; bodies under eight
  instructions (`memcpy` value witnesses, a lone `ret`) are left out. An
  oracle test names each helper in every arm64 fixture with its labels
  hidden and finds only the symbol's own name. GoodLinks:
  `sub_100008ce8` (2,077 calls) and `sub_100008d0c` (3,280) are now the
  project and allocate helpers. The boxed-existential helpers now leave
  out the witness-table count (`__swift_project_boxed_opaque_existential`):
  one body serves `…_0`, `…_1` and merged `…Tm` forms, and named `…_1`
  the stripped-name oracle found 430 that were `…_0` or merged. Rerun
  over the 431 binaries the oracle flagged: 87,621 names, 0 conflicts.
  Each call whose pair argument is a constant now renders as the type the
  pair's mangled name spells (`MangledNamePair`): `swift_allocObject(type
  metadata for Swift._ContiguousArrayStorage<Swift.String>, 56, 7)`. The
  name's length must equal the pair's, or nothing is claimed. Checked
  against the `…MR` symbols of `mangledtypes.swift` (12 types, 12 exact).
  GoodLinks: `type metadata for` 2,268 → 11,240; 113 calls whose pair is
  untracked stay calls.
  The table now also holds the two helpers IRGen emitted before V2,
  `__swift_instantiateConcreteTypeFromMangledName` and `…Abstract`, which
  an image from an older toolchain carries (the swift-syntax dylibs in
  Xcode 27's toolchain). Stripped, the compiler-grounded audit counted 818
  of their 5,434 unchecked direct calls going to these two unnamed bodies;
  the four dylibs now name 831 call sites (`→ __swift_instantiate…`):
  PluginMessageHandling 230, IfConfig 78, ParserDiagnostics 461,
  Operators 62. Fixture `oldmangledhelper.s`.

Silent omission is the worst failure mode: it is indistinguishable from a
correct empty answer. See the empty-result rule in `CLAUDE.md`.

- **MITIGATED — division by a constant rendered `?`.** `smulh`/`umulh` were
  unmodelled, so every -O `x / 7` lost its value. `MagicDivision` folds the
  multiply-high lowering back to `x / D` and `x % D` (`48d20d6`, seven shapes in
  libCodegen checked by the differential oracle). Since the next commit the
  fold is proven, not sampled: the tree must be the sequence LLVM emits for the
  recovered divisor with LLVM's own constants (ported from
  `DivisionByConstantInfo.cpp`, pinned to eleven compiler-emitted constants),
  and a remainder must reduce exactly to `x - D*q`. Remaining: 32-bit
  `smull`/`umull` are untracked; an unfolded multiply-high renders as the
  pseudo-operator `mulh`; a correct sequence LLVM would not emit stays
  unfolded.
- **MITIGATED — a `br xN` had no successors.** A jump table's arms were
  orphaned from the CFG (`pickByte` rendered nine `// continues at` lines and no
  case bodies). `JumpTables` now recovers LLVM's two AArch64 lowerings where the
  bound is proven: the compressed table (`ldrb`/`ldrh` entries, bounded by a
  `cmp; b.hi` whose fall-through is the table block's only entry) and arm64e's
  hardened table (`ldrsw` entries, bounded by a `csel …, ls` clamp). The
  structurer emits `switch (?) { case …: }`. Measured: 22 of 22 `br x16` tables
  in `/bin/zsh` (arm64e); Fiery Feeds has about 331 compressed tables among its
  4,790 `br`s (most of the rest are async returns). Remaining: the switch index
  renders `?`; an unrecovered `br` still has no successors and reports no gap;
  dyld-cache images decline (no file-backed table bytes).

- **FIXED — whole-binary disassembly returned nothing on most dylibs.**
  llvm-objdump right-aligns its address column; the parser required
  `allSatisfy(isHexDigit)` on everything before the first colon, so every
  instruction line of a low-based binary was dropped. Reported
  `// No functions matched.` — 0 functions where the binary had 446 (`d1ca94f`).
- **FIXED — the guard against that class.** An empty parse is now cross-checked
  against `LC_FUNCTION_STARTS` and throws `DisassembleError.parsedNothing` with
  both counts rather than returning `[]`.
- **FIXED — the call graph dropped every tail call.** `CallGraph` read only
  `bl`/`blr`, so a `b` into another function's entry added no edge. On Fiery
  Feeds 14,401 of 180,015 functions are reached only that way, and `xrefs
  --unreferenced` listed all of them as having no caller. Found with an
  independent oracle: a raw `bl`/`b` imm26 scan of `__text` (89 ms) agreed
  with the graph on every `bl` target and disagreed on exactly those `b`
  targets, each from another function. A `b` is now an edge, marked
  `(tail call)`, when it leaves its function for a recovered entry or a stub;
  one into the middle of another function is not. Test:
  `countsATailCallAsACallerIfPresent`.
- **FIXED — an x8-indirect return rendered `return ?` (or a stale x0).**
  `3dc93d0`, `17efe56`, `854ffc5`. Callee side: the stores through the
  incoming x8 that reach a `ret` on every path render field-wise against the
  result type's complete FieldMap (`OuterY.Wide.init` → `return
  Reconstruction.OuterY.Wide(v1: arg0, …)`; the resilient `IntPair.init`,
  `Vec2.init`, `Point.init` likewise), a forwarded buffer renders the callee
  (`makeWide` at -Onone → `return Indirect.Wide5.init(arg0, …)`, its `memcpy`
  folded), and a payload enum of more than four scalars names its case from
  the stored tag and its declared word-tuple payload (`return
  Indirect.Shape4.box(arg0, arg1, arg2, arg3)`, `return Indirect.Shape4.empty`).
  Caller side: a proven x8 reader of known size called with x8 into the frame
  leaves words of its result in those slots, bound once (`let r0 = makeWide(…)`;
  `return (r0.a + r0.e)`), never spelled out per field. -O constant fills
  through `ldr q`/`dup` read the `__TEXT` literal pool and nothing else.
  Measured on the shared fixtures (0c8550e tool vs `854ffc5`, `--structured`):
  libReconstruction 6 lines, .opt 2, .resilient 30, libSample 2, sample.debug
  7, every one a stale-x0 return replaced or declined. Still declines, by
  design: a generic result (its pointer escapes into the value witness), an
  existential (no stored-property layout), a result copied from a local whose
  address escaped (`escapedWide`), a payload whose scalar arity is not a
  word-tuple's (`tagged(String, Int, Int)`), and a buffer filled by an
  unknown callee. Guarded by the indirect-result section of
  `ReconstructionTests`, `PayloadEnumCaseIndexTests`, `ReturnTypeNameTests`.
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
  *from*. Measured, on CoreLocation: 2,018 of 4,126 recovered functions
  (~49%) render `sub_<addr>` — the single dominant real-output gap.

  The standard tool workaround — reading the dyld cache's **local-symbols
  region**, which is what IDA/Hopper use to name internal functions — was checked
  and **does not apply here**: on the shipping macOS cache `localSymbolsInfo` is
  nil (the `localSymbolsSize` header field is zero) and there is no separate
  `.symbols` subcache file. Local symbols are stripped from the production cache,
  so there is nothing to recover. This upgrades "partly inherent" from a claim to
  a measurement: for `--image` targets the names are *genuinely* absent, not
  merely unread. (A standalone unstripped `.dylib` on disk keeps its local
  nlist symbols; the gap is specific to cache images.)
- **FIXED — async resume funclets were anonymous, ungrouped functions.** The
  compiler splits an async function at each suspension point into an entry
  funclet plus one resume funclet per `await` (`…TQ<n>_`) or executor hop
  (`…TY<n>_`). Those are local symbols, so a stripped binary listed each as an
  unrelated `sub_<addr>` with nothing recording that it is the second half of
  some `await`. `AsyncFuncletIndex` (`3368fc8`) recovers the grouping from two
  cross-checked sources: the `__TEXT,__swift_as_entry` / `__swift_as_ret` /
  `__swift_as_cont` relative-pointer tables the compiler emits for the
  backtracer (present on a stripped system app, Stocks), and the resume-pointer
  stores in the code (a funclet materialises its successor's address before
  suspending). Without the tables it falls back to the code evidence with a
  stricter test (context allocation or a hop in the same function), so a
  synchronous function storing a plain function pointer is never grouped, and a
  suspension-free async leaf is then undetectable by construction. A declared
  funclet nothing reaches is an orphan, attached to no parent.

  Measured on `libAsyncFns` (7 async functions, 7 resume funclets, 5 await-
  return and 2 continuation): all 14 grouped with the parent, ordinal and kind
  the unstripped symbol table gives, on `-Onone`, `-O` and stripped `-O`; the
  stripped listing recovers 34 of 34 `LC_FUNCTION_STARTS` functions; the nine
  synchronous fixtures change zero output lines. A nameless funclet is titled
  `resume #N of <parent>` (source `async-funclet`), `--function` on an async
  function brings its whole chain, and the JSON carries the chain. Oracle:
  `AsyncFuncletTests.groupsFuncletsAsTheSymbolTableDoesIfPresent`.
- **FIXED — async ownership was first-wins, and suspensions sat on internal
  branches.** Any store of a declared resume address, anywhere, made its
  function the funclet's predecessor, and the first claimant won. The
  suspension was the last instruction of the basic block holding the address,
  so in a diamond it was the arm's `b` to the join. Measured on the system
  `libswift_Concurrency.dylib` (`disasm --image-path … --pseudo`): 16
  identical-code-folded funclets attached to whichever function came first,
  252 continuations rendered "how is not recovered" because their "suspension"
  was an internal `b`, and 40 loop targets named one of several awaits as their
  predecessor.

  The pre-merge stash (`983aa25`) held the strict replacement: only a resume
  pointer stored in the ResumeParent word (+8) of a `swift_task_alloc` context
  that then reaches x22 is a handoff, a funclet claimed twice is declined, and
  hint entries must be 4-aligned declared function starts. Ported alone, it
  recovered **0** of that dylib's 610 resume links. Each arm64e shape that
  defeated it is now modelled: in-place PAC signing (`pacia x16, x17`,
  `pacia1716`), the return-address check before a tail call (`tbz x16, #62;
  brk #0xc471`) splitting the call into its own block, straight-line paths
  through unconditional joins and back through unique predecessors, byte loads
  and frame stores that cannot touch a context, continuation contexts inside
  the own context (`add x22, x22, #0x10`, handed to `swift_continuation_init`),
  and the runtime waits that take the resume function as an argument
  (`swift_taskGroup_wait_next_throwing` x2, `swift_taskGroup_waitAll` x3, …,
  from `include/swift/Runtime/Concurrency.h`). Ownership is per chain: several
  sites of one chain (a loop) keep the parent but report no predecessor and no
  awaited result; two chains decline it and render "shared by N async
  functions". After: 0 orphans, 16 shared, no funclet's parent changed except
  those 16, 12 continuations name their runtime wait. The value tracer's async
  context loads and copies now require a full-width integer register
  (`AsyncPointerWidthTests`), and a function-typed result
  (`f() -> (Int) -> Int`) no longer reads as the Int its last arrow names.
  Tests: `AsyncAmbiguityTests`, `AsyncPointerWidthTests` (ported), and
  `AsyncHandoffShapeTests`, one assembled arm64e shape per rule.
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

- **OPEN — a send whose receiver is another send's result drops a known
  argument.** `objc_factory_return.m` (-O2): `[r0 setLimit:?]` with `mov w2,
  #4` right before the send, and `[r0 addObject:?]` with `x2 = @"y"`, where
  r0 came from `initWithLimit:`/`initWithCapacity:`. The same argument
  renders when the receiver comes from `objc_alloc_init` or `objc_opt_new`
  (`setLimit:arg0`, `addObject:@"x"`). A decline, not a wrong value; the
  mechanism is not yet found.

## 3. Robustness — what breaks it?

- **FIXED — a file shorter than a dyld cache header trapped four
  commands.** `disasm`, `interface`, `objc` and `analyze` on
  `Fixtures/Sample/abi_source_aliased.o` (424 bytes, `MH_OBJECT`, one
  `__text`) ended in `Trace/BPT trap` at MachOKit `DyldCache.swift:87`:
  `MachOFile.fileOffset(of:)` asks `cache` whether a standalone file is a
  dyld cache, and `DyldCache.init` reads the 568-byte header with `try!`.
  `dump` and `layout` survived only because the file has no Swift section
  to read. `BinaryLoader.load` now refuses any file shorter than that
  header with an error naming both sizes, for every command. Found by
  `Tools/blast-radius.sh`, which renders every Mach-O product; the earlier
  render scripts read only dylibs and executables. The `try!` itself is in
  the pinned MachOKit fork and is not changed.
- **FIXED — a conformance whose trailing records ran past its section
  trapped `dump`.** A conformance's flags count the records after it
  (retroactive pointer, conditional requirements, pack shapes, resilient
  witnesses, generic witness table, global actor reference). Fuzzed to 218
  pack shapes (libReconstruction.opt.stripped, seed 9001, mutant 53), the
  resilient witnesses moved 1,744 bytes on, still in the file and a
  segment, so the witness check passed them, and a requirement read there
  trapped. Preflight now requires the whole record to end inside the
  section that holds it. GaugeKit mutant 130 is also refused now: the old
  build accepted it and printed `struct GaumeKit.Tank` with its
  initializer and members gone. Seed 9001, 200 mutants:
  libReconstruction.opt.stripped 2 crashes → 0. Host corpus: 0 status
  changes.
- **FIXED — a corrupt witness table pattern trapped `dump`, `interface`,
  `objc` and `disasm`.** The conformance check read the protocol, the type
  and the resilient witnesses, not the pattern pointer at +8, which
  MachOSwiftSection resolves at whatever file offset it makes. Fuzzing
  (`Tools/fuzz.swift metadata <f> 200 9001`) set its top byte in
  libSample.stripped (mutant 122) and libGaugeKit (mutant 75), and both
  trapped with `Negative value is not representable` in
  `MachOFile.readWrapperElement`. Preflight now requires a nonzero pattern
  to land in a mapped segment. GaugeKit mutant 1 is also refused now: the
  old build accepted it and printed `protocol Ga�ge` with its three
  requirements gone. Seed 9001, 200 mutants: libSample.stripped 7 crashes
  → 0, libGaugeKit 3 → 0. `swift-version` over the 6,127-binary host corpus
  (arm64 slice of fat files): 0 status changes.
- **FIXED — a corrupt resilient witness trapped `dump`, `interface` and
  `analyze`.** The conformance check (5d17c6f) stopped at the 16-byte
  header, but MachOSwiftSection also resolves each resilient witness's
  requirement pointer, through its slot's bind, at whatever file offset the
  pointer makes. Fuzzing (`Tools/fuzz.swift metadata
  libMangledTypes.stripped.dylib 100 2024`, mutant 39) set a requirement's
  top byte and trapped with `Negative value is not representable` in
  `MachOFile.resolveBind`. Preflight now finds the witnesses at the trailing
  offset MachOSwiftSection reads them from (after the retroactive pointer,
  the conditional requirements and the pack shapes), requires the array to
  lie in the file, and requires each requirement, and each slot's rebase
  target, to lie in a mapped segment. Two more mutants (24, 86), a pack
  shape count of 255 and 165, are now rejected: the old build accepted them
  and rendered `extension Choice: Swift.Equatable {}`, the witness silently
  gone. The same fuzz run: 0 crashes in 800 (3 before); `version` over the
  6,127-binary host corpus: 0 status changes.
- **FIXED — a corrupt conformance descriptor trapped every subcommand.**
  Preflight checked that each `__swift5_proto` entry points at an aligned
  descriptor, not the descriptor: MachOSwiftSection force-unwraps its type
  reference kind and resolves its protocol and type pointers unchecked.
  Fuzzing with `__const` in reach (`Tools/fuzz.swift metadata
  libReconstruction.opt.stripped.dylib 100 31337`) found three: a kind of
  4 (mutant 54), a protocol slot rebased to junk (55), a type reference
  moved out of the file (88), 21 crashing runs. Each conformance's kind
  must now be one of the four the ABI defines, its protocol a context
  descriptor directly or through a slot (a zero slot is one classic bind
  opcodes fill, and is not judged), and its type reference valid for its
  kind. The same fuzz run: 0 crashes in 800; `version` over the 6,127-binary
  host corpus: 0 status changes.
- **FIXED — a corrupt mangled-name pair trapped `disasm`, `xrefs` and
  `analyze`.** The `type metadata for T` rendering (748222e) demangles a
  name a code-side pair points at, which preflight never validated: it
  checks the names metadata records start. Fuzzing with `__const` in reach
  (`Tools/fuzz.swift metadata`, 60 mutants each, seed 777) trapped two
  fixtures: a corrupt fixup top byte made an indirect reference's slot a
  rebase onto junk (libMangledTypes.stripped, mutant 56), and a corrupt
  direct reference offset in `__swift5_typeref` named a "context" outside
  the file (libSample.stripped, mutant 11), both `Negative value is not
  representable` in MachOKit. A pair's name must now lie in
  `__swift5_typeref`, pass preflight's own reference validation, and have
  every indirect slot be a bind or a rebase onto a valid context
  descriptor. The same fuzz runs: 0 crashes in 960.

- **FIXED (upstream) — MachOKit read an empty `seg_info_offset` as a segment's
  starts.** Recorded against the 0.52.102 fork (`07d7633`): a zero
  `seg_info_offset` ("no fixups in this segment") was resolved as a starts
  record at offset 0, and a three-segment dylib read 32 KB past its mapping.
  MachOKit 0.54.101 skips it (`guard offset != 0` in
  `MachOFile+DyldChainedFixups.swift` `startsInSegments(of:)`, mirrored for
  `MachOImage`), and the current fork (`4c4738f`) is 0.54.101 plus one unrelated
  change. Verified against the source, not by re-running the original
  40-iteration loop.
- **FIXED — an ivar whose offset is computed at load time trapped `objc`,
  `xrefs`, `disasm` and `analyze`.** A Swift class whose stored properties
  follow a resilient-size one (a Foundation `Date`) keeps its field offsets in
  zero-fill `__common`, and ObjCDump `try!`-reads them as if file-backed. On
  Prime Video the slot maps past the end of the file: at origin/master four of
  eight subcommands died by SIGTRAP with no output (`objc` at 0.5 s; `xrefs`,
  `disasm --structured`, `analyze` after 488–569 s and 4–6 GB). Inside the file
  the read returns padding (offset 0). Such ivars are now recorded at
  `ObjCMetadataSnapshot.runtimeIvarOffset` and never named in a field map
  (`267e341`); `recordsLoadTimeIvarOffsetsAsRuntimeIfPresent` was seen red.
- **FIXED — a C string read at a zero-fill address ran `strlen` off the
  mapping.** `ReferenceResolver.name(at:)` read a string at any unnamed operand
  address through `fileOffset(of:)` + `readString`; an `adrp` to a `__common`
  global on Prime Video pointed past the end of the file, and the scan faulted
  whenever the next page was unmapped (`objc` SIGSEGV after 282 s in one run,
  exit 0 under lldb). Standalone images now read strings only from file-backed,
  non-zero-fill bytes, bounded by the segment and 4 KB, at all three sites
  (`1741748`).
- **FIXED — the preflight's zero-fill table had 0x13 for 0x12.** 0x13 is
  `S_THREAD_LOCAL_VARIABLES` (file-backed TLV descriptors), 0x12 is
  `S_THREAD_LOCAL_ZEROFILL`, so a large `__thread_bss` would have been refused and
  an overrunning `__thread_vars` passed (`bc344aa`, both directions tested red).
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
- **FIXED — a structurally valid Mach-O missing an expected segment trapped.**
  Renaming `__TEXT` to `__TEXTX`, or letting an unknown `cmd` hide `__LINKEDIT`,
  is valid ASCII in a legal layout, and MachOKit aborted on it: exit 133 from
  `dump`, `interface`, `disasm` and `analyze` (and `objc` for the `__LINKEDIT`
  case), with empty stderr.

  This was recorded as uncontainable, on the grounds that "require a segment
  named `__TEXT`" would reject object files, which carry one unnamed segment.
  That holds for a blanket rule but not for dyld's own. `dlopen` on each
  re-signed mutant names three distinct checks, applied to loadable images
  only (`MH_EXECUTE`, `MH_DYLIB`, `MH_BUNDLE`): a section's `segname` must
  match its containing segment ("section '__text' segment name '__TEXT' does
  not match containing segment's name '__TEXTX'"), "missing __TEXT segment",
  and "malformed mach-o has no LINKEDIT". `MachOPreflight` now applies exactly
  those, after walking every load command. An object file is exempt: its one
  unnamed segment holds `__TEXT`, `__DATA` and `__LD` sections, and it still
  analyzes (exit 0).

  Measured: every subcommand on the three mutants now exits 1 with dyld's
  reason. A sweep of 328 real on-disk Mach-O files (`/bin`, `/usr/bin`,
  `/usr/sbin`, Xcode dylibs, app and kext binaries) gave 0 rejections and 0
  crashes. Guarded by the segment tests in `MachOPreflightTests`.

  Two more of dyld's rules close the rest of the class the fuzz still found:
  "section '…' end address … is beyond containing segment's end address …"
  (a flipped top byte of a section `addr`; SIGSEGV/SIGTRAP), and "chained
  fixups, seg_count exceeds number of segments" (a flipped `cmd` byte turns a
  segment into an unknown command and its memory vanishes; SIGSEGV). The
  address rule skips unmapped segments and debug sections: a Go binary's
  `__DWARF` (`vmsize` 0, `S_ATTR_DEBUG`, sections sized past its empty range)
  loads under dyld, and the first version of the rule falsely rejected
  `com.docker.build` in the real-binary sweep.

  Measured with `Tools/container-fuzz.py Fixtures/Sample/libSample.dylib 120 7`
  plus a second 120-mutant set drawn in a different RNG order: **6 + 3 crashes
  before (`0c3bb54`), 0 now.** Every mutant rejected with a dyld-attributed
  message (92) is one dyld also refuses after re-signing; 0 disagreements. A
  real-binary sweep of 465 on-disk Mach-O files (system, Xcode, apps, kexts,
  fat and thin): 0 rejected, 0 crashed.
- **MITIGATED — a bounded container fuzz exists, and its yield is measured.**
  It is now committed as `Tools/container-fuzz.py` (seeded, deterministic;
  exits nonzero on any crash). History: 3 crashes in 120 (2.5%) after the
  payload fix; 0 in 240 after the dyld-rule preflight above. Still run by
  hand, not a CI gate.
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
  (covered by `buildsObjCIndexWithoutTrappingOnSpuriousCacheMarkers`). The
  markers were never real: the iOS simulator's frameworks are linked
  `-interposable`, so a class-list slot pointing at an exported class holds a
  bind to the image itself, and MachOObjCSection 0.8.105 resolved rebases only,
  so those classes were read from the wrong place. The guard kept the process
  alive but skipped them: `objc` on the iOS 18.3 simulator's
  `UIKit.axbundle/UIKit` printed 6 of its 853 classes. MachOObjCSection 0.8.110
  resolves the self-bind (its `f17ace7`); at the 0.22.0 pin the same command
  prints all 853 (the `__objc_classlist` size, 0x1aa8 / 8) plus its 6
  categories, and the guard filters nothing. The test now asserts that.
- **FIXED — a dylib command's name offset outside its command trapped
  `dump`/`interface` at the 0.22.0 pin.** New trap class, opened by the
  upgrade: the class dumper's ObjC ancestor walk reads
  `MachOFile.dependencies`, and MachOKit's `DylibCommand.dylib(in:)` reads
  each name with `try! readString` at the command's `name.offset`.
  `Tools/container-fuzz.py Fixtures/Sample/libSample.dylib 150 7` mutant 63
  and `sample.release 150 7` mutant 104 died by SIGTRAP on 0.22.0 and failed
  cleanly on 0.19.0 (0 crashes, same seeds). `MachOPreflight.validateDylib`
  requires `24 <= name.offset < cmdsize` on the six dylib command kinds;
  both mutants now decline with rc 1 on every subcommand. Covered by
  `rejectsADylibNameOffsetOutsideItsCommand` (seen red) and
  `acceptsAWellFormedDylibCommand`.
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
  | `__swift5_assocty` | SIGTRAP + SIGSEGV | dump, interface, analyze (now contained: walked by record layout, 2026-10-10) |
  | `__objc_methlist` | SIGSEGV | objc, objc --methods, disasm, xrefs, analyze (now contained for relative lists, 2026-10-10) |
  | `__swift5_mpenum` | SIGTRAP | objc, disasm, analyze (found 2026-10-10; contained the same day) |
  | `__swift5_fieldmd` | SIGTRAP | objc, layout, disasm, xrefs, analyze (found on `sample.release`, seed 4242; contained) |
  | `__swift5_proto` into code | SIGTRAP | dump, analyze (an in-file target inside `__text`; contained) |
  | `__swift5_builtin` | SIGTRAP | dump, interface, objc, layout (found on `libReconstruction.opt`, seed 777; contained) |
  | `__swift5_typeref` | SIGTRAP | dump, interface (symbolic references; contained, parsed only from names records point at) |
  | `__swift5_mpenum` spare bits | SIGTRAP | analyze (`Index out of range` on a mask the record cannot hold; contained) |
  | `__objc_selrefs`, `__objc_classlist`, `__objc_nlclslist`, `__objc_catlist` | SIGSEGV/SIGTRAP | contained: each slot's decoded target must land, aligned, in the section that kind of slot names |
  | `__objc_const`, `__objc_data` | SIGSEGV/SIGTRAP | contained: classes walked through their pointer fields only (table below) |

  **`sample.release`, seed 4242, 150 mutants: 114 → 76 → 28 crashes in 1200
  runs (2026-10-10).** The pointer *arrays* are now checked slot by slot:
  chained-fixup formats 2 and 6 decoded (binds checked against the import
  table, other formats declined), plain pointers read as addresses, and each
  rebase required to land (8-aligned for classes and categories) in the section
  that kind of slot names on 1,058 real thin binaries (453k selrefs, all in
  `__objc_methname`).

  **Then 28 → 0.** `__objc_const`/`__objc_data` interleave pointers with
  flags, sizes and offsets, so each class named by a class list is walked
  through the fields that are always pointers, and each must land where it
  does in all 44,323 classes of those 1,058 binaries:

  | field | lands in (rebase), else |
  |---|---|
  | class / metaclass `isa` | `__objc_data`, `__data` (8-aligned); metaclass also null/bind |
  | `superclass` | `__objc_data`, `__data`; null; bind |
  | `cache` / `vtable` | bind or null / null only |
  | `data` (low 3 bits masked) | `__objc_const` or `__objc_data` (both hold `class_ro_t`) |
  | `ro.name` | `__objc_classname`, `__cstring`, `__const` |
  | `ro.baseMethods` (bit 0 masked, 4-aligned) | `__objc_methlist`, `__objc_const`, `__objc_methname`; null |
  | `ro.ivars` / `baseProtocols` / `baseProperties` | `__objc_const`; null |
  | ivar layouts | `__cstring`, `__objc_classname`; null |
  | ivar list (entsize 32) | offset in `__objc_ivar`/`__const`/`__data`/`__common`/`__bss`; name in `__objc_methname`/`__cstring`; type in `__objc_methtype`/`__cstring` |
  | property list (entsize 16) | name and attributes in `__objc_methname`/`__cstring` |

  A raw zero is a null field outside every fixup chain, not a rebase to the
  image base (the first prototype got this wrong and misread 3,000+ nulls).
  Measured: both metadata fuzz sets now 0 crashes (`libSample.dylib 100 1234`:
  0/800; `sample.release 150 4242`: 0/1200), the container fuzz 0/120, 0 false
  rejections on the 1,058 binaries, and every one of the 48 class-walk
  rejections in the two fuzz sets names a field the mutation changed.

  **A third binary and seed (`libReconstruction.opt.dylib 150 777`): 44 → 0.**
  It found `__swift5_builtin`, `__swift5_typeref`, the multi-payload enum
  spare-bit mask, a bind planted in a `class_ro_t` field, and a corrupt
  metaclass `class_ro_t`. Binds never occur in any `class_ro_t` field or list
  entry of the 1,058 binaries (only in `cache`, `superclass` and the metaclass
  `isa`/`superclass`), so they are refused there, and metaclass read-only data
  is walked like a class's.

  **A resilient build (`libReconstruction.resilient.dylib 150 31`): 6 → 0.**
  Two `__swift5_proto` mutants aimed a conformance entry into the middle of a
  descriptor. Descriptors are 4-byte-aligned records: every entry of
  `__swift5_proto`/`__swift5_types`/`__swift5_protos`/`__swift5_types2` in the
  1,058 binaries (556,643 of them) targets an aligned word, so a misaligned
  target is refused.

  **A fresh seed on the executable (`sample.release 150 99`): 10 → 0.** Both
  mutants flipped `next` bits of a chained pointer (`__objc_selrefs`,
  `__objc_data`). The chain then skipped slots, and MachOKit read a skipped
  slot's raw chained bits as a plain address, so a MachOObjCSection `try!`
  trapped. Preflight walks every fixup chain the way dyld does, from each
  page start, refusing one that leaves its page, lands on a slot that is not
  4-byte aligned, or binds past the import table. It records the slots the
  chains reach, and a nonzero Objective-C pointer slot or class field
  outside them is refused. Measured: every one of 3.94 million ObjC
  pointer-array slots in the chained images of four corpora (1,058 + 832
  thin, 1,434 arm64e system binaries, 1,609 universal binaries under
  /Applications) is a chain entry.

  **Universal binaries were not checked at all until 2026-10-10.** Every
  section-content check ran only for thin files, so a fat file's slices
  reached MachOKit with nothing but their headers validated: the selref
  mutant above, wrapped by `lipo -create`, still trapped in
  `objc --arch arm64` (exit 133). Each 64-bit slice now goes through the
  same checks as a thin image. Sweeping fat files surfaced three false
  rejections in the thin-only rules (tagged `__swift5_types` entries,
  x86_64 ObjC layouts, packed x86_64 chains), each fixed in its own commit,
  and a symlink-sizing bug that refused `/usr/bin/ex` and 46 other system
  binaries. 0 rejections over the 4,933-binary sweep afterwards.

  **arm64e images were walked for the first time on 2026-10-10.** Preflight
  decoded only the 64-bit pointer formats 2 and 6, so the ObjC checks skipped
  every arm64e image (formats 1, 9, 12). With the decoder in place, the first
  metadata fuzz of an arm64e binary (the arm64e slice of Stickies,
  `metadata-fuzz.py ... 60 11`) found 17 crashes, all in `__objc_protolist`,
  which was never checked. The protocol and reference arrays are now checked
  slot by slot, and each protocol the lists name is walked through its
  pointer fields like a class. 17 → 0, with 0 rejections over the 4,933
  binaries.

  Dead ends, recorded so they are not retried. Requiring 8-byte-aligned slots
  (true of all 10.6 million arm64 slots measured) refuses Electron
  Framework, whose x86_64 slices pack pointers at 4-byte offsets. Requiring
  rebase targets inside the image refuses `/usr/libexec/fairplaydeviceidentityd`,
  which dyld loads with 690 rebases pointing outside it (`dyld_info -fixups`).

  Dead end, recorded so it is not retried: `__swift5_typeref` is **not** a
  plain table of mangled names. Current toolchains place 16-byte-aligned binary
  records between the names, and walking the section front to back misread
  them as symbolic references, falsely rejecting 130 of 832 real binaries (in
  both file and VM space). Names are parsed only from the starts the
  field-descriptor, associated-type, builtin and multi-payload-enum records
  point at, by the grammar in `docs/ABI/Mangling.rst`, with references
  resolved in VM space (an indirect one names a GOT slot in `__DATA_CONST`,
  16 MB from its file offset in Xcode's frameworks). Those slots are chained-fixup-encoded, and
  `__objc_const`/`__objc_data` interleave pointers with flags, sizes and
  ivar offsets, so a flat "every word is a pointer" scan would reject valid
  files. Containing them needs a struct-aware walk (`class_t`, `class_ro_t`,
  category, protocol lists) over decoded chained-fixup targets, a larger
  piece than the relative-pointer layouts above. `libSample.dylib`, seed
  1234: 0 crashes in 800.

  **2026-10-10: 0 crashes in 800 runs** at the same settings (`metadata-fuzz.py
  libSample.dylib 100 1234`), after `__swift5_assocty` and `__swift5_mpenum`
  were walked by record layout and relative ObjC method names were checked
  against `__objc_selrefs`. Each rule was swept against real thin binaries
  carrying its section with 0 false rejections (401 / 432 / 571 binaries; the
  method-list walk covered 504,037 relative names).

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

- **FIXED — a stripped copy printed its original's local names.**
  `DeclarationPlacementTests.aStrippedCopyLoadedAfterItsOriginalReadsOnlyItselfIfPresent`
  failed in 1 of 8 full enforcing runs at c340e62: the stripped copy
  rendered `Local #1 in` names that only the original's symbols record.
  MachOSwiftSection keys its per-image caches (the symbol index among them)
  by `imagePath` and `LC_UUID`, and a stripped copy keeps both. Clearing
  them on load (`forgetCachedImage`) did not help when the original was
  analysed after the copy loaded, which the every-fixture sweeps do
  concurrently. Made deterministic as: load the copy, disassemble the
  original, dump the copy. `BinaryLoader.load` now names a thin file by its
  resolved path, so two files never share an entry. Fat slices keep their
  install name, because MachOKit has no public initializer for one. No
  output changed in the four disasm views, `dump`, `objc`, `interface` or
  `layout` on any fixture or swift-syntax dylib. The CLI opens one file per
  process and was never exposed. Library callers and the test suite were.
- **Measured — `--structured` and `--pseudo` on dyld cache images are
  stable across processes.** Release 4d39b01, every 8th entry of the
  cache manifest (249 Swift images), each command run twice in separate
  processes (`Tools/corpus.swift run … --commands structured,pseudo
  --swift-only --repeat 2 --jobs 4`): 498 (image, command) pairs, 996
  runs, 0 differ, 0 failures, 0 control bytes. Rerun at be0a5ee, after
  the argument-layout changes: 498 runs, 0 failures, 0 control bytes,
  total wall 5,727 s → 5,742 s, max peak 1,915 → 1,887 MB (largest rise
  SwiftUICore `--structured`, +123 MB). The other six commands at
  f3af5e8 over the same sample's 413 images (`dump`, `interface`,
  `layout`, `objc`, `version`, `xrefs`): 2,478 runs, 0 failures, 0
  control bytes; `xrefs` reports 2,113,408 functions against 2,113,414
  starts, the six missing in five images being the data-in-`__text`
  starts already open.

- **FIXED (`294dce7`) — the structurer broke a post-dominator tie by
  hash order.**
  - A loop inside a landing pad is never visited by the entry's DFS, so its
    cycle stays in the forward graph and its nodes tie.
  - `max(by:)` over a Set then picked by per-process hash seed. One app's
    `disasm --structured` gave six different outputs in six runs.
  - Ties now go to the lowest block index.
  - `landingpadloop.cpp` gave five outputs in six runs before the fix, one
    after. The cross-process determinism test now includes it.

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

- **FIXED — one C++ function in WebKit took the value tracer past 3 GB.**
  The full structured/pseudo sweep of the 1,913 Swift cache images (3,826
  runs, `Tools/corpus.swift run … --commands structured,pseudo --swift-only
  --jobs 4 --kill-mb 3000`) passed every run but WebKit's two, killed at
  3 GB. `heap` during the spike: 7,580 tracer state dictionaries averaging
  180 KB, all for `WebKit::WebPreferences::features()` (39,628
  instructions, 5,159 blocks). Its frame keeps about 9,800 words live
  across every block, and the fixpoint stores an entry and an exit state
  per block: 50.4M facts. The tracer now counts the facts its block states
  hold and, past `stateFactBudget` (8M, about 520 MB), claims nothing and
  records `values.state-budget`, as at the iteration cap. The largest real
  functions measured on eight large images hold 3.9M (CoreML's
  431k-instruction function), 1.4M (MetalPerformanceShadersGraph), 0.73M
  (GeoServices); Swift-heavy images stay under 0.21M; no fixture passes
  21k. `disasm --image-path …/WebKit -f WebPreferences8featuresEv
  --structured`: 28 s and 3.47 GB to 7.7 s and 594 MB. Whole-image
  `--structured` on WebKit: killed at 3 GB to 182 s and 965 MB, exit 0.
  Fixture `--structured` and `--pseudo` byte-identical. OPEN: states that
  share structure across blocks would let such a function keep its facts.

- **OPEN — Fiery Feeds whole-binary `xrefs` is 1.17× origin/master.**
  Current (streaming, entry below): 179.6 s, 580 MB. Before that: 204.9 s,
  7.04 GB, output byte-identical, after
  three more profiled fixes, each measured alone (release, guarded):
  Objective-C bindings indexed by selector (`50625b3`, 272.6 s to 254.0 s),
  jump-table ranges built once (`bf5782b`, to 235.8 s), and chained-fixup
  rebases from the same table as binds (to 204.9 s; back-to-back with the
  previous binary at 235.1 s). At `5e8cb53` (after the bind table below): 275.3 s,
  peak footprint 11.81 GB, output byte-identical to `74b7b06`'s (`cmp`).
  Origin/master: 153.5 s. The footprint came from the decode: `heap` at
  6.4 GB found 1,114,404 Capstone `cs_detail` blocks (2.8 GB) held by one
  `cs_disasm(…, count: 0)` call, then a `[DecodedInstruction]`, an
  address-keyed dictionary of it, and the `[Instruction]` built from it all
  alive at once, plus the objdump text. Decoding in 4,096-instruction batches
  without Capstone's text, attaching to objdump's stream in place by binary
  search, and freeing objdump's text first: 272.6 s, **7.04 GB**, output
  byte-identical. A footprint sampler polling every second saw only 5.5 GB:
  the decode spike is shorter than that, so a guard must kill well below
  the ceiling. Remaining: the 1.8× time, and the decode still holds the
  image about twice over. Earlier record: At `74b7b06`, release build, `/usr/bin/time -l swiftdc
  xrefs "/Applications/Fiery Feeds.app/Contents/MacOS/Fiery Feeds" --arch arm64
  --unreferenced`: 953 s, max RSS 5.47 GB, **peak footprint 11.05 GB**, 126,173
  output lines, exit 0. origin/master took 153.5 s (below). The symbolizer fix
  (`c00e5a7`) removed about 35 s of it. `sample` at 60 s and 200 s then put
  7,903 of 13,878 analysis samples under `ReferenceResolver.loadedName(at:)`:
  MachOKit's `resolveBind(at:)` walks every chained pointer of the image on
  each lookup. A bind table built once (`BoundSymbolTable`) took a filtered
  `disasm --pseudo -f Article` from 222.2 s / 224.5 s to 57.0 s / 57.2 s
  (alternating runs, footprint +35 MB, output byte-identical), Clarc `disasm
  --pseudo` 35.5 s to 28.6 s, Macs Fan Control and UTM unchanged (few bound
  loads), all six outputs `cmp`-identical. The RSS
  watcher used for this run sampled `ps -o rss` every 5 s, saw at most 4.0 GB,
  and never tripped its 8 GB kill: compressed pages leave RSS but count in the
  footprint. A memory guard on this host must read the footprint
  (`footprint <pid>` or `/usr/bin/time -l`), not RSS.
- **FIXED — whole-image `xrefs` held every instruction of the image.** On
  Swiftcord (49.7 MB of `__text`, about 12.4M instructions) a footprint guard
  killed `xrefs --unreferenced` at 7.5 GB after 69 s, still climbing about
  1 GB every 5 s; `heap` at 3 GB found one 1.1 GB `[Instruction]`, 3.36M
  instruction strings (626 MB) and 553 MB of objdump's split lines. Fiery
  Feeds' 7.2M instructions peaked at 7.15 GB: about 1 KB per instruction held
  at once. `xrefs` now streams the image the way cache-image `disasm` does
  (`disassembleStreaming`) and keeps only each function's call and branch
  sites and its last instruction (`CallGraph.sites(of:)`). Release, guarded,
  `/usr/bin/time -l swiftdc xrefs <app> --arch arm64 --unreferenced`:
  Fiery Feeds 213.3 s / 7.15 GB to **179.6 s / 580 MB**, output
  byte-identical (`cmp`); Swiftcord, never finished before, **227.4 s /
  429 MB**, 106,790 functions. The graph over every fixture matches the
  objdump path's on `--unreferenced` and on `--json --function` for eight
  needles (385 outputs), once two naming corrections are allowed for: imports
  whose C name starts with an underscore keep it (`_Unwind_Resume`,
  `__stack_chk_fail`; the objdump path stripped every leading underscore),
  and notes no longer leak into names (next entry).
  `aStreamedCallGraphMatchesTheWholeImageGraphIfPresent` and
  `aSitesOnlyFunctionKeepsItsSpan` were seen red (sites without branches;
  sites without the last instruction). Earlier record: the ship2 sweep
  stopped it at 8,636 MB RSS after 112.8 s.
- **FIXED — call-graph names carried analysis notes.** A callee's name was
  cut from its annotation at four known note markers, so semantic notes
  survived: `castOptional`'s callee was named `swift_dynamicCastClass  let r0
  = (? as? Reconstruction.Dog)` and `objc_msgSend$twice:  return
  [self->_target twice:arg0]`, in both the objdump and Capstone paths, and a
  `--function` search matched text inside the notes. Every note follows two
  spaces, which no name contains; names are now cut there. No render changed
  on any fixture. `callGraphNamesCarryNoAnalysisNotesIfPresent` was seen red.
- **FIXED — a standalone binary re-opened itself as a dyld cache on every
  `MachOFile.cache` access.** The 0.22 upgrade dropped the fork that memoized
  the failed load, estimating it at about 2.5% of a Keynote `dump`. On a
  Swift-heavy app it dominated: Time Profiler, attached 90 s to `dump --arch
  arm64` on Prime Video (296 MB), put 71.5% of samples under
  `MachOFile.cache.getter` -> `DyldCache.init(url:)` (`__open` 37.5%, `__munmap`
  19.4% self), reached once per relative-pointer resolve in 0.22's class
  dumper. Re-pinned to `CamdenBopp/MachOKit` 4c4738f (0.54.101 plus the
  three-line memo, `3608e37`). Back to back at matched load: `layout` 69.9s to
  4.4s, `dump` 168s to 77s, `interface` 240s to 74s, `objc` 610s to 375s, all
  byte-identical (`cmp`). SwiftPM warns the fork and MachOObjCSection's upstream
  URL share the identity `machokit` and says it will become an error.
- **FIXED (`c00e5a7`) — `xrefs`/`disasm` paid for a full Swift class dump to name vtable
  slots, and 0.22 made that dump walk every class's ObjC ancestors.** The
  symbolizer now reads method descriptors and override tables directly: on Fiery
  Feeds 36.3 s to 1.03 s for the symbolizer alone, 7042 names both ways, none
  lost. The `DyldCache` memo below is likely moot for this path; unmeasured for
  others. Original record:
  `MetadataSymbolizer.classMethodNames(in:)` renders the whole `.types` dump and
  scans it for `sub_` addresses. Under 0.22, `ClassDumper.body` resolves each
  class's ObjC ancestor chain unconditionally (no configuration skips it). Fiery
  Feeds `xrefs --unreferenced`: origin/master 153.5 s, HEAD 966.5 s, same
  output size class. `sample` (20 s, 60 s in): 3,850 of 6,884 command-thread
  samples under `classMethodNames`, 1,429 under
  `ObjCClassMethodIndex.ancestors`, whose hot frames are MachOKit re-deriving
  cache structures per call: `DyldCache._machO(at:)` 685,
  `_headerOptimizationRO64` 619, `_objcOptimization` 261. Two independent
  fixes: name vtable slots from the method descriptors directly (no dump), and
  memoize those `DyldCache` derivations in the MachOKit fork (both the old and
  new ObjC-optimization formats).
- **FIXED — a filtered query demangled the whole symbol table one symbol
  at a time.** `disasm -f ChatView.body --structured` on Enchanted's
  release build (3.66M instructions) took 47.7 s / 48.1 s, 57% of it in
  `matchedRanges` demangling every label and folded symbol (audit E-5).
  The demangle cache is now filled across the cores first; demangling is
  pure and the cache is behind a `Mutex`. 12.45 s / 11.88 s, output
  identical on that query and on 268 filtered fixture renders.
  Reproduce: `/usr/bin/time -l swiftdc disasm <app> -f ChatView.body
  --structured`.
- **DEAD END — prefetching async funclet bodies in parallel for a filtered
  query.** The funclet index's sequential decode looked like the next
  38%. Decoding the hinted funclets across the cores first measured 11.42
  to 11.95 s against 11.82 to 11.90 s (three alternating runs each) for
  65 MB more peak footprint. Reverted; do not retry without parallelising
  the scan itself.
- **DEAD END — capturing `MachOFile.fullCache` once in the resolver.**
  MachOKit memoises `fullCache` only on success, so a standalone binary
  re-attempts opening a cache on every read, and `sample` at 50 s on Fiery
  Feeds `xrefs` put 224 of 5,855 analysis samples under it (through
  `pointerTarget(at:)`). Reading it once per resolver measured nothing,
  alternating runs at `39eb91b`: baseline 204.6 s and 203.1 s, candidate
  203.8 s and 203.6 s, output identical. The sample's share was one thread's
  view of a short early phase. Reverted; do not retry for speed.
- **DEAD END — reserving the decode array once at the text bound.** A memory
  sample at 7 GB in Swiftcord `xrefs` put every frame in `decodeText` ->
  `CapstoneEngine.append` -> `_ArrayBuffer._consumeAndCreateNew`, and
  `append` reserves `results.count + batch` per Capstone batch. Hypothesis: the
  exact-size reserve defeats geometric growth. Replacing it with one
  `reserveCapacity(code.count / 4)` was worse at matched settings, alternating
  runs, `disasm --structured --arch arm64` UTM: baseline 47.7 s / 1.9 GB and
  45.8 s / 2.7 GB, candidate 53.2 s / 2.9 GB and 48.7 s / 3.0 GB, output
  byte-identical. The up-front bound allocates for every word, data included.
  Reverted; do not retry. The Swiftcord peak itself (7.8 GB, sawtooth between
  ~2 and ~7.6 GB) matches origin/master's 7.85 GB.
- **OPEN — whole-image `xrefs`/`disasm`/`analyze` exceed 30 minutes on a 296 MB
  app.** Prime Video, release build: `xrefs --unreferenced` and `disasm
  --structured` both hit the sweep's 30-minute cap (5.7 GB and 6.8 GB peak).
  origin/master never finished either (it trapped at 488 s and 569 s, see
  Robustness), so there is no baseline. `sample` early in `xrefs`: whole-image
  Capstone decoding (`CapstoneEngine.append`, Capstone 6's `matchAliasPatterns`)
  plus malloc/free. Whether Capstone 6 decodes slower than the Homebrew
  Capstone 5 it replaced is **UNKNOWN**: the migration measured byte-identical
  output, not speed.
- **OPEN — the MachOSwiftSection 0.22.0 pin makes `dump`/`interface`/`objc`
  on standalone ObjC-heavy apps 7x to 40x slower, upstream.** Measured with
  the same binary set before and after the pin (times under build load, so
  indicative; the `sample` attributions are not): Keynote `dump` 1.35s to
  20.2s, `interface` 1.36s to 24.4s, `objc` 60s to 2,424s; GoodLinks `dump`
  7.4s to 54.5s, `objc` 10.4s to 106s; peak RSS roughly doubled. Two causes,
  both in the dependencies: (a) 0.22's class dumper resolves each class's ObjC
  ancestor chain inside the system dyld cache, and MachOKit's
  `DyldCache.locateValue` re-reads `headerOptimizationRO64` / `mappingInfos`
  on every call (3,235 of 5,225 samples under
  `ObjCClassMethodIndex.ancestors` on Keynote `dump`); (b) MachOObjCSection
  0.8.110's `info(in:)` resolves referenced protocol infos recursively, each
  method slot through a fixup lookup (2,448 of 5,560 samples under
  `referencedProtocolInfos` on Keynote `objc`). The dropped MachOKit fork
  memoisation was estimated here at about 2.5% of a `dump`; on Prime Video it
  was 71.5%, and it is restored (see the FIXED entry above). Cache images are faster
  (SwiftUICore `dump` 228s to 160s, `interface` 260s to 163s, `objc` 70s to
  35s, same load caveat). Candidate fixes: memoise the `DyldCache` header
  parsing in MachOKit; pass `ObjCInfoOptions.headerDump` from swiftdc's own
  `objc` path if its output stays byte-identical. Profiles:
  `sample <pid> 8` on `dump --arch arm64 Keynote` and `objc --arch arm64 Keynote`.
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
  no longer all resident). `xrefs` now streams too (keeping call sites only),
  and so do `disasm --structured`/`--pseudo` on a standalone file: Enchanted
  -Onone (7.02M instructions), killed at a 4 GB guard after 45 s before, now
  renders in 284 s at 416 MB, and its -O build in 157 s at 369 MB. The plain
  listing and `--cfg` (objdump's instruction text), `--json` and `analyze`
  still materialise every function; a streaming JSON writer, or chunking the
  array modes, is the remaining scale work.
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
  serialization boxing in that historical implementation, rather than held
  function objects. Current source constructs Codable DTO arrays and uses
  `JSONEncoder` Data followed by a String; the old measurement does not
  establish the current allocation cause. In the historical run, a
  "well under 1,192" bound (e.g. 500 MB) would sail past the actual failure mode,
  which tops out at 261 MB. 200 MB splits the two — ~1.6× over the 123 MB baseline,
  under the 261 MB a hold-every-function regression reaches. Proven both
  directions: the injection trips it (262 MB), the clean path clears it (123 MB).
  Host-gated on CoreLocation; ~60 s, skips cleanly without the cache.
- **UNKNOWN — no wall-time regression guard.** The memory guard above covers
  allocation; nothing guards decode *time*, which is deliberately left to a
  measured OPEN rather than a test — wall time is too machine- and load-dependent
  to assert as a stable bound without flaking.

- **FIXED — `analyze` reported a failed disassembly as an empty one.**
  `try?` turned an llvm-objdump failure into `(no functions recovered)` with
  exit 0, while `disasm` on the same file exited 1 (audit E-3). The report
  keeps its declarations, states `disassembly failed: …` (JSON
  `disassemblyError`), and the command exits 1 with the error on stderr.

- **FIXED — `layout` printed an understated instance size as fact.** A
  layout that stops at a field it cannot resolve has a size covering only
  the trusted prefix: `instance size 0 bytes` for a class with an
  unresolved ObjC ancestor, 97 for an app's 152-byte struct (audit A6, E-1:
  28 to 652 such types per binary). Such a type now reads `instance size
  unknown (at least N bytes)`, and JSON `instanceSize` is null.

- **FIXED — `xrefs` counted named GOT calls as unresolved.** A `blr`
  through a bound GOT slot has a proven import name but no address in the
  image. It is now an external call (`CallGraph.externalCallSites`), not an
  unresolved one. On OpenMHz -Onone, 1,841 of 5,864 `blr` remain
  unresolved, matching the 4,023 GOT-bound sites the audit counted
  independently (E-2). `--unreferenced` now prints the unresolved count
  next to its dead-code caveat.

## 6. Usability — are commands, diagnostics, and docs accurate?

- **FIXED — `-f` could not select a function by address.** `disasm -f
  0x1a5ce3f10` on WebKit printed `No function matched`; the function had
  a symbol, so `sub_1a5ce3f10` did not match either. `-f 0x<hex>` now
  selects the function whose span holds the address, at its start or
  inside it, on files and cache images.

- **FIXED — three README defects.** A documented command that errors
  (`--sections types,protocols` is space-separated); an entire undocumented
  subcommand (`layout`, including the `--self-index` flag that produces numbers
  the README cited); a stale measurement (49/33 → re-measured 60/39). `f549857`.
- **FIXED — the ambiguous empty-result message.** `// No functions matched.`
  covered three distinct causes including a parser failure. Now distinguishes
  "no function matched `<filter>`" from "this binary contains no recoverable
  functions", and an analysis failure throws instead.
- **FIXED — an empty `--function ""` meant opposite things.** `disasm` and
  `objc` matched every function; `xrefs` matched none and printed `// No
  function matched ''.` with exit 0. Every command that takes `--function`
  now rejects an empty name as a usage error. Test:
  `everyFunctionFilterRejectsAnEmptyNameIfPresent`, which finds the commands
  from their help text.
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
- **OPEN — closures, existentials, generic witnesses, `throws`** render as
  low-level runtime calls rather than reconstructed control flow. Honest
  declines; large surface. A generic or existential *result* in particular
  still declines its `return`: the x8 pointer escapes into the value-witness
  call, or the type has no stored-property layout to cover (`identity<A>`,
  `asAny` in the indirect fixture).
- **MITIGATED — `async` functions.** Each funclet of an async function is
  grouped under its entry (see Completeness), and on the `-O` build the body
  reads as source: `let awaited1 = await AsyncFns.fetchValue(arg0)` in the
  entry, `return (awaited1 + awaited2)` in the last funclet, an executor hop
  as `await hop_to_executor(generic)`, and a parameter reloaded from the async
  context as `arg0` (`04682ec`). Every claim carries a proof: the return is a
  `br` through the context's ResumeParent that the tracer followed from the
  seeded x22; the awaited result is seeded only when the callee's signature
  proves a single-register result; a context slot is named only when exactly
  one store in the whole chain reaches it and the value is portable. What is
  still declined, by design: `-Onone` funclets reload the context through
  stack spills the chain pass does not follow, so their returns print no
  value (pinned by `declinesUnprovenAsyncReturnsAtOnoneIfPresent`); the error
  register at an await-return funclet is left as a raw register (`x20 == 0`);
  an executor obtained from an actor's `unownedExecutor` renders
  `hop_to_executor(?)`; and a value spilled twice to the same slot is never
  named. Repro: `swiftdc disasm --structured -f twoAwaits
  Fixtures/Sample/libAsyncFns.opt.stripped.dylib`.
- **OPEN — a result that crosses only its own ARC hand-off is bound.**
  `return [arg0 stringByAppendingString:self->_name]` at -O2 renders `let r0
  = …; return r0`, because `objc_claimAutoreleasedReturnValue(r0)` sits
  between the send and the tail return and counts as an ordering effect.
  Sound (one evaluation either way) but verbose, and common in ObjC.
  Exempting a passthrough helper whose argument is the producer's own
  result from `crossesEffect` would inline it again; it would also inline
  non-return uses (`-[W q1]`, `peerCopy`), so it is its own change.
- **PLATEAU — condition naming.** ~70% of raw-register conditions are compiler
  plumbing (value witnesses, generic specializations, Codable machinery) with no
  source-level named value to recover. Investigated and documented as
  coverage-bound in `docs/research/field-map-name-collision.md`. Not a tractable
  slice; do not re-mine it without new evidence.

## 8. Validation — what independent oracle checks each subsystem?

The meta-category. Every gap here weakens confidence in every claim above.

| Subsystem | Oracle | Status |
|---|---|---|
| Analysis decisions | `--probe` claims (`types.field-named`, `values.unmodelled-write`) checked by validators or DWARF | **New (`7d3fd29`)**: the tracer's write check is silent on every fixture and three apps, and is seen red under a clobber mutation. Field-name claims are ready for a DWARF validator |
| Source semantics | The app-audit harness (`Tools/audit`): the source at a recorded revision, objdump, DWARF, SIL, runtime | **Run once, 2026-10-12**: about 20 confirmed semantic errors, each reduced |
| Function boundaries | `LC_FUNCTION_STARTS` | **Enforced** — throws on empty parse, warns below 50% recovery. The count is deduped and cross-checked against `dyld_info` in tests |
| Byte-level decode coverage | `dyld_info -function_starts` extents | **In tests + measured by hand** — 100.000% of declared slots decode; no holes inside bodies on either decoder |
| Peak memory | `/usr/bin/time -l` peak footprint | **Measured + guarded** — linear ~2.5 KB/instruction; SwiftUI 13.5 GB exceeds a 16 GB host; `MemoryRegressionTests` bounds per-instruction footprint |
| Instruction decode | `llvm-objdump` vs in-process Capstone | Two independent decoders exist; **checked once by hand, 2026-10-24**: every address both decode, on the five audit apps (4.67M instructions), mnemonic by mnemonic. The only disagreements were 17 GoodLinks instructions objdump could not decode without `--mattr=+all` (below). Both silent-truncation bugs found so far were in whichever decoder the other wasn't covering |
| Enum tag → case index | SIL (`swiftc -emit-sil`) | Used once, manually, to confirm the `rank` lowering |
| Field offsets | `__swift5_fieldmd`, computed offline | Runtime-exact by construction |
| Cross-image symbols | export trie | Used as the primary source |
| Stripped-binary names from metadata | the unstripped twin's symbol at the same address, demangled by `xcrun swift-demangle` | **In tests** — `MetadataNameOracleTests`, four stripped fixtures, overrides, same-simple-name classes, and folds required |
| Recovered semantics | the compiled function itself, called via `dlsym` | **In tests** — 1,264 comparisons at both `-Onone` and `-O`: 636 integer/boolean (catches an injected U1) and 628 floating point (catches a one-ULP constant error). Narrow: no strings, payload enums, or side effects |
| Async funclet grouping | the unstripped symbol table (`…TQ<n>_` / `…TY<n>_` suffixes) | **In tests** — parent, ordinal and kind of all 14 funclets on three builds, and the stripped build must match address for address; the code-only fallback is checked against the same oracle |
| Malformed-input handling | the CLI's own exit status, checked from a subprocess | **In tests** — 9 header-shaped inputs; no fuzzer, no malformed metadata |
| Whole-binary output | `Tools/corpus.swift` over every arm64 image on the host: exit status and signal, cross-process output hashes, `dyld_info -function_starts`, the image's own sections, `proc_pid_rusage` | **Measured (2026-10-31)**: 6,127 images; `corpus compare` diffs two builds' outputs, outcomes, time and memory. Hashes are not committed (the images are private and host-specific), so a regression shows only when a sweep is re-run |

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

## 2026-10-12: native research-loop follow-up

- **FIXED (`7c6a070`) — symbolic W-register accesses lost their width.**
  The previous 1,174 width probes held constants. A fresh symbolic-input
  fixture, `UInt64(UInt32(truncatingIfNeeded: x))`, returned `arg0` instead of
  its low word. Native execution refuted 20 of 39 samples at each optimization
  level. W reads now narrow before use, W writes narrow arithmetic results,
  signed word operations extend their word sign, and register shift counts
  use the architectural low five/six bits. Word normalization is idempotent;
  proven boolean values retain their existing rendering. The existing 217,728
  CCMP and 1,174 width-flag comparisons remain regression gates.
- **FIXED (`7c6a070`) — tracked stack loads ignored width and signedness.**
  Enlarging the research corpus exposed 49 wrong -Onone samples across byte
  truncation and sign extension. Stack stores record initialized widths;
  wider loads decline, signed loads extend the access-width sign, and partial
  overwrites invalidate intersecting snapshots. Memory copies consult the
  initialized width too. Symbolic tests cover byte/word loads and an overlapping
  byte write, with a neighboring non-overlapping control.
- **FIXED — display presets changed semantic recovery.** The imported-object
  fixture formerly emitted `note(?)` in interface mode and `note()` in
  simplified mode. Canonical semantic identities now recover the argument
  under every preset; the integer corpus has matching coverage across presets.
  See the presentation-independent recovery follow-up below.
- **FIXED (`3f929e7`) — unsupported pure returns disappear from the flat fallback.**
  Optimized `signExtendWord`, `signExtendByte` and `wordSelect` have known
  UInt64 signatures but unsupported instruction semantics. Their unknown
  register facts were observed, while the early enrichment guard skipped return
  outcomes and the single-block pseudo fallback emitted a leaf comment. Known
  value-return contracts now retain `return ?` and an unknown return outcome,
  without creating a value claim. Void, Never, unknown signatures and async
  entry RETs do not acquire a value return. Re-running
  `swiftdc research --iterations 2 --seed 7` produced 36 configurations with
  zero refutations or missing observations: each optimized configuration had
  468 verified and 156 not-evaluated cases; each -Onone configuration had
  546 verified and 78 not-evaluated cases. Recovery coverage did not increase.
- **IMPLEMENTED — repeatable research evidence in Swift.**
  `swiftdc research --iterations 2 --seed 7` adds fixed edges and repeatable
  random samples across the authored scalar functions, three optimization
  levels, three display presets and two analysis entry points. Each batch uses
  distinct modules and validates native symbol ownership. Evidence is retained
  under a fresh run directory, and refutations make the command fail. Scoring
  coverage is explicit; unknown/missing recovery remains a discovery, never an
  accuracy claim. See [INSTRUMENTATION.md](INSTRUMENTATION.md).

## 2026-10-12: presentation-independent semantic recovery

- **FIXED (working tree) — display presets changed argument and return facts.**
  Canonical signature and nominal-kind evidence now come from the same parsed
  mangled tree independently of presentation options. Function copies retain
  `semanticName`; callee analysis retains canonical annotations and renderers
  use a separate display spelling. Type recovery and structuring read the
  semantic name. Requested headings/call spellings and displayed-name filters
  remain available.
  The imported object and optional-object fixtures recover their integer call
  argument under all three presets. The native research matrix has identical
  outcomes and coverage across presets, with no refutations. Earlier simplified
  runs evaluated no cases. All 144 default-preset fixture outputs are unchanged.
  `PresetSemanticTests` covers imported calls, sampled native outcomes, display
  spellings, filters and identity preservation. Canonical-print and semantic-name
  fallback mutations independently remove the covered recovery.

## 2026-10-12: scalar extension aliases

- **FIXED (`985880b`) — optimized integer sign extensions were unknown.**
  `ResearchOptimized.signExtendWord` is `sxtw x0, w0; ret`, and
  `signExtendByte` uses `sxtb x0, w0`. The tracer had operand-extension support
  but declined these standalone scalar instructions. It now handles SXTB,
  SXTH, SXTW, UXTB and UXTH using the low source byte/halfword/word; a W
  destination still zero-extends its final 32-bit result. This follows the
  [Arm instruction reference](https://documentation-service.arm.com/static/6245c734b059dc5ff9a8bdab),
  including the distinct W and X destination semantics.
- **VALIDATED — native extensions at every optimization level.** An authored
  halfword function and explicit byte/halfword/word sign-boundary inputs extend
  the Swift research corpus to 17 functions and 47 inputs. Running
  `swiftdc research --iterations 2 --seed 7` produced 36 configurations, each
  with 705 verified, 94 not-evaluated, zero refuted and zero missing cases.
  All byte/halfword/word sign-extension samples are required to verify at
  -Onone, -O and -Osize. The bounded loop and word selection remain unknown.
  Signed and unsigned transfer mutations independently fail the scalar
  regression; disabling signed extensions also loses native recovery coverage.
- **FIXED (working tree) — text rendering did not distinguish arithmetic and
  logical shifts.** `AbstractBinaryOperator.symbol` formerly used `>>` for
  both, although the exported probe AST preserved the distinction. Text now
  uses `>>ˢ` (sign-filling) and `>>ᵁ` (zero-filling), preserving the register
  operation independently of source types. A strict Swift test parses the
  actual pseudo and structured return text for six required research functions
  across three optimization levels and all display presets, then compares 47
  samples per function with independent native expectations: 5,076 comparisons.
  Unsupported grammar fails; it cannot silently remove a covered function.
  The pre-fix output failed with 270 issues, including native mismatches in
  logical shifts with high-bit inputs. The test parser now reads full-width
  hex bit patterns before decimal exponents, so hexadecimal `e` does not make
  an integer a floating-point value. These operators denote pseudocode, not
  compilable Swift syntax.

## 2026-10-12: scalar complemented operands

- **FIXED (working tree) — MVN kept conditional word selection unknown.**
  Optimized `wordSelect` contains `mvn w8, w0; add w9, w0, #1; tst x0, #1;
  csel x8, x8, x9, eq; mov w0, w8; ret`. The tracer already handled CSEL
  and word normalization, but declined the complement. Scalar MVN and ORN now
  complement the optionally shifted right operand before combining it with
  the left operand, then apply the destination width. Constants fold exactly;
  repeated complements cancel; unknown or excessively deep operands decline.
  General-register guards leave vector forms and unsupported shifts unclaimed.
  This follows [Arm's ORN specification](https://www.scs.stanford.edu/~zyedidia/arm64/orn_log_shift.html):
  lifting the actual register operation also applies to common compiler output
  outside Swift; ABI and Mach-O recovery remain separate concerns.
- **VALIDATED — native expressions, text and independent mutations.**
  The research corpus now contains 21 functions and 47 inputs, adding word
  complement, shifted complement, OR-with-complement and a byte-swap decline
  control. `swiftdc research --iterations 2 --seed 7` produced 36 configurations,
  each with 893 verified, 94 not-evaluated, zero refuted and zero missing cases.
  The bounded loop and byte swapping remain unknown. Four complement/selection
  functions add 3,384 strict text/native comparisons across all optimization
  levels, display presets and both text renderers. Disabling MVN or ORN
  independently failed the regression gates with six/four issues. All 555
  tests pass after restoring and rebuilding.
- **MEASURED — six of 144 fixture outputs changed.** The optimized/size research
  modules recover wordNot, orNot and wordSelect. WidthFlags.flagProbe1055
  recovers the constant `0x7ffffffe`; an independently resolved, image-owned
  native call returns exactly that value. No other fixture output changed.

## 2026-10-13: recovered loop-carried state

- **FIXED (working tree) — named loop variables had no entry bindings.**
  ResearchOnone.boundedLoop printed `while (i <ᵁ (arg0 & 15)) { sum += i;
  i += 1 }` without initializing either variable. The induction analysis
  already required constant entry values but discarded them. Typed
  `FunctionAnalysis.loopInitializations` now retains those bit patterns and
  entry-frame stack offsets; the structured renderer declares them before
  entering the corresponding loop. Nested declarations remain inside the
  outer loop. Sequential accumulators use distinct names. Unknown starting
  values do not acquire guessed initializers.
  Across 146 outputs from 73 fixture dylibs, four structured outputs changed:
  LoopEntry's bindings, names and back-edge step; zero bindings for accumulate
  and countTo in both Reconstruction variants; and boundedLoop's zero bindings
  in ResearchOnone. Flat output and every other fixture output are unchanged.
- **FIXED (working tree) — unrotated loops omitted their proven step.**
  The authored LoopEntry.multipleExits fixture exposed `var i = 3;
  while (true) { ... continue }` with no increment. Updates were appended only
  to rotated while bodies. They now precede the proven loop-back transfer,
  including explicit continues, and do not execute on exit paths. Proven
  primary-counter facts flow to body snapshots so its `i != 7` test refers to
  the same initialized counter instead of an unexplained x8. Other temporary
  placeholders remain unknown. Six independent mutation gates cover entry
  facts, declarations, unique naming, probe export, back-edge steps and body
  identity propagation.
  The restored full suite passes 561 tests in 11 suites. Independent mutations
  fail with 17/11/2/3/2/2 issues. The native Swift research matrix remains
  893 verified and 94 not-evaluated cases per configuration, with zero refuted
  or missing observations across 36 configurations; return coverage did not
  increase.
- **IMPLEMENTED — independent loop-entry validation surfaces.**
  `values.loop-initialization` exports the synthetic name, exact UInt64 entry
  value and stack offset at the header branch. It comes from a completed
  analysis snapshot, preserving observational-only probes. Five authored
  -Onone functions cover nonzero starts, sequential and nested loops, an
  unknown entry and multiple exits. Source return recovery remains separate;
  these functions still decline unrecovered results.
- **SUPERSEDED — widened multiply/extract now transfer; loop verification stays open.**
  At -O/-Osize the loop becomes arithmetic including SMULL and EXTR. The
  current tracer declines its nonzero result. Its -Onone body is structured,
  but exit accumulator recovery and a complete executable-body oracle remain
  unimplemented. Initializer and transition evidence do not verify a complete
  recovered function.

## 2026-10-13: tuple call result words

- **FIXED (`d1314e3`) — a scalar word rendered as an entire tuple call.**
  New native high-product functions call multipliedFullWidth at -Onone, whose
  signature returns `(high: UInt64, low: UInt64)` or `(high: Int64, low: UInt64)`.
  The caller reads only the high word from x0, but output returned the whole
  call expression as UInt64. A known logical tuple now leaves scalar result
  registers unknown until its projection/layout is proven. Calls remain
  visible and the scalar return explicitly declines. Tuple parameters,
  closure results and grouped tuple/getter signatures are classified separately.
- **VALIDATED — new independent native high-product inputs.** The Swift research
  corpus now has 23 scalar functions and 47 inputs, including signed products
  by a negative multiplier and unsigned squares. Each configuration supplies
  1,081 expectations. The tuple-call regression was red with 24 issues;
  disabling the decline reproduces those failures. At -Onone the two added
  cases remain not-evaluated. At -O/-Osize native AST evaluation verifies their
  direct SMULH/UMULH results. Full tuple projection recovery and distinct
  high-multiply text notation remain separate follow-ups.

## 2026-10-13: high-product signedness in text

- **FIXED (working tree) — signed and unsigned high products shared mulh.**
  The typed AST already distinguished the operations, but output concealed
  the interpretation of its operands. Text now uses mulhˢ for the signed
  128-bit product's high half and mulhᵁ for the unsigned high half. This
  matches [Arm's A64 multiplication overview](https://developer.arm.com/-/media/Files/pdf/graphics-and-multimedia/ARMv8_InstructionSetOverview.pdf),
  independently of a caller's UInt64 result type.
- **VALIDATED — strict text/native comparison of both variants.** Signed
  products by a negative multiplier and unsigned squares are required to
  verify at -O and -Osize, through both renderers and all three presets:
  1,128 comparisons over 47 inputs. Swapping signed/unsigned markers
  independently fails with 564/108 issues, including native disagreements.
  Onone's tuple-call word projection remains a separately tested decline;
  its unknown cases are not omitted from the research denominator.

## 2026-10-13: widened word multiplication

- **IMPLEMENTED (`5d7e6fe`) — scalar long multiplication.** SMULL/UMULL,
  SMADDL/UMADDL, SMSUBL/UMSUBL and their negate aliases now widen both 32-bit
  operands using the instruction's signedness before multiplication, with
  64-bit addends and result arithmetic. Scalar register/width guards exclude
  vector forms. Operand metadata cannot apply the alias's widening twice.
  This follows [Arm's long-multiplication overview](https://developer.arm.com/-/media/Files/pdf/graphics-and-multimedia/ARMv8_InstructionSetOverview.pdf).
- **VALIDATED — symbolic, native and actual text.** Four authored native
  functions split the input into high/low words, including opposite sign
  boundaries, and exercise plain and fused signed/unsigned products. Eight
  forms have 356 symbolic operand comparisons; the text/native oracle adds
  3,672 comparisons over 51 inputs, all optimization levels, presets and
  renderers. Independently removing signed extension, unsigned narrowing or
  the 64-bit addend failed with 480/588/582 issues. Unsupported inputs decline.
- **SUPERSEDED — EXTR support ships below; loop verification stays open.**
  Its SMULL transferred correctly at this checkpoint, but the following extract
  remained unknown, so its return declined. Do not count the instruction addition as complete loop recovery.
- **MEASURED — 36 native configurations, zero refutations.** Onone verifies
  1,122 of 1,377 cases with 255 not-evaluated; O/Osize verifies 1,275 with 102
  not-evaluated. All four new widened-product functions verify, and missing
  observations remain zero. All 568 tests pass. Six of 146 fixture outputs
  changed, only the three research modules' pseudo/structured views: their
  previously unknown long-product return expressions now recover. Other
  fixture output is unchanged.
- **SUPERSEDED (`44fcbeb`) — freshly compiled Onone signedRange declined.** Both the frozen
  baseline and new binary emit return ? for ResearchOnone_R0.signedRange.
  This adds 51 unknown cases to the matrix; do not hide it by dropping that
  function or counting it as verified.

## 2026-10-13: symbolic addition flags

- **FIXED (`5b44c97`) — ADDS/CMN conditions ignored addition overflow.**
  Onone signedRange exposed `adds x8,x0,#11; b.lt` rendered as
  `(arg0 + 11) < 0`. A wrapped sum's sign is not N xor V, so this condition
  is false evidence at signed-overflow boundaries. Addition producers now
  preserve their operands and width, even for add-zero. Consumers reconstruct
  N/Z/C/V and all 14 conditions at 32/64 bits. Constant signed thresholds
  simplify exactly, with a separate signed-minimum case instead of overflowing
  a negation. Unknown/depth-limited predicates still decline.
- **VALIDATED — native flags and rendered bounds.** The authored addflags.s
  exports 104 probes for ADDS/CMN, both widths, every condition and zero/11/minimum
  constants. Eleven edge values give 12,584 native input-pair comparisons.
  The signedLowerBound Swift fixture adds 918 actual text/native comparisons
  over all compiler levels, presets and renderers. Independent consumer,
  ADDS-producer, CMN-producer and minimum-threshold mutations failed with
  191/220/220/968 issues. The new native probe test was red before the fix.
- **SUPERSEDED (`44fcbeb`) — chained diamonds used stale outgoing states.**
  signedRange's first boolean merge is reconstructed in its entry state, but
  the second diamond reads the original unknown outgoing state. Correcting
  addition conditions prevents false predicates; propagating proven merged
  facts remains a separate completeness task.
- **MEASURED — 570 tests pass; 36 native configurations have zero refutations.**
  Onone verifies 1,173 of 1,428 cases with 255 not-evaluated; O/Osize verifies
  1,326 with 102 not-evaluated. Missing observations remain zero. In 148
  fixture outputs, 21 change: overflow-aware signed thresholds, canonical
  argument spellings for CMN equality, and original-site bindings for call
  results referenced by exact flag expressions. Call count/order is preserved.
  Compares.doubled falls back to its equivalent raw x0 sign test, retaining
  the original CMN operand rather than presenting an unsupported baked form.

## 2026-10-13: consumed calls respect runtime argument arity

- **FIXED — unused argument registers hid their producer calls.** Consumed
  call results now use the same fixed ABI argument normalization as rendering.
  A zero-argument `__stack_chk_fail` must not consume a stale x0; nor may typed
  throwing helpers consume availability-check results in unused registers.
  This restores availability checks in Reconstruction typedScale/typedPick
  (-O/-Osize) and TypedThrowsAwait.codeAsync's second resume function.
  A dependent-select experiment also exposed a dropped `swift_errorRelease`
  in SwiftErrorProbe.listingCount; the regression covers both symbol modes
  and both renderers ahead of shipping that propagation.
- **VALIDATED — 572 tests pass in the enforcing suite.** Comparing 150
  structured/pseudo fixture outputs changes three pseudo outputs: the two
  Reconstruction optimization levels and TypedThrowsAwait gain their original
  availability-check calls, in instruction order. Structured output is stable.
  Removing normalization fails the independent availability-check regression
  with two issues, and the select-propagation release regression with six.

## 2026-10-13: dependent select propagation

- **FIXED — later diamonds read stale outgoing states.**
  ResearchOnone.signedRange's first boolean merge was known at entry but
  never re-transferred before the next decider read it. A forward pass now
  visits acyclic dependencies in topological graph order, rebuilds merge
  entry facts from updated predecessors, and re-transfers only changed states.
  Both diamond and equality-switch merges use refreshed outgoing facts.
  Cycles and their dependents retain the original converged analysis;
  this pass does not pretend to solve a new loop fixpoint. Repeated work is
  probe-muted.
- **VALIDATED — native and layout-independent regressions.** signedRange is
  required to verify at all optimization levels in native AST scoring. Its
  recovered Onone text adds 306 native comparisons through all presets and
  both renderers. The text interpreter uses signed bare comparisons, so the
  optimized UInt64 offset expression remains covered by its typed AST gate.
  Two assembly fixtures cover separated dependent diamonds and a return
  placed earlier in address order; a cyclic control must remain unknown.
  Removing outgoing refresh, incoming propagation or graph ordering fails
  independently with 3/1/1 issues. The original corpus gate was red before
  propagation. Complete executable-body scoring remains a separate goal.
- **PREREQUISITE — d9ad06e preserves unused-argument producer calls.**
  The fixture comparison exposed `swift_errorRelease` disappearing from
  SwiftErrorProbe.listingCount when its stale result reached `__stack_chk_fail`.
  The latter has zero arguments: consuming calls now uses the same fixed ABI
  argument normalization as rendering. Both stripped and unstripped outputs
  retain the release in both renderers. Removing this normalization fails the
  regression with six issues.
- **MEASURED — native coverage increases without refutations.** The two-batch,
  36-configuration Swift research run (`research --iterations 2 --seed 7`)
  verifies 1,224 of 1,428 Onone cases (previously 1,173), with 204 unknowns;
  O/Osize stays at 1,326 verified and 102 unknowns. All configurations have
  zero refutations and missing observations. This measures the authored corpus,
  not general decompilation accuracy.
- **BLAST RADIUS — 12 of 150 fixture outputs change after d9ad06e.**
  ResearchOnone recovers the signed range; Indirect, Reconstruction and both
  EnumIdentity modules recover enum equality returns from their ordinal
  selections. Cow binds the earlier conditional buffer call at its original
  site and carries its partial select into the later buffer call's argument.
  Calls and stores retain their order. SwiftErrorProbe output stays unchanged
  with the prerequisite consumption fix applied.
  Rebuilt final enforcing suite: 574 tests in 11 suites pass, including
  cross-process determinism, probe output independence and streaming memory.

## 2026-10-13: scalar extract and immediate rotation

- **IMPLEMENTED — EXTR and immediate ROR preserve their bit window.**
  Scalar 32/64-bit EXTR now takes low bits from the second source and high
  bits from the first, using logical shifts and a width-normalized write.
  Immediate ROR supplies the same register for both halves. Capstone attaches
  that alias's immediate to the source's shift metadata; it is applied once.
  A zero shift reads only the low register, even if the high register is
  unknown. Register ROR and incompatible register/operand layouts decline.
  This follows [Arm's assembler reference, EXTR and ROR immediate](https://documentation-service.arm.com/static/5f3fa899428f7a6b3328fd44).
- **VALIDATED — 3,402 native assembly comparisons.** The authored fixture
  covers 42 extract/rotate forms across both widths, zero and maximum shifts,
  word-boundary shifts, asymmetric halves and high-bit inputs. Additional
  tests require constant folding, unknown-high zero extraction and declining
  register rotation. Native and actual rendered text also cover rotateBits
  and rotateWord at Onone/O/Osize: 1,836 text comparisons over all presets
  and both renderers. Removing the low-half selection, alias handling, zero
  special case or unsigned shift fails independently with 1,254/1/2/471 issues.
  The native assembly test was red before implementation.
- **MEASURED — the Swift corpus grows to 30 functions, with zero refutations.**
  `research --iterations 2 --seed 7` verifies 1,326 of 1,530 Onone cases
  (204 unknowns), and 1,428 at O/Osize (102 unknowns), in all 36 configurations.
  Missing observations remain zero. The two rotate functions are required
  verified cases, adding 102 per configuration. This measures the authored
  corpus; no performance improvement or general accuracy percentage is claimed.
- **OPEN — boundedLoop remains unverified after extract support.** Its
  optimized arithmetic can now transfer through EXTR, but multiple returns
  and partially rendered complex expressions still prevent full verification.
  The research loop retains those cases as unknown. Onone's actual loop and
  byteSwap remain separate gaps. Do not claim this change completes loops.
- **BLAST RADIUS — four of 152 outputs change.** Only the optimized and
  size-optimized research modules' pseudo/structured views change: both rotates
  recover and boundedLoop gains a partial expression with explicit unknown
  leaves at the existing text-depth limit. Its zero return and branch structure
  stay intact. Native scoring reports multiple exits and keeps it unknown.
  Onone rotates already lowered to supported shifts and are unchanged.
  All other fixture output is unchanged; the rebuilt enforcing suite passes
  578 tests in 11 suites, including determinism and streaming memory.

## 2026-10-13: partial source-return claims

- **FIXED — depth-limited text was scored as a complete recovered return.**
  ResearchOptimized.boundedLoop's nonzero exit has an evaluable internal AST,
  but the existing render depth cap replaces nested operands with `?`.
  With an explicit exit oracle, recovered-return scoring previously verified
  that partial source expression. The independently executed input 7 produces
  21; the new regression was red with three issues before the fix.
- **IMPLEMENTED — the return-outcome API distinguishes `partial`.** Actual
  placeholder emissions during each return's rendering mark it partial;
  the default scorer treats it as not-evaluated and no complete return-value
  claim is emitted. This tracks renderer decisions, without scanning text
  where question marks may be ternary operators or literal content. Other
  returns in the same function retain their own completeness. Raw-register
  mode still verifies the exact internal value, without claiming source text.
  Tracking stores no return entries when probes are disabled, and no rendered
  source text or recovered dataflow fact depends on the tracking state.
- **VALIDATED — independent tracking, classification and scope mutations.**
  Removing placeholder tracking or partial classification fails the native
  regression with three issues each. Comparing the cumulative counter rather
  than the current return's delta fails its later complete-zero-exit check.
  A complete ternary return remains recovered. Full-function exit-path
  selection and loop execution remain separate validation work.
- **MEASURED — 580 tests pass; all 152 fixture views are unchanged.**
  Structured/pseudo comparisons against 9e1b914 change zero outputs. The
  two-batch, 36-configuration Swift research run (`research --iterations 2
  --seed 7`) retains 1,326 of 1,530 verified Onone cases (204 unknown), and
  1,428 at O/Osize (102 unknown), with zero refutations or missing observations.
  Its function-level multi-exit decline remains intact; the regression proves
  the corrected behavior when a caller supplies an explicit nonzero exit.

## 2026-10-13: guarded multi-exit scoring in Swift

- **IMPLEMENTED — default cases select exits from supplied inputs.** Return
  probes carry a bounded path predicate. The scorer requires exactly one true
  path and evaluates its value against the independent expected result; it
  never searches for a return whose value matches the oracle. Declined values
  on proven untaken paths are ignored. Unknown, overlapping or unmatched paths,
  duplicate exit analyses and multiple image analyses decline. Explicit exit
  cases retain their direct-exit contract; legacy traces remain compatible.
- **IMPLEMENTED — observational path facts follow the CFG.** The public
  `Probe.returnPathConditions` helper uses acyclic dependency order, composes
  taken/fall-through guards and ORs joined routes. Detached DAG roots are
  unreachable. Cycles and dependents stay unknown, as do unsupported forks and
  external conditional targets. An unresolved indirect branch prevents claiming
  disconnected roots unreachable. Construction stops at 256 blocks, 512 nodes
  or depth 24 and discards exhausted evidence. The lazy producer changes no
  source output or value analysis. It is shared by raw-register and recovered
  source-return probes, with the same portable AST in saved JSONL traces.
- **VALIDATED — independent native, protocol and limit tests.** Five authored
  assembly functions add 55 native comparisons for split, shuffled, nested,
  joined and detached layouts. Controls cover a cycle and an external target.
  Saved-trace replay and four separate CLI processes preserve predicate trees.
  Protocol tests refute a deliberately wrong expectation, ignore only proven
  untaken declines, and reject ambiguity/duplicates/multiple images. Block,
  node and depth bounds have separate regressions. The initial default scorer
  tests were red with two issues before implementation.
- **VALIDATED — twelve independent mutations fail.** Removing selection,
  duplicate/image/unique-match checks, reversing taken predicates, losing OR
  joins, using address order, permitting external targets, trusting cyclic
  exits, and relaxing each bound fail with 9/1/1/1/6/2/2/1/1/1/1/1 issues.
  This is return/path validation; full executable-body scoring, loop execution
  and side-effect oracles remain open.
- **VALIDATED — all three producer hooks and incomplete CFGs.** Removing raw
  register, declined-outcome or recovered-value path evidence fails separately
  with 6/2/69 issues. The native corpus gate now requires optimized boundedLoop
  zero-exit cases to verify without exit addresses. Suppressing the unresolved
  indirect-branch guard fails its otherwise-disconnected-return regression.
- **MEASURED — 590 tests pass; 154 fixture views are unchanged.** The two-batch
  36-configuration Swift run (`research --iterations 2 --seed 7`) retains
  1,326/1,530 verified Onone cases with 204 unknowns. O/Osize verifies 1,441,
  previously 1,428, with 89 unknowns. Exactly 13 boundedLoop zero-exit cases
  gain verification in each optimized configuration; no partial nonzero return
  is verified. All runs have zero refutations or missing observations. This
  does not establish complete loop reconstruction or full-body accuracy.

## 2026-10-13: scalar tail-return forwarding

- **FIXED — a tail-called result disappeared from source output.**
  LargeStrings.matches's slow path ends in B to Swift._stringCompareWithSmolCheck,
  whose Bool result is returned directly to the original caller. Both views
  printed the call as a standalone statement, leaving only the identity fast
  path's `return true`. The slow path now emits `return callee(...)`.
- **IMPLEMENTED — signatures and ABI constrain forwarding.** Only a direct
  branch outside the function to an ordinary synchronous Swift callee with
  the same proven scalar result type qualifies. Caller/callee async, throwing,
  generic/closure/reabstraction conventions, mismatched results, void and
  multiword results decline. Caller ABI eligibility is computed once per
  function. The branch and its target remain intact for CFG and xrefs;
  reconstructed call arguments and side-effect order are unchanged.
- **VALIDATED — authored wrappers and the real fixture lowering.** Int, Bool
  and Double wrappers at Onone/O/Osize cover BL/RET and optimized B forms;
  Void remains a statement. Independent native execution adds 42 wrapper/leaf
  comparisons using exported Swift symbols and the external demangler. ABI
  controls cover incompatible effects/types/conventions and internal/call
  branches. A `tail-call` return outcome is observable, but the outgoing
  argument registers are never emitted as returned-value claims or raw exits.
- **VALIDATED — ten independent mutations fail.** Removing return emission,
  the external-target, branch-kind, caller/callee effect, result-type, scalar
  ABI, caller/callee head or diagnostic-status checks fails with
  14/1/1/1/2/1/4/1/1/2 issues. All 595 tests pass in the enforcing suite.
- **BLAST RADIUS — 22 of 160 fixture views change.** Every changed line adds
  return forwarding to an existing call, with identical arguments. Changes
  cover AuditSemantics.adjacent, CallArity.callMixed, Compares.onMinusOne and
  onMinusTen, ImportedClassProbe's three wrappers, LargeStrings.matches,
  Reconstruction.clampLow at O/Osize and both stripped twins, and six scalar
  wrapper instances at O/Osize. Call count, stores, ordering and CFG branches
  are unchanged. All other output is stable.
- **MEASURED — native research stays conservative.** The two-batch 36-mode
  Swift run retains Onone 1,326/1,530 verified cases (204 unknown) and O/Osize
  1,441 verified (89 unknown), with zero refutations or missing observations.
  Tail-call return markers do not count opaque call results as proven values.

## 2026-10-13: ABI preservation, loop switches and CFG bound proofs

- **FIXED (`9e2f279`) — a switch case leaving its enclosing loop used the
  switch's break.** In `loopswitch.s`, case 0 must leave the loop and call
  `finished()`, while cases 1–9 repeat. Previously, the structured output's
  bare `break` repeated `while (true)` indefinitely. Loop contexts now track
  intervening switches and emit an explicit labeled transfer across their
  scope; nested loops retain local breaks. Six regressions cover direct and
  conditional exits, nested switches, nested loops, ordinary loop breaks and
  native table decoding. Independently disabling scope propagation or goto
  rendering fails five tests with eleven assertions; restoration rebuilds
  green. Reproduce with `swiftdc disasm Fixtures/Sample/libLoopSwitch.dylib
  --structured -f loopSwitchExit`. Switch indices and irreducible-loop
  reconstruction remain outside this fix.
- **FIXED (`7b5d5ce`) — saved-register proofs account for overlapping store bytes.**
  `CalleeRegisterSummary` now invalidates the complete byte extent of stores,
  including narrow, unaligned and SIMD writes, and uses actual pair strides.
  Only full-width GPR stores can establish saved-entry facts. Indexed writes
  through a known stack base and unmodelled stack writes decline save proofs.
  In `abi_saved_slots.s`, two callers previously rendered `return arg0`,
  despite their fragments changing bytes in saved x19; both now decline.
  For input `0x1122334455667788`, native execution independently returns
  `0x11223344aa667788` and `0xaabbccdd55667788`. Coverage includes disjoint
  stores, normal saves/restores, FP writes, both decode paths and 32 native
  calls (`ABISavedSlotTests`). All seven focused tests pass. Restoring the
  baseline and independently disabling ranges, narrow widths, pair strides,
  the GPR-source guard, unknown-index decline, unsupported-store decline or
  STNP save support fails with 30/9/2/1/1/1/1/1 assertions respectively;
  restoration rebuilds green. Reproduce with `swiftdc disasm
  Fixtures/Sample/libABISavedSlots.dylib -f ABIStackSlots --pseudo` or
  `--structured`. Existing assumptions about non-stack pointers
  and escaped aliases remain outside this byte-overlap fix.
- **FIXED (`334628b`) — jump-table guards prove the index actually read.**
  `JumpTables` rejects a narrow comparison bounding a wide load, a call
  clobbering clamp flags, and a destructive SUBS replacing the compared index
  in either the clamp or branch-guard form. `jump_table_bounds.s` reduces
  all four unsafe proofs alongside five valid controls, including UXTW,
  rechecked flags and SUBS writing a separate destination. The tests cover
  both whole-file objdump and filtered Capstone paths (`JumpTableBoundTests`).
  All eight focused table tests pass. Independently removing the width, call,
  destructive-clamp or destructive-guard check fails with 8/8/2/2 assertions;
  the restored source was rebuilt and passed again. Across 88 fixture CFGs,
  only the reduction changes (nine tables to five); the other 87 retain
  identical indirect-branch targets. `/bin/zsh` arm64e retains all 22 recovered
  tables with identical targets. Declined tables retain unresolved indirect
  transfers. Reproduce with `swiftdc disasm
  Fixtures/Sample/libJumpTableBounds.dylib --cfg`.
- **VALIDATION MAINTENANCE — unknown-return coverage survives REV support.**
  Scalar REV recovery makes byteSwap a recovered result, and CLZ, CLS and
  RBIT recovery a leading-zero count. `unknownreturn.swift` now supplies a
  popcount (`cnt`/`addv`, still unmodelled); `UnknownReturnTests`
  still requires `return ?`
  and an unknown probe outcome. All new fixtures, including byte reversal,
  are built by `Fixtures/Sample/build.sh` and required by the enforcing suite.
- **BLAST RADIUS — seven of 176 fixture source views change after byte
  reversal (`c9de323`).** Across 88 fixtures in structured and pseudo modes,
  the ABI reduction changes two incorrect scalar returns to unknown;
  the loop-switch reduction adds its
  exit goto and label in one view; the bound reductions retain unresolved
  transfers in two views. The remaining two changes are in sample.debug:
  its outlined Foundation.Data representation helpers write a W register
  immediately before the saved x29 slot. Correctly retaining that disjoint
  save restores frame addresses and spilled-call bindings. The new
  `local_50`/`local_58` argument pairs are proved by `sub x1, x29, #...;
  mov x0, x1`; related call-result bindings and temporary numbering follow.
  All other fixture source views are byte-identical. This measures the
  reductions and fixture corpus, not complete ABI or control-flow recovery.
- **VALIDATED — 614 tests pass with fixture presence enforced.** Freshly
  rebuilt via `swift build --build-tests`, then
  `SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build`: all 614 tests in eleven
  suites pass, including the final disjoint-word-store control. CLI smoke
  checks on libSample succeed with nonempty output for disasm, dump, layout,
  interface, objc, xrefs (`--unreferenced`), analyze and swift-version. The
  four code commits passed enforcing suites at each intermediate state.

## 2026-10-13: scalar byte reversal

- **FIXED (`c9de323`) — scalar REV results were unmodelled.** Model 32/64-bit
  REV, REV16 and REV32 using explicit per-chunk byte-swap expressions, retaining
  W-register normalization and conservative register/width/depth guards.
  Constant folding and integer probe evaluation share the byte permutation;
  native ARM64 instructions provide independent expectations. The authored
  bytereversal.s fixture covers five forms with 255 native comparisons
  (`scalarByteReversalMatchesNativeInstructionsIfPresent`). The unknown-return
  regression now uses a CLZ/RET lowering instead of supported byteSwap.
  Fixtures are built by build.sh and required in the enforcing suite.
  Reproduce with `swift test --filter scalarByteReversal`.

- **VALIDATED — 596 tests pass with fixture presence enforced.** Removing
  REV tracking or byte-swap probe evaluation independently fails the native
  regression with one issue; restored source is rebuilt before testing. Six
  of 176 fixture source views change, recovering byte reversal in all three
  research images; the remaining 170 views are identical.

## 2026-10-13: preservation and oracle trust follow-up

- **FIXED — the audit footprint guard swallowed child failures.**
  `Tools/audit/guard.sh /tmp/guard 100 -- /usr/bin/false` logged `exit 1`
  but returned 0 because its final command was `echo`. Capture the result of
  `wait` and return it after logging. Independent subprocess checks preserve
  exits 0, 1 and 23. `auditMemoryGuardPreservesChildExitStatus` protects both
  the shell status and the log; removing `exit $rc` must fail the nonzero cases.
  This changes audit reliability, with no decompiler output or hot-path effect.
  Removing the status-propagation line fails with three issues (exits 1, 23
  and terminated-child 143 become 0). The restored intermediate enforcing
  suite passes 615 tests in eleven suites; the original baseline passes 614.

- **FIXED (local frame-derived escapes) — save proofs survived writable
  pointer aliases.** `abi_escaped_saves.s` independently returns its replacement
  argument through five fragments; baseline rendered `return arg0`. A separate
  MAY frame-provenance set survives joins and unsupported transforms. Pointer
  stores/calls make escape persistent, including before a save is created;
  unknown writes and subsequent calls invalidate exposed save facts. Six
  independent mutations fail with 19/10/19/9/9/1 issues (call invalidation,
  call escape, stored escape, join, transform, escaped unknown store).
  The native matrix executes 96 comparisons; the safe ordinary-call control
  retains its seed. Both decoding paths and both text renderers decline the
  five incorrect caller results.

- **OPEN — precise call memory footprints are required to regain legitimate
  preservation coverage.** This protection intentionally loses some correct
  `-Onone` output. `Indirect.makeWide` and `otherWide` pass a temporary at
  entrySP[-56,-16) to a six-instruction initializer writing exactly 40 bytes,
  then memcpy; the saved frame pointer is at [-16,0). The present summary
  cannot carry that disjoint footprint through calls. Both return buffers
  still reconstruct inside their producers, but consumers lose x29-relative
  fields. The Onone tests now require an explicit decline and a single visible
  producer call; optimized result-field recovery remains required. This is a
  measured completeness cost, not a correction to those formerly valid values.
  Reproduce: `disasm Fixtures/Sample/libIndirect.dylib -f makeWide`.
  Across 178 source views, 16 change: the new escape reduction declines five
  wrong returns; ABISource loses an unused optional-result binding; Indirect
  loses the two frame-derived results above; Reconstruction ordinary/resilient
  countMatches loses iterator self and an assertion's frame-spilled literal;
  RetainRegister.join declines its frame-preserved scalar; sample.debug loses
  frame-derived iterator/Stack arguments; sample.release loses frame-spilled
  metadata-helper arguments. Both views change for each of these eight images.
  No call/store ordering or CFG changes are introduced.

- **OPEN (independently reproduced) — preservation is not yet a complete
  interprocedural or alias proof.** Nested outlined-call and tail-call clobbers
  do not propagate; x29-only custom callees can mutate save memory; incoming
  pointers can reach caller-owned saves at nonnegative entry-SP offsets.
  Authored native reductions return a replacement while output claims arg0.
  The local-escape correction does not resolve these cases. Ordinary ABI
  stack ownership remains an assumption for unescaped negative save slots.
  Restored, freshly rebuilt intermediate enforcing suite: 620 tests in eleven
  suites pass. This is scoped escape coverage; no complete alias proof or
  performance improvement is claimed.

- **FIXED (caller-owned save ranges) — incoming pointers could mutate a
  save without a local escape.** `abi_frame_ownership.s` stores x19 at positive
  entry-SP offsets, across the entry-SP boundary, or at zero before a call.
  An incoming pointer can reach those caller-owned bytes. Unknown writes and
  calls now discard every save whose eight-byte end exceeds entry SP;
  local aliases/escapes still discard all saves. Checked addition handles
  overflow, and an exact [-8,0) control remains preserved under the existing
  ordinary-ABI ownership assumption. This is not proof of arbitrary negative
  memory privacy or nonstandard x29 conventions.
  Before correction, three callers rendered arg0 although native execution
  returned the replacement/full upper word. 64 native comparisons and both
  decoding/rendering paths cover all three and the safe control. The pre-fix
  regression failed with 36 issues. Five independent mutations fail with
  36/14/39/4/31 issues (ownership filter, straddling extent, supported write,
  unsupported write, call effects); all original escape regressions still pass.
  Freshly rebuilt enforcing intermediate suite: 624 tests in eleven suites.
  Across 180 fixture source views, only the new ownership reduction's two
  views change: three wrong returns decline, and its safe control is unchanged.

- **FIXED (represented async aliases/effects) — context-slot constants survived
  unrepresented pointer provenance and writes.** Native ARM64 wrappers show
  slot16 changing from 7 to 18 through a spilled pointer, interior pointer,
  FMOV round trip or vector-loaded parent pointer; byte/unaligned writes produce
  263. Six native executions also check final memory. Register-only escape
  analysis now declines stored pointers, copies through every source position
  and register bank, interior addresses without a proven write footprint,
  unrepresented stores and parent-pointer loads. Exact full-width GPR parent
  loads and aligned recorded GPR stores retain their existing treatment.
  Thirteen soundness regressions cover detector and chain seed claims; the
  native regression and no-escape control remain independent. Baseline tests
  fail with 30 issues. Six individual mutations fail with 2/9/9/6/4/10 issues
  (stored pointer, memory widths, copy inputs, footprint, register bank,
  parent-pointer load). Rebuilt enforcing intermediate suite: 638 tests in
  eleven suites pass.

- **OPEN — stronger escape checks also decline valid async spill recovery.**
  Exporting ParentContext into a callee context does not by itself bound writes
  to the parent. Without interprocedural memory effects, twoAwaits's saved
  awaited1 across its second suspension, fetchOrThrow's parameter across a
  hop, and onMainAwait's stored result now decline. Direct awaited results,
  subsequent direct call arguments, executor hops and error transfers remain
  reconstructed. The previous native/source behavior is still valid; these
  are explicit completeness losses rather than corrected values. Updated
  expectations require unknown returns/raw machine conditions for these cases.
  Future recovery requires memory-effect or ownership evidence, not an x22
  handoff exception based solely on spelling.
  Blast radius: four of 180 source views change, only optimized AsyncFns and
  its stripped twin in both views. Each loses the three spill-derived returns
  above; fetchOrThrow's condition retains the machine register/sign-bit test.
  All other fixture output is unchanged. No CFG or funclet ownership changes.

- **FIXED — mixed-image traces could falsely verify a single return.**
  `ProbeScoring.report` previously rejected multiple loader events only for
  default-exit cases containing multiple facts. An explicit exit or one
  surviving fact bypassed it. Addresses do not identify an image, and records
  lack per-image association: any two loader events now decline scoring,
  including repeated UUIDs. UUID-bound manifests retain invalid-input handling;
  single-image and legacy image-free traces retain their previous contract.
  Twelve formerly accepted scenarios cover both scoring modes, explicit/default
  exits, one/two facts, and repeated/distinct UUIDs. Reinstating the old condition
  fails 36 assertions; restored three focused tests pass. Rebuilt enforcing
  intermediate suite: 641 tests in eleven suites pass. This changes scoring
  only; all disassembly source views remain byte-identical.

- **FIXED — async chain facts could flow backwards in time.** A unique
  chain-wide store was used as an entry seed even before that store executed,
  or on a branch that skipped it. Authored ABI-compatible leaves use explicit
  async entry hints and a compiler-style ResumeParent return. Native execution
  observes 11 before a later store of 7; the conditional leaf observes 11/7
  according to its input. Both final source views previously said `observe(7)`.
  Entry now receives no chain seeds. Resume seeds require a matching definite
  entry-state fact at every actual entry suspension, in addition to unique
  portable stores and the existing alias/effect checks. Later-resume stores
  cannot seed earlier observations. Snapshots are requested only by the chain
  pass at those transfers; ordinary analysis records none.
  Four pre-fix regressions fail with six issues while six native return/memory
  observations pass. Three positive/overhead controls retain forward local
  recovery and unconditional resume initialization. Independent mutations of
  entry exclusion, definite transfer proof and snapshot production fail with
  1/3/2 issues. The synthetic chain tests isolate analysis seams, rather than
  claiming compiler-generated context layouts. Rebuilt enforcing suite: 648
  tests in eleven suites. Only two of 182 source views change, both belonging
  to the new chronology reduction: false `observe(7)` becomes `observe(?)`.
  This sufficient temporal condition is not a complete inter-funclet proof.

- **FIXED — async memory facts survived writes through possible aliases.**
  Authored ARM64 leaves store 7 through x22, then 11 through an incoming
  pointer aliasing that slot. Native execution returns 11 and observes 11 in
  memory; final source previously rendered `observe(7)`. Context seeds and
  ResumeParent/callee-parent header facts now live in mutable forward state,
  with no immutable fallback after invalidation. Unknown writes clear both
  context identities; precise writes invalidate overlapping byte intervals.
  Paired loads use current local stores. Only full-width GPR stores establish
  integer facts: a SIMD store of 1.0 cannot establish integer 1.
  Unknown write widths cannot prove private-frame disjointness. A native ST4
  reduction writes 64 bytes starting eight bytes below entry SP and changes
  the caller-context word. Checked complete negative extents retain ordinary
  live-frame ABI disjointness; caller-owned and straddling extents decline.
  Relative context offsets do not prove allocation bounds: native reductions
  place child+32 at parent+16 and parent-16 at child header zero. Known writes
  therefore also forget the other identity's memory facts when present.
  Loaded scalar register snapshots survive; exact later stores can recover
  their own local values. Chain seeding declines any unbounded write, including
  an incomplete analysis. Calls remain a separate confirmed open limitation.
  These are authored machine-memory observations and analysis-seam regressions,
  not a proof of complete compiler async ABI or arbitrary allocation ownership.
  Twenty-seven regressions include seven native executions and fifteen return/
  memory observations. Fourteen independent mutations fail with respectively
  1/1/17/1/13/2/2/1/4/1/2/2/2/1 issues (opposite identity invalidation,
  unknown write, chain flag, scalar/paired seeds, scalar/paired parent headers,
  overlap/adjacent ranges, register bank, private extent, unknown width,
  incomplete analysis). Restored fresh build passes 675 tests in eleven suites.
  Six of 184 source views change: the new leaf loses its stale observed value
  and unproved return header; RethrowCleanup.persist resume #3 retains a raw
  indirect branch because stores through unknown modify-accessor results at
  0xfc8 and 0x1004 cannot prove ResumeParent disjointness. TypedThrowsAwait's
  onError(?) becomes onError(): independent source and x0 setup confirm this
  exposes a separate existing argument-snapshot omission. Its known Int
  footprint must retain a placeholder; this arity correction is next, rather
  than restoring unproved context facts. No existing golden test is weakened.

- **FIXED — known scalar calls lost all-unknown arguments.**
  TypedThrowsAwait.useCode's error continuation calls onError(Int) with x0 set
  to an unproved context value plus 1000. Dropping a wholly unknown positional
  snapshot bypassed the existing signature layout and rendered onError().
  Missing snapshots are now completed only for resolved calls/tail calls whose
  existing Swift layout proves a nonempty footprint; layout fills unknown
  integer/floating values without trailing trim. Unsupported generic, aggregate,
  async and unresolved layouts retain their previous treatment. Independent
  compiler source and LDR/ADD/BL instructions establish one supplied Int.
  Two regressions pass; before correction the rendered/arity test fails five
  assertions. Disabling missing-site completion independently reproduces those
  five failures. All 184 source views were compared: four change, restoring one
  unknown argument to TypedThrowsAwait.onError and AuditSemantics.walk's log
  in each renderer. Source and machine x0 setup confirm both scalar footprints.
  Fresh restored enforcing suite: 677 tests in eleven suites pass.

## 2026-10-15: Swift error exits

- **FIXED — a throwing function's unproven exit rendered as a normal
  return.** Every `ret` of a throwing function counted as a normal return
  unless x21 was proven to hold a thrown error. Two shapes return and throw
  through one exit:
  `Reconstruction.typedForward` at -O and -Osize ends
  `cmp x21, #0; csel x21, x21, x8, eq; cinc x0, x0, eq; ret`, and
  `TypedThrowsAwait.codeAsync` resume #2 joins `mov x20, #0` and
  `mov w20, #1` at one ResumeParent branch. Both rendered `return ?`.
  An exit is now normal only when one proof covers every path into it:
  1. `SwiftErrorExitProof`: x21 untouched since entry, set to zero, or on
     the zero edge of a 64-bit `cbz`/`cbnz x21`. A call keeps x21 only when
     the callee provably does not throw and its body summary restores x21.
     An undecoded instruction, an unreachable predecessor or an orphan
     block ends the proof. An async function's x20 holds self on entry, so
     there only zeros prove.
  2. Per-exit `Preservation` (`f2587e2`): x21 holds its entry value through
     a spill and reload (-Onone) or a register copy (-O `mov x19, x21` …
     `mov x21, x19`), on blocks every way into which is modelled.
  3. The tracer's existing zero facts.

  Throw paths already rendered `throw ?` at a merged epilogue are set aside
  by both proofs. An unproven exit renders `machine_return() /* unresolved
  Swift success/error exit */`; a proven exit with no value renders
  `return`. Unresolved indirect branches still decline the whole function.
  The structurer keys its unclassified exit on the `throws` signature, so a
  non-throwing function that catches a callee's error keeps its returns.
  A new note, `swift-exit=unknown|normal`, is excluded from callee-name
  parsing (it would otherwise have read as a callee).

  Blast radius: 19 of 194 fixture views change. New fixture
  `libErrorExitControls` (2 views). Corrections: `typedForward` at
  -O/-Osize and their stripped twins (8 views) and the async resume
  (2 views) now render `machine_return()`. SwiftErrorProbe's pseudo view
  gains its proven void `return` (1 view). Losses are the two OPEN entries
  below (6 views). The earlier draft of this change, which accepted only
  explicit zeros, also declined -O/-Onone `mightFail`, `typedScale` and
  MergedThrow's `return r0`; all of those recover.

  Reproduce: `swiftdc disasm Fixtures/Sample/libReconstruction.opt.dylib
  --structured -f typedForward`.

  Verified: `ErrorExitProofTests` (11 tests over 27 fixture functions plus
  synthetic bodies) and the restored `aThrowMergedIntoTheEpilogue` and
  typedScale expectations. Thirty mutations, each seen red: every guard of
  the dataflow (entry state, entry back edge, zeroing, zero edge and its
  width, call rule, writes, undecoded instructions, unreachable start and
  predecessor, merged-throw exclusion), both call-rule halves (clobber
  summary, may-throw), the preservation proof and its call hook, modelled
  blocks, merged-throw exclusion and excluded-edge propagation, the note
  emitters and renderers, the callee-name exclusion, the signature proof,
  the opaque-branch declines and the async x20 proof (caught by
  `asyncThrowsRenderAsThrows`). Enforcing suite: 688 tests in 11 suites.

- **OPEN — the -Onone `try` exit declines.** `Reconstruction.typedForward`
  at -Onone (and resilient) spills the callee's x21, tests it with `cbz`,
  and on the zero edge reloads x21 from the spill. Proving the reload zero
  needs "this slot holds the value that was tested", which no analysis can
  say. It renders `machine_return()` where the source returns `r0 + 1`.
  Needs value identity with edge refinement ([IR.md](IR.md) step 5).

- **FIXED (the commit after 6cca3c4) — `throws(Never)` specializations
  declined.** Two generic specializations of `withUTF8CodeUnits` in
  `sample.debug` with `B = Swift.Never` spill x21, call their closure
  through `blr`, and return. They cannot throw, but the signature reads
  `throws(B)` and the indirect callee may write x21. The specialization's
  substitution list, read from the demangle tree, now proves `B = Never`
  and both exits are returns; see 2026-10-23 at the end of this file.

## 2026-10-15: frame slots reachable through escaped addresses

- **FIXED — a frame slot kept its value across writes through an escaped
  address.** `StackCallEffects.cacheEscape` at -O and -Osize stores a stack
  address to a global, writes 7 through it, and calls a helper that writes
  11 through the global; native execution returns 11 for every seed, and
  the source view said `return 7`. The tracer forgot a slot only while its
  address sat in an argument register at that very call, and a store
  through an unknown pointer forgot nothing. Ten authored reductions in
  `frame_escape_controls.s` rendered `return 7` against native 11 (or 0):
  escape through an earlier call, through an outgoing stack argument, on
  one path of a join (before or at it), through a global reloaded as an
  unknown pointer, an indexed frame store, an `st1` into a slot, a
  bit-reversed address, a pointer read back through an alias, a pointer
  dropped at a join, and a write to the second word of an escaped local.

  The tracer now keeps MAY markers of escaped frame regions, unioned at
  joins and never cleared. A frame address escapes when it reaches a call
  (x0–x8, x20, outgoing slots), is stored anywhere but an exactly tracked
  frame slot (or into a slot that has itself escaped), is transformed
  beyond the tracer's arithmetic, or is dropped from a slot or a join while
  it is still in memory or a register. Every call except the exactly
  modelled memory helpers and read-only projections, and every store
  through a pointer that does not predate the frame, forgets the escaped
  regions; a forgotten slot that held a frame address escapes that address
  too. Stores the tracer cannot bound (indexed, unmodelled store opcodes)
  forget what they may reach. A region runs from the escaped address to the
  next address-taken local, as before; an address into a dynamic
  allocation reaches only below the frame offset it was carved from.

  Blast radius: 6 of 196 fixture views change, all in the new reductions
  and `cacheEscape` (-O, -Osize: `return 7` becomes `return ?`). Every
  other fixture view is byte-identical, including every Onone spill and
  reload the blanket "forget memory at every call" proposal of
  2026-10-13 lost. On Clarc (13,861 functions, `disasm --pseudo`), 142
  functions change, all from dynamic allocation (20 of 20 sampled): an
  allocation sized from runtime metadata makes `frame(k) - size` an
  unknown value, so the lost-provenance rule escapes the whole frame and
  later calls forget the fixed frame's spills (mostly metadata accessor
  results reused as call arguments). Release A/B on Clarc, alternating,
  three rounds: 33.40 s against 34.32 s median (+2.8%); peak footprint
  59.4 MB against 58.4 MB (noise).

  Reproduce: `swiftdc disasm Fixtures/Sample/libStackCallEffects.opt.dylib
  --structured -f cacheEscape`.

  Verified: `FrameEscapeTests` runs every reduction natively (23
  executions) and checks both views of all 17 plus `cacheEscape` on the array,
  filtered and streamed paths. Twenty-one mutations, each seen red: the
  call's register and outgoing-slot escapes, the call's forgetting and its
  helper exemption (full suite), the store escape, escapes into escaped
  slots, the forget-escape fixpoint, join union and dropped values,
  unknown-pointer stores, entry-provenance pointers in both directions,
  unbounded and unmodelled frame stores, lost provenance, the dynamic
  allocation marker, its region and its store bound, the escaped region's
  extent, the whole-frame marker, and read-only loads. Enforcing suite:
  692 tests in 11 suites.

- **OPEN — dynamic allocations sized from runtime metadata forget the
  fixed frame.** `frame(k) - unknown` collapses to an unknown value, so
  the block's address loses its provenance and escapes the whole frame
  (142 Clarc functions). Keeping frame provenance alongside an unknown
  value is the shared memory model's job ([IR.md](IR.md) step 4).

- **MITIGATED — empty argument lists read as "no arguments".** When every
  positional value of a signatureless callee becomes unknown, the trimmed
  list renders `swift_arrayInitWithTakeBackToFront()` where the call takes
  four. The escape fix makes this more frequent in Clarc. A call of known C
  arity now shows exactly its parameters (see "2026-10-15: known C
  arities", below). A call whose arity is unproven still prints its
  trimmed positional values, `()` when none is known; the body-read bound
  is too loose to pad (any inner call counts as reading all eight
  registers).

- **FIXED — the objdump path stripped every leading underscore from
  callee names.** `calleeName(of:)` turned `___stack_chk_fail` into
  `stack_chk_fail` where the in-process paths say `__stack_chk_fail`. The
  unrecognised name missed `knownCArity` (zero) and runtime-noise lists
  (`__chkstk`), so the array path rendered `stack_chk_fail(r0)` at -Onone,
  an argument the C function does not take, bound the closure result it
  "consumed" as `let r0`, and disagreed with the filtered and streamed
  views of `cacheEscape`. A Mach-O symbol has one linker underscore; only
  that one is stripped now. Blast radius, on the objdump-backed outputs
  (plain listing and `--json` for every fixture): 19 of 196 change.
  `__stack_chk_fail` loses `args(r0)` and `args(((r1 == 0) ? r3 : ?))`
  (SwiftErrorProbe, both twins), and the `let r3 = swift_errorRelease(r2)`
  binding it forced; `__sincos_stret`, `_Unwind_Resume`,
  `__cxa_begin_catch`, `__clang_call_terminate` and
  `_swift_stdlib_reportUnimplementedInitializerInFile` get their C names.
  The streamed `--structured`/`--pseudo` views are byte-identical.
  Verified: `objdumpCalleeNamesKeepTheirOwnUnderscores` and the restored
  three-path equality in `compiledStackEscapeIsNotRenderedAsThePreCallStore`
  fail with 14 issues under the old stripping; enforcing suite 693 tests.

## 2026-10-15: async context slots across calls

- **FIXED — an async context slot kept its value across calls that could
  write it.** Authored ABI leaves (`async_call_effects.s`) store 7 to their
  own context slot 16, let the context escape, call something that writes
  11 there, and observe the slot. Native execution observes 11. Five leaves
  rendered `observe(7)`: `globalLeaf` and `conditionalLeaf` export x22 to a
  global, `interiorLeaf` hands `x22 + 16` to a call, `rbitLeaf` exports it
  bit-reversed, `joinLeaf` passes it through a join that drops it. The
  tracer forgot context slots at a call only when the exact context pointer
  sat in an argument register at that call.

  The frame escape markers now cover the context. An own-context pointer
  escapes on the same events as a frame address, with its offset: a pointer
  to offset k reaches k and above, so the header below an `inout` slot
  (ParentContext, ResumeParent) stays known. After an escape every call
  forgets the reachable context slots and declines chain-wide seeds.
  Storing the context into a context slot (the -Onone spill, the callee's
  parent header) keeps it followed. The awaited callee's context has its
  own marker; a call handed it (`swift_task_dealloc`) forgets only that
  context's parent header.

  Each of these precision rules was added after measuring a real-app loss.
  - **Known arity.** A call to a runtime entry point of known C arity passes
    only its parameters. `knownCArity` gains `swift_task_alloc`/`_dealloc`
    and the one-object refcount entry points, which also clamps their
    rendered arguments. sample.debug's plain listing loses fabricated
    trailing arguments such as
    `swift_release(?, ?, Data._Representation.init(…))`.
  - **Stack arguments.** They are the contiguous run stored upward from sp,
    as `snapshot` reads them. Only a callee that can take any (unknown
    arity, or a Swift signature needing more than eight registers) reads
    them, and never from the prologue's register save area.
  - **Save area.** It bounds escaped frame regions too, so an escaped local
    no longer reaches the callee-saved saves above it.
  - **Joins.** A join escapes only values it drops from a register or slot,
    not from an outgoing copy or the callee's header.

  Escape markers are now sticky per block in both fixpoints. A marker
  derived from a value dropped at a join can stop being derived once that
  value is forgotten, then return. On GoodLinks this made one function cap
  (`values.fixpoint-cap`: all its values lost) and another loop-body pass
  cap.

  Blast radius: 4 of 196 fixture views (the two reduction fixtures).
  Clarc's `--pseudo` is byte-identical to the frame-escape commit. On
  GoodLinks (64,322 functions), against that commit, 16 functions change:
  - **Corrections:** two `_convertNSErrorToError(0)` became `(?)`. The error
    out-parameter lived in the async context, and an interior pointer to it
    reached the throwing call.
  - **Recoveries:** five functions recover arguments that broad escapes had
    hidden.
  - **Losses:** four async exits, and seven call arguments in five
    functions. In each, an escaped local's region (up to the next
    address-taken offset) reaches a later x22 spill, or an interior context
    pointer's region (offset upward, no object boundary) reaches a slot
    above the object.

  Fixpoint caps on GoodLinks: one, the same pre-existing function at every
  build; the frame-escape commit's loop-body cap is gone. Release A/B on
  Clarc, five alternating rounds: 33.80 s against 34.79 s median, inside
  the 32.8–36.4 s run-to-run spread.

  Verified: `AsyncCallEffectTests` (natively: twelve adapters, 15
  executions; both views of 10 leaves; a tracer-seam test of the callee's
  header) and three frame precision controls. Eighteen mutations, seventeen
  seen red: the context marker, interior offset, call
  forgetting, region bound, context-slot stores (full suite), the callee's
  marker and forgetting, lost provenance, dropped context values,
  value-holding keys, the arity-limited registers, the stack-argument
  run, its save-slot stop, the save-area boundaries, both directions of
  the stack-argument bound, and the arity table (full suite). The sticky
  markers survive on every fixture. They are verified only on GoodLinks,
  where removing them caps `values.fixpoint-cap` and keeping them
  converges. The population test `theTracerModelsEveryWriteOnTheFixtures`
  now also covers the async, frame-escape and compiled stack fixtures.
  Enforcing suite: 696 tests in 11 suites.

- **OPEN (assumption) — a caller does not pass pointers into the callee's
  own context.** `incomingLeaf` (an incoming argument aliasing slot 16)
  still renders `observe(7)` against native 11; compiled Swift does not
  pass one. The second half of this entry, a sync callee that reads x22,
  is fixed (b9c1b02): `implicitLeaf` (a C helper writing through x22)
  renders `observe(?)`, because a callee whose body uses x22 receives the
  context (`CalleeRegisterSummary.readsContextRegister`).

- **OPEN — context regions have no object boundaries.** An interior
  context pointer reaches every slot above its offset, and an escaped frame
  local reaches every slot up to the next address-taken offset; both cost
  GoodLinks values (above). Object extents belong in the shared memory
  model ([IR.md](IR.md) step 4).

- **FIXED (tests) — no fixture reproduced the join-derived marker
  oscillation.** `markeroscillation.swift` at -O (`[a, b, c].compactMap
  { $0 }`, a stack array compacted in a loop that re-materializes its base)
  hits `values.fixpoint-cap` without the per-block sticky markers in
  `analyze`, and every call in it renders `()`.
  `theTracerConvergesWhereAJoinDerivesAnEscapeIfPresent` fails with them
  removed (2 issues).
- **DEAD END (tests): no test can see the loop-body pass's sticky
  markers today.** Removing them from `retransferBody` left all 701 tests
  green and every fixture (also the -Onone and -Osize builds of
  `markeroscillation.swift`) without a cap. On GoodLinks one 578-block
  loop then hit `values.loop-body-cap`, and GoodLinks and Clarc output
  stayed byte-identical. That GoodLinks number predates the converged
  header seed (`ff9c56f`) and was not rechecked.

  Rechecked at `13fe3d5`, after the converged seed. With the carry
  removed, the enforcing suite still passes (728 tests in 11 suites).
  A temporary audit, reverted, re-ran every loop-body pass the suite
  reaches (342, CLI subprocesses included) with and without the carry,
  under the converged seed and under the old entry seed. In all 342,
  under both seeds, the non-marker states and the capped-or-settled
  result are identical. The carry restores a marker in one pass only:
  the 123-block loop at `0x192c94328` in CoreLocation's `sub_192c93d9c`,
  reached by `streamingWholeImageMemoryStaysLowIfPresent`. It restores
  `frame.escaped@-1848` and `@-1872` 12 times under the converged seed
  (14 under the entry seed), and every time the entry already holds
  `frame.escaped`, which reaches every slot, so nothing more is forgotten.

  The suggested shape cannot reach the carry. A frame address stored to
  a global on one path of an inner join raises its marker in the
  transfer, on every visit, and the join unions it in. `lateEscape` in
  `loopescape.c` is that shape, and the carry never fires on it.

  Why the carry has nothing to add: the header's entry is fixed to the
  seed, so the seed's markers reach every body block, and the seed holds
  every marker the main pass derived anywhere in the body (in all 342
  passes, no body block's converged state has a marker the seed lacks).
  Without an inner loop the body pass follows no cycle, so the carry can
  only keep a marker a join derived on an early visit and no longer
  derives on a later one. That needs the dropped address to leave every
  predecessor without raising the same marker or `frame.escaped`.
  Reading the transfer, a join drop, a forget and an untracked
  transformation each raise one, a context-slot store marks the address
  at the store, and a narrow store truncates the value so the paths
  differ. No other route was found.

  The body pass can derive markers the seed lacks: in `sub_192c93d9c` it
  raises `frame.escaped` at a join dropping `0 | (frame(-1864) ==
  frame(-1864))`, a pointer comparison `containsFrame` counts as an
  address, and the main pass derives no `frame.escaped` in that body. So
  an inner loop inside a body could still oscillate the way `analyze`
  did. Keep the carry: it is a MAY fact and costs nothing. Before retrying
  a fixture search, recheck GoodLinks at HEAD with it removed
  (`values.loop-body-cap` under `--probe`).

## 2026-10-15: a capped loop-body pass claimed its loop

- **FIXED — the induction pass named loop variables from unsettled
  states.** `retransferBody` re-runs a loop body from a seeded header and
  stops at `(body blocks + 1) × 8` visits. On hitting the bound it broke out
  and returned whatever states it had, and `resolveLoopInductions` named
  the loop's induction variables and updates from them. A bound that is hit
  must claim nothing. It now returns nil and the loop is skipped. The budget
  is injectable (`loopBodyIterationsPerBlock`, default 8, same bound as
  before). With a budget of one, one of `LoopEntry.nestedCounters`' two
  loops hits the bound; before the fix both loops kept their claims (two
  initializations, two updates), now only the settled one does. At the
  default budget no fixture and no GoodLinks function hits the bound since
  the sticky escape markers (above), so every fixture view and app output is
  unchanged.

  Verified: `aCappedLoopBodyPassClaimsNothingForItsLoopIfPresent` fails
  with four issues when the old `break` is restored and passes with the fix.
  Enforcing suite: 697 tests in 11 suites.

## 2026-10-15: known C arities

- **FIXED — calls of known C arity printed their trimmed operands.**
  Positional arguments drop trailing unknowns, so a runtime call whose
  operands were all unknown read as a call that takes nothing
  (`swift_errorRelease()`, `memcpy()`), and one with stale later registers
  read as taking more (`memset(local_38, 0, 40, arg3, arg4)` in
  ABISource.ABIFiveWords.init). A callee in `knownCArity` now gets exactly
  its parameters, unknown ones as `?`, the way a proven Swift layout does.
  The table gains `memcpy`/`memmove`/`memset` and, from
  swift/include/swift/Runtime/RuntimeFunctions.def, `swift_arrayDestroy`,
  the three `swift_arrayInitWith…` helpers and
  `swift_unknownObjectWeakLoadStrong`.

  Blast radius: 10 of 196 fixture views (`swift_errorRelease(?)` in
  SwiftErrorProbe and its twin and Reconstruction, the `memset` above in
  ABISource); on the objdump-backed outputs, 68 of 196 listing/JSON files,
  where runtime calls gain `args(?)`. Clarc `--pseudo`: 313
  `swift_errorRelease(?)`, 264 `memcpy(?, ?, ?)`, 127
  `swift_unknownObjectWeakLoadStrong(?)`, 94 `memmove`, 79 array helpers
  gain their fourth `?`.

  Verified: `KnownArityTests` (two tests) fail with two issues when the
  layout is removed and with two when `memset` leaves the table; enforcing
  suite 699 tests in 11 suites.

## 2026-10-15: per-function facts in the enrichment pass

- **FIXED (speed) — the enrichment pass re-derived per-function facts at
  every instruction.** A `sample` of a release `disasm --pseudo` on Clarc
  put 5,182 of 9,771 analysis samples in `enrichCallArguments`, with
  `hasProvenMachineValueReturn` (414), `signatureReturnsValue` (289) and
  `splitSignature` (284) among its leaves: the per-instruction value
  contract parsed the function's own demangled name twice per instruction.
  `swiftReturnRegister(of:)`, which reruns a CFG walk, ran at every return
  in four places, and `calleeName(of:)` re-parsed every instruction's
  annotation though a per-call map already held it. All are computed once
  per function now (after the no-facts early exit). Output is unchanged:
  every fixture's structured, pseudo, listing and JSON view is
  byte-identical, and so is Clarc's `--pseudo`.
  Release A/B on Clarc, five alternating rounds: wall 38.47 s against
  33.49 s median (-13%), user CPU 36.01 s against 32.05 s (-11%); every
  round of the change beat every baseline round.

## 2026-10-15: callee facts once per call in the tracer

- **FIXED (speed): the tracer re-parsed every call's callee name on every
  visit.** A `sample` of the release `disasm --pseudo` on Clarc put 5,009
  samples in `ValueTracer.transfer`, 1,148 of them in `calleeName(of:)`:
  call transfer parsed the name out of the annotation three times per call,
  and the Objective-C void-return hook a fourth, on every fixpoint lap and
  in every later pass (selects, loop bodies, the snapshot). The facts
  derived from the name (`splitSignature` 211, `hasTupleResult` 194,
  `swiftAccessorProperty` 190, `passesNoStackArguments` 274) were re-derived
  each time too. `ValueTracer.CallFacts` now holds them, built once per
  call instruction when `analyze` starts, and the hook receives the name.
  Output is unchanged: every fixture's structured, pseudo, listing and JSON
  view is byte-identical, and so is Clarc's `--pseudo`.
  Release A/B on Clarc, five alternating rounds: wall 33.80 s against
  29.35 s median (-13%), user CPU 32.33 s against 27.91 s (-14%); every
  round of the change beat every baseline round.

## 2026-10-15: frame layout parses only frame-register instructions

- **FIXED (speed): `frameLayout` split and trimmed the text of every
  instruction.** It ran once per `analyze`, but its operand parse (split,
  lowercase, trim) touched every instruction: 602 of 6,249 tracer samples
  on Clarc. Every rule in it needs an operand that is `sp` or `x29` or
  starts with `[sp`, so a byte scan now skips instructions naming neither.
  Output is unchanged: every fixture view and Clarc's `--pseudo` are
  byte-identical. Release A/B on Clarc, five alternating rounds: wall
  27.75 s against 26.51 s median (-4.5%), user CPU 26.88 s against
  25.60 s (-4.8%); four of five rounds beat their baseline.
  The x29 rules had no guard: removing either left every test green and
  every fixture view unchanged. `fpBoundary` and `fpAboveBoundary` in
  `frame_escape_controls.s` now pin them.

## 2026-10-15: callee facts shared across a run

- **FIXED (speed): every `analyze` re-derived each call's name facts.**
  After facts moved to once per call, building them (`FunctionFacts.init`)
  took 1,061 of the tracer's samples on Clarc: `analyze` runs more than
  once per function (enrichment, the re-analysis after indirect targets
  resolve, async chains), and the facts parse the signature four times.
  Clarc's 103,776 calls name only 5,636 distinct callees, so
  `ValueTracer.CallFactsCache` keeps them per callee name for one run
  (owned by the `Disassembler`, like `DemangleCache`). Output is
  unchanged: every fixture view and Clarc's `--pseudo` are
  byte-identical. Release A/B on Clarc, five alternating rounds, under an
  unrelated process holding five cores, so wall time is not comparable:
  instructions retired 371.9 G against 349.3 G median (-6.1%; every round
  of the change below every baseline round), cycles 98.5 G against
  92.3 G (-6.3%), user CPU 28.62 s against 26.45 s.

## 2026-10-15: typed tracer locations (IR step 3)

- **FIXED (speed): the tracer keyed its state by strings.** After the
  callee-facts changes, a `sample` of the release `disasm --pseudo` on
  Clarc put about 2,500 of the tracer's 4,899 self samples in string
  machinery: dictionary probes hashing key strings, `hasPrefix`, string
  comparison, building keys like `stack@-16` and parsing them back.
  `ValueTracer.State` is now `[Location: AbstractValue]`; `Location` names
  registers, frame, context and result-buffer words, the flags and the
  escape markers, and its `description` is the former key. Seeds keep
  their string spellings at the API and are parsed once per analysis. One
  order depended on the strings: loop-induction candidates are numbered
  in the former key order (`stack@-16` before `stack@-8`), kept by sorting
  on `description`. `result`'s width payload is `Int32`, which keeps the
  key at 16 bytes; at 24 bytes peak footprint rose 5-10 MB on Clarc.
  Output is unchanged: every fixture's structured, pseudo, listing and
  JSON view, Clarc's `--pseudo` and GoodLinks' `--pseudo` (16.4 MB) are
  byte-identical, and the determinism tests pass. Release A/B on Clarc,
  five alternating rounds: wall 25.97 s against 23.18 s median (-10.7%;
  every round of the change faster than every baseline round), user CPU
  25.18 s against 22.15 s, instructions retired 351.6 G against 309.7 G
  (-11.9%), peak footprint 59.4 MB against 59.8 MB.

## 2026-10-15: partial writes

- **FIXED (soundness): `movk` on a register the tracer held no constant
  for claimed a constant.** MOVK replaces one 16-bit field and keeps the
  other 48 bits. The tracer read a non-constant register as zero, so
  `movk x0, #1` on an argument claimed `return 1` (native:
  `(x0 & ~0xffff) | 1`). On GoodLinks the compiler builds a 64-bit
  small-string word with `mov`/`movk` and branches into the middle of the
  sequence from another path; the join dropped the low bits and four call
  arguments rendered a word whose low 32 or 48 bits were zero-filled, a
  value neither path makes (`LocalizationValue.init(0x746f4e2000000000, …)`).
  The result is now `(value & ~field) | inserted`, which folds to the same
  constant when the register is one, is exact for a symbolic value and is
  unknown otherwise. `partial_writes.s` runs each probe natively over 100
  input pairs; before the fix four of its five probes claimed constants
  (290 mismatches). Blast radius: no fixture view and no Clarc line change;
  GoodLinks changes at five call sites, four zero-filled words now `?` and
  one a select of the two words the paths build, top field included;
  `libswift_RegexParser` (arm64e) is unchanged.

- **FIXED (soundness): a join kept a frame slot's value after dropping its
  width.** Where one path stored a slot as eight bytes and another as four,
  the predecessors agreed on the value (a small constant is the same at
  both widths) but not on the width, and the meet dropped only the width.
  A later eight-byte load read the slot with no width check and claimed
  the value, though on the narrow path the upper four bytes are the
  earlier store's: `slot_width_join` rendered `return 1` where native
  execution returns 0xffffffff00000001 on that path. A diamond whose
  condition is recoverable was safe by accident (its select pass turned
  the width into a `select`, which the load rejects); a branch on an
  unmodelled value forms no select. The meet now drops a slot whose widths
  disagree. No fixture view, Clarc line or GoodLinks line changes.

- **FIXED (soundness): a join kept the flags after dropping their
  width.** The same defect for NZCV: `cmp x8, #1` on one path and
  `cmp w8, #1` on the other, with x8 = 0x80000000, leave equal flags
  values (the constant fits both widths) and different widths. The meet
  dropped the width, and `flagCondition` reads an absent width as 64 bits,
  so `b.lt` after the join rendered `if (0)`: the 32-bit compare
  overflows and takes the branch (native `f(0) = 1`). The meet now drops
  flags whose width it dropped (`flags_width_join`, control
  `flags_width_agree`). No fixture view, Clarc line or GoodLinks line
  changes.

- **Not a defect (was OPEN): an entry-seeded stack argument has no
  width.** The entry seeds only stack locations whose argument is eight
  bytes (`objcArgumentLocations`, since `ed4f157`), so no narrower slot is
  seeded, and a load at a packed argument's slot reads unknown
  (`objc_packed_stack.m`'s callees render `return ?`). The width defect
  was on the caller's side; see 2026-10-22.

## 2026-10-15: call results an indirect call takes

- **FIXED (correctness): a result an unresolved indirect call took
  rendered at the indirect call.** Counting a call result's uses (which
  decides whether it is bound as `let rN` where it is computed) skipped
  calls with no name, but the pass that hides a consumed result's own
  statement did not. A result kept in a callee-saved register and handed
  to a `blr` the decompiler cannot resolve was neither bound nor shown
  where it ran, and its call was spelled inside the indirect call's
  recovered arguments: `render_effect()` and then
  `indirect_call(?, recovered_args: [render_helper()])` for a helper that
  runs first (`render_order.s`). Nameless calls now count their
  arguments as uses. No fixture view changes; on Clarc and GoodLinks the
  change binds results that indirect calls take (a metadata accessor
  spelled in five indirect calls is one `let`), which renumbers later
  bindings: 2,472 and 12,647 changed lines, every one a new binding, a
  reference to one, or a renumbered binding.

- **FIXED (completeness): a bound call dropped its `self`.** A call whose
  result is bound (`let r0 = …`, because it is used across another call or
  its indirect result is read by word) rendered from the call's arguments
  alone, while the same call as a statement prints `self:`:
  `let r0 = RenderOrder.Widget.count.getter()` with the note
  `self=arg0`. Both binding paths now name `self` as the statement does
  (`render_order.s` `boundSelf`, `boundself.swift` at -O). No fixture
  view changes beyond the new probes; Clarc and GoodLinks change at 881
  and 1,557 lines, each a bound call gaining its `self:`.

- **FIXED (soundness): a static member of a value type rendered a
  `self`.** The self rule printed x20 for any Swift call where x20 was
  written since the last call. A static member of a struct or enum
  receives a thin metatype, which occupies no register, so x20 there is
  the caller's scratch: `static Swift.Array._allocateBufferUninitialized(
  self: 256, 256)` (a copy of the count), `static SwiftUI.Edge.Set.all.getter(
  self: SwiftUI.Color.init(…))`. The rule now declines `self` for a static
  member whose owner (the longest dotted prefix of its name) the class
  index proves a struct or enum; a class's static member keeps its
  metatype `self`. 116 Clarc lines and 255 GoodLinks lines drop such a
  `self` (`Edge.Set`, `String`, `Alignment`, `Array`, `Locale`, `URL`,
  `Date`, result builders, `Selector.==`, …), and nothing else changes.
  The owner is the member's own context, not the longest value-type
  prefix of its name: a class nested in a struct (`BoxA.Holder`) keeps
  its static members' `self`, and a struct declared in an extension is
  found by its extension spelling (`(extension in Dispatch):
  __C.OS_dispatch_queue.Attributes`, 2 more lines).
  A value type's initializer receives a thin metatype too, and rendered
  the same kind of `self`: `SwiftUI.EdgeInsets.init(self:
  static SwiftUI.Edge.Set.vertical.getter(…), …)`, `SwiftUI.State.init(self:
  type metadata for Swift.Bool, …)`, and in `sample.debug`
  `String.init(_builtinStringLiteral:…)` with `self=local_50`. Initializers
  of proven value types now decline it as well (128 Clarc and 130
  GoodLinks lines, every one a struct's `init`).
  Compiler-generated helpers have no `self` in their convention either
  (metadata and witness-table accessors take x0 and up, outlined copies
  and destroys take addresses), yet the listing and JSON noted one when
  x20 was fresh: `self=arg0` on a lazy protocol witness table accessor,
  ten such notes across six fixtures. They now decline it; a `merged`
  method is still a method and keeps its `self`.
  A C typedef that the importer makes a struct (`os_log_type_t`) is
  mangled as a typealias, so the class index had no evidence it is a value
  type and its static members kept a scratch `self` (48 Clarc calls such as
  `static (extension in os):__C.os_log_type_t.info.getter(self: …)`). An
  extension of a `__C` typealias now counts as value-type evidence: Swift
  extends only nominal types.

- **FIXED (completeness): a call spelled inside its use dropped its
  `self`.** A call whose result has one use renders inside that use
  (`return f(…)`, an argument), and that spelling printed the arguments
  alone: `return RenderOrder.Widget.count.getter()` for a getter called
  with self = arg0. The self rule (including the thin-metatype, helper
  and typedef declines above) is now decided once per call, and the
  statement, the binding and the inline spelling all render it. Every
  changed line in the fixtures (126), Clarc (805) and GoodLinks (1,460)
  differs from before only by added `self:` arguments.

## 2026-10-20: fixpoint visiting order

- **FIXED (completeness): a block ran before any of its predecessors had,
  from an empty state.** The tracer's worklist starts with every block in
  address order, and a block whose predecessors had not run met nothing:
  it started from "nothing known" rather than unconstrained, and facts
  arrived only once a predecessor ran. Entry states then grew after they
  shrank. In a loop that rotates values between registers (x25 and x28 in
  a 39-block GoodLinks function) the "nothing known" state chased the real
  one around the cycle and the fixpoint never settled
  (`values.fixpoint-cap`): the function claimed nothing and its calls
  rendered `()`. Elsewhere the empty state became a consistent but worse
  fixpoint: a loop header lost a register its body ran too early to see,
  so `Reconstruction.nestedLabelledContinue` (-O) rendered `if (x1 <ᵁ 2)`
  for `if ((0 <= arg1) && (arg1 < 2))`.

  A block the entry or a block without predecessors (a landing pad) reaches
  over modelled edges now waits until a predecessor has run. A block no
  modelled edge reaches can run only through an edge the CFG cannot follow
  (an unresolved `br`), so it starts from nothing every time, like a
  landing pad; letting it wait claimed the direct path's value at the join
  it shares with that edge. `fixpoint_order.s` holds the reduced rotation
  (`unsettled`), the hidden-edge cycle (`unmodelledLoop`) and a block
  reached only through the hidden edge whose successor uses what it sets
  (`handlerTail`), each checked against native execution.

  Blast radius (against HEAD, after the renderer fixes of 2026-10-15 that
  this change exposed): two -O fixture views (the loop conditions above);
  269 Clarc functions and 1,087 GoodLinks functions change. Every change
  was checked: recovered arguments where calls rendered `()`, decoded
  string literals, new bindings and the renumbering they cause, resolved
  vtable calls (`self.method()` for an indirect call), resolved casts, and
  an async return proven through x22. No function loses a value or a call:
  the only tokens that disappear are unknowns respelled (`/* unresolved
  call @ … */ ?` as `?`), string words now decoded, and calls bound once
  instead of re-spelled.

## 2026-10-21: the callee as a typed fact (IR step 1)

- **FIXED (hazard): a note appended to a call's annotation could read as
  its callee.** Every consumer re-parsed the callee name from the
  annotation (`calleeName(of:)`, about 25 sites), so any new note whose text
  did not start with a deny-listed prefix became a callee name wherever it
  came first. `Instruction.callee` now holds the name of a call's or
  branch's target, fixed where the target is named (decode, the Capstone
  merge, the call-target and resolved-indirect passes) and kept through the
  rebuilds that only append notes (enrichment, the `return ?` note, the
  throw split, CallGraph's slimming); `calleeName(of:)` reads it for calls
  and branches. `calleeFactsMatchTheirAnnotationsOnTheFixturesIfPresent`
  checks that the fact still equals what the annotation parses to; with
  `args(` dropped from the deny-list it reports 31 calls, and HEAD's views
  change on 15 fixtures while the fact build's do not.
  Output is unchanged: every fixture view, Clarc `--pseudo`, GoodLinks
  `--pseudo` and GoodLinks `xrefs --unreferenced` are byte-identical.
  Release A/B on Clarc, three alternating rounds: instructions retired
  325.3 G against 300.0 G median (-7.8%). The field costs memory: GoodLinks
  `xrefs` peak footprint 280 MB against 294 MB (+5%), after the fact was
  made to share the annotation's or resolver's string rather than copy it
  (+30 MB before).

## 2026-10-21: exits and bindings as typed facts (IR step 1)

- **FIXED (soundness): a string literal in a call's arguments could
  become the function's return.** Notes are separated by two spaces, the
  rendered arguments are a note, and the renderers split the whole
  annotation at every two spaces, literals included. The first piece
  starting `return ` was the statement, so an embedded script with an
  indented `return` line printed that piece as a `return` and the call
  disappeared; a literal holding `then throw ?` added a `throw ?`; a
  bound call or a returned call whose literal had a double space was cut
  there. Exits, bindings and the throw after a statement are now facts on
  `Instruction` (`exit`: `.normal(value?)`, `.throw(error)`,
  `.unclassified`; `binding`; `thenThrows`), written where enrichment
  appends the matching note and read by the pseudo statement and the
  structurer instead of the text. `notetext.swift` reduces each shape;
  `literalsThatReadAsNotesStayInsideTheirStatementsIfPresent` pins the
  true statements, and `exitFactsMatchTheirAnnotationsOnTheFixturesIfPresent`
  checks every fact against its note, read with literals kept whole.
  Blast radius: no other fixture view changes. Clarc changes at 3 sites
  (a fabricated return in place of an append of an embedded script, and
  two bindings cut at a label's double space), GoodLinks at 5 (two
  fabricated returns from embedded scripts, one printed once per call
  carrying the literal, five times in all; a format-string return and two
  bindings cut short). GoodLinks `xrefs --unreferenced` is unchanged.
  Release A/B, three alternating rounds, instructions retired: Clarc
  `--pseudo` 302.3 G against 294.0 G median (-2.7%), peak footprint
  67.5 MB against 67.8 MB; GoodLinks `--pseudo` 1266.3 G against
  1237.2 G (-2.3%, measured before the facts were boxed). The facts share
  one optional box, so an instruction without any pays one pointer.
- **OPEN (soundness): the statement notes still read from text.** The same
  split still finds field writes (`self.x = …`), `self = …`, `yield …`,
  the executor hop and `await=` in a literal: a call `emit("a  self.x = 1")`
  renders `self.x = 1")`, and `emit("a  await=r9")` renders
  `let r9") = await emit(…)`. Moving those notes to facts the same way
  closes it. *FIXED 2026-10-22, below.*

## 2026-10-22: Objective-C stack arguments

- **FIXED (soundness): a packed Objective-C stack argument claimed its
  neighbour's bytes.** Apple arm64 packs stack arguments to their own
  alignment, so after six int arguments in x2-x7 the seventh is at sp+0
  and the eighth at sp+4, and at -O clang merges the two stores into one
  (`mov x8, #7; movk x8, #8, lsl #32; str x8, [sp]`). A send read each
  stack argument from a whole eight-byte slot: `[p a:1 … g:7 h:8]`
  rendered `g:0x800000007`. Without a signature it also took one slot per
  argument, so a 16-byte struct argument's second word became the next
  argument (`g:7 h:9`, true h 8). The call-site snapshot now records the
  width of each slot's store, up to the register save area. A send with a
  signature takes a stack argument only from a store that covers it and
  no other argument (`ObjCArgumentABI.storeHoldsOnlyArgument`); one
  without takes one slot per argument only where the area holds exactly
  one aligned store per argument. `objc_packed_stack.m` (-O0 and -O2)
  holds each shape, typed and untyped. Blast radius: no other fixture
  view changes; Clarc and GoodLinks (`--pseudo`, `--structured`) and
  GoodLinks `xrefs --unreferenced` are unchanged. On Terminal (an
  Objective-C system app) 14 untyped sends change, each a wrong render
  declined: 13 `+[NSEvent keyEventWithType:…]` sends printed the packed
  `isARepeat` and key code, or their merged constant, as `characters:`,
  and one of Terminal's own sends read an argument from a packed slot.
  Five calls bound only for that misread use are no longer bound.
- **FIXED (soundness): an untyped send named floating-point arguments'
  neighbours wrongly.** With no signature the explicit arguments are laid
  across x2-x7 by colon position, but a double, point, size or rect
  travels in v registers: `[o put:1.5 at:7]` rendered `put:7 at:?`, and
  Terminal's `keyEventWithType:location:modifierFlags:timestamp:…` sends
  rendered the modifier flags as `location:`. A send with no signature
  now declines its explicit arguments when a value is left in v0-v7 for
  it: written in its block after the previous call and not then stored to
  memory (a stored register was a copy temporary: a double copied through
  d0, a struct zeroed with `stp q0, q0`). `objc_untyped_float.m` (-O0 and
  -O2) holds the shapes, with witnesses for each limit
  (`anUntypedSendPassingAFloatDeclinesItsArgumentsIfPresent`). On five
  apps 408 sends decline (Clarc 37, GoodLinks 185, Terminal 155, TextEdit
  15, Chess 16); at least 23 of them are integer-only selectors
  (`valueForKey:`, `objectAtIndex:`, `setFont:`), sound but lost, from a v
  register left set for something else; the rest pass a float, point,
  size or rect the integer layout misread. No other fixture view changes.
- **OPEN (soundness): a floating-point argument passed through untouched
  still misreads.** `putPassed(o, x)` at -O2 sends `put:x at:7` with x
  still in d0 from its own entry, so nothing before the send writes a v
  register and the integer layout renders `put:7 at:?`. A signature
  source for SDK selectors (the system frameworks' method type encodings
  in the dyld cache) closes it. Since 2026-10-24 a method's own float
  arguments count (below); a C function or block has no signature to show
  them, so `putPassed` itself is unchanged.
- **FIXED (correctness): a call's stack arguments ran into the register
  save area.** The snapshot reads the words stored upward from sp until
  one is missing, and the prologue's `stp x29, x30, [sp, #…]` stores two
  more, so a call with no stack arguments could look like it had some,
  and a variadic count could read the frame record as arguments. The
  snapshot now stops at the save slots, as the escape at a call does
  (`stackArgumentsStopAtTheRegisterSaveArea`). Done first, it pushed
  known-arity calls whose only "values" were the frame record into the
  `memmove()` defect below (Clarc: 19; GoodLinks: 32); after that fix no
  fixture view and no Clarc or GoodLinks line changes.
- **FIXED (soundness): a known-arity call with nothing tracked rendered
  as taking no arguments.** The tracer records no call site with nothing
  in it, and the known-C-arity layout that pads unknown operands to `?`
  runs only on recorded sites, so `memmove` whose operands were all loaded
  through an unknown pointer read `memmove()`. The pass that already
  inserted an empty site for a Swift callee whose scalar signature proves
  its arity now does so for a runtime entry point of known C arity
  (`untracked_args.c`, -O0 and -O2:
  `untrackedOperandsKeepTheCalleesKnownArityIfPresent`). A resolved call
  without a site also rendered its result as `/* unresolved call @ … */
  ?` wherever it was used; a `swift_bridgeObjectRetain` of an unknown
  value now reads `?`. Blast radius: the pseudo and structured views of
  8 fixtures gain the `?` operands of `memcpy`, `memmove` or
  `objc_sync_exit` (14 pseudo lines), and 14 listings and their JSON the
  matching `args(?…)` notes. Clarc `--pseudo` changes 227
  lines and GoodLinks 2,091, every one of them padding, the dropped
  marker, or (7 on GoodLinks) a setter call printed as the call rather
  than `self.Node = /* unresolved call @ … */ ?`, the assignment form
  being kept for a known value. `memmove()`, `memcpy()` and `free()` go
  from 175 to 0 on Clarc and from 902 to 0 on GoodLinks.
- **OPEN (soundness): other calls with nothing tracked still render
  `()`.** A runtime function missing from `knownCArity`
  (`swift_weakLoadStrong()`: 55 on Clarc, 1,821 on GoodLinks; that one and
  17 more are in the table since 2026-10-23, below), a Swift
  callee whose signature has a non-scalar parameter, which
  `swiftCallArgumentSlots` does not lay out (`Swift.String.append()`: 51
  and 308; since 2026-10-23 only a value type's instance method or a
  parameter outside the String and `inout` footprints), and a C callee of unknown arity (`bzero()`, `malloc()`) each
  print only the operands that were tracked, so nothing reads as nothing.
  Since 2026-10-24 `bzero`, `malloc`, `objc_enumerationMutation`,
  `CFRelease`, `dispatch_async`, `dispatch_sync`, `swift_getKeyPath`,
  `swift_slowAlloc`, `swift_once` and `swift_slowDealloc` are in the table
  too (below), and since 2026-10-24 every C function the SDK declares
  takes its declared parameters (below); an undeclared C callee, or a
  variadic one, still prints only what was tracked.

## 2026-10-22: findings from a read-only audit

- **FIXED (soundness): a tail call resolved into its own function rendered
  as a loop.** `annotateIndirectControlFlowTargets` wrote a resolved `br`
  target into `branchTarget`; when the target was inside the function,
  every later CFG gained an edge the call never takes. `countdown(n)`,
  which tail-calls itself through self's vtable (`br x1`), rendered
  `while (arg0 >= 1) { self.countdown((arg0 - 1)) }`, an infinite loop on
  an unchanging `arg0`. A resolved `br` to an address inside the function
  now keeps its callee and no target, so it stays a tail call
  (`selftail.swift`, -O: `aTailCallResolvedIntoItsOwnFunctionIsNoLoopIfPresent`).
  Blast radius: no other fixture view and no line of Clarc, GoodLinks,
  Terminal, TextEdit or Chess changes. The tail call's result is not yet
  returned (`else { self.countdown((arg0 - 1)) }`): OPEN below.
- **FIXED (853543f, was OPEN, completeness): a resolved indirect tail call
  did not forward its result.** `scalarTailReturnSites` took only direct
  branches outside the function, so `countdown`'s tail call through the
  vtable rendered as a bare call rather than `return
  self.countdown((arg0 - 1))`.
- **FIXED (fedffd0, was OPEN, soundness): an indirect call named from a
  writable pointer's initial value.** `long (*next)(long) = countdown; … return next(n - 1)`
  names its target `countdown` from the initial contents of `next` in
  `__DATA,__data`, which the program may overwrite before the call.
- **FIXED (soundness): the loop-body pass missed what only the back edge
  brings.** `resolveLoopInductions` re-transferred the body from the
  loop's entry state, so a fact that reaches the header only over the
  back edge never held on its lap: an address escaped at the end of the
  body (`lateEscape`: `g = &i` after `i++`, so the next lap's `poke()`
  may write `i`) and a pointer slot that changes after the first lap
  (`staleEntryPointer`: `p` points at `j` only on the first lap). Both
  rendered five-lap loops, `var i = 0 … i += 1` and `j += 100`, where
  native execution runs two laps and returns 102 and 202. The lap is now
  seeded from the converged header state, taken before any loop's names
  are written back, with the candidates' placeholders on top; initial
  values still come from the entry (`loopescape.c`, -O0:
  `aLoopBodyPassSeedsFromTheConvergedHeaderIfPresent`). The loops now
  render without those claims. Blast radius: no other fixture view and no
  line of Clarc, GoodLinks, Terminal, TextEdit or Chess changes.

## 2026-10-22: every note a renderer reads as a typed fact (IR step 1)

- **FIXED (soundness): a literal's text could become a statement, a call
  marker or a cut condition.** The pseudo statement still split the
  annotation at every two spaces, literals included, and took the first
  piece that read as a field write, `self = …`, a yield or an executor
  hop; `await=` and `jump=` were found the same way, `dispatch=self` by a
  search of the whole annotation, and the structurer split for `cond:`,
  the loop notes, a field read and `self = `. Measured on
  `notetext.swift` (-O) against the pre-change release build: each
  `emit("a  <note>")` printed the piece (`self.x = 1")`,
  `await hop_to_executor(MainActor)")`, …) in place of its call,
  `emit("a  await=r9")` printed `let r9") = await NoteText.emit(…)`,
  `emit("a  dispatch=self")` printed `self.emit(…)` and `xrefs` called
  its edge a dispatch through self; a field write
  `self.count = NoteText.measure("ok`, a jump
  `indirect_jump(NoteText.handler("a)` and a condition
  `if ((arg0 == "a) {` were cut at their literal's double space. On an
  earlier build of the fixture the literal's own `add` carried it in a
  `literal pool for:` note and printed it a second time.
  `Instruction.facts` now carries all of them beside their notes
  (`statement`, `awaitBinding`, `indirectJumpTarget`, `condition`,
  `loopUpdates`, `loopInitializations`, `fieldRead`, `isSelfDispatch`,
  with the exit, binding and `thenThrows` of 2026-10-21), and no renderer
  reads the annotation for a note. Blast radius: every other fixture view
  (structured, pseudo, listing, JSON) is byte-identical, and so are Clarc
  `--pseudo`, `--structured`, the listing and `--json`, and GoodLinks
  `--pseudo`, `--structured` and `xrefs --unreferenced` (text and JSON):
  neither app has one of these shapes.
  Release A/B against 39a4aa5, three alternating rounds, instructions
  retired median: Clarc `--pseudo` 293.5 G against 286.0 G (-2.6%),
  peak footprint 68.5 MB against 68.0 MB; GoodLinks `--pseudo` 1223.3 G
  against 1210.4 G (-1.1%), `--structured` 1445.7 G against 1360.1 G
  (-5.9%, peak 248.2 MB against 237.7 MB): the structurer no longer
  splits annotations. GoodLinks `xrefs --unreferenced` shows no measurable
  change: two A/B sets gave +1.6% and -1.3%, and one binary's rounds span
  1121 G to 1158 G. Reading emptiness field by field instead of comparing
  with `Facts()` measured 1127.2 G against 1121.9 G and was not kept.
- **FIXED (soundness): a pair store over two fields that was no tuple took
  the first register's value.** `fieldWrite` fell through to the
  single-value form, so `objc_pair_stores.m`'s `packC:` (`stp x2, x9,
  [x0, #0x18]`, x9 unknown) rendered `self->{_c, _d} = arg0`. A pair
  store over several fields that is no tuple shows no value:
  `self->{_c, _d} = …`. Blast radius: that one fixture line; release
  `disasm --pseudo` of TextEdit, Chess, Clarc and GoodLinks is
  byte-identical, and Terminal changes two lines: a two-int span's
  `-= 1` taken from one register now reads `= …`, and a four-int span
  zeroed by `stp q0, q0` reads `= …` where it read `= (0, 0)`.
- **FIXED (soundness): a pair store was a tuple of the fields it covered
  whatever its registers' boundaries.** `packE:f:` (`stp x2, x3, [x0,
  #0x8]` over a 12-byte struct ivar and an int) rendered
  `(self->_e, self->_f) = (arg0, arg1)`, though x2 is only `_e`'s first
  8 bytes. Each register must now fill one whole field, in order; the
  store reads `self->{_e, _f} = …`. Only that fixture line changes;
  release `disasm --pseudo` of the five apps is byte-identical.
- **FIXED (completeness): a pair store that started inside a field was
  dropped.** `SDPairParts setTail:b:` (`stp w2, w3, [x0, #0x10]` over the
  last four bytes of the 12-byte `_a` and all of `_b`) named no field, so
  the method printed nothing. A pair store that is no tuple of whole
  fields is now the tuple of what each register writes:
  `(self->_a[8..<12], self->_b) = ((arg0 & 0xffffffff), (arg1 &
  0xffffffff))`, and `packC:` reads `(self->_c, self->_d) = (arg0, …)`.
  Only one statement per instruction renders, so the two writes stay one
  tuple. A forwarded value in a register is named at the register's
  width (`self.front[0..<16]`, not `self.front`). Blast radius: those
  fixture stores; release `disasm --pseudo` changes four Terminal lines,
  each a two-int span now a tuple per register, and nothing else.
- **FIXED (completeness): an all-zero store over several fields read as
  its words.** A zeroed vector register stored over a span rendered
  `self->{_v, _u, _t, _s} = (0, 0)` (`SDPairZeros clear`), or `= …` for a
  pair of them (Terminal's deleteAllCharacters). Every stored byte zero is
  `= 0` now (`isAllZero`). Release `disasm --pseudo`: six Terminal lines
  and one Clarc line, each such a span; nothing else changes.
- **FIXED (soundness): a value forwarded from this object's fields was
  named by the field at its offset.** With no load to fix its width,
  `.selfFieldValue(offset)` named the field there whatever the store's
  width: `objc_pair_stores.m`'s `SDPairZeros clear` stored one zeroed q0
  over `_v`..`_s` and then over `_w`..`_z`, and the second read
  `self->{_w, _x, _y, _z} = self->_v`. `fieldWrite` now looks the value
  up at the store's width: `self->{_v, _u, _t, _s}`. Only that fixture
  line changes; the five apps are byte-identical.
- **FIXED (completeness): a store into two Swift fields at once was noted
  but never printed.** `fieldWriteStatement` made every field write a
  statement but a tuple of Swift fields: `fieldwrites.swift`'s
  `FieldPQ.set` (`stp x0, x1, [x20]`, -O) noted
  `(self.p, self.q) = (arg0, arg1)` and its pseudo view read
  `// no non-runtime calls`. A tuple is a statement in both syntaxes now;
  a tuple is written only when each register fills one whole field
  (78bd747), and a pair store that is no tuple names each register's own
  target (cf68ec0), so printing it claims no more than the note did.
  Blast radius: two libFieldWrites functions (`FieldPQ.set`, and
  `FieldWrites.init`'s three pair stores of one zeroed q0); release
  `disasm --pseudo` of the five apps is byte-identical.
- **FIXED (soundness, see "field writes that do not fill one field"
  below): a String stored to a field rendered as one word.**


## 2026-10-23: malformed Objective-C type encodings

- **FIXED (robustness): a corrupt ivar type encoding trapped `disasm`.**
  `ObjCTypeLayoutDecoder`, which sizes an ivar so its field-map range can
  be bounds-checked, did unchecked arithmetic and unbounded recursion on a
  string read from the file. A copy of `libObjCNonselfOutgoing.dylib` with
  `SDNonselfCaller._target`'s type (`@"SDNonselfTarget"`, the last string
  in `__objc_methtype`) overwritten in place passes the preflight, whose
  ivar check is only that the type points into `__objc_methtype`. Six
  payloads each died by SIGTRAP (exit 133): a 25-digit array count
  (`parseNumber`), `[4611686018427387904q]` (count times size), a 19-digit
  bitfield width, `j[…]` (complex doubling), field alignment and field
  addition in an aggregate. `[9223372036854775807c]` decoded to `Int.max`
  bytes and trapped one step later, in `FieldMap`'s
  `offset + bytes <= instanceSize`. A run of 1,000 to 12,000 `^`, or 4,000
  nested `[1`, overflowed the stack (SIGBUS, exit 138): the debug build's
  `parseType` frame is 2.2 KB and the 512 KB cooperative-thread stack ran
  out at 236 levels. Every size, count and alignment step is now checked
  and nesting stops at `maximumNestingDepth` (32); either one declines the
  whole encoding, so the ivar gets no field range and its accesses keep
  their raw offsets. The deepest real encoding among 197,428
  `__objc_methtype` strings in 889 binaries (400 under /Applications, 489
  in Xcode) nests 11 levels. `FieldMap` compares `bytes` with the room
  left, which cannot overflow. All ten payloads now exit 0 from `disasm`
  and `dump`, and `objc` still exits 0 on the six overflow payloads
  (`declinesObjCTypeLayoutsWhoseSizeOverflows`,
  `declinesObjCTypeLayoutsNestedPastTheBound`,
  `dropsAnIvarFieldLargerThanTheInstance`,
  `corruptIvarTypeEncodingsDeclineTheirFieldIfPresent`, which builds the
  corrupt copies from the fixture's bytes). Blast radius: every fixture's
  structured, pseudo, listing and JSON views are byte-identical.
- **OPEN (robustness): a deeply nested type encoding still overflows the
  stack in `objc`.** The same `^` and `[1` payloads kill `objc` (SIGBUS,
  exit 138) inside ObjCDump's own `ObjCTypeDecoder._decode` /
  `_decodePointer` recursion, which renders the header text and is not
  ours. A fix either bounds the nesting before handing an encoding to
  ObjCDump (and prints it undecoded) or patches the dependency.

## 2026-10-23: 64-bit segment fields past Int.max

- **FIXED (robustness, below): a segment `vmaddr` or `vmsize` at or above
  2^63 trapped.** MachOKit's `SegmentCommand64.virtualMemoryAddress` and
  `virtualMemorySize` convert the raw `UInt64` with a trapping
  `numericCast` ("Not enough bits to represent the passed value",
  SIGTRAP, exit 133). Setting each 64-bit segment and section field of
  `libObjCNonselfOutgoing.dylib` to 2^63 and to 2^64 - 1 (104 copies)
  gave 96 clean rejections and 8 traps from `disasm`: `vmsize` of
  `__TEXT` (both values), `__DATA_CONST` and `__DATA` (2^63) and
  `__LINKEDIT`'s `vmaddr` and `vmsize` (both values). They pass the
  preflight because its containment check adds `vmaddr + vmsize` with
  wrapping and `__LINKEDIT` has no sections to check; the traps are in
  `MachOFile._fileOffset` (from `Disassembler.sectionBytes`) and
  `_fileSliceForLinkEditData` (from `dyldChainedFixups`). A sum past
  `Int.max` of two fields below 2^63 does not trap. A real arm64e kernel
  hits the same trap: `objc` on
  `/System/Library/Kernels/kernel.release.t6000` (`__TEXT` at
  0xfffffe0007004000) dies in our `FileBackedRanges.init`, while `dump`
  exits 0 with "No Swift metadata found". The obvious fix, a preflight
  rejection of a segment field above `Int.max`, turns that `dump` into an
  error too. Fixed between the two: `BinaryLoader.load` fails such an image
  with an error naming the segment, field and value
  (`requireSignedAddresses`), and `dump` and `swift-version`, which read it
  without address arithmetic, opt out (`allowingWideAddresses`). Over the
  104 corrupted copies every entry point now exits cleanly (the 10 that
  trapped are rejected by the seven commands that did address arithmetic
  and still read by `dump` and `swift-version`); on the kernel, `objc` and
  `disasm` print the error and `dump` and `swift-version` exit 0. `layout`
  now also rejects the two `__LINKEDIT.vmsize` copies it used to read.

## 2026-10-23: callee-saved registers through calls

- **FIXED (soundness): a caller kept a callee-saved register across a call
  that reaches a clobber one call down.** The register summaries judged
  each body alone, so a function that never writes x19 itself but calls
  or tail-branches to an outliner fragment that does (`mov x19, x1; ret`)
  was summarised as preserving x19, and its caller rendered `return arg0`
  where native execution returns arg1 (`preserve_calls.s`: `nested`,
  `tail`). A summary now carries what a call does to the caller's
  callee-saved registers (`CalleeEffect`), and `closeOverCalls` rebuilds
  every summary from its callees' effects until nothing changes. Only a
  definite clobber travels (a register the body never stores, minus x21,
  Swift's error register, which each call site models already); a
  register saved somewhere stays clobbered for direct callers only.
  Filtered runs decode up to 512 further callees, a level at a time, so
  they agree with whole-image runs.
- **FIXED (soundness): an outlined epilogue's reload counted as a
  clobber.** Read as an unknown clobber, the reload lost `self` in 158
  GoodLinks `--pseudo` lines: an assertion path such as
  `-[DDAbstractDatabaseLogger saveThreshold]`'s `sub_100d70128` saves x19
  to x24, calls the fragment `sub_1001664d4` (`mov x19, x1; mov x20, x0`)
  and leaves through `ldp x29, x30, [sp, #0x30]; b 0x10016f85c`, whose
  `ldp x20, x19, [sp, #0x20]; …; b objc_release` hands back what it saved.
  A load from entry sp or above that no write since entry can reach is
  now `incoming(k)`, a register every exit reloads that way is a reload,
  and a caller evaluates it against its own frame at the call or tail
  branch. A rebuilt summary replaces the first one rather than merging
  with it, so a function that writes x19 itself before its outlined
  epilogue is not left clobbering it. The reload restores only what the
  slot holds: `forged` (a slot holding arg1), `scribbled` (half the slot
  written first, on one path) and `smudged` (written through an address
  computed from sp) return arg1 natively and render `return ?`; on
  origin/dev all three rendered `return arg0`. A closure stopped by its
  cap now claims nothing for every caller of an unsettled function as
  well, and a body that cannot be summarised again claims nothing. Blast
  radius against origin/dev (`disasm --pseudo` and `--structured`):
  `libPreserveCalls` only among the fixtures (six lines, each matching
  native execution); three GoodLinks lines, `?` to `arg0` in
  `-[GDTCORTransport initWithMappingID:transformers:target:]`,
  `sendDataEvent:onComplete:` and `sendEvent:onComplete:`, whose helpers
  write x19 themselves and leave through the outlined epilogue at
  0x10016f87c; Clarc, Terminal, TextEdit, Chess and GoodLinks
  `xrefs --unreferenced` byte-identical. Clarc `disasm --pseudo`, release,
  three alternating rounds: instructions retired 287.7G to 285.6G (run
  spread 1.1%), wall 22.9 s both, peak footprint 66.9 MB to 70.7 MB
  (medians).
- **OPEN (assumption): x21 is not carried through calls.** A fragment that
  writes x21 changes it only for its direct callers' summaries. Sound
  while compiled code saves x21 in every function whose outlined code
  writes it; a chain of fragments writing x21 would go unseen.

## 2026-10-23: struct arguments of typed Objective-C sends

- **FIXED (completeness): a typed send with a struct argument rendered
  every argument `?`.** `ObjCArgumentABI.locations` declined any signature
  with a struct in it, so `[self place:p flags:7 stamp:2.5]` (a CGPoint
  first) read `[self place:? flags:? stamp:?]`. Struct arguments are now
  laid out the way Apple's clang lowers them, checked against its output
  for each shape: an HFA (one to four members of one floating type,
  nested structs flattened, so a CGRect is four doubles) takes one v
  register per member while enough remain; any other struct of 16 bytes
  or less takes one or two x registers; a larger one is passed as the
  address of a copy, like a pointer. A struct that does not fit goes on
  the stack (an HFA at its member alignment, any other struct eight-byte
  aligned in whole words) and closes its bank: no later floating
  argument takes a v register after an HFA spills, and no later argument
  takes an x register after a small struct spills. The struct itself
  still renders `?`. Every stack argument's start, struct ones included,
  bounds a merged store (`stackArgumentStarts`), so `count:7` followed by
  a one-float HFA at sp+4, stored together at -O as one eight-byte
  `str`, reads `count:?`. Unions, arrays, bitfields, long double,
  128-bit, complex and vector members, opaque or empty structs and
  quoted field names still decline the whole layout. A method that takes
  a struct still seeds none of its own arguments
  (`objcArgumentLocations`): with them seeded, the untyped layout below
  named pass-through values one argument off (Terminal's `[super
  initWithContentRect:arg1 styleMask:arg2 backing:arg3 defer:?]`, Chess
  the same). Fixture `objc_aggregate_args.m` (-O0 and -O2) and
  `keyEventLayoutPlacesEveryArgumentAfterTheLocation` (NSEvent's
  `keyEventWithType:…`, CGPoint in d0-d1, the BOOL and key code packed
  at sp+0 and sp+2). Blast radius: no other fixture view, listing or
  JSON changes. `--pseudo`: Terminal 98 changed hunks, every one a typed
  send to self or a typed ivar gaining arguments after a struct
  (`[self drawAttributedStringsToScreen:? inRect:? selectedTextRanges:0
  selectionColor:0]`, `[self ttSendMouseButton:0 atPoint:?
  modifierFlags:[arg0 modifierFlags]]`), plus 101 lines that only
  renumber `let rN` because a result is now used as an argument; TextEdit
  3 sends (`[self textViewAtIndex:0 documentSize:?]`); Chess none.
- **FIXED (soundness, see "untyped sends of struct-taking selectors"
  below): an untyped send of a selector that takes a struct was laid out
  by colon position.** The entry seeding of struct-taking methods is still
  off (the guard in `objcArgumentLocations`); see "Entry seeding of
  struct-taking methods" below for what still blocks it.
- **FIXED (soundness): `ObjCTypeLayoutDecoder` truncated a struct at a
  pointer to an empty struct.** `parseAggregate` returned for an empty
  definition (`{Opaque=}`) without consuming its `}`, so inside a struct
  it closed the outer struct early: `{S=^{Opaque=}q}` measured 8 bytes,
  not 16, and an ivar of that type claimed half its bytes. The closer is
  now consumed before the empty definition declines: 16, and
  `{S=^{Opaque=}c^{Other=}}` 24, as `NSGetSizeAndAlignment` measures them
  on this host. Every fixture view and release `disasm --pseudo` of the
  five apps are byte-identical.
- **FIXED (soundness): `ObjCTypeLayoutDecoder` measured `l`/`L` as 8
  bytes.** The runtime's `NSGetSizeAndAlignment` treats them as 32 bits
  on 64-bit platforms (LP64's `long` encodes as `q`), so an `l` ivar
  claimed four bytes of the next one. They are 4 bytes, aligned to 4:
  `{T=lL}` is 8, as `NSGetSizeAndAlignment` measures it. Every fixture
  view and release `disasm --pseudo` of the five apps are byte-identical.

## 2026-10-23: throws(Never) specializations

- **FIXED (6cca3c4) — a `then throw ?` note read as a branch's callee.**
  `parsedCalleeName` named the merged-throw `b` of the unspecialized
  `TypedThrowsNeverLib.transform` (-O) `then throw ?`, against its nil
  callee fact; `calleeFactsMatchTheirAnnotationsOnTheFixturesIfPresent`
  caught it once the fixture below existed. The note is now declined like
  `swift-exit=`. Every fixture view is byte-identical.
- **FIXED (the commit after 6cca3c4) — a specialization that binds its
  thrown type to `Swift.Never` read as throwing.** The demangler prints a
  specialization as the declaration it specializes, so
  `generic specialization <serialized, (), Swift.Never> of
  Unicode.Scalar.withUTF8CodeUnits<A, B where B: Error>(…) throws(B) -> A`
  read `throws(B)`, and both of its specializations in `sample.debug` (the
  function and its closure #1) rendered
  `machine_return() /* unresolved Swift success/error exit */` on their one
  exit. No value of `Never` exists, so neither can throw. Their -Onone
  bodies keep the generic function's x21 convention: they spill x21, call
  through `bl`/`blr`, test x21 with `cbz` (trapping otherwise) and reload
  it from the spill before `ret`, which no x21 proof follows (the -Onone
  `try` exit OPEN). `typedthrowsnever_lib.swift` (an -O library) and
  `typedthrowsnever.swift` (its -Onone client) reduce the shape: the client
  emits the library's serialized specializations of
  `transform<E: Error>(…) throws(E)` for `Never`, `ProbeError` and
  `any Error`. Built as one -O module, the `Never` specialization keeps x21
  in a callee-saved register and was already proven; the decline needs the
  -Onone lowering of a serialized specialization.

  `specializationBindsThrownTypeToNever`
  (`NeverThrowingSpecialization.swift`) reads the substitution list from
  the demangle tree of the function's own symbol. The list is positional
  over the canonical generic parameters of the specialized function's
  signature (`GenericSpecializationMangler::appendSubstitutions`), so the
  proof requires all of: the tree prints the analysed name; one `Tg`, `TG`,
  `TB` or `Ts` specialization (optionally under one function signature
  specialization) of a function or of a closure directly in one; a generic
  signature of one depth with no same-type, same-shape, pack or value
  requirement and as many parameters as substitutions; a thrown type that
  is a depth-0 parameter with its own `Swift.Error` conformance; and a
  substitution of exactly `Swift.Never`. Anything else keeps the throwing
  reading. `signatureThrows` replaces the text test in both renderers, the
  exit classifier (`throwsSignature`) and the machine-value contract. The
  structured view still names x21 `error`, because the body threads x21
  under the generic convention (`threadsSwiftError`).

  Blast radius: of 448 fixture views (112 binaries; structured, pseudo,
  listing, JSON), only `sample.debug` changes, in exactly the two
  specializations. The function's exit becomes
  `return generic specialization <…> of closure #1 (local_28, ?, ?, local_30, local_38)`:
  its result A travels through the x8 buffer it hands the closure (the
  existing indirect-result forwarding), so the call statement folds into
  the return. The closure's exit becomes `return ?`. In the new fixture the
  `Never` specialization's exit becomes `return (? + 1)` (the source returns
  `body(x) &+ 1`); the `ProbeError` and `any Error` controls are
  byte-identical and stay throwing. Clarc (`disasm --pseudo`) is
  byte-identical, and so is GoodLinks (`disasm --pseudo`): neither has a
  `Never` specialization.

  Not changed, because nothing shows an effect: the enrichment gate and the
  tail-call caller test still read the text. Switching either between the
  text and the new fact moves no test and no fixture view.
- **OPEN — a specialization's generic result type is read from the
  unspecialized signature.** `withUTF8CodeUnits`'s closure now renders
  `return ?` for a result `A` its specialization binds to `()`, and
  `swiftReturnRegister` reads the text `A`, not its substitution: a
  specialization returning a parameter bound to `Double` would look in an
  integer register. The substitution list that settles the thrown type
  settles this too. Non-throwing specializations have had the same reading
  all along. Its arguments are laid out from the substituted signature
  since 2026-10-24 ("a specialization's arguments", below); the result
  register still reads the printed type.
- **OPEN — a callee's `throws(Never)` specialization still reads as
  throwing.** `provablyDoesNotThrow` and the tail-call callee test work
  from the callee's printed name. Carrying the fact on the callee, as
  `Instruction.callee` carries its name, would let a caller keep its x21
  proofs across a call to one.

## 2026-10-23: calls through pointer slots and resolved tail calls

- **FIXED (soundness): a call through a writable function pointer was
  named from the pointer's initial value.** `long (*next)(long) =
  countdown;` puts `next` in `__DATA,__data` with a rebase to countdown,
  and `countdown` ends `adrp; ldr x1, [x8]; br x1`. The listing said
  `br x1 ; → countdown` and the pseudo view `countdown()`, but the program
  can store another function in `next` first. A bind is the same:
  `int (*hook)(const char *) = puts;` rendered `puts(?, puts)`.
  `ReferenceResolver.indirectCallTarget` now names a `.loaded` slot only
  when `holdsFixedPointer(at:)` holds: the slot's segment is read-only
  after fixups (`SG_READ_ONLY`, or `__DATA_CONST` or `__AUTH_CONST` by
  name, where GOTs and witness tables live), or, in a full dyld cache, a
  slot outside the image lies in a const or read-only mapping. The
  indirect-jump target applies the same rule, so the bind no longer
  prints `indirect_jump(puts)`. Fixture `writablepointer.c` (-O2) has
  both writable shapes and a `__DATA_CONST` control that stays `twice()`.
  Blast radius: every other fixture view (structured, pseudo, listing,
  JSON) is byte-identical. Clarc `disasm --pseudo` and
  `xrefs --unreferenced` are byte-identical. Terminal `disasm --pseudo`
  changes 12 call sites, all through one table of function pointers in
  `__DATA,__data` initialised to local wrappers (`[NSDate date]`,
  `NSFileManager` attributes, `NSUserDefaults boolForKey:`, `NSWorkspace`
  URL lookup); they now render `indirect_call(?, …)` or
  `indirect_jump(?)`. No `adrp; str [x, #off]` store to those slots was
  found in the filtered listings, so whether Terminal rewrites them is not
  proven either way: the slots are writable, and the name was their
  initial value. The full-cache mapping clause has no automated test.
- **FIXED (soundness): a value loaded from a writable bind rendered as
  the bound symbol.** `sanitizeValue` keeps any `.loaded` slot that
  `loadedName` names, and `loadedName` read binds in any section, so
  `writablepointer.c`'s `currentHook`, which passes what `hook` holds,
  rendered `keep(puts)`, though `silence` can store another function in
  `hook` first. `loadedName` now names a bind only where
  `holdsLoaderOwnedPointer(at:)` holds: the slot is read-only after fixups
  (`holdsFixedPointer`, as for calls), or it lies in a section only dyld
  and the Objective-C runtime write (`__objc_classrefs`,
  `__objc_superrefs`, `__objc_protorefs`, `__got`, `__auth_got`,
  `__la_symbol_ptr`, `__nl_symbol_ptr`). Selector references keep their
  own table. An image linked without `__DATA_CONST` keeps its GOT in the
  writable `__DATA`, and GoodLinks has its class references there, so the
  section rule is what keeps their receivers named: `writable_tables.m`
  (-O1, `-no_data_const`) pins `[NSUserDefaults standardUserDefaults]`
  and `keep(puts)` through a `__DATA,__got`. Now `currentHook` renders
  `keep()`. Blast radius: every other fixture view (structured, pseudo,
  listing, JSON) is byte-identical, and release `disasm --pseudo` of
  Terminal, TextEdit, Chess, Clarc and GoodLinks is byte-identical.
- **FIXED (diagnostics, see "slice names" below): an unfiltered plain
  listing of an arm64e-only fat binary with `--arch arm64` failed as a
  parser defect.**
- **FIXED (completeness): a resolved indirect tail call did not forward
  its result.** `selftail.swift` (-O): `countdown` ends `br x1` through
  self's vtable, resolved to `SelfTail.Counter.countdown` with no edge
  (277b543), and rendered `else { self.countdown((arg0 - 1)) }`, as if
  the call's result were dropped. `scalarTailReturnSites` accepted only a
  direct branch out of the function; it now also accepts a `br` whose
  callee the tracer named and which has no branch target, with the same
  caller and callee signature checks, so the view reads
  `return self.countdown((arg0 - 1))`. Blast radius: only the selftail
  fixture changes (that line in structured and pseudo, and the `br`'s
  note in the listing and JSON); Clarc and Terminal `disasm --pseudo`
  are byte-identical.
- **FIXED (determinism): `abi.argument-layout` probe events came out in
  hash order.** The argument-layout loop in `enrichCallArguments` walked
  the `sites` Dictionary, and each site records its event as it is laid
  out. `disasm libSample.dylib --pseudo --probe … --probe-filter
  event=abi.argument-layout` gave three different traces of 230 events in
  three processes, though the rendered output matched. The loop now walks
  the sites in address order, and the same three runs give one trace.
  `argumentLayoutProbeTracesAreIdenticalAcrossProcessesIfPresent`
  compares four processes. Rendered output does not change: every fixture
  view, and Clarc and Terminal `disasm --pseudo`, are byte-identical.

## 2026-10-23: floating values in vector registers and variadic slots

- **FIXED (soundness): a scalar read of a zeroed vector register took
  both lanes.** Clang and Swift make every floating zero with
  `movi v0.2d, #0`, which writes all 128 bits, and the tracer holds that
  as two eight-byte lanes. A read of `d0` took the whole pair: at -O0,
  `movi v0.2d, #0; str d0, [x8]` stored the pair into one eight-byte
  variadic slot, so `printf("%f|%d", 0.0, 1)` rendered
  `printf("%f|%d", (0, 0), 1)` and `stringWithFormat:@"%f", 0.0` rendered
  `(0, 0)`. A Double argument and a Double return read v0 whole as well:
  Swift `laneTakes(0)` rendered `laneTakes((0, 0))` and `return 0` rendered
  `return (0, 0)`, at -Onone and -O. A scalar view of a vector register
  (`ValueTracer.scalarView`) is now its low lane: a `d` operand, every
  call's floating arguments (each reader lays out a scalar `f`, `d`,
  Double, Float or CGFloat) and the floating return. A view narrower than
  a lane keeps a constant lane's low bits and declines anything else.
  `vectorlane.m` (-O0, and -O2 where clang stores `xzr` instead) and
  `vectorlane.swift` (-Onone and -O) hold the shapes. Blast radius: one
  fixture call changes, `sample.debug`'s `Point(x: 0, y: 0)`
  (`movi.2d v1, #0; mov.16b v0, v1; bl Point.init(x:y:)`), from
  `sample.Point.init((0, 0), (0, 0))` to `sample.Point.init(0.0, 0.0)` in
  `--pseudo`, `--structured`, the listing and `--json`; every other
  fixture view is byte-identical. Clarc `--pseudo` changes two lines, both
  `SwiftUI.Animation.spring(0.3, 0.85, (0, 0))` to `spring(0.3, 0.85, 0.0)`
  (the defaulted `blendDuration: 0`); Terminal `--pseudo` is
  byte-identical.
- **FIXED (soundness): `dup` into four lanes was held as two eight-byte
  lanes.** The `dup` transfer required only a general-register source and
  a 128-bit destination, so `dup.4s v0, w0` held w0 in each word, though
  each word is `w0 | w0 << 32`. `dup_lanes.c` (-O2) fills an `int[8]`
  with a call's result (`dup.4s v0, w0; stp q0, q0, [sp]`) and reads one
  word back: `fillInts` rendered `sink((r0 & 0xffffffff))`. The transfer
  now also requires a 64-bit source (`dup.2d v0, x0`), so `fillInts`
  passes an unknown and the `long[4]` control `fillLongs` keeps
  `sink(r0)`. Blast radius: only `libDupLanes`; release `disasm
  --pseudo` of the five apps is byte-identical.
- **FIXED (correctness): a floating variadic argument printed its bits.**
  On Apple arm64 a double passed to a variadic function is its bits in
  one eight-byte stack slot, and the format paths kept only a count of
  the conversions, so `[NSString stringWithFormat:@"%f", 1.5]` rendered
  `0x3ff8000000000000` and `printf("%Lf %lf %e %g %a\n", …)` five hex
  words. The format parser now classifies each conversion
  (`formatArgumentKinds`: `f F e E g G a A` bare or with `l` or `L` are
  floating, `d i o u x X c C` integer, `s S p @ n` pointer, a floating
  conversion with any other length modifier unsized), and a floating
  slot renders as its shortest round-trip double when one eight-byte
  store wrote it (`CallSite.stackArgumentWidths`) with a normal or zero
  constant (`Disassembler.formatSlotTypes`). A NaN, an infinity, a
  subnormal, a narrower store and an argument the format disagrees with
  (`@"%f", 3` and `@"%d", 1.5`) keep their bits. `__snprintf_chk` and
  `__sprintf_chk`, which snprintf and sprintf lower to at -O0, joined the
  format table, so their variadic arguments print instead of being
  dropped. `variadicfloat.m` (-O0 and -O2) holds each shape. Blast
  radius: the `%f` zero of `vectorlane.m` reads `0.0` (was `0`), and
  `objc_untyped_float.m`'s `formatLocal` (-O0 and -O2) reads
  `stringWithFormat:@"%f", 1.5` (was `0x3ff8000000000000`) in every
  view; every other fixture view is byte-identical. Clarc and Terminal
  `--pseudo` are byte-identical.

## 2026-10-23: the known C arity table against its headers

- **FIXED (soundness): known C arities that disagreed with their headers,
  and entry points of no parameters that printed a stale x0.** The
  "c-arity" layout pads a call to the table's count, so a wrong entry is a
  wrong render in either direction. `exit` was 0, not 1 (`_stdlib.h:165`),
  and read `exit()`; `objc_loadWeakRetained` was 2, not 1, and
  `objc_copyWeak`/`objc_moveWeak` 3, not 2 (Swift
  `include/swift/Runtime/ObjCBridge.h:46-50`), each printing a phantom
  `?`; `swift_unexpectedError` was 0, not 5 (`Error.h:128`), so a failed
  `try!` lost its error and location. `__error`, `pthread_main_np`,
  `arc4random`, `dispatch_group_create`, `objc_end_catch` and
  `objc_terminate` take nothing but were missing, so whatever x0 held
  printed as their argument, often a whole unrelated call
  (`objc_terminate(_Unwind_Resume())`). The count is also the tracer's
  `passedRegisters`, which now matches the header for each. The table's
  comment claimed a wrong entry could only drop arguments, which stopped
  being true when the layout began padding; it now says so
  (`known_arity.c`, -O0 and -O2, and `forcedtry.swift`, -Onone and -O:
  `aKnownCArityMatchesTheHeaderIfPresent`,
  `aFailedForcedTryPassesItsFiveArgumentsIfPresent`). Blast radius: no
  other fixture view changes (structured, pseudo, listing, JSON). Clarc
  `--pseudo` changes 148 lines: 17 `pthread_main_np` calls lose a stale
  operand, 6 `swift_unexpectedError()` gain their five arguments, and the
  rest are the bindings that existed only to feed a stale operand
  (`let r1 = …` becomes a statement) and the renumbering after them.
  Terminal `--pseudo` changes 44 lines for 55: 9 `__error`, 10
  `objc_end_catch` and 2 `objc_terminate` calls lose a stale operand,
  `exit()` reads `exit(12)`, and 11 calls that were
  printed only inside such an operand (`_Unwind_Resume`,
  `__stack_chk_fail`, `NSLog`, `objc_begin_catch`, a send) are now their
  own statements.
- **FIXED (soundness, see "known arity and in-image name twins" below):
  the table applied by name.** An in-image function
  that shares a name with an entry (a vendored `qsort`) gets the libc
  arity in the "c-arity" layout, the empty-site pass and the tracer's
  `passedRegisters`, ahead of its own body summary: the "body-reads"
  layout skips any callee the table names, and the empty-site pass and
  the tracer's `CallFacts` consult only the name. A scratch dylib with an in-image
  `long arc4random(long, long)` called as `arc4random(x, 7)` (-O2)
  rendered `arc4random(?, 7)` before the entry above and `arc4random()`
  after it, and the tracer would no longer let a frame address escape
  into it. The same holds today for `free`, `memcpy` and every older
  entry. None of the changed entries has such a twin in the fixtures,
  Clarc or Terminal. The completeness
  entries a read-only audit of the SDK and Swift runtime headers listed
  (`bzero` 2, `memchr` 3, `malloc` 1, `_Unwind_Resume` 1,
  `swift_allocObject` 3, `swift_weakLoadStrong` 1 and others) should land
  behind a gate that applies the arity only to a callee reached through a
  stub or bind.

## 2026-10-23: Swift String and inout argument footprints

- **FIXED (soundness): a call to a Swift callee with a String, `String?`
  or `inout` parameter rendered the wrong number of arguments.**
  `swiftCallArgumentSlots` declined the whole layout when any parameter
  was not one scalar register, so with nothing tracked the call printed
  no arguments, and with some registers tracked the positional fallback
  printed one argument per register. In `stringarity.swift` (-O):
  `takeTwo(_: String, _: Int)` read `takeTwo()`, `takeTwo(?, ?, 7)` and
  `takeTwo(StringArity.makeString(arg0), ?, 7)`, `takeInout(&x, b)` read
  `takeInout()`, `takeOptString(nil, 7)` read `takeOptString(0, 0, 7)`,
  and the class method `Box.put(_: String, _: Int)` read
  `Box.put(?, ?, 7)`. A slot now carries its register footprint: one for
  a scalar and for `inout` of any type (its address), two integer
  registers for `Swift.String` and `Swift.Optional<Swift.String>`. Each
  declared parameter renders as one argument. A String renders as the
  literal when both words spell one (small or large), and `?` otherwise:
  a known first word over an unknown second is not that String. The
  layout still declines a bank past eight registers, a typed throw, and
  every other parameter type; the context guard is unchanged, so a value
  type's instance method (`Swift.String.append`) is still not laid out.
  The fixture now reads `takeTwo(?, ?)`, `takeTwo(?, 7)`,
  `takeInout(?, ?)`, `takeOptString(?, 7)` for both callers and
  `Box.put(?, 7)`, and keeps its literals (`takeTwo("hi", 7)`) (`stringAndInoutParametersAreOneArgumentEachIfPresent`,
  `theLayoutSizesStringAndInoutParameters`). Blast radius: 4 views of 6
  fixtures. `bump()` and `syncBump()` over an `inout Int` read `bump(?)`
  (StaleSlot, AsyncInout); `Dog.__allocating_init(name:)` and the
  `Animal`, `Dog` and `Widget` initializers in `sample` gain their
  untracked String as `?`; `Dog.__allocating_init(name:breed:)` at
  -Onone read three arguments for two (`String.init("Rex", 3, 1), ?,
  String.init("Lab", 3, 1)`) and now reads `(?, ?)`, and `Widget.init(r0)`
  over a bridged String reads `Widget.init(?)`, both with the call that
  made the String printed as its own statement. Clarc `--pseudo` changes
  107 lines to 116: about 50 calls with nothing tracked
  (`LocalizedStringKey.init()`, `Image.init()`) gain their `?`; 37
  printed a raw String word as an argument of its own (a high word over
  an unknown low word, a newline or non-ASCII small string such as
  `AttributedString.init(10, 0xe100000000000000)`, a large string's count
  over an unknown object) and read `?`; 13 printed the empty string as
  two arguments, `init(0, 0xe000000000000000)`, and read `?`; 11 passed a
  call's first result word, and that call (13 lines) is now a statement
  of its own; and `String.init(repeating:count:)` gains its untracked
  count. `Swift.String.append()` stays at 51.
- **FIXED (completeness): a String field handed on whole rendered `?`.**
  A laid-out String slot kept its two words only when they spelled a
  literal, so `stringarity.swift`'s new `Box.passLabel` (`ldp x19, x20,
  [x20, #0x18]`, then `takeTwo(label, 7)`) read `takeTwo(?, 7)`. Two
  words that are consecutive words of one String field of `self`, the
  whole field, are now that field: `takeTwo(self.label, 7)`
  (`selfStringField`). The field's first word over another second word
  (`passMixedLabel`), the two words of a field that is no String
  (`passSpan`) and a String that is only part of a field
  (`passFirstOfBoth`) stay `?`. Blast radius: only `passLabel` in
  libStringArity; release `disasm --pseudo` of the five apps is
  byte-identical (no laid-out String slot there takes a field's words).
- **FIXED (completeness, for laid-out slots): a String that is a call's
  result rendered `?`.** After a call whose Swift signature returns a
  String the tracer now sets x1 to `callResultHigh(site)`, and a String
  slot holding that call's two words renders the call:
  `takeTwo(makeString(arg0), 7)`. The paragraph below is the original
  entry; the value-type method part (`Swift.String.append`) is still
  open. Alone, the high word is no argument and no receiver: it trims
  from a positional list like any unknown, and x20 holding it is no
  `self` (`string_high_receiver.s`, after Terminal's `mov x20, x22`
  before `String.hasPrefix`). Blast radius: StringArity and sample.debug
  (`Dog.__allocating_init(Swift.String.init("Rex", 3, 1),
  Swift.String.init("Lab", 3, 1))` where it read `(?, ?)`); release
  `disasm --pseudo` of Terminal, TextEdit and Chess is byte-identical,
  Clarc changes 4 lines and GoodLinks 20, each a body-bounded call padded
  now that a reloaded high word makes its snapshot non-empty, or a String
  result passed by name (`Swift.Substring.init(r#)` for `(?)`).
- **OPEN (completeness): a String that is a call's result renders `?`.**
  After a call, x1 is untracked, so `takeTwo(makeString(n), 7)` reads
  `makeString(arg0)` then `takeTwo(?, 7)`, and the -Onone
  `Dog(name: "Rex", breed: "Lab")` reads `"Rex"`, `"Lab"`, then
  `Dog.__allocating_init(?, ?)`. Proving x1 as the second word of a callee
  whose demangled result is `Swift.String` lets the slot render the
  call. That same proof is what laying out a value type's instance
  method (`Swift.String.append`) needs first, or the correct
  `append(f())` renders (1,274 on Clarc and GoodLinks, counted by the
  2026-10-22 audit) read `append(?)`.
- **FIXED (completeness): some String literals the layout could prove
  rendered `?`.** The empty string, `(0, 0xe000000000000000)` (13 on
  Clarc), a small string with a control character (`"\n"` is
  `(10, 0xe100000000000000)`) and a non-ASCII small string
  (discriminator `0xa_`) were rejected by `ValueTracer.decodeSmallString`,
  which the positional path shares. A typed String slot or field now uses
  `decodeStringSmallString`, which takes any small string whose words
  prove it (ASCII bit agreeing with the bytes, valid UTF-8, zero past the
  count): `stringarity.swift`'s `takeTwo("", 7)`, `takeTwo("\n", 7)` and
  `takeTwo("é", 7)`, and FieldWrites' `self.name = ""` (was `= …`).
  Release `disasm --pseudo`: Clarc 25 lines and GoodLinks 2, each a `?`
  that became a literal (Clarc: 13 empty, 9 with an escaped control
  character, 3 non-ASCII); Terminal, TextEdit and Chess byte-identical.
- **FIXED (soundness): an Optional scalar parameter was read one argument
  per register.** An Optional of a fixed-width scalar has no spare bits for
  nil, so Swift passes the payload's bytes and then a tag byte that is 1
  for nil, and `swiftCallArgumentSlots` declined it, leaving the
  positional fallback. `optionalscalars.swift` (-O): `takeOptInt(nil, 7)`
  rendered `takeOptInt(0, 1, 7)`, `takeOptDouble(2.5, 7)` rendered
  `takeOptDouble(0x4004000000000000, 0, 7)`, and `takeOptInt32(nil, 7)`,
  whose payload and tag share x0, rendered `takeOptInt32(0x100000000, 7)`.
  Probed lowerings, one -O caller per type: an eight-byte payload
  (`Int?`, `UInt?`, `Int64?`, `UInt64?`, `Double?`, `CGFloat?`) takes two
  integer registers, the payload in the first, a Double's bits too, and
  the tag in the second; a narrower one (`Int32?`, `UInt32?`, `Int16?`,
  `UInt16?`, `Int8?`, `UInt8?`, `Float?`) packs payload and tag into one,
  the tag just above the payload. `Bool?`, pointer and class optionals use
  an extra inhabitant and keep their one-register reading.
  `integerRegisterFootprint` now sizes those optionals
  (`optionalScalarPayload`), `optionalScalarArgument` keeps a slot only
  when its tag is a known 0 or 1, and the renderer spells `nil` or the
  payload as its own type: `takeOptInt(nil, 7)`, `takeOptInt(5, 7)`,
  `takeOptDouble(2.5, 7)`, `takeOptInt32(nil, 7)`, and `?` for an
  unknown optional. Blast radius: the two fixtures only (stringarity's
  `takeOptInt(?, ?, 7)` reads `takeOptInt(?, 7)`); release
  `disasm --pseudo` of Terminal, TextEdit, Chess and Clarc is
  byte-identical, and GoodLinks changes two calls to FoundationModels'
  `SamplingMode.random`, whose overloads both take a `UInt64?` seed, from
  `random()` to `random(?, ?)`.

## 2026-10-23: fixtures the presence check did not list

- **FIXED (tests): 26 fixtures that tests read could go missing on an
  enforcing run.** `FixturePresenceTests.requiredFixtures` is the list a
  `SWIFTDC_REQUIRE_FIXTURES=1` run checks, so a fixture a test reads but
  the list leaves out turns its `…IfPresent` test into a silent pass. 26
  were left out, among them `libCallArity`, `libObjCOutgoing`,
  `libSwitches`, `libCodegen.opt` and the three `libABISource` builds
  (`libStringArity`, a 27th, was listed when its fixture landed, in
  `851477a`). With `libCallArity.dylib` moved away, the enforcing
  presence test passed and the CallArity tests skipped. The list now holds
  every build product a test names, by literal path or through a level
  loop. The products no test reads stay out: link-only dependencies
  (`libTypedThrowsNeverLib`, the `…IdentityExternal` and
  `libFieldIdentityDuplicate` dylibs) and `libReconstruction.osize.stripped`.
  Found by comparing every `-o` and `cp` product in `Fixtures/Sample/build*.sh`
  against the list and against the names in `Tests/`.

## 2026-10-23: untyped sends of struct-taking selectors

- **FIXED (ffd5fdb, soundness): an untyped send of a selector that an
  image implementation takes a struct for read the struct's registers as
  later arguments.** With no signature for the receiver the explicit arguments
  are read one x register each from x2, and only a floating-point
  parameter in some implementation doubted that. A struct breaks it too:
  `[u span:NSMakeRange(3, 4) count:5]` rendered `span:3 count:4` (the
  range's location and length, from x2-x3), and at -O2 `[u place:p
  flags:7]`, with the CGPoint passed through in d0-d1, rendered `place:7`.
  On Chess the forwarding `[super initWithContentRect:…]` rendered
  `initWithContentRect:0`, which was the style mask. Now any parameter
  that is not an integer, pointer, object, class or selector doubts the
  layout (`ObjCArgumentABI.takesOneXRegister`), from that parameter on:
  each argument's register depends only on the ones before it, so the
  arguments before the first such parameter in every implementation of
  the selector keep their registers (`[u count:5 span:r]` reads `count:5
  span:?`). This also keeps the leading integer arguments of a
  float-taking selector, which the old rule declined whole.
  `objc_untyped_struct.m` (-O0, -O2) holds the shapes and a control.

  Blast radius: of every fixture view, only `objc_untyped_struct.m`'s,
  plus `libObjCNonselfOutgoing` (`forwardWhole:11 ratio:? tail:?`, was
  `forwardWhole:?`; the source passes 11) and `libObjCPackedStack`'s
  listing and JSON (the untyped `pairs:` send's args note lists `g` and
  `h` as `?` instead of trimming them; its pseudo view is unchanged).
  Release `disasm --pseudo`: TextEdit unchanged; Chess one send (above);
  Clarc 6 `insertText:replacementRange:` sends decline the NSRange
  (`replacementRange:[? selectedRange]` read one word of it), so the
  `selectedRange` send prints on its own; GoodLinks 3 sends gain a
  leading argument the float rule had declined, each checked against the
  listing (`reloadFromCacheWithGoogleAppID:r22`, where x2 is the retained
  result of the send before it, and `attempts:1`, from `mov w2, #1`).
  Terminal: 80 hunks once `let rN` renumbering is normalised away. 70
  decline values at or after a struct or floating argument (`setFrame:1
  display:?`, where 1 was `display:`; `updateContentSize:r1 rowCount:r2`,
  where r1 was the row count), 4 keep an argument before one, and the rest
  are calls that now print as statements because the send no longer
  consumes their result. Two of those calls were missing from the old
  render altogether (below).
- **FIXED (completeness): a call whose result an untyped send reads past
  its colon count vanished.** In Terminal's `-[TTAppPrefsController
  thumbnailView]`, `setSelectedRange:NSMakeRange(a, b - a)` took x2 and x3
  positionally; the pseudo view printed one argument, `r5`, and the second
  `unicharOffsetForDisplayPosition:` call, whose result fed only x3, was
  not printed anywhere. The consumption scan read every register a send's
  site held; it now counts only what a send prints, the receiver, the
  selector and one argument per colon (all of them for a variadic
  selector). `objc_dropped_result.m`'s `spanSend` (an untyped `setSpan:`
  of an NSRange) prints `secondValue()` as its own statement, and
  `formatFirst` still prints its variadic `firstValue()` once. Release
  `disasm --pseudo`: TextEdit gains one line, a `length` call whose
  result was only the length of `addAttribute:value:range:`'s range; the
  other four apps are byte-identical.
- **FIXED (ad13b4d, soundness): an untyped send to a receiver of known
  class that inherits the selector was laid out by colon position.** The doubt above
  applied only when the receiver's class was unknown, a guard kept from
  when the rule skipped sends to self (`0c92a85`). A class that does not
  declare the selector inherits or forwards it, so the image's
  implementations are evidence for it too: `[self span:r count:5]` from
  `SDUntypedStructLeaf`, which inherits `span:count:` from an image
  superclass, rendered `span:3 count:4` and now `span:? count:?`
  (`objc_untyped_struct.m`, `sendInheritedSpan`). Blast radius: only that
  fixture's views change. Release `disasm --pseudo`: TextEdit, Chess,
  Clarc and GoodLinks unchanged; Terminal 3 `[self setSelectedRange:r1]`
  sends in `RawTextView`, where r1 was one word of the NSRange
  `selectionRangeForProposedRange:granularity:` returned, now read `?`.

## 2026-10-23: calls of known arity inside a callee's body

- **FIXED (d64d215, soundness): a call inside a body was taken to read
  every argument register.** A signatureless in-image callee passes what its
  body reads (`CalleeRegisterSummary.argumentReads`), and any call in the
  body counted as reading x0-x7 that the body had not yet written. A
  metadata accessor whose body is `adrp x0; add x0; bl objc_opt_self; mov
  x1, #0; ret` therefore summarized as reading x1-x7, and its callers
  passed it whatever those held: `runtimearity.swift`'s `@objc`
  initializer rendered `type metadata accessor for
  RuntimeArity.RuntimeArityOpenEvent  args(self, ?, arg0, arg1)`, its own
  arguments. A call to a target of known arity (`knownCArity`, by the
  name the call renders, the dyld cache's included so the streaming and
  array paths agree) now reads only that many registers. This settles the
  MITIGATED item's "a non-generic metadata accessor, whose body never
  reads x0, renders `accessor(arg0)`" wherever the accessor's own calls
  have known arity. Blast radius: 12 fixtures, every change an argument
  a callee's body never reads (`type metadata accessor for
  ABISource.ABIRef(arg0)` → `()`, `Cow.Storage(?)` → `()`; the
  `String._unconditionallyBridgeFromObjectiveC` result that only fed such
  an accessor is no longer bound; `sample.Circle.name.getter`, whose self
  is in x20, no longer takes `memcpy`'s result in x0). Release `disasm
  --pseudo`, lines changed once `let rN` renumbering is normalised:
  Terminal 65, TextEdit 29 (`defaultValues(r#)` → `defaultValues()`, a
  `(void)` function), Chess 71 (`sub_1000271ac` takes x0-x2, read before
  its first call), Clarc 530, GoodLinks 9,269 in 3,990 hunks, almost all
  `sub_…(0)` accessors whose bodies never read the request. No printed
  call disappeared in any app (each callee's call count is the same or
  higher); 47 GoodLinks lines lost a second reference to an unresolved
  call's result, which they had passed as a fabricated argument.
- **FIXED (soundness): runtime entry points outside `knownCArity` took
  every live register.** `runtimearity.swift`'s final class called
  `swift_getObjectType(self, ?, arg0, arg1)`, which takes one argument
  (swift/include/swift/Runtime/Casting.h:231), and where the object was
  unknown it read `swift_getObjectType()`. Surveying every call to a
  function in RuntimeFunctions.def in the five apps against its declared
  arguments found six more, each now in the table with its declaration
  checked in the runtime headers: `swift_task_getMainExecutor` (0),
  `swift_getObjCClassMetadata` (1), `swift_checkMetadataState` and
  `swift_continuation_throwingResumeWithError` (2), `swift_getWitnessTable`
  and `swift_getOpaqueTypeConformance2` (3). RuntimeFunctions.def is not
  an oracle by itself: it declares `swift_unexpectedError(error *)`, but
  the compiler calls the five-argument form in Error.h:128. After the fix
  the survey finds no call wider than declared apart from that one and
  names whose generic arguments hold commas. Blast radius: the seven
  callees' calls in 35 fixtures (`swift_getObjectType()` → `(?)`, 104
  `swift_getWitnessTable` notes gain their unknown third argument).
  Release `disasm --pseudo`, new lines after normalising `let rN`:
  Terminal 20 (19 `swift_getObjectType`, the widest `(self, ?, arg0, …,
  arg4)`), Chess 2, Clarc 96, GoodLinks 1,027 (637 `swift_getObjectType`,
  181 `swift_getWitnessTable`, 72 `swift_checkMetadataState`, and 119
  in-image callees whose bodies call them and now take fewer arguments).
  No printed call disappeared.

## 2026-10-23: entry seeding of struct-taking methods

- **OPEN (completeness, blocked): a method that takes a struct still seeds
  none of its arguments.** With the guard in `objcArgumentLocations`
  removed on top of `cd835c5`, every seeded name in the fixtures is right
  (`objc_aggregate_args.m`: `self->_flags = arg1; self->_stamp = arg2`,
  `self->_tag = arg8`; `objc_untyped_struct.m`: `self->_count = arg0 +
  arg2`), and Chess does not change. But the newly known values also reach
  callees nothing bounds, where they print as fabricated arguments:
  - the metadata accessor of a type in another image, which takes only
    the request when the type is not generic: Clarc's and GoodLinks'
    `type metadata accessor for Swift.MainActor(0, ?, arg1, arg2, arg3,
    arg4)` (2 and 18 more sites; dev already has 8 and 368 from methods
    seeded today);
  - an SDK-only selector that takes a struct, laid out by colon position:
    Terminal's `[? setNeedsDisplayInRect:arg0]`, whose rect is in d0-d3
    (fixed since, by the SDK selector table below).
  The accessor is fixed since too (`NonGenericMetadataAccessors`, below).
  Measured again on `8720eb2`: Chess unchanged, and most of Terminal's 304
  normalised lines, TextEdit's 8, Clarc's 12 and GoodLinks' 18 are right
  names (`[self cellSizeForProfile:arg1 controller:arg2 kern:0]`,
  `[self->_activeStorage shiftLineRange:? inDirection:arg1 byAmount:arg2
  withANSIBackgroundColor:arg3]`). What still blocks it: an in-image helper
  whose body makes an Objective-C send summarizes as reading every
  argument register the body has not written, so seeded values reach it as
  arguments it never takes. Terminal's `sub_100020e6c(self->_lines, arg1,
  ?, ?, arg1, arg2)`, whose only reads of x4 and x5 are through `[NSException
  raise:format:…]`, a send of two pointer arguments. Bounding a send in a
  summary needs its selector's x-register footprint, which is known for
  selectors the image or the public SDK declares, not for one an embedded
  framework declares. Measured again on `914b099` (reads through in-image
  calls): the same five Terminal helpers remain, each over a send through
  a selector stub, plus two Swift callees without a register footprint in
  Clarc (`SwiftTerm.TerminalView.method(self: self, ?, ?, arg1)`). A
  positive table of every public selector's footprint (about 800 KB) would
  remove the first kind; the patch stays out until both are covered.

## 2026-10-23: SDK selectors' public declarations

- **FIXED (7a50189, soundness): an untyped send of a selector only the
  SDK declares was laid out one x register per argument.** Nothing in the image doubted
  the layout, so a struct or floating argument the method passed straight
  through left x2 holding something else. `objc_sdk_selectors.m` (-O2):
  `[window setAlphaValue:alpha]` rendered `setAlphaValue:arg0` (the
  receiver, still in x2), `setFrameOrigin:` the same,
  `removeIndexesInRange:` read the location as the whole range, and
  `performSelector:withObject:afterDelay:` read the object again as the
  delay. Terminal had `[self convertPoint:0 toView:?]`, x2 being the view.
  `SDKSelectorPrefixes` is a generated table: for every selector that a
  public framework's class, category or protocol takes a struct or
  floating argument for, how many leading arguments all of them pass in
  one x register. `positionalArgumentPrefix` takes the smaller of it and
  the image's own. A send's registers follow the declaration its compiler
  saw, so only declarations a public SDK header names count: private
  classes (`CAContext`'s `setLevel:(float)`) and underscore selectors are
  left out. The table is committed, so output does not depend on the host
  (4,764 selectors, 189 KB, from the macOS 27.2 cache and the 27.0 SDK);
  `SDKSelectorPrefixGenerator.swift` regenerates it in about 3.5 minutes
  with `SWIFTDC_GENERATE_SDK_SELECTORS=<path>`.

  Blast radius: only the new fixture's views. Release `disasm --pseudo`,
  lines after normalising `let rN` renumbering: Terminal 462, TextEdit
  58, Chess 76, Clarc 146, GoodLinks 437. Nearly every change declines a
  value at or after an SDK struct or floating argument
  (`convertPoint:fromView:`, the NSRange selectors). About 70 sends gain
  arguments before one, which the float rule had declined whole
  (`performSelector:@selector(_clearTabIsBusy:) withObject:arg0
  afterDelay:?`, `setLineDash:… count:1 phase:?`,
  `popUpMenuPositioningItem:0 atLocation:? inView:?`). No send
  disappeared.
- **OPEN (completeness): a selector whose public declarations disagree
  declines for every untyped receiver.** `setTarget:` (NSControl takes an
  object, SceneKit's `SCNCameraController` an `SCNVector3`), `setLength:`
  (NSMutableData an integer, NSStatusItem a CGFloat), `setLevel:` and
  `setOrientation:` now render `?` when the receiver's class is unknown:
  Terminal 14 `setTarget:` sends. A receiver whose class is known from
  outside the image (a class reference such as `[NSEvent …]`, an ivar
  typed `@"NSButton"`) could use that class's SDK declaration instead;
  that needs the SDK encodings keyed by class, not only the prefixes.

## 2026-10-23: system libraries' non-generic metadata accessors

- **FIXED (8720eb2, soundness): a metadata accessor in a system library
  took every live register.** A type metadata accessor takes the metadata request,
  then one argument per generic parameter, so a non-generic type's takes
  the request alone. With no body in the image the accessor of a
  system type was laid out positionally: `runtimearity.swift`'s
  `sharedActor(_:_:_:)` rendered `type metadata accessor for
  Swift.MainActor(0, arg1, arg2)`. `NonGenericMetadataAccessors` is a
  generated, committed table of the types whose accessor a system Swift
  library exports and whose nominal type descriptor (`…Mn`) lacks the
  generic bit, 0x80 (swift/include/swift/ABI/MetadataValues.h:1940):
  15,607 types from 202 images of the macOS 27.2 cache, 643 KB, in about
  six seconds with `SWIFTDC_GENERATE_ACCESSORS=<path>`. `knownCArity`
  gives such an accessor one argument. Blast radius: only
  `runtimearity.swift`'s views. Release `disasm --pseudo`: Terminal,
  TextEdit and Chess unchanged; Clarc 291 normalised lines, GoodLinks
  3,188. The `Swift.MainActor` accessor with extra arguments goes from 8
  to 0 in Clarc and from 368 to 0 in GoodLinks; the rest are other system
  accessors (`Foundation.URL`, `Foundation.Notification`) and in-image
  callees whose bodies call them, which now take fewer arguments. No call
  disappeared.

## 2026-10-23: argument reads through in-image calls

- **FIXED (914b099, soundness): a call inside a body to another in-image
  function read every argument register.** `CalleeRegisterSummary` counted such a
  call as reading every register the body had not written, so a fragment
  whose only call reaches a function that reads nothing took its caller's
  registers as arguments: `abi_escaped_saves.s`'s `control_save_fragment`
  (it calls `ordinary_noop`, a `ret`) rendered `control_save_fragment(arg0,
  arg1)`, and `preserve_calls.s`'s `epilogue_fragment` (a tail branch to
  `stack_sink`, a `ret`) took `setup_fragment()`'s result. A call to an
  in-image function now records its target and the registers unwritten at
  it (`pendingReads`), and `closeOverReads` gives each call its target's
  reads among those, to the least fixpoint: reads only grow, eight a
  function, so it needs no cap, and a register counts only through a
  finite chain of calls that reads it. A target with no summary reads
  every register. `epilogue_helper`, which reads x0 and x1 only through
  its call to `setup_fragment`, still renders `epilogue_helper(arg0,
  arg1)`. Blast radius: only those two fixtures. Release `disasm
  --pseudo`, lines changed after normalising `let rN`: Terminal 2, Clarc
  73, GoodLinks 1,849 in 714 hunks; TextEdit and Chess unchanged. No hunk
  gains an argument, and in no app does a function lose a callee
  altogether (a call that printed twice, once nested in a fabricated
  argument, now prints once). GoodLinks' peak footprint went from 159 MB
  to 119 MB, within run-to-run noise.

## 2026-10-23: register summaries and jump tables

- **FIXED (0f0b271, soundness): a callee's register summary read a
  switch's `br` as a tail call.** The summaries were built before `analyzeFunction`
  recovers jump tables, so a switch's cases were never reached and the
  `br` counted as reading every argument register. `switch_clobbers.s`:
  case 2 of `table_switch` calls `table_clobber`, which leaves x19
  changed; callers keeping arg0 in x19 across `table_switch`, directly or
  through one or two wrappers, rendered `return arg0`, where native
  execution with (2, 5) returns 5. `switchsummary.c` (-O2):
  `dispatchTable(void)` dispatches through a table and reads only
  globals, yet the call after `printf` rendered `dispatchTable(printf(…))`.
  Every summary builder now attaches the function's jump tables first
  (`withJumpTables`): the streaming pass and its clobber rebuilds, the
  array path, and the deeper decode of a filtered run. Blast radius: only
  the two new fixtures; release `disasm --pseudo` of Terminal, TextEdit,
  Chess, Clarc and GoodLinks is byte-identical. Started by an agent on
  2026-10-22 and finished here.

## 2026-10-23: callees that use the caller's frame pointer

- **FIXED (6da37c9, soundness): a save slot that x29 pointed at was taken
  as intact across a call to a callee that writes through x29.** The preservation
  analysis counts sp and x29 as ordinary frame bookkeeping at a call,
  because every function with a frame keeps a frame address in x29. A
  callee can still use it: `preserve_calls.s`'s `x29_writer` stores x1 at
  `[x29]`, and `x29_fragment` saves x19 at `[sp]`, points x29 there and
  calls it, so its reload brings back arg1; the Swift caller keeping arg0
  in x19 rendered `return arg0`, native 2. A summary now records whether
  the body uses the caller's x29 (`readsFramePointer`): reads it before
  writing it, other than as the value a store to its own stack saves
  (the prologue's `stp x29, x30, [sp, #-16]!`). The flag goes through
  calls to in-image functions with the reads fixpoint (`x29relay` reaches
  the writer through a tail branch), and a call to a callee that has it
  lets x29's frame address escape. Imports are taken to keep the ABI and
  not write through x29, as before. Blast radius: only those two callers;
  release `disasm --pseudo` of Terminal, TextEdit, Chess, Clarc and
  GoodLinks is byte-identical (none is built -Osize, where the machine
  outliner makes such fragments).
- **FIXED (fc87a54, soundness): the value tracer kept the caller's frame
  slots across a call to a callee that uses x29.** `preserve_calls.s`'s
  `x29local` keeps arg0 in its frame at `[x29, #16]` across a call to
  `x29_local_writer`, which stores x1 there through x29, and `x29below`
  does the same below the frame record, at `[x29, #-8]`: both rendered
  `return arg0`, native 2. The tracer forgets a frame slot at a call only
  when a frame address escapes through an argument or memory; a callee
  whose summary uses x29 (`framePointerUsers`) now lets the whole frame
  escape at its call, since it can reach either side of the frame record.
  Blast radius: only those two callers; release `disasm --pseudo` of the
  five apps is byte-identical.
- **FIXED (b9c1b02, soundness): an async function's context was kept
  across a call to a callee that writes through x22.** A call hands the context over
  only through an argument, as far as the tracer knew, and x22 is
  callee-saved, so `async_call_effects.s`'s `implicitLeaf` stored 7 to its
  context slot, called `async_calls_mutate_implicit` (which stores 11 at
  `[x22, #16]`) and rendered `return AsyncCalls.observe(7)`; native 11.
  The summary flag above now has an x22 twin, `readsContextRegister`, on
  its own bit of the pending mask, and the tracer lets whatever x22 holds
  escape at a call to such a callee (`contextRegisterUsers`). The leaf now
  renders `AsyncCalls.observe(?)`, and its return, a branch through the
  ResumeParent it reloads from the same context, is no longer proven.
  `readonlyLeaf`, whose callee does not touch x22, keeps `observe(7)`.
  Blast radius: only that function; release `disasm --pseudo` of the five
  apps is byte-identical.

## 2026-10-23: Swift runtime object and weak-reference entry points

- **FIXED (13f2bb2, soundness): eighteen runtime entry points printed only
  their tracked operands.** Outside `knownCArity` a call shows the operands that
  were tracked, so one whose arguments were not tracked read as taking
  nothing: `runtimearity.swift`'s weak reference rendered
  `swift_weakLoadStrong()`, `swift_weakAssign(&self.target)` and
  `swift_weakDestroy()`, and GoodLinks had 1,821 `swift_weakLoadStrong()`,
  774 `swift_allocObject()` and 330 `swift_setDeallocating()`. Each was
  checked in the runtime headers: `swift_setDeallocating`,
  `swift_unownedRetainStrong`, `swift_weakLoadStrong`, `swift_weakDestroy`
  and `swift_unknownObjectWeakDestroy` take 1 (HeapObject.h:211, 505, 627,
  641, 883); `swift_initStackObject`, `swift_initStaticObject`,
  `swift_weakInit`, `swift_weakAssign`, `swift_unknownObjectWeakInit`,
  `swift_unknownObjectWeakAssign` (HeapObject.h:75, 86, 610, 618, 811,
  830) and `swift_getEnumCaseMultiPayload` (Enum.h:155) take 2;
  `swift_allocObject`, `swift_deallocObject`, `swift_deallocClassInstance`
  (HeapObject.h:65, 296, 331), `swift_storeEnumTagMultiPayload`
  (Enum.h:161) and `swift_getErrorValue` (Error.h:63) take 3; and
  `swift_initStructMetadata` takes 5 (Metadata.h:690). Left out on
  purpose: `swift_willThrow` (its arguments are x20 and x21, so `()` is
  right), `swift_once` and `swift_getKeyPath` (the plan's exclusions), and
  the executor checks, whose `SerialExecutorRef` is two words. Blast
  radius: `runtimearity.swift` and `libRuntimeIvars`
  (`swift_allocObject(?, ?, ?)`); release `disasm --pseudo` normalised
  lines: Terminal and TextEdit unchanged, Chess 12, Clarc 2,199, GoodLinks
  11,657. About nine hunks in ten only add the missing arguments, often a
  metadata accessor's result the old render dropped
  (`swift_allocObject(type metadata accessor for
  Foundation.JSONDecoder(0), ?, ?)`); the rest are in-image callers whose
  bodies call these and now take fewer arguments
  (`RxSwift.PublishSubject.init(?)` becomes `init()`). No function loses a
  callee.

## 2026-10-23: field writes that do not fill one field

- **FIXED (50a0c9e, soundness): a field write rendered the first register
  a store wrote as the field's value.** A store into part of a field, or one that
  filled a two-word field with an `stp`, printed that one word as the
  whole field. `fieldwrites.swift` (-O): `name = "a  b"` (`stp x8, x9,
  [x20, #0x10]`) rendered `self.name = 0x62202061`, the String's low word;
  a large literal rendered its count and flags; `pair.a = x` rendered
  `self.pair = arg0`. On Chess a one-byte write deep in a 2 KB struct ivar
  rendered `self->fCollection = arg0`, and a board copied in 16-byte
  pieces rendered `self->fPrvPos = self->fCurPos` for each piece. Now:
  a part is written to its byte range (`self.pair[0..<8] = arg0`); a
  two-word field shows a String literal its words spell, every byte
  zeroed (`= 0`), or a field of the object read whole (`self.end =
  self.start`, one wide register's copy `self->_saved = self->_current`),
  and otherwise `…`; and a value read from the object's own fields names
  the range it came from (`self->fPrvPos[32..<48] =
  self->fCurPos[32..<48]`). Blast radius: `fieldwrites.swift`,
  `objc_field_copy.m`, and the partial writes of `libBoundSelf.opt` and
  `sample.debug`, which now name their ranges (`self.center[0..<8] = …`).
  Release `disasm --pseudo`, normalised lines: Terminal 132, TextEdit 0,
  Chess 124, Clarc 114, GoodLinks 218; about half name a written range,
  and one whole write per app declines where the old render was one word
  (`self->logicalSize = Double(arg1)` for a CGSize, Clarc's `self.start =
  0` from `stp x11, x10`).
- **FIXED (soundness, below): a read of part of a field rendered as the
  whole field.**
- **FIXED (f051793, soundness): a read of part of a field rendered as the
  whole field.** A value loaded from `self` (`selfFieldValue`) printed the name
  of the field holding its offset, whatever it read: `fieldwrites.swift`'s
  `secondOfPair` (`ldr x0, [x20, #0x28]`, pair.b) rendered `return
  self.pair`; Terminal closed `self->_signalPipe` twice where it closes
  each of its two descriptors; GoodLinks formatted `self->fg` three times
  for three colour bytes. The load's note now names its byte range, and
  a loaded value does too, with the width every load of that offset in the
  function agrees on (`self.pair[8..<16]`, `self->_signalPipe[4..<8]`,
  `self->fg[1..<2]`); where loads of one offset differ in width, only the
  start is shown (`objc_field_copy.m`'s `mixed`: `self->_pair[8...]`).
  Blast radius: `fieldwrites.swift`, `objc_field_copy.m`, and the second
  word of a String passed from a field (`libConditions`, `libSample`,
  `sample.release`: `self.breed, self.breed` reads `self.breed,
  self.breed[8...]`). Release `disasm --pseudo` normalised lines:
  Terminal 118, TextEdit 0, Chess 30, Clarc 124, GoodLinks 316.
- **FIXED (soundness): the first word of a paired load named the whole
  field.** `ldp x8, x9, [x20, #off]` recorded one read as wide as both
  registers, so the value in x8 took the whole field's name:
  `fieldwrites.swift`'s new `differenceOfPair` (`ldp x8, x9, [x20,
  #0x20]; sub x0, x8, x9`) rendered `return (self.pair - self.pair[8...])`,
  and `Dog.speak` in `sample` passed `self.breed, self.breed[8...]`.
  A paired load's access now carries `registerBytes`, and the widths that
  name a loaded value give each register its own word:
  `return (self.pair[0..<8] - self.pair[8..<16])` and
  `self.breed[0..<8], self.breed[8..<16]`. The load's own listing note
  still names the whole field it reads. Blast radius: six fixtures (the
  first word of each such pair in libFieldWrites, libSample and its
  stripped copy, sample.release and libConditions opt and osize, whose
  second words' `[8...]` also become `[8..<16]`). Release `disasm
  --pseudo`, lines changed after normalising `let rN`: Terminal 4,
  TextEdit and Chess none, Clarc 3, GoodLinks 127, every one a word of a
  paired load from `self` now named by its own range (`self.impl[0..<8]`,
  `self.visitor[24..<32]`); no function loses a callee. Three of
  Terminal's are `return self->_cursorPosition` (and
  `_displayCursorPosition`, `_scrollRange`) in methods returning a
  two-word struct, `ldp x8, x1, [x0, #0x30]; mov x0, x8; ret`: they now
  read `return self->_cursorPosition[0..<8]`. The old line was right only
  because x0's word took the whole field's name; the return path proves
  x0 alone (see the two-word return item below).
- **FIXED (completeness): a two-word struct returned from one ivar read
  as its first word.** `twoWordFieldReturn`: a method whose encoded
  return type is a composite of 9 to 16 bytes, whose x0 and x1 at the
  `ret` are consecutive words of one whole 16-byte ivar, returns that
  ivar. `objc_pair_stores.m`'s `range` reads `return self->_range`, and
  Terminal's `cursorPosition`, `displayCursorPosition` and `scrollRange`
  read as they did before 2c92b57. Those three lines and that fixture
  line are the whole blast radius.
- **OPEN (completeness): an Objective-C two-word struct return from two
  ivars renders only x0.** `rangeHead`, whose words come from two ivars,
  reads `return self->_range[0..<8]`.
- **FIXED (completeness): a Swift two-word struct returned from one field
  printed `return ?`.** The return path proved only a single-register
  result. `swiftTwoWordFieldReturn`: a function returning a struct of 9
  to 16 bytes of integer scalars (so in x0 and x1), whose two words at
  the `ret` are one whole field of `self` whose type is the return type,
  returns that field. The field's type comes from its record, demangled
  with symbolic references resolved (`FieldMap.fieldTypeNames`, f3b82e2),
  since a field of a type in the same module records `\u{01}` and an
  offset, which matches no name. `fieldwrites.swift` (-O): `pairCopy`
  (`ldp x0, x1, [x20, #0x20]; ret`) reads `return self.pair`, and the
  `pair`, `start`, `end` and `other` getters return their fields;
  `pairMixed` (words of two fields), `otherAsPair` (a field of another
  two-word type) and `pointCopy` (two Doubles, returned in d0 and d1)
  stay `return ?`. Those five lines in each view of libFieldWrites are
  the whole blast radius: no other fixture changes, and release `disasm
  --pseudo` on Terminal, TextEdit, Chess, Clarc and GoodLinks is
  byte-identical.
- **FIXED (80235e1, soundness): an in-image function named like a C
  library function took the library's arity.** `knownCArity` is looked up by name,
  so a vendored function sharing a libc entry's name got its arity in the
  c-arity layout, the render-time trim, the body-reads gate, the tracer's
  passed registers and the summaries' call reads. `arity_twin.c` (-O2)
  defines `long arc4random(long *slot, long value)`, which stores through
  `slot`: `useTwin` rendered `arc4random()`, and `useTwinFrame`, which
  passes its local's address, rendered `sink(5)` after the call, because
  the address did not escape into a callee of arity 0 (native 7). Now
  a call to an in-image function whose name is a C library function's
  (`knownArityNameMayHaveTwin`: not a `swift_`, `__swift_`, `objc_` or
  `_os_log` entry point and not a demangled Swift entity) is bounded by
  its own body everywhere the table applied: `arc4random(?, 7)`,
  `arc4random(local_18, 7)` and `sink()`, a stale x2 bounded out, and a
  relay that tail-branches to the twin reading x0 and x1 through it. The
  compiler's own helpers and Swift accessors keep their entries: gating
  every in-image name broke the lazy witness table accessor's `()` and
  concrete witness dispatch through `__swift_project_boxed_…`. Blast
  radius: only `arity_twin.c`; release `disasm --pseudo` of the five apps
  is byte-identical.
- **FIXED (soundness): an in-image `memset` or `memcpy` was modelled as
  the library's stores.** The tracer's `applyMemoryHelper` matched the
  callee by name, so `libc_twins.c` (-O2 `-fno-builtin`), whose `memset`
  writes nothing, rendered `useFill`'s `memset(&a, 0, 8); sink(a)` as
  `sink(0)`; the local still holds 1. `CallFacts` now keeps
  `knownArityApplies`, false for a call to an in-image function with a
  C library name, and the model runs only when it holds, so the call is an
  ordinary one that may write the local it receives: `sink()`, its
  unknown argument trimmed (see the body-reads item below). The outlined
  `__swift_memcpyN_M` copies are compiler helpers, not twins, and stay
  modelled. `useCopy`, the memcpy shape, renders `sink()` before and
  after: the copy model does not carry that frame source either. Blast
  radius: every other fixture view (structured, pseudo, listing, JSON) is
  byte-identical, and release `disasm --pseudo` of Terminal, TextEdit,
  Chess, Clarc and GoodLinks is byte-identical.
- **FIXED (soundness): an in-image printf-family name was laid out by its
  format.** `enrichCallArguments` read the variadic arguments of any
  callee named in `cFormatVariadics` from the stack. `libc_twins.c` also
  defines `int printf(long, long)` and `int fprintf(const char *, long,
  long)`: `printf(x, 4)` rendered `printf(?, …)` and
  `fprintf("%ld\n", x, 9)` rendered `fprintf(0x630, ?, …)`, each dropping
  its last register argument for stack varargs that are not there. The
  format layout now also requires `!isNameTwin(address)`, as the
  known-arity layout beside it does, so the calls read `printf(?, 4)` and
  `fprintf(0x630, ?, 9)`. Blast radius: every other fixture view
  (structured, pseudo, listing, JSON) is byte-identical, and release
  `disasm --pseudo` of the five apps is byte-identical.
- **OPEN (soundness): the direct-return table may still apply to an
  in-image twin.** `IndirectResults.isKnownDirectReturnCallee` is
  consulted only for a call whose target has no `indirectResultUses`
  entry. Every function the run decodes has one, but a filtered array run
  decodes only its matches, so a call to an in-image `strlen` returning a
  struct through x8 could be called direct by name there. A probe
  (`struct Big strlen(long)`, read back from the buffer) rendered the same
  `strlen()` filtered and unfiltered, so no wrong render is shown yet. The
  identity runtime set holds only `objc_` names, which
  `knownArityNameMayHaveTwin` already treats as one function wherever it
  is, and the read-only set follows `knownArityApplies`.
- **FIXED (soundness): a body-bounded call showed a register its callee
  never reads.** Such a call passed every register through the highest
  its callee's body may read, positionally, so a register below that one
  which the body writes before reading showed the caller's stale value:
  `body_reads.s`'s `useSecond` (`mov x0, x1; …`) rendered
  `useSecond(5, 7)`, and `accessorLike`, which reads only x2 (by passing
  it to memset), `accessorLike(5)`; Clarc's lazy witness table accessors
  took the previous call's result the same way. A position keeps its
  value only when `argumentReads` holds that register: `useSecond(?, 7)`,
  `accessorLike()`. Blast radius: 15 fixtures; release `disasm --pseudo`
  changes Terminal 64 lines, TextEdit 7, Chess 64, Clarc 4,159 and
  GoodLinks 9,787, each a value dropped from an unread position, a call
  that fed only such a position now printed as its own statement, or a
  binding inlined at its one remaining use. Six GoodLinks functions lose a
  call from the pseudo view whose only remaining use is generic plumbing
  that view strips; the listing keeps it.
- **FIXED (completeness): a body-reads call with untracked arguments
  rendered `()`.** A call to an in-image function no signature describes
  passes what its body may read, trimmed of trailing unknowns, so a call
  whose arguments were all untracked read as taking nothing:
  `libc_twins.c`'s `sink(a)` after the memset twin rendered `sink()`,
  and `variadic.m`'s `churn(a, b, c, d)` over untracked C parameters
  `churn()`. The may-read set is an upper bound: a call inside the body
  counts as reading every register it could be passed, and even a
  known-arity callee's parameter can be whatever the register held (a
  lazy witness table accessor hands its untouched x2 to
  `swift_getWitnessTable`). The summary now also keeps
  `provenArgumentReads`, the registers the body's own instructions read,
  and the call is padded with `?` to that count: `sink(?)`,
  `churn(?, ?, ?, ?)`. Padded to the may-read count, the in-image
  `swift_willThrowTyped` in `libTypedThrowsNever` read eight arguments for
  its three, and `body_reads.s`'s `accessorLike` three for none. Blast
  radius: 36 fixtures, 189 pseudo lines, each only gaining `?` arguments
  in every view (checked by stripping the added `?`s and comparing).
  Release `disasm --pseudo`: Terminal 193 lines, TextEdit 19, Chess 159,
  Clarc 8,040, GoodLinks 38,440, all padding but 14 Clarc and 356
  GoodLinks lines, where a generic plumbing argument the pseudo view
  strips only from the end of a list now precedes a padded `?` and shows.

## 2026-10-24: body-bounded calls with nothing tracked

- **FIXED (completeness): a body-bounded call whose registers held
  nothing tracked was not padded.** db4729a pads a body-bounded call to
  the registers its callee's own instructions read, but only where the
  call has a snapshot, and a snapshot with nothing tracked in it is never
  recorded: `body_reads.s`'s `callReadsFirstUnknown` (rand, then a load
  through a clobbered register) rendered `readsFirst()`. Such a callee now
  gets an empty site, as a call of known arity does: `readsFirst(?)`.
  Release `disasm --pseudo`: Terminal 19 lines, TextEdit 3, Chess 23,
  Clarc 985, GoodLinks 5,932, all padding only.

## 2026-10-24: fields past a standard-library generic

- **OPEN (completeness): a field past an `ArraySlice` or `Task` field
  stays unnamed.** The field maps come from MachOSwiftSection's
  `StaticLayoutCalculator` over one image, whose `KnownLayoutTable`
  covers Array, Dictionary, Set, String and the pointer types but not
  `Swift.ArraySlice` or `Swift.Task`, whose descriptors live in the
  standard library. The layout stops at such a field (its trusted
  prefix), so every later field of the type reads `+0x…`: `xrefs
  --probe` over Clarc counts 132 `types.field-unnamed`, 122
  `typeDescriptorNotFound(Swift.ArraySlice)` and 10 `Swift.Task`. Both
  are frozen with fixed layouts, measured here with `MemoryLayout`:
  `ArraySlice<T>` is 32 bytes, alignment 8, for any T (its Optional also
  32), and `Task<S, F>` is 8 (its Optional 8). The fix is two entries in
  the dependency's table (upstream, or a fork pin like MachOKit's).

## 2026-10-23: slice names

- **FIXED (diagnostics): `--arch arm64` chose an arm64e.x1 slice, and the
  listing then blamed a parser defect.** `BinaryLoader.archName` named an
  ARM64 slice through MachOKit's subtype enum, which does not know
  `CPU_SUBTYPE_ARM64E_X1` (12, mach/machine.h:347), so Terminal's two
  slices read "arm64e, arm64". `--arch arm64` selected the x1 slice for
  the in-process paths, and the unfiltered listing asked llvm-objdump for
  an arm64 slice the file does not have, then failed with "llvm-objdump
  produced 0 lines … This is a parser defect, not an empty binary". Slices
  are now named by the raw subtype, capability bits masked, as lipo and
  llvm-objdump name them (arm64, arm64v8, arm64e, arm64e.x1, else
  `arm64 (subtype n)`): `--arch arm64` on Terminal reports "Architecture
  'arm64' not found. Available: arm64e, arm64e.x1", and `--arch arm64e.x1`
  lists the slice, `pacibsppc` and all. Every fixture view and the five
  apps are byte-identical.

## 2026-10-24: literals that hold a quote or a backslash

- **FIXED (soundness): a rendered literal did not spell its bytes.** A
  small Swift string's bytes and a C string were printed between quotes
  as they were, so the four characters c, backslash, n, d rendered
  `"c\nd"`, which reads as a newline, and `a"b` rendered `"a"b"`, which
  does not parse. A C string escaped its quotes but not its backslashes
  (`puts("\\"")` for the bytes `\"`), and the -Onone interpolation fold
  escaped pieces that were already escaped (`"say \\\"hi\\\" …"`). Every
  literal now goes through one escaper, the one large Swift literals
  already used (`escapedLiteralText`); C strings, CFStrings from a file
  or the dyld cache, and both small-string paths share it, and the fold
  keeps each piece as rendered. `literal_escapes.swift` (-O and -Onone)
  and `literal_escapes.m` (-O2) read `take("c\\nd")`, `take("a\"b")`,
  `puts("a\\nb")`, `puts("\\\"")`, `NSLog(@"x\\y")` and
  `"say \"hi\" \(local_40) and a \\n slash"`. Blast radius: those three
  fixtures only, 3 pseudo lines each; no other fixture holds such a
  literal. Release `disasm --pseudo` changes Terminal 31 lines, TextEdit
  7, Chess 1, Clarc 35 and GoodLinks 277, each only adding backslashes
  (equal once every backslash is deleted). The dyld-cache CFString read
  has no fixture: no cache CFString found holds a quote or a backslash
  (Foundation's `\` and `"` at 0x181DC33B4 and 0x181DC33B7 are plain C
  strings), so that branch is guarded only by sharing
  `printableLiteralText`.
- **FIXED (soundness): a condition holding a literal with an escaped
  quote inverted wrong.** The condition inverter found top-level
  operators by toggling at every `"`, so the escaped quote in `"a\""`
  ended the literal for it and the real end opened a new one, hiding
  the rest of the condition. `quoted_conditions.swift` (-O): the loop
  guard of `while p != "a\"" && i > 0` (`cmp x0, x8; ccmp x1, #1, #8,
  ne; b.lt`) rendered `if (!(arg0 == "a\"") || (arg1 < 1))`, entered when
  n < 1, where the same loop over `"ab"` rendered
  `!((arg0 == "ab") || (arg1 < 1))`. `LiteralScan` steps over a
  literal's characters, an escaped one included, and the inverter and
  `unwrapOuterParentheses` (which ignored literals entirely, so
  `!(a == "(") + (b == ")")` inverted to `a == "(") + (b == ")"`) both
  use it. That guard is the whole blast radius: every other fixture
  view and the five apps' `--structured` and `--pseudo` are
  byte-identical.
- **FIXED (completeness): a literal with an escaped quote did not fold.**
  The -Onone literal and interpolation folds find a call's arguments with
  `outermostArgumentListRange` and `splitTopLevelArguments`, which toggled
  at every `"`, so `"q\""` never closed and both declined:
  `literal_escapes.swift`'s `storeQuote` kept
  `Swift.String.init("q\"", 2, 1)`. Both use `LiteralScan` now:
  `"q\""`, and `"q\"\(local_40)"` for `interpolatedQuote`. Blast radius:
  that fixture's pseudo and structured views only; the five apps'
  `--pseudo` is byte-identical.
- **FIXED (soundness): an interpolation fold restarted after a piece it
  could not read.** `matchStringInterpolation` was tried at every
  statement, so when one `appendLiteral` piece did not parse, the run was
  retried from the next append, and the tail folded alone and consumed the
  closing `String(stringInterpolation:)`. `literal_escapes.swift`'s
  `bell` (-Onone), `"\u{7}ring \(x) done"`, whose first piece is a C
  string with a control character that renders only as its address,
  rendered `"\(local_40) done"`, which reads as the whole string;
  `middleBell` folded only its last interpolation. A run now folds only
  from its builder's init or from a statement that no other step of a run
  precedes, so both keep the raw run. Blast radius: those two functions'
  pseudo and structured lines; the five apps' `--pseudo` is
  byte-identical. Since the next entry those two pieces read whole; the
  rule still covers any piece the fold cannot read.
- **FIXED (soundness): an -Onone literal printed cut, or as an address.**
  -Onone builds every String literal with
  `String(_builtinStringLiteral:utf8CodeUnitCount:isASCII:)`, and its
  address rendered as a C string: printable ASCII only, cut after 48
  characters. So `longInterp`'s 54-byte piece folded as
  `"a literal that is longer than forty-eight charac…\(local_40)"`, the
  cut text claimed as the string, and `"\u{7}ring "` and `"café "`
  printed an address. That initializer's pointer now reads as exactly its
  count of bytes (NUL after them, UTF-8, ASCII exactly when the flag
  says): `"\u{7}ring \(local_40) done"`, `"café \(local_40)"`, and every
  byte of the long literals. A C call of the same (address, count, 1)
  shape keeps its address. Blast radius: `literal_escapes.swift`'s five
  such functions and one sample.debug line, `print`'s default terminator
  (`Swift.String.init(0x100007f86, 1, 1)` to `"\n"`, bytes `0a 00`); the
  five apps' `--pseudo` is byte-identical.

## 2026-10-24: a specialization's arguments

- **FIXED (soundness): a generic specialization's arguments were read
  from its unspecialized signature.** The demangler prints a
  specialization as its declaration, `generic specialization
  <Swift.Double> of Specializations.bump<A where A: Swift.Numeric>(A) ->
  A`, and the call took the printed `(A)` positionally from x0. The Double
  specialization takes its argument in d0: `specializations.swift` (-O)
  `useDouble(d, n)` rendered `bump(arg1)`, passing n, and
  `returnDouble(d)` rendered `bump()`. `specializedSignature` reads the
  specialization's substitution list from its symbol and prints the
  declaration's function type with each generic parameter replaced
  (`Specializations.bump(Swift.Double) -> Swift.Double`), and the call is
  laid out from that: `bump(arg0)` in both. Declined, so laid out as
  before, for a function signature specialization, a closure, a generic
  signature of more than one depth or with a same-type requirement, a
  member type such as `A.Element`, a name the tree does not print, and an
  address the linker folded several symbols onto. Blast radius: that
  fixture's two lines in every view; the other fixtures' specialization
  calls are struct methods, closures or signature specializations, and
  the five stripped apps have none, so all are byte-identical.
- **FIXED (soundness): an untyped send a method's own double reached
  read its arguments as integers.** The guard that declines an untyped
  send when a v register is written for it saw no write when the double
  was the method's own argument, untouched since the entry:
  `objc_untyped_float.m`'s `-[Relay relay:to:]` (-O2) rendered
  `[arg1 put:7 at:?]`. The method's encoding now says how many of v0-v7
  its arguments arrive in (`ObjCArgumentABI.floatRegisterCount`), and when
  straight-line code with no call reaches the send from the entry, any of
  them not rewritten counts: `[arg1 put:? at:?]`. `relayCount:to:` (a
  long) and `relayAfterCall:to:` (a call clobbers the double first) keep
  their integer layout. Release `disasm --pseudo`: Terminal 2 sends
  (`setIsOffScreen:` in two methods taking an `NSPoint`, d0 and d1) and
  Chess 1 (`objectForKey:` in `-[MBCController setValue:forAchievement:]`,
  whose value is a double) decline; TextEdit, Clarc and GoodLinks are
  byte-identical. Counting all eight registers for functions without a
  signature as well declined 27 Terminal, 9 TextEdit and 5 Chess sends
  with nothing to show a float was there, so they keep the integer
  layout.

## 2026-10-24: a field of self held across a call

- **OPEN (completeness): untyped sends with a float in a v register
  decline even for selectors the SDK proves integer.** The untyped-float
  guard declines a send's arguments whenever a v register may hold one,
  with no signature to say the selector takes none. Release `disasm
  --pseudo --probe` counts `objc-untyped-float` at Terminal 58, TextEdit
  18, Chess 21, Clarc 45 and GoodLinks 128 sends. The public frameworks
  in the macOS 27.2 shared cache declare 43,919 selectors (with at least
  one argument) whose every declaration passes all arguments in x
  registers (counted with the `SDKSelectorPrefixes` generator's walk), and
  for those the integer layout stands whatever v0-v7 hold. A table of
  them is about 1.8 MB of names, or about 470 KB as 64-bit hashes, next
  to the 4,764-selector prefix table already generated; not yet worth
  the size without a count of how many of the 270 it restores.
- **FIXED (soundness): a register named as a field of self kept the name
  across a call that may write the field.** The tracer names a register
  loaded from, or stored to, a field of self as that field
  (`.selfFieldValue`) and forgot the name only at the next field store.
  `field_aliases.swift` (-O): `let old = a; bumpA(); b = old` rendered
  `bumpA(); self.b = self.a`, the incremented a, and
  `let old = a; bumpA(); return old` rendered `return self.a`, the same
  text as `bumpA(); return a`. A call now forgets those names unless it is
  a retain or an exclusivity access marker (`CallFacts.writesNoFields`; a
  release can run a deinit that writes anything): `self.b = …` and
  `return ?`. Fixture blast radius: the new fixture, the `args(…)` of a
  release after a call in libCow, libSample, libStringArity and
  sample.release (`args(?)`), and one libReconstruction -Osize return.
  Release `disasm --pseudo` changes Terminal 243 lines, TextEdit 2, Chess
  49, Clarc 130 and GoodLinks 554 (after normalising `let rN`); across
  them the self-field references fall from 291 to 34, 2 to 0, 92 to 20,
  152 to 18 and 702 to 134, and no changed line gains one.
- **FIXED (completeness): an in-image wrapper of an access marker forgot
  field names.** -Osize outlines `swift_beginAccess` into
  `OUTLINED_FUNCTION_3` (`mov x2, #0; mov x3, #0; b swift_beginAccess`),
  which is no retain or marker by name, so libReconstruction -Osize's
  `return (self.first + self.second)` became `return ?`.
  `CalleeRegisterSummary.closeOverFieldWrites` marks a body that stores
  only through sp, makes no indirect call and calls only stubs that write
  no field (by the resolver's name) or bodies already marked, a least
  fixpoint; a call to one keeps the names. That return is back, and so
  are 1 Chess and 19 GoodLinks lines, every one a line the apps rendered
  before the fix above; the other three apps are byte-identical.
- **FIXED (completeness): a store renamed its argument source to the
  field.** After `a = x`, x19 was named `self.a`, not `arg0`, so once a
  call forgot field names `a = x; bumpA(); b = x` read `self.b = …`. A
  store now leaves an argument as the argument: `self.b = arg0`, and
  `objc_pair_stores.m`'s `spreadArgs:and:` `(self->_t, self->_u) =
  (arg0, arg1)` where it read the two halves of `_s`. Release `disasm
  --pseudo`: Terminal 11, Chess 5 and GoodLinks 1 lines, 5 of them a `?`
  that is now the argument and 12 a field name now the argument it was
  stored from (`[self->_profile addObserver:…]` as `[arg0 addObserver:…]`
  in a setter); none loses a value, and TextEdit and Clarc are
  byte-identical.
- **FIXED (correctness): a pair store's constant source was renamed to
  the field it wrote.** An initializer zeroes its fields with one
  `movi v0.2d, #0` and a run of stores of q0, and each pair store renamed
  q0 to the field it had just written, so FieldWrites.init rendered
  `(self.end, self.front[0..<16]) = (self.start, self.start)` and
  `self.point = self.other`, a pair of Doubles from a pair of Ints. A pair
  store now keeps a constant source as the constant, and the whole-field
  zero rule takes a zero vector (`isAllZero`): `((0, 0), (0, 0))` and
  `self.point = 0`. The init was the only fixture of a forwarded part in
  a pair store over two fields; `objc_pair_stores.m`'s SDTailForward
  (`str x2, [x0, #0x8]; stp x2, x2, [x0, #0x18]`) now is:
  `(self->_a[16..<24], self->_b) = (self->_a[0..<8], self->_a[0..<8])`.
  Blast radius: those four init lines; the five apps' `--pseudo` is
  byte-identical.
- **FIXED (soundness): a forwarded part of a field was named as the whole
  field outside `registerWrite`.** A value renamed to a field by a store
  rendered by the widths of the loads at its offset, and had none:
  `objc_pair_stores.m`'s `spreadParts:and:` (`stp x2, x3, [x0, #0x8]` over
  a 16-byte `_s`, then over `_t` and `_u`) read
  `(self->_t, self->_u) = (self->_s, self->_s[8...])`, and `tailInt:`
  `((self->_a & 0xffffffff), …)` for `_a`'s first four bytes. The tracer
  records each renaming store's width (`selfFieldAliasWidths`), and those
  join the load widths: `(self->_s[0..<8], self->_s[8..<16])` and
  `(self->_a[0..<4] & 0xffffffff)`. Release `disasm --pseudo`: Clarc 2
  lines, a comparison of two 16-byte fields word by word whose first or
  second field had been named whole, now by both ranges; the other four
  apps are byte-identical.
- **FIXED (completeness): a `dup`'d vector store over two ivars rendered
  nothing.** `objc_pair_stores.m`'s SDStraddle `fill:` is `dup v0.2d, x2;
  stur q0, [x0, #0x18]; stur q0, [x0, #0x8]`, each store over the end of
  one ivar and the start of the next, and printed no statement.
  `registerWrite` now takes a 16-byte single-register store as its two
  lanes: `(self->_s[8..<16], self->_t) = (arg0, arg0)`, and
  `(self->_a, self->_s[0..<8]) = (…, …)` for the second, whose q0 is by
  then named as a field. The same rule writes a vector store over two
  whole fields per lane, which also ends one wrong line: libReconstruction
  -O and -Osize `x *= k; y *= k` (`fmul v0.2d`) read
  `self.{x, y} = (self.x * arg0)`, one value for both, and now reads
  `(self.x, self.y) = (…, …)`. Release `disasm --pseudo`: Terminal 5,
  Chess 1, Clarc 2 and GoodLinks 2 lines, each a two-field span store
  now one tuple per lane with the same values (`= 0` as `(0, 0)`); TextEdit
  is byte-identical.

## 2026-10-24: the autorelease family returns its argument

- **FIXED (soundness): an autoreleased object rendered as a new
  allocation at every use.** `objc_autorelease` returns the object it is
  handed, and the tracer modelled its result as new: that result printed
  as the allocation it came from wherever it was used, and as a runtime
  helper's it was never bound. `objc_autorelease.m` (no ARC) rendered
  `[[NSMutableString alloc] init]` three times for one string, and
  TextEdit's `-[Controller application:runTest:duration:]` eight
  `[[NSMutableAttributedString alloc] init]`. `objc_autorelease`,
  `objc_retainAutorelease`, `objc_retainAutoreleaseReturnValue` and
  `objc_unsafeClaimAutoreleasedReturnValue` now return their argument, and
  the last, the one member the pseudo view did not hide, is hidden with
  the rest (either change alone regresses: a printed claim, or a result
  never bound). Release `disasm --pseudo`, after normalising `let rN`:
  Terminal 352 lines, TextEdit 51, Chess 27, GoodLinks 84; across them the
  rendered sends fall from 1,206 to 474, 183 to 69, 78 to 30 and 132 to
  84, and the allocations from 264 to 2, 40 to 1 and 20 to 1. GoodLinks
  printed 22 `objc_unsafeClaimAutoreleasedReturnValue(…)` wrappers and
  prints none; Clarc is byte-identical.
- **FIXED (soundness): an unknown object handed through retain or
  autorelease vanished from argument lists.** An identity call's result is
  the object it was handed, and an unknown one made the result unknown,
  which a positional argument list trims: `objc_autorelease.m`'s
  `enumerateAutoreleased` read `objc_enumerationMutation()`, as did
  `objc_retain` of an unknown object all along. An unknown object now
  leaves the call's own result, kept as `?`
  (`objc_enumerationMutation(?)`), and that result renders `?`, not
  `/* unresolved call @ … */ ?`: `objc_thunk_return.swift`'s `@objc`
  getter thunk reads `return ?`. Release `disasm --pseudo` (lines after
  normalising `let rN`): Terminal 15, Chess 4, Clarc 43, GoodLinks 467;
  across them the empty argument lists fall from 4 to 0, 2 to 0, 26 to 0
  and 325 to 22, each call showing the `?` it takes; TextEdit is
  byte-identical.
- **DEAD END (completeness): the Swift retain family as identity calls.**
  `swift_retain`, `swift_bridgeObjectRetain` and `swift_unknownObjectRetain`
  return their argument too, and taking them so (known arguments only,
  as above) binds some re-rendered calls: Clarc 22 and GoodLinks 77 lines
  after normalising `let rN`, their C-style calls falling from 31 to 17
  and 147 to 69. But a retained String's second word then flows on as a
  lone high word, which an argument list trims as unknown, and
  `Swift.String.Iterator.next(?)` read `next()` three times on Clarc, a
  call that takes nothing. Measured at 933ccbd and reverted; it needs the
  lone high word kept as a value first.
- **FIXED (soundness): ten common runtime and C functions read as taking
  fewer arguments than they do.** With nothing tracked, a call of no
  known arity printed only the operands the tracer knew: `bzero()` 376
  times across the five apps, `swift_getKeyPath()` 173, `malloc()` 55,
  `objc_enumerationMutation()` 46. Each now has its declared arity
  (`_strings.h:75`, `_malloc.h:56`, `objc/runtime.h:1526`, `CFBase.h:781`,
  `dispatch/queue.h:248` and `:323`, and swift/include/swift/Runtime
  `Metadata.h:1044`, `Heap.h:34` and `:49`, `Once.h:33`), and
  `untracked_args.c` reads `bzero(?, ?)` and `malloc(?)`. Release `disasm
  --pseudo` changes Terminal 51 lines, TextEdit 3, Chess 19, Clarc 1,668
  and GoodLinks 5,608, every one a call to one of them now at its
  declared count: `swift_once` from 2 arguments to 3 (3,777 on
  GoodLinks), `swift_getKeyPath` from 1 to 2, `bzero` from 0 to 2, and 7
  GoodLinks `bzero` calls from 3 to 2, a stale third register dropped.
- **FIXED (soundness): fifteen more runtime and C functions read at a
  count their declarations do not have.** Surveyed by the callees whose
  rendered argument count varies across call sites: `memchr` showed two
  of its three arguments 402 times and none 31, `sqlite3_column_type`
  none 67 times, `swift_task_isCurrentExecutor` one of its executor's two
  words 1,794 times. Each now has its declared arity (malloc_size,
  _Block_release, objc_destroyWeak and os_unfair_lock_unlock 1;
  swift_dynamicCastClass, swift_conformsToProtocol,
  swift_task_isCurrentExecutor, sqlite3_column_type, sqlite3_column_int64,
  objc_getAssociatedObject and dispatch_once 2; memchr 3;
  swift_getAssociatedTypeWitness and swift_task_create 5;
  swift_task_reportUnexpectedExecutor 6, its executor two words), each
  cited in `knownCArity`. `swift_willThrow` stays out: its one rendered
  argument is the error it reads from x21. Release `disasm --pseudo`:
  Clarc 947 lines and GoodLinks 3,460, nearly all a call to one of them
  at its count; a few in-image functions that reach x5-x7 only through
  one of them no longer take those registers (Terminal's four
  `sub_…(?, ?, arg0)` read `sub_…()`), and TextEdit and Chess change two
  lines each.

## 2026-10-24: C calls laid out from the SDK's declarations

- **FIXED (soundness, `a395807`): a signatureless C call took the
  registers it found and left x0 as its result.** A call to an SDK C function carries
  no signature in the binary, so its arguments were laid out by position
  from the tracked x registers and x0 after it was taken as its result.
  Chess's OpenGL drawing, `glTexCoord2f(u, v); glVertex3f(x, y, z); …;
  glEnd();`, read `glEnd(glVertex3f(glTexCoord2f(glVertex3f(…))))` in 53
  lines; `glFlush(); notifyDone();` read `notifyDone(glFlush())`;
  `glVertex3f(1.0f, 2.0f, 0.5f)` read `glVertex3f()`; `strchr(s, c)` read
  `strchr()`; Terminal's `NSInsetRect(NSInsetRect(r))` nested a CGRect
  that comes back in d0-d3; and `CGRectGetMinY(rect)` took x0, which
  holds no part of the rect. `SDKCPrototypes` is a table of every
  external C function the macOS SDK 27.0 headers declare (20,279, from
  224 of 333 translation units: each public framework's umbrella header
  and one unit of the C library and runtime headers, dumped by clang as
  text), with what each returns (void, integer or pointer, float,
  double, a struct or other value no one register holds, or
  unclassified) and each parameter's register bank. The generator,
  `generateSDKCPrototypes` (`SWIFTDC_GENERATE_SDK_C_PROTOTYPES=<file>
  swift test --filter generateSDKCPrototypes`, about 4 minutes), keeps
  no declaration without a prototype (`int f()`, whose parameters are
  unknown, not none: a first draft gave `SMJobBless` and
  `vImageBuffer_InitForCopyFromCVPixelBuffer` an arity of 0), reads a
  returned function pointer as a pointer (`signal` had read as void),
  drops the attribute macros clang prints inside a type
  (`DISPATCH_RETURNS_RETAINED dispatch_queue_t`, which had made every
  dispatch, os_log and xpc creator unclassified), resolves an anonymous
  struct typedef to its struct (`CMTime`), and declines the 4 names
  declared two ways (the `objc_msgSend` family). Where the callee is the
  import, not an in-image function of the same name:
  - an all-integer declaration is the call's arity (`strchr(?, ?)`);
  - otherwise integers take x registers and floats v registers in
    order, up to the first struct, which with every parameter after it
    renders `?`, since its registers depend on how it is passed
    (`glVertex3f(1.0, 2.0, 0.5)`, `CGContextFillRect(0, ?)`,
    `CGRectOffset(?, ?, ?)`);
  - the result is in x0 for an integer or pointer, v0 for a float or
    double, and neither for void or a struct (`glFlush()` then
    `notifyDone()`; `CGContextSetFontSize(?, CTFontGetSize(r25))`); an
    unclassified result keeps the old reading.
  `c_prototypes.c` (-O2) holds the shapes
  (`anSDKCCallIsLaidOutFromItsDeclarationIfPresent`,
  `anSDKCPrototypeReadsItsBanksAndVariadics`). Fixtures: only
  libGridSampler.opt changes, `fmod(atan2(sin(asin(__sincos_stret(…)))))`
  becoming the seven calls it makes, with `__sincos_stret(r0)` reading
  atan2's double and `fmod(?, 360.0)` its stack constant. Release
  `disasm --pseudo` against the build before: Terminal 634/711,
  TextEdit 32/47, Chess 214/1144, Clarc 317/405 and
  GoodLinks 1161/1285 lines (removed/added). Nearly all are C
  calls taking their declared arguments, nested calls coming apart, and
  results in v0 or in no register; bindings renumber after a binding
  that is gone. In-image functions that only reached x registers
  through such a call take fewer (`sub_…(self, ?, arg0, arg1)` around
  `CFAbsoluteTimeGetCurrent()` reads `sub_…()`). The table is
  568,644 bytes of source.
- **FIXED (soundness): a C argument showed one lane of a struct result
  as the whole call.** After any call the tracer models v0 as the call's
  result, and for a call returning a struct in several v registers v0 is
  only its first field: Chess's `gluOrtho2D([self bounds], ?, ?, ?)` showed
  the whole NSRect as `left`. In a C declaration's float slot a call result
  now stands only where its declaration proves a single `float` or
  `double`: a C prototype result `f`/`d`, a Swift signature returning
  Double, Float or CGFloat, or a send whose every in-image declaration
  returns `d` or `f`; anything else, at any depth short of a conversion,
  is `?`. `objc_struct_lanes.m` (-O2):
  `glVertex2d(r.origin.x, r.origin.y)` after `r = [self rect]` read
  `glVertex2d([self rect], ?)` and reads `glVertex2d(?, ?)`, and
  `glVertex2d([self scale], 0.5)` keeps its send
  (`aCArgumentTakesOnlyAWholeFloatResultIfPresent`). Release `disasm
  --pseudo`: Chess 2 lines (`gluOrtho2D`); Clarc 33, two
  `[? underlinePosition]` (an AppKit CGFloat, true but unproven here)
  declined and the bindings after them renumbered; GoodLinks 7, two
  `modf` arguments that were sends declined and three `/* unresolved call
  */ ?` read `?`; Terminal and TextEdit none.
- **FIXED (soundness): a send's float result was judged by the image's
  declarations alone.** Code reads v0 after a send only when the
  declaration it was compiled against returns there: one float whole, or a
  struct of floats of which v0 is the first field. The image's
  declarations left both ways open: an image `- (double)size` passed for a
  send whose receiver may be an NSImage, whose `size` is an NSSize, and an
  SDK `- (CGFloat)underlinePosition` was unproven. `SDKSelectorReturns`
  (generated by `generateSDKSelectorReturns` from every image of the
  shared cache, keeping the classes, categories and protocols the public
  headers declare, since NSFont's getters are a private framework's; 2,725
  selectors, 1,003 returning an aggregate, 27 minutes) says per selector
  whether its v-register returns are all one float (`f`) or include an
  aggregate (`h`). A send's v0 is now its result when some declaration, in
  the image or the SDK, returns one float and none returns an aggregate; a
  send to `self` takes its class's own declaration.
  `objc_struct_lanes.m`: `[date timeIntervalSinceNow]` is kept, `[object
  size]` and `[object lane]` (the image's `double` and `CGPoint` lanes)
  decline, `[self scale]` stays (`scale` is `h` in the SDK)
  (`aCArgumentTakesOnlyAWholeFloatResultIfPresent`,
  `theSDKSelectorReturnsHoldFloatsAndAggregates`). Release `disasm
  --pseudo`: Clarc 34 lines, its two `[? underlinePosition]` back and the
  bindings after them renumbered; GoodLinks 4, two `modf` arguments that
  are `doubleValue` sends back; Terminal, TextEdit and Chess none.
- **OPEN (completeness): `SDKSelectorPrefixes` walks only the public
  frameworks' images.** A class the headers declare can be implemented in
  a private framework (NSFont in UIFoundation), so its selectors' argument
  prefixes are missing; the returns generator walks every image.
- **FIXED (completeness): nothing at or after an HFA struct parameter
  was placed.** The table recorded only that a parameter was a struct, so
  `NSDivideRect(rect, &slice, &rem, amount, edge)`, whose CGRect is a
  homogeneous float aggregate in d0-d3, read `NSDivideRect(?, ?, ?, ?, ?)`
  and `CGContextDrawImage(ctx, rect, image)` lost its image in x1. The
  generator now reads each struct's fields from the dump and records a
  parameter that flattens, through nested structs and arrays, to one to
  four of one float type as `D<n>` or `F<n>` (CGRect `D4`, CGSize `D2`;
  CGAffineTransform's six doubles stay `s`), in 164 declarations. The
  layout gives such a parameter its `n` v registers as one `?` and places
  what follows; one that does not fit in the v registers left goes on the
  stack (AAPCS64), so it and what follows stay unplaced.
  `c_prototypes.c`: `CGRectInset(?, 0.5, 0.5)`, `CGRectOffset(?, 5.0,
  6.0)`, `CGContextDrawImage(0, ?, 0)`; `objc_struct_lanes.m`:
  `CGRectInset(?, [self scale], 0.5)` and, offsets from a send's lanes,
  `CGRectOffset(?, ?, ?)` (`anSDKCCallIsLaidOutFromItsDeclarationIfPresent`,
  `anHFAParameterIsPlacedOnlyWhereItFits`,
  `aCArgumentTakesOnlyAWholeFloatResultIfPresent`). Release `disasm
  --pseudo`: Terminal 64 lines, among them
  `NSDivideRect(?, local_80, local_60, 40.0, ((r0 == 1) ? 2 : 0))`,
  `NSRectFillUsingOperation(?, 2)`, `CGContextDrawImage(r6, ?, r1)` and
  constant insets and offsets; TextEdit 5, Chess 1, GoodLinks 5
  (`CGRectDivide`'s pointers); Clarc none.
- **OPEN (completeness): nothing at or after a non-HFA struct parameter
  is placed.** A small integer struct (an NSRange in x0-x1) and a large
  one passed by address would need their sizes, which the table does not
  record.
- **FIXED (soundness): a float constant inside a float expression
  rendered as its bit pattern.** `mov x8, #0x4059000000000000; fmov d1,
  x8; fdiv d0, d0, d1` gave the tracer `.binary(.divide, x,
  .immediate(0x4059000000000000))`, the node an integer divide makes, and
  the renderer read the immediate as a float only beside a float
  argument, a conversion or a Swift call returning a float. Beside an
  Objective-C send, a field or a C call it printed the integer: TextEdit
  `[r13 doubleValue] / 0x4059000000000000` for `/ 100.0`, Chess
  `self->_totalTime * 0x40800000` for `* 4.0`. A float operation's
  immediate operand, read from a float register, is now marked
  `.floatConstant(bits:)` at the operation's width and renders as its
  decimal; an integer register's immediate converted by `scvtf` stays the
  integer it is. `float_constants.c` (-O2) and a synthetic `scvtf`/`fcvt`
  body hold it (`aFloatOperationsConstantRendersAsItsDecimalIfPresent`,
  `onlyAFloatRegistersImmediateIsAFloatConstant`). Fixtures: objc_outgoing
  (both builds) `fraction:(arg0 + 0x4004000000000000)` reads `+ 2.5`, and
  libSample.stripped `self.radius * 0x400921fb54442d18` reads
  `* 3.141592653589793`. Release `disasm --pseudo`: TextEdit 1 line, Chess
  2 (`* 4.0`, `+ 180.0`), GoodLinks 2 (`* 0.85`, `* 0.65`), Terminal and
  Clarc none.
- **OPEN (completeness): a float constant passed as an Optional's
  payload renders as its bit pattern.** GoodLinks passes `14.0` to
  `SwiftUI._FrameLayout.init`'s `CGFloat?` height as
  `0x402c000000000000, 0`: the typed-constant rendering knows `Double`,
  `Float` and `CGFloat`, not an Optional of them.

## 2026-10-24: what decoding costs

- **FIXED (speed, `4b87870`): a plain file paid for a dyld-cache lookup
  on every decode span.** `sectionBytes` and `pointerTarget` asked
  `MachOFile.fullCache` first, and MachOKit keeps a full cache it finds
  but not the failure to find one (the fork's `4c4738f` memoizes only
  `cache`), so for a standalone file each read re-opened it as a cache.
  `sample` of release `disasm --pseudo` on GoodLinks put 6,055 of 81,749
  streaming-thread samples (7.4%) under `fullCache.getter`, more than
  `cs_disasm` itself. Both, and `holdsFixedPointer`, now ask only for an
  image loaded from a dyld cache. Release `disasm --pseudo`, three
  alternating rounds, medians: GoodLinks 106.98 s to 99.11 s, Clarc
  24.34 s to 23.05 s, outputs byte-identical, as are `disasm --image
  UserNotifications --pseudo` and every fixture view.
- **FIXED (completeness): the unfiltered listing printed LSE and RCpc
  atomics as data.** llvm-objdump given no CPU or features decodes a
  plain arm64 slice as ARMv8.0, but clang's default macOS arm64 target
  (apple-m1) emits ARMv8.1 LSE, ARMv8.2 dot-product and ARMv8.3 RCpc
  instructions. The listing showed `.long 0xf8e80000` where the CPU
  executes `ldaddal x8, x0, [x0]`, and the analysis ran on Capstone's
  decoding of an instruction the text called data. A filtered run of the
  same function showed `ldapr x0, [x0]`. Found by comparing the two
  decoders' mnemonics at every address of the five audit apps (ReIPA
  scores its decoder against Capstone the same way): after normalizing
  objdump's `mov.16b v0, v1` against Capstone's `mov v0.16b, v1.16b`,
  Terminal, TextEdit, Chess and Clarc agreed everywhere, and GoodLinks
  differed at 17 `.long` words (`casal`, `casalb`, `casp`, `caspl`,
  `ldadd`, `ldapr`, `udot`). The listing and the audit harness's
  reference listing now pass `--mattr=+all`, which decodes every
  extension, as Capstone does. On the five apps it changes exactly those
  17 lines, and on the fixtures nothing but the new `atomics.c` (-O2,
  `anUnfilteredListingDecodesEveryArchitectureExtensionIfPresent`).
- **FIXED (speed): a streaming run re-read `__text` for every span.**
  Each function's decode in `disassembleStreaming` (pass 1, the summary
  closure, the async chains and pass 2) looked up the section's bounds in
  the load commands, read its bytes from the file and opened a Capstone
  engine: `sample` of GoodLinks `--pseudo` put 2,555 of 81,749 samples
  under `textSectionBounds` and 2,291 under `readElements`. The run now
  reads `__text` once (`TextSection`) and slices each span from it with
  one engine, falling back to the per-span read when the whole section
  does not read. Release `disasm --pseudo`, three alternating rounds,
  medians: GoodLinks 98.71 s to 94.14 s, Clarc 22.94 s to 22.38 s (the
  third round overlapped another build and is the noisiest), outputs and
  probe counts identical. GoodLinks' peak footprint rises by about its
  14.1 MB `__text`.
- **Measured (speed): where a whole-image run's decode time goes.** On
  GoodLinks' 3,524,352-word `__text`, decode alone (medians of three
  rounds, each the median of five): Capstone 6 as swiftdc calls it
  (4,096-instruction batches, detail on) 3.24 s, 1.09M instructions/s;
  `cs_disasm_iter` with one reused `cs_insn` 2.76 s; detail off 2.29 s;
  `CS_OPT_SYNTAX_REAL` with real detail, to skip alias matching, 3.44 s,
  no faster (DEAD END). ReIPA's hand-written decoder
  (github.com/JRBusiness/REipa, MIT) does it in 0.71 s, 4.96M/s, but
  yields only a text string and a flow class: no operands, register
  reads and writes, or flag effects, which the tracer is built on, and it
  is scored against Capstone by mnemonic alone. In the same `--pseudo`
  run Capstone's decode is about 7% of wall time and the streaming path
  decodes the image twice; per-function analysis is about 50%. The plain
  listing's `llvm-objdump` pass alone takes 13.2 s on GoodLinks (0.27M/s).
  So a faster decoder buys at most a few percent of a `--pseudo` run;
  the decode-twice pass, `cs_disasm_iter`, and replacing objdump in the
  plain listing are the larger levers.

## 2026-10-24: build times

- **FIXED (speed): a release build after a debug one rebuilt every
  dependency.** Swift Build (Swift 6.4's default) keeps one `.build` for
  both configurations, and switching between them invalidated the other's
  products: with no source change, a release build right after `swift
  build --build-tests` took 315 s, recompiling swift-syntax, the
  MachOSwiftSection modules and the rest, against 66 s for release after
  release, and the debug build after a release 54 s against about 10 s.
  Every verification cycle alternated the two. A release build now has
  its own scratch path (`--scratch-path .build-release`, git-ignored; the
  CLAUDE.md, README and handoff commands say so): after a one-time 379 s
  build, release with no change takes 5.7 s and after a `Disassembler.swift`
  edit 71 s, and debug no longer rebuilds after it. MachOSwiftSection's
  own notes warn against the same thing.
- **Measured (speed): where an incremental debug build goes.** A no-op
  `swift build` costs 5.3 s, nearly all manifest loading and planning
  before any compile. A body-only edit to a large source file costs 26-29 s
  with `--build-tests`: about 4.5 s planning, 7.5 s recompiling the
  module, 10.5 s recompiling all 151 test files (they import the module,
  and nothing makes that incremental across modules), and about 2 s of
  test discovery and links. `-warn-long-function-bodies=80` puts 18.6 s of
  type checking over the threshold, most of it in tests: two copies of
  one chained `split`/`compactMap`/`filter` in `CLIDiagnosticsTests`
  (1.2 s each), an integer literal chain in `TransitiveReadsTests`
  (0.6 s), array concatenations in `FlagsAcrossCallTests` (0.6 s); in
  sources `enrichCallArguments` (0.9 s) and `ValueTracer.apply` (0.3 s).
- **DEAD END (speed): typing the slowest test expressions.** Rewriting
  the three worst (the `CLIDiagnosticsTests` helper, the `UInt32` literal,
  the byte-array joins; about 3.7 s of type checking) left a body edit's
  `--build-tests` at 28.54 s median against 28.87 s, three rounds each:
  within noise. The test module's critical path is elsewhere. Reverted.

## 2026-10-24: probe traces across processes

- **FIXED (determinism): the async chain pass recorded its probe events
  in hash order.** `asyncChainSlots` walked `AsyncFuncletIndex.chains`, a
  Dictionary, so its `async.context-escape` and
  `async.context-escape-unknown` events came out in a different order in
  every process: two runs of one release binary on Chess differed in 148
  trace lines. Rendered output was unaffected (the result is keyed). It
  now walks the chains by entry address, and three runs of Chess give
  identical whole traces. `asyncChainProbeTracesAreIdenticalAcrossProcessesIfPresent`
  compares four processes on `libAsyncFns.dylib` (27 events).



## 2026-10-30: FairPlay-encrypted images

- **FIXED (soundness): an App Store binary decoded its ciphertext.** The
  first whole-corpus sweep (`Tools/corpus.swift`, 6,127 arm64 images on
  this host) found 14 FairPlay-encrypted binaries (`cryptid 1`), all iOS
  apps under `/Applications/*/Wrapper`. Four decoded ciphertext with
  only a stderr warning: three exited 0 from every command, `xrefs`
  included (two Flutter runners whose encrypted range is 4 KB, so the
  rest of the image passed the preflight, and MikroTik), and `xrefs` on
  ShredderChessLite died by SIGTRAP. The other ten failed as "Malformed
  Mach-O: … `__swift5_fieldmd` descriptor 0 declares 27615-byte records"
  (or `__swift5_assocty`), one message for
  a different cause. The preflight now declines an image whose
  `LC_ENCRYPTION_INFO(_64)` has a non-zero `cryptid`, before any content
  check, with "FairPlay-encrypted: <path> — N bytes at file offset O are
  ciphertext". `cryptid 0` (`ld -encryptable`) still reads. All 14 now
  exit 1 with that message. Every fixture's `dump`, `objc`, `xrefs` and
  `disasm --structured` output is unchanged (`corpus compare`, 145
  binaries, 580 runs).

## 2026-10-30: code outside `__TEXT,__text`

- **FIXED (completeness): functions in other code sections were dropped.**
  Every decode path read `__TEXT,__text` alone. The corpus sweep's
  function-count check (`xrefs` against `dyld_info -function_starts`)
  flagged seven binaries; on this host 60 images have code in other
  `__TEXT` sections (`__lcxx_override` 24, `__text_cold` 4, `__realtime`
  4, `__text_startup` 3, and helpers). Those functions were missing from
  every listing and from `xrefs`, `disasm -f` could not find them, and a
  direct `bl` to one rendered in `--structured` as `/* unresolved call */
  indirect_call(?)`. `CodeSection.of` now takes every `__TEXT` section the
  linker marks as instructions that holds a function start (stub sections
  excluded), and the objdump listing (`--section` per extra section),
  the Capstone decode, streaming, filtered matching, callee decoding,
  on-demand decoding, symbol labels and fold detection all read it.
  `xrefs` function counts, release, before → after (function starts):
  auvaltool 291 → 294 (294), audiomxd 229 → 232 (232),
  systemsoundserverd 230 → 233 (233), Emacs's libcc1plugin 875 → 904
  (904) and libcp1plugin 971 → 1000 (1000). Fixture blast radius: only
  `libCodeSections.dylib` changes (146 fixtures × dump, objc, xrefs,
  listing, pseudo, structured, `corpus compare`).
- **PARTLY FIXED (soundness): `LC_FUNCTION_STARTS` marks data in
  `__text`, and the paths disagreed about it.** DumpPanic and
  DumpPanicRecoveryOS each list starts at lookup tables (`0x1000210c0`
  holds `52 52 52 …`). Each marked start is now one function at its own
  address on every path: one whose first word does not decode starts
  there (AGXMetalG15G_B0's 0x24ae3fc70 ran on from the function before it
  in an in-process decode, and a filter named it `sub_24ae3fc74`), and
  one where no word decodes renders `// no instruction decodes here: the
  image marks a function, but its bytes are not code` instead of being
  dropped (its 0x24ae4e7a4, 2,596 bytes). `xrefs` on the five cache images
  that reported fewer functions than starts: 196,563 of 196,563. Still
  open: a table whose bytes do decode (`52 52 52 …`) reads as code. The
  image gives no evidence against it: DumpPanic's `LC_DATA_IN_CODE` is
  empty (`datasize 0`), and a start reached only through `adrp`/`add` is
  also how a function pointer is taken. The use, though, is evidence:
  DumpPanic materialises 0x1000210b0 (`adrp x2`; `add x2, x2, #0xb0` at
  0x1000210ec) only to load through it (`ld1.4s {v3, v4, v5}, [x2]`, a
  48-byte vector constant), and nothing calls or branches into the
  region. A start whose every reference is the base of a load, never a
  branch target, a call, a stored or passed pointer, would be data by
  its use; that needs an image-wide pass over address materialisations,
  not yet written.

## 2026-10-30: symbols that are not addresses

- **FIXED (soundness, robustness): every nlist value was read as an
  address.** `symbolLabels` and fold detection converted each symbol's
  `n_value` with `UInt64(symbol.offset)`, whatever its type. Two kinds
  are not addresses. An indirect symbol (`N_INDR`, a re-export) holds a
  string-table offset: Gqrx's libc++ re-exports libc++abi, and the
  offset of `__ZNKSt9bad_alloc4whatEv`'s target name, 0x7923, fell in
  `__text`, so `disasm -f bad_alloc4what` listed a function by that name
  at an unaligned address, decoded from the middle of another
  (`sbfx w17, w28, #1, #0xf`). 19 images on this host carry 13,664
  `N_INDR` symbols. SDRangel's libavformat.61 gained 214 such functions
  (3,446 listed, 3,232 starts) and exited 0; Gqrx's libc++, SDRangel's
  libavformat.58 and the CoreGraphics in Xcode's asset runtimes trapped
  in the tracer on the misaligned bytes. An absolute symbol (`N_ABS`) is
  a constant: pixman's NEON assembly sets `mask_bpp_shift` to -1, whose
  conversion trapped ("Negative value is not representable") `xrefs`,
  `disasm` and `analyze` on Emacs's and KiCad's libpixman. Only a
  section-defined (`N_SECT`) symbol names code now, converted with
  `UInt64(exactly:)`. After, release `xrefs`: libc++ 2,143 functions
  (2,143 starts), libavformat.61 3,232 (3,232), CoreGraphics 15,291
  (15,291), Emacs's libpixman 1,082 (1,082), KiCad's 1,189 (1,189), all
  exit 0. Fixture blast radius: only `libAbsoluteSymbols.dylib`, crash →
  ok on listing, pseudo, structured and xrefs; no output changes
  elsewhere (147 fixtures, 882 runs).

## 2026-10-30: SVE registers

- **FIXED (robustness, soundness): an SVE instruction reached the scalar
  model.** Capstone gives `z` and `p` registers no bank, so `PhysReg`
  calls them `.other`, width 0. `lsr z9.s, z9.s, #0x19` (OpenSSL 3's
  ChaCha20) reached the shift model, and `UInt64(width - 1)` trapped
  `xrefs` on six images: five copies of libcrypto (Gqrx, KiCad ×2, UTM,
  zoom) and ChatGPT's `usb_webauthn.node`. In the two OpenSSL 1.1
  builds the instructions are `fcmla`, `ld1sb` and `sel`, which
  `llvm-objdump --mattr=+all` lists too (963 in KiCad's); whether they
  are code or constants in `__text` is not established. And a `z`
  register's low 128 bits are the `v` register of its number: after
  `fmov d0, #2.0; lsr z0.s, z0.s, #1` the tracer still held v0 = 2.0 at
  the return. The tracer now computes nothing into a register it does
  not model, and a write to one leaves no vector value standing. All six
  exit 0, listing every function start (libcrypto 3 for Gqrx 13,087 of
  13,087; usb_webauthn.node 10,389 of 10,389). Fixture blast radius:
  only `libSVERegisters.dylib`, crash → ok on listing, pseudo, structured
  and xrefs (148 fixtures, 888 runs).
- **OPEN (soundness): images list more functions than their starts.**
  UTM's crypto.1.1 lists 7,511 functions against 7,424 starts and zoom's
  libcrypto 10,638 against 10,495. Symbol labels are boundaries too, and
  OpenSSL's assembly keeps local labels inside functions; a label that is
  no function start may be cutting one function in two. Unmeasured.

## 2026-10-30: 4-aligned relative method lists

- **FIXED (robustness): the preflight refused two valid images as
  malformed.** The corpus sweep found every command failing on Brave's
  `ksadmin` and Grok Bot's `chrome_crashpad_handler` with "Objective-C
  method list at 0x100215b78 points at 0x1001f0d60, not into
  __objc_const or __objc_data or __objc_methlist or __objc_methname". The
  fixup targets 0x1001f0d64, the first byte of `__objc_methlist`
  (`dyld_info -fixups` agrees). `class_ro_t.baseMethods` is objc4's
  `PointerUnion`: bit 0 tags a list of lists, and a relative method list
  (12-byte entries) is only 4-aligned. The check masked three bits and
  required 8-byte alignment, which held in the 1,058 binaries it was
  measured on only because their `__objc_methlist` happened to start on
  an 8-byte boundary. It now masks bit 0 and requires 4. Both images load:
  `objc` prints 291 and 32 lines of headers. The metadata fuzzer accepts
  and rejects the same mutants as before (`libObjCAggregateArgs.dylib
  100 4242`: 504/296, 0 crashes; `sample.release 100 4242`: 384/409, 7
  crashes, the same 7 in both builds, next entry).
- **FIXED (robustness): a corrupt `__swift5_typeref` trapped seven
  commands.** `swift Tools/fuzz.swift metadata Fixtures/Sample/sample.release
  100 4242`, mutant 4 (offsets 15813, 15827, 15873, 15921): `interface`,
  `objc`, `objc --methods`, `layout`, `disasm`, `xrefs` and `analyze` died
  by SIGTRAP. The mutation moved a direct context reference (`\x01`) onto
  bytes that are no descriptor but still inside the image, so the
  preflight's "lands in a mapped segment" passed; MachOSwiftSection read
  a "module" there whose name pointer resolved to offset -121290283. The
  preflight now walks the descriptor a `\x01` reference names and its
  parents: a kind the ABI defines, a name the file holds, a mapped parent,
  no loop, at most 64 deep. The fuzz set: 7 crashes → 0 (383 accepted,
  417 rejected of 800). No real image changes outcome: `swift-version`
  over all 6,127 corpus images, with and without the check, 0 outcome
  changes.

## 2026-10-31: objdump's file line

- **FIXED (soundness): the listing named a function after the file.**
  `llvm-objdump --macho -d` opens with `<path>:`, the shape of a label,
  and `parseObjdump` took it as the next instruction's symbol. When the
  first function has no symbol (a stripped executable), the unfiltered
  listing and `analyze` titled it with the path: `disasm /usr/bin/true
  --arch arm64e` printed `/usr/bin/true:` over its only function, and a
  call to it was annotated `→ /usr/bin/true`. With the original HEAD's
  release build, 1,029 of the 3,201 corpus images with at most 64 KB of
  `__text` did this. Labels now count only after a `(…) section` line.
  The fixture blast radius is 23 fixtures' listing and analyze, each
  only its first function's title or symbol comment (an Objective-C
  method's comment regains "[recovered from Objective-C metadata]"); the
  filtered, pseudo and structured views read no objdump labels and are
  unchanged.

## 2026-10-31: Go function tables

- **FIXED (completeness, memory): a stripped Go image was one function.**
  Go's internal linker writes no `LC_FUNCTION_STARTS`, and `-ldflags=-s`
  removes the symbol table: 20 of the 41 Go images on this host (Docker's
  CLI plugins, github-mcp-server, claude-ssh-askpass) had no boundary at
  all, so all of `__text` was analysed as a single function. `xrefs`
  reported "1 of 1 functions" and peaked at 2.68 to 2.85 GB on the 7 MB
  plugins (the corpus sweep's 7 memory kills at 1.8 GB). The Go runtime's
  own table, `__gopclntab` (what it reads to print a stack trace), lists
  every function's entry and name. `GoFunctionTable` reads it (Go 1.18
  and later), declining the whole table on any inconsistency, and its
  entries join the function starts and name otherwise unnamed functions
  as an unstripped image's symbols do (`_main.scale`). On the fixture the
  table equals the unstripped twin's symbol table: 1,683 addresses, every
  name equal once the symbol table's `.abi0` suffix is dropped. Release
  `xrefs`, before → after: github-mcp-server 1 → 24,783 functions,
  2,850 → 142 MB, 90.7 → 112.6 s; docker-ai 1 → 21,419, 2,678 → 158 MB,
  60.7 → 105.8 s; com.docker.socket 1 → 1,952, 188 → 33 MB, 5.5 →
  10.8 s. The time grows because each function is now analysed as one.
- **FIXED (soundness): a branch to the function's own entry rendered as a
  loop and a call.** The CFG makes `b <own entry>` a loop's edge, and its
  callee made the same branch a call: Go's stack-growth prologue (`cmp sp,
  x16; b.ls` to `bl runtime.morestack_noctxt; b main.main`) rendered
  `while (sp <=ᵁ x16) { runtime.morestack_noctxt(); main.main() }`, and
  `error_exit_controls.s`'s `entryBackEdge`, whose entry is a loop target,
  rendered `ExitProof.entryBackEdge(arg0)` inside its own loop. Such a
  branch keeps its target and loses its callee. Fixture blast radius:
  only `entryBackEdge` (listing loses `args(arg0)`, pseudo and structured
  lose the call), across 169 fixtures × listing, pseudo, structured,
  xrefs.
- **OPEN (soundness): `go:buildid` is data at the start of `__text`.** The
  table lists it as a function at `runtime.text`; its bytes are the build
  ID string, decoded as instructions (the data-in-`__text` item above).

## 2026-10-31: boundaries the corpus measures but nothing supplies

- **OPEN (completeness): an image with neither function starts nor
  symbols is a handful of functions.** Chromium's `app_mode_loader` (in
  Brave and in ChatGPT's Codex framework) has 152,073 instructions, no
  `LC_FUNCTION_STARTS` and 2 function symbols: `xrefs` lists 2 functions.
  libRosettaRuntime lists 1 for 80,317. `app_mode_loader` has an
  `__unwind_info` with 410 entries, and every compact-unwind entry is a
  function start in 1,141,960 of 1,142,197 entries sampled across 591
  corpus images (the 237 others begin code regions after a `ret` with
  their own unwind record, real code no start names). But the linker
  merges consecutive functions with the same encoding into one entry (5
  functions, 2 entries in a reduction), so an entry is not a function's
  extent; used as one, it would render several functions as one. A
  boundary source would need the merged runs split, for example at direct
  call targets.
- **Explained: AppleMediaServicesKit lists 55 fewer functions than its
  starts.** 47 of the 55 starts swiftdc does not list follow a `br`: they
  are the jump tables after it (`e4f9ffff 5cfeffff …`, offsets), which
  `LC_FUNCTION_STARTS` marks and swiftdc does not render as functions.
  The other 8 follow a `bl` and are not yet classified.

## 2026-10-31: accessor classification in images without function starts

- **FIXED (memory, soundness): `objc` decoded accessors up to the next
  IMP.** The large-image tier (148 images over 8 MB of `__text`) found
  `objc` killed at 3 GB on nine Chromium and Electron frameworks;
  Discord's Electron Framework passed 6 GB at 118 s. `objc` classifies
  property accessors by decoding each IMP to the next boundary, and
  `disassembleFunctions` took boundaries from function starts and IMPs
  only. Electron Framework has no `LC_FUNCTION_STARTS`, so each extent ran
  to the next IMP, megabytes away, and the async funclet grouping then
  decoded every boundary of the image. Symbols are boundaries there now,
  the classification decodes a 4 KB prefix of each extent and skips async
  grouping. The overlong
  extent was also wrong: a synthesized setter decoded together with the
  6 KB function after it read as custom and stayed in the header
  (`accessorextent.m`). Release `objc`, all nine now exit 0: 1,814 to
  3,610 MB, 12.2 to 24.3 s (Discord's 1,974 MB, 13.6 s). Fixture blast
  radius: only the new fixture's `objc` and `objc --methods` (171
  fixtures).
- **FIXED (soundness): an accessor was judged by its whole extent.** The
  first form of the entry above left an extent past 4 KB unclassified,
  which the rewriter treats as synthesized: a custom getter that is the
  last IMP before a long unnamed function (`accessorextentcustom.m`,
  `return [_inner value]`) was dropped from the header. Judging the whole
  extent was wrong the other way (the synthesized setter above). The
  accessor is now the block its entry starts, over the prefix: one block
  ending in a return or a tail call, with only property-storage helpers,
  is synthesized; a branch inside it is custom; a block that runs off a
  decode the prefix cut is unknown, and one that runs into the next
  function (after a call that does not return) is custom. Release `objc`
  on the nine frameworks: 1,791 to 3,438 MB, 11.9 to 21.3 s, all exit 0.
  On 150 sampled Objective-C images the headers equal the upstream
  build's. Fixture blast radius: only the new fixture (171 fixtures ×
  `objc`, `objc --methods`).
- **FIXED (soundness): a getter that returns a constant read as
  synthesized.** `- (int)period { return -1; }` (`mov w0, #-1; ret`) is
  one block with no call, so `objc` dropped its line, in the upstream
  build as well. Brave's `BraveSoftwareUpdateAgent` has four
  (`CRUManagedPreferenceGlobalPolicySettings`' `lastCheckPeriodMinutes`
  returns -1, `proxyMode`, `proxyServer` and `proxyPacURL` return nil).
  A synthesized accessor now must touch the ivar: a load or store
  addressed from `self` or from a copy of it (a `mov`, an `add` for a
  non-fragile ivar offset, a reload of the stack slot `-O0` spills it to,
  a callee-saved copy across a call), or a property-storage helper. On
  150 sampled Objective-C images it keeps 291 accessor lines in 34
  images and drops none; of 12 read by hand, 8 are custom (constants, a
  category getter backed by a global, message sends) and 4 tail-call an
  outlined or shared helper. Fixture blast radius: only
  `constantgetter.m`.

## 2026-10-31: whole-binary corpus measurements

`Tools/corpus.swift` (see [Tools/audit/README.md](../Tools/audit/README.md))
over every arm64 Mach-O image on the audit host: 6,127 unique images
(by SHA-256) from 9,079 candidates, 7.2 GB of `__text`, 1,615 with Swift
metadata, 2,459 with Objective-C classes; Xcode's frameworks and plugins
(1,782), `/usr/libexec` (583), `/usr/bin` (487), `/System/Library`
(411), and third-party apps (SDRangel, VLC, KiCad, Docker, Electron and
Chromium apps, Go tools). The harness's header reader agrees with `otool
-l` on all 6,091 images both read. Release builds throughout; the
"before" build is the session's starting point, `10e5c9e`.

**Reliability**, the 5,979 images with at most 8 MB of `__text`, `dump`,
`interface`, `layout`, `objc`, `swift-version` and `xrefs --unreferenced`,
4 jobs, 1.8 GB and 900 s limits, 35,874 runs each:

| | crash | memory kill | timeout | error |
|---|---|---|---|---|
| before (`10e5c9e`) | 17 | 7 | 0 | 72 (12 per command) |
| after (`0b3f7db`) | 0 | 0 | 0 | 84 (14 per command, all FairPlay declines) |

The 12 errors per command before were 10 encrypted images misreported as
malformed and 2 valid Chromium helpers refused; after, the 14 encrypted
images decline by their cause and the helpers load. The 148 images over
8 MB (4.8 GB of `__text`; metadata commands, 3 GB limit): 0 crashes, 0
errors, 0 timeouts; `objc` exceeded 3 GB on 9 before the accessor fixes
and finishes on all 148 after (1.8 to 3.6 GB on the Electron and Chromium
frameworks).

**Completeness against independent evidence** (`xrefs` function counts
against `dyld_info -function_starts`, same 5,979 images): images listing
fewer functions than their starts, 17 → 7, every remaining one explained
(jump tables after a `br`, which swiftdc declines as functions, in
AppleMediaServicesKit ×3; data in `__text` in DumpPanic ×2; one start each
in CryptexKitHost and MobileDevice, unexamined). Images averaging over
20,000 instructions per function: 7 → 3 (Chromium's `app_mode_loader`
×2 and libRosettaRuntime, no starts and no Go table, OPEN above).

**Consistency across processes**: 400 sampled images × 7 commands
(`disasm --structured` included) × 3 separate processes, 8,400 runs: 0
output differences, 0 failures.

**Performance**, the A/B the working agreement asks for: 40 images
stratified by size (64 KB to 8 MB, Swift and not), `dump`, `interface`,
`objc`, `xrefs`, `--jobs 1`, nothing else running, the upstream build
(`175a563`) and this one (`0b3f7db`) alternated three rounds, medians per
image. Spread between rounds of one build: 1.5% median, 4.3% p90.

| command | median wall ratio | median peak ratio | total wall, s |
|---|---|---|---|
| dump | 1.000 | 1.003 | 28.6 → 28.5 |
| interface | 1.002 | 1.001 | 30.5 → 30.7 |
| objc | 0.517 | 1.004 | 40.1 → 10.1 |
| xrefs | 1.005 | 1.001 | 494.4 → 497.3 |

Output differs on 7 images' `objc` (accessor classification) and 1
`xrefs` (Zoom's libavcodec loses 81 functions named by `N_INDR` symbols),
and one `xrefs` crash is gone (CoreGraphics). Against `10e5c9e` in the
4-job sweep, `xrefs`' peak footprint is up about 3 MB median in every
size band (8.9 → 12.2 MB for images under 64 KB of `__text`); the A/B
puts none of it in this session's commits, so it predates `175a563`.

**Go images**, all 41 on the host (550 MB of `__text`; `xrefs
--unreferenced`, `--jobs 1`, 3.5 GB and 1,200 s limits; the 30 Docker
images on `1f6dd3e`, the other 11 on the Go-table build): 40 finish, 0
crash, 0 memory kills, none lists fewer functions than its starts, 1.48
million functions in all, 1.47 GB peak at most (docker-scout, 72 MB of
`__text`, 1,146 s).

- **NOT A TARGET (speed): `xrefs` on a large Go image runs at half the
  corpus's rate.** Median 16,300 instructions/s across the Go images
  over 4 MB, against 35,800 for the 142 corpus images over 4 MB; at that
  rate `com.docker.backend` (81 MB of `__text`, 188,961 starts) needs
  over 20 minutes and hit the 1,200 s limit at 1.8 GB. A 30 s `sample`
  of that run, main thread: decoding 28% (Capstone's text printer and
  alias matching 15%), `CalleeRegisterSummary.of` 20%
  (`Preservation.exitValues` 7%, `indirectResultUse` 7%), the rest
  spread across CFG building, hashing and retain/release. No single
  hotspot; not yet compared against a non-Go image of the same size.
  swiftdc targets Swift and Objective-C, so this is recorded, not pursued;
  Go images stay in the sweeps for crashes and fabricated output only.

Commits from the corpus: FairPlay declines (`7ed8c6d`), every `__TEXT`
code section (`0eec0b5`), section-defined symbols only (`ffa5e26`), no
scalar model of SVE registers (`5a68ec2`), 4-aligned method lists
(`7ed62b4`), the objdump file line (`6cdb88d`), direct context
references (`949f90d`), Go function tables (`b01115d`), the own-entry
branch (`9f92b71`), accessor decoding and classification (`10712d8`,
`bb3d206`, `0b3f7db`); the harness itself (`a28c827`, `f423c7f`,
`7b47780`).

## 2026-10-31: the dyld shared cache

- **FIXED (soundness): `--image <name>` took the first cache image with
  that name.** 260 names on the macOS 27 host cache belong to more than
  one of its 4,115 images, and for 22 the first is a Mac Catalyst copy
  under `/System/iOSSupport` or an accessibility bundle: `--image
  libswiftMetalKit` read the Catalyst overlay, not `/usr/lib/swift`'s,
  and printed it as the answer. `--image SwiftUI` read macOS SwiftUI only
  because the cache lists it first. An ambiguous name now declines and
  lists every matching install path; `--image-path` picks one.
- **FIXED (correctness): `layout` printed a symbolic field type as raw
  bytes.** A field whose type is in the same module records a symbolic
  reference (a byte from 0x01 to 0x1F and a relative offset), and
  `layout` printed the mangled name as is: `center: ^A` plus the
  offset's bytes, control characters in the text and in JSON's `type`.
  On SwiftUI that was 2,165 of 3,536 fields (61%); on the fixtures, 42
  fields in 10 of 177. Such a field now prints the name the reference
  resolves to (`center: sample.Point`) or `?`, and a plain mangling
  (`Si`) prints as before. SwiftUI: 0 control bytes, 0 `?`.
- **FIXED (completeness, e82eedc): `dump` skipped a declaration it failed
  to render.** A type, protocol, conformance or associated-type entry
  whose rendering threw was left out, which reads as a binary without
  it. GenerativeAgents exports `OpenAICompatibleModel` and
  `InMemorySessionService`, and `dump` and `interface` never mentioned
  them. Each now prints `// struct GenerativeAgents.OpenAICompatibleModel:
  not rendered: unexpected(at: 4)` in its place. The error itself is
  OPEN below.
- **FIXED (correctness, 12f3d24): a constrained existential field printed
  `symbolic existential type (non-unique) 0x0 <Swift.String>`.** The
  shape's existential type was demangled but never printed. `dump` and
  `layout` now substitute the field's arguments into it:
  `Optional<any Source<Self.Source.Element == Swift.String>>`, the type
  swift-demangle gives the field's accessor symbols. On SwiftUI 3 fields
  change and on Foundation 2 (its predicate expressions).
- **FIXED (soundness, 302f9ec): a function-local type printed as a member
  of the enclosing type.** The renderer skipped the unnamed anonymous
  context, so LLDB's `PrecedenceGroupBody`, local to
  `ASTGenVisitor.generate(precedenceGroupDecl:)`, printed as
  `ASTGenVisitor.PrecedenceGroupBody`. The oracle counted 468 such types.
  The type's descriptor symbol now names it (`Local #1 in
  M.Outer.make() -> Any`). Without one, the dropped context is marked as
  the Swift runtime marks it: `M.Outer.(unknown context at $1514).Local`.
- **FIXED (completeness, 7e0d714): a type no type metadata record lists
  was missing from `dump`.** IRGen records a type only when it emits the
  type's metadata, which an optimized build does lazily. LLDB's
  `ASTGenVisitor.DeclAttributesResult` has a descriptor and field
  metadata but no record. The field descriptors in `__swift5_fieldmd` now
  add such types. Declared types: LLDB 872 → 876, SwiftUI 6,308 → 6,316,
  Foundation 1,180 → 1,183.
- **FIXED (correctness): a private type IRGen did not wrap in an
  anonymous context printed without its discriminator.** IRGen nests a
  private type in an anonymous context unless the type is usable from
  inline (`getAddrOfParentContextDescriptor`). Swift's own SIL and
  Optimizer modules (in `swift-frontend`, `sourcekitdInProc` and
  `lib_InternalSwiftScan`) have private types whose descriptor's parent
  is the module itself, so `dump` printed `struct SIL.AccessPathWalker`,
  the same as a second file's private `AccessPathWalker` would print.
  When a file's descriptor symbol names the type with discriminators
  added and nothing else changed, `dump` now prints the symbol's name,
  `SIL.(AccessPathWalker in _FFCB…)`. Type oracle on those three binaries:
  7 missing each → 0. Fixture `dump` output byte-identical. A reduced
  fixture did not reproduce the shape: `-cross-module-optimization`,
  `-enable-cmo-everything`, C++ interop and private imports all keep the
  anonymous context, so the test reads Xcode's binary (`IfAvailable`).
- **Type oracle rerun** (release 4d39b01 plus the private-type fix) on the
  84 binaries the full run flagged with misses: 0 missing types. Xcode had
  updated since the full run, which cleared most. The oracle now strips
  C++ `ns::` qualifiers from identities (libusd_ms's 31 "missing"
  `CodingKeys` were declared under the imported record's C++ name), and
  reports a binary `dump` declines (2 FairPlay-encrypted ChatGPT
  extensions) as `dump-failed` rather than as missing types.
- **OPEN (completeness): a cross-image indirect reference in a dyld cache
  image resolves to the wrong place.** GenerativeAgents'
  `OpenAICompatibleModel.source` is a constrained existential whose
  argument is a type from IntelligencePlatformLibrary (an indirect 0x02
  reference). MachOSwiftSection reads the pointer cell as an "opaque type"
  at offset 0, with ASCII text for flags, so the demangle fails and the
  type is not rendered. 4 types in that image are affected.
- **FIXED (completeness): `layout` and the metadata indices read
  unrecorded types too.** Every index that walked the records (field maps,
  enum cases, payload cases, class names, self types, vtables, the
  metadata symbolizer, descriptor names) now walks `UnrecordedTypes.all`.
  `layout` types: SwiftUI 5,769 → 5,771, Foundation 1,100 → 1,102, LLDB
  581 → 587. The fixtures' structured and pseudo renders do not change.
- **OPEN (completeness, dependency): a field whose type has no record
  stops its type's layout.** MachOSwiftSection's layout calculator finds a
  field's type by name in an index seeded from the records only, so
  `Holder { inner: Inner }` stops at `inner`
  (`typeDescriptorNotFound("UnrecordedType.Inner")`) even though `Inner`
  is laid out. That index is private, and fixing it needs a change in the
  dependency.

## 2026-10-31: the dyld shared cache in the corpus, and a type-identity oracle

The corpus harness reads dyld shared cache images (`cache-manifest`,
02cc7bd). On the macOS 27 host cache: 4,115 images, 1,913 with Swift
metadata (2.55 GB of `__text`), 3,130 with Objective-C classes. Release
build 9aabf0f, the 3,215 Swift or Objective-C images with at most 8 MB of
`__text`, `dump`, `interface`, `layout`, `objc`, `swift-version` and
`xrefs --unreferenced`, 4 jobs, 1.8 GB and 900 s limits: 19,290 runs, 0
crashes, 0 memory kills, 0 timeouts, 0 errors. No output holds a control
byte (f57b103). `xrefs` reports 10,586,556 functions against 10,586,566
starts. The 10 missing starts sit in data inside `__text`
(libMobileGestalt and 6 more, 1 to 3 each), the open data-in-`__text`
item above.

**Type identity** (`Tools/audit/typeid.py`): every nominal type descriptor
symbol (`$s…Mn`) an image defines, demangled by swift-demangle, must be a
type `dump` declares, compared by module and nesting path. A file's
symbols come from `nm -U`; a cache image's from its exports. Across 3,528
Swift images (1,913 cache, 1,615 files), 266,460 type symbols, 889 (0.33%)
in 209 images were not declared on 9aabf0f. The oracle was seen to fail
on a `dump` with one type renamed. On those 209 images, after the fixes
above, missing went 847 → 205 of 69,778, and 4 are not-rendered stubs.
What is left: 26 C-imported `__C` types, local types in private functions
whose names the oracle keys differently, and a tail not yet read.
- **FIXED (completeness, 5edd9af): an unrecorded type its field descriptor
  names indirectly.** Swift Testing's noncopyable `FileHandle` names itself
  through a pointer cell (0x02), and the walk read direct references only.
  Testing (iPhoneOS) declares 274 → 275 types.
- **FIXED (correctness, f742f6e): a local type in a private function kept
  its unknown context although its symbol names the function.**
  InstrumentsKit headers that name their function: 1 → 3; LLDB: 7 → 9.

## 2026-10-31: names in a stripped binary

`Tools/audit/stripnames.py` strips a binary that has its local symbols
(`strip -x`), runs `disasm` on the copy, and checks each function name
recovered from metadata against the original symbol at that address,
demangled by swift-demangle (rules in Tools/audit/README.md). Corpus:
the 472 Swift files on the host with at least 50 local Swift function
symbols and at most 1.5 MB of `__text`.

- **Before (ebcee3b):** 172,467 names recovered: 118,257 exact, 26,696
  compatible, 15,550 Objective-C names of `@objc` thunks, and 11,814
  Objective-C methods under a category the linker merged into another
  (the runtime name). 67 conflicts in 26 binaries, all local classes
  named as members of the enclosing type.
- **FIXED (soundness, d0b24a9): a stripped local class's methods were
  named under the enclosing type.** The symbolizer marks the dropped
  context as `dump` does. After: 0 conflicts on all 472 binaries, with no
  name lost (1,576 names on the 26 affected binaries, before and after).
- **Not a defect: a merged Objective-C category.** The linker merges a
  class's categories and keeps the first name (FileMerge's
  `NSTextView(diffSpecials)` holds `extras`'s 9 methods; only the method
  list's symbol, `NSTextView(diffSpecials|extras)`, says so). The runtime
  reports the first name, and so does swiftdc.
- **FIXED (correctness): a class member named from metadata read as an
  instance one.** `OpenEmuKit.OESystemPlugin.getter` is a `static`
  getter. Vtable entries and witnesses now say `static` when their
  descriptor's flags do (an initializer never does). Stripped-name oracle,
  472 binaries, counting static-ness: 3,917 conflicts → 0, none lost
  (172,466 names).

## 2026-11-01: MachOSwiftSection 0.24 and the dependency refresh

An upgrade experiment on `exp/machoswiftsection-0.24`, from dev at
`ba6d9d6`: MachOSwiftSection 0.22.0 → 0.24.0, MachOObjCSection 0.8.110 →
0.8.205, MachOKit 0.54.101 → 0.55.100 (with the `cache` memo rebased onto
it), swift-capstone 6.0.1 → 7.0.0 (C Capstone 6.0.100 → 6.0.101),
swift-demangling 0.7.2, MachOKitExtensions 1.3.0, swift-semantic-string
0.6.0. Not merged into dev.

Measured on the same inputs as dev: 192 fixtures in eight views, 413
dyld-cache images in six commands (`Tools/corpus.swift`), the 472-binary
stripped-name oracle, and the 40-binary perf set, three alternating rounds
at `--jobs 1`.

- **Suite:** 926 tests pass with fixtures required.
- **Robustness:** 2,478 of 2,478 corpus runs exit 0 on both builds, with
  no crash, timeout or memory kill. `xrefs` reports 2,113,414 of 2,113,414
  function starts on both. The three crashing fuzz mutants of seed 9001
  (libSample.stripped m122, libReconstruction m53, libGaugeKit m75)
  reproduce identically on both; fixed afterwards in preflight (see
  Robustness: witness table pattern, conformance record extent).
- **Stripped-name oracle:** 235,241 names recovered, 165,432 exact,
  0 conflicts, identical per binary to dev.
- **Determinism:** 160 outputs of the perf set × 3 processes, per build:
  0 differ.
- **Speed and memory:** dev against the upgrade, medians of three rounds,
  sums over the perf set: `dump` 29 s / 28 s, `interface` 29 s / 27 s,
  `objc` 13 s / 13 s, `xrefs` 933 s / 942 s. Peak footprint is within 3 MB
  on each command. No single binary moved more than 1.5 s except
  RealityFoundation `interface`, 6.2 s → 4.7 s.
  SwiftUI, SwiftUICore and iOSSupport SwiftUI, same method, dev against
  the upgrade: `dump` 50.3 / 15.5 s, 60.9 / 10.9 s and 43.6 / 13.7 s;
  `interface` 55.5 / 19.5 s, 61.8 / 10.8 s and 47.0 / 15.9 s, with
  interface peak footprint up 7 to 32 MB; `layout` and `xrefs` unchanged
  (within 1 s). 0 of 108 runs failed, and no output differs between
  processes.

Findings:

- **FIXED (soundness, by the upgrade): a protocol requirement's generic
  right-hand side was replaced by its argument.** For
  `Readiness.Element == Event<Payload>` and `Pending == [Payload]`, dev
  printed `Self.Readiness.Element == Self.Payload` and `Self.Pending ==
  Self.Payload`, requirements the protocol does not have (upstream
  6b758d0e). On the cache, CloudKitDaemon
  printed one. `aProtocolRequirementsGenericRightHandSideIsPrintedIfPresent`
  on the new `libProtocolRHS.dylib` is red on dev.
- **FIXED (soundness, by the upgrade): local types that share a name
  shared their fields.** SwiftUI's `TableDataSource` declares six local
  `Visitor` structs, one per drop and delete method. Dev printed all six
  as members of `TableDataSource` with the same field, `var result:
  SwiftUI.DeleteInteraction?`. The upgrade names each by its function
  (`Visitor #1 in SwiftUI.TableDataSource.performDropOn(index:dropInfo:)`)
  with its own fields (`dropInfo`, `strategy` and `items`,
  `itemProvider`). A protocol requirement printed an unbound generic
  parameter: `Self.Host == SwiftUI.AppKitPlatformViewHost<A>`, now
  `<Self>`.
- **FIXED (soundness, by the upgrade): bare-colon Objective-C selectors
  lost their arguments.** Dev printed one-colon selectors that do not
  exist. The ObjC runtime confirms `enumerateRangesIn::`, `decimal::`,
  `formatDate::` and `createStyledButtons:buttonFont:isCompact::`.
- **FIXED (completeness, by the upgrade): Objective-C properties and
  protocol lists on cache images.** 32 of 413 `objc` outputs change. All
  1,930 method lines that disappear return as properties. `CMOdometer` and
  `CKAsset` attribute strings match the runtime's exactly.
- **FIXED (correctness, by the upgrade): a local class's superclass was
  misplaced.** libLocalTypes printed `LocalDouble: LocalTypes.Outer.LocalCounter`,
  a type that does not exist. Local `bump()` methods are now named, and
  deinit members are listed.
- **FIXED (completeness, by the upgrade): Swift 6.4 `borrow` and `mutate`
  accessors.** Dev omitted such a property from `dump` entirely.
- **FIXED (correctness, by the upgrade): `layout` sizes for builtin
  types.** `ExecutorJob`, `Job` and `LocalAllocator` now report 8 bytes,
  which matches stdlib's `Builtin.Job`. The type itself still prints as
  the raw mangling `Bj`.
- **FIXED (correctness, on the branch): 0.23's position-named local
  types defeated the placement cross-check.** 0.23 spells an unnamed local
  type `Outer.(Local in $1dbc)`, where the discriminator is the address of
  its innermost anonymous context. `withoutPositionName` unwraps it only
  when that address is the context swiftdc already proved, and declines
  otherwise. Before the fix the stripped fixture lost 13 names, and
  SwiftUITap lost 7 for a nested `(WorkItem in $3990c).State`.
- **FIXED (completeness, on the branch): a local type the binary names by
  its function.** With `-enable-anonymous-context-mangled-names`, or a
  `_symbolic` symbol on the cache, 0.23 names `Local #1 in M.T.f()`.
  Accessor names now use that name when the mangling places the type on
  each anonymous context swiftdc proved
  (`namesEveryAnonymousContext`). Without this the upgrade lost 46 accessor
  names on cache images to `sub_`. libLocalTypesNamed: 14 → 24 names
  recovered, 12 → 22 exact, 0 conflicts. Class-method labels decline such
  an owner, because `T.method` would read as a member of the function's
  return type: allowing it produced 2 oracle conflicts.
- **FIXED (soundness, on the branch): a stripped copy read its original's
  names in the same process.** MachOKitExtensions keys
  `SymbolIndexStore` and `SymbolicDemangler` caches by install name plus
  UUID, and a stripped copy keeps both. `BinaryLoader` now evicts the
  loaded file's entries. The guard only evicts Swift images, because
  eviction reaches `MachOFile.cache`, and MachOKit's `DyldCache.init`
  traps with `try!` on a file shorter than a cache header.
  `aStrippedCopyLoadedAfterItsOriginalReadsOnlyItselfIfPresent` passes on
  dev, so the contamination is new in the upgrade. OPEN: two same-key
  files read at once in one process still share upstream's caches. No
  CLI command does that (each loads one file), but the parallel suite
  did: aStrippedLocalTypeKeepsItsUnknownContextIfPresent failed once in
  six runs while another test read the original, so the stripped
  fixture now has its own install name. The fix belongs upstream: key a
  file by its path on disk, not its install name.
- **MachOKit fork: the `cache` memo still matters; fat64 does not.** The
  fat64 cherry-pick is upstream (p-x9 #340), identical, and its test
  passes on 0.55.100. The negative `cache` memo is upstream nowhere.
  Without it (upstream 0.55.100) the perf set takes `dump` 53 s,
  `interface` 61 s, `objc` 48 s and `xrefs` 1,166 s, against 28 / 27 / 13 /
  942 s with it, byte-identical output. SourceEditor `objc` goes 4.9 s →
  21.3 s.
- **Capstone: no decoding change.** swift-capstone 7 rewrites the Swift
  wrapper; swiftdc calls the C API, so the wrapper is irrelevant. C
  Capstone 6.0.101 changes `cs_disasm_iter` flag resets, `CS_OPT_OFF`,
  custom mnemonic aliases and x86/Alpha tables, none of which swiftdc
  uses, and no AArch64 table. All 192 fixture listings are byte-identical.
- **Not integrated: CrossReferenceAnalysis.** It reads only an in-process
  `MachOImage`, so it cannot read a file on disk, an iOS binary or a
  foreign cache without loading untrusted code. On AppIntents, SwiftData
  and Charts it decodes the same function table. Its site set contains
  all of swiftdc's, with 0 target disagreements over about 172,000 sites.
  Its extra sites are swiftdc's unresolved calls plus indirect `br`, none
  resolved. swiftdc resolves 12,472 GOT and slot calls that it leaves as
  bare indirect. It classifies no call as a vtable or witness dispatch;
  the discriminator-to-declaration map is not in 0.24. It is much faster
  (0.3–1.3 s against 9–37 s) because it does no value tracking, so the
  times are not comparable. One thing it has that swiftdc lacks: selectors
  on `objc_msgSendSuper2` (39 sites). Tool: `Sources/xrefcompare`.
- **Not wired in:** 0.23's GenericSpecializer, module selectors,
  private source-file recovery, `marksNestedDefinitions` and
  `protocolRequirementPlacement` are opt-in. Each needs its own
  measured change.

## 2026-11-02: runtime calls that return through x8

- **FIXED — a result buffer survived a runtime call that overwrites it.**
  `isKnownDirectReturnCallee` took every `swift_`/`objc_` callee to return
  in registers, so a caller's x8 buffer forwarded to `swift_getAtKeyPath`
  (the stdlib's generic `_getAtKeyPath<Root, Value>`, whose `Value` is
  indirect) kept the stores made before the call:
  `return ResultBuffer.Big(a: 7, b: 7, c: 7, d: 7, e: 7)` for a function
  whose result is whatever the key path read (`resultbuffer.s`). Six
  runtime functions return through x8 (`swiftResultBufferRuntimeNames`,
  from the runtime-signature table on the audit branch); their calls now
  leave the convention unknown, which poisons the buffer, and the render
  is `return ?`. The four swift-syntax dylibs' three `swift_getAtKeyPath`
  sites write a frame slot already forgotten as escaped, so their renders
  are byte-identical.

## 2026-11-02: async methods and yielding accessors named from metadata

- **FIXED (soundness): an async method's name landed on its async function
  pointer, and the entry stayed `sub_`.** For an async method,
  `MethodDescriptorFlags::isAsync()` (0x40) makes the descriptor's
  implementation a relative pointer to an async function pointer record
  (`{ i32 relative Function; u32 ExpectedContextSize }`, in `__TEXT,__const`),
  not to code (`TargetMethodDescriptor::getImpl`, Metadata.h). An override
  takes its base method's flags, and an async requirement's witness table
  slot holds the witness's record (`ProtocolRequirementFlags` 0x20). A
  callee-allocated coroutine (`yielding borrow` / `yielding mutate`, 0x40 on
  a coroutine kind) is the same shape with a coroutine function pointer.
  `classMethodClaims`, `witnessClaims`, `SelfTypeIndex` and `VTableIndex` read
  every field as code. On `libAsyncMethods.opt.stripped.dylib`
  (asyncmethods.swift, -O, `strip -x`) `Animal.fetch` stayed `sub_c64`,
  `Animal.rest` `sub_d1c`, `Dog.fetch` `sub_e28` and the `Box: Fetcher.pull`
  witness `sub_1054`, while `layout --self-index` bound `self` at the data
  addresses 0x1718 and 0x1720 and a data reference to the witness's record
  (`add x8, x8, #0x760`) rendered `→ Box: Fetcher.method`. The yielding
  accessors of `libCoroAccessors.opt.stripped.dylib` (coroaccessors.swift,
  -O, CoroutineAccessors) went the same way: five entries unnamed, three
  `self` bindings on records. `MethodImplementation` now follows a record's
  first field when the flags say the field is data, and names the result
  only if it lies in a code section; a field read as code must lie in code
  too, which also covers an override whose base descriptor is in another
  image. A `VTableIndex` slot holding a record is left out: a `blr` straight
  to the slot's value calls nothing it can name. Measured against the
  pre-fix debug build: 200 of 204 fixtures byte-identical in all four
  `disasm` views. AsyncMethods stripped: 4 entries named, 9 resume funclets
  retitled `resume #n of …` after their entry, the false name on the
  record reference gone. CoroAccessors: 5 entries named; the `self`
  bindings move to code, so `x20 + 0x10` reads `&self.stored` and the
  `blr` in `Box.value.yielding_borrow` resolves to `Box.stored.getter`
  (unresolved indirect sites 11 → 10). One loss: a bound method seeds only
  signature-proven arguments, so the yielding mutate's buffer in x0 renders
  `x0`, not `arg0`, and `sub_a30(arg0)` becomes `sub_a30()` (the open
  "calls with nothing tracked render `()`" item). `xrefs`, `analyze` and
  `layout --self-index` change the same way; `dump` and `interface` do not
  change. Tests: `AsyncMethodDescriptorTests` (unstripped symbol table as
  the oracle).

## 2026-11-02: runtime arities from the signature table

- **FIXED — nine runtime functions had no arity, and the helpers that call
  them took fabricated arguments.** The runtime-signature table (audit
  branch) found `knownCArity` covering 44 of the 57 runtime stubs the
  swift-syntax dylibs call. Nine, each checked against its declaration in
  the Swift checkout, are now in it: `swift_allocBox`,
  `swift_unownedRetain`, `swift_unownedRelease`,
  `swift_getMetatypeMetadata` (1), `swift_allocateGenericClassMetadata`,
  `swift_lookUpClassMethod` (3), `swift_allocateGenericValueMetadata`,
  `swift_getTypeByMangledNameInContext2` (4) and
  `swift_getTypeByMangledNameInContextInMetadataState2` (5). The pre-V2
  mangled-name helpers set x0-x3 (x0-x4) for their runtime call, so with
  its arity unknown their bodies read as taking x0-x5:
  `__swift_instantiateConcreteTypeFromMangledName(arg4, ?, ?, ?, arg4,
  arg5)` is now `(arg4)`. Stripped swift-syntax `--structured`: 113
  changed lines, every one a fabricated argument dropped or a `()` call
  given its true count; three specialized callers checked against their
  symbols (`Dictionary.init(dictionaryLiteral:)`, a closure-specialized
  `map`, `ActiveSyntaxRewriter.init`) now take the arguments their bodies
  read. Still out: `swift_setAtWritableKeyPath` and `swift_getAtKeyPath`,
  whose lowering the table only infers.

## 2026-11-02: specializations seeded from their original's signature

- **FIXED — a dead-argument specialization credited a value to the
  parameter it dropped.** A function signature specialization prints its
  original's signature, but `Arg[n] = Dead` (and every other kind except
  an ownership change) changes the registers. `<Arg[0] = Dead> of
  helperI(Swift.Int, Swift.Int)` takes `b` in x0, and seeded from the
  printed signature its `b &* 23` read `return (arg0 * 23)`
  (`deadargs.swift`). `signatureSpecializationKeepsLayout` now seeds a
  specialization only when every entry is `Owned To Guaranteed` or
  `Guaranteed To Owned`; it renders `return ?`. Fixtures and the four
  swift-syntax dylibs: no other render changes.
- **FIXED — a free function's specialization took a `self`.** The test
  for a free function (`Module.name(…)`, no `self` in x20) read the whole
  name, so a specialization's `function signature specialization <…> of`
  clause defeated it, and `callI`'s second call read `helperI(self: r0,
  arg0)` for the result its caller kept in x20. The clauses are stripped
  first (`withoutSpecializationClauses`). Fixtures: only libDeadArgs
  changes (2 lines); swift-syntax dylibs byte-identical.
- **FIXED — the same specializations' arity.** `callI` rendered
  `helperI(arg1, arg1)` for the one-argument specialization: x1 still
  held `arg1` at the first call, and a callee with a printed Swift
  signature was never bounded by its body's reads. A specialization whose
  clause changes the layout now counts as having no signature of its own,
  so its body bounds the call: `helperI(arg1)`.
- **OPEN — a stdlib value type's initializer takes a `self`.** 12
  `Swift.Dictionary.init(self: _swiftEmptyArrayStorage, …)` calls in the
  swift-syntax dylibs: `receivesThinMetatype` knows only the image's own
  value types.

## 2026-11-02: parameters after a fixed-footprint parameter

- **FIXED — one multi-word parameter left every parameter unseeded.** A
  String, `Int?`, StaticString or `inout` parameter is not one scalar
  register, and `swiftScalarArgumentRegisters` seeded nothing for the
  whole signature, so `afterString(_: String, _ i: Int)` read `return ?`
  for `i &* 3`. Such a parameter is now skipped by the word count the ABI
  fixes (`integerRegisterFootprint`), and an `inout` one, which is its
  address in one register, is seeded: `return (arg1 + (arg1 << 1))`, and
  `mix(_ h: inout Hasher, …)` reads `Hasher._combine(self: arg0, arg1)`.
  Two layouts that read seeded registers as arguments are bounded with
  it: after a value method's formals, a trailing run of registers still
  holding their own entry value is dropped (`W.k(arg1, arg0, arg2)` ->
  `k(arg1, arg0)`), and a String's property getter takes exactly its two
  words (`String.utf8.getter(?, ?, arg1)` -> `(?, ?)`). Fixtures: 156
  lines in 27 files, mostly `hash(into:)` and `_combine` naming their
  `inout` Hasher. swift-syntax `--structured`: 52 lines.

## 2026-11-02: ABI review

- **OPEN — fourteen ABI areas reviewed.** The ranked findings, each with a
  reproduction checked against the compiler, are in
  [ABI-REVIEW-2026-11-02.md](ABI-REVIEW-2026-11-02.md): 14 soundness
  classes (multi-register call results spelled as the whole call, a
  parked x20 taken as `self`, signed 32-bit comparisons rendered at 64
  bits, ObjC returns read from x0 whatever the encoding, the throw path's
  x0 in a return select, `swift_dynamicCast`'s Bool as the cast value,
  async calls laid out positionally, among others) and the completeness
  gaps. The earlier entry that says the `swift_willThrow` select "no
  longer reproduces" is stale: `plainThrow` at -O still renders it.
- **FIXED — one register of a multi-register call result read as the
  whole call** (ABI review item 1). The tracer now writes a Swift call's
  result only to the register its printed result type proves holds all
  of it (`callResultBank`): x0 for a scalar, class, `any Error`, Builtin
  scalar or one-word collection, v0 for a float. For any other type x0
  and x1 are the call's words, as a String's are: passed on together they
  are the value (`UTF8View.count.getter(String.utf8.getter(?, ?))`), and
  x0 alone renders `?` while the call keeps its statement. `mkPair(x).a +
  2` read `(mkPair(x) + 2)`; it reads `mkPair(x)` then `return (? + 2)`
  (`multiresult.swift`). A call handed a frame buffer in x8, a generic
  result and an unreadable result type claim nothing. Cost: in the
  swift-syntax dylibs about 130 enum-tag tests that named the raw
  register (`w9 >=ᵁ 4`) now read `? & 255`.
- **FIXED — a one-case enum counted as one register** (ABI review item 8).
  `isNoPayloadEnum`, the one-register gate for seeding, call layout and
  return registers, now needs two or more cases; a one-case enum is
  zero-sized, and the entry skips it. `oneMid(_ a: Int, _ o: One, _ b:
  Int)` read `return ((7 * arg0) - arg1)` with `arg1` the enum; it reads
  `- arg2`, and its caller `oneMid(arg0, arg1)` instead of `(arg0, arg1,
  ?)` (`onecase.swift`). Three `(? == ?)` on one-case enums now read
  `__derived_enum_equals()`, which takes no registers. swift-syntax
  dylibs: byte-identical.
- **FIXED — `swift_dynamicCast`'s Bool rendered as the cast value** (ABI
  review item 6). The conditional cast renders `((src as? T) != nil)`, its
  success, and the call is in `resultFitsInWord`; the value itself goes to
  the dest buffer. `isInt<T>(_ a: T) -> Bool { a is Int }` read `return (?
  as? Swift.Int)`, a Bool function returning an Optional
  (`dynamiccast.swift`). The unconditional form, which traps on failure,
  keeps `(src as! T)`. Fixtures: 6 lines (the new fixture and the
  Reconstruction `castToString` statements); swift-syntax byte-identical.
- **FIXED — a throw's x0 joined the return** (ABI review item 5, first
  half). `swift_willThrow` (Error.h:71), `swift_willThrowTypedImpl`
  (:116) and `swift_job_run` (Concurrency.h:1137) return nothing
  (`voidRuntimeCalls`), so x0 after one is no value. `plainThrow`
  (`throwselect.swift`, -O), whose throw shares the normal `ret`, read
  `return ((arg0 < 0) ? r1 : (arg0 + (arg0 << 1)))` with `r1 =
  swift_willThrow(r0)`; it reads `return ?`. The earlier entry that says
  this select "no longer reproduces at HEAD" was stale.
- **FIXED — a `ret` a throw shares returned `?`** (ABI review item 5,
  second half). The tracer now records x0 and v0 per incoming path at a
  shared `ret`, as it did x21, and an exit whose throwing paths
  `mergedThrowEnds` proves returns the value its normal paths agree on.
  `plainThrow` reads `return (arg0 + (arg0 << 1))`; `typedPick` (four
  builds) `return arg0`; the generic `transform` `return (… + 1)`.
  swift-syntax byte-identical.
- **MITIGATED — a parked x20 taken as `self`** (ABI review item 2). A
  callee's register summary now records whether its body may read the x20
  it is handed (`readsSelfRegister`: a read before any write, other than
  a prologue's save to the stack; an in-image call that does; or a call
  with no C arity, which may take it as `self`). An in-image callee that
  does not takes no `self`: `freshEnum` read `Mode.weight(self: r0, r0)`
  for a by-value enum method and reads `Mode.weight(r0)`
  (`parkedself.swift`). swift-syntax: 30 lines, each a `self:` dropped
  from a callee that never reads x20 (`sub_35e8(self:
  swift_allocObject(…), …)`, `Descriptor.init(self: …stringValue.getter())`
  for `init(rawValue: Int)`). Still OPEN: an out-of-image value method
  (`String._bridgeToObjectiveC(self: arg0)`) is decided by name.
- **FIXED — signed 32-bit comparisons rendered at 64 bits** (ABI review
  item 3). A w register reads as its zero-extended bits, so a signed order
  over two of them compared the wrong numbers: `cmp w9, w8; b.lt` with w8
  = -100000 read `… < 0xfffe7960`, the branch inverted for every
  non-negative sum, and `tbnz w0, #31` read `arg0 < 0`, the sign of an
  undefined high half (`signed32.c`). A signed order (LT/GE/GT/LE) at
  width 32 now goes through the exact `subtractionCondition`, MI/PL (the
  difference's sign) at every width, and a w sign-bit test sign-extends
  the low half; a value whose bit 31 is provably clear (a small mask, a
  small constant, a choice of them) is not extended, and a signed order
  prints a negative constant in decimal. Fixtures: 140 lines, 67 of them
  value-witness and Int32 sign tests `arg1 < 0` -> `((arg1 << 32) >>ˢ 32)
  < 0` (getEnumTagSinglePayload's count is `unsigned`); swift-syntax 218
  lines, the same shapes. The z3 condition harness covers only the text
  path; these tracer facts are checked by the fixture test alone.
- **FIXED — an Objective-C method's return read from x0 whatever its
  encoding** (ABI review item 4). The return is now read where the method
  encoding puts it: x0 for an integer, pointer or object, v0 for a lone
  `float`/`double` (a constant printed as its value), and nothing for a
  struct of floats, a 9-16-byte composite whose two ivars differ, or an
  x8 return. A tail call forwards a one-register result, or a float struct
  from a C function declared to return a struct (`return
  CGRectInset(…)`). `-(double)scaled:` read `return self` and reads
  `return (arg0 * self->_scale)`; `-(S5)big` and `-(CGRect)rect:` read
  `return ?` (`objcreturns.m`). Fixtures: 17 `return self` replaced by
  the true value (`return 2.5`, `(arg0 + arg0)`) or `?`; `rangeHead` and
  `rangeShifted`, one word of a two-word NSRange result, now `return ?`.
  swift-syntax byte-identical. OPEN: a tail branch in an x8-returning
  method still reads `return h(…)` when x8 is not proven forwarded.
- **FIXED — the x8 convention called a closure tuple or a nested
  collection type direct** (ABI review a3 #4). `isKnownDirectReturnType`
  kept its own type list, which took any type spelling ` -> ` as a closure
  and any `Swift.Dictionary<` prefix as the one-pointer collection, so
  `((Int) -> Int, (Int) -> Int, (Int) -> Int)` (six words) and
  `Dictionary<Int, Int>.Iterator` (40 bytes) were taken as returned in
  registers. It now asks `SwiftLowering`, the classification
  `swiftReturnRegister` uses (a93b674). Latent in the fixtures and the
  swift-syntax dylibs (byte-identical): the frame-slot escape rule masked
  it, and a forwarded result pointer exposed it (reported, a3).
- **FIXED — a collection, `any Error` or `AnyObject` parameter stopped
  seeding and call layout.** `scalarParameterClass` kept its own scalar
  list; it now asks `SwiftLowering` (a93b674), so a one-pointer
  collection, `any Error`, `AnyObject` and the Builtin scalars are one
  integer register, as a result of those types already was.
  `afterArray(_ xs: [Int], _ i: Int)` read `return ?` and reads `return
  (arg1 * 11)`; `firstCount<[Int]>()` reads `(arg0)`. swift-syntax: 160
  lines, calls laid out by their signatures: `nodesDescriptionAndCommon
  Parent<A>(_: [A], format: Bool)` lost a fabricated third argument
  (`(local, ?, 0)` -> `(local, ?)`), `_findStringSwitchCase(cases:
  string:)` gained its String as `?`, raw `x0 == x1` became `arg0 ==
  arg1`.
- **FIXED — async calls laid out by position** (ABI review item 7). An
  async callee's context is its `swiftasync` parameter (x22) and its
  formals take the ordinary registers (`define swifttailcc void @dbl(ptr
  swiftasync %0, double %1)`), unless an indirect result's buffer comes
  first (`@bigRes(ptr %0, ptr swiftasync %1, i64 %2)`). A callee whose
  result `SwiftLowering` proves direct is laid out as a synchronous one;
  any other shows its declared parameters, each `?`; a resume funclet,
  which takes only the context, is left as it was. `bumpG(?)` (x0 the
  callee context) reads `bumpG()`, `dbl(?)` reads `dbl(arg0)` from d0,
  `bigRes(?, arg0)` reads `bigRes(?)` (`asynccalls.swift`). Fixtures: 74
  lines, 20 `Task.yield(?)` -> `yield()` and hand-written leaves
  matching their declared parameters; swift-syntax byte-identical.
- **FIXED — inside an async function with an indirect result, `arg0`
  named the buffer** (a7 #2). Such a function takes the result's buffer
  in x0 before its formals, so an async function whose result
  `SwiftLowering` does not prove direct is not seeded: `bigRes(_ x: Int)
  async -> Big5` read `mem64[arg0] = x1` and reads `mem64[x0] = x1`.
  Fixtures: 6 lines, that function; swift-syntax byte-identical.
- **FIXED — unspecialized generic calls laid out by position** (ABI
  review item 11, first part). A generic function takes a generic value
  by address, one register, and its metadata and witness tables after the
  formals, so it is now laid out from its declared parameters and the
  metadata is not shown; a tuple result with a generic element takes its
  buffer first, from x0 (GenCall.cpp: `CanUseSRet = false` for a direct
  result beside an indirect one, or two indirect ones), so such a call
  shows its declared parameters as `?`. `identity<A>(local_20, 0x4010)`
  reads `identity<A>(local_20)`; `split<A>(local_18, local_20, ?,
  0x4010)` reads `split<A>(?, ?)` (`genericcalls.swift`). Fixtures: 30
  lines, `_hashValue<A>(local, 0x…)` -> `(local)`; swift-syntax 132 lines,
  `_print_unlocked<A, B>(…, 0x…)` without the metadata, Bool arguments
  typed (`rewrite<A>(…, 1)` -> `true`), `appendInterpolation<A>()` ->
  `(?)`.
- **FIXED — a `Tt` specialization read against its unspecialized
  parameters** (ABI review a8 #2). A generic specialization that drops
  the arguments its substitution made trivial prints like the declaration
  (the demangler's printer skips `DroppedArgument`), and
  `specializedSignature` declined on the dropped-argument node, so the
  call fell to position: `tt<Double>(Double.self, d, k)` read
  `tt<…>(arg0)`, `k` as the metatype and `d` gone. The substituted
  signature now drops those arguments: `tt<…>(arg1, arg0)`, d from d0 and
  k from x0 (`droppedmeta.swift`). Fixtures: that line; swift-syntax
  byte-identical.
- **FIXED — a vector lane move modelled as a whole move** (ABI review
  a12 #1, item 10). `ins`/`umov` canonicalize to `mov` with a lane
  operand, and the structured operand did not carry the lane, so `mov
  v0.d[1], x2` read as `v0 = x2`. Compiled code does this: the
  `storeEnumTagSinglePayload` value witnesses build a 16-byte payload
  with `mov v0.d[0], x11; mov v0.d[1], x10; str q0, [x9]` and read
  `mem128[arg0] = 0`, the last lane as the whole store. The operand now
  carries Capstone's `vector_index`, and a lane move is not modelled (the
  register is clobbered): `mem128[arg0] = q0`. Fixtures: 20 lines, six
  value witnesses in five fixtures and `vectorlanes.s`; swift-syntax
  byte-identical.
- **FIXED — `fmov` immediates read at the wrong precision or shape**
  (ABI review a2 #1, #3). A vector `fmov.2d v0, #3.0` fills every lane and
  was stored as one Double (lane 1 reading 0: `mem128[x0 + 0x10] =
  0x3ff0000000000000` in a compiled initializer); a Float vector read as
  a Double pattern; `fmov h1, #3.0` carried a Double's pattern, whose low
  16 bits rendered `0.0`. A 128-bit destination or a lane operand is now
  not modelled, an `h` destination takes the Float16 pattern, and a
  Float16 constant renders as its value: `half(_ h: Float16)` reads
  `return ((arg0 * 3.0) + 0.5)` and its caller `half(1.5)`
  (`fpimmediates.swift`). swift-syntax byte-identical.
- **FIXED — integer-to-float conversions lost their signedness and
  width** (ABI review a2 #4). `ucvtf` and `scvtf` were both `Double(x)`:
  `ucvtf d0, x0` read as a signed conversion (`Double(UInt(bitPattern:
  k))` rendered `Double(arg0)`, wrong for every negative k), and `scvtf
  d0, w0` converted a word's zero-extended bits (Int32 -1 as
  4294967295.0). `ucvtf` is now `unsignedToFloat`, rendered `Double(x)`
  only when x is a UInt or provably non-negative, else `Double(UInt(
  bitPattern: x))`; `scvtf` from a w register sign-extends
  (`intconvert.swift`). Fixtures: 7 lines, the -O typedScale `Double(arg1)`
  -> `Double(UInt(bitPattern: arg1))`, exact (the compiler chose `ucvtf`
  after proving n >= 0 on that path; a path-aware simplification is
  future work). swift-syntax byte-identical.

## 2026-11-03: whole-image runs on swift-syntax

Measured with release builds (`.build-release`, each binary copied out),
`/usr/bin/time -l` under `Tools/audit/guard.sh`, on the toolchain's
`lib/swift/host/libSwiftSyntax.dylib` and `libSwiftParser.dylib`. The host
was shared with other agents, so the figure is instructions retired (three
repeats spread 0.15%), not wall time. Baseline: origin/dev `20dcc5d`.

- **FIXED (speed): every method of a type rebuilt that type's accessor
  map.** `enrichCallArguments` built `selfAccessors` for each function
  whose `self` type is known by calling `ReferenceResolver.name(at:ownedBy:)`
  on every vtable method of the type, and that call demangles and splits
  every symbol folded onto the address. libSwiftSyntax's `SyntaxVisitor`
  has 880 `visit` methods whose default bodies fold up to 871 symbols onto
  one address, so the cost was methods x slots x folded symbols: a sample
  put 99% of the main thread in that initializer. `SelfMemberCache` on
  `PerFunctionContext` (one per image) now memoizes the map per type name
  and `name(at:ownedBy:)` per (address, type name); both are pure
  functions of the context's resolver and vtable index, and the cache is
  only looked up, never iterated. Instructions retired, before and after:

  | run | before | after | peak footprint |
  |---|---|---|---|
  | libSwiftSyntax `disasm --structured` | 4,199.6G | 642.4G (-84.7%) | 208 MB to 248 MB |
  | libSwiftSyntax `xrefs --unreferenced` | 4,109.4G | 565.5G (-86.2%) | 207 MB to 199 MB |
  | libSwiftParser `disasm --structured` | 241.9G | 241.9G | 70 MB to 71 MB |
  | libSwiftParser `xrefs --unreferenced` | 211.5G | 211.7G | 73 MB to 72 MB |

  Wall time on libSwiftSyntax `--structured` went from 254 s to 47 s.
  Every output is byte-identical (`cmp`), and `Tools/blast-radius.sh` over
  the 243 fixture inputs changed 0 lines in all four views.

- **FIXED (speed): `callResultBank` re-derived per call and re-parsed a
  regex each time.** The tracer asks where a callee's result is at every
  call on every fixpoint iteration, and `Disassembler.callResultBank`
  re-parsed the demangled name each time and evaluated the regex literal
  `#/(^|[^A-Za-z0-9_.])[A-Z][0-9]*($|[^A-Za-z0-9_])/#`, which Swift
  parses again on every evaluation: 20% of a libSwiftParser
  `--structured` sample, `Regex.init` alone 9.6%. `CallResultBankCache`
  on `PerFunctionContext` keeps the answer per callee name for the image
  (lookups only), and `containsGenericParameterToken` scans for the token
  by hand over `Character`s. A `Regex` is not `Sendable`, so it cannot be
  a static. `genericParameterTokenScanMatchesTheRegex` checks the scan
  against the regex on printed types and 3,000 short strings over the
  characters that decide it. Instructions retired, after the change above
  and after this one:

  | run | before | after | peak footprint |
  |---|---|---|---|
  | libSwiftParser `disasm --structured` | 241.9G | 191.3G (-20.9%) | 71 MB to 72 MB |
  | libSwiftParser `xrefs --unreferenced` | 211.7G | 161.1G (-23.9%) | 72 MB to 73 MB |
  | libSwiftSyntax `disasm --structured` | 642.4G | 587.5G (-8.5%) | 248 MB to 221 MB |
  | libSwiftSyntax `xrefs --unreferenced` | 565.5G | 510.9G (-9.7%) | 199 MB to 198 MB |

  Every output is byte-identical (`cmp`), and the fixture blast radius
  changed 0 lines in all four views.

- **FIXED (speed): every mangled-name pair walked the image's chains.**
  `MangledNamePair.referencesAreSound` (from `dba6e5e`) built a fresh
  `ChainedFixupTable` per lookup, and the first indirect (`\x02`) reference
  in a name walked every chain of the image. `renderValue` reaches it at
  each `__swift_instantiateConcreteTypeFromMangledName` call. On GoodLinks
  `xrefs --arch arm64 --unreferenced`, a sample put 3,534 of 3,960
  main-thread samples (89%) in `ChainedFixupTable.build`. The resolver's
  `chainedFixups`, built once and shared by every copy, now goes to
  `typeName(at:in:fixups:)` and `referencesAreSound` from all three
  callers. A caller with no resolver (the tests) still gets a fresh table.
  Instructions retired, against the change above:

  | run | before | after | peak footprint |
  |---|---|---|---|
  | GoodLinks `xrefs --unreferenced` | 14,989.4G | 1,473.9G (-90.2%) | 449 MB to 480 MB |
  | libSwiftParser `disasm --structured` | 191.3G | 191.7G | 72 MB to 72 MB |
  | libSwiftParser `xrefs --unreferenced` | 161.1G | 161.5G | 73 MB to 64 MB |
  | libSwiftSyntax `disasm --structured` | 587.5G | 586.9G | 221 MB to 210 MB |
  | libSwiftSyntax `xrefs --unreferenced` | 510.9G | 509.6G | 198 MB to 201 MB |

  GoodLinks wall time went from 1,605 s to 168 s. The swift-syntax dylibs
  hardly reach the check. Every output is byte-identical (`cmp`, GoodLinks
  included), and the fixture blast radius changed 0 lines in all four
  views. `EnumCaseIndex` and `MetadataSymbolizer` each still build their
  own table, at most two more walks per image. They are not hot: a 25 s
  sample of the start of the fixed GoodLinks run, which covers both index
  builds, has no `ChainedFixupTable` frame. Left as is.

- **FIXED (speed): the async funclet scan named every instruction.** In an
  image without the async hint sections (libSwiftSyntax and
  libSwiftParser have none), `AsyncFuncletIndex.build` scans every
  function, and for each instruction on each path it computed
  `branchTarget.flatMap(nameOf) ?? calleeName(of:)`. For a non-call,
  `calleeName` fell through to `parsedCalleeName`, which splits the
  instruction's text. The name is read only for a `.call`, so it is now
  computed only there. That was 13.6% of a libSwiftParser sample.
  Instructions retired, against the change above:

  | run | before | after | peak footprint |
  |---|---|---|---|
  | libSwiftParser `disasm --structured` | 191.7G | 176.5G (-7.9%) | 72 MB to 64 MB |
  | libSwiftParser `xrefs --unreferenced` | 161.5G | 146.1G (-9.5%) | 64 MB to 64 MB |
  | libSwiftSyntax `disasm --structured` | 586.9G | 557.6G (-5.0%) | 210 MB to 217 MB |
  | libSwiftSyntax `xrefs --unreferenced` | 509.6G | 479.5G (-5.9%) | 201 MB to 238 MB |

  Every output is byte-identical (`cmp`), and the fixture blast radius
  changed 0 lines in all four views. OPEN: the same scan still builds
  54 string keys per call (`pages["x\(n)"]` for n in 0...17), and it
  decodes each function a third time. Folding it into pass 1 would remove
  a whole-image decode and CFG build.

  Over the four changes, libSwiftSyntax `--structured` went from 4,199.6G
  to 557.6G instructions (-86.7%), its `xrefs` from 4,109.4G to 479.5G
  (-88.3%), libSwiftParser `--structured` from 241.9G to 176.5G (-27.0%)
  and its `xrefs` from 211.5G to 146.1G (-30.9%).
## 2026-11-03: typed returns that render `return ?`

Measured on the toolchain's `libSwiftCompilerPluginMessageHandling.dylib`
(`swiftdc disasm <lib> --structured --probe <file>`, the
`render.return-outcome` event's `status`), at 20dcc5d: of 1,425 return
outcomes, 513 void, 440 no-signature, 248 `unknown`, 179
`unsupported-layout-or-value`, 39 `recovered`, 5 `partial`. Causes, read
from each event's function in a plain listing (a type-and-shape
heuristic, so the bins are approximate):

- **FIXED (4e3efb9) — a String return was never read from its two
  words.** 37 of the 248 `unknown`. A literal, a String call's whole
  result or a String field of self is now the return. After: unknown
  248 -> 241, recovered 39 -> 46; over all four swift-syntax dylibs,
  unknown 972 -> 933, recovered 100 -> 139. Fixture `stringreturns.swift`.
- **OPEN — a value picked per path.** The 30 String returns left in the
  plugin library are CodingKey `stringValue` and enum `rawValue` getters:
  `csel x0, …; csel x1, …` chains over the case tag, so each word is a
  select, and two selects on the same condition were never paired into
  one `c ? "a" : "b"`. One-register scalars that join at a block (23,
  `mov w0, #0` / `mov w0, #1` before a shared `ret`) are the same cause.
- **OPEN — `unsupported-layout-or-value` is all throwing functions whose
  normal exit is not proven** (179 of 179). 119 `ret` straight after a
  throwing call, mostly protocol witnesses forwarding a `decode`; x21 at
  the `ret` is the callee's error, so the exit is the callee's outcome,
  `return try callee(…)`, which nothing models. The status name hides
  this; it reads as a layout gap.
- **OPEN — generic results** (102): `A`, `Optional<A>`, `A.Index`,
  returned through x8 with a layout only the caller's metadata fixes.
- **OPEN — Optional results** (38): a payload's tag or extra inhabitant
  is not modelled (SwiftLowering's `.direct`/`.unknown`).
- **OPEN — nominal structs, enums and existentials** (37) with no
  complete layout in the image, and **tuples** (11, such as
  `(bucket: _HashTable.Bucket, found: Bool)` in x0 and x1), which no
  direct path assembles.

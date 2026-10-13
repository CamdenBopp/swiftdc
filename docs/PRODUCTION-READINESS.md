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
  251 and 816 to 785 on three release apps. Value-type instance methods
  and getters, whose small `self` travels in x0 onward, remain positional.
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
  (String, aggregate, generic, `T?`, value-type methods, ObjC, C).
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
- **OPEN — `awaitedN` is bound for a generic or indirect async result.** The
  result is written into a context buffer, so x0 at the resume is not it.
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
- **OPEN — a call into a linker-deduplicated function is named after an
  arbitrary alias.** ld folds identical functions by default in a release link,
  so one address carries every folded symbol. In an -O probe (`func optK(_ k:
  K?) -> K? { k }` beside struct accessors), 11 symbols share one bare `ret` at
  0xa78; `optK`'s specialization calls it, and swiftdc renders that call as
  `Sync3.pair(arg0)` under `--pseudo` and `Sync3.P2.a.modify … .resume.0` under
  `disasm`. Neither is what the source called, and the two modes disagree.
  Repro: `nm libX.dylib | awk '$1=="<addr>"'` lists the aliases. The rendering
  needs a decision: decline (`sub_…` with a "folded: N functions" note), list the
  aliases, or prefer the one a specialization names.
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
- **PARTLY FIXED — `-f` cannot select a folded function, and its callers ignore the
  fold.** Selection is fixed: every symbol folded onto an address, raw or
  demangled, now selects it, on both the range matcher and the final filter
  (`everyFoldedSymbolSelectsItsFunctionIfPresent`, seen red; five fixture
  symbols had printed "No function matched"). Still open: naming a direct call
  into a folded address (needs the decline/list/rank decision). Original: The definition declines as `sub_5d8` with its candidates
  (`foldedByAddress`), but call sites name an arbitrary alias, and `disasm -f
  '$s1P7secondsySiAA7SecondsVF'` prints "No function matched" for a symbol in
  the export table: the empty-result class this project's rules forbid.
- **OPEN — a call to an address that also carries linker marker symbols is
  named after the marker.** TinyCC places `__start_text`, `__init_array_start`
  and friends on `add3`'s address; the function header declines
  (`sub_100001000`) but the call is annotated `→ _init_array_end`. Same class as
  the deduplicated-function alias entry above.
- **FIXED — a float argument to a call was not tracked.** -Onone
  `Double(f) * 1.5` rendered `(Swift.Double.init() * 1.5)`: the Float argument
  is in s0 and call sites read only general registers. Call sites now snapshot
  v0–v7, and a Swift callee whose parameters are proven one-register scalars
  takes its float slots from them (`Swift.Double.init(arg0)`,
  `mixed(arg0, 2.5, arg1)`; `CallArityTests`). Callees outside that layout
  (ObjC sends, C functions, multi-register parameters) still read x0–x7 only.
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

## 3. Robustness — what breaks it?

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
  | `ro.baseMethods` | `__objc_methlist`, `__objc_const`, `__objc_methname`; null |
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
| Instruction decode | `llvm-objdump` vs in-process Capstone | Two independent decoders exist; **nothing cross-checks them**. Both silent-truncation bugs found so far were in whichever decoder the other wasn't covering |
| Enum tag → case index | SIL (`swiftc -emit-sil`) | Used once, manually, to confirm the `rank` lowering |
| Field offsets | `__swift5_fieldmd`, computed offline | Runtime-exact by construction |
| Cross-image symbols | export trie | Used as the primary source |
| Stripped-binary names from metadata | the unstripped twin's symbol at the same address, demangled by `xcrun swift-demangle` | **In tests** — `MetadataNameOracleTests`, four stripped fixtures, overrides, same-simple-name classes, and folds required |
| Recovered semantics | the compiled function itself, called via `dlsym` | **In tests** — 1,264 comparisons at both `-Onone` and `-O`: 636 integer/boolean (catches an injected U1) and 628 floating point (catches a one-ULP constant error). Narrow: no strings, payload enums, or side effects |
| Async funclet grouping | the unstripped symbol table (`…TQ<n>_` / `…TY<n>_` suffixes) | **In tests** — parent, ordinal and kind of all 14 funclets on three builds, and the stripped build must match address for address; the code-only fallback is checked against the same oracle |
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


## 2026-10-13: scalar byte reversal

- **FIXED (working tree) — scalar REV results were unmodelled.** Model 32/64-bit
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

## 2026-10-13: ABI preservation

- **FIXED (working tree) — saved-register proofs account for overlapping store bytes.**
  `CalleeRegisterSummary` now invalidates the complete byte extent of stores,
  including narrow, unaligned and SIMD writes, and uses actual pair strides.
  Only full-width GPR stores can establish saved-entry facts. Indexed writes
  through a known stack base and unmodelled stack writes decline save proofs.
  In `abi_saved_slots.s`, two callers previously rendered `return arg0`,
  despite their fragments changing bytes in saved x19; both must decline.
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

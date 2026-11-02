# ABI review, 2026-11-02

Fourteen reviewers each probed one area of the arm64 Swift, Objective-C
and C calling conventions against swiftdc at 8c1f202 (plus the change
that became 78fa7ff). Every finding below has a reproduction compiled from
a probe source, with the truth taken from `-emit-ir`, clang `-S` or
`llvm-objdump`, never from swiftdc. Probes were kept outside the
repository; each item names the shape so it can be rebuilt as a fixture.

Ranked by how often the shape occurs in compiled code and how wrong the
render is. "Soundness" means a wrong value, name, argument or condition is
printed; "completeness" means something provable prints `?` or is
omitted.

## Soundness

1. **One register of a multi-register call result is spelled as the whole
   call.** `mkPair(x).a + 2` renders `(mkPair(x) + 2)`; a `{Int, Double}`
   result's d0 renders as the call; `if case .num(let n) = mkPE(x)` passes
   `r0`; the same for C 16-byte structs and ObjC `NSRange` sends.
   `ValueTracking.swift` post-call transfer writes `.callResult` into x0
   and v0 for every non-void callee; only tuples, String and C prototypes
   are excluded. Write it only when the result is a proven single-register
   scalar of that bank.
2. **A parked x20 becomes `self`.** Any Swift call after a callee-saved
   temporary lands in x20 takes `self:`: a non-mutating enum method
   (`Mode.weight(self: r0, r0)`, its real self dropped), a one-word struct
   method (`W.g(self: arg1)`), a generic free function (`gen<A>(self: …)`,
   the identifier test rejects `<`), local functions (`inner #1 (self: …)`),
   a specialization whose metatype is Dead, `RandomNumberGenerator.next`,
   `String._bridgeToObjectiveC(self: arg0)`. Take x20 as `self` only when
   the callee's body is proven to read it before writing it, or the value
   is a proven address (mutating); decline out-of-image value methods.
3. **Signed 32-bit comparisons render at 64 bits.** `cmp w9, w8; b.lt`
   with `w8 = -100000` renders `… < 0xfffe7960`, inverting the branch for
   every non-negative sum; `cmp w0, #0; cinc ge` renders `>= 0`, always
   true; `tbnz w0, #31` renders `arg0 < 0` on an undefined high half.
   `comparisonValue` ignores width 32 and the w sign-bit test does not
   sign-extend. The z3 harness covers only the text path; extend it to the
   tracer's facts.
4. **An Objective-C method's return is read from x0 whatever its
   encoding.** `-(double)scaled:` and `-(CGRect)…` render `return self`; a
   24- or 40-byte struct written through x8 renders `return self` or a
   callee's result; a tail branch in an x8-returning method renders
   `return h(…)` for a void `h`. Classify the encoded return (x0, v0-v3,
   x0+x1, x8) and decline the rest.
5. **The error path's x0 leaks into the return.** `plainThrow` renders
   `return ((arg0 < 0) ? r1 : (arg0 + (arg0 << 1)))` where `r1 =
   swift_willThrow(r0)`: `swift_willThrow` is void and that path throws.
   The FIXED entry that says this select no longer reproduces is stale.
   Mark `swift_willThrow` void and build an exit's value only from its
   non-throwing predecessors.
6. **`swift_dynamicCast`'s Bool renders as the cast value.** `a is Int`
   renders `return (? as? Swift.Int)`; `if let _ = a as? String` renders
   `return r0` for a Bool function. Render it as a success test; keep
   `(x as? T)` for the casts that return the object.
7. **Async callees are laid out positionally.** `await bumpG(?)` for a
   function with no parameters (x0 is the callee context), `await dbl(?)`
   dropping the Double in d0, `await bigRes(?, arg0)` showing the x0 result
   buffer as a parameter, `leafB(awaited1)` dropping x1. Inside an async
   function with an indirect result, `arg0` names the buffer. Give async
   calls a layout (result in x0, formals from x1, self x20, floats in v),
   or decline the arity.
8. **A single-case enum counts as one register.** It is zero-sized:
   `oneMid(_ a: Int, _ o: One, _ b: Int)` renders `7 * arg0 - arg1` with
   `arg1` the enum, and callers shift every later argument.
9. **Narrow integers.** A non-constant Int8/16/32 return renders unnarrowed
   (`return takeInt(arg0 + 72)` for a UInt16); C constants render as their
   zero-extended register (`close(0xffffffff)`, `printf(…, 0xffffffff)` for
   `%d -1`). Record C prototype widths and printf conversion widths.
10. **Vector registers.** `mov v0.d[1], x2` is modelled as a whole move
    (`mem128[p] = arg2`), and `mov x0, v1.d[1]` reads the low lane; a vector
    `fmov.2d #3.0` stores one Double (lane 1 reads 0); Float16 constants read
    `0.0` or a Double pattern; `ucvtf` renders `Double(x)` for an unsigned
    convert; v8-v15 keep their upper halves across a call.
11. **Generic and specialization layouts.** A generic function with a
    direct and an indirect result takes the buffer in x0, read as the first
    formal (`split<A>(local_18, local_20, ?, …)`); a `Tt` specialization
    drops metatype arguments but prints like `Tg`; a closure-propagated
    specialization's survivors are matched to the original parameter list.
12. **Positional fallback for struct, SIMD and tuple parameters.**
    `fMix(Mix(i: k, d: 1.5, j: 7), 2.0)` renders `fMix(arg0, 7)`, the 7
    read as the Double. Render one `?` per declared parameter instead.
13. **Body-reads arity sees only x0-x7.** `take10(1…10)` renders eight
    arguments and `takef3` (three floats) renders `()`; record entry reads
    of v0-v7 and the incoming stack area.
14. **Smaller shapes.** An -Onone payload-enum switch reuses `w8` for two
    reloaded values, making a live branch read dead; the untyped-float ObjC
    guard misses a float set in a predecessor block or by a call
    (`[p zput:7 at:?]`); `objc_opt_new` renders `[[X alloc] init]`; void
    runtime calls feed `swift_task_asyncMainDrainQueue(swift_job_run(…))`;
    `swift_errorInMain()` and `swift_projectBox()` drop their argument;
    `type metadata for Any + 8` is Any's metadata. Assembly-only: flags read
    across a call in the text path, a `blr` to a resolved target skips its
    clobber summary, x18 and below-sp slots kept across calls, an escaped
    local's region cut at another field's taken address.

## Completeness

- **Swift errors:** give x21 after a throwing call a value of its own, so
  `try?`, do/catch and propagation render (`error == nil ? r0 + 1 : -7`
  now reads `return ?`); exempt the `[x29-8]` frame store from the async
  context escape check, which blocks ResumeParent in every framed funclet.
- **Async:** follow async function pointer records in `__TEXT,__const`
  (target and context size); keep context slots across a store into a
  fresh `swift_allocError` box.
- **Value witness calls:** name `[metadata-8] → [vwt+k] → blr` by its
  ValueWitness.def slot (156 sites in the swift-syntax dylibs).
- **Layouts:** fields reached through a `…Wvd` field-offset global, inherited
  Swift superclass fields, a class parameter's fields in a free function,
  enum case names in tests and field stores, specialized generic layouts.
- **Tail calls and closures:** a scalar tail call whose types differ in
  spelling prints no `return`; a partial-apply forwarder's tail call
  likewise; a closure body's captured arguments are dropped at its call;
  a closure-propagated specialization's printed name has an unclosed `[`
  that defeats `splitSignature`, losing its result.
- **Objective-C:** `super` sends ignore the superclass's encoding;
  variadic selectors outside four suffixes drop their stack arguments
  (`stringByAppendingFormat:`, `raise:format:`, NSAssert's
  `description:`); a class object loaded by `adrp/add` prints as hex; a
  receiver passed straight through prints `?`.
- **C:** SDK prototypes with stack parameters read only registers;
  non-format variadics (`open`, `fcntl`) drop their stack argument with no
  `…`.
- **Floating point:** `Int(Double)` at -O renders `return ?` after its
  range checks; fcmp-driven selects decline (known).

## Checked and found correct

Separate x and v counters at entry and call; Optional scalar packing
(`Int32?` tag at bit 32, `Int?` two registers); fixed-footprint skips at
entry; StaticString straddling x6/x7; nine-Int stack spill; `__int128`
pairs; mutating `self` in x20; resilient value self by address; class
methods; funclet grouping and awaited results; no stale value across a
suspension; `try!`; `swift_willThrow` reads x21; the 95 `knownCArity`
entries in the signature table; ObjC HFA and stack packing for typed
sends; SwiftLayout offsets for every probed field type; x9/x10/x16/x17
dropped after calls and x19/x20/d8 low half kept.

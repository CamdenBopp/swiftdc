# ABI completeness sprints

The ordered queue for closing swiftdc's Swift ABI coverage on Darwin arm64,
one sprint at a time. A sprint is one provable behaviour that lands as one
commit. This file is the queue and its status. The detail for each sprint
(the compiler rule, the swiftdc change site, a fixture sketch, the expected
render before and after, negative controls and mutations) is in the four
card files under
[research/abi-sprints-2026-11-23](research/abi-sprints-2026-11-23/).

It refines the batches of [ABI-CLOSURE-PLAN.md](ABI-CLOSURE-PLAN.md) and
keeps the item IDs of its eight audits (L, M, G, C, A, E, F, O, U), so a
sprint closes part of a named audit item. `X` sprints come from open
entries in [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md) that no audit
item owns.

## What the cards are, and are not

The cards were written on 2026-11-23 from a source read of swiftdc at
`ca9eef5` and of the Swift compiler at `1b7bd8e`. That is not the plan's
pin: Swift 6.4.2 at `83eb1244` is kept under `work/abi-gap-audit/`, and a
card's compiler citation is re-read against the pin before its sprint
lands. Clang's Swift calling convention and LLVM's AArch64 backend were not
read; cards that rest on them say so.

No card was compiled or run. Every "before" render is a prediction and
every "possibly wrong" classification is an inference from code. Across
the 84 audit items the read found none fully closed, 43 partially closed,
14 safely declined and 27 possibly wrong. A sprint's first step replaces
the prediction with a measurement.

## How a sprint runs

1. **Reproduce.** Reduce the card's sketch to a fixture and render it with
   the release binary of the current tip. Record what it prints.
2. **Decide.** A wrong render is a soundness sprint and lands a fix. A
   decline is a completeness sprint and lands the recovery. A phase 1
   candidate that cannot be made to render wrong lands its fixture as a
   negative control, and the status says "guarded".
3. **Fix** one behaviour, in the consumer the card names, at -Onone, -O and
   -Osize.
4. **Prove every test red** by mutating each independent gate separately,
   with a rebuild between mutations.
5. **Measure** the full enforcing suite and the blast radius against the
   tip, and explain every changed line.
6. **Commit** with the readiness record, set the status here to the commit
   hash, and publish through `Tools/integration-gate.sh --push`.

A sprint that grows past one behaviour is split, and the new sprint takes
the next free letter under the same item ID. A sprint blocked on evidence
the binary does not hold is marked "declined" with the reason: it stays
outside demonstrated completeness.

## Phase 1: suspected wrong output

These jump the queue. Each is a place where the source read found a
premise that could print a false value, receiver, argument, type or exit.
They are ordered by how much ordinary Swift and Objective-C code the
premise touches.

| # | Sprint | Behaviour | Axis | Size | Status |
|---|---|---|---|---|---|
| 1 | [G01-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Keep a source metatype argument visible | soundness | M | fixed in `c3c80c3`: reproduced, see [readiness](PRODUCTION-READINESS.md#2026-11-23-sprint-g01-a-a-metatype-argument-dropped-from-its-call) |
| 2 | [G06-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Do not print a generic cast with a truncated target | soundness | S | fixed in `a16d9d0`: reproduced, see [readiness](PRODUCTION-READINESS.md#2026-11-23-sprint-g06-a-a-cast-target-cut-short) |
| 3 | [E05-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Keep shared cleanup before throw | soundness | M | fixed by declining in `c6f6e08`: reproduced, see [readiness](PRODUCTION-READINESS.md#2026-11-23-sprint-e05-a-a-throw-printed-ahead-of-work-it-shares) |
| 4 | [E07-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Retain trapping-tail outcome uncertainty | soundness | S/M | fixed in `3625d5b`: reproduced in a stripped image, see [readiness](PRODUCTION-READINESS.md#2026-11-23-sprint-e07-b-a-tail-into-a-body-that-may-not-return) |
| 5 | [F04-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Never fold a virtual tail through a base implementation's body | soundness | S | guarded: not reproduced, see [readiness](PRODUCTION-READINESS.md#2026-11-23-sprint-f04-a-a-virtual-tail-is-not-folded-through-the-base-body) |
| 6 | [C10-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Reject a storage property's function type as its entry signature | soundness | S | fixed in `e4a5913`: reproduced, see [readiness](PRODUCTION-READINESS.md#2026-11-23-sprint-c10-a-a-propertys-function-type-read-as-its-accessors-signature) |
| 7 | [O06-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Require provider proof before preserving fields across access markers | soundness | S | fixed in `4fb7ead`: reproduced with an in-image twin, see [readiness](PRODUCTION-READINESS.md#2026-11-23-sprint-o06-a-a-field-carried-across-an-access-markers-name-twin) |
| 8 | [E10-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Qualify error-runtime helpers | soundness | S | fixed: reproduced with authored assembly only, see [readiness](PRODUCTION-READINESS.md#2026-11-23-sprint-e10-a-error-runtime-helpers-recognized-by-prefix) |
| 9 | [E10-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Make willThrow evidence path-local | soundness | S/M | open |
| 10 | [O01-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Hide runtime calls only under an exact effect contract | soundness | S | open |
| 11 | [F05-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Prove the dispatcher before interpreting an Objective-C send | soundness | M | open |
| 12 | [F06-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Stop deriving objc_direct from missing metadata | soundness | S | open |
| 13 | [F01-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Reject address-shaped x20 as external nominal Self proof | soundness | S | open |
| 14 | [E07-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Propagate a callee's no-success result | soundness | M | open |
| 15 | [E03-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Require a proven direct typed-error carrier | soundness | S/M | open |
| 16 | [M04-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Keep pointer reach past outgoing stack holes | soundness | M | open |
| 17 | [L03-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Preserve an FP barrier when counting integer pieces | soundness | M | open |
| 18 | [L06-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Bound recursive Optional direct-result claims | soundness | S/M | open |
| 19 | [M02-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Include a proven async context in unknown-edge reach | soundness | M | open |
| 20 | [M01-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Decline ordinary preservation for an unproved nondefault convention | soundness | M | open |
| 21 | [A02-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Stop entry-slot seeds at unproved child effects | soundness | S/M | open |
| 22 | [A08-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Qualify rendered runtime-hop roles | soundness | S/M | open |
| 23 | [C06-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Separate a placed capture word from its source value category | soundness | M | open |
| 24 | [G04-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Require enum evidence for enum-only witness names | soundness | S | open |
| 25 | [C07-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Make an unsupported specialization contract explicitly unavailable | soundness | M | open |
| 26 | [O01-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Derive direct runtime result ABI from an exact declaration | soundness | S | open |
| 27 | [F10-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Provider-qualify the void-runtime result discard | soundness | S | open |
| 28 | [M07-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Separate authenticated slot identity from invocation proof | soundness | M | open |
| 29 | [C06-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Validate repeated propagated-closure roots | soundness | S | open |
| 30 | [C09-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Decline ordinary function directness for differentiable products | soundness | S | open |
| 31 | [O02-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Render the producer once through a tail-called retain | soundness | S | open |
| 32 | [X08](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Distinguish empty render causes without claiming purity | soundness | S | open |

## Phase 2: completeness

The four domains in rotation, each in the order its card file recommends,
which already respects the dependencies inside a domain. The rotation is
the default; when a real binary shows one decline dominating, that sprint
moves up and the move is recorded here.

| # | Sprint | Behaviour | Axis | Size | Status |
|---|---|---|---|---|---|
| 33 | [L02-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Preserve singleton enum source slots at calls | completeness | S | open |
| 34 | [C01-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Place an ordinary thick function argument as a pair | completeness | M | open |
| 35 | [E12-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Retain exact runtime terminal attributes | soundness | S | open |
| 36 | [F09-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Recover the declared width of one scalar C result | completeness | M | open |
| 37 | [L01-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Keep a Float16 producer when forwarding its FP result | completeness | S | open |
| 38 | [C01-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Preserve a thick function result's code/context pairing | completeness | M | open |
| 39 | [E12-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Cut only proven normal continuations | soundness | M | open |
| 40 | [F01-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Place an ordinary direct value receiver from ordered pieces | completeness | M | open |
| 41 | [L01-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Seed a one-Float16 stored field | completeness | S | open |
| 42 | [C02-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Seed a neutral closure-context role at a proved entry | completeness | M | open |
| 43 | [E10-c](research/abi-sprints-2026-11-23/03-async-errors.md) | Render a proved untyped error value without requiring its hook | completeness | S/M | open |
| 44 | [F01-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Distinguish thin value metatype from class metatype context | completeness | M | open |
| 45 | [L01-c](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Place Unicode.Scalar as its one narrow integer piece | completeness | S | open |
| 46 | [C03-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Type one concrete captured field from descriptor plus layout evidence | completeness | M | open |
| 47 | [A05-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Recover a suspension-free async scalar return | completeness | S/M | open |
| 48 | [F02-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Recover read-only indirect Self without inventing mutation | completeness | M | open |
| 49 | [L01-d](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Place Unmanaged without inventing ownership | completeness | S | open |
| 50 | [C03-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Forward one proven scalar capture through a partial-apply thunk | completeness | M | open |
| 51 | [E01-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Prove compare-plus-branch error outcomes | completeness | S/M | open |
| 52 | [F02-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Apply a specialized Self transformation before placement | completeness | M | open |
| 53 | [L01-e](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Seed one typed pointer field in a direct struct | completeness | S/M | open |
| 54 | [C03-c](research/abi-sprints-2026-11-23/02-generics-closures.md) | Preserve the physical input layout of a merged closure | completeness | M | open |
| 55 | [E02-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Attach a versioned untyped error token to a call | completeness | M | open |
| 56 | [F03-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Seed a nonallocating class initializer's instance receiver | completeness | M | open |
| 57 | [L03-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Seed nested single-field projections from ordered pieces | completeness | M | open |
| 58 | [G01-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Emit canonical scalar generic requirements in one ordered plan | completeness | M | open |
| 59 | [A01-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Share bounded region dependency loading | completeness | M | open |
| 60 | [F03-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Carry allocator metatype without labeling it instance self | completeness | S | open |
| 61 | [L02-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Keep production empty-struct layout evidence | completeness | S/M | open |
| 62 | [G01-c](research/abi-sprints-2026-11-23/02-generics-closures.md) | Fulfill a generic metadata requirement from a nominal parameter | completeness | M | open |
| 63 | [A05-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Recover nonsending formal locations only from an independent prefix proof | completeness | M | open |
| 64 | [F03-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Distinguish destroying from deallocating entries | completeness | M | open |
| 65 | [L07-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Project a one-field nominal direct result | completeness | M | open |
| 66 | [G01-d](research/abi-sprints-2026-11-23/02-generics-closures.md) | Account for early metadata of an indirect nominal self | completeness | M | open |
| 67 | [E03-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Map one direct typed-error payload from the combined schema | completeness | M | open |
| 68 | [F03-d](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve a self-returning callee's result at a later store | completeness | S | open |
| 69 | [L08-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Continue the other bank after one bank spills | completeness | M | open |
| 70 | [G01-e](research/abi-sprints-2026-11-23/02-generics-closures.md) | Place a scalar hidden generic role after GP exhaustion | completeness | M | open |
| 71 | [E04-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Recover a fixed typed-error buffer on its throw edge | completeness | M | open |
| 72 | [F05-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Recover a selector declaration through proved receiver ancestry | completeness | M | open |
| 73 | [L08-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Read packed narrow outgoing parameters by byte interval | completeness | M | open |
| 74 | [G02-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Distinguish a class archetype reference from an opaque value address | completeness | M | open |
| 75 | [E05-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Retain correlated outcome through a merged select | completeness | M | open |
| 76 | [F06-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Recover positively proved objc_direct layout | completeness | M | open |
| 77 | [L08-c](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Seed one incoming stack scalar from entry-SP coordinates | completeness | M | open |
| 78 | [G02-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Name the output destination of one opaque generic result | completeness | M | open |
| 79 | [A05-c](research/abi-sprints-2026-11-23/03-async-errors.md) | Project a two-GP awaited result | completeness | M | open |
| 80 | [F08-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Reconstruct one complete GP aggregate message result | completeness | M | open |
| 81 | [L08-d](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Place a split two-word Swift String formal | completeness | M | open |
| 82 | [G02-c](research/abi-sprints-2026-11-23/02-generics-closures.md) | Place one formal indirect result beside a direct result | completeness | M | open |
| 83 | [A05-d](research/abi-sprints-2026-11-23/03-async-errors.md) | Project a mixed-bank awaited result | completeness | M | open |
| 84 | [F08-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Reconstruct one HFA message result | completeness | M | open |
| 85 | [L01-f](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Place Int128 as a wide piece, not a scalar whitelist entry | completeness | M | open |
| 86 | [G02-d](research/abi-sprints-2026-11-23/02-generics-closures.md) | Keep two indirect result destinations distinct | completeness | M | open |
| 87 | [A05-e](research/abi-sprints-2026-11-23/03-async-errors.md) | Name a by-address awaited result after proven initialization | completeness | M | open |
| 88 | [F08-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve machine-proved nil-path indirect result initialization | completeness | M | open |
| 89 | [L04-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Place an ordinary labeled tuple formal by its SIL abstraction | completeness | M | open |
| 90 | [C07-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Recover one scalar Dead-argument transformation | completeness | M | open |
| 91 | [E09-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Separate direct typed outcomes across an await | completeness | M | open |
| 92 | [F05-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Recover struct-taking sends only when a call-site declaration becomes applicable | completeness | M | open |
| 93 | [L04-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Flatten a tuple stored as one struct field | completeness | M | open |
| 94 | [C07-c](research/abi-sprints-2026-11-23/02-generics-closures.md) | Place retained self after a method becomes thin | completeness | M | open |
| 95 | [E09-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Carry an indirect typed error through await | completeness | M/L | open |
| 96 | [O05-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Initialize destination storage through a proved copy witness | completeness | M | open |
| 97 | [L05-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Admit a frozen cross-module value only with boundary evidence | completeness | M | open |
| 98 | [C07-d](research/abi-sprints-2026-11-23/02-generics-closures.md) | Recover a merged specialization's body-proven appended operand | completeness | M | open |
| 99 | [A07-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Read a successful Task.value result buffer | completeness | M | open |
| 100 | [O05-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Expire source storage after a proved take | completeness | M | open |
| 101 | [L05-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Place one ordinary indirect output beside a direct result | completeness | M | open |
| 102 | [C05-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Prove both boundaries of one synchronous reabstraction thunk | completeness | M | open |
| 103 | [A07-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Read an async-let get result | completeness | M | open |
| 104 | [O05-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Replace live destination state through assign-with-copy | completeness | M | open |
| 105 | [L07-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Keep two direct result projections tied to one call | completeness | M | open |
| 106 | [C04-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Recover one C function-pointer formal without a context word | completeness | M | open |
| 107 | [A04-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Preserve one owner slot across an exact ordinary awaited body | completeness | M | open |
| 108 | [O05-d](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Expire storage and aliases after destroy | completeness | M | open |
| 109 | [L06-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Place Optional<Float16> payload and tag | completeness | S/M | open |
| 110 | [C04-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Recover a block invoke's implicit object argument | completeness | M | open |
| 111 | [A04-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Join two ordinary-await results in order | completeness | M | open |
| 112 | [O05-e](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Render a proved outlined copy as destination assignment | completeness | S | open |
| 113 | [L06-c](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Decode one fixed single-payload enum's register tag | completeness | M | open |
| 114 | [G08-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Decode a descriptor-backed metadata accessor's key operands | completeness | M | open |
| 115 | [A07-c](research/abi-sprints-2026-11-23/03-async-errors.md) | Consume an async-let result exactly once | completeness | M | open |
| 116 | [O05-f](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Mark indirect result initialized only on its producing outcome | completeness | M | open |
| 117 | [L06-d](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Decode one two-payload enum's proven common tag bits | completeness | M | open |
| 118 | [G08-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Track metadata response state separately from its pointer | completeness | M | open |
| 119 | [A07-d](research/abi-sprints-2026-11-23/03-async-errors.md) | Preserve async-let finish cancellation and destruction | completeness | M | open |
| 120 | [F07-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Prove initializer adoption through a private O0 ARC local | completeness | M | open |
| 121 | [L09-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Place one Swift SIMD2<Float> without scalarizing it | completeness | M | open |
| 122 | [G03-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Name a generic witness slot without a method-name descriptor | completeness | S | open |
| 123 | [A07-e](research/abi-sprints-2026-11-23/03-async-errors.md) | Recover immediate continuation completion | completeness | M | open |
| 124 | [F07-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Prove adoption through an exact objc_storeStrong helper | completeness | M | open |
| 125 | [L09-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Keep SIMD3 padding outside source value lanes | completeness | M | open |
| 126 | [G03-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Follow one inherited protocol witness-table path | completeness | M | open |
| 127 | [A07-f](research/abi-sprints-2026-11-23/03-async-errors.md) | Join delayed continuation completion with the inline case | completeness | M | open |
| 128 | [F07-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve legacy Super's search-start distinction | completeness | M | open |
| 129 | [L10-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Place one foreign small GP record with structured provenance | completeness | M | open |
| 130 | [G03-c](research/abi-sprints-2026-11-23/02-generics-closures.md) | Follow one conditional conformance table identity | completeness | M | open |
| 131 | [A07-g](research/abi-sprints-2026-11-23/03-async-errors.md) | Distinguish group-next nil, value and error | completeness | M | open |
| 132 | [F07-d](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Track class-method super search through metaclasses | completeness | M | open |
| 133 | [L10-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Preserve foreign HFA whole-group exhaustion | completeness | M | open |
| 134 | [G04-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Preserve initialized-copy witness destination identity | completeness | M | open |
| 135 | [A07-h](research/abi-sprints-2026-11-23/03-async-errors.md) | Model group wait-all completion without an invented value | completeness | M | open |
| 136 | [F04-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Recover resilient super dispatch by method descriptor | completeness | M | open |
| 137 | [L11-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Start Darwin unnamed arguments after named stack extent | completeness | M | open |
| 138 | [G04-c](research/abi-sprints-2026-11-23/02-generics-closures.md) | Invalidate source initialization after a proved take witness | soundness | M | open |
| 139 | [E06-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Recover try? optional outcomes | completeness | M | open |
| 140 | [F04-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Keep witness declaration ABI independent of implementation identity | completeness | M | open |
| 141 | [M02-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Give a proven coroutine role its own input reach | soundness | M | open |
| 142 | [G05-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Select the correct table in a two-protocol existential | completeness | M | open |
| 143 | [E06-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Preserve catch dispatch and error cleanup | completeness | M | open |
| 144 | [O02-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Keep observable last-release ordering | soundness | M | open |
| 145 | [M03-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Preserve a proved low SIMD slice across an upper-lane-only write | completeness | M | open |
| 146 | [G05-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Preserve out-of-line existential payload identity | completeness | M | open |
| 147 | [E06-c](research/abi-sprints-2026-11-23/03-async-errors.md) | Distinguish forced-try trap from catch | completeness | S/M | open |
| 148 to 153 | [O03-a through O03-f](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | One native weak-slot transition per commit | completeness | S each | open |
| 154 | [M05-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Prove one additional complete framed forwarding shape | completeness | M | open |
| 155 | [G05-c](research/abi-sprints-2026-11-23/02-generics-closures.md) | Place an existential metatype's metadata and tables | completeness | M | open |
| 156 | [E08-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Forward an untyped throwing branch tail | completeness | M | open |
| 157 | [F12-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Route unknown-object weak storage without interpreting its bits as native | completeness | M | open |
| 158 | [M06-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Keep coroutine partial return distinct from function completion | soundness | M | open |
| 159 | [G06-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Place a scalar following a proved resilient indirect formal | completeness | M | open |
| 160 | [E08-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Forward typed errors without losing reabstraction | completeness | M | open |
| 161 | [O03-g](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve checked-unowned upgrade's possible trap | completeness | M | open |
| 162 | [M07-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Require a matching authenticated return token | soundness | M | open |
| 163 | [G06-c](research/abi-sprints-2026-11-23/02-generics-closures.md) | Preserve a generic opaque factory's result destination | completeness | M | open |
| 164 | [E11-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Recover foreign integer-sentinel error policy | completeness | M | open |
| 165 | [F12-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Keep unsafe unowned transport separate from checked storage | soundness | S | open |
| 166 | [M08-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Intersect effects across a backdeployment alternative | soundness | M | open |
| 167 | [G08-c](research/abi-sprints-2026-11-23/02-generics-closures.md) | Name one field selected by a dynamic field-offset vector | completeness | M | open |
| 168 | [E11-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Recover foreign nil-result error policy | completeness | S/M | open |
| 169 | [O04-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve the decline for ownership distinctions erased before IRGen | soundness | S | open |
| 170 | [M08-b](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Expire exact-body effects at a replacement chain | soundness | M | open |
| 171 | [G07-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Recover a scalar class metadata argument after pack lengths | completeness | M | open |
| 172 | [E11-c](research/abi-sprints-2026-11-23/03-async-errors.md) | Recover foreign nonnil-error policy | completeness | S/M | open |
| 173 | [O04-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Retain a dependent address's proved base lifetime | completeness | M | open |
| 174 | [M10-a](research/abi-sprints-2026-11-23/01-lowering-machine.md) | Select one target-dependent effect from artifact facts | soundness | M | open |
| 175 | [G07-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Keep an invocation's pack shape separate from metadata-pack identity | completeness | M | open |
| 176 | [A06-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Bind witness async code and context size to one descriptor | completeness | M | open |
| 177 | [O06-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Pair a dynamic access token with its actual end | completeness | M | open |
| 178 | [G07-c](research/abi-sprints-2026-11-23/02-generics-closures.md) | Resolve a witness-pack element using the matching shape and index | completeness | M | open |
| 179 | [A06-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Bind an async class override descriptor | completeness | M | open |
| 180 | [O06-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve signed-access temporary writeback | completeness | M | open |
| 181 | [G07-d](research/abi-sprints-2026-11-23/02-generics-closures.md) | Preserve value-pack element addresses as an address array | completeness | M | open |
| 182 | [A02-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Admit byte-accurate scoped transport state | completeness | M | open |
| 183 | [F11-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Identify a global block literal and its invoke target | completeness | M | open |
| 184 | [G07-e](research/abi-sprints-2026-11-23/02-generics-closures.md) | Gate one generic value-parameter role by descriptor version | completeness | S/M | open |
| 185 | [A08-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Establish one versioned switch-effect contract | completeness | M/L | open |
| 186 | [F11-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Identify a stack block from reaching header stores | completeness | M | open |
| 187 | [C08-a](research/abi-sprints-2026-11-23/02-generics-closures.md) | Restore one synchronous generic closure binding from its context | completeness | M | open |
| 188 | [F11-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Recover one scalar block capture at its proved field offset | completeness | M | open |
| 189 | [C08-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Associate a generic async forwarder's descriptor with its binding context | completeness | M | open |
| 190 | [F11-d](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Model block heap copy as a new storage identity | completeness | M | open |
| 191 | [C10-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Give a key-path getter its own boundary | completeness | M | open |
| 192 | [A07-i](research/abi-sprints-2026-11-23/03-async-errors.md) | Preserve cancellation callback write reach | completeness | M | open |
| 193 | [F11-e](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Apply block invocation's hidden first operand and result schema | completeness | M | open |
| 194 | [C10-c](research/abi-sprints-2026-11-23/02-generics-closures.md) | Give a key-path setter its own value/base boundary | completeness | M | open |
| 195 | [A07-j](research/abi-sprints-2026-11-23/03-async-errors.md) | Retire task-backed coroutine storage with through-dealloc | completeness | M | open |
| 196 | [F11-f](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Keep C callback arguments independent of Swift closure context | completeness | M | open |
| 197 | [C10-d](research/abi-sprints-2026-11-23/02-generics-closures.md) | Give key-path index equality its two-packet boundary | completeness | S/M | open |
| 198 | [A05-f](research/abi-sprints-2026-11-23/03-async-errors.md) | Select the SwiftTail call-preservation contract | completeness | M | open |
| 199 | [F11-g](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve argument/result conversion across a representation-changing thunk | completeness | M | open |
| 200 | [C10-e](research/abi-sprints-2026-11-23/02-generics-closures.md) | Give key-path index hash its packet/size boundary | completeness | S/M | open |
| 201 | [A07-k](research/abi-sprints-2026-11-23/03-async-errors.md) | Recognize one SwiftCoro activation boundary | completeness | M/L | open |
| 202 | [F10-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Retain foreign ownership attributes in the boundary fact | completeness | M | open |
| 203 | [C10-f](research/abi-sprints-2026-11-23/02-generics-closures.md) | Resolve one serialized generic key-path binding | completeness | M | open |
| 204 | [F10-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Correlate an imported NSError outcome with its actual out parameter | completeness | M | open |
| 205 | [C09-b](research/abi-sprints-2026-11-23/02-generics-closures.md) | Preserve differentiable original/JVP/VJP component identity | completeness | M | open |
| 206 | [F10-d](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve exported Swift throws to Objective-C error translation | completeness | M | open |
| 207 | [C09-c](research/abi-sprints-2026-11-23/02-generics-closures.md) | Distinguish a distributed local implementation from its thunk | completeness | M | open |
| 208 | [O07-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Recover a scalar _read yield without treating the continuation as value | completeness | M | open |
| 209 | [O07-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Recover one ordered multi-piece yield and its overflow | completeness | M | open |
| 210 | [O07-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Decode a callee-allocated coroutine's entry descriptor and allocator role | completeness | M | open |
| 211 | [O08-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Match a legacy coroutine activation's normal completion | completeness | M | open |
| 212 | [O08-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Distinguish legacy abort from normal completion | completeness | M | open |
| 213 | [O08-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Complete a new yielding accessor even when its caller throws | completeness | M | open |
| 214 | [O08-d](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Replace the continuation across repeated YieldMany activations | completeness | M | open |
| 215 | [X01](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Name a defined global data symbol without claiming its value | completeness | S | open |
| 216 | [X02](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Index selector references independently of function names | completeness | M | open |
| 217 | [X03](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Index exact string references as data references | completeness | M | open |
| 218 | [X04](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Cross-reference data-symbol reads and writes | completeness | M | open |
| 219 | [X05](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Recover a proved native Array storage count | completeness | M | open |
| 220 to 221 | [X06 and X07](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Recover Dictionary and Set counts separately | completeness | M | open |

## Phase 3: last by scope

The closed-caller async transport chain (A03), which depends on most of
the async sprints above and on the uncommitted proof work described in its
card file; dynamic replacement and foreign async completion (U01, U02);
and C++ interop (F13, O09), which is outside the Swift and Objective-C
target and ranked last.

| # | Sprint | Behaviour | Axis | Size | Status |
|---|---|---|---|---|---|
| 222 | [A03-a](research/abi-sprints-2026-11-23/03-async-errors.md) | Admit one complete local caller activation | completeness | L | open |
| 223 | [A03-b](research/abi-sprints-2026-11-23/03-async-errors.md) | Recover the first authentic closed scalar across a hop | completeness | M | open |
| 224 | [U01-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Retain declared ABI while keeping replacement target effects open | completeness | M | open |
| 225 | [U01-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Identify previous implementation separately from original definition | completeness | M | open |
| 226 | [U01-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve async replacement descriptor association | completeness | M | open |
| 227 | [U01-d](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve coroutine replacement's distinct descriptor category | completeness | M | open |
| 228 | [U02-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Identify the declaration's completion-block slot | completeness | S | open |
| 229 | [U02-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Associate a successful completion invocation with its Swift continuation | completeness | M | open |
| 230 | [U02-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Choose foreign-async failure from the declared sentinel polarity | completeness | M | open |
| 231 | [U02-d](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve exported async-to-completion direction and optional handler | completeness | M | open |
| 232 | [F13-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Represent a C++ member receiver separately from Swift Self | completeness | M | open |
| 233 | [F13-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Identify constructor destination independently of ordinary result | completeness | M | open |
| 234 | [F13-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Distinguish nontrivial indirect C++ result from register aggregate | completeness | M | open |
| 235 | [O09-a](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve nontrivial C++ copy-construction effects | completeness | M | open |
| 236 | [O09-b](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve nontrivial C++ move-construction source state | completeness | M | open |
| 237 | [O09-c](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Preserve complete destructor and cleanup responsibility | completeness | M | open |
| 238 | [F13-d](research/abi-sprints-2026-11-23/04-foreign-ownership.md) | Retain a proved virtual this adjustment | completeness | M | open |

## Landed before the queue

Found by probing while the cards were being written, and not sprints:

- `ca9eef5`: `Int64` and `UInt64` struct fields are read from registers.
- `10f90df`: the flags `bics` sets, so subset tests render.
- `bf340f3`: an inlined fragment's call keeps its library binding (found while
  preparing O06-a): runtime calls at -Osize sites show their arguments.

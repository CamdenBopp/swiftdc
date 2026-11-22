# Merge review — reports 01–06

Read-only review, with no new binaries or tests run. A local check covered 81
unique pinned Swift/LLVM source paths and all linked line anchors across these
reports. The sole out-of-range endpoint was report 03's Coro.h L15–99. The file
ends at L93. Cite L15–93 in the merged plan.

## Evidence boundaries

- L02 is a source-confirmed divergence between zero-size entry handling and an
  outgoing layout that declines at the formals in question. Mark as
  source-confirmed mismatch / conservative decline. No wrong call argument was
  shown.
- L03 is a source-confirmed schema mismatch. The compiler's real
  AggregateBarrierProbe IR has three distinct pieces before the sentinel,
  while swiftdc's chunk set conflates the integer pieces. The qualified renderer
  declined at that call. Crossing the direct/indirect threshold remains an
  oracle case. Reserve wrong-render wording for a reproduced result.
- G07 reproduces an incorrect value-witness type label. `typeOfA` still
  emits an unresolved return. In `PackBox.identityA`, the actual A metadata
  load is at byte 88. The scalar index uses immediate-members base 80 and
  converts that load to parameter B. The published gate binary labels the
  witness B with both compiler builds. The command-line Swift 6.4.2 paired
  fixture labels the ordinary `PlainBox.identityA` witness A. Verify the
  admission guard and both index and rendering consumers before full pack support.
- F07 reproduces an incorrect receiver assignment.
  Distinct selectors in the fixture, independent machine calls through the
  same super stub, and incorrect self assignment line up. Prioritize by the
  observed wrong statement. Keep declarations and fixed results qualified
  independently. Report 06's general status definition should separate source
  contradiction from reproduced wrong output.
- Report 03's name-only candidate, parent reach and hop shape issues are proof
  limitations. The useInt pre-implementation red measures a missing approved
  rendering, not an incorrect scalar. Its six assertions are three API modes
  times two renderers in one test. Keep the 19 passing focused tests and prior
  witness qualification attached to their own baselines.
- E03/E05/E10 and F01/F05/F06 are source risks. A helpful compiler rule is not
  evidence that the current consumer took a specific branch on a real binary.
  C08's async demotion hook does not establish shipping code transformation.

## Five shared dependencies

1. Establish evidence/version/provenance facts first. Exact compiler, target,
   deployment, optimization and resilience, and separate image, symbol and
   provider evidence. Split target identity from the contract actually proved
   at that boundary. Reports 02, 03, 04 and 06 need this immediately.
2. Give 01–06 a common lowered signature with source slot, pre/post abstraction
   SIL role, native shape, physical placement and ownership represented
   independently. Account separately for zero-size values, unknown value with
   known placement, leading result buffers, receiver/context, metadata and
   witness tails, error channel and resume/coroutine roles. Share native
   component and allocation logic across entry/call/result paths.
3. Connect that signature to role-preserving transport in the machine analysis.
   Ordered byte/lane state, aliases, frame and context lifetime, target/auth
   provenance and exact or unknown call effects feed both forwarded arguments
   and edge states. Keep declared slot, actual bytes, producer and validity
   separate through joins. This enables 01 stack, 02 descriptors, 03 frame
   replay, 04 error buffers, 05 context and 06 bridges.
4. Publish one boundary transition and exit model. Distinguish direct/indirect
   call, tail, await suspend/resume and yield/resume/abort, success/error,
   trap/unwind/unknown, and conditional initialization/consumption. Apply
   provider-scoped runtime effects using this model. Reabstraction transforms
   between two signatures and must preserve real effects. Let trace and both
   renderers consume the same proof.
5. Build independent ordered-oracle records and adopt them for staged gates.
   Measure each role rather than only sets of entry registers. Require matched
   compiler IR, linked assembly, native outcome/effect trace where applicable,
   and one-factor proof mutations. Confirm filtered, array and streaming
   renderers agree and count unchecked cases explicitly.

F07 can land independently with a minimal selector/receiver proof and native
control. The G07 admission guard can land before pack support. L02/L03 can be
covered with a safe decline first, while native role allocation is being built.
Do not route these narrow fixes through full schema migration before testing.

## Unassigned cases worth naming explicitly

- **Native dynamic replacement and previous implementation** (reports 05/06).
  No dedicated row covers replaceable, replacement or previous function
  references and their execution through a runtime-selected implementation.
  A declared ABI may be known while the original body's preservation/effect
  facts are no longer valid. Cover sync and async descriptor-backed transitions
  where the installed compiler emits them. Test a separately linked replacement
  with an observable changed effect and the original-implementation control.
  Do not promote absent coverage to a wrong-render claim.
  [GenDecl.cpp emitDynamicReplacements L1939–1978](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/GenDecl.cpp#L1939-L1978)
  [IRGenSIL.cpp dynamic and previous function refs L3246–3265](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/IRGen/IRGenSIL.cpp#L3246-L3265)
- **ObjC foreign async completion bridges** (03/04/05/06). A completion block
  param slot, optional error arg and separate flag index/polarity go beyond
  raw block invocation and native x20 error channels. Treat original ObjC call,
  block invocation/ownership and Swift continuation as separate contracts.
  Add repeatable native success, error and pre-/post-suspension completion
  fixtures plus one-factor block operand/sentinel polarity mutations.
  [ForeignAsyncConvention.h L25–80](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/AST/ForeignAsyncConvention.h#L25-L80)
  [ResultPlan.cpp emitForeignAsyncCompletionHandler L796–855](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/lib/SILGen/ResultPlan.cpp#L796-L855)

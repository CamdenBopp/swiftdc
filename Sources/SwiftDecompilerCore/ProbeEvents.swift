/// Every instrument swiftdc defines. The identifiers are the trace schema
/// (`ProbeRecorder.schema`); `docs/INSTRUMENTATION.md` lists them with their
/// fields.
public extension ProbeEvent {
    static let imageIdentity = ProbeEvent("loader.image", .loader, .metric,
        "The Mach-O UUID and architecture of the image being analyzed; no path is exposed.")
    static let analysisSnapshot = ProbeEvent("analysis.function", .values, .metric,
        "One completed per-function value analysis, with symbol and coverage denominators.")
    static let blockSnapshot = ProbeEvent("cfg.block", .cfg, .decision,
        "A recovered basic block and its successors; missing edges remain missing.")
    static let exitRegisters = ProbeEvent("values.exit-registers", .values, .decision,
        "Raw register facts at a return; these are not a claim about a source-level result's ABI.")
    static let callSnapshot = ProbeEvent("values.call", .values, .decision,
        "Raw argument, receiver and result-buffer facts at a machine call site.")
    static let conditionSnapshot = ProbeEvent("values.condition", .values, .decision,
        "The recovered branch-taken condition, retaining signed versus unsigned operators.")
    static let returnOutcome = ProbeEvent("render.return-outcome", .render, .decision,
        "Whether an exit renders a recovered, partial, unknown, void, throwing or unsupported-layout return.")
    static let returnValue = ProbeEvent("render.return-value", .render, .claim,
        "The abstract value and rendered expression of a recovered return, for an independent oracle.")
    static let renderedFunction = ProbeEvent("render.function", .render, .metric,
        "One committed render, with view, final return statements and coverage counts; excludes trial emission.")
    static let slotProven = ProbeEvent("async.slot-proven", .async, .claim,
        "A context slot is claimed to hold this portable value throughout the funclet chain.")
    static let contextEscape = ProbeEvent(
        "async.context-escape", .async, .decline,
        "A possible context alias takes a slot address; this slot and later slots cannot be proven constant across the chain.")
    static let contextEscapeCap = ProbeEvent(
        "async.context-escape-cap", .async, .limit,
        "Context alias analysis did not converge within its bound; no chain slot is proven.")
    static let contextEscapeUnknown = ProbeEvent(
        "async.context-escape-unknown", .async, .decline,
        "Missing instruction semantics prevent proving that context slots do not escape.")

    // MARK: perf
    static let analysisTime = ProbeEvent("perf.analysis", .perf, .metric, "Time in per-function analysis.")
    static let renderTime = ProbeEvent("perf.render", .perf, .metric, "Time rendering structured or flat pseudocode.")
}

extension ProbeEvent {
    // MARK: values
    static let loopInitialization = ProbeEvent(
        "values.loop-initialization", .values, .claim,
        "A named loop-carried variable has a proven constant entry value; address is the header branch, stackOffset is relative to the entry frame.")
    static let tracerFixpointCap = ProbeEvent(
        "values.fixpoint-cap", .values, .limit,
        "The value tracer stopped at its iteration bound before converging; its states are not a fixpoint.")
    static let tracerLoopBodyCap = ProbeEvent(
        "values.loop-body-cap", .values, .limit,
        "The induction re-transfer over a loop body stopped at its bound before converging.")
    static let tracerUnmodelledWrite = ProbeEvent(
        "values.unmodelled-write", .values, .claim,
        "An instruction writes a register (Capstone access flags) whose proven value the tracer kept.")
}

extension ProbeEvent {
    // MARK: abi
    static let argumentLayout = ProbeEvent(
        "abi.argument-layout", .abi, .decision,
        "How a call site's arguments were laid out: strategy is swift-signature, c-format, c-format-unread, objc-format, objc-signature, objc-signature-disputed, objc-maybe-float, objc-variadic, body-reads, will-throw or positional.")
}

extension ProbeEvent {
    // MARK: types
    static let fieldNamed = ProbeEvent(
        "types.field-named", .types, .claim,
        "An access at offset into type was named after a stored property from metadata. Checkable against DWARF member offsets.")
    static let fieldUnnamed = ProbeEvent(
        "types.field-unnamed", .types, .decline,
        "An access at offset into type was left unnamed; reason is past-instance-size, past-trusted-prefix, padding or no-layout.")
}

extension ProbeEvent {
    // MARK: structure
    static let structureDepthGoto = ProbeEvent(
        "structure.depth-goto", .structure, .limit,
        "The structurer's recursion bound turned a block into a goto.")
    static let structureDetachedBlock = ProbeEvent(
        "structure.detached-block", .structure, .decline,
        "A block not reached by structured emission printed as a labelled block: a landing pad, or a CFG/jump-table gap upstream.")
    static let structureUnknownCondition = ProbeEvent(
        "structure.unknown-condition", .structure, .decline,
        "A two-way branch rendered `if (?)`.")
    static let structureUnknownSwitchIndex = ProbeEvent(
        "structure.unknown-switch-index", .structure, .decline,
        "A jump table rendered `switch (?)`: its index is not tracked.")
}

extension ProbeEvent {
    // MARK: decode
    static let decodeSkippedSlot = ProbeEvent(
        "decode.skipped-slot", .decode, .decline,
        "Capstone could not decode a 4-byte slot (data in text, or an unsupported encoding); decoding resumed after it.")
    static let decodeJumpWithoutDetail = ProbeEvent(
        "decode.jump-without-detail", .decode, .decline,
        "A jump with no Capstone detail was assumed conditional, which adds a fall-through edge.")
    static let decodeUnmatched = ProbeEvent(
        "decode.unmatched", .decode, .claim,
        "An objdump instruction has no Capstone instruction at its address, so it has no control-flow class; a branch there would read as sequential.")

    // MARK: abi (summaries)
    static let summaryCap = ProbeEvent(
        "abi.summary-cap", .abi, .limit,
        "A callee summary's dataflow hit its visit bound; it claims nothing (argument reads) or every written register clobbered (preservation). The closure over calls (call-clobbers) stopped instead: each function still waiting, and every caller of one, claims every callee-saved register clobbered.")
}

extension ProbeEvent {
    // MARK: cfg
    static let jumpTable = ProbeEvent(
        "cfg.jump-table", .cfg, .decision,
        "A `br` was proven a jump table with this many cases.")
    static let unresolvedIndirectBranch = ProbeEvent(
        "cfg.unresolved-indirect-branch", .cfg, .decline,
        "A `br` with no proven jump table and no proven target: its successors are missing from the CFG.")
    static let unresolvedIndirectCall = ProbeEvent(
        "cfg.unresolved-indirect-call", .cfg, .decline,
        "A `blr` with no proven target: absent from the call graph.")
}

extension ProbeEvent {
    static let structureUnreadableFlags = ProbeEvent(
        "structure.unreadable-flags", .structure, .decline,
        "A branch's flags come from an instruction the text path does not model (ccmp, fcmp, ngcs, …); the condition renders `?`.")
}

/// What per-function analysis reads of a callee's register summary, once
/// every closure over the summaries is done.
///
/// A summary also holds what only the closures need: the body's call edges
/// (`callees`, `outgoingCalls`), its pending reads, its preservation work
/// (`definitelyClobbered`, `restoredFrom`) and what it reads of its callees'
/// results (`resultReads`). Kept for every function through the whole of
/// pass 2, those were the larger part of the summary table's heap. Ported
/// from a projection Codex measured on an earlier dev (502be0e, its own
/// worktree).
struct CalleeRegisterFacts: Sendable {
    let argumentReads: RegisterSet
    let provenArgumentReads: RegisterSet
    let provenFloatArgumentReads: RegisterSet
    let floatArgumentWidths: [Int: Int]
    let mayWriteFloatResult: Bool
    let mayWriteResult: Bool
    let readsFramePointer: Bool
    let readsContextRegister: Bool
    let readsSelfRegister: Bool
    /// Positive uses of incoming x0...x7 and x19...x29 (bit n for xn).
    let provenEntryRegisterReads: UInt32
    let clobberedCalleeSaved: Set<String>
    let storesOnlyToStack: Bool
    let writesNoFields: Bool
    let memoryEffect: CalleeMemoryEffect
    /// `CalleeRegisterSummary.provenAllocationSites`, for the function's own
    /// tracer.
    let provenAllocationSites: [UInt64]
    /// `CalleeRegisterSummary.readsIncomingStack`: its call passes stack
    /// arguments beyond its registers.
    let readsIncomingStack: Bool
    /// `CalleeRegisterSummary.mayReadRegisters`.
    let mayReadRegisters: UInt32

    var argumentCount: Int { (argumentReads.max() ?? -1) + 1 }
    var provenArgumentCount: Int { (provenArgumentReads.max() ?? -1) + 1 }
    var provenFloatArgumentCount: Int { (provenFloatArgumentReads.max() ?? -1) + 1 }

    private init(_ summary: CalleeRegisterSummary) {
        argumentReads = summary.argumentReads
        provenArgumentReads = summary.provenArgumentReads
        provenFloatArgumentReads = summary.provenFloatArgumentReads
        floatArgumentWidths = summary.floatArgumentWidths
        mayWriteFloatResult = summary.mayWriteFloatResult
        mayWriteResult = summary.mayWriteResult
        readsFramePointer = summary.readsFramePointer
        readsContextRegister = summary.readsContextRegister
        readsSelfRegister = summary.readsSelfRegister
        provenEntryRegisterReads = summary.provenEntryRegisterReads
        clobberedCalleeSaved = summary.clobberedCalleeSaved
        storesOnlyToStack = summary.storesOnlyToStack
        writesNoFields = summary.writesNoFields
        memoryEffect = summary.memoryEffect
        provenAllocationSites = summary.provenAllocationSites
        readsIncomingStack = summary.readsIncomingStack
        mayReadRegisters = summary.mayReadRegisters
    }

    /// The finished summaries: what analysis reads of each, and the results
    /// their callers prove (`CalleeRegisterSummary.callerProvenResults`),
    /// which need the call-site reads the projection drops, so they are
    /// taken first. Call only after every closure; `summaries` is emptied,
    /// so nothing can read a construction table that no longer holds them.
    static func finish(
        _ summaries: inout [UInt64: CalleeRegisterSummary]
    ) -> (facts: [UInt64: CalleeRegisterFacts], callerProvenResults: [UInt64: Disassembler.SwiftReturnRegister]) {
        let callerProven = CalleeRegisterSummary.callerProvenResults(summaries)
        let facts = summaries.mapValues(Self.init)
        summaries.removeAll()
        return (facts, callerProven)
    }
}

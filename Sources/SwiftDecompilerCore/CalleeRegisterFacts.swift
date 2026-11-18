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
    /// Possible FP0...7 reads; never a positive count or width proof.
    let mayReadFloatArguments: UInt8
    let floatArgumentWidths: [Int: Int]
    let mayWriteFloatResult: Bool
    let mayWriteResult: Bool
    let readsFramePointer: Bool
    let readsContextRegister: Bool
    let readsSelfRegister: Bool
    /// Positive uses of incoming x0...x7 and x19...x29 (bit n for xn).
    let provenEntryRegisterReads: UInt32
    let clobberedCalleeSaved: Set<String>
    /// Actual body preservation, closed over every outgoing transfer. The
    /// ordinary opaque ABI's callee-saved default is not this proof.
    var bodyPreservesSwiftError = false
    let storesOnlyToStack: Bool
    let writesNoFields: Bool
    let memoryEffect: CalleeMemoryEffect
    /// `CalleeRegisterSummary.provenAllocationSites`, for the function's own
    /// tracer.
    let provenAllocationSites: [UInt64]
    /// `CalleeRegisterSummary.readsIncomingStack`: its call passes stack
    /// arguments beyond its registers.
    let readsIncomingStack: Bool
    /// Closed opaque-transfer extent; it supplies no concrete arity.
    let hasOpaqueInputTransfer: Bool
    /// `CalleeRegisterSummary.mayReadRegisters`.
    let mayReadRegisters: UInt32

    /// Whether anything in the image is evidence about this function's
    /// result: a caller reads a register after calling it, or its body
    /// leaves x21 changed (a possible throw). Where there is such evidence
    /// and it proves no one x0 result (`callerProvenResults`), x0 at a
    /// return is not offered as a possible result either.
    var resultEvidence = false

    var argumentCount: Int { (argumentReads.max() ?? -1) + 1 }
    var provenArgumentCount: Int { (provenArgumentReads.max() ?? -1) + 1 }
    var provenFloatArgumentCount: Int { (provenFloatArgumentReads.max() ?? -1) + 1 }

    private init(_ summary: CalleeRegisterSummary) {
        argumentReads = summary.argumentReads
        provenArgumentReads = summary.provenArgumentReads
        provenFloatArgumentReads = summary.provenFloatArgumentReads
        mayReadFloatArguments = summary.mayReadFloatArguments
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
        hasOpaqueInputTransfer = summary.hasOpaqueInputTransfer
        mayReadRegisters = summary.mayReadRegisters
    }

    /// The finished summaries: what analysis reads of each, and the results
    /// their callers prove (`CalleeRegisterSummary.callerProvenResults`),
    /// which need the call-site reads the projection drops, so they are
    /// taken first. Call only after every closure; `summaries` is emptied,
    /// so nothing can read a construction table that no longer holds them.
    static func finish(
        _ summaries: inout [UInt64: CalleeRegisterSummary],
        externalPreservesSwiftError: (UInt64) -> Bool = { _ in false },
        body: (UInt64) -> DisassembledFunction? = { _ in nil },
        calleeArity: (UInt64) -> Int? = { _ in nil },
        projecting registerSummaryStarts: Set<UInt64>? = nil
    ) -> (facts: [UInt64: CalleeRegisterFacts], registerFacts: [UInt64: CalleeRegisterFacts],
          callerProvenResults: [UInt64: Disassembler.SwiftReturnRegister]) {
        // Bodies decoded only to qualify Swift's error register do not
        // introduce argument/result contracts at an indirect call boundary.
        let (callerProven, evidence) = {
            let inputs = registerSummaryStarts.map { starts in summaries.filter { starts.contains($0.key) } } ?? summaries
            return (CalleeRegisterSummary.callerProvenResults(inputs), CalleeRegisterSummary.resultEvidence(inputs))
        }()
        // A closed cycle with no error-register write preserves x21 on any
        // path that returns. Remove every candidate that reaches an unproved
        // call, then its callers; never seed a proof from the opaque ABI.
        var preserving = Set(summaries.compactMap { start, summary in
            summary.inputProofEntry == start && !summary.hasUnresolvedSwiftErrorCall
                && summary.hasProvenReturnTargets && !summary.clobberedCalleeSaved.contains("x21") ? start : nil
        })
        var callers: [UInt64: [UInt64]] = [:]
        var rejected: [UInt64] = []
        var external: [UInt64: Bool] = [:]
        for start in preserving.sorted() {
            guard let summary = summaries[start] else { continue }
            var invalid = false
            for target in summary.callees {
                if summaries[target] != nil {
                    callers[target, default: []].append(start)
                    if !preserving.contains(target) { invalid = true }
                } else {
                    let proved = external[target] ?? externalPreservesSwiftError(target)
                    external[target] = proved
                    if !proved { invalid = true }
                }
            }
            if invalid { rejected.append(start) }
        }
        while let start = rejected.popLast() {
            guard preserving.remove(start) != nil else { continue }
            rejected.append(contentsOf: callers[start] ?? [])
        }
        // The general summary intentionally carries MAY clobbers through
        // save escapes. That policy cannot prove a parked return address
        // survives a chain of helpers. Validate these candidates with a
        // separate strict preservation closure, without changing the MAY
        // effects consumed by argument and receiver reconstruction.
        let saved = Set(Preservation.calleeSavedKeys)
        var affected = Set(preserving.filter {
            !(summaries[$0]?.clobberedCalleeSaved.subtracting(["x21"]).isEmpty ?? true)
        })
        var pending = Array(affected)
        while let start = pending.popLast() {
            for caller in callers[start] ?? [] where preserving.contains(caller) {
                if affected.insert(caller).inserted { pending.append(caller) }
            }
        }
        var strictClobbers = Dictionary(uniqueKeysWithValues: affected.compactMap { start in
            summaries[start].map { (start, $0.clobberedCalleeSaved) }
        })
        var strictRestores = Dictionary(uniqueKeysWithValues: affected.compactMap { start in
            summaries[start].map { (start, $0.effect.restores) }
        })
        var returnTargets: [UInt64: Bool] = [:]
        var bodies: [UInt64: DisassembledFunction] = [:]
        var missing = false
        for start in affected.sorted() {
            guard let function = body(start), function.startAddress == start,
                  function.instructions.first?.address == start else { missing = true; continue }
            bodies[start] = function
        }
        pending = affected.sorted()
        var queued = affected
        var visits = 0
        // A capped or oscillating closure supplies no positive evidence.
        let cap = 64 * max(affected.count, 1)
        while !missing, let start = pending.popLast() {
            queued.remove(start)
            visits += 1
            guard visits <= cap, let function = bodies[start] else { missing = true; break }
            let addresses = Set(function.instructions.map(\.address))
            func effect(_ insn: Instruction) -> CalleeEffect {
                guard let target = insn.branchTarget,
                      !addresses.contains(target) || (insn.controlFlow == .call && target == start),
                      let summary = summaries[target] else { return CalleeEffect() }
                var result = summary.effect
                let clobbers = strictClobbers[target] ?? summary.clobberedCalleeSaved
                let restores = strictRestores[target] ?? summary.effect.restores
                result.clobbers = clobbers.subtracting(restores.keys)
                result.entryValueClobbers = clobbers
                result.restores = restores
                return result
            }
            let proof = Preservation.ReturnAddressProof()
            let exits = Preservation.exitValues(
                blocks: function.basicBlocks(), entry: start, addresses: addresses,
                callEffect: effect,
                exitEffect: { insn in
                    insn.controlFlow == .branch || insn.controlFlow == .conditionalBranch
                        ? effect(insn) : CalleeEffect()
                },
                callInputs: { insn in
                    guard let target = insn.branchTarget else { return Preservation.abiCallInputs }
                    // A spelling's formal count cannot hide actual GP
                    // inputs or pointer bits carried in a vector register.
                    if let summary = summaries[target] {
                        return CalleeRegisterSummary.registerKeys(summary.mayReadRegisters)
                            .union((0..<32).map { "v\($0)" })
                    }
                    if let arity = calleeArity(target) {
                        return Set((0..<min(arity, 8)).map { "x\($0)" } + ["x8"])
                            .union((0..<8).map { "v\($0)" })
                    }
                    return Preservation.abiCallInputs
                }, clobbersMayAliasStack: true, returnAddressProof: proof)
            guard let exits else { missing = true; break }
            var clobbers: Set<String> = []
            var restores: [String: Int64] = [:]
            for key in saved {
                if exits.values.contains(where: { $0[key] != .entry(key) }) { clobbers.insert(key) }
                if let first = exits.values.first, case .incoming(let offset)? = first[key],
                   exits.values.allSatisfy({ $0[key] == .incoming(offset) }) {
                    restores[key] = offset
                }
            }
            returnTargets[start] = proof.acceptsExits
            if strictClobbers[start] != clobbers || strictRestores[start] != restores {
                strictClobbers[start] = clobbers
                strictRestores[start] = restores
                for caller in callers[start] ?? [] where affected.contains(caller) {
                    if queued.insert(caller).inserted { pending.append(caller) }
                }
            }
        }
        rejected = affected.filter {
            missing || returnTargets[$0] != true || strictClobbers[$0]?.contains("x21") != false
        }
        while let start = rejected.popLast() {
            guard preserving.remove(start) != nil else { continue }
            rejected.append(contentsOf: callers[start] ?? [])
        }
        var facts = summaries.mapValues(Self.init)
        for start in preserving { facts[start]?.bodyPreservesSwiftError = true }
        for start in evidence { facts[start]?.resultEvidence = true }
        summaries.removeAll()
        let registerFacts = registerSummaryStarts.map { starts in facts.filter { starts.contains($0.key) } } ?? facts
        return (facts, registerFacts, callerProven)
    }
}

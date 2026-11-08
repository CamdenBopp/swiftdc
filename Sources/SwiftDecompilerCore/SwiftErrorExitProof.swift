import Ccapstone

/// Which exits of a Swift throwing function are proven normal (non-throwing):
/// a forward must-analysis of the error register over the CFG.
///
/// A synchronous Swift function throws by returning its error in x21
/// (swifterror); the caller arms x21 with zero and tests it after the call. So
/// a path that never writes x21 has not thrown, and neither has one whose x21
/// is a proven zero: `mov x21, #0`, or the zero edge of a full-width
/// `cbz`/`cbnz x21`. Everything else declines: any other write, an undecoded
/// instruction, a call that may throw or does not preserve the register, and
/// any block reached from outside the modelled CFG (no predecessor, or not
/// reachable from the entry, as an unwinder landing pad would be).
///
/// An async function's error travels in x20, which holds `self` on entry, so
/// its entry state is not a proof (`entryIsNoError: false`).
///
/// Unresolved indirect branches are the caller's concern: such a branch may
/// land inside a proven path and skip its guard, so a function with one must
/// not consult this at all.
enum SwiftErrorExitProof {
    /// The addresses of the instructions before which every modelled path from
    /// the entry leaves `key` without a possible error.
    ///
    /// `excluding` removes edges whose paths the renderers already end in a
    /// throw (a throw merged into a shared epilogue). Only the remaining paths
    /// are then asked to be normal.
    static func noErrorPoints(
        blocks: [BasicBlock],
        entry: UInt64,
        key: String,
        entryIsNoError: Bool,
        excluding excludedEdges: Set<CFGEdge> = [],
        callPreserves: (Instruction) -> Bool
    ) -> Set<UInt64> {
        let blockByStart = Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
        guard blockByStart[entry] != nil else { return [] }

        let reachable = reach(from: [entry], in: blockByStart)
        var predecessors: [UInt64: [UInt64]] = [:]
        for block in blocks {
            for successor in Set(block.successors) where blockByStart[successor] != nil {
                predecessors[successor, default: []].append(block.startAddress)
            }
        }

        func transfer(_ insn: Instruction, _ noError: Bool) -> Bool {
            if insn.controlFlow == .call { return noError && callPreserves(insn) }
            guard let detail = insn.detail else { return false }
            guard detail.writtenRegisterKeys.contains(key) else { return noError }
            return isZeroing(detail, key: key)
        }

        /// The state each block leaves along each of its out-edges. Greatest
        /// fixpoint: reachable blocks start optimistic and only fall to false.
        var edgeOut: [UInt64: [UInt64: Bool]] = [:]
        func outEdges(of block: BasicBlock, from noError: Bool) -> [UInt64: Bool] {
            var state = noError
            for insn in block.instructions { state = transfer(insn, state) }
            var edges: [UInt64: Bool] = [:]
            for successor in block.successors { edges[successor] = state }
            // The zero edge of a full-width compare-and-branch on the register.
            if let test = block.instructions.last, test.controlFlow == .conditionalBranch,
               let detail = test.detail, detail.id == AARCH64_INS_CBZ || detail.id == AARCH64_INS_CBNZ,
               let tested = detail.operands.first?.operand.register,
               tested.kind == .gpr, tested.key == key, tested.widthBits == 64,
               let taken = test.branchTarget, block.successors.count == 2,
               Set(block.successors).count == 2,
               let fallThrough = block.successors.first(where: { $0 != taken }) {
                edges[detail.id == AARCH64_INS_CBZ ? taken : fallThrough] = true
            }
            return edges
        }
        func entryState(of start: UInt64) -> Bool {
            guard reachable.contains(start) else { return false }
            let incoming = predecessors[start] ?? []
            var state = start == entry ? entryIsNoError : true
            for predecessor in incoming {
                if let end = blockByStart[predecessor]?.instructions.last?.address,
                   excludedEdges.contains(CFGEdge(from: end, to: start)) { continue }
                // An unreachable predecessor still has an edge here that the
                // CFG cannot account for; it proves nothing.
                guard reachable.contains(predecessor) else { return false }
                state = state && (edgeOut[predecessor]?[start] ?? true)
            }
            return state
        }

        var worklist = blocks.map(\.startAddress).filter(reachable.contains)
        var queued = Set(worklist)
        while let start = worklist.popLast() {
            queued.remove(start)
            guard let block = blockByStart[start] else { continue }
            let edges = outEdges(of: block, from: entryState(of: start))
            guard edges != edgeOut[start] else { continue }
            edgeOut[start] = edges
            for successor in Set(block.successors) where reachable.contains(successor) {
                if queued.insert(successor).inserted { worklist.append(successor) }
            }
        }

        var points = Set<UInt64>()
        for block in blocks {
            var state = entryState(of: block.startAddress)
            for insn in block.instructions {
                if state { points.insert(insn.address) }
                state = transfer(insn, state)
            }
        }
        return points
    }

    /// The blocks every way into which is a modelled path from the entry:
    /// reachable from it, and from no block that is not (an unwinder landing
    /// pad, or code only an unresolved branch reaches).
    static func modelledBlocks(blocks: [BasicBlock], entry: UInt64) -> Set<UInt64> {
        let blockByStart = Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
        guard blockByStart[entry] != nil else { return [] }
        let reachable = reach(from: [entry], in: blockByStart)
        let outside = blocks.map(\.startAddress).filter { !reachable.contains($0) }
        return reachable.subtracting(reach(from: outside, in: blockByStart))
    }

    private static func reach(from starts: [UInt64], in blockByStart: [UInt64: BasicBlock]) -> Set<UInt64> {
        var reached = Set(starts)
        var stack = starts
        while let start = stack.popLast() {
            for successor in blockByStart[start]?.successors ?? [] where blockByStart[successor] != nil {
                if reached.insert(successor).inserted { stack.append(successor) }
            }
        }
        return reached
    }

    /// `mov key, #0`, `mov key, xzr` and their 32-bit forms, which zero the
    /// whole register.
    static func isZeroing(_ detail: StructuredInsn, key: String) -> Bool {
        guard detail.id == AARCH64_INS_MOV || detail.id == AARCH64_INS_MOVZ, detail.operands.count >= 2,
              let destination = detail.operands[0].operand.register,
              destination.kind == .gpr, destination.key == key
        else { return false }
        let source = detail.operands[1]
        if source.operand.register?.kind == .zero { return true }
        return source.shiftedImmediate == 0
    }
}

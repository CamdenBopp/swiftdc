import Ccapstone

/// MUST facts for native-stack addresses. Value/context facts may be lost at
/// an unmodelled operation without proving that the result is a stack pointer.
enum AsyncHardwareFrames {
    private static let universe = Set((0...30).map { "x\($0)" })
    private static let helperSensitive = Set((0...17).map { "x\($0)" } + ["x22"])

    static func advance(_ frames: inout Set<String>, by insn: Instruction,
                        isHeaderHelper: (UInt64) -> Bool) {
        guard let detail = insn.detail else { frames.removeAll(); return }
        if insn.controlFlow == .call {
            // The complete leaf's only register writes are x22 and BL's LR.
            // Resolve it only when an ordinary ABI transfer would differ.
            if !frames.isDisjoint(with: helperSensitive),
               let target = insn.branchTarget, isHeaderHelper(target) {
                frames.remove("x22"); frames.remove("x30")
                return
            }
            for n in 0...17 { frames.remove("x\(n)") }
            frames.remove("x30")
            return
        }
        if AsyncFuncletIndex.signsInPlace.contains(detail.id) { return }
        let operands = detail.operands
        let destination: String? = {
            guard let dst = operands.first?.operand.register,
                  dst.kind == .gpr, dst.widthBits == 64,
                  operands.count >= 2, let src = operands[1].operand.register,
                  src.widthBits == 64,
                  src.kind == .stackPointer || frames.contains(src.key)
            else { return nil }
            switch detail.id {
            case AARCH64_INS_MOV, AARCH64_INS_ORR:
                guard operands.count == 2 else { return nil }
            case AARCH64_INS_ADD, AARCH64_INS_SUB:
                guard operands.count == 3, operands[2].shiftedImmediate != nil else { return nil }
            default: return nil
            }
            return dst.key
        }()
        frames.subtract(detail.writtenRegisterKeys)
        if let destination { frames.insert(destination) }
    }

    /// Meet every reachable predecessor, including backedges. Unvisited
    /// outputs start at lattice top, then only lose facts until convergence.
    /// A limit or an inconsistent transfer returns no incoming proofs.
    static func inputs(in blocks: [BasicBlock], entry: UInt64, maximumVisits: Int? = nil,
                       isHeaderHelper: (UInt64) -> Bool) -> [UInt64: Set<String>] {
        let byStart = Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { first, _ in first })
        guard byStart[entry] != nil else { return [:] }
        var reachable: Set<UInt64> = [entry]
        var discover: [UInt64] = [entry]
        var cursor = 0
        while cursor < discover.count {
            let address = discover[cursor]; cursor += 1
            for next in (byStart[address]?.successors ?? []).sorted()
                where byStart[next] != nil && reachable.insert(next).inserted {
                discover.append(next)
            }
        }
        var predecessors: [UInt64: [UInt64]] = [:]
        for address in reachable.sorted() {
            for next in (byStart[address]?.successors ?? []).sorted() where reachable.contains(next) {
                predecessors[next, default: []].append(address)
            }
        }
        let limit = maximumVisits ?? (reachable.count * 64 + 16)
        var work: [UInt64] = [entry]
        var queued: Set<UInt64> = [entry]
        var outputs: [UInt64: Set<String>] = [:]
        var inputs: [UInt64: Set<String>] = [:]
        cursor = 0
        while cursor < work.count {
            guard cursor < limit else { return [:] }
            let address = work[cursor]; cursor += 1
            queued.remove(address)
            guard let block = byStart[address] else { return [:] }
            var incoming: Set<String> = address == entry ? ["x29"] : universe
            for previous in predecessors[address] ?? [] {
                incoming.formIntersection(outputs[previous] ?? universe)
            }
            inputs[address] = incoming
            var outgoing = incoming
            for insn in block.instructions { advance(&outgoing, by: insn, isHeaderHelper: isHeaderHelper) }
            guard outgoing.isSubset(of: outputs[address] ?? universe) else { return [:] }
            if outputs[address] == nil || outputs[address] != outgoing {
                outputs[address] = outgoing
                for next in block.successors.sorted()
                    where reachable.contains(next) && queued.insert(next).inserted {
                    work.append(next)
                }
            }
        }
        guard outputs.count == reachable.count else { return [:] }
        return inputs
    }
}

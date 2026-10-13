import Ccapstone

/// Escape detection is a MAY analysis: an alias on either incoming path can
/// let a callee mutate the context. Value recovery's intersection meet would
/// lose exactly the aliases this check must retain.
struct AsyncContextEscapes {
    var iterationsPerBlock = 64

    func lowestOffset(in function: DisassembledFunction, terminalBranches: Set<UInt64> = []) -> Int? {
        let blocks = function.basicBlocks()
        guard !blocks.isEmpty else { return nil }
        let byStart = Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
        var predecessors: [UInt64: [UInt64]] = [:]
        for block in blocks {
            for next in block.successors where byStart[next] != nil {
                predecessors[next, default: []].append(block.startAddress)
            }
        }
        var outputs: [UInt64: Set<Int>] = [:]
        var work = blocks.map(\.startAddress)
        var queued = Set(work)
        var cursor = 0
        var escapes: [UInt64: Int] = [:]
        let cap = blocks.count * iterationsPerBlock + 16
        while cursor < work.count {
            guard cursor < cap else {
                Probe.record(.contextEscapeCap, at: function.startAddress,
                             ["blocks": .int(blocks.count), "cap": .int(cap)])
                return Int.min // no slot is proven past an incomplete analysis
            }
            let address = work[cursor]
            cursor += 1
            queued.remove(address)
            guard let block = byStart[address] else { continue }
            let incoming = predecessors[address] ?? []
            var contexts = incoming.reduce(into: Set<Int>()) { $0.formUnion(outputs[$1] ?? []) }
            if address == function.startAddress { contexts.insert(22) }
            // An isolated landing pad has no modeled incoming edge or register
            // state. Its callee-saved registers may carry a context alias.
            if incoming.isEmpty, address != function.startAddress { contexts.formUnion(19...28) }
            for insn in block.instructions {
                guard let detail = insn.detail else {
                    Probe.record(.contextEscapeUnknown, at: insn.address, ["reason": .label("missing-detail")])
                    return Int.min
                }
                if insn.controlFlow == .branch, insn.branchTarget == nil,
                   function.switchTargets[insn.address] == nil, !terminalBranches.contains(insn.address) {
                    Probe.record(.contextEscapeUnknown, at: insn.address, ["reason": .label("unresolved-indirect-flow")])
                    return Int.min
                }
                if insn.controlFlow == .call {
                    contexts = contexts.filter { (19...28).contains($0) }
                    continue
                }
                if detail.writeback, detail.operands.contains(where: { info in
                    if case .memory(let base?, _, _) = info.operand {
                        return base.kind == .gpr && contexts.contains(base.number)
                    }
                    return false
                }) {
                    // The set carries pointer identity, not a changing byte
                    // offset. Never trust subsequent zero-offset reloads after
                    // a context base was advanced by an addressing mode.
                    Probe.record(.contextEscapeUnknown, at: insn.address, ["reason": .label("context-writeback")])
                    return Int.min
                }
                // Inspect the incoming state BEFORE killing the destination:
                // add x19,x19,#16 takes a slot's address too.
                if detail.operands.count >= 2,
                   let dest = detail.operands[0].operand.register, dest.kind == .gpr,
                   dest.number != 22, dest.number != 29,
                   let source = detail.operands[1].operand.register,
                   source.kind == .gpr, contexts.contains(source.number) {
                    let offset: Int?
                    switch detail.id {
                    case AARCH64_INS_ADD:
                        offset = detail.operands.count == 3
                            ? Int(clamping: detail.operands[2].shiftedImmediate ?? 0) : 0
                    case AARCH64_INS_MOV, AARCH64_INS_ORR, AARCH64_INS_SUB:
                        offset = 0
                    default: offset = nil
                    }
                    if let offset { escapes[insn.address] = min(escapes[insn.address] ?? offset, offset) }
                }
                let loaded: Set<Int> = {
                    let paired = detail.id == AARCH64_INS_LDP || detail.id == AARCH64_INS_LDNP
                    guard paired || detail.id == AARCH64_INS_LDR || detail.id == AARCH64_INS_LDUR,
                          detail.operands.count >= (paired ? 3 : 2),
                          case .memory(let base?, nil, let displacement) = detail.operands[paired ? 2 : 1].operand,
                          base.kind == .gpr, contexts.contains(base.number)
                    else { return [] }
                    var aliases: Set<Int> = []
                    for index in 0..<(paired ? 2 : 1) {
                        guard let dest = detail.operands[index].operand.register,
                              dest.kind == .gpr, dest.widthBits == 64,
                              displacement + Int64(index * 8) == 0 else { continue }
                        aliases.insert(dest.number)
                    }
                    return aliases
                }()
                // Compare/test aliases write NZCV only, even if a decoder's
                // operand-access flags incorrectly label an input as written.
                switch detail.id {
                case AARCH64_INS_ALIAS_CMP, AARCH64_INS_ALIAS_CMN, AARCH64_INS_ALIAS_TST, AARCH64_INS_CCMP, AARCH64_INS_CCMN:
                    break
                default:
                    for key in detail.writtenRegisterKeys {
                        guard key.hasPrefix("x"), let number = Int(key.dropFirst()), number != 22 else { continue }
                        contexts.remove(number)
                    }
                }
                contexts.formUnion(loaded)
            }
            if outputs[address] != contexts {
                outputs[address] = contexts
                for next in block.successors where byStart[next] != nil && queued.insert(next).inserted {
                    work.append(next)
                }
            }
        }
        for (address, offset) in escapes.sorted(by: { $0.key < $1.key }) {
            Probe.record(.contextEscape, at: address, ["offset": .int(offset)])
        }
        return escapes.values.min()
    }
}

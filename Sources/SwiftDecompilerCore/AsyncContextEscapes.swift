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
                // A context pointer stored anywhere can be reloaded through an
                // alias this register-only analysis does not represent. Decline
                // rather than lose that possible pointer at a stack/heap spill.
                let memory = detail.operands.first { $0.operand.isMemory }
                let readOnlyLoad = [
                    AARCH64_INS_LDR, AARCH64_INS_LDUR, AARCH64_INS_LDP, AARCH64_INS_LDNP,
                    AARCH64_INS_LDRB, AARCH64_INS_LDURB, AARCH64_INS_LDRH, AARCH64_INS_LDURH,
                    AARCH64_INS_LDRSB, AARCH64_INS_LDURSB, AARCH64_INS_LDRSH, AARCH64_INS_LDURSH,
                    AARCH64_INS_LDRSW, AARCH64_INS_LDURSW,
                ].contains(detail.id)
                if detail.operands.contains(where: { $0.operand.isMemory }), !readOnlyLoad, detail.operands.contains(where: { info in
                    guard let reg = info.operand.register else { return false }
                    return reg.kind == .gpr && contexts.contains(reg.number)
                }) {
                    Probe.record(.contextEscapeUnknown, at: insn.address, ["reason": .label("stored-context-pointer")])
                    return Int.min
                }
                if let memory, case .memory(let base?, let index, let displacement) = memory.operand,
                   base.kind == .gpr, contexts.contains(base.number) {
                    // Only aligned, exact 64-bit integer stores are represented
                    // in asyncSlotStores. Narrow, vector, indexed, overlapping or
                    // unmodelled writes cannot leave chain-wide constants intact.
                    let modeledStore = [AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP].contains(detail.id)
                        && index == nil && displacement % 8 == 0
                        && detail.operands.prefix { !$0.operand.isMemory }.allSatisfy {
                            ($0.operand.register?.kind == .gpr || $0.operand.register?.kind == .zero)
                                && $0.operand.register?.widthBits == 64
                        }
                    if !modeledStore && !readOnlyLoad {
                        Probe.record(.contextEscapeUnknown, at: insn.address, ["reason": .label("unmodelled-context-memory")])
                        return Int.min
                    }
                }
                // Inspect every source before killing the destination. Conditional
                // copies and a context in operand 2 are possible aliases too. An
                // exported interior address has no proven write footprint: a
                // callee can write at a negative offset, so lower slots are unsafe.
                let comparesOnly: Bool
                switch detail.id {
                case AARCH64_INS_ALIAS_CMP, AARCH64_INS_ALIAS_CMN, AARCH64_INS_ALIAS_TST, AARCH64_INS_CCMP, AARCH64_INS_CCMN:
                    comparesOnly = true
                default: comparesOnly = false
                }
                if !comparesOnly, !detail.operands.contains(where: { $0.operand.isMemory }),
                   detail.operands.first?.operand.register != nil,
                   detail.operands.dropFirst().contains(where: { info in
                       guard let source = info.operand.register else { return false }
                       return source.kind == .gpr && contexts.contains(source.number)
                   }) {
                    escapes[insn.address] = Int.min
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
                // A load of parent-pointer bits is safe for this register-only
                // model only when the complete pointer becomes a tracked GPR
                // alias. Indexed, partial or SIMD reads may reconstruct a pointer
                // later through register banks the alias set does not represent.
                if readOnlyLoad, let memory,
                   case .memory(let base?, let index, let displacement) = memory.operand,
                   base.kind == .gpr, contexts.contains(base.number),
                   index != nil || (displacement < 8 && loaded.isEmpty) {
                    Probe.record(.contextEscapeUnknown, at: insn.address, ["reason": .label("unproven-parent-pointer-load")])
                    return Int.min
                }
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

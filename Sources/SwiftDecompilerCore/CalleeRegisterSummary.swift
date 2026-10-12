import Ccapstone
import Foundation

/// What an in-image function's own body proves about the registers a call to
/// it uses, for callees no signature describes.
///
/// A call snapshotted x0–x7 positionally, so a register the callee never reads
/// rendered as an argument: clang -O0 `printf(…); return bump();` with
/// `long bump(void)` showed `bump(printf(…))`. And the value tracer kept
/// x19–x29 across every call, as AAPCS64 promises. LLVM's machine outliner
/// (`-Osize` Swift, `-Oz` C) breaks both: an `OUTLINED_FUNCTION_n` fragment is
/// reached by `bl` but takes inputs in any register and writes callee-saved
/// ones (`add x20, sp, #8; b Hasher._finalize` rewrites `self`). On an -Osize
/// build of the Reconstruction fixture, `ReconError.hashValue` rendered
/// `OUTLINED_FUNCTION_9(OUTLINED_FUNCTION_35(Swift.Hasher._combine(0)))`:
/// `_combine` returns nothing, and neither fragment takes an argument. The
/// fragments are local symbols, so a stripped binary has no name to go by;
/// the body is the evidence.
struct CalleeRegisterSummary: Sendable, Equatable {
    /// Argument registers x0…x7 (by number) the body may read before writing
    /// them on some path from its entry. A call or tail call inside counts as
    /// reading every one not yet written, since it may pass them on.
    let argumentReads: Set<Int>
    /// Callee-saved registers (`x19`…`x29`) the body writes and does not
    /// provably hand back: at some exit (a `ret` or a tail branch out) the
    /// register does not hold its entry value. Anything unproven counts as
    /// clobbered.
    let clobberedCalleeSaved: Set<String>

    /// The integer arguments a call to this function can pass: through the
    /// highest argument register it reads. Unread registers below that are
    /// positional parameters it ignores.
    var argumentCount: Int { (argumentReads.max() ?? -1) + 1 }

    private static let argumentKeys = (0...7).map { "x\($0)" }
    private static let calleeSavedKeys = Set((19...29).map { "x\($0)" })

    /// Nil when any instruction lacks structured detail: nothing is claimed
    /// about a body that was not fully decoded.
    static func of(_ function: DisassembledFunction) -> CalleeRegisterSummary? {
        let instructions = function.instructions
        guard !instructions.isEmpty, instructions.allSatisfy({ $0.detail != nil }) else { return nil }
        let addresses = Set(instructions.map(\.address))
        let blocks = function.basicBlocks()
        guard let entry = blocks.first?.startAddress else { return nil }
        let blockAt = Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })

        // Forward must-analysis: the argument registers written on every path
        // into a block (intersection at joins). A read of one not in the set is
        // a possible argument read.
        var inState: [UInt64: Set<String>] = [entry: []]
        var reads = Set<Int>()
        var worklist = [entry]
        var visits = 0
        while let start = worklist.popLast() {
            visits += 1
            // A pathological CFG must not hang the summary; giving up claims
            // nothing (every caller keeps its positional arguments).
            guard visits <= 64 * max(blocks.count, 1) else {
                Probe.record(.summaryCap, at: function.startAddress, ["pass": .label("argument-reads")])
                return nil
            }
            guard let block = blockAt[start] else { return nil }
            var written = inState[start] ?? []
            for insn in block.instructions {
                guard let detail = insn.detail else { return nil }
                func read(_ key: String) {
                    if let index = argumentKeys.firstIndex(of: key), !written.contains(key) { reads.insert(index) }
                }
                let internalBranch = insn.branchTarget.map(addresses.contains) == true
                let leavesThroughCall = insn.controlFlow == .call
                    || (insn.controlFlow == .branch && !internalBranch && block.switchCases == nil)
                if leavesThroughCall {
                    // The callee may read any argument register still holding
                    // this function's incoming value.
                    argumentKeys.forEach(read)
                }
                // Operands without access flags are counted as read, so a gap
                // in Capstone's tables cannot hide an argument.
                for info in detail.operands {
                    if case .register(let register) = info.operand, register.kind == .gpr,
                       info.access == 0 || info.isRead {
                        read(register.key)
                    }
                }
                detail.readRegisterKeys.forEach(read)
                written.formUnion(detail.writtenRegisterKeys.intersection(argumentKeys))
                if insn.controlFlow == .call { written.formUnion(argumentKeys) }
            }
            for successor in block.successors where addresses.contains(successor) {
                let merged = inState[successor].map { $0.intersection(written) } ?? written
                if merged != inState[successor] {
                    inState[successor] = merged
                    worklist.append(successor)
                }
            }
        }

        var writtenCalleeSaved = Set<String>()
        for insn in instructions {
            guard let detail = insn.detail else { return nil }
            writtenCalleeSaved.formUnion(detail.writtenRegisterKeys.intersection(calleeSavedKeys))
        }
        let clobbered = writtenCalleeSaved.isEmpty
            ? []
            : Preservation.unrestored(writtenCalleeSaved, blocks: blocks, entry: entry, addresses: addresses)
        return CalleeRegisterSummary(argumentReads: reads, clobberedCalleeSaved: clobbered)
    }
}

/// Which callee-saved registers a body hands back with their entry values.
///
/// Being stored somewhere is not being preserved: a function can spill x19,
/// overwrite it and never reload it. Over the CFG, each general register and
/// each 8-byte stack slot holds an abstract value: some register's entry
/// value, an address `entry sp + k`, or unknown. Moves copy values; `add`/`sub`
/// of an immediate move addresses; stores and loads through a known stack
/// address (pre- and post-index included) save and reload them; anything else
/// a register is written with is unknown. At every exit, a `ret` or a tail
/// branch out, a register holding anything but its own entry value is not
/// preserved. Joins keep only what every path agrees on, and an unfinished
/// fixpoint gives up on every written register.
private enum Preservation {
    enum Value: Hashable {
        case entry(String)
        case stack(Int64)
        case unknown
    }

    struct State: Equatable {
        var registers: [String: Value]
        var slots: [Int64: Value]

        func value(_ key: String) -> Value { registers[key] ?? .unknown }

        func merged(with other: State) -> State {
            State(
                registers: registers.filter { other.registers[$0.key] == $0.value },
                slots: slots.filter { other.slots[$0.key] == $0.value }
            )
        }
    }

    static func unrestored(
        _ written: Set<String>, blocks: [BasicBlock], entry: UInt64, addresses: Set<UInt64>
    ) -> Set<String> {
        var initial = State(registers: ["sp": .stack(0)], slots: [:])
        for index in 19...29 { initial.registers["x\(index)"] = .entry("x\(index)") }
        let blockAt = Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
        var inState: [UInt64: State] = [entry: initial]
        var clobbered = Set<String>()
        var worklist = [entry]
        var visits = 0
        while let start = worklist.popLast() {
            visits += 1
            guard visits <= 64 * max(blocks.count, 1) else {
                Probe.record(.summaryCap, at: entry, ["pass": .label("preservation")])
                return written
            }
            guard let block = blockAt[start], var state = inState[start] else { return written }
            for insn in block.instructions {
                guard let detail = insn.detail else { return written }
                let internalBranch = insn.branchTarget.map(addresses.contains) == true
                let exits = insn.controlFlow == .return
                    || (insn.controlFlow == .branch && !internalBranch && block.switchCases == nil)
                if exits {
                    for key in written where state.value(key) != .entry(key) { clobbered.insert(key) }
                    continue
                }
                if insn.controlFlow == .call {
                    // The callee keeps the ABI: x19–x29 and sp survive it.
                    for index in 0...18 { state.registers["x\(index)"] = nil }
                    state.registers["x30"] = nil
                    continue
                }
                apply(detail, to: &state)
            }
            for successor in block.successors where addresses.contains(successor) {
                let merged = inState[successor].map { $0.merged(with: state) } ?? state
                if merged != inState[successor] {
                    inState[successor] = merged
                    worklist.append(successor)
                }
            }
        }
        return clobbered
    }

    /// The memory operand's address and the base's value after writeback.
    private static func access(_ detail: StructuredInsn, in state: State) -> (address: Int64?, base: String?, after: Value?) {
        guard let memory = detail.operands.first(where: { $0.operand.isMemory }),
              case .memory(let base?, let index, let displacement) = memory.operand, index == nil,
              case .stack(let k) = state.value(base.key)
        else { return (nil, nil, nil) }
        if detail.postIndex {
            let delta = detail.operands.last?.operand.immediateValue ?? 0
            return (k, base.key, .stack(k &+ delta))
        }
        return (k &+ displacement, base.key, detail.writeback ? .stack(k &+ displacement) : nil)
    }

    private static func apply(_ detail: StructuredInsn, to state: inout State) {
        let operands = detail.operands
        // A writeback through a base that is no known stack address still
        // moves that base.
        if detail.writeback, access(detail, in: state).address == nil,
           let memory = operands.first(where: { $0.operand.isMemory }),
           case .memory(let base?, _, _) = memory.operand {
            state.registers[base.key] = .unknown
        }
        func register(_ index: Int) -> PhysReg? {
            index < operands.count ? operands[index].operand.register : nil
        }
        switch detail.id {
        case AARCH64_INS_MOV:
            if let destination = register(0), let source = register(1), destination.widthBits == 64 {
                state.registers[destination.key] = state.value(source.key)
                return
            }
        case AARCH64_INS_ADD, AARCH64_INS_SUB:
            if let destination = register(0), let source = register(1), destination.widthBits == 64,
               operands.count == 3, let immediate = operands[2].shiftedImmediate,
               case .stack(let k) = state.value(source.key) {
                state.registers[destination.key] = .stack(detail.id == AARCH64_INS_ADD ? k &+ immediate : k &- immediate)
                return
            }
        case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP:
            let (address, base, after) = access(detail, in: state)
            let count = detail.id == AARCH64_INS_STP ? 2 : 1
            if let address {
                for offset in 0..<count {
                    guard let source = register(offset) else { continue }
                    let slot = address &+ Int64(offset * 8)
                    // Only a whole 64-bit register is a saved value.
                    state.slots[slot] = source.widthBits == 64 ? state.value(source.key) : .unknown
                    if source.widthBits != 64 { state.slots[slot &- 4] = nil; state.slots[slot &+ 4] = nil }
                }
            }
            // A store through an unknown pointer is assumed not to reach the
            // register save area, which no pointer escapes to.
            if let base, let after { state.registers[base] = after }
            return
        case AARCH64_INS_LDR, AARCH64_INS_LDUR, AARCH64_INS_LDP:
            let (address, base, after) = access(detail, in: state)
            let count = detail.id == AARCH64_INS_LDP ? 2 : 1
            for offset in 0..<count {
                guard let destination = register(offset) else { continue }
                if let address, destination.widthBits == 64 {
                    state.registers[destination.key] = state.slots[address &+ Int64(offset * 8)] ?? .unknown
                } else {
                    state.registers[destination.key] = .unknown
                }
            }
            if let base, let after { state.registers[base] = after }
            return
        default:
            break
        }
        for key in detail.writtenRegisterKeys { state.registers[key] = .unknown }
    }
}

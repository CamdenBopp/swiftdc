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
enum Preservation {
    enum Value: Hashable {
        case entry(String)
        case stack(Int64)
        case unknown
    }

    struct State: Equatable {
        var registers: [String: Value]
        // Each fact covers exactly eight bytes. A store at a different start
        // address can still overwrite part of that saved register.
        var slots: [Int64: Value]
        // MAY provenance is independent of the must-value facts above: a
        // join can lose an exact address while retaining a feasible alias.
        var stackAliases: Set<String> = ["sp"]
        var stackAddressEscaped = false

        mutating func setRegister(_ key: String, to value: Value, mayAliasStack: Bool = false) {
            registers[key] = value == .unknown ? nil : value
            if case .stack = value { stackAliases.insert(key) }
            else if mayAliasStack { stackAliases.insert(key) }
            else { stackAliases.remove(key) }
        }

        func value(_ key: String) -> Value { registers[key] ?? .unknown }

        func merged(with other: State) -> State {
            State(
                registers: registers.filter { other.registers[$0.key] == $0.value },
                slots: slots.filter { other.slots[$0.key] == $0.value },
                stackAliases: stackAliases.union(other.stackAliases),
                stackAddressEscaped: stackAddressEscaped || other.stackAddressEscaped
            )
        }

        mutating func invalidateSlotsForUnknownWrite(throughStackAlias: Bool) {
            if throughStackAlias || stackAddressEscaped {
                slots.removeAll()
                return
            }
            // Incoming pointers can reach caller-owned memory at entry SP
            // or above it. A save is private only if all eight bytes lie
            // below entry SP; testing its start alone misses straddling saves.
            slots = slots.filter { start, _ in
                let (end, overflow) = start.addingReportingOverflow(8)
                return !overflow && end <= 0
            }
        }

        mutating func invalidateSlots(at address: Int64, bytes: Int) {
            let (end, overflow) = address.addingReportingOverflow(Int64(bytes))
            guard bytes > 0, !overflow else {
                slots.removeAll()
                return
            }
            slots = slots.filter { start, _ in
                let (slotEnd, slotOverflow) = start.addingReportingOverflow(8)
                return !slotOverflow && (slotEnd <= address || start >= end)
            }
        }
    }

    static func unrestored(
        _ written: Set<String>, blocks: [BasicBlock], entry: UInt64, addresses: Set<UInt64>
    ) -> Set<String> {
        guard let exits = entryValuesAtExits(blocks: blocks, entry: entry, addresses: addresses) else {
            return written
        }
        var clobbered = Set<String>()
        for preserved in exits.values { clobbered.formUnion(written.subtracting(preserved)) }
        return clobbered
    }

    /// For each exit (a `ret`, or a tail branch out), the callee-saved
    /// registers that hold their entry values there on every path. Nil when
    /// the body is not fully decoded or the fixpoint is capped: nothing is
    /// claimed then. An exit no path from the entry reaches is absent.
    ///
    /// `callClobbers` names registers a call does not hand back despite the
    /// ABI (a callee that may throw redefines x21; an outlined fragment can
    /// write any of them). They may hold a frame address afterwards.
    /// `excluding` drops edges whose paths are accounted for elsewhere (a
    /// throw merged into a shared epilogue); exits are judged without them.
    static func entryValuesAtExits(
        blocks: [BasicBlock], entry: UInt64, addresses: Set<UInt64>,
        excluding excludedEdges: Set<CFGEdge> = [],
        callClobbers: (Instruction) -> Set<String> = { _ in [] }
    ) -> [UInt64: Set<String>]? {
        let calleeSaved = (19...29).map { "x\($0)" }
        var initial = State(registers: ["sp": .stack(0)], slots: [:])
        for key in calleeSaved { initial.registers[key] = .entry(key) }
        let blockAt = Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
        var inState: [UInt64: State] = [entry: initial]
        // States only shrink, so the last visit of an exit is the smallest;
        // intersecting every visit yields it without tracking which was last.
        var exits: [UInt64: Set<String>] = [:]
        var worklist = [entry]
        var visits = 0
        while let start = worklist.popLast() {
            visits += 1
            guard visits <= 64 * max(blocks.count, 1) else {
                Probe.record(.summaryCap, at: entry, ["pass": .label("preservation")])
                return nil
            }
            guard let block = blockAt[start], var state = inState[start] else { return nil }
            for insn in block.instructions {
                guard let detail = insn.detail else { return nil }
                let internalBranch = insn.branchTarget.map(addresses.contains) == true
                let isExit = insn.controlFlow == .return
                    || (insn.controlFlow == .branch && !internalBranch && block.switchCases == nil)
                if isExit {
                    let preserved = Set(calleeSaved.filter { state.value($0) == .entry($0) })
                    exits[insn.address] = exits[insn.address].map { $0.intersection(preserved) } ?? preserved
                    continue
                }
                if insn.controlFlow == .call {
                    // A callee may mutate any save whose address it can
                    // reach. sp/x29 alone are ordinary frame bookkeeping;
                    // any other frame alias can be an outgoing argument,
                    // including an outlined fragment's nonstandard input.
                    if !state.stackAliases.subtracting(["sp", "x29"]).isEmpty {
                        state.stackAddressEscaped = true
                    }
                    state.invalidateSlotsForUnknownWrite(throughStackAlias: false)
                    // The callee keeps the ABI: x19–x29 and sp survive it.
                    for index in 0...18 { state.setRegister("x\(index)", to: .unknown) }
                    state.setRegister("x30", to: .unknown)
                    for key in callClobbers(insn) { state.setRegister(key, to: .unknown, mayAliasStack: true) }
                    continue
                }
                apply(detail, to: &state)
            }
            for successor in block.successors where addresses.contains(successor) {
                if let end = block.instructions.last?.address,
                   excludedEdges.contains(CFGEdge(from: end, to: successor)) { continue }
                let merged = inState[successor].map { $0.merged(with: state) } ?? state
                if merged != inState[successor] {
                    inState[successor] = merged
                    worklist.append(successor)
                }
            }
        }
        return exits
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
        let hasStackBase = operands.contains { info in
            guard case .memory(let base?, _, _) = info.operand else { return false }
            return state.stackAliases.contains(base.key)
        }
        // A writeback through a base that is no known stack address still
        // moves that base.
        if detail.writeback, access(detail, in: state).address == nil,
           let memory = operands.first(where: { $0.operand.isMemory }),
           case .memory(let base?, _, _) = memory.operand {
            state.setRegister(base.key, to: .unknown, mayAliasStack: state.stackAliases.contains(base.key))
        }
        func register(_ index: Int) -> PhysReg? {
            index < operands.count ? operands[index].operand.register : nil
        }
        switch detail.id {
        case AARCH64_INS_MOV:
            if let destination = register(0), let source = register(1), destination.widthBits == 64 {
                state.setRegister(destination.key, to: state.value(source.key), mayAliasStack: state.stackAliases.contains(source.key))
                return
            }
        case AARCH64_INS_ADD, AARCH64_INS_SUB:
            if let destination = register(0), let source = register(1), destination.widthBits == 64,
               operands.count == 3, let immediate = operands[2].shiftedImmediate,
               case .stack(let k) = state.value(source.key) {
                state.setRegister(destination.key, to: .stack(detail.id == AARCH64_INS_ADD ? k &+ immediate : k &- immediate))
                return
            }
        case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP, AARCH64_INS_STNP,
             AARCH64_INS_STRB, AARCH64_INS_STURB, AARCH64_INS_STRH, AARCH64_INS_STURH:
            let (address, base, after) = access(detail, in: state)
            let count = detail.id == AARCH64_INS_STP || detail.id == AARCH64_INS_STNP ? 2 : 1
            // Even a pointer stored before a later save can expose that
            // future save. Do not tie escape lifetime to existing slot facts.
            for offset in 0..<count {
                if let source = register(offset), state.stackAliases.contains(source.key) {
                    state.stackAddressEscaped = true
                }
            }
            if let address {
                for offset in 0..<count {
                    guard let source = register(offset) else { continue }
                    let bytes: Int
                    switch detail.id {
                    case AARCH64_INS_STRB, AARCH64_INS_STURB: bytes = 1
                    case AARCH64_INS_STRH, AARCH64_INS_STURH: bytes = 2
                    default: bytes = source.widthBits / 8
                    }
                    let slot = address &+ Int64(offset * bytes)
                    state.invalidateSlots(at: slot, bytes: bytes)
                    // Only a whole 64-bit GPR is a saved entry value. A SIMD
                    // store invalidates its complete extent, including both
                    // adjacent eight-byte saves when it writes a Q register.
                    if bytes == 8, source.kind == .gpr {
                        state.slots[slot] = state.value(source.key)
                    }
                }
            } else {
                state.invalidateSlotsForUnknownWrite(throughStackAlias: hasStackBase)
            }
            if let base, let after { state.setRegister(base, to: after) }
            return
        case AARCH64_INS_LDR, AARCH64_INS_LDUR, AARCH64_INS_LDP:
            let (address, base, after) = access(detail, in: state)
            let count = detail.id == AARCH64_INS_LDP ? 2 : 1
            for offset in 0..<count {
                guard let destination = register(offset) else { continue }
                if let address, destination.widthBits == 64 {
                    state.setRegister(destination.key, to: state.slots[address &+ Int64(offset * 8)] ?? .unknown)
                } else {
                    state.setRegister(destination.key, to: .unknown)
                }
            }
            if let base, let after { state.setRegister(base, to: after) }
            return
        default:
            break
        }
        // An unsupported memory write (or missing memory access flags) has no
        // proven extent. Forget the saves when its base points into the frame.
        // Flags are used only to decline; supported stores use actual widths.
        if operands.contains(where: { $0.operand.isMemory && ($0.isWritten || $0.access == 0) }) {
            state.invalidateSlotsForUnknownWrite(throughStackAlias: hasStackBase)
        }
        // An unmodelled transform of a frame address loses its exact offset,
        // not its ability to alias the frame. Keep that MAY fact at joins too.
        let readsStackAlias = !detail.readRegisterKeys.intersection(state.stackAliases).isEmpty
            || operands.contains { info in
                guard let reg = info.operand.register else { return false }
                return (info.isRead || info.access == 0) && state.stackAliases.contains(reg.key)
            }
        if operands.contains(where: { $0.operand.isMemory && ($0.isWritten || $0.access == 0) }), readsStackAlias {
            state.stackAddressEscaped = true
        }
        for key in detail.writtenRegisterKeys {
            state.setRegister(key, to: .unknown, mayAliasStack: readsStackAlias)
        }
    }
}

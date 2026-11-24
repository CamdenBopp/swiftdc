import Ccapstone

/// How far above the stack pointer it was entered with a body addresses
/// memory, without being handed a pointer there.
///
/// A caller's frame slot is taken to survive a call that receives no
/// address of it. That holds for a callee that stays inside its own frame.
/// A body that stores above its entry sp, or makes a pointer there and
/// stores through it or passes it on, writes its caller's frame:
/// `add x2, sp, #144` in an 80-byte frame is the caller's `[sp, #64]`, and a
/// 64-byte `st4` at `[sp]` in a 16-byte frame covers 48 bytes of the caller.
/// The caller read the slot back as the constant it stored before the call.
///
/// A store has an extent: the bytes above the entry sp it can cover, which
/// are the caller's `[sp, sp + extent)` at the call. Compiled code does
/// this to its stack arguments, which the caller does not read back. An
/// address made above the entry sp is a point: the caller's slot there has
/// escaped, as if the caller had passed its address. Outlined code does
/// this, running on its caller's sp.
///
/// The depth of sp below its entry value is a lower bound, followed over the
/// body's own branches, so an address is never taken to be lower than it is.
/// An address made from sp or x29 is followed through register copies and
/// constant offsets, to a store through it. One that is loaded back from
/// memory, indexed by a register or handed to a call is not: what a callee
/// writes through a pointer to a local is taken to stay inside the local.
enum CallerFrameReach {
    private struct State: Equatable {
        /// sp is at least this far below its entry value. Nil when nothing
        /// bounds it.
        var depth: Int64?
        /// x29 is exactly this far below the entry sp. Nil when x29 is not a
        /// frame pointer the body set from sp.
        var frame: Int64?
        /// General registers holding an address the body made from sp or
        /// x29, by their number: the address is this far above the entry sp
        /// at most (negative: below it).
        var derived: [Int: Int64] = [:]
    }

    /// The most bytes one store can write: `st4` of four 16-byte vectors,
    /// or `dc zva`.
    private static let widestStore: Int64 = 64
    /// A merge that keeps lowering a bound is a loop that pops: give up.
    private static let visitLimit = 16
    /// More addresses than this and the body is taken to reach everything.
    static let pointLimit = 8

    private static func storeBytes(_ detail: StructuredInsn) -> Int64 {
        func width(_ operands: ArraySlice<StructuredOperandInfo>) -> Int64 {
            operands.reduce(0) { total, info in
                guard case .register(let register) = info.operand else { return total }
                return total + Int64(max(register.widthBits, 8) / 8)
            }
        }
        let registers = detail.operands.prefix { !$0.operand.isMemory }
        switch detail.id {
        case AARCH64_INS_STRB, AARCH64_INS_STURB: return 1
        case AARCH64_INS_STRH, AARCH64_INS_STURH: return 2
        case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP:
            let bytes = width(registers)
            return bytes == 0 ? widestStore : bytes
        default: return widestStore
        }
    }

    /// No bound: the whole of the caller's frame.
    static let unbounded = Int64.max

    struct Scan: Equatable {
        /// Bytes above the entry sp the body itself may write: 0 for none.
        var own: Int64 = 0
        /// Each direct call or branch out of the body, with the least depth
        /// of sp below the entry sp at one. Nil when nothing bounds it.
        var calls: [UInt64: Int64?] = [:]
        /// Offsets above the entry sp the body makes an address of.
        var points: Set<Int64> = []
        static let everything = Scan(own: CallerFrameReach.unbounded)
    }

    static func scan(_ instructions: [Instruction]) -> Scan {
        guard !instructions.isEmpty else { return Scan() }
        let addresses = Set(instructions.map(\.address))
        var scan = Scan()
        let index = Dictionary(instructions.enumerated().map { ($1.address, $0) }, uniquingKeysWith: { a, _ in a })
        var states: [State?] = Array(repeating: nil, count: instructions.count)
        var visits = Array(repeating: 0, count: instructions.count)
        var indirect: [State] = []
        var worklist = [0]
        states[0] = State(depth: 0, frame: nil)

        func merge(_ state: State, into target: Int) -> Bool {
            guard let old = states[target] else {
                states[target] = state
                worklist.append(target)
                return true
            }
            let depth: Int64? = if let a = old.depth, let b = state.depth { min(a, b) } else { nil }
            // An address is an upper bound: the higher of two that meet.
            let derived = old.derived.merging(state.derived) { max($0, $1) }
                .filter { old.derived[$0.key] != nil && state.derived[$0.key] != nil }
            let merged = State(depth: depth, frame: old.frame == state.frame ? old.frame : nil, derived: derived)
            guard merged != old else { return true }
            visits[target] += 1
            guard visits[target] <= visitLimit else { return false }
            states[target] = merged
            worklist.append(target)
            return true
        }

        while true {
            while let position = worklist.popLast() {
                let insn = instructions[position]
                guard var state = states[position], let detail = insn.detail else { return .everything }
                let (extent, point) = reach(detail, in: state)
                guard extent != unbounded else { return .everything }
                scan.own = max(scan.own, extent)
                if let point {
                    scan.points.insert(point)
                    guard scan.points.count <= pointLimit else { return .everything }
                }
                if let target = insn.branchTarget, insn.controlFlow == .call || !addresses.contains(target) {
                    let depth: Int64? = if let seen = scan.calls[target] {
                        if let a = seen, let b = state.depth { min(a, b) } else { nil }
                    } else { state.depth }
                    scan.calls[target] = .some(depth)
                }
                step(detail, &state)
                if insn.controlFlow == .return { continue }
                if insn.controlFlow == .branch || insn.controlFlow == .conditionalBranch {
                    if let target = insn.branchTarget {
                        if let next = index[target], !merge(state, into: next) { return .everything }
                    } else {
                        indirect.append(state)
                    }
                    if insn.controlFlow == .branch { continue }
                }
                if position + 1 < instructions.count, !merge(state, into: position + 1) { return .everything }
            }
            // What only a register branch reaches (a jump table's cases) is
            // entered with that branch's state. Two that disagree prove none.
            guard let unvisited = states.firstIndex(where: { $0 == nil }) else { return scan }
            guard let state = indirect.first else { return scan }
            guard indirect.allSatisfy({ $0 == state }) else { return .everything }
            states[unvisited] = state
            worklist.append(unvisited)
        }
    }

    /// The bytes above the entry sp this instruction may write (0 for none,
    /// `unbounded` for a store or an address nothing bounds), and the
    /// offset above the entry sp it makes an address of.
    private static func reach(_ detail: StructuredInsn, in state: State) -> (extent: Int64, point: Int64?) {
        var extent: Int64 = 0
        var readsStack = false, readsFrame = false
        var writesOther = false
        for info in detail.operands {
            switch info.operand {
            case .memory(let base?, let indexRegister, let displacement) where info.isWritten:
                // A post-index store's displacement is already 0 (`unfoldPostIndex`).
                let offset = displacement
                if base.kind == .stackPointer {
                    guard let depth = state.depth, indexRegister == nil else { return (unbounded, nil) }
                    extent = max(extent, offset + storeBytes(detail) - depth)
                } else if base.kind == .gpr, base.number == 29, let frame = state.frame {
                    guard indexRegister == nil else { return (unbounded, nil) }
                    extent = max(extent, offset + storeBytes(detail) - frame)
                } else if base.kind == .gpr, indexRegister == nil, let address = state.derived[base.number] {
                    extent = max(extent, address + offset + storeBytes(detail))
                }
            case .register(let register):
                if info.isWritten {
                    // A compare writes the zero register: it makes no address.
                    if register.kind == .gpr, register.number != 29 { writesOther = true }
                } else if register.kind == .stackPointer {
                    readsStack = true
                } else if register.kind == .gpr, register.number == 29, register.widthBits == 64 {
                    readsFrame = true
                }
            default: break
            }
        }
        // A derived address advanced to the entry sp or past it.
        if writesOther, !readsStack, detail.id == AARCH64_INS_ADD, detail.operands.count == 3,
           case .register(let from) = detail.operands[1].operand, from.kind == .gpr,
           let address = state.derived[from.number], let delta = detail.operands[2].shiftedImmediate,
           address + delta >= 0 {
            return (extent, address + delta)
        }
        guard writesOther, readsStack || (readsFrame && state.frame != nil) else { return (extent, nil) }
        // The value made: `base + delta`, as an offset from the entry sp.
        let base: Int64? = readsStack ? state.depth : state.frame
        guard let base else { return (unbounded, nil) }
        let immediate = detail.operands.last?.shiftedImmediate
        let registerSources = detail.operands.filter {
            if case .register = $0.operand { !$0.isWritten } else { false }
        }.count
        switch detail.id {
        case AARCH64_INS_MOV where registerSources == 1 && immediate == nil:
            return (extent, base <= 0 ? -base : nil)
        case AARCH64_INS_ADD where registerSources == 1:
            guard let immediate else { return (unbounded, nil) }
            return (extent, immediate >= base ? immediate - base : nil)
        case AARCH64_INS_SUB:
            return (extent, base <= 0 ? -base : nil)
        default:
            return (unbounded, nil)
        }
    }

    private static func step(_ detail: StructuredInsn, _ state: inout State) {
        let written = detail.writtenRegisterKeys
        let operands = detail.operands
        func source() -> PhysReg? {
            guard operands.count >= 2, case .register(let register) = operands[1].operand else { return nil }
            return register
        }
        let immediate: Int64? = operands.count == 3 ? operands[2].shiftedImmediate : nil
        let destination: PhysReg? = if case .register(let register)? = operands.first?.operand, operands.first?.isWritten == true {
            register
        } else { nil }
        let isFrameRegister = { (register: PhysReg?) in register?.kind == .gpr && register?.number == 29 && register?.widthBits == 64 }
        var newDepth = state.depth, newFrame = state.frame
        if written.contains("sp") {
            // After a write nothing models, sp is still at or below a frame
            // pointer the body set: the record sits at the top of the frame.
            newDepth = state.frame
            if destination?.kind == .stackPointer, let from = source() {
                let base: Int64? = from.kind == .stackPointer ? state.depth : isFrameRegister(from) ? state.frame : nil
                switch detail.id {
                case AARCH64_INS_SUB: if let base, let immediate { newDepth = base + immediate }
                case AARCH64_INS_ADD: if let base, let immediate { newDepth = base - immediate }
                case AARCH64_INS_MOV: if let base, operands.count == 2 { newDepth = base }
                default: break
                }
            } else if detail.writeback, let depth = state.depth,
                      let memory = operands.first(where: { $0.operand.isMemory }),
                      case .memory(let base?, nil, let displacement) = memory.operand, base.kind == .stackPointer {
                let delta = detail.postIndex ? operands.last?.operand.immediateValue : displacement
                newDepth = delta.map { depth - $0 } ?? state.frame
            }
        }
        if written.contains("x29") {
            newFrame = nil
            if isFrameRegister(destination), let from = source(), from.kind == .stackPointer, let depth = state.depth {
                switch detail.id {
                case AARCH64_INS_ADD: if let immediate { newFrame = depth - immediate }
                case AARCH64_INS_SUB: if let immediate { newFrame = depth + immediate }
                case AARCH64_INS_MOV: if operands.count == 2 { newFrame = depth }
                default: break
                }
            }
        }
        var derived = state.derived
        // What this instruction's address would be, as `reaches` computed
        // it: a constant offset of sp, of x29, or of a derived register.
        var made: Int64?
        if let destination, destination.kind == .gpr, destination.number != 29, destination.widthBits == 64,
           let from = source() {
            let base: Int64? = from.kind == .stackPointer ? state.depth.map { -$0 }
                : isFrameRegister(from) ? state.frame.map { -$0 }
                : from.kind == .gpr && from.widthBits == 64 ? state.derived[from.number] : nil
            if let base {
                switch detail.id {
                case AARCH64_INS_ADD: made = immediate.map { base + $0 }
                case AARCH64_INS_SUB: made = immediate.map { base - $0 }
                case AARCH64_INS_MOV: made = operands.count == 2 ? base : nil
                default: break
                }
            }
        }
        for key in written {
            guard key.hasPrefix("x") || key.hasPrefix("w"), let number = Int(key.dropFirst()) else { continue }
            derived[number] = nil
        }
        if detail.id == AARCH64_INS_BL || detail.id == AARCH64_INS_BLR { for number in 0...18 { derived[number] = nil } }
        if let made, let destination { derived[destination.number] = made }
        state = State(depth: newDepth, frame: newFrame, derived: derived)
    }
}

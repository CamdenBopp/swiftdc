import Ccapstone

/// Body-proven memory effects, relative to the callee's entry registers.
/// Unknown is distinct from a complete body that performs no memory access.
/// This first producer accepts straight-line literal stores and register-only
/// address calculations. A load, call, branch, unsupported opcode or incomplete
/// body declines the entire summary, never just the unrecognized instruction.
enum CalleeMemoryEffect: Sendable, Equatable {
    struct LiteralStore: Sendable, Equatable {
        let base: PhysReg
        let offset: Int64
        let bytes: Int64
        let value: UInt64
        let source: PhysReg
    }
    case unknown
    case literalStores([LiteralStore], inputs: [PhysReg])

    struct FrameStore: Sendable, Equatable {
        let start: Int64
        let bytes: Int64
        let value: UInt64
        let source: PhysReg
    }
    struct FramePlan: Sendable, Equatable {
        let stores: [FrameStore]
        let inputs: [PhysReg]

        fileprivate init(stores: [FrameStore], inputs: [PhysReg]) {
            self.stores = stores
            self.inputs = inputs
        }

        func writeEffect(arithmetic: FrameMemoryEffect.FactEndArithmetic) -> FrameMemoryEffect {
            FrameMemoryEffect(Set(stores.map {
                .finite(lower: $0.start, upper: $0.start + $0.bytes)
            }), arithmetic: arithmetic)
        }
    }

    /// Resolve the whole input transaction before claiming a bounded effect.
    /// Even non-address entry inputs must be proven frame coordinates here;
    /// this deliberately leaves other spaces and mixed provenance unknown.
    func framePlan(resolve: (PhysReg) -> Int64?) -> FramePlan? {
        guard case .literalStores(let stores, let inputs) = self else { return nil }
        var origins: [String: Int64] = [:]
        for input in inputs {
            // BL replaces x30 with the return address. Its entry value is
            // not the caller's pre-call x30, even if that held a frame alias.
            guard input.kind != .gpr || input.number != 30 else { return nil }
            guard let offset = resolve(input) else { return nil }
            origins[input.key] = offset
        }
        var resolved: [FrameStore] = []
        for store in stores {
            guard let base = origins[store.base.key], [1, 2, 4, 8].contains(store.bytes) else { return nil }
            let (start, overflow) = base.addingReportingOverflow(store.offset)
            let (_, endOverflow) = start.addingReportingOverflow(store.bytes)
            guard !overflow, !endOverflow else { return nil }
            resolved.append(FrameStore(start: start, bytes: store.bytes, value: store.value, source: store.source))
        }
        return FramePlan(stores: resolved, inputs: inputs)
    }

    private enum Value: Equatable {
        case input(PhysReg, Int64)
        case literal(UInt64)
        case unknown
    }

    private static func unmodified(_ info: StructuredOperandInfo) -> Bool {
        info.vectorIndex == nil && info.vectorArrangement == AARCH64LAYOUT_INVALID
            && info.extender == AARCH64_EXT_INVALID
            && (info.shift.type == AARCH64_SFT_INVALID || info.shift.type == AARCH64_SFT_LSL)
            && info.shift.amount == 0
    }

    static func discover(in function: DisassembledFunction) -> Self {
        let instructions = function.instructions
        guard let last = instructions.last, let end = last.detail,
              function.startAddress % 4 == 0,
              end.id == AARCH64_INS_RET,
              end.operands.isEmpty || end.operands.count == 1
                && end.operands[0].operand.register == PhysReg(kind: .gpr, number: 30, widthBits: 64)
        else { return .unknown }
        let (length, lengthOverflow) = UInt64(instructions.count - 1).multipliedReportingOverflow(by: 4)
        let (lastAddress, addressOverflow) = function.startAddress.addingReportingOverflow(length)
        guard !lengthOverflow, !addressOverflow, last.address == lastAddress else { return .unknown }
        // Untouched registers are entry inputs; retain only actual writes.
        var values: [String: Value] = [:]
        let sp = PhysReg(kind: .stackPointer, number: 31, widthBits: 64)
        let lr = PhysReg(kind: .gpr, number: 30, widthBits: 64)
        var inputs: Set<PhysReg> = []
        var stores: [LiteralStore] = []
        func read(_ register: PhysReg) -> Value {
            if register.kind == .zero { return .literal(0) }
            guard register.kind == .gpr && (0...30).contains(register.number)
                || register.kind == .stackPointer && register.number == 31
            else { return .unknown }
            let root = PhysReg(kind: register.kind, number: register.number, widthBits: 64)
            let value = values[register.key] ?? .input(root, 0)
            if case .input(let root, _) = value { inputs.insert(root) }
            if register.widthBits == 32 {
                if case .literal(let bits) = value { return .literal(bits & 0xffff_ffff) }
                return .unknown
            }
            return register.widthBits == 64 ? value : .unknown
        }
        for (index, instruction) in instructions.dropLast().enumerated() {
            let (offset, offsetOverflow) = UInt64(index).multipliedReportingOverflow(by: 4)
            let (address, overflow) = function.startAddress.addingReportingOverflow(offset)
            guard !offsetOverflow, !overflow, instruction.address == address else { return .unknown }
            guard let detail = instruction.detail,
                  instruction.controlFlow == nil || instruction.controlFlow == .sequential
            else { return .unknown }
            let operands = detail.operands
            switch detail.id {
            case AARCH64_INS_MOV:
                guard operands.count == 2, let destination = operands[0].operand.register,
                      destination.kind == .gpr || destination.kind == .stackPointer,
                      destination.widthBits == 32 || destination.widthBits == 64,
                      operands.allSatisfy(unmodified)
                else { return .unknown }
                let value: Value
                if let source = operands[1].operand.register {
                    guard source.kind == .gpr || source.kind == .stackPointer || source.kind == .zero
                    else { return .unknown }
                    value = read(source)
                } else if let immediate = operands[1].operand.immediateValue {
                    let bits = UInt64(bitPattern: immediate)
                    value = .literal(destination.widthBits == 32 ? bits & 0xffff_ffff : bits)
                } else { return .unknown }
                if destination.widthBits == 32 {
                    if case .literal(let bits) = value { values[destination.key] = .literal(bits & 0xffff_ffff) }
                    else { values[destination.key] = .unknown }
                } else {
                    values[destination.key] = value
                }
            case AARCH64_INS_ADD, AARCH64_INS_SUB:
                guard operands.count == 3, let destination = operands[0].operand.register,
                      let source = operands[1].operand.register,
                      destination.widthBits == 64, source.widthBits == 64,
                      destination.kind == .gpr || destination.kind == .stackPointer,
                      unmodified(operands[0]), unmodified(operands[1]),
                      let immediate = operands[2].operand.immediateValue, (0...4095).contains(immediate),
                      operands[2].extender == AARCH64_EXT_INVALID,
                      operands[2].shift.type == AARCH64_SFT_INVALID && operands[2].shift.amount == 0
                        || operands[2].shift.type == AARCH64_SFT_LSL && [0, 12].contains(operands[2].shift.amount)
                else { return .unknown }
                let delta = immediate << operands[2].shift.amount
                guard case .input(let root, let offset) = read(source) else { return .unknown }
                let (next, overflow) = detail.id == AARCH64_INS_SUB
                    ? offset.subtractingReportingOverflow(delta) : offset.addingReportingOverflow(delta)
                guard !overflow else { return .unknown }
                values[destination.key] = .input(root, next)
            case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STRB, AARCH64_INS_STURB,
                 AARCH64_INS_STRH, AARCH64_INS_STURH, AARCH64_INS_STP, AARCH64_INS_STNP:
                let pair = detail.id == AARCH64_INS_STP || detail.id == AARCH64_INS_STNP
                let count = pair ? 2 : 1
                guard operands.count == count + 1, !detail.writeback, !detail.postIndex,
                      operands.allSatisfy(unmodified),
                      case .memory(let base?, nil, let displacement) = operands[count].operand,
                      base.widthBits == 64,
                      case .input(let root, let offset) = read(base)
                else { return .unknown }
                for index in 0..<count {
                    guard let source = operands[index].operand.register,
                          source.kind == .gpr || source.kind == .zero,
                          source.widthBits == 32 || source.widthBits == 64,
                          !pair || source.widthBits == operands[0].operand.register?.widthBits,
                          case .literal(let bits) = read(source)
                    else { return .unknown }
                    let bytes: Int64 = switch detail.id {
                    case AARCH64_INS_STRB, AARCH64_INS_STURB: 1
                    case AARCH64_INS_STRH, AARCH64_INS_STURH: 2
                    default: Int64(source.widthBits / 8)
                    }
                    let (at, overflow) = offset.addingReportingOverflow(displacement)
                    let (element, elementOverflow) = at.addingReportingOverflow(Int64(index) * bytes)
                    guard !overflow, !elementOverflow else { return .unknown }
                    let value = bytes == 8 ? bits : bits & ((UInt64(1) << (bytes * 8)) - 1)
                    stores.append(LiteralStore(base: root, offset: element, bytes: bytes, value: value, source: source))
                }
            default:
                return .unknown
            }
        }
        guard (values[sp.key] ?? .input(sp, 0)) == .input(sp, 0),
              (values[lr.key] ?? .input(lr, 0)) == .input(lr, 0)
        else { return .unknown }
        return .literalStores(stores, inputs: inputs.sorted { $0.key < $1.key })
    }
}

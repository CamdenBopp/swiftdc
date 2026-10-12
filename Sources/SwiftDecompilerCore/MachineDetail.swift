import Ccapstone
import Foundation

/// A canonical ARM64 physical register.
///
/// Canonical means `w3` and `x3` collapse to the same register identity with
/// different widths — they are one architectural register, and dataflow must key
/// on the register, not the mnemonic spelling.
public struct PhysReg: Hashable, Sendable {
    public enum Kind: UInt8, Sendable {
        /// x0–x30 / w0–w30.
        case gpr
        /// v/q/d/s/h/b 0–31.
        case vector
        /// sp / wsp. Distinct from the zero register despite both encoding 31.
        case stackPointer
        /// xzr / wzr.
        case zero
        /// The condition flags.
        case nzcv
        /// Anything this canonicalizer does not model.
        case other
    }

    public let kind: Kind
    /// Register number within its bank (0–30 for gpr, 0–31 for vector).
    public let number: Int
    /// Access width. A 32-bit GPR write zeroes the upper half — callers that
    /// model values must account for that; this type only reports it.
    public let widthBits: Int

    public init(kind: Kind, number: Int, widthBits: Int) {
        self.kind = kind
        self.number = number
        self.widthBits = widthBits
    }

    /// Stable key for dataflow maps: width-independent, so `w3` and `x3` agree.
    public var key: String {
        switch kind {
        case .gpr: return "x\(number)"
        case .vector: return "v\(number)"
        case .stackPointer: return "sp"
        case .zero: return "xzr"
        case .nzcv: return "nzcv"
        case .other: return "reg\(number)"
        }
    }

    /// Canonicalize a raw Capstone register id.
    ///
    /// The register numbering has a trap that silently corrupts dataflow if
    /// missed: X0–X28 are contiguous at 238…266, but **X29 and X30 are not in
    /// that block** — they are `AARCH64_REG_FP` (2) and `AARCH64_REG_LR` (4), which
    /// are the *same* enum values, not aliases resolved by Capstone. Computing
    /// `raw - AARCH64_REG_X0` therefore yields a negative index for the frame
    /// pointer and link register. W0–W30 (207…237) *is* contiguous, which is
    /// what makes the asymmetry easy to miss. Likewise SP (6) and XZR (10) are
    /// distinct despite both encoding register 31 in the instruction word;
    /// conflating them makes every stack access alias the zero register.
    public static func canonical(_ raw: aarch64_reg) -> PhysReg? {
        let value = Int(raw.rawValue)
        switch value {
        case Int(AARCH64_REG_X29.rawValue): return PhysReg(kind: .gpr, number: 29, widthBits: 64)
        case Int(AARCH64_REG_X30.rawValue): return PhysReg(kind: .gpr, number: 30, widthBits: 64)
        case Int(AARCH64_REG_SP.rawValue): return PhysReg(kind: .stackPointer, number: 31, widthBits: 64)
        case Int(AARCH64_REG_WSP.rawValue): return PhysReg(kind: .stackPointer, number: 31, widthBits: 32)
        case Int(AARCH64_REG_XZR.rawValue): return PhysReg(kind: .zero, number: 31, widthBits: 64)
        case Int(AARCH64_REG_WZR.rawValue): return PhysReg(kind: .zero, number: 31, widthBits: 32)
        case Int(AARCH64_REG_NZCV.rawValue): return PhysReg(kind: .nzcv, number: 0, widthBits: 4)
        default: break
        }
        for bank in Self.banks where bank.range.contains(value) {
            return PhysReg(kind: bank.kind, number: value - bank.range.lowerBound, widthBits: bank.widthBits)
        }
        return value == Int(AARCH64_REG_INVALID.rawValue) ? nil : PhysReg(kind: .other, number: value, widthBits: 0)
    }

    /// Contiguous register banks, verified against capstone 6.0.100's aarch64.h.
    /// Capstone 6 has no separate `V` bank: a vector operand (`v0.4s`) is its
    /// `Q` register plus a vector-arrangement specifier.
    private static let banks: [(range: Range<Int>, kind: Kind, widthBits: Int)] = {
        func span(_ first: aarch64_reg, count: Int) -> Range<Int> {
            let low = Int(first.rawValue)
            return low ..< (low + count)
        }
        return [
            (span(AARCH64_REG_X0, count: 29), .gpr, 64),      // x0–x28 only; x29/x30 handled above
            (span(AARCH64_REG_W0, count: 31), .gpr, 32),      // w0–w30
            (span(AARCH64_REG_Q0, count: 32), .vector, 128),
            (span(AARCH64_REG_D0, count: 32), .vector, 64),
            (span(AARCH64_REG_S0, count: 32), .vector, 32),
            (span(AARCH64_REG_H0, count: 32), .vector, 16),
            (span(AARCH64_REG_B0, count: 32), .vector, 8),
        ]
    }()
}

/// One structurally-decoded operand.
public enum StructuredOperand: Sendable {
    case register(PhysReg)
    case immediate(Int64)
    case floatingPoint(Double)
    /// A memory reference. Note `aarch64_op_mem` carries **no access width and no
    /// scale** — the width comes from the instruction id, the index scale from
    /// the operand's own shift.
    case memory(base: PhysReg?, index: PhysReg?, displacement: Int64)
    case other

    public var register: PhysReg? {
        if case .register(let reg) = self { return reg }
        return nil
    }

    public var immediateValue: Int64? {
        if case .immediate(let value) = self { return value }
        return nil
    }

    public var floatingPointValue: Double? {
        if case .floatingPoint(let value) = self { return value }
        return nil
    }

    public var isMemory: Bool {
        if case .memory = self { return true }
        return false
    }
}

/// An operand plus the modifiers Capstone attaches to it.
public struct StructuredOperandInfo: Sendable {
    public let operand: StructuredOperand
    /// `(shifter, amount)` — e.g. `lsl #12`. Dropping this is a live source of
    /// wrong values: `sub sp, sp, #0x2, lsl #12` subtracts 8192, not 2.
    public let shift: (type: aarch64_shifter, amount: UInt32)
    /// Register extension on an index operand (`uxtw`, `sxtw`, …).
    public let extender: aarch64_extender
    /// Capstone's access flags (`CS_AC_READ` 1, `CS_AC_WRITE` 2). For a
    /// register operand they say whether the register is read, written or
    /// both (`movk` reads the register it writes). For a memory operand they
    /// describe the memory; its base and index registers are always read.
    public var access: UInt8 = 0

    public var isRead: Bool { access & 1 != 0 }
    public var isWritten: Bool { access & 2 != 0 }

    public var shiftedImmediate: Int64? {
        guard case .immediate(let value) = operand else { return nil }
        guard shift.type == AARCH64_SFT_LSL else { return value }
        return value << Int64(shift.amount)
    }
}

/// A structurally-decoded ARM64 instruction: what Capstone's detail mode already
/// knows, which the text form throws away.
public struct StructuredInsn: Sendable {
    /// Capstone's instruction id — a stable identity to switch on, unlike a
    /// mnemonic string.
    public let id: aarch64_insn
    /// Condition code. `AArch64CC_Invalid` for unconditional instructions.
    public let conditionCode: AArch64CC_CondCode
    public let updatesFlags: Bool
    /// The memory operand writes back to its base register.
    public let writeback: Bool
    /// Only meaningful with `writeback`: post-index rather than pre-index.
    public let postIndex: Bool
    public let operands: [StructuredOperandInfo]

    /// Every register this instruction reads, by key, from the operands'
    /// access flags plus the base and index of a memory operand. Implicit
    /// registers (a call's arguments, `ret`'s x30) are not operands and are
    /// not included.
    public var readRegisterKeys: Set<String> {
        var keys = Set<String>()
        for info in operands {
            switch info.operand {
            case .register(let register) where info.isRead && register.kind == .gpr:
                keys.insert(register.key)
            case .memory(let base, let index, _):
                if let base, base.kind == .gpr { keys.insert(base.key) }
                if let index, index.kind == .gpr { keys.insert(index.key) }
            default:
                break
            }
        }
        return keys
    }

    /// Every general register this instruction writes, by key: written
    /// register operands, and a writeback memory operand's base.
    public var writtenRegisterKeys: Set<String> {
        var keys = Set<String>()
        for info in operands {
            switch info.operand {
            case .register(let register) where info.isWritten && (register.kind == .gpr || register.kind == .stackPointer):
                keys.insert(register.key)
            case .memory(let base?, _, _) where writeback:
                keys.insert(base.key)
            default:
                break
            }
        }
        return keys
    }

    /// The last immediate operand — the target of a direct branch in every form
    /// (`b 0x…`, `cbz x0, 0x…`, `tbz w0, #3, 0x…`). Nil for indirect branches.
    public var branchTargetOperand: Int64? {
        operands.reversed().compactMap(\.operand.immediateValue).first
    }

    /// Decode from a Capstone instruction. Returns nil when detail is absent.
    ///
    /// The anonymous union in `cs_detail` imports as a *computed* Swift property
    /// that copies the whole 456-byte struct, so it is bound exactly once here
    /// rather than re-read per operand.
    static func decode(_ insn: cs_insn) -> StructuredInsn? {
        guard let detail = insn.detail else { return nil }
        let arm = detail.pointee.aarch64
        // Capstone 6 hands an alias (`cmp`, `mov`, `lsl`) over as its real
        // instruction's id plus `alias_id`, with the operands shaped as the
        // alias prints them. Key the id on the alias so id and operands agree,
        // then fold it onto the same-named real id where one exists (see
        // AArch64AliasCanon) so each mnemonic has one id to switch on.
        let rawID: UInt32 = insn.is_alias
            ? (AArch64AliasCanon.realID(for: insn.alias_id) ?? UInt32(truncatingIfNeeded: insn.alias_id))
            : insn.id
        var operands: [StructuredOperandInfo] = []
        operands.reserveCapacity(Int(arm.op_count))
        // A fixed-size C array imports as a tuple, which is not subscriptable.
        withUnsafeBytes(of: arm.operands) { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: cs_aarch64_op.self) else { return }
            for index in 0..<Int(arm.op_count) {
                let op = base[index]
                let value: StructuredOperand
                switch op.type {
                case AARCH64_OP_REG:
                    value = PhysReg.canonical(op.reg).map(StructuredOperand.register) ?? .other
                case AARCH64_OP_IMM, AARCH64_OP_CIMM:
                    value = .immediate(op.imm)
                case AARCH64_OP_FP:
                    value = .floatingPoint(op.fp)
                case AARCH64_OP_MEM:
                    value = .memory(
                        base: PhysReg.canonical(op.mem.base),
                        index: PhysReg.canonical(op.mem.index),
                        displacement: Int64(op.mem.disp)
                    )
                default:
                    value = .other
                }
                operands.append(
                    StructuredOperandInfo(
                        operand: value,
                        shift: (op.shift.type, op.shift.value),
                        extender: op.ext,
                        access: UInt8(truncatingIfNeeded: op.access.rawValue)
                    )
                )
            }
        }
        let id = aarch64_insn(rawValue: rawID)
        Self.unfoldShiftAlias(id, &operands)
        if arm.post_index { Self.unfoldPostIndex(&operands) }
        return StructuredInsn(
            id: id,
            conditionCode: arm.cc,
            updatesFlags: arm.update_flags,
            // Capstone 6 keeps writeback on the generic detail, not the
            // architecture struct.
            writeback: detail.pointee.writeback,
            postIndex: arm.post_index,
            operands: operands
        )
    }

    /// Capstone 6 prints the shift aliases with the shift folded onto the source
    /// operand: `lsl x0, x1, #2` is `[x0, x1 lsl #2]`, and `lsl x0, x1, x2`
    /// (LSLV) is `[x0, x1 lsl_reg x2]` with the shift *value* holding x2's
    /// register id. Capstone 5 gave three operands, `[x0, x1, #2]` and
    /// `[x0, x1, x2]`, and the value tracer reads the amount from operand 2.
    /// Restore that shape: the shift becomes its own operand and the source
    /// operand's shift is cleared, so the tracer does not apply it twice.
    private static func unfoldShiftAlias(_ id: aarch64_insn, _ operands: inout [StructuredOperandInfo]) {
        guard id == AARCH64_INS_LSL || id == AARCH64_INS_LSR || id == AARCH64_INS_ASR,
              operands.count == 2
        else { return }
        let source = operands[1]
        let amount: StructuredOperand
        switch source.shift.type {
        case AARCH64_SFT_LSL, AARCH64_SFT_LSR, AARCH64_SFT_ASR:
            amount = .immediate(Int64(source.shift.amount))
        case AARCH64_SFT_LSL_REG, AARCH64_SFT_LSR_REG, AARCH64_SFT_ASR_REG:
            guard let register = PhysReg.canonical(aarch64_reg(rawValue: source.shift.amount)) else { return }
            amount = .register(register)
        default:
            return
        }
        operands[1] = StructuredOperandInfo(
            operand: source.operand,
            shift: (AARCH64_SFT_INVALID, 0),
            extender: source.extender,
            access: source.access
        )
        operands.append(StructuredOperandInfo(operand: amount, shift: (AARCH64_SFT_INVALID, 0),
                                              extender: AARCH64_EXT_INVALID, access: 1))
    }

    /// Capstone 6 folds a post-index amount into the memory operand's
    /// displacement: `ldr x0, [x1], #8` is `[x0, mem(x1, disp 8)]` with
    /// `post_index` set. Capstone 5 left the displacement at 0 and appended the
    /// amount as a trailing immediate, which is where the tracer reads the
    /// base register's writeback delta. A post-index access reads the base
    /// itself, so the displacement must not stay on the memory operand either.
    private static func unfoldPostIndex(_ operands: inout [StructuredOperandInfo]) {
        guard operands.last?.operand.immediateValue == nil,
              let index = operands.firstIndex(where: { $0.operand.isMemory }),
              case .memory(let base, let indexRegister, let displacement) = operands[index].operand,
              displacement != 0
        else { return }
        let memory = operands[index]
        operands[index] = StructuredOperandInfo(
            operand: .memory(base: base, index: indexRegister, displacement: 0),
            shift: memory.shift,
            extender: memory.extender,
            access: memory.access
        )
        operands.append(StructuredOperandInfo(operand: .immediate(displacement), shift: (AARCH64_SFT_INVALID, 0), extender: AARCH64_EXT_INVALID))
    }
}

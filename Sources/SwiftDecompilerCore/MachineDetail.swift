import CCapstone
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
    /// missed: X0–X28 are contiguous at 218…246, but **X29 and X30 are not in
    /// that block** — they are `ARM64_REG_FP` (2) and `ARM64_REG_LR` (3), which
    /// are the *same* enum values, not aliases resolved by Capstone. Computing
    /// `raw - ARM64_REG_X0` therefore yields a negative index for the frame
    /// pointer and link register. W0–W30 (187…217) *is* contiguous, which is
    /// what makes the asymmetry easy to miss. Likewise SP (5) and XZR (9) are
    /// distinct despite both encoding register 31 in the instruction word;
    /// conflating them makes every stack access alias the zero register.
    public static func canonical(_ raw: arm64_reg) -> PhysReg? {
        let value = Int(raw.rawValue)
        switch value {
        case Int(ARM64_REG_X29.rawValue): return PhysReg(kind: .gpr, number: 29, widthBits: 64)
        case Int(ARM64_REG_X30.rawValue): return PhysReg(kind: .gpr, number: 30, widthBits: 64)
        case Int(ARM64_REG_SP.rawValue): return PhysReg(kind: .stackPointer, number: 31, widthBits: 64)
        case Int(ARM64_REG_WSP.rawValue): return PhysReg(kind: .stackPointer, number: 31, widthBits: 32)
        case Int(ARM64_REG_XZR.rawValue): return PhysReg(kind: .zero, number: 31, widthBits: 64)
        case Int(ARM64_REG_WZR.rawValue): return PhysReg(kind: .zero, number: 31, widthBits: 32)
        case Int(ARM64_REG_NZCV.rawValue): return PhysReg(kind: .nzcv, number: 0, widthBits: 4)
        default: break
        }
        for bank in Self.banks where bank.range.contains(value) {
            return PhysReg(kind: bank.kind, number: value - bank.range.lowerBound, widthBits: bank.widthBits)
        }
        return value == Int(ARM64_REG_INVALID.rawValue) ? nil : PhysReg(kind: .other, number: value, widthBits: 0)
    }

    /// Contiguous register banks, verified against Capstone 5.0.9's arm64.h.
    private static let banks: [(range: Range<Int>, kind: Kind, widthBits: Int)] = {
        func span(_ first: arm64_reg, count: Int) -> Range<Int> {
            let low = Int(first.rawValue)
            return low ..< (low + count)
        }
        return [
            (span(ARM64_REG_X0, count: 29), .gpr, 64),      // x0–x28 only; x29/x30 handled above
            (span(ARM64_REG_W0, count: 31), .gpr, 32),      // w0–w30
            (span(ARM64_REG_V0, count: 32), .vector, 128),
            (span(ARM64_REG_Q0, count: 32), .vector, 128),
            (span(ARM64_REG_D0, count: 32), .vector, 64),
            (span(ARM64_REG_S0, count: 32), .vector, 32),
            (span(ARM64_REG_H0, count: 32), .vector, 16),
            (span(ARM64_REG_B0, count: 32), .vector, 8),
        ]
    }()
}

/// One structurally-decoded operand.
public enum StructuredOperand: Sendable {
    case register(PhysReg)
    case immediate(Int64)
    case floatingPoint(Double)
    /// A memory reference. Note `arm64_op_mem` carries **no access width and no
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
}

/// An operand plus the modifiers Capstone attaches to it.
public struct StructuredOperandInfo: Sendable {
    public let operand: StructuredOperand
    /// `(shifter, amount)` — e.g. `lsl #12`. Dropping this is a live source of
    /// wrong values: `sub sp, sp, #0x2, lsl #12` subtracts 8192, not 2.
    public let shift: (type: arm64_shifter, amount: UInt32)
    /// Register extension on an index operand (`uxtw`, `sxtw`, …).
    public let extender: arm64_extender

    public var shiftedImmediate: Int64? {
        guard case .immediate(let value) = operand else { return nil }
        guard shift.type == ARM64_SFT_LSL else { return value }
        return value << Int64(shift.amount)
    }
}

/// A structurally-decoded ARM64 instruction: what Capstone's detail mode already
/// knows, which the text form throws away.
public struct StructuredInsn: Sendable {
    /// Capstone's instruction id — a stable identity to switch on, unlike a
    /// mnemonic string.
    public let id: arm64_insn
    /// Condition code. `ARM64_CC_INVALID` for unconditional instructions.
    public let conditionCode: arm64_cc
    public let updatesFlags: Bool
    /// The memory operand writes back to its base register.
    public let writeback: Bool
    /// Only meaningful with `writeback`: post-index rather than pre-index.
    public let postIndex: Bool
    public let operands: [StructuredOperandInfo]

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
        let arm = detail.pointee.arm64
        var operands: [StructuredOperandInfo] = []
        operands.reserveCapacity(Int(arm.op_count))
        // A fixed-size C array imports as a tuple, which is not subscriptable.
        withUnsafeBytes(of: arm.operands) { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: cs_arm64_op.self) else { return }
            for index in 0..<Int(arm.op_count) {
                let op = base[index]
                let value: StructuredOperand
                switch op.type {
                case ARM64_OP_REG:
                    value = PhysReg.canonical(op.reg).map(StructuredOperand.register) ?? .other
                case ARM64_OP_IMM, ARM64_OP_CIMM:
                    value = .immediate(op.imm)
                case ARM64_OP_FP:
                    value = .floatingPoint(op.fp)
                case ARM64_OP_MEM:
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
                        extender: op.ext
                    )
                )
            }
        }
        return StructuredInsn(
            id: arm64_insn(rawValue: insn.id),
            conditionCode: arm.cc,
            updatesFlags: arm.update_flags,
            writeback: arm.writeback,
            postIndex: arm.post_index,
            operands: operands
        )
    }
}

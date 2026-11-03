import Ccapstone

/// What a data-processing instruction computes, stated once for every
/// analysis that reads it. The value tracer evaluates a term over register
/// values; the structurer's text path renders it over register names. Two
/// copies of an instruction's meaning drift: the text path read `ubfx` as a
/// copy of its source while the tracer knew nothing of it.
///
/// A term names operands by their index in Capstone's detail. `operand`
/// reads one as the instruction does, its printed shift or extend applied;
/// `register` reads its register bare, for an alias whose extension Capstone
/// repeats on the operand (`sxtw x8, w0` carries SXTW on w0).
indirect enum SemanticTerm: Equatable, Sendable {
    case operand(Int)
    case register(Int)
    case constant(UInt64)
    case binary(AbstractBinaryOperator, SemanticTerm, SemanticTerm)
    case complement(SemanticTerm)
    /// The low `bits` of the value, sign-extended to 64.
    case signExtend(SemanticTerm, bits: Int)
    /// The low `bits` of the value.
    case zeroExtend(SemanticTerm, bits: Int)
}

/// An instruction's register result: the destination and its value. The
/// write itself (a W destination zero-extends) belongs to the reader.
struct SemanticEffect: Equatable, Sendable {
    let destination: PhysReg
    let value: SemanticTerm
}

enum InstructionSemantics {
    /// The instructions this table owns. For one of these, `effect` returning
    /// nil means its shape is one the table does not model, and the reader
    /// claims nothing about the destination.
    static func covers(_ id: aarch64_insn) -> Bool { owned.contains(id.rawValue) }

    private static let owned: Set<UInt32> = Set([
        AARCH64_INS_AND, AARCH64_INS_ANDS, AARCH64_INS_ORR, AARCH64_INS_EOR,
        AARCH64_INS_MUL, AARCH64_INS_SMULH, AARCH64_INS_UMULH,
        AARCH64_INS_LSL, AARCH64_INS_LSR, AARCH64_INS_ASR,
        AARCH64_INS_SDIV, AARCH64_INS_UDIV,
        AARCH64_INS_ALIAS_MVN, AARCH64_INS_ORN,
        AARCH64_INS_SXTB, AARCH64_INS_SXTH, AARCH64_INS_SXTW,
        AARCH64_INS_UXTB, AARCH64_INS_UXTH,
        AARCH64_INS_MOV, AARCH64_INS_MOVZ,
        AARCH64_INS_ALIAS_UBFX, AARCH64_INS_ALIAS_SBFX, AARCH64_INS_ALIAS_UBFIZ, AARCH64_INS_ALIAS_SBFIZ,
        AARCH64_INS_ALIAS_BFI, AARCH64_INS_ALIAS_BFXIL,
        AARCH64_INS_NEG, AARCH64_INS_ALIAS_NEG, AARCH64_INS_ALIAS_NEGS,
        AARCH64_INS_BIC, AARCH64_INS_ALIAS_BIC, AARCH64_INS_BICS, AARCH64_INS_ALIAS_BICS,
        AARCH64_INS_EON, AARCH64_INS_ALIAS_EON,
        AARCH64_INS_ALIAS_MNEG, AARCH64_INS_MOVN, AARCH64_INS_ALIAS_MOVN,
    ].map(\.rawValue))

    static func effect(of detail: StructuredInsn) -> SemanticEffect? {
        guard let dest = detail.operands.first?.operand.register else { return nil }
        let operands = detail.operands
        func isScalar(_ register: PhysReg) -> Bool { register.kind == .gpr || register.kind == .zero }

        switch detail.id {
        case AARCH64_INS_AND, AARCH64_INS_ANDS, AARCH64_INS_ORR, AARCH64_INS_EOR,
             AARCH64_INS_MUL, AARCH64_INS_SMULH, AARCH64_INS_UMULH,
             AARCH64_INS_LSL, AARCH64_INS_LSR, AARCH64_INS_ASR,
             AARCH64_INS_SDIV, AARCH64_INS_UDIV:
            guard operands.count >= 3 else { return nil }
            let op: AbstractBinaryOperator = switch detail.id {
            case AARCH64_INS_AND, AARCH64_INS_ANDS: .bitAnd
            case AARCH64_INS_ORR: .bitOr
            case AARCH64_INS_EOR: .bitXor
            case AARCH64_INS_MUL: .multiply
            case AARCH64_INS_SMULH: .multiplyHigh
            case AARCH64_INS_UMULH: .unsignedMultiplyHigh
            case AARCH64_INS_SDIV: .divide
            case AARCH64_INS_UDIV: .unsignedDivide
            case AARCH64_INS_LSL: .shiftLeft
            case AARCH64_INS_LSR: .shiftRight
            default: .arithmeticShiftRight
            }
            var lhs = SemanticTerm.operand(1)
            // A 32-bit arithmetic shift shifts in the 32-bit sign: `asr w0,
            // w8, #31` of 0x80000001 is 0xffffffff, not 1.
            if dest.widthBits == 32, op == .arithmeticShiftRight || op == .divide {
                lhs = .signExtend(lhs, bits: 32)
            }
            var rhs = SemanticTerm.operand(2)
            if op == .divide, dest.widthBits == 32 { rhs = .signExtend(rhs, bits: 32) }
            if op == .shiftLeft || op == .shiftRight || op == .arithmeticShiftRight {
                rhs = .binary(.bitAnd, rhs, .constant(UInt64(dest.widthBits - 1)))
            }
            return SemanticEffect(destination: dest, value: .binary(op, lhs, rhs))

        case AARCH64_INS_ALIAS_MVN, AARCH64_INS_ORN:
            // MVN is ORN with a zero first operand: complement the optionally
            // shifted source before OR.
            let count = detail.id == AARCH64_INS_ALIAS_MVN ? 2 : 3
            guard isScalar(dest), operands.count == count,
                  operands.dropFirst().allSatisfy({ operand in
                      guard let register = operand.operand.register else { return false }
                      return isScalar(register) && register.widthBits == dest.widthBits
                  })
            else { return nil }
            let inverted = SemanticTerm.complement(.operand(count - 1))
            return SemanticEffect(destination: dest,
                                  value: count == 2 ? inverted : .binary(.bitOr, .operand(1), inverted))

        case AARCH64_INS_SXTB, AARCH64_INS_SXTH, AARCH64_INS_SXTW,
             AARCH64_INS_UXTB, AARCH64_INS_UXTH:
            // The low byte, halfword or word, extended. Read bare: Capstone may
            // repeat the alias's extension on the operand.
            guard dest.kind == .gpr, operands.count == 2,
                  let input = operands[1].operand.register, input.kind == .gpr
            else { return nil }
            let bits: Int = switch detail.id {
            case AARCH64_INS_SXTB, AARCH64_INS_UXTB: 8
            case AARCH64_INS_SXTH, AARCH64_INS_UXTH: 16
            default: 32
            }
            let signed = detail.id == AARCH64_INS_SXTB || detail.id == AARCH64_INS_SXTH || detail.id == AARCH64_INS_SXTW
            return SemanticEffect(destination: dest,
                                  value: signed ? .signExtend(.register(1), bits: bits) : .zeroExtend(.register(1), bits: bits))

        case AARCH64_INS_MOV, AARCH64_INS_MOVZ:
            // Capstone pre-folds MOVZ's shift into the immediate. A lane move
            // (`ins`/`umov`, `mov v0.d[1], x2`) writes or reads one element,
            // not the register: modelled as a whole move, `fmov d0, x1; mov
            // v0.d[1], x2; str q0, [x0]` stored `arg2` alone.
            guard operands.count >= 2, operands.allSatisfy({ $0.vectorIndex == nil }) else { return nil }
            return SemanticEffect(destination: dest, value: .operand(1))

        case AARCH64_INS_ALIAS_UBFX, AARCH64_INS_ALIAS_SBFX, AARCH64_INS_ALIAS_UBFIZ, AARCH64_INS_ALIAS_SBFIZ,
             AARCH64_INS_ALIAS_BFI, AARCH64_INS_ALIAS_BFXIL:
            // `op d, s, #lsb, #width` on a field of `width` bits (Arm ARM
            // UBFM/SBFM/BFM aliases): ubfx `(s >> lsb) & mask`, ubfiz `(s &
            // mask) << lsb`, sbfx/sbfiz the same field sign-extended from
            // its top bit, bfxil/bfi that field inserted into d, d's other
            // bits kept.
            guard dest.kind == .gpr, operands.count == 4,
                  let source = operands[1].operand.register, isScalar(source), source.widthBits == dest.widthBits,
                  let lsb = operands[2].operand.immediateValue, let width = operands[3].operand.immediateValue,
                  lsb >= 0, width >= 1, lsb + width <= Int64(dest.widthBits)
            else { return nil }
            let mask: UInt64 = width == 64 ? .max : (1 << UInt64(width)) - 1
            func shifted(_ term: SemanticTerm, _ op: AbstractBinaryOperator) -> SemanticTerm {
                lsb == 0 ? term : .binary(op, term, .constant(UInt64(lsb)))
            }
            let field = SemanticTerm.binary(.bitAnd, shifted(.operand(1), .shiftRight), .constant(mask))
            let low = SemanticTerm.binary(.bitAnd, .operand(1), .constant(mask))
            let value: SemanticTerm = switch detail.id {
            case AARCH64_INS_ALIAS_UBFX: field
            case AARCH64_INS_ALIAS_SBFX: .signExtend(field, bits: Int(width))
            case AARCH64_INS_ALIAS_UBFIZ: shifted(low, .shiftLeft)
            case AARCH64_INS_ALIAS_SBFIZ: shifted(.signExtend(low, bits: Int(width)), .shiftLeft)
            case AARCH64_INS_ALIAS_BFXIL: .binary(.bitOr, .binary(.bitAnd, .register(0), .constant(~mask)), field)
            default: .binary(.bitOr, .binary(.bitAnd, .register(0), .constant(~(mask << UInt64(lsb)))),
                             shifted(low, .shiftLeft))
            }
            return SemanticEffect(destination: dest, value: value)

        case AARCH64_INS_NEG, AARCH64_INS_ALIAS_NEG, AARCH64_INS_ALIAS_NEGS:
            // `neg d, s{, shift}` is `0 - s`, the shift applied to s. The
            // flags `negs` sets are the reader's to clear.
            guard dest.kind == .gpr, operands.count == 2, let source = operands[1].operand.register,
                  isScalar(source), source.widthBits == dest.widthBits
            else { return nil }
            return SemanticEffect(destination: dest, value: .binary(.subtract, .constant(0), .operand(1)))

        case AARCH64_INS_BIC, AARCH64_INS_ALIAS_BIC, AARCH64_INS_BICS, AARCH64_INS_ALIAS_BICS,
             AARCH64_INS_EON, AARCH64_INS_ALIAS_EON, AARCH64_INS_ALIAS_MNEG:
            // `bic d, n, m` is `n & ~m` and `eon` is `n ^ ~m`, m shifted
            // before the complement; `mneg` is `0 - n * m`.
            guard isScalar(dest), operands.count == 3,
                  operands.dropFirst().allSatisfy({ operand in
                      guard let register = operand.operand.register else { return false }
                      return isScalar(register) && register.widthBits == dest.widthBits
                  })
            else { return nil }
            let value: SemanticTerm = switch detail.id {
            case AARCH64_INS_ALIAS_MNEG: .binary(.subtract, .constant(0), .binary(.multiply, .operand(1), .operand(2)))
            case AARCH64_INS_EON, AARCH64_INS_ALIAS_EON: .binary(.bitXor, .operand(1), .complement(.operand(2)))
            default: .binary(.bitAnd, .operand(1), .complement(.operand(2)))
            }
            return SemanticEffect(destination: dest, value: value)

        case AARCH64_INS_MOVN, AARCH64_INS_ALIAS_MOVN:
            // `movn d, #imm{, lsl #s}` is `~(imm << s)`; Capstone folds the
            // shift into the operand.
            guard dest.kind == .gpr, operands.count == 2, operands[1].operand.register == nil else { return nil }
            return SemanticEffect(destination: dest, value: .complement(.operand(1)))

        default:
            return nil
        }
    }
}

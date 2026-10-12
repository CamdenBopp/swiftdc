import Ccapstone
import Foundation
import MachOKit

/// LLVM's compressed AArch64 jump table, recovered only where its bound is
/// proven.
///
/// The lowering (clang and swiftc alike):
///
///     cmp   xI, #k          ; the guard
///     b.hi  default         ; index > k (unsigned) leaves
///     adrp  xB, table@PAGE
///     add   xB, xB, table@PAGEOFF
///     adr   xA, anchor
///     ldrb  wE, [xB, xI]            (or ldrh wE, [xB, xI, lsl #1])
///     add   xT, xA, xE, lsl #2
///     br    xT
///
/// Case i branches to `anchor + 4 * table[i]` for i in 0...k. arm64e system
/// code uses the hardened form instead (`-faarch64-jump-table-hardening`): the
/// index is clamped in the same block, `cmp xI, #k; csel xI, xI, xzr, ls`, so
/// an out-of-range index takes case 0, and the entries are signed 32-bit byte
/// offsets, `ldrsw xE, [xB, xI, lsl #2]; adr xA, #0; add xT, xA, xE`. The
/// clamp is the bound. A `br` with no
/// recovered targets orphaned every arm from the CFG. A table is accepted only
/// when every link holds: each register's last definition before its use is
/// the expected instruction, the table block is entered only by the guard's
/// fall-through, the guard compares the very index register (not narrower
/// than the load uses it) and nothing writes it in between, the entries are
/// file-backed, and every target is an instruction of this function. Anything
/// else declines and the `br` keeps no successors, as before.
enum JumpTables {
    /// `br` address → target of each case, in case order.
    static func recognize(
        in function: DisassembledFunction, machO: MachOFile
    ) -> [UInt64: [UInt64]] {
        guard let ranges = FileBackedRanges(standalone: machO) else { return [:] }
        let instructions = function.instructions
        guard instructions.contains(where: { $0.detail?.id == AARCH64_INS_BR }) else { return [:] }
        let addresses = Set(instructions.map(\.address))
        let internalTargets = Set(instructions.compactMap(\.branchTarget).filter(addresses.contains))
        var tables: [UInt64: [UInt64]] = [:]
        for index in instructions.indices where instructions[index].detail?.id == AARCH64_INS_BR {
            if let targets = table(endingAt: index, in: instructions, addresses: addresses,
                                   internalTargets: internalTargets, machO: machO, ranges: ranges) {
                tables[instructions[index].address] = targets
            }
        }
        return tables
    }

    private static func table(
        endingAt branchIndex: Int, in instructions: [Instruction], addresses: Set<UInt64>,
        internalTargets: Set<UInt64>, machO: MachOFile, ranges: FileBackedRanges
    ) -> [UInt64]? {
        guard let branch = instructions[branchIndex].detail, branch.operands.count == 1,
              let targetRegister = branch.operands[0].operand.register
        else { return nil }

        // The table block: back to its leader (a branch target, or the
        // instruction after control flow).
        var start = branchIndex
        while start > 0 {
            if internalTargets.contains(instructions[start].address) { break }
            if let flow = instructions[start - 1].controlFlow, flow != .sequential, flow != .call { break }
            start -= 1
        }
        let block = Array(instructions[start ..< branchIndex])

        /// The last instruction in the block before `position` that writes `key`.
        /// A call clobbers the caller-saved registers, so it counts as the
        /// definition of one, and matches no expected shape.
        func definition(of key: String, before position: Int) -> (index: Int, detail: StructuredInsn)? {
            for index in stride(from: position - 1, through: 0, by: -1) {
                guard let detail = block[index].detail else { return nil }
                if block[index].controlFlow == .call, callerSaved.contains(key) { return (index, detail) }
                if writes(detail, key) { return (index, detail) }
            }
            return nil
        }

        // add xT, xA, xE (lsl #2 for a compressed table)
        guard let sum = definition(of: targetRegister.key, before: block.count),
              sum.detail.id == AARCH64_INS_ADD, sum.detail.operands.count == 3,
              let anchorRegister = sum.detail.operands[1].operand.register,
              let entryRegister = sum.detail.operands[2].operand.register,
              sum.detail.operands[2].extender == AARCH64_EXT_INVALID || sum.detail.operands[2].extender == AARCH64_EXT_UXTW
        else { return nil }
        let sumShift = sum.detail.operands[2].shift.type == AARCH64_SFT_INVALID ? 0 : Int(sum.detail.operands[2].shift.amount)
        // adr xA, anchor
        guard let anchorDefinition = definition(of: anchorRegister.key, before: sum.index),
              anchorDefinition.detail.id == AARCH64_INS_ADR,
              let anchorImmediate = anchorDefinition.detail.operands.last?.operand.immediateValue
        else { return nil }
        // ldrb wE, [xB, xI] / ldrh wE, [xB, xI, lsl #1] (scaled by 4 in the
        // add), or the hardened ldrsw xE, [xB, xI, lsl #2] (unscaled, signed).
        guard let load = definition(of: entryRegister.key, before: sum.index),
              !load.detail.writeback, load.detail.operands.count == 2,
              case .memory(let base?, let indexRegister?, 0) = load.detail.operands[1].operand
        else { return nil }
        let entrySize: Int
        switch load.detail.id {
        case AARCH64_INS_LDRB: entrySize = 1
        case AARCH64_INS_LDRH: entrySize = 2
        case AARCH64_INS_LDRSW: entrySize = 4
        default: return nil
        }
        let signedEntries = entrySize == 4
        guard sumShift == (signedEntries ? 0 : 2) else { return nil }
        let memory = load.detail.operands[1]
        let expectedShift: UInt32 = entrySize == 1 ? 0 : (entrySize == 2 ? 1 : 2)
        guard memory.shift.amount == expectedShift,
              memory.shift.type == (expectedShift == 0 ? memory.shift.type : AARCH64_SFT_LSL),
              memory.extender == AARCH64_EXT_INVALID || memory.extender == AARCH64_EXT_UXTW
        else { return nil }
        let loadUsesLow32 = memory.extender == AARCH64_EXT_UXTW || indexRegister.widthBits == 32
        // add xB, xB, #lo after adrp xB, page
        guard let low = definition(of: base.key, before: load.index),
              low.detail.id == AARCH64_INS_ADD, low.detail.operands.count == 3,
              low.detail.operands[1].operand.register?.key == base.key,
              let lowImmediate = low.detail.operands[2].operand.immediateValue,
              let page = definition(of: base.key, before: low.index),
              page.detail.id == AARCH64_INS_ADRP,
              let pageImmediate = page.detail.operands.last?.operand.immediateValue
        else { return nil }
        let tableAddress = UInt64(bitPattern: pageImmediate) &+ UInt64(lowImmediate)
        var limit: UInt64?
        if let clamp = definition(of: indexRegister.key, before: load.index) {
            // The hardened bound: `cmp xS, #k; csel xI, xS, xzr, ls`, in this block.
            guard signedEntries, clamp.detail.id == AARCH64_INS_CSEL,
                  clamp.detail.conditionCode == AArch64CC_LS, clamp.detail.operands.count == 3,
                  let source = clamp.detail.operands[1].operand.register,
                  clamp.detail.operands[2].operand.register?.kind == .zero,
                  clamp.detail.operands[0].operand.register?.widthBits == 64 || loadUsesLow32
            else { return nil }
            for index in stride(from: clamp.index - 1, through: 0, by: -1) {
                guard let detail = block[index].detail else { return nil }
                if detail.id == AARCH64_INS_ALIAS_CMP || detail.id == AARCH64_INS_SUBS {
                    let operands = detail.id == AARCH64_INS_SUBS ? Array(detail.operands.dropFirst()) : detail.operands
                    guard operands.count == 2, operands[0].operand.register?.key == source.key,
                          let k = operands[1].shiftedImmediate, k >= 0
                    else { return nil }
                    limit = UInt64(k)
                    break
                }
                if detail.updatesFlags || writes(detail, source.key) { return nil }
            }
            guard limit != nil else { return nil }
        }

        // Otherwise the guard: the block before is entered only by fall-through
        // from `b.hi`, after `cmp xI, #k` with nothing writing xI in between.
        if limit == nil {
        guard start >= 2, !internalTargets.contains(instructions[start].address),
              let conditional = instructions[start - 1].detail,
              conditional.id == AARCH64_INS_B, conditional.conditionCode == AArch64CC_HI
        else { return nil }
        for index in stride(from: start - 2, through: 0, by: -1) {
            let insn = instructions[index]
            guard let detail = insn.detail else { return nil }
            if let flow = insn.controlFlow, flow != .sequential { return nil }
            if detail.id == AARCH64_INS_ALIAS_CMP || detail.id == AARCH64_INS_SUBS {
                // `cmp xI, #k` (Capstone: `subs xzr, xI, #k` or its CMP alias).
                let operands = detail.id == AARCH64_INS_SUBS ? Array(detail.operands.dropFirst()) : detail.operands
                guard operands.count == 2, let compared = operands[0].operand.register,
                      compared.key == indexRegister.key,
                      let k = operands[1].shiftedImmediate, k >= 0,
                      // A 32-bit compare bounds only the low half: the load
                      // must read only that half.
                      compared.widthBits == 64 || loadUsesLow32
                else { return nil }
                limit = UInt64(k)
                break
            }
            if detail.updatesFlags || writes(detail, indexRegister.key) { return nil }
            if internalTargets.contains(insn.address) { return nil }
        }
        }
        guard let limit, limit < 4096 else { return nil }

        let count = Int(limit) + 1
        guard ranges.holdsBytes(at: tableAddress, count: count * entrySize),
              let (offset, _) = ranges.fileBytes(at: tableAddress),
              let bytes: [UInt8] = try? machO.readElements(offset: offset, numberOfElements: count * entrySize)
        else { return nil }
        let anchor = UInt64(bitPattern: anchorImmediate)
        var targets: [UInt64] = []
        for case_ in 0 ..< count {
            let target: UInt64
            switch entrySize {
            case 1:
                target = anchor &+ UInt64(bytes[case_]) &* 4
            case 2:
                target = anchor &+ (UInt64(bytes[2 * case_]) | UInt64(bytes[2 * case_ + 1]) << 8) &* 4
            default:
                let raw = (0 ..< 4).reduce(UInt32(0)) { $0 | UInt32(bytes[4 * case_ + $1]) << (8 * UInt32($1)) }
                target = anchor &+ UInt64(bitPattern: Int64(Int32(bitPattern: raw)))
            }
            guard addresses.contains(target) else { return nil }
            targets.append(target)
        }
        return targets
    }

    private static let callerSaved: Set<String> = Set((0...17).map { "x\($0)" } + ["x30"])

    /// Whether `detail` writes the register with `key` (its first operand, the
    /// destination for every instruction this recognizer looks at, plus the
    /// second destination of a load pair).
    private static func writes(_ detail: StructuredInsn, _ key: String) -> Bool {
        switch detail.id {
        case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP, AARCH64_INS_STRB, AARCH64_INS_STRH,
             AARCH64_INS_ALIAS_CMP, AARCH64_INS_ALIAS_CMN, AARCH64_INS_ALIAS_TST, AARCH64_INS_CCMP, AARCH64_INS_CCMN:
            return detail.writeback && detail.operands.contains { $0.operand.isMemory && memoryBase($0)?.key == key }
        case AARCH64_INS_LDP, AARCH64_INS_LDPSW:
            return detail.operands.prefix(2).contains { $0.operand.register?.key == key }
        default:
            if detail.writeback, detail.operands.contains(where: { $0.operand.isMemory && memoryBase($0)?.key == key }) {
                return true
            }
            return detail.operands.first?.operand.register?.key == key
        }
    }

    private static func memoryBase(_ operand: StructuredOperandInfo) -> PhysReg? {
        if case .memory(let base, _, _) = operand.operand { return base }
        return nil
    }
}

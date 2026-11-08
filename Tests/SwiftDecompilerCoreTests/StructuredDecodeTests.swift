import Testing
import Foundation
import Ccapstone
@testable import SwiftDecompilerCore

/// Register canonicalization. X29/X30 are NOT in the contiguous X0–X28 block —
/// they are AARCH64_REG_FP (2) and AARCH64_REG_LR (3), the same enum values — so
/// `raw - AARCH64_REG_X0` yields a negative index for them. SP and XZR are
/// distinct despite both encoding register 31.
@Test func canonicalizesRegisterTraps() {
    #expect(PhysReg.canonical(AARCH64_REG_X0) == PhysReg(kind: .gpr, number: 0, widthBits: 64))
    #expect(PhysReg.canonical(AARCH64_REG_X28) == PhysReg(kind: .gpr, number: 28, widthBits: 64))

    // The trap: these are FP/LR, outside the X block.
    #expect(PhysReg.canonical(AARCH64_REG_X29) == PhysReg(kind: .gpr, number: 29, widthBits: 64))
    #expect(PhysReg.canonical(AARCH64_REG_X30) == PhysReg(kind: .gpr, number: 30, widthBits: 64))
    #expect(PhysReg.canonical(AARCH64_REG_FP)?.number == 29)
    #expect(PhysReg.canonical(AARCH64_REG_LR)?.number == 30)

    // w3 and x3 are one register at two widths, and must key identically.
    #expect(PhysReg.canonical(AARCH64_REG_W3)?.number == 3)
    #expect(PhysReg.canonical(AARCH64_REG_W3)?.widthBits == 32)
    #expect(PhysReg.canonical(AARCH64_REG_W3)?.key == PhysReg.canonical(AARCH64_REG_X3)?.key)

    // Both encode 31; conflating them aliases every stack access to zero.
    #expect(PhysReg.canonical(AARCH64_REG_SP)?.kind == .stackPointer)
    #expect(PhysReg.canonical(AARCH64_REG_XZR)?.kind == .zero)
    #expect(PhysReg.canonical(AARCH64_REG_SP)?.key != PhysReg.canonical(AARCH64_REG_XZR)?.key)

    #expect(PhysReg.canonical(AARCH64_REG_INVALID) == nil)
}

private func decode(_ bytes: [UInt8], at address: UInt64 = 0x1000) -> [DecodedInstruction] {
    guard let engine = CapstoneEngine() else { return [] }
    return engine.disassemble(Data(bytes), address: address)
}

/// The structured form carries the shift that the text form drops.
///
/// `sub sp, sp, #0x2, lsl #12` subtracts 8192, not 2. Text parsing reads
/// operand[2] (`#0x2`) and ignores operand[3] (`lsl #12`), which is a value
/// wrong by 4096x — and it is *fabricated*, not missing.
@Test func decodesShiftedImmediates() throws {
    // sub sp, sp, #0x2, lsl #12 ; add x0, x0, #0x1, lsl #12
    let insns = decode([0xff, 0x0b, 0x40, 0xd1, 0x00, 0x04, 0x40, 0x91])
    #expect(insns.count == 2)

    let sub = try #require(insns[0].detail)
    #expect(sub.id == AARCH64_INS_SUB)
    #expect(sub.operands.count == 3)
    #expect(sub.operands[2].operand.immediateValue == 2)          // raw immediate
    #expect(sub.operands[2].shift.type == AARCH64_SFT_LSL)
    #expect(sub.operands[2].shift.amount == 12)
    #expect(sub.operands[2].shiftedImmediate == 8192)             // the real value

    let add = try #require(insns[1].detail)
    #expect(add.operands[2].shiftedImmediate == 4096)
}

/// Shifted *register* operands, memory displacement, and writeback flags.
@Test func decodesRegisterShiftsAndMemory() throws {
    // add x0, x1, x2, lsl #3 ; ldr x1, [x8, #0x578] ; stp x29, x30, [sp, #-0x20]!
    let insns = decode([
        0x20, 0x0c, 0x02, 0x8b,
        0x01, 0xbd, 0x42, 0xf9,
        0xfd, 0x7b, 0xbe, 0xa9,
    ])
    #expect(insns.count == 3)

    let add = try #require(insns[0].detail)
    #expect(add.operands[2].operand.register?.number == 2)
    #expect(add.operands[2].shift.type == AARCH64_SFT_LSL)
    #expect(add.operands[2].shift.amount == 3)

    let ldr = try #require(insns[1].detail)
    guard case .memory(let base, let index, let displacement) = ldr.operands[1].operand else {
        Issue.record("expected a memory operand"); return
    }
    #expect(base?.number == 8)
    #expect(index == nil)
    #expect(displacement == 0x578)
    #expect(ldr.writeback == false)

    // Writeback is a flag, not something to infer from a trailing `!` in text.
    let stp = try #require(insns[2].detail)
    #expect(stp.writeback == true)
    #expect(stp.postIndex == false)
    // Capstone reports x29/x30 here — the FP/LR aliases the canonicalizer maps.
    #expect(stp.operands[0].operand.register?.number == 29)
    #expect(stp.operands[1].operand.register?.number == 30)
    guard case .memory(_, _, let stpDisplacement) = stp.operands[2].operand else {
        Issue.record("expected a memory operand"); return
    }
    #expect(stpDisplacement == -0x20)
}

/// Capstone 6 reports `cmp`, `mov`, `lsl`, `mul`, `cset`, `tst` as aliases of the
/// real instruction they encode (`subs`, `orr`/`movz`, `ubfm`/`lslv`, `madd`,
/// `csinc`, `ands`), with the operands shaped as the alias prints them. The
/// value tracer switches on one id per mnemonic with those operands, so the
/// decoder must key the id on the alias and fold it onto the same-named real id
/// where Capstone 6 has one. Keying on the real id instead would hand the
/// `subs` case the two operands of `cmp`, and a `mov` would read as `orr`.
@Test func decodesAliasesAsOneIdPerMnemonic() throws {
    // cmp x0, x1 ; mov x0, x1 ; mov w0, #1 ; lsl x0, x1, #2 ; mul x0, x1, x2 ;
    // cset w0, eq ; tst w0, #1 ; cmp w8, #0
    let insns = decode([
        0x1f, 0x00, 0x01, 0xeb,
        0xe0, 0x03, 0x01, 0xaa,
        0x20, 0x00, 0x80, 0x52,
        0x20, 0xf4, 0x7e, 0xd3,
        0x20, 0x7c, 0x02, 0x9b,
        0xe0, 0x17, 0x9f, 0x1a,
        0x1f, 0x00, 0x00, 0x72,
        0x1f, 0x01, 0x00, 0x71,
    ])
    #expect(insns.count == 8)

    let cmp = try #require(insns[0].detail)
    #expect(cmp.id == AARCH64_INS_ALIAS_CMP)
    #expect(cmp.operands.count == 2)
    #expect(cmp.operands[0].operand.register?.number == 0)
    #expect(cmp.operands[1].operand.register?.number == 1)
    #expect(cmp.updatesFlags)

    let movReg = try #require(insns[1].detail)
    #expect(movReg.id == AARCH64_INS_MOV)
    #expect(movReg.operands.count == 2)
    #expect(movReg.operands[1].operand.register?.number == 1)

    let movImm = try #require(insns[2].detail)
    #expect(movImm.id == AARCH64_INS_MOV)
    #expect(movImm.operands.count == 2)
    #expect(movImm.operands[1].operand.immediateValue == 1)

    let lsl = try #require(insns[3].detail)
    #expect(lsl.id == AARCH64_INS_LSL)
    #expect(lsl.operands.count == 3)
    #expect(lsl.operands[2].operand.immediateValue == 2)

    let mul = try #require(insns[4].detail)
    #expect(mul.id == AARCH64_INS_MUL)
    #expect(mul.operands.count == 3)
    #expect(mul.operands[2].operand.register?.number == 2)

    let cset = try #require(insns[5].detail)
    #expect(cset.id == AARCH64_INS_ALIAS_CSET)
    #expect(cset.conditionCode == AArch64CC_EQ)
    #expect(cset.operands.first?.operand.register?.number == 0)

    let tst = try #require(insns[6].detail)
    #expect(tst.id == AARCH64_INS_ALIAS_TST)
    #expect(tst.operands.count == 2)
    #expect(tst.operands[1].operand.immediateValue == 1)
    #expect(tst.updatesFlags)

    let cmpImm = try #require(insns[7].detail)
    #expect(cmpImm.id == AARCH64_INS_ALIAS_CMP)
    #expect(cmpImm.operands[1].operand.immediateValue == 0)
}

/// A post-index access reads the base itself and applies the displacement
/// afterwards. The tracer expects the shape Capstone 5 gave: `mem.disp` is 0 and
/// the post-index amount is a separate trailing immediate operand, with the
/// `writeback` and `postIndex` flags set.
@Test func decodesPostIndexAsTrailingImmediate() throws {
    // ldr x0, [x1], #8 ; ldp x29, x30, [sp], #0x10 ; str x0, [sp, #-16]!
    let insns = decode([
        0x20, 0x84, 0x40, 0xf8,
        0xfd, 0x7b, 0xc1, 0xa8,
        0xe0, 0x0f, 0x1f, 0xf8,
    ])
    #expect(insns.count == 3)

    let ldr = try #require(insns[0].detail)
    #expect(ldr.id == AARCH64_INS_LDR)
    #expect(ldr.writeback)
    #expect(ldr.postIndex)
    guard case .memory(let base, _, let displacement) = ldr.operands[1].operand else {
        Issue.record("expected a memory operand"); return
    }
    #expect(base?.number == 1)
    #expect(displacement == 0)
    #expect(ldr.operands.last?.operand.immediateValue == 8)

    let ldp = try #require(insns[1].detail)
    #expect(ldp.writeback)
    #expect(ldp.postIndex)
    #expect(ldp.operands.last?.operand.immediateValue == 0x10)

    let str = try #require(insns[2].detail)
    #expect(str.writeback)
    #expect(!str.postIndex)
    guard case .memory(_, _, let preDisplacement) = str.operands[1].operand else {
        Issue.record("expected a memory operand"); return
    }
    #expect(preDisplacement == -16)
}

/// `braa`/`braaz` are UNCONDITIONAL indirect tail calls. Classifying them as
/// conditional makes `CFG.successors` invent a fall-through edge that does not
/// exist — on every arm64e stub island and tail call.
@Test func classifiesPointerAuthBranchesAsUnconditional() {
    // braa x16, x17 ; braaz x8
    let insns = decode([0x11, 0x0a, 0x1f, 0xd7, 0x1f, 0x09, 0x1f, 0xd6])
    #expect(insns.count == 2)
    #expect(insns[0].mnemonic == "braa")
    #expect(insns[0].controlFlow == .branch)       // was .conditionalBranch
    #expect(insns[0].branchTarget == nil)          // indirect: no static target
    #expect(insns[1].mnemonic == "braaz")
    #expect(insns[1].controlFlow == .branch)
}

/// Real conditional branches must stay conditional, and direct targets must
/// still resolve now that they come from the immediate operand rather than the
/// last hex substring of the text.
@Test func classifiesRealBranchesAndResolvesTargets() {
    // b.eq L ; cbz x0, L ; b L ; L: nop — assembled, so the offsets are real.
    // Loaded at 0x1000, L lands on the nop at 0x100c.
    let insns = decode([
        0x60, 0x00, 0x00, 0x54,
        0x40, 0x00, 0x00, 0xb4,
        0x01, 0x00, 0x00, 0x14,
        0x1f, 0x20, 0x03, 0xd5,
    ])
    #expect(insns.count == 4)
    #expect(insns[0].controlFlow == .conditionalBranch)   // b.eq: a real cc
    #expect(insns[0].branchTarget == 0x100c)
    #expect(insns[1].controlFlow == .conditionalBranch)   // cbz: condition in the opcode, cc is INVALID
    #expect(insns[1].branchTarget == 0x100c)
    #expect(insns[2].controlFlow == .branch)              // b: unconditional
    #expect(insns[2].branchTarget == 0x100c)
    #expect(insns[3].controlFlow == .sequential)
    #expect(insns[3].branchTarget == nil)
}

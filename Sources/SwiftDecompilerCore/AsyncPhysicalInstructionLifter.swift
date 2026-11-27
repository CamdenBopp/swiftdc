/// Local ARM64 effects used by the checked async interval. Width, addressing
/// mode and writeback come from the actual instruction word. Unsupported
/// instructions remain unresolved; no instruction is skipped by its mnemonic.
enum AsyncPhysicalInstructionLifter {
    typealias Effect = AsyncClosedCallerSolver.Effect

    static func lift(_ word: UInt32, at site: UInt64, flow: ControlFlow,
                     successors: [UInt64]) -> [Effect]? {
        let dest = Int(word & 31)
        let rn = Int((word >> 5) & 31)
        let rm = Int((word >> 16) & 31)

        func signExtend(_ raw: UInt32, bits: Int) -> Int {
            Int(Int32(bitPattern: raw << (32 - bits)) >> (32 - bits))
        }

        if flow == .branch {
            guard successors.count == 1, word & 0xfc00_0000 == 0x1400_0000 else { return nil }
            let delta = signExtend(word & 0x03ff_ffff, bits: 26) * 4
            let (destination, overflow) = delta >= 0
                ? site.addingReportingOverflow(UInt64(delta))
                : site.subtractingReportingOverflow(UInt64(delta.magnitude))
            return !overflow && successors == [destination] ? [] : nil
        }
        guard flow == .sequential, site <= UInt64.max - 4, successors == [site + 4] else { return nil }

        if dest != 31, word & 0x9f00_0000 == 0x9000_0000 {
            let imm = ((word >> 5) & 0x7ffff) << 2 | ((word >> 29) & 3)
            let displacement = signExtend(imm, bits: 21) * 4096
            let page = site & ~UInt64(4095)
            let (address, overflow) = displacement >= 0
                ? page.addingReportingOverflow(UInt64(displacement))
                : page.subtractingReportingOverflow(UInt64(displacement.magnitude))
            return overflow ? nil : [.immediate(address, result: dest)]
        }

        switch word & 0xffc0_0000 {
        case 0x9100_0000, 0xd100_0000:
            guard rn == 31 else { break }
            let delta = Int((word >> 10) & 0xfff)
            if dest == 31 {
                return [.adjustMachineStack(by: word & 0x4000_0000 == 0 ? delta : -delta)]
            }
            if dest == 29, word & 0x4000_0000 == 0 {
                return [.formMachineFrame(offset: delta)]
            }
        case 0xf940_0000, 0xf900_0000:
            guard rn == 31 || rn == 29, dest != 31 else { break }
            return [.machineStackWords(.init(base: rn, offset: Int((word >> 10) & 0xfff) * 8,
                registers: [dest], load: word & 0x0040_0000 != 0, update: .none))]
        default: break
        }

        // LDP/STP signed offset, pre-index and post-index, 64-bit GPRs.
        // Saving these registers is a write to the native frame; it is not an
        // async-context store. Bounds and alias facts are checked dynamically.
        let pair = word & 0xffc0_0000
        if [0xa9000000, 0xa9400000, 0xa9800000, 0xa9c00000, 0xa8800000, 0xa8c00000].contains(pair) {
            let second = Int((word >> 10) & 31)
            guard rn == 31 || rn == 29, dest != 31, second != 31, dest != second else { return nil }
            let mode = (word >> 23) & 3
            let update: AsyncClosedCallerSolver.MachineStackWords.Update =
                mode == 3 ? .preIndex : (mode == 1 ? .postIndex : .none)
            guard update == .none || rn == 31 else { return nil }
            let delta = signExtend((word >> 15) & 127, bits: 7) * 8
            return [.machineStackWords(.init(base: rn, offset: delta, registers: [dest, second],
                load: word & 0x0040_0000 != 0, update: update))]
        }

        // Unscaled/pre-index/post-index LDR/STR, no register indexing.
        let scalar = word & 0xffe0_0c00
        if [0xf8000000, 0xf8400000, 0xf8000400, 0xf8400400, 0xf8000c00, 0xf8400c00].contains(scalar) {
            guard (rn == 31 || rn == 29), dest != 31 else { return nil }
            let mode = (word >> 10) & 3
            let update: AsyncClosedCallerSolver.MachineStackWords.Update =
                mode == 3 ? .preIndex : (mode == 1 ? .postIndex : .none)
            guard update == .none || rn == 31 else { return nil }
            return [.machineStackWords(.init(base: rn, offset: signExtend((word >> 12) & 0x1ff, bits: 9),
                registers: [dest], load: word & 0x0040_0000 != 0, update: update))]
        }

        if word & 0xffe0_ffe0 == 0xaa00_03e0, dest != 31 {
            return rm == 31 ? [.immediate(0, result: dest)] : [.copy(from: rm, to: dest)]
        }
        if dest != 31, word & 0x1f80_0000 == 0x1280_0000 {
            let opcode = (word >> 29) & 3
            let wide = word & 0x8000_0000 != 0
            let shift = Int((word >> 21) & 3) * 16
            guard wide || shift < 32 else { return nil }
            let field = UInt64((word >> 5) & 0xffff) << shift
            let mask = wide ? UInt64.max : UInt64(UInt32.max)
            switch opcode {
            case 0: return [.immediate((~field) & mask, result: dest)]
            case 2: return [.immediate(field, result: dest)]
            case 3: return [.insertMachineImmediate(field: field, mask: 0xffff << shift,
                                                     widthMask: mask, register: dest)]
            default: return nil
            }
        }

        if word == 0xb244_03bd || word == 0x9243_fbbd {
            // Swift's frame-chain tag changes x29, not the stack pointer.
            // Drop x29 rather than treating an altered pointer as a coordinate.
            return [.forget(29)]
        }
        return nil
    }
}

/// A function body that does nothing of its own, read from its first words:
/// `ret`, or at most two constants or arguments moved into the result
/// registers and returned.
///
/// The linker folds identical bodies onto one address, and the less specific
/// a body is, the more functions share it. In a stripped image the evidence
/// goes with the symbols: a bare `ret` folded with 18 other functions keeps
/// one surviving name, and nothing says the others existed. These shapes are
/// where that happens, measured over every fixture, the swift-syntax dylibs
/// and a -O/-Osize/-Onone matrix against unstripped twins
/// (docs/PRODUCTION-READINESS.md has the numbers). Length alone costs far
/// more: a two-instruction body that computes something is usually unique.
enum TrivialBody {
    /// The most words `matches` looks at.
    static let wordCount = 3

    private static let ret: UInt32 = 0xD65F_03C0
    /// `x0`...`x7` and `v0`...`v7` carry results. `mov w8, #1; mov x0, x8; ret`
    /// goes through a scratch register, a shape only -Onone emits.
    private static let resultRegisters: ClosedRange<UInt32> = 0 ... 7

    /// Whether `words`, in order from the function's first instruction, are
    /// one of the shapes.
    static func matches(_ words: [UInt32]) -> Bool {
        for word in words.prefix(wordCount) {
            if word == ret { return true }
            guard movesIntoResultRegister(word) else { return false }
        }
        return false
    }

    private static func movesIntoResultRegister(_ word: UInt32) -> Bool {
        guard resultRegisters.contains(word & 31) else { return false }
        let source = (word >> 5) & 31
        let second = (word >> 16) & 31
        return word & 0x7F80_0000 == 0x5280_0000 // movz
            || word & 0x7F80_0000 == 0x1280_0000 // movn
            || word & 0x7FE0_FFE0 == 0x2A00_03E0 // mov Rd, Rm (orr with zr)
            || word & 0x7F80_03E0 == 0x3200_03E0 // mov Rd, #bitmask (orr with zr)
            || word & 0xFF20_1FE0 == 0x1E20_1000 // fmov Vd, #imm
            || word & 0xFF3F_FC00 == 0x1E20_4000 // fmov Vd, Vn
            || word & 0x9FF8_0C00 == 0x0F00_0400 // movi
            || (word & 0xBFE0_FC00 == 0x0EA0_1C00 && source == second) // mov.16b Vd, Vn
    }
}

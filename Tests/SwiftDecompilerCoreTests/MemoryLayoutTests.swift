import Testing
import Ccapstone
@testable import SwiftDecompilerCore

/// The per-instruction types are held once per decoded instruction (a
/// whole image is millions), so their size is a memory budget. Each bound
/// is the packed layout; a field that widens one breaks the budget here.
@Test func perInstructionTypesStayPacked() {
    // Two Ints stored a number under 1,000 and a width under 256: 24 bytes,
    // three times in a memory operand, and 96 an operand.
    #expect(MemoryLayout<PhysReg>.stride <= 6)
    #expect(MemoryLayout<StructuredOperandInfo>.stride <= 48)
    // `xrefs` holds one per call site of the whole image; an `Instruction`
    // per site was 176 bytes.
    #expect(MemoryLayout<GraphSite>.stride <= 40)
}

/// Packing keeps every value: a Capstone id past a bank (`.other`), the
/// widest vector, and a lane index read back as they were stored.
@Test func packedRegistersAndLanesRoundTrip() {
    let other = PhysReg(kind: .other, number: 900, widthBits: 0)
    #expect(other.number == 900 && other.key == "reg900")
    #expect(PhysReg(kind: .vector, number: 31, widthBits: 128).widthBits == 128)
    var info = StructuredOperandInfo(operand: .register(other), shift: (AARCH64_SFT_INVALID, 0),
                                     extender: AARCH64_EXT_INVALID, vectorIndex: 15)
    #expect(info.vectorIndex == 15)
    info.vectorIndex = nil
    #expect(info.vectorIndex == nil)
}

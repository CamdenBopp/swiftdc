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
    // And one of these per function: the whole function was 312 bytes.
    #expect(MemoryLayout<FunctionCallSites>.stride <= 48)
    // One per function for the whole run; field order padded it to 128.
    // The pure-alias input proof adds 16: the decoded entry and the
    // branch's 32-bit offset. Entry-register roles add 24: their pending
    // forwards (construction state, emptied by closeOverProvenEntryReads),
    // the 32-bit proven-read mask and a flag. The proven probed-allocation
    // sites add 8: one array, empty for every function without a probe.
    #expect(MemoryLayout<CalleeRegisterSummary>.stride <= 144)
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

/// A register set behaves as the `Set<Int>` it replaced, in one word, and
/// walks its members in ascending order.
@Test func aRegisterSetIsASetOfRegisterNumbers() {
    var set: RegisterSet = [7, 0, 3]
    #expect(Array(set) == [0, 3, 7])
    #expect(set.max() == 7 && set.contains(3) && !set.contains(4) && !set.contains(16) && !set.contains(-1))
    #expect(set.insert(3).inserted == false && set.insert(4).inserted == true)
    #expect(set.remove(0) == 0 && set.remove(0) == nil)
    #expect(set == [3, 4, 7])
    #expect(set.union([1]) == [1, 3, 4, 7] && set.intersection([4, 5]) == [4] && set.symmetricDifference([4, 5]) == [3, 5, 7])
    #expect(RegisterSet(0 ..< 8) == [0, 1, 2, 3, 4, 5, 6, 7] && RegisterSet().isEmpty)
    #expect(Set(RegisterSet([2, 15])) == Set([2, 15]))
    #expect(MemoryLayout<RegisterSet>.size == 2)
    // Every number in range, present and absent.
    let all = RegisterSet(0 ..< 16)
    #expect((0 ..< 16).allSatisfy { all.contains($0) && !RegisterSet().contains($0) })
    #expect((0 ..< 16).allSatisfy { RegisterSet([$0]).contains($0) && Array(RegisterSet([$0])) == [$0] })
    #expect(Array(all) == Array(0 ..< 16))
}

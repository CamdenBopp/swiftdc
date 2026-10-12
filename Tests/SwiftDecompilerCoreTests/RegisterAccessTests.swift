import Foundation
import Testing
@testable import SwiftDecompilerCore

/// Capstone's per-operand access flags, as `StructuredInsn` exposes them: the
/// registers an instruction reads and writes. Assembled with
/// `xcrun clang -arch arm64 -c` and read back with `llvm-objdump -d`.
@Test func operandAccessGivesExactReadAndWriteSets() throws {
    let words: [UInt32] = [
        0xf2e00031, // movk x17, #0x1, lsl #48
        0x91002020, // add x0, x1, #8
        0xf9000410, // str x16, [x0, #8]
        0xa8c17bfd, // ldp x29, x30, [sp], #16
        0xf100045f, // cmp x2, #1
        0x9a850083, // csel x3, x4, x5, eq
        0xa9004509, // stp x9, x17, [x8]
        0xaa0003f6, // mov x22, x0
        0xf86978e6, // ldr x6, [x7, x9, lsl #3]
        0xf81f0fea, // str x10, [sp, #-16]!
    ]
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    let sets = try decoded.map { insn -> (Set<String>, Set<String>) in
        let detail = try #require(insn.detail)
        return (detail.readRegisterKeys, detail.writtenRegisterKeys)
    }
    let expected: [(read: Set<String>, written: Set<String>)] = [
        (["x17"], ["x17"]),              // movk keeps the other bits
        (["x1"], ["x0"]),
        (["x16", "x0"], []),
        ([], ["x29", "x30", "sp"]),      // sp is no general register; writeback writes it
        (["x2"], []),
        (["x4", "x5"], ["x3"]),
        (["x9", "x17", "x8"], []),
        (["x0"], ["x22"]),
        (["x7", "x9"], ["x6"]),
        (["x10"], ["sp"]),
    ]
    for (index, (read, written)) in sets.enumerated() {
        #expect(read == expected[index].read, "\(decoded[index].text): read \(read)")
        #expect(written == expected[index].written, "\(decoded[index].text): written \(written)")
    }
}

import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `cs_disasm` stops at the FIRST byte sequence it cannot decode and reports how
/// many instructions it managed — it does not skip and continue. Treating that
/// first result as "the decode" silently truncates the whole-image path at the
/// first piece of inline data, padding, jump table, or unknown arm64e form in
/// `__text`.
///
/// That is not hypothetical: it capped `disasm --image SwiftUI` at 4,040
/// instructions — 285 of 105,647 functions (0.27%) — while the output looked
/// entirely normal. These tests pin the resynchronisation, since the failure
/// mode is invisible in any output you would think to read.
///
/// No binary needed: the defect and its fix live entirely in the decode loop.

/// ARM64 encodings used below. `udf` is deliberately absent — `0x00000000`
/// decodes as `udf #0`, so zero padding does NOT stall Capstone and would make
/// a test written around it vacuous. These two were confirmed undecodable by
/// probing the engine directly.
private let nop: UInt32 = 0xd503_201f
private let ret: UInt32 = 0xd65f_03c0
private let undecodable: [UInt32] = [0xffff_ffff, 0xdead_beef]

private func code(_ words: [UInt32]) -> Data {
    var data = Data()
    for word in words {
        var le = word.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
    return data
}

@Test func resumesDecodingPastUndecodableBytes() throws {
    let engine = try #require(CapstoneEngine())
    let base: UInt64 = 0x1000
    // nop ret | GARBAGE GARBAGE | nop ret
    let decoded = engine.disassemble(
        code([nop, ret, undecodable[0], undecodable[1], nop, ret]), address: base
    )

    // Without resynchronisation this stops after the first two.
    #expect(decoded.count == 4)
    // Addresses pin the STRIDE, not merely that decoding resumed: a resync that
    // skipped the wrong number of bytes would still yield 4 instructions here,
    // at the wrong addresses.
    #expect(decoded.map(\.address) == [base, base + 4, base + 16, base + 20])
    #expect(decoded.map(\.mnemonic) == ["nop", "ret", "nop", "ret"])
}

@Test func decodesInstructionsAfterLeadingGarbage() throws {
    let engine = try #require(CapstoneEngine())
    let base: UInt64 = 0x2000
    let decoded = engine.disassemble(code([undecodable[0], nop, ret]), address: base)

    // Garbage first: the old single-call form returned nothing at all here.
    #expect(decoded.count == 2)
    #expect(decoded.map(\.address) == [base + 4, base + 8])
}

@Test func toleratesTrailingGarbageWithoutLoopingForever() throws {
    let engine = try #require(CapstoneEngine())
    let base: UInt64 = 0x3000
    // A long undecodable tail: the resync loop must terminate, not spin.
    let decoded = engine.disassemble(
        code([nop, ret] + Array(repeating: undecodable[0], count: 64)), address: base
    )

    #expect(decoded.count == 2)
    #expect(decoded.map(\.address) == [base, base + 4])
}

@Test func decodesAnAllGarbageBufferAsEmpty() throws {
    let engine = try #require(CapstoneEngine())
    // Adversarial: nothing decodable at all must yield nothing — the resync must
    // not invent instructions to fill the gap it skipped over.
    let decoded = engine.disassemble(
        code(Array(repeating: undecodable[1], count: 32)), address: 0x4000
    )
    #expect(decoded.isEmpty)
}

@Test func preservesContiguousDecodeExactly() throws {
    let engine = try #require(CapstoneEngine())
    let base: UInt64 = 0x5000
    // Regression guard on the common path: a clean buffer must decode identically
    // to before, with no duplicated or dropped instructions from the new loop's
    // offset bookkeeping.
    let words = Array(repeating: [nop, nop, ret], count: 20).flatMap { $0 }
    let decoded = engine.disassemble(code(words), address: base)

    #expect(decoded.count == words.count)
    #expect(decoded.map(\.address) == (0..<words.count).map { base + UInt64($0 * 4) })
}

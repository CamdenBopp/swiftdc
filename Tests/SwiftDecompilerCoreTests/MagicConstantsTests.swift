import Testing
@testable import SwiftDecompilerCore

/// The constant generators are the trusted half of the magic-division proof,
/// so they are pinned to what `swiftc -O` (Swift 6.3, arm64) actually emitted:
/// the `mov`/`movk` immediates and shift amounts in libCodegen and its probes.
@Suite struct MagicConstantsTests {
    @Test func signedMatchesTheCompiler() {
        #expect(MagicConstants.signed(7) == .init(magic: 0x4924_9249_2492_4925, shift: 1))
        #expect(MagicConstants.signed(3) == .init(magic: 0x5555_5555_5555_5556, shift: 0))
        #expect(MagicConstants.signed(5) == .init(magic: 0x6666_6666_6666_6667, shift: 1))
        #expect(MagicConstants.signed(6) == .init(magic: 0x2AAA_AAAA_AAAA_AAAB, shift: 0))
        #expect(MagicConstants.signed(15) == .init(magic: 0x8888_8888_8888_8889, shift: 3))
        #expect(MagicConstants.signed(100) == .init(magic: 0xA3D7_0A3D_70A3_D70B, shift: 6))
        #expect(MagicConstants.signed(-7) == .init(magic: 0xB6DB_6DB6_DB6D_B6DB, shift: 1))
        #expect(MagicConstants.signed(1) == nil)
    }

    @Test func unsignedMatchesTheCompiler() {
        #expect(MagicConstants.unsigned(10) == .init(magic: 0xCCCC_CCCC_CCCC_CCCD, preShift: 0, postShift: 3, isAdd: false))
        #expect(MagicConstants.unsigned(3) == .init(magic: 0xAAAA_AAAA_AAAA_AAAB, preShift: 0, postShift: 1, isAdd: false))
        #expect(MagicConstants.unsigned(7) == .init(magic: 0x2492_4924_9249_2493, preShift: 0, postShift: 2, isAdd: true))
        #expect(MagicConstants.unsigned(1000) == .init(magic: 0x20C4_9BA5_E353_F7CF, preShift: 3, postShift: 4, isAdd: false))
        #expect(MagicConstants.unsigned(1) == nil)
    }
}

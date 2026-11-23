import Testing
@testable import SwiftDecompilerCore

private func descriptorBytes(displacement: Int32, size: UInt32) -> [UInt8] {
    [UInt32(bitPattern: displacement), size].flatMap { word in
        (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) }
    }
}

@Test func asyncDescriptorPairsSignedEntryWithRoleNeutralExtent() throws {
    for extent in [UInt32(0), 3, 17, .max] {
        let descriptor = try #require(AsyncFunctionDescriptor.decode(
            descriptorBytes(displacement: -0x400, size: extent), at: 0x4000,
            expectedEntry: 0x3c00
        ) { $0 == 0x3c00 })
        #expect(descriptor.address == 0x4000)
        #expect(descriptor.entry == 0x3c00)
        #expect(descriptor.requiredContextSize == extent)
    }
    let descriptor = AsyncFunctionDescriptor.decode(
        descriptorBytes(displacement: 0x480, size: 32), at: 0x4004
    ) { $0 == 0x4484 }
    #expect(descriptor?.entry == 0x4484)
}

@Test func asyncDescriptorRejectsTruncationMisalignmentWrapAndNoncode() {
    let good = descriptorBytes(displacement: -0x400, size: 32)
    #expect(AsyncFunctionDescriptor.decode(Array(good.dropLast()), at: 0x4000) { _ in true } == nil)
    #expect(AsyncFunctionDescriptor.decode(good + [0], at: 0x4000) { _ in true } == nil)
    #expect(AsyncFunctionDescriptor.decode(good, at: 0x4002) { _ in true } == nil)
    #expect(AsyncFunctionDescriptor.decode(good, at: 0x4000) { _ in false } == nil)
    #expect(AsyncFunctionDescriptor.decode(good, at: 0x4000, expectedEntry: 0x3bfc) { _ in true } == nil,
        "isolated declared expected entry")
    #expect(AsyncFunctionDescriptor.decode(good, at: 0x100) { _ in true } == nil)
    #expect(AsyncFunctionDescriptor.decode(good, at: UInt64.max - 3) { _ in true } == nil)
    #expect(AsyncFunctionDescriptor.decode(descriptorBytes(displacement: 16, size: 32),
                                           at: UInt64.max - 15) { _ in true } == nil)
    #expect(AsyncFunctionDescriptor.decode(descriptorBytes(displacement: 2, size: 32),
                                           at: 0x4000) { _ in true } == nil)
    #expect(AsyncFunctionDescriptor.decode(descriptorBytes(displacement: 4, size: 32),
                                           at: 0x4000) { _ in true } == nil)
}

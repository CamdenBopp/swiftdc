import Foundation
import Testing
@testable import SwiftDecompilerCore

private func bindBytes(_ suffix: [UInt8] = []) -> Data {
    // segment 2, offset 16; dylib 3; a pointer binding for _swift_retain.
    Data([0x72, 0x10, 0x13, 0x40] + Array("_swift_retain".utf8) + [0, 0x51, 0x90] + suffix)
}

@Test func legacyNormalDoneDoesNotCreateASecondBinding() throws {
    let first = bindBytes([0])
    let bytes = first + bindBytes([0])
    let bindings = try #require(LegacyImportBindings.decode(bytes, kind: .normal))
    #expect(bindings.count == 1)
    #expect(bindings.first?.libraryOrdinal == 3)
    #expect(bindings.first?.offset == 16)
    #expect(bindings.first?.isWeak == false)
}

@Test func legacyBindingBoundsAndMalformedOperandsDiscardEarlierClaims() {
    // A valid first binding must not survive a later unsupported operation,
    // missing operand, unterminated name, overflowing ULEB, or record bound.
    let malformed: [[UInt8]] = [
        [0xd0], [0x20], [0x40, 0x5f],
        [0x20] + Array(repeating: 0xff, count: 10),
        [0xc0, 0xc1, 0x84, 0x3d, 0], // 1,000,001 bindings
    ]
    for suffix in malformed {
        #expect(LegacyImportBindings.decode(bindBytes(suffix), kind: .normal) == nil)
    }
}

@Test func legacyLazyBindingsKeepIndependentEntryOffsetsAndWeakFlags() throws {
    let prefix = [UInt8(0x72), 0x10, 0x13, 0x40]
    let name = Array("_swift_retain".utf8) + [UInt8(0)]
    let first = prefix + name + [0x90, 0]
    let second = [UInt8(0x72), 0x18, 0x13, 0x41] + name + [0x60, 0x7c, 0x90, 0]
    let bindings = try #require(LegacyImportBindings.decode(Data(first + second), kind: .lazy))
    #expect(bindings.count == 2)
    #expect(bindings.first?.lazyEntry == 0)
    #expect(bindings.last?.lazyEntry == first.count)
    #expect(bindings.first?.isWeak == false)
    #expect(bindings.last?.isWeak == true)
    #expect(bindings.last?.addend == -4)
    #expect(bindings.last?.offset == 24)
}

import Testing
import Foundation
import MachOKit
@testable import SwiftDecompilerCore

private func fixture() -> MachOFile? {
    let path = "Fixtures/Sample/libRuntimeIvars.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    return try? BinaryLoader.load(path: path)
}

private func section(_ name: String, in machO: MachOFile) -> Range<UInt64>? {
    machO.sections64.first { $0.sectionName == name }.map {
        UInt64($0.address) ..< UInt64($0.address + $0.size)
    }
}

/// MachOKit maps a zero-fill address to a file offset as if the segment were
/// file-backed. Read through `readString(offset:)` that is a `strlen` on bytes
/// the address does not own: on Prime Video, past the end of the file, it
/// faulted (SIGSEGV) in some runs and not others. A string is read only from
/// bytes the file holds.
@Test func readsNoStringFromAZeroFillAddressIfPresent() throws {
    guard let machO = fixture() else { return }
    let ranges = try #require(FileBackedRanges(standalone: machO))
    let common = try #require(section("__common", in: machO), "the fixture's field offsets are zero-fill")

    // The hazard: MachOKit hands back an offset for it.
    #expect(machO.fileOffset(of: common.lowerBound) != nil)
    #expect(ranges.fileBytes(at: common.lowerBound) == nil)
    #expect(Disassembler.ReferenceResolver.rawCString(
        at: common.lowerBound, in: machO, ranges: ranges) == nil)
}

/// The bounded read changes nothing where the file has the string.
@Test func readsAFileBackedStringAsBeforeIfPresent() throws {
    guard let machO = fixture() else { return }
    let ranges = try #require(FileBackedRanges(standalone: machO))
    let cstrings = try #require(section("__objc_methname", in: machO))
    var address = cstrings.lowerBound
    var compared = 0
    while address < cstrings.upperBound {
        let offset = try #require(machO.fileOffset(of: address))
        let expected = try machO.readString(offset: Int(offset))
        let actual = Disassembler.ReferenceResolver.rawCString(at: address, in: machO, ranges: ranges)
        #expect(actual == expected, "at 0x\(String(address, radix: 16))")
        address += UInt64(expected.utf8.count + 1)
        compared += 1
    }
    #expect(compared > 3)
}

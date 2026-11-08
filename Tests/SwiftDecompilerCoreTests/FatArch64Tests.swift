import Testing
import Foundation
import MachOKit
@testable import SwiftDecompilerCore

/// A universal binary whose slice starts at or past 4 GiB needs the 64-bit fat
/// header (`FAT_MAGIC_64`, 32-byte `fat_arch_64` entries with a 64-bit
/// offset). MachOKit read those entries with the 20-byte 32-bit layout, so the
/// offset lost its high half and every later entry was read out of step: on a
/// real two-slice file `--arch arm64` failed with "Available: x86_64, x86_64"
/// while `lipo` placed arm64 at 4,294,983,680. Fixed upstream by p-x9 (#340),
/// carried on the fork swiftdc pins.
///
/// The file is built here, sparse: two copies of libSample, one low and one
/// past 4 GiB, so the test writes about 100 KB, not 4 GB.
@Test func readsASliceBeyondFourGiBIfPresent() throws {
    let thinPath = "Fixtures/Sample/libSample.dylib"
    guard FileManager.default.fileExists(atPath: thinPath) else { return }
    let thin = try Data(contentsOf: URL(fileURLWithPath: thinPath))

    let low: UInt64 = 0x4000
    let high: UInt64 = (1 << 32) + 0x4000
    // The slice is named from its own Mach-O header, so the low copy is
    // relabelled arm64e (cpusubtype at +8): `--arch arm64` can then only mean
    // the copy past 4 GiB.
    var relabelled = thin
    relabelled.replaceSubrange(8 ..< 12, with: [2, 0, 0, 0])
    let entries: [(cpuType: UInt32, subtype: UInt32, offset: UInt64, bytes: Data)] = [
        (0x0100_000c, 2, low, relabelled),
        (0x0100_000c, 0, high, thin),
    ]
    var header = Data()
    func append32(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { header.append(contentsOf: $0) } }
    func append64(_ value: UInt64) { withUnsafeBytes(of: value.bigEndian) { header.append(contentsOf: $0) } }
    append32(0xcafe_babf)
    append32(UInt32(entries.count))
    for entry in entries {
        append32(entry.cpuType)
        append32(entry.subtype)
        append64(entry.offset)
        append64(UInt64(thin.count))
        append32(14)
        append32(0)
    }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-fat64-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fatURL = directory.appendingPathComponent("fat64.dylib")
    FileManager.default.createFile(atPath: fatURL.path, contents: header)
    let handle = try FileHandle(forWritingTo: fatURL)
    for entry in entries {
        try handle.seek(toOffset: entry.offset)
        try handle.write(contentsOf: entry.bytes)
    }
    try handle.close()

    let expected = try BinaryLoader.load(path: thinPath)
    let slice = try BinaryLoader.load(path: fatURL.path, architecture: "arm64")
    #expect(slice.headerStartOffset == Int(high))
    #expect(slice.header.ncmds == expected.header.ncmds)
    #expect(slice.functionStarts.map { Array($0).count } == expected.functionStarts.map { Array($0).count })
    #expect(Array(slice.symbols).count == Array(expected.symbols).count)
}

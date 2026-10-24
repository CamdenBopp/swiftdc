import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A copy of a thin Mach-O with its header's CPU subtype set to `subtype`.
private func withSubtype(_ source: String, _ subtype: UInt32) throws -> URL {
    var data = try Data(contentsOf: URL(fileURLWithPath: source))
    var little = subtype.littleEndian
    withUnsafeBytes(of: &little) { data.replaceSubrange(8 ..< 12, with: $0) }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("subtype-\(subtype)-\(UUID()).dylib")
    try data.write(to: url)
    return url
}

/// An ARM64 slice is named by its raw subtype, capability bits masked, the
/// way lipo and llvm-objdump name it. MachOKit does not know ARM64E_X1 (12,
/// mach/machine.h), which read as "arm64": `--arch arm64` then chose
/// Terminal's arm64e.x1 slice, and the unfiltered listing, which asks
/// llvm-objdump for an arm64 slice the file does not have, failed with
/// "llvm-objdump produced 0 lines … This is a parser defect".
@Test(arguments: [(UInt32(0x8000_0002), "arm64e"), (UInt32(0x8000_000c), "arm64e.x1"), (UInt32(0), "arm64"),
                  (UInt32(1), "arm64v8"), (UInt32(7), "arm64 (subtype 7)")])
func anARM64SliceIsNamedByItsSubtypeIfPresent(subtype: UInt32, name: String) throws {
    let source = "Fixtures/Sample/libSwitches.arm64e.dylib"
    guard FileManager.default.fileExists(atPath: source) else { return }
    let url = try withSubtype(source, subtype)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(BinaryLoader.archName(try BinaryLoader.load(path: url.path)) == name)
}

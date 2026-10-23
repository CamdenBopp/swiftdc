import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A copy of `source` with one 64-bit field of the named segment command
/// (`vmaddr` or `vmsize`) set to `value`.
private func corrupted(_ source: String, segment: String, field: String, value: UInt64) throws -> URL {
    var data = try Data(contentsOf: URL(fileURLWithPath: source))
    let commands = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt32.self) }
    var offset = 32
    for _ in 0..<commands {
        let (command, size) = data.withUnsafeBytes {
            ($0.loadUnaligned(fromByteOffset: offset, as: UInt32.self),
             $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
        }
        // LC_SEGMENT_64: segname at +8, vmaddr at +24, vmsize at +32.
        if command == 0x19 {
            let name = String(decoding: data[offset + 8 ..< offset + 24].prefix { $0 != 0 }, as: UTF8.self)
            if name == segment {
                var little = value.littleEndian
                let at = offset + (field == "vmaddr" ? 24 : 32)
                withUnsafeBytes(of: &little) { data.replaceSubrange(at ..< at + 8, with: $0) }
            }
        }
        offset += Int(size)
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wide-\(segment)-\(field)-\(UUID().uuidString).dylib")
    try data.write(to: url)
    return url
}

/// MachOKit converts a segment's address and size to `Int` with a trapping
/// `numericCast` wherever it computes a file offset or a section range, so a
/// segment field at or above 2^63 (a real arm64e kernel's `__TEXT` is at
/// 0xfffffe0007004000) killed `disasm`, `objc`, `layout`, `interface`,
/// `xrefs` and `analyze` with SIGTRAP: an uncatchable trap, past the
/// preflight. Loading now fails with an error naming the segment, unless the
/// reader opts out because it does no address arithmetic (`dump`,
/// `swift-version`).
@Test(arguments: [("__TEXT", "vmsize", UInt64(1) << 63), ("__LINKEDIT", "vmaddr", UInt64.max),
                  ("__DATA_CONST", "vmsize", UInt64(1) << 63)])
func aSegmentFieldPastInt64FailsToLoadIfPresent(segment: String, field: String, value: UInt64) async throws {
    let source = "Fixtures/Sample/libObjCNonselfOutgoing.dylib"
    guard FileManager.default.fileExists(atPath: source) else { return }
    let url = try corrupted(source, segment: segment, field: field, value: value)
    defer { try? FileManager.default.removeItem(at: url) }
    // Stop at a load that succeeds: analysing the image would trap the test
    // process itself.
    do {
        _ = try BinaryLoader.load(path: url.path)
        Issue.record("\(segment).\(field) = 0x\(String(value, radix: 16)) loaded")
        return
    } catch {
        #expect("\(error)".contains("Segment \(segment) has a virtual") && "\(error)".contains("at or above 2^63"),
                "\(error)")
    }
    await #expect(throws: BinaryLoadError.self) {
        _ = try await Disassembler().disassemble(path: url.path)
    }
    #expect(throws: Never.self) { _ = try BinaryLoader.load(path: url.path, allowingWideAddresses: true) }
    // The untouched fixture still loads.
    #expect(throws: Never.self) { _ = try BinaryLoader.load(path: source) }
}

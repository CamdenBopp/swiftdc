import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

/// A damaged LC_FUNCTION_STARTS whose one entry lies far outside the image
/// marks no function, yet the boundary warning fired only when the table was
/// empty: a stripped executable decoded as one function with nothing said.
/// A table with no address inside the code now warns, in its own words; the
/// intact image does not.
@Test func aFunctionStartsTableOutsideTheCodeWarnsIfPresent() async throws {
    let path = "Fixtures/Sample/sample.stripped"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let intact = try BinaryLoader.load(path: path)
    var dataOffset = 0, dataSize = 0
    for command in intact.loadCommands {
        if case .functionStarts(let starts) = command {
            dataOffset = Int(starts.layout.dataoff)
            dataSize = Int(starts.layout.datasize)
        }
    }
    try #require(dataSize >= 6, "no LC_FUNCTION_STARTS to damage")
    var bytes = try Data(contentsOf: URL(fileURLWithPath: path))
    // One ULEB128 delta of 2^34, far past the image, then the terminator.
    let damaged: [UInt8] = [0x80, 0x80, 0x80, 0x80, 0x40] + Array(repeating: 0, count: dataSize - 5)
    bytes.replaceSubrange(dataOffset ..< dataOffset + dataSize, with: damaged)
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent("boundary-\(UUID().uuidString)")
    try bytes.write(to: copy)
    defer { try? FileManager.default.removeItem(at: copy) }
    let image = try BinaryLoader.load(path: copy.path)
    await withStableDependencies {
        let warning = Disassembler().boundaryWarning(in: image)
        #expect(warning?.contains("LC_FUNCTION_STARTS lists no address inside the code") == true,
                Comment(rawValue: warning ?? "no warning"))
        #expect(Disassembler().boundaryWarning(in: intact) == nil)
    }
}

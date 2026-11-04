import Testing
import Foundation

/// Bitfields in one byte report the same ivar offset, so a field map kept the
/// last of them: `-[BitFlags middle]` reads `_b` and rendered `self->_c`, and
/// AppKit's `alignmentSatisfied` rendered `self->_isCatalyst`.
private func structured(_ function: String) throws -> String? {
    let fixture = "Fixtures/Sample/libObjCBitfields.dylib"
    let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
    guard FileManager.default.fileExists(atPath: fixture),
          FileManager.default.fileExists(atPath: binary.path) else { return nil }
    let process = Process()
    let pipe = Pipe()
    process.executableURL = binary
    process.arguments = ["disasm", fixture, "-f", function, "--structured"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: output, as: UTF8.self)
}

@Test func bitfieldsSharingAnOffsetNameNoneOfThemIfPresent() throws {
    guard let text = try structured("BitFlags middle") else { return }
    #expect(text.contains("return"))
    for name in ["_a", "_b", "_c"] { #expect(!text.contains("self->\(name)"), "\(text)") }
}

@Test func anIvarWithItsOwnOffsetKeepsItsNameIfPresent() throws {
    guard let text = try structured("BitFlags after") else { return }
    #expect(text.contains("self->_after"), "\(text)")
}

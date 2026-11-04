import Testing
import Foundation
@testable import SwiftDecompilerCore

// Segments that lie at a different offset in memory than in the file
// (`Fixtures/Sample/slidsegments.swift`, `slidsegments_c.c`). Zero fill at
// the end of __DATA moves every later segment's addresses 0x870000 past its
// file bytes. The Mach-O readers underneath resolve fixup chains and
// relative pointers by file offset, so on such a segment they trap or read
// unrelated bytes: the image is declined, by that cause.

private let executable = "Fixtures/Sample/slidsegments"
// No .dylib suffix: the tests that walk every fixture dylib load images
// the preflight declines, and MachOKit traps on this one.
private let cLibrary = "Fixtures/Sample/slidsegments_c"

private func misread(_ path: String) throws -> [String]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let handle = try #require(FileHandle(forReadingAtPath: path))
    defer { try? handle.close() }
    let image = MachOPreflight.ImageReader(handle: handle, base: 0, size: data.count)
    return MachOPreflight.misreadSegments(prefix: data, image: image).map(\.name)
}

/// Every entry point declines the executable with the layout as its cause,
/// as an error exit. Before, every one exited 1 calling it malformed
/// (preflight read `__swift5_fieldmd`'s VM displacements as file
/// displacements), and with that check fixed every one trapped in MachOKit's
/// chained-fixup reader (`try!` past the end of the file).
@Test func everyEntryPointDeclinesSlidSegmentsIfPresent() throws {
    let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
    guard FileManager.default.fileExists(atPath: binary.path),
          FileManager.default.fileExists(atPath: executable) else { return }
    let commands: [[String]] = [
        ["disasm", "--structured"], ["dump"], ["layout"], ["interface"], ["objc"],
        ["xrefs", "--unreferenced"], ["analyze"],
    ]
    for command in commands {
        let out = Pipe(), err = Pipe()
        let process = Process()
        process.executableURL = binary
        process.arguments = command + [executable]
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationReason == .exit, "\(command): killed by signal \(process.terminationStatus)\n\(stderr)")
        #expect(process.terminationStatus == 1, "\(command): exit \(process.terminationStatus)\n\(stderr)")
        #expect(stderr.contains("Unsupported Mach-O layout"), "\(command): \(stderr)")
        #expect(stderr.contains("__DATA_DIRTY (VM offset 0x87c000, file offset 0xc000)"), "\(command): \(stderr)")
        #expect(!stderr.contains("Malformed"), "\(command): \(stderr)")
        #expect(stdout.isEmpty, "\(command): \(stdout)")
    }
}

/// A slid segment counts by either cause: fixup chains (__DATA_DIRTY) or a
/// metadata section with only relative pointers in it (__SWIFT_FIELDS).
@Test func slidSegmentsCountByChainsOrMetadataIfPresent() throws {
    guard let names = try misread(executable) else { return }
    #expect(names == ["__DATA_DIRTY", "__SWIFT_FIELDS"])
}

/// In a C library, a slid segment with fixup chains counts, though it holds
/// no metadata; a slid segment of raw bytes that nothing fixes up or reaches
/// by relative pointer (`__FONT_DATA`, as NanoTimeKit has) does not.
@Test func slidSegmentCountsOnlyWithChainsOrMetadataIfPresent() throws {
    guard let names = try misread(cLibrary) else { return }
    #expect(names == ["__DATA_DIRTY"])
}

/// The usual layout keeps one slide, zero fill at the end of __DATA
/// included (`__bss` and `__common` in sample.release): only __LINKEDIT
/// moves, and nothing counts.
@Test func ordinaryLayoutsHaveNoMisreadSegmentsIfPresent() throws {
    for path in [
        "Fixtures/Sample/sample.release", "Fixtures/Sample/libSample.dylib",
        "Fixtures/Sample/libRuntimeIvars.dylib", "Fixtures/Sample/libReconstruction.opt.dylib",
    ] {
        guard let names = try misread(path) else { continue }
        #expect(names.isEmpty, "\(path): \(names)")
    }
}

import Testing
import Foundation
import MachOKit
@testable import SwiftDecompilerCore

/// The `--cache` entry point had the same uncatchable-trap shape as the Mach-O
/// path, and for the same reason: `FullDyldCache(url:)` reads a whole
/// `dyld_cache_header` at offset 0 *before* checking the magic, through a `try!`.
/// A file shorter than that struct trips MachOKit's
/// `precondition(data.count >= layoutSize)` and aborts the process — empty
/// stderr, exit 133.
///
/// Probed: 5 of 7 malformed caches crashed, every one shorter than the header;
/// every file at least header-length instead declined cleanly through MachOKit's
/// own magic and cpu-type checks. So the whole class closes with one size guard.
///
/// The crash is unobservable in-process — a trap kills the test runner too — so
/// the end-to-end guard drives the CLI as a subprocess.

private let binary = URL(fileURLWithPath: ".build/debug/swiftdc")

private func makeCaches(in directory: URL) throws -> [(name: String, size: Int)] {
    let magic = Data("dyld_v1   arm64e".utf8).prefix(16)
    func padded(_ prefix: Data, to length: Int) -> Data {
        var data = prefix
        if data.count < length { data.append(Data(repeating: 0, count: length - data.count)) }
        return data
    }

    // Each of these crashed the CLI before the guard (except the two noted).
    let headerSize = DyldCacheHeader.layoutSize
    let cases: [(String, Data)] = [
        ("empty", Data()),
        ("magic_only", Data(magic)),
        ("truncated_header", padded(Data(magic), to: 24)),
        ("just_under_header", padded(Data(magic), to: headerSize - 1)),
        // The boundary: exactly header-length is long enough NOT to trap, and
        // then declines on content. It must be accepted by the size guard.
        ("exactly_header", padded(Data(magic), to: headerSize)),
    ]
    var written: [(name: String, size: Int)] = []
    for (name, bytes) in cases {
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url)
        written.append((name, bytes.count))
    }
    return written
}

@Test func theCLISurvivesAMalformedDyldCacheIfPresent() throws {
    guard FileManager.default.fileExists(atPath: binary.path) else { return }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-cache-\(ProcessInfo.processInfo.processIdentifier)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let caches = try makeCaches(in: directory)

    for (name, _) in caches {
        let url = directory.appendingPathComponent(name)
        let output = Pipe()
        let process = Process()
        process.executableURL = binary
        // --image forces the guarded cachePath branch of loadMachO.
        process.arguments = ["dump", "--image", "Foundation", "--cache", url.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(
            process.terminationReason == .exit,
            "\(name): killed by signal \(process.terminationStatus), not a clean exit"
        )
        #expect(
            process.terminationStatus == 1,
            "\(name): exit \(process.terminationStatus), expected 1 (declined)"
        )
        #expect(stdout.isEmpty, "\(name): produced \(stdout.count) bytes of stdout despite failing")
    }
}

/// The over-rejection guard: the size check must reject ONLY files that are
/// genuinely too short. A real cache is far larger than the header, so the
/// boundary — a file of exactly header length — must pass the size check and
/// reach MachOKit (which then declines it on content, cleanly).
@Test func theSizeGuardRejectsOnlyShortFilesIfPresent() throws {
    guard FileManager.default.fileExists(atPath: binary.path) else { return }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-cache-boundary-\(ProcessInfo.processInfo.processIdentifier)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let headerSize = DyldCacheHeader.layoutSize
    func run(bytes: Int) throws -> String {
        let url = directory.appendingPathComponent("cache_\(bytes)")
        var data = Data("dyld_v1   arm64e".utf8).prefix(16)
        if data.count < bytes { data.append(Data(repeating: 0, count: bytes - data.count)) }
        try data.write(to: url)
        let error = Pipe()
        let process = Process()
        process.executableURL = binary
        process.arguments = ["dump", "--image", "Foundation", "--cache", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = error
        try process.run()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: stderr, as: UTF8.self)
    }

    // Just under the header → rejected BY THE SIZE GUARD, which names the size.
    let short = try run(bytes: headerSize - 1)
    #expect(
        short.contains("shorter than a \(headerSize)-byte cache header"),
        "a too-short file should be rejected by the size guard, got: \(short)"
    )
    // Exactly the header length → past the size guard, declined by MachOKit on
    // content. The distinction proves the guard is not simply rejecting
    // everything: the two files differ by one byte and take different paths.
    let boundary = try run(bytes: headerSize)
    #expect(
        !boundary.contains("shorter than a"),
        "a header-length file must pass the size guard, got: \(boundary)"
    )
    #expect(
        boundary.contains("Not a dyld shared cache"),
        "a header-length non-cache should be declined by MachOKit, got: \(boundary)"
    )
}

import Testing
import Foundation
@testable import SwiftDecompilerCore

/// MachOKit and its `FileIOBinary` dependency use `try!` and `precondition` on
/// malformed input: a bad file does not throw, it **aborts the process**. Those
/// traps live in a dependency and cannot be caught, so the only mitigation is
/// to reject structurally impossible files before handing them over.
///
/// A survey of nine hand-written malformed inputs crashed seven, including an
/// empty file and one SIGSEGV. These tests pin both directions of the fix: that
/// impossible files are rejected, and — just as important — that valid ones are
/// still accepted. An over-eager validator that refuses real binaries would be a
/// worse regression than the crash it prevents.

// MARK: - Header construction

private func machHeader64(
    ncmds: UInt32, sizeofcmds: UInt32, magic: UInt32 = 0xfeed_facf
) -> Data {
    var data = Data()
    for word: UInt32 in [magic, 0x0100_000c, 0, 2, ncmds, sizeofcmds, 0, 0] {
        withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
    }
    return data
}

private func loadCommand(cmd: UInt32, size: UInt32) -> Data {
    var data = Data()
    withUnsafeBytes(of: cmd.littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: size.littleEndian) { data.append(contentsOf: $0) }
    data.append(Data(repeating: 0, count: max(0, Int(size) - 8)))
    return data
}

/// Big-endian fat header, the on-disk convention.
private func fatHeader(nfat: UInt32) -> Data {
    var data = Data()
    for word: UInt32 in [0xcafe_babe, nfat] {
        withUnsafeBytes(of: word.bigEndian) { data.append(contentsOf: $0) }
    }
    return data
}

private func rejects(_ prefix: Data, fileSize: Int? = nil) -> Bool {
    do {
        try MachOPreflight.validate(prefix: prefix, fileSize: fileSize ?? prefix.count)
        return false
    } catch {
        return true
    }
}

// MARK: - Must reject (each of these crashed the process before)

@Test func rejectsAnEmptyFile() {
    // Crashed with `Precondition failed: Invalid Data Size`.
    #expect(rejects(Data(), fileSize: 0))
}

@Test func rejectsAMagicNumberWithNoHeader() {
    // Four valid bytes and nothing else. Crashed inside FileIOBinary.
    var data = Data()
    withUnsafeBytes(of: UInt32(0xfeed_facf).littleEndian) { data.append(contentsOf: $0) }
    #expect(rejects(data))
}

@Test func rejectsAHeaderTruncatedMidway() {
    #expect(rejects(machHeader64(ncmds: 5, sizeofcmds: 500).prefix(20), fileSize: 20))
}

@Test func rejectsLoadCommandsThatCannotFitInTheFile() {
    // Declares 500 bytes of load commands in a 32-byte file.
    #expect(rejects(machHeader64(ncmds: 5, sizeofcmds: 500)))
}

@Test func rejectsMoreLoadCommandsThanTheirRegionCanHold() {
    // 100 commands cannot fit in 64 bytes: the smallest possible command is 8.
    let header = machHeader64(ncmds: 100, sizeofcmds: 64)
    #expect(rejects(header + Data(repeating: 0, count: 64)))
}

@Test func rejectsAbsurdLoadCommandCounts() {
    #expect(rejects(machHeader64(ncmds: 0xffffff, sizeofcmds: 0xffffff)))
}

@Test func rejectsALoadCommandDeclaringAnImpossibleSize() {
    // cmdsize below the 8-byte minimum would make the walk loop forever.
    let body = loadCommand(cmd: 0x19, size: 8).prefix(4) + Data([4, 0, 0, 0])
    let header = machHeader64(ncmds: 1, sizeofcmds: 8)
    #expect(rejects(header + body))
}

@Test func rejectsLoadCommandsThatOverrunTheirRegion() {
    // Two commands of 16 bytes each declared inside a 16-byte region.
    let header = machHeader64(ncmds: 2, sizeofcmds: 16)
    let body = loadCommand(cmd: 0x19, size: 16) + loadCommand(cmd: 0x19, size: 16)
    #expect(rejects(header + body))
}

@Test func rejectsAFatHeaderClaimingSlicesThatArentThere() {
    // 99 architectures in an 8-byte file. This one was a SIGSEGV, not a trap.
    #expect(rejects(fatHeader(nfat: 99)))
}

@Test func rejectsAFatSlicePointingOutsideTheFile() {
    var data = fatHeader(nfat: 1)
    // cputype, cpusubtype, offset, size, align — offset well past the end.
    for word: UInt32 in [0x0100_000c, 0, 0xffff_0000, 4096, 14] {
        withUnsafeBytes(of: word.bigEndian) { data.append(contentsOf: $0) }
    }
    #expect(rejects(data))
}

// MARK: - Must accept (the over-rejection guard)

@Test func acceptsAWellFormedHeaderWithNoLoadCommands() {
    #expect(!rejects(machHeader64(ncmds: 0, sizeofcmds: 0)))
}

@Test func acceptsAWellFormedHeaderWithLoadCommands() {
    let body = loadCommand(cmd: 0x19, size: 72) + loadCommand(cmd: 0x2, size: 24)
    let header = machHeader64(ncmds: 2, sizeofcmds: 96)
    #expect(!rejects(header + body))
}

@Test func acceptsAHeaderWhoseLoadCommandsExtendBeyondTheReadPrefix() {
    // The validator reads a bounded prefix. Running out of prefix is OUR limit,
    // not evidence of a bad file, so the walk must stop quietly rather than
    // report an overrun — otherwise every large binary would be rejected.
    let header = machHeader64(ncmds: 200, sizeofcmds: 8000)
    let partial = header + loadCommand(cmd: 0x19, size: 72)
    #expect(!rejects(partial, fileSize: 100_000))
}

@Test func ignoresFilesThatArentMachOAtAll() {
    // A PNG is not a corrupt Mach-O. It must fall through to the caller's
    // existing "Not a Mach-O file" path, not be reported as malformed.
    let png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    #expect(!rejects(png))
}

@Test func acceptsEveryBuiltFixtureBinary() throws {
    // The strongest over-rejection guard available without shipping binaries:
    // real linker output, in several shapes (debug, release, stripped, dylib).
    let fixtures = [
        "Fixtures/Sample/sample.debug", "Fixtures/Sample/sample.release",
        "Fixtures/Sample/sample.stripped", "Fixtures/Sample/libSample.dylib",
        "Fixtures/Sample/libReconstruction.dylib",
    ]
    for path in fixtures where FileManager.default.fileExists(atPath: path) {
        #expect(throws: Never.self) {
            try MachOPreflight.validate(url: URL(fileURLWithPath: path))
        }
    }
}

@Test func acceptsRealSystemBinariesIncludingFat() throws {
    // /bin/ls and /usr/lib/dyld are fat on macOS — the fat path needs a real
    // multi-slice file, which no hand-built header exercises faithfully.
    for path in ["/bin/ls", "/usr/lib/dyld"] where FileManager.default.fileExists(atPath: path) {
        #expect(throws: Never.self) {
            try MachOPreflight.validate(url: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - End-to-end: the process must not die

/// The crash cannot be observed in-process — a trap would take the test runner
/// down with it — so this drives the built CLI as a subprocess and inspects how
/// it terminated. Before the preflight, seven of these nine inputs killed it
/// (six SIGTRAP, one SIGSEGV).
///
/// Skips when the debug binary hasn't been built, matching the fixture-based
/// convention elsewhere in the suite.
@Test func theCLISurvivesEveryMalformedInput() throws {
    let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
    guard FileManager.default.fileExists(atPath: binary.path) else { return }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-preflight-\(ProcessInfo.processInfo.processIdentifier)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    var cases: [String: Data] = [
        "empty": Data(),
        "magic_only": machHeader64(ncmds: 0, sizeofcmds: 0).prefix(4),
        "magic_short": machHeader64(ncmds: 0, sizeofcmds: 0).prefix(4)
            + Data(repeating: 0xab, count: 200),
        "lying_ncmds": machHeader64(ncmds: 5, sizeofcmds: 500),
        "absurd_ncmds": machHeader64(ncmds: 0xffffff, sizeofcmds: 0xffffff),
        "truncated_lc": machHeader64(ncmds: 5, sizeofcmds: 500) + Data([0x19, 0, 0, 0]),
        "fat_lying": fatHeader(nfat: 99),
        "fat_empty": fatHeader(nfat: 0),
        "header_only": machHeader64(ncmds: 0, sizeofcmds: 0),
    ]
    cases["all_zero"] = Data(repeating: 0, count: 512)

    for (name, bytes) in cases {
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url)

        let process = Process()
        process.executableURL = binary
        process.arguments = ["disasm", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        // A signal means the process was killed, not that it declined the file.
        #expect(
            process.terminationReason == .exit,
            "\(name): terminated by signal \(process.terminationStatus), not a clean exit"
        )
        #expect(
            process.terminationStatus <= 1,
            "\(name): exit status \(process.terminationStatus) — expected 0 (handled) or 1 (error)"
        )
    }
}

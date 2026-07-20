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

// MARK: - Load-command payloads
//
// The header checks above prove the command TABLE is coherent; these prove the
// commands do not POINT outside the file. That distinction is not academic:
// mutating a real fixture's segment and symbol-table fields crashed the CLI 12
// times across `dump`, `layout`, `interface` and `objc` — silently, with empty
// stderr. `disasm` survived only because llvm-objdump rejects the file first,
// which is why the original header-shaped survey never found this class.

/// `segment_command_64` (72 bytes) followed by `nsects` × `section_64` (80).
private func segment64(
    name: String = "__TEXT", fileoff: UInt64, filesize: UInt64, sections: [Data] = []
) -> Data {
    var data = Data()
    withUnsafeBytes(of: UInt32(0x19).littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: UInt32(72 + 80 * sections.count).littleEndian) { data.append(contentsOf: $0) }
    var segname = Data(name.utf8); segname.append(Data(repeating: 0, count: 16 - segname.count))
    data.append(segname)
    withUnsafeBytes(of: UInt64(0).littleEndian) { data.append(contentsOf: $0) }   // vmaddr
    withUnsafeBytes(of: UInt64(0).littleEndian) { data.append(contentsOf: $0) }   // vmsize
    withUnsafeBytes(of: fileoff.littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: filesize.littleEndian) { data.append(contentsOf: $0) }
    for word: UInt32 in [7, 5, UInt32(sections.count), 0] {                       // prot, nsects, flags
        withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
    }
    for section in sections { data.append(section) }
    return data
}

private func section64(size: UInt64, offset: UInt32, flags: UInt32 = 0) -> Data {
    var data = Data(repeating: 0, count: 32)                                       // sectname + segname
    withUnsafeBytes(of: UInt64(0).littleEndian) { data.append(contentsOf: $0) }     // addr
    withUnsafeBytes(of: size.littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: offset.littleEndian) { data.append(contentsOf: $0) }
    for word: UInt32 in [0, 0, 0] { withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) } }
    withUnsafeBytes(of: flags.littleEndian) { data.append(contentsOf: $0) }
    data.append(Data(repeating: 0, count: 12))                                     // reserved1…3
    return data
}

private func symtab(symoff: UInt32, nsyms: UInt32, stroff: UInt32, strsize: UInt32) -> Data {
    var data = Data()
    for word: UInt32 in [0x2, 24, symoff, nsyms, stroff, strsize] {
        withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
    }
    return data
}

/// Wrap one load command in a header that declares exactly it.
private func imageWith(_ command: Data, fileSize: Int) -> (Data, Int) {
    let header = machHeader64(ncmds: 1, sizeofcmds: UInt32(command.count))
    return (header + command, fileSize)
}

@Test func rejectsASegmentStartingBeyondTheFile() {
    let (data, size) = imageWith(segment64(fileoff: 0xffff_0000, filesize: 16), fileSize: 4096)
    #expect(rejects(data, fileSize: size))
}

@Test func rejectsASegmentWhoseContentsOverrunTheFile() {
    let (data, size) = imageWith(segment64(fileoff: 0, filesize: 0xffff_0000), fileSize: 4096)
    #expect(rejects(data, fileSize: size))
}

@Test func rejectsASegmentSizeThatWouldOverflowOnConversion() {
    // UInt64.max would TRAP a plain Int() conversion — the hostile case the
    // clamping exists for. It must be rejected, not crash the validator.
    let (data, size) = imageWith(segment64(fileoff: 0, filesize: .max), fileSize: 4096)
    #expect(rejects(data, fileSize: size))
}

@Test func rejectsASectionPointingBeyondTheFile() {
    let segment = segment64(fileoff: 0, filesize: 16, sections: [section64(size: 16, offset: 0xffff_0000)])
    let (data, size) = imageWith(segment, fileSize: 4096)
    #expect(rejects(data, fileSize: size))
}

@Test func rejectsASectionWhoseContentsOverrunTheFile() {
    let segment = segment64(fileoff: 0, filesize: 16, sections: [section64(size: 0xffff_0000, offset: 64)])
    let (data, size) = imageWith(segment, fileSize: 4096)
    #expect(rejects(data, fileSize: size))
}

@Test func rejectsASymbolTableBeyondTheFile() {
    let (data, size) = imageWith(symtab(symoff: 0xffff_0000, nsyms: 4, stroff: 0, strsize: 0), fileSize: 4096)
    #expect(rejects(data, fileSize: size))
}

@Test func rejectsASymbolCountThatCannotFitInTheFile() {
    // No separate "too many symbols" rule: nsyms × sizeof(nlist_64) simply does
    // not fit, which is the same arithmetic as an out-of-range offset.
    let (data, size) = imageWith(symtab(symoff: 64, nsyms: 0x00ff_ffff, stroff: 0, strsize: 0), fileSize: 4096)
    #expect(rejects(data, fileSize: size))
}

@Test func rejectsAStringTableBeyondTheFile() {
    let (data, size) = imageWith(symtab(symoff: 0, nsyms: 0, stroff: 64, strsize: 0xffff_0000), fileSize: 4096)
    #expect(rejects(data, fileSize: size))
}

// MARK: - Payload over-rejection guards

@Test func acceptsAZeroFillSectionLargerThanTheFile() {
    // `__bss` occupies NO file bytes: its size is a memory extent and is
    // routinely larger than the whole binary. Bounds-checking it against the
    // file would reject essentially every real linker output.
    let bss = section64(size: 0x0010_0000, offset: 0, flags: 0x1)   // S_ZEROFILL
    let segment = segment64(name: "__DATA", fileoff: 0, filesize: 16, sections: [bss])
    let (data, size) = imageWith(segment, fileSize: 4096)
    #expect(!rejects(data, fileSize: size))
}

@Test func acceptsAWellFormedSegmentAndSymbolTable() {
    let segment = segment64(fileoff: 0, filesize: 1024, sections: [section64(size: 512, offset: 128)])
    let header = machHeader64(ncmds: 2, sizeofcmds: UInt32(segment.count + 24))
    let table = symtab(symoff: 2048, nsyms: 16, stroff: 3072, strsize: 512)
    #expect(!rejects(header + segment + table, fileSize: 8192))
}

// MARK: - End-to-end: the payload crashes, reproduced

/// The header-shaped corpus above is synthetic. This one mutates a REAL linked
/// binary, which is what exposed this class in the first place: a hand-built
/// header never reaches the code that reads a segment's contents.
///
/// Each mutation below was observed killing the CLI by SIGTRAP before the
/// payload checks existed — 12 crashes over four subcommands, with EMPTY stderr,
/// so the process vanished without a diagnostic. `disasm` is deliberately absent:
/// it survived even then, because llvm-objdump rejects the file before MachOKit
/// parses it, which is exactly why the earlier survey missed this.
@Test func theCLISurvivesMalformedLoadCommandPayloads() throws {
    let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
    let fixture = URL(fileURLWithPath: "Fixtures/Sample/libReconstruction.dylib")
    guard FileManager.default.fileExists(atPath: binary.path),
          FileManager.default.fileExists(atPath: fixture.path)
    else { return }
    var image = try Data(contentsOf: fixture)

    func u32(_ offset: Int) -> UInt32 {
        image[image.startIndex + offset ..< image.startIndex + offset + 4]
            .reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }
    func patch(_ data: inout Data, _ offset: Int, _ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { bytes in
            for (index, byte) in bytes.enumerated() { data[data.startIndex + offset + index] = byte }
        }
    }
    func patch64(_ data: inout Data, _ offset: Int, _ value: UInt64) {
        withUnsafeBytes(of: value.littleEndian) { bytes in
            for (index, byte) in bytes.enumerated() { data[data.startIndex + offset + index] = byte }
        }
    }

    // Locate the first section-bearing segment and the symbol table.
    var segmentOffset: Int?, symtabOffset: Int?
    var cursor = 32
    for _ in 0 ..< Int(u32(16)) {
        let cmd = u32(cursor), size = u32(cursor + 4)
        if cmd == 0x19, segmentOffset == nil, u32(cursor + 64) > 0 { segmentOffset = cursor }
        if cmd == 0x2 { symtabOffset = cursor }
        cursor += Int(size)
    }
    guard let segment = segmentOffset, let symbols = symtabOffset else { return }

    var cases: [String: Data] = [:]
    for (name, mutate) in [
        ("seg_fileoff", { (d: inout Data) in patch64(&d, segment + 40, 0xffff_ffff_0000_0000) }),
        ("seg_filesize", { (d: inout Data) in patch64(&d, segment + 48, 0xffff_ffff_0000_0000) }),
        ("sect_offset", { (d: inout Data) in patch(&d, segment + 72 + 48, 0xffff_f000) }),
        ("symtab_symoff", { (d: inout Data) in patch(&d, symbols + 8, 0xffff_f000) }),
        ("symtab_nsyms", { (d: inout Data) in patch(&d, symbols + 12, 0x00ff_ffff) }),
        ("symtab_stroff", { (d: inout Data) in patch(&d, symbols + 16, 0xffff_f000) }),
        ("symtab_strsize", { (d: inout Data) in patch(&d, symbols + 20, 0xffff_f000) }),
    ] {
        var mutated = image
        mutate(&mutated)
        cases[name] = mutated
    }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-payload-\(ProcessInfo.processInfo.processIdentifier)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for (name, bytes) in cases {
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url)
        // The four subcommands that reach MachOKit directly, i.e. the ones that died.
        for subcommand in ["dump", "layout", "interface", "objc"] {
            let output = Pipe()
            let process = Process()
            process.executableURL = binary
            process.arguments = [subcommand, url.path]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let stdout = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            #expect(
                process.terminationReason == .exit,
                "\(subcommand) \(name): killed by signal \(process.terminationStatus)"
            )
            #expect(
                process.terminationStatus == 1,
                "\(subcommand) \(name): exit \(process.terminationStatus), expected 1"
            )
            // A rejected file must not also emit output that could read as success.
            #expect(
                stdout.isEmpty,
                "\(subcommand) \(name): produced \(stdout.count) bytes of stdout despite failing"
            )
        }
    }
}

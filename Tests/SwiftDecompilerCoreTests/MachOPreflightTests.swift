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

/// `filetype` defaults to `MH_OBJECT` (1): these tests are about structure, and
/// an object file is held to no segment requirements. A loadable image (2,
/// `MH_EXECUTE`) must also carry `__TEXT` and `__LINKEDIT`, as dyld requires;
/// see the segment tests at the end.
private func machHeader64(
    ncmds: UInt32, sizeofcmds: UInt32, magic: UInt32 = 0xfeed_facf, filetype: UInt32 = 1
) -> Data {
    var data = Data()
    for word: UInt32 in [magic, 0x0100_000c, 0, filetype, ncmds, sizeofcmds, 0, 0] {
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

// MARK: - Segments dyld requires of a loadable image

/// A structurally valid file can still lack what dyld requires, and MachOKit
/// aborted on it: renaming `__TEXT` to `__TEXTX` SIGTRAPped `dump`, `interface`,
/// `disasm` and `analyze`; hiding `__LINKEDIT` did the same. Each rejection
/// below is dyld's own (verified with `dlopen` on the re-signed mutant), and
/// an object file, whose one unnamed segment holds sections of every segment
/// name, must still pass.
private func fixtureLoadCommands() -> Data? {
    guard let data = FileManager.default.contents(atPath: "Fixtures/Sample/libSample.dylib") else { return nil }
    return data
}

/// Overwrite the 16-byte name at `offset` (a segment's `segname`, or a
/// section's `segname` at section + 16).
private func renamed(_ data: Data, at offset: Int, to name: String) -> Data {
    var copy = data
    let bytes = Array(name.utf8) + Array(repeating: 0, count: 16 - name.utf8.count)
    copy.replaceSubrange(offset..<(offset + 16), with: bytes)
    return copy
}

/// File offsets of each `LC_SEGMENT_64` segname, by name, and of each of its
/// sections' segnames.
private func segmentNameOffsets(_ data: Data) -> [String: (segment: Int, sections: [Int])] {
    func u32(_ at: Int) -> UInt32 { data.subdata(in: at..<at + 4).withUnsafeBytes { $0.load(as: UInt32.self) } }
    var result: [String: (Int, [Int])] = [:]
    var offset = 32
    for _ in 0..<Int(u32(16)) {
        let cmd = u32(offset), size = Int(u32(offset + 4))
        if cmd == 0x19 {
            let name = String(decoding: data[(offset + 8)..<(offset + 24)].prefix { $0 != 0 }, as: UTF8.self)
            let sections = (0..<Int(u32(offset + 64))).map { offset + 72 + $0 * 80 + 16 }
            result[name] = (offset + 8, sections)
        }
        offset += size
    }
    return result
}

@Test func rejectsASectionInASegmentItDoesNotNameIfPresent() throws {
    guard let data = fixtureLoadCommands() else { return }
    let text = try #require(segmentNameOffsets(data)["__TEXT"])
    // `__TEXT` stays present; only one section disagrees about its segment
    // (dyld: "section '__text' segment name '__TEXTX' does not match containing
    // segment's name '__TEXT'").
    let first = try #require(text.sections.first)
    #expect(rejects(renamed(data, at: first, to: "__TEXTX")))
}

@Test func rejectsALoadableImageWithoutTextIfPresent() throws {
    guard let data = fixtureLoadCommands() else { return }
    let text = try #require(segmentNameOffsets(data)["__TEXT"])
    // Rename the segment and every section's copy of the name, consistently:
    // only the absence of `__TEXT` is left to catch.
    var mutated = renamed(data, at: text.segment, to: "__TEXTX")
    for section in text.sections { mutated = renamed(mutated, at: section, to: "__TEXTX") }
    #expect(rejects(mutated))
}

@Test func rejectsALoadableImageWithoutLinkeditIfPresent() throws {
    guard let data = fixtureLoadCommands() else { return }
    let linkedit = try #require(segmentNameOffsets(data)["__LINKEDIT"])
    #expect(rejects(renamed(data, at: linkedit.segment, to: "__LINKEDITX")))
}

@Test func rejectsAnExecutableHeaderWithNoSegments() {
    // dyld: "missing __TEXT segment". The same bytes as an object file pass.
    #expect(rejects(machHeader64(ncmds: 0, sizeofcmds: 0, filetype: 2)))
    #expect(!rejects(machHeader64(ncmds: 0, sizeofcmds: 0, filetype: 1)))
}

@Test func acceptsTheRealImageAndAnObjectFileIfPresent() throws {
    guard let data = fixtureLoadCommands(),
          let object = FileManager.default.contents(atPath: "Fixtures/Sample/sample_objc.o")
    else { return }
    #expect(!rejects(data))
    // One unnamed segment holding `__TEXT`, `__DATA` and `__LD` sections.
    #expect(!rejects(object))
}

private func u32(_ data: Data, _ at: Int) -> UInt32 {
    data.subdata(in: at..<at + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
}

private func setU64(_ data: inout Data, _ at: Int, _ value: UInt64) {
    withUnsafeBytes(of: value.littleEndian) { data.replaceSubrange(at..<at + 8, with: $0) }
}

/// dyld: "section '__swift5_types' end address 0xF900000000004428 is beyond
/// containing segment's end address 0x8000" (a fuzz mutant that flipped the top
/// byte of a section's `addr`; it SIGSEGVed `dump` and `interface`).
@Test func rejectsASectionAddressedOutsideItsSegmentIfPresent() throws {
    guard var data = fixtureLoadCommands() else { return }
    let text = try #require(segmentNameOffsets(data)["__TEXT"])
    let addr = try #require(text.sections.first) + 16   // segname (+16) → addr (+32)
    setU64(&data, addr, 0xF900_0000_0000_4000)
    #expect(rejects(data))
}

/// A Go binary's `__DWARF` is an unmapped segment (`vmsize` 0) of debug
/// sections sized past its empty range, and dyld loads it
/// (`com.docker.build`): the address rule must not apply to it.
@Test func acceptsDebugSectionsOfAnUnmappedSegmentIfPresent() throws {
    guard var data = fixtureLoadCommands() else { return }
    let segment = try #require(segmentNameOffsets(data)["__DATA"])
    setU64(&data, segment.segment + 24, 0)               // segname (+8) → vmsize (+32)
    for section in segment.sections {
        let flags = section + 48                          // segname (+16) → flags (+64)
        var value = u32(data, flags) | 0x0200_0000
        withUnsafeBytes(of: &value) { data.replaceSubrange(flags..<flags + 4, with: $0) }
    }
    #expect(!rejects(data))
}

/// dyld: "chained fixups, seg_count exceeds number of segments". A flipped
/// byte in a segment's `cmd` turns it into an unknown command, its memory
/// vanishes, and metadata pointers into it read unmapped pages (SIGSEGV in
/// `dump`/`interface`). The fixups payload sits in `__LINKEDIT`, so this goes
/// through `validate(url:)`, which reads it from the file.
@Test func rejectsAnImageThatLostASegmentItsFixupsCountIfPresent() throws {
    guard var data = fixtureLoadCommands() else { return }
    let segment = try #require(segmentNameOffsets(data)["__DATA"])
    let cmd = segment.segment - 8
    data[cmd + 3] = 0x1d                                  // LC_SEGMENT_64 → 0x1d000019
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-lost-segment-\(UUID().uuidString).dylib")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: (any Error).self) { try MachOPreflight.validate(url: url) }

    // The untouched image passes the same path.
    let original = url.deletingLastPathComponent()
        .appendingPathComponent("swiftdc-intact-\(UUID().uuidString).dylib")
    try fixtureLoadCommands()?.write(to: original)
    defer { try? FileManager.default.removeItem(at: original) }
    try MachOPreflight.validate(url: original)
}

// MARK: - __swift5_assocty, by record layout

/// One `AssociatedTypeDescriptor`: two relative pointers, a record count, a
/// record size, then `count` records of two relative pointers. `deltas` are
/// the six (or more) pointer fields in order.
private func assocty(count: UInt32, recordSize: UInt32 = 8, deltas: [Int32]) -> Data {
    var data = Data()
    func put(_ word: UInt32) { withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) } }
    put(UInt32(bitPattern: deltas[0])); put(UInt32(bitPattern: deltas[1]))
    put(count); put(recordSize)
    for delta in deltas.dropFirst(2) { put(UInt32(bitPattern: delta)) }
    return data
}

private func rejectsAssocty(_ bytes: Data, at offset: Int = 4096, fileSize: Int = 8192) -> Bool {
    (try? MachOPreflight.validateAssociatedTypeTable(bytes: bytes, sectionOffset: offset, fileSize: fileSize)) == nil
}

@Test func acceptsAWellFormedAssociatedTypeTable() {
    // Pointers backwards into the file, as the compiler emits them.
    #expect(!rejectsAssocty(assocty(count: 1, deltas: [-100, -200, -300, -400])))
    #expect(!rejectsAssocty(assocty(count: 0, deltas: [-100, -200])))
}

/// Each of these crashed every subcommand when the mutated byte reached
/// MachOSwiftSection (fuzz mutants 17, 30, 54, 65, 80, 81).
@Test func rejectsAMalformedAssociatedTypeTable() {
    // A count whose records run past the section (mutant 17: 4865 records).
    #expect(rejectsAssocty(assocty(count: 4865, deltas: [-100, -200, -300, -400])))
    // A name pointer before the file's start (mutant 30: offset -3796).
    #expect(rejectsAssocty(assocty(count: 1, deltas: [-8000, -200, -300, -400])))
    // A record pointer past the end of the file (mutant 54).
    #expect(rejectsAssocty(assocty(count: 1, deltas: [-100, -200, 0x4000_0000, -400])))
    // A record size the compiler never emits.
    #expect(rejectsAssocty(assocty(count: 1, recordSize: 12, deltas: [-100, -200, -300, -400])))
    // A descriptor cut off by the section's end.
    #expect(rejectsAssocty(assocty(count: 1, deltas: [-100, -200, -300, -400]).prefix(12)))
}

@Test func rejectsTheFuzzedAssociatedTypeMutantIfPresent() throws {
    // `metadata-fuzz.py libSample.dylib 100 1234`, mutant 17: one byte at 0x3e9d.
    guard var data = FileManager.default.contents(atPath: "Fixtures/Sample/libSample.dylib") else { return }
    data[0x3e9d] = 19
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-assocty-\(UUID().uuidString).dylib")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: (any Error).self) { try MachOPreflight.validate(url: url) }
}

// MARK: - __objc_methlist, list by list

/// A relative method list at `0x1000`: header, then `names.count` 12-byte
/// methods whose name offsets are `names` (types and imp offsets zero).
private func methodList(_ names: [Int32], header: UInt32 = 0x8000_000c) -> Data {
    var data = Data()
    func put(_ word: UInt32) { withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) } }
    put(header); put(UInt32(names.count))
    for name in names { put(UInt32(bitPattern: name)); put(0); put(0) }
    return data
}

private let selrefs: (addr: UInt64, size: Int) = (0x2000, 64)

/// The relative offset from method `method`'s name field (in a list at
/// `0x1000`) to selector-reference slot `slot`.
private func nameOffset(method: Int, slot: Int) -> Int32 {
    let field: Int = 0x1000 + 8 + 12 * method
    let target: Int = 0x2000 + 8 * slot
    return Int32(target - field)
}

private func rejectsMethodLists(_ bytes: Data) -> Bool {
    (try? MachOPreflight.validateObjCMethodLists(bytes: bytes, sectionAddress: 0x1000, selrefs: selrefs)) == nil
}

@Test func acceptsRelativeMethodListsNamingSelectorReferences() {
    // Method i's name field sits at 0x1000 + 8 + 12i; aim each at a selref slot.
    let names: [Int32] = (0..<3).map { nameOffset(method: $0, slot: $0) }
    let first = methodList(names)
    // Zero padding, then a second list (its fields start after the first + 4).
    let secondStart = 0x1000 + first.count + 4
    let second = methodList([Int32(0x2038) - Int32(secondStart + 8)])
    #expect(!rejectsMethodLists(first + Data(repeating: 0, count: 4) + second))
    // An unrecognised header ends the walk without a verdict.
    #expect(!rejectsMethodLists(methodList([0x7fff_0000], header: 0x0000_0010)))
}

/// Fuzz mutant 13 redirected a name onto bytes that are not a selector
/// reference; MachOObjCSection read them as a pointer and `strlen` SIGSEGVed
/// `objc`, `disasm`, `xrefs` and `analyze`.
@Test func rejectsAMethodNameThatIsNotASelectorReference() {
    let names: [Int32] = (0..<2).map { nameOffset(method: $0, slot: $0) }
    #expect(rejectsMethodLists(methodList([names[0], names[1] + 4])))     // misaligned slot
    #expect(rejectsMethodLists(methodList([names[0], 0x00fd_c398])))      // far outside
    #expect(rejectsMethodLists(methodList([names[0]]).prefix(16)))        // list cut short
    var overrun = methodList([names[0]])
    overrun.replaceSubrange(4..<8, with: [0xff, 0xff, 0, 0])               // 65535 methods
    #expect(rejectsMethodLists(overrun))
}

@Test func rejectsTheFuzzedMethodListMutantIfPresent() throws {
    guard var data = FileManager.default.contents(atPath: "Fixtures/Sample/libSample.dylib") else { return }
    // `metadata-fuzz.py libSample.dylib 100 1234`, mutant 13.
    for (offset, value) in [(0x3792, 253), (0x378e, 239), (0x37d3, 23), (0x37d1, 87)] {
        data[offset] = UInt8(value)
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-methlist-\(UUID().uuidString).dylib")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: (any Error).self) { try MachOPreflight.validate(url: url) }
}

// MARK: - __swift5_mpenum, by record layout

/// One `MultiPayloadEnumDescriptor`: a relative `TypeName`, then `words`
/// content words, the first holding `words << 16`.
private func mpenum(typeName: Int32, words: UInt32) -> Data {
    var data = Data()
    func put(_ word: UInt32) { withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) } }
    put(UInt32(bitPattern: typeName)); put(words << 16)
    for _ in 1..<max(words, 1) { put(0) }
    return data
}

private func rejectsMPEnum(_ bytes: Data) -> Bool {
    (try? MachOPreflight.validateMultiPayloadEnumTable(bytes: bytes, sectionOffset: 4096, fileSize: 8192)) == nil
}

@Test func acceptsAWellFormedMultiPayloadEnumTable() {
    #expect(!rejectsMPEnum(mpenum(typeName: -100, words: 1) + mpenum(typeName: -200, words: 3)))
}

/// Fuzz mutants 19, 21, 33, 42 and 90 each trapped `objc`, `disasm` and
/// `analyze` with `Negative value is not representable`.
@Test func rejectsAMalformedMultiPayloadEnumTable() {
    // A type name before the file's start.
    #expect(rejectsMPEnum(mpenum(typeName: -8000, words: 1)))
    // A type name past its end.
    #expect(rejectsMPEnum(mpenum(typeName: 0x4000_0000, words: 1)))
    // Content words running past the section (mutant 19: 51 words).
    var long = mpenum(typeName: -100, words: 1)
    long.replaceSubrange(4..<8, with: [0, 0, 51, 0])
    #expect(rejectsMPEnum(long))
    // Zero content words, which the runtime asserts against. Read as a
    // 4-byte descriptor, the next words would misparse into a valid-looking
    // one (`0` as its type name, `1 << 16` as its size), so only the
    // zero-words rule catches it.
    var empty = Data()
    for word: UInt32 in [UInt32(bitPattern: -100), 0, 1 << 16] {
        withUnsafeBytes(of: word.littleEndian) { empty.append(contentsOf: $0) }
    }
    #expect(rejectsMPEnum(empty))
}

// MARK: - __swift5_fieldmd, by record layout

/// One `FieldDescriptor`: relative type name and superclass, `Kind` and
/// `FieldRecordSize` (u16s), `NumFields`, then 12-byte records of `Flags` and
/// two relative pointers. `deltas` are the header's two pointers, then each
/// record's two.
private func fieldmd(count: UInt32, recordSize: UInt16 = 12, deltas: [Int32]) -> Data {
    var data = Data()
    func put(_ word: UInt32) { withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) } }
    put(UInt32(bitPattern: deltas[0])); put(UInt32(bitPattern: deltas[1]))
    put(UInt32(recordSize) << 16 | 1); put(count)
    var rest = deltas.dropFirst(2)
    while let type = rest.popFirst() {
        put(0); put(UInt32(bitPattern: type)); put(UInt32(bitPattern: rest.popFirst() ?? 0))
    }
    return data
}

private func rejectsFieldmd(_ bytes: Data) -> Bool {
    (try? MachOPreflight.validateFieldDescriptorTable(bytes: bytes, sectionOffset: 4096, fileSize: 8192)) == nil
}

@Test func acceptsAWellFormedFieldDescriptorTable() {
    // A null superclass (delta 0) points at itself, inside the file.
    #expect(!rejectsFieldmd(fieldmd(count: 2, deltas: [-100, 0, -300, -400, -500, -600])))
}

@Test func rejectsAMalformedFieldDescriptorTable() {
    #expect(rejectsFieldmd(fieldmd(count: 1, deltas: [-8000, 0, -300, -400])))          // type name
    #expect(rejectsFieldmd(fieldmd(count: 1, deltas: [-100, 0x4000_0000, -300, -400])))  // superclass
    #expect(rejectsFieldmd(fieldmd(count: 1, deltas: [-100, 0, -300, -8000])))           // field name
    #expect(rejectsFieldmd(fieldmd(count: 9, deltas: [-100, 0, -300, -400])))            // past the end
    #expect(rejectsFieldmd(fieldmd(count: 1, recordSize: 16, deltas: [-100, 0, -300, -400])))
}

/// `metadata-fuzz.py sample.release 150 4242`, mutant 5: two bytes in
/// `__swift5_fieldmd` trapped five subcommands.
@Test func rejectsTheFuzzedFieldDescriptorMutantIfPresent() throws {
    guard var data = FileManager.default.contents(atPath: "Fixtures/Sample/sample.release") else { return }
    data[0x3f7a] = 163
    data[0x4140] = 86
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-fieldmd-\(UUID().uuidString)")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: (any Error).self) { try MachOPreflight.validate(url: url) }
}

// MARK: - Descriptor tables never point into code

/// A `__swift5_proto` entry aimed into `__text` stays inside the file, so the
/// bounds check passed, but the conformance descriptor was then parsed out of
/// machine code and its protocol pointer trapped in `resolveBind(fileOffset:)`
/// (`metadata-fuzz.py sample.release 150 4242`, mutant 31: one byte).
@Test func rejectsADescriptorEntryPointingIntoCode() throws {
    var table = Data()
    withUnsafeBytes(of: Int32(-2000).littleEndian) { table.append(contentsOf: $0) }   // → 2096
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateRelativePointerTable(
            bytes: table, sectionOffset: 4096, fileSize: 8192, name: "__swift5_proto",
            code: [1024..<3072])
    }
    try MachOPreflight.validateRelativePointerTable(
        bytes: table, sectionOffset: 4096, fileSize: 8192, name: "__swift5_proto",
        code: [3072..<4000])
}

@Test func rejectsTheFuzzedConformanceMutantIfPresent() throws {
    guard var data = FileManager.default.contents(atPath: "Fixtures/Sample/sample.release") else { return }
    data[0x44fd] = 218
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-proto-\(UUID().uuidString)")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: (any Error).self) { try MachOPreflight.validate(url: url) }
}

/// A method's type-encoding offset flipped out of the file sent `strlen` off
/// the mapping (`metadata-fuzz.py sample.release 150 4242`, mutant 105).
@Test func rejectsAMethodTypeEncodingOutsideTheFile() throws {
    var list = methodList([nameOffset(method: 0, slot: 0)])
    // Method 0's types field is at +12; point it far past an 8192-byte file.
    list.replaceSubrange(12..<16, with: [0x8b, 0x44, 0x00, 0x13])
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateObjCMethodLists(
            bytes: list, sectionAddress: 0x1000, selrefs: selrefs, sectionOffset: 0x1000, fileSize: 8192)
    }
    // The same list with an in-file type encoding passes.
    list.replaceSubrange(12..<16, with: [0x00, 0x01, 0x00, 0x00])
    try MachOPreflight.validateObjCMethodLists(
        bytes: list, sectionAddress: 0x1000, selrefs: selrefs, sectionOffset: 0x1000, fileSize: 8192)
}

// MARK: - Objective-C pointer arrays

private let chained6 = MachOPreflight.PointerEncoding.chained(format: 6, imageBase: 0x1_0000_0000, imports: 4)

@Test func decodesChainedAndPlainPointers() {
    // Format 6: a 36-bit offset from the image base; format 2: the address.
    #expect(MachOPreflight.decodePointer(0x0000_c5e0, chained6) == .address(0x1_0000_c5e0))
    #expect(MachOPreflight.decodePointer(0x1_0000_c5e0,
        .chained(format: 2, imageBase: 0, imports: 4)) == .address(0x1_0000_c5e0))
    // A bind: bit 63, ordinal in the low 24 bits, checked against the imports.
    #expect(MachOPreflight.decodePointer(1 << 63 | 3, chained6) == .bind)
    #expect(MachOPreflight.decodePointer(1 << 63 | 9, chained6) == .badBind(9))
    // A format this check does not decode declines (7: DYLD_CHAINED_PTR_32_FIRMWARE).
    #expect(MachOPreflight.decodePointer(0x1234, .chained(format: 7, imageBase: 0, imports: 4)) == .undecoded)
    // arm64e (`mach-o/fixup-chains.h`): bit 62 bind, bit 63 auth.
    let base: UInt64 = 0x1_0000_0000
    func e(_ format: UInt16, imports: UInt32 = 4) -> MachOPreflight.PointerEncoding {
        .chained(format: format, imageBase: base, imports: imports)
    }
    // USERLAND24 binds carry a 24-bit ordinal; the other formats 16 bits.
    #expect(MachOPreflight.decodePointer(1 << 62 | 0x1_0003, e(12, imports: 0x2_0000)) == .bind)
    #expect(MachOPreflight.decodePointer(1 << 62 | 0x1_0003, e(12)) == .badBind(0x1_0003))
    #expect(MachOPreflight.decodePointer(1 << 62 | 0x1_0003, e(9)) == .bind)
    // An authenticated rebase: a 32-bit offset, the diversity bits above it ignored.
    #expect(MachOPreflight.decodePointer(1 << 63 | 0xbeef << 32 | 0xc5e0, e(12)) == .address(base + 0xc5e0))
    // A plain rebase: a 43-bit target with the top byte at bits 43-50; a vmaddr
    // in DYLD_CHAINED_PTR_ARM64E, an offset from the base in USERLAND(24).
    #expect(MachOPreflight.decodePointer(0xab << 43 | 0xc5e0, e(12)) == .address(0xab << 56 | (base + 0xc5e0)))
    #expect(MachOPreflight.decodePointer(0x1_0000_c5e0, e(1)) == .address(0x1_0000_c5e0))
    #expect(MachOPreflight.decodePointer(0x1_0000_c5e0, .plain) == .address(0x1_0000_c5e0))
}

private func slots(_ values: [UInt64]) -> Data {
    var data = Data()
    for value in values { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    return data
}

private let objcData: [(name: String, addr: UInt64, size: Int)] = [("__objc_data", 0x1_0000_c400, 0x200)]

@Test func checksEachObjCPointerArraySlot() throws {
    // In range, aligned, and a bind inside the import table: accepted.
    try MachOPreflight.validateObjCPointerArray(
        bytes: slots([0xc4a8, 0xc530, 1 << 63 | 2]), name: "__objc_classlist",
        encoding: chained6, allowed: objcData)
    let bad: [UInt64] = [
        0xa430,             // outside __objc_data (fuzz mutant 6)
        0xc52a,             // inside, but the middle of an object (mutant 47)
        0x2_0000_c4a8,      // a flipped high byte (mutant 108)
        1 << 63 | 40,       // a bind past the import table
    ]
    for value in bad {
        #expect(throws: (any Error).self, "\(String(value, radix: 16))") {
            try MachOPreflight.validateObjCPointerArray(
                bytes: slots([value]), name: "__objc_classlist", encoding: chained6, allowed: objcData)
        }
    }
    // Selector strings carry no alignment.
    try MachOPreflight.validateObjCPointerArray(
        bytes: slots([0xc401]), name: "__objc_selrefs", encoding: chained6,
        allowed: [("__objc_methname", 0x1_0000_c400, 0x100)])
}

@Test func rejectsTheFuzzedObjCPointerMutantsIfPresent() throws {
    guard let original = FileManager.default.contents(atPath: "Fixtures/Sample/sample.release") else { return }
    // `metadata-fuzz.py sample.release 150 4242`: classlist 108, selrefs 21, catlist 12.
    for edit in [(0x855c, 146), (0xc37b, 36), (0x8569, 216)] {
        var data = original
        data[edit.0] = UInt8(edit.1)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftdc-objcptr-\(UUID().uuidString)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self, "edit at \(String(edit.0, radix: 16))") {
            try MachOPreflight.validate(url: url)
        }
    }
}

// MARK: - Objective-C classes, through their pointer fields

/// `metadata-fuzz.py sample.release 150 4242`: each mutant corrupts one layer
/// of a class (class, metaclass, `class_ro_t` in `__objc_const` or
/// `__objc_data`, ivar and property lists), and each crashed `objc` or
/// `analyze` before the class walk.
@Test func rejectsTheFuzzedObjCClassMutantsIfPresent() throws {
    guard let original = FileManager.default.contents(atPath: "Fixtures/Sample/sample.release") else { return }
    let mutants: [(Int, [(Int, UInt8)])] = [
        (7, [(0xc49d, 176), (0xc57b, 248)]),                              // metaclass data
        (10, [(0xc524, 238), (0xc539, 117), (0xc545, 114), (0xc47d, 228)]), // superclass bind
        (84, [(0xc2fd, 26), (0xc090, 252)]),                               // method list
        (111, [(0xc46f, 187), (0xc475, 59), (0xc4f3, 9), (0xc45c, 94)]),   // class_ro_t in __objc_data
        (117, [(0xc16b, 225), (0xc329, 150)]),                             // property list
        (119, [(0xc1ed, 67), (0xc280, 98), (0xc2c3, 29), (0xc279, 93)]),   // ivar entry
        (141, [(0xc4aa, 51), (0xc4cf, 128), (0xc553, 38), (0xc4a9, 140)]), // class isa
    ]
    for (index, edits) in mutants {
        var data = original
        for (offset, value) in edits { data[offset] = value }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftdc-objcclass-\(index)-\(UUID().uuidString)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self, "mutant \(index)") { try MachOPreflight.validate(url: url) }
    }
}

/// A one-class image in plain pointers: the class at 0x1000 (`__objc_data`),
/// its read-only data at 0x2000 (`__objc_const`), a name at 0x3000.
private func oneClassReader(
    cache: UInt64 = 0, ivarList: UInt64 = 0, ivarHeader: (UInt32, UInt32) = (32, 1), ivarType: UInt64 = 0x3000,
    methodList: UInt64 = 0, ivarName: UInt64 = 0x3000
) -> MachOPreflight.PointerReader {
    func words(_ values: [UInt64], size: Int) -> Data {
        var data = Data()
        for value in values { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        return data + Data(repeating: 0, count: max(0, size - data.count))
    }
    // The class at 0x1000 and its own metaclass at 0x1080.
    var objcData = words([0x1080, 0, cache, 0, 0x2000], size: 0x80)
    objcData += words([0, 0, 0, 0, 0x2000], size: 0x80)
    var objcConst = words([0, 0, 0, 0x3000, methodList, 0, ivarList, 0, 0], size: 0x100)
    // An ivar list at 0x2080 with one 32-byte entry: offset, name, type.
    var list = Data()
    for word in [ivarHeader.0, ivarHeader.1] { withUnsafeBytes(of: word.littleEndian) { list.append(contentsOf: $0) } }
    list += words([0x4000, ivarName, ivarType, 0], size: 32)
    objcConst.replaceSubrange(0x80..<(0x80 + list.count), with: list)
    return MachOPreflight.PointerReader(
        sections: [
            ("__objc_data", 0x1000, 0x100, 0, objcData),
            ("__objc_const", 0x2000, 0x100, 0, objcConst),
            ("__cstring", 0x3000, 0x100, 0, nil),
            ("__objc_ivar", 0x4000, 0x10, 0, nil),
            ("__const", 0x5000, 0x100, 0, nil),
        ],
        encodings: [0: .plain])
}

@Test func walksAClassThroughItsPointerFields() throws {
    try MachOPreflight.validateObjCClasses([0x1000], reader: oneClassReader())
    try MachOPreflight.validateObjCClasses([0x1000], reader: oneClassReader(ivarList: 0x2080))
    // `cache` is only ever bound to `_objc_empty_cache` or null.
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateObjCClasses([0x1000], reader: oneClassReader(cache: 0x2000))
    }
    // An ivar's type is an encoding string.
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateObjCClasses([0x1000], reader: oneClassReader(ivarList: 0x2080, ivarType: 0x2000))
    }
    // An ivar list must use 32-byte entries and fit its section.
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateObjCClasses([0x1000], reader: oneClassReader(ivarList: 0x2080, ivarHeader: (24, 1)))
    }
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateObjCClasses([0x1000], reader: oneClassReader(ivarList: 0x2080, ivarHeader: (32, 500)))
    }
}

/// x86_64 slices lay Objective-C metadata out differently from arm64: a
/// pointer-based method list in `__objc_data` (86 in the arm64e sweep's fat
/// system binaries) and ivar and property names in `__TEXT,__const` (7 in
/// the universal binaries under /Applications).
@Test func acceptsTheX86_64ObjCLayouts() throws {
    try MachOPreflight.validateObjCClasses([0x1000], reader: oneClassReader(methodList: 0x10c0))
    try MachOPreflight.validateObjCClasses([0x1000], reader: oneClassReader(ivarList: 0x2080, ivarName: 0x5000))
    // A method list is still never in a string section.
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateObjCClasses([0x1000], reader: oneClassReader(methodList: 0x3000))
    }
}

// MARK: - __swift5_builtin, mangled names, spare-bit masks

@Test func checksBuiltinTypeDescriptors() throws {
    var table = Data()
    for word: UInt32 in [UInt32(bitPattern: -100), 8, 8, 8, 0] {
        withUnsafeBytes(of: word.littleEndian) { table.append(contentsOf: $0) }
    }
    try MachOPreflight.validateBuiltinTypeTable(bytes: table, sectionOffset: 4096, fileSize: 8192)
    var bad = table
    bad.replaceSubrange(0..<4, with: [0x00, 0x00, 0x00, 0x40])
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateBuiltinTypeTable(bytes: bad, sectionOffset: 4096, fileSize: 8192)
    }
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateBuiltinTypeTable(bytes: table.prefix(16), sectionOffset: 4096, fileSize: 8192)
    }
}

/// Names parse from the starts the records point at, by the symbolic-reference
/// grammar; the rest of `__swift5_typeref` is never walked, because current
/// toolchains place binary records between the names (walking it whole falsely
/// rejected 130 of 832 real binaries).
@Test func parsesMangledNamesFromTheirStartsOnly() throws {
    let segments: [Range<UInt64>] = [0x1000..<0x3000]
    // At +0: "S" then a direct reference whose payload holds a NUL, then "i",
    // NUL. At +16: record bytes that would read as a wild reference.
    var section = Data([0x53, 0x01]) + Data([0x00, 0x08, 0x00, 0x00]) + Data([0x69, 0x00])
    section += Data(repeating: 0, count: 8)
    section += Data([0x01, 0xff, 0xff, 0xff, 0x7f, 0x00])
    try MachOPreflight.validateMangledNames(
        at: [0x2000], in: section, sectionOffset: 0x2000, sectionAddress: 0x2000,
        segments: segments, name: "__swift5_typeref")
    // The same bytes, reached from +16, are rejected.
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateMangledNames(
            at: [0x2010], in: section, sectionOffset: 0x2000, sectionAddress: 0x2000,
            segments: segments, name: "__swift5_typeref")
    }
}

@Test func checksAMultiPayloadEnumSpareBitMask() {
    func descriptor(_ words: [UInt32]) -> Data {
        var data = Data()
        for word in [UInt32(bitPattern: -100)] + words {
            withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
    func rejects(_ bytes: Data) -> Bool {
        (try? MachOPreflight.validateMultiPayloadEnumTable(bytes: bytes, sectionOffset: 4096, fileSize: 8192)) == nil
    }
    // Flag 1 set: a mask-size word, then a 4-byte mask in one more word.
    #expect(!rejects(descriptor([3 << 16 | 1, 4, 0xff])))
    // Flag set, but only the size-flags word (fuzz mutant 88).
    #expect(rejects(descriptor([1 << 16 | 1])))
    // A 12-byte mask in a record with room for one word.
    #expect(rejects(descriptor([3 << 16 | 1, 12, 0xff])))
}

@Test func rejectsTheFuzzedReconstructionMutantsIfPresent() throws {
    guard let original = FileManager.default.contents(atPath: "Fixtures/Sample/libReconstruction.opt.dylib") else { return }
    // `metadata-fuzz.py libReconstruction.opt.dylib 150 777`.
    let mutants: [(String, [(Int, UInt8)])] = [
        ("builtin type name", [(0x3db3, 144), (0x3da3, 252)]),
        ("typeref symbolic reference", [(0x316d, 236), (0x318e, 243)]),
        ("mpenum spare bits", [(0x3db8, 243)]),
        ("class ro protocol list turned into a bind", [(0xc0bf, 216)]),
        ("metaclass ro protocol list", [(0xc102, 39)]),
    ]
    for (what, edits) in mutants {
        var data = original
        for (offset, value) in edits { data[offset] = value }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftdc-recon-\(UUID().uuidString)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self, "\(what)") { try MachOPreflight.validate(url: url) }
    }
}

/// One segment of 64-byte pages in `DYLD_CHAINED_PTR_64_OFFSET` with two
/// imports, its chain starting at `pageStart` of page 0; `slots` are raw
/// values by byte offset into the segment.
private func chainedFixupsFixture(_ slots: [Int: UInt64], pageStart: UInt16 = 0) -> (blob: Data, segment: Data) {
    var blob = Data(count: 64)
    func put32(_ value: UInt32, _ at: Int) { withUnsafeBytes(of: value.littleEndian) { blob.replaceSubrange(at..<at + 4, with: $0) } }
    func put16(_ value: UInt16, _ at: Int) { withUnsafeBytes(of: value.littleEndian) { blob.replaceSubrange(at..<at + 2, with: $0) } }
    put32(32, 4); put32(2, 16)      // starts_offset, imports_count
    put32(1, 32); put32(8, 36)      // seg_count, seg_info_offset[0]
    put16(64, 44); put16(6, 46)     // page_size, pointer_format
    put16(1, 60); put16(pageStart, 62)  // page_count, page_start[0]
    var segment = Data(count: 128)  // a second page, so a chain leaving the first still reads
    for (offset, raw) in slots {
        withUnsafeBytes(of: raw.littleEndian) { segment.replaceSubrange(offset..<offset + 8, with: $0) }
    }
    return (blob, segment)
}

private func rebase(_ next: UInt64, to target: UInt64 = 0x1000) -> UInt64 { next << 51 | target }

private func walkChains(_ slots: [Int: UInt64], pageStart: UInt16 = 0) throws -> MachOPreflight.ChainEntries {
    let (blob, segment) = chainedFixupsFixture(slots, pageStart: pageStart)
    return try MachOPreflight.validateFixupChains(
        blob: blob, startsOffset: 32, segmentCount: 1, readSegment: { _ in (0x4000, segment) }
    )
}

@Test func walksFixupChainsAndRecordsTheSlotsTheyReach() throws {
    // +0, +8, +24, +32, ending in the page; one bind of import 1.
    let entries = try walkChains([0: rebase(2), 8: rebase(4), 24: 1 << 63 | 2 << 51 | 1, 32: rebase(0)])
    #expect([0, 8, 24, 32].allSatisfy { entries.contains(0x4000 + $0) })
    #expect(![16, 40, 64].contains { entries.contains(0x4000 + $0) })
    // Electron Framework's x86_64 slices put chained pointers at 4-byte offsets.
    #expect(try walkChains([0: rebase(3), 12: rebase(0)]).contains(0x400c))
}

@Test func rejectsAChainDyldWouldNotWalk() {
    func rejects(_ slots: [Int: UInt64], pageStart: UInt16 = 0) -> Bool {
        (try? walkChains(slots, pageStart: pageStart)) == nil
    }
    #expect(rejects([0: 1 << 63 | 5]))                          // a bind past the two imports
    #expect(rejects([2: rebase(0)], pageStart: 2))              // a chain starting mid-word
    #expect(rejects(Dictionary(uniqueKeysWithValues: (0..<8).map { ($0 * 8, rebase(2)) })))  // off the page
}

@Test func rejectsAPointerSlotNoChainReaches() throws {
    func validate(_ slots: [Int: UInt64]) throws {
        var bytes = Data(count: 24)
        for (offset, raw) in slots {
            withUnsafeBytes(of: raw.littleEndian) { bytes.replaceSubrange(offset..<offset + 8, with: $0) }
        }
        try MachOPreflight.validateObjCPointerArray(
            bytes: bytes, name: "__objc_selrefs", encoding: .chained(format: 6, imageBase: 0, imports: 2),
            allowed: [("__objc_methname", 0x1000, 16)], address: 0x4000, chainEntries: try walkChains(slots)
        )
    }
    try validate([0: rebase(2), 8: rebase(2), 16: rebase(0)])
    // `next` 4 from +0 skips the slot at +8, as the fuzz mutants' flipped bits do.
    #expect(throws: (any Error).self) { try validate([0: rebase(4), 8: rebase(2), 16: rebase(0)]) }
}

/// `metadata-fuzz.py sample.release 150 99`: each mutant flips `next` bits
/// of a chained pointer, so MachOKit's walk lands mid-pointer and a
/// MachOObjCSection `try!` traps.
@Test func rejectsTheFuzzedFixupChainMutantsIfPresent() throws {
    try expectMutantsRejected("Fixtures/Sample/sample.release", [
        ("selref next 2 -> 29", [(0xc37e, 236)]),
        ("class data next", [(0xc57e, 155), (0xc53d, 0)]),
    ])
}

/// `metadata-fuzz.py libReconstruction.resilient.dylib 150 31`, mutants 64
/// and 124: `__swift5_proto` entries aimed into the middle of a descriptor.
@Test func rejectsTheFuzzedMisalignedConformanceMutantsIfPresent() throws {
    try expectMutantsRejected("Fixtures/Sample/libReconstruction.resilient.dylib", [
        ("proto mutant 64", [(0xcb28, 249), (0xcb1c, 246)]),
        ("proto mutant 124", [(0xcb2c, 85)]),
    ])
}

private func expectMutantsRejected(_ path: String, _ mutants: [(String, [(Int, UInt8)])]) throws {
    guard let original = FileManager.default.contents(atPath: path) else { return }
    for (what, edits) in mutants {
        var data = original
        for (offset, value) in edits { data[offset] = value }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftdc-mutant-\(UUID().uuidString)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self, "\(what)") { try MachOPreflight.validate(url: url) }
    }
}

/// `validate(url:)` sized the file with `attributesOfItem`, which describes a
/// symlink itself, not its target: `/usr/bin/ex` (a link to `vim`) was
/// "3 byte(s); too short to contain a magic number", and 47 of the 1,434
/// arm64e system binaries were refused the same way.
@Test func validatesABinaryReachedThroughASymlinkIfPresent() throws {
    let target = URL(fileURLWithPath: "Fixtures/Sample/sample.release").standardizedFileURL
    guard FileManager.default.fileExists(atPath: target.path) else { return }
    let link = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-link-\(UUID().uuidString)")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    defer { try? FileManager.default.removeItem(at: link) }
    #expect(throws: Never.self) { try MachOPreflight.validate(url: link) }
}

@Test func checksTheProtocolAndReferenceArrays() throws {
    let sections: [(name: String, addr: UInt64, size: Int)] = [
        ("__data", 0x1_0000_d000, 0x100), ("__objc_data", 0x1_0000_c400, 0x200),
    ]
    func rejects(_ name: String, _ values: [UInt64], nullable: Bool = false) -> Bool {
        (try? MachOPreflight.validateObjCPointerArray(
            bytes: slots(values), name: name, encoding: chained6,
            allowed: sections.filter { name == "__objc_protolist" ? $0.name == "__data" : $0.name == "__objc_data" },
            nullable: nullable)) == nil
    }
    #expect(!rejects("__objc_protolist", [0xd040]))
    #expect(rejects("__objc_protolist", [0xff_d040]))                // a protocol outside `__data`
    #expect(rejects("__objc_protolist", [0]))                         // lists never hold nulls
    #expect(!rejects("__objc_classrefs", [0xc4a8, 0, 1 << 63 | 1], nullable: true))
}

/// `metadata-fuzz.py` on the arm64e slice of Stickies (60 mutants, seed 11):
/// one byte of an `__objc_protolist` slot trapped MachOObjCSection's file
/// reader in every ObjC-reading subcommand. Located at run time, since the
/// system binary's layout changes between OS versions.
@Test func rejectsACorruptProtocolListSlotInASystemBinaryIfPresent() throws {
    let path = "/System/Applications/Stickies.app/Contents/MacOS/Stickies"
    guard var data = FileManager.default.contents(atPath: path) else { return }
    var protolist: Int?
    for slice in MachOPreflight.fatSliceExtents(prefix: data, fileSize: data.count) {
        let thin = data.subdata(in: slice.offset..<slice.offset + slice.size)
        if let section = MachOPreflight.sectionTable(prefix: thin)?.sections.first(where: { $0.name == "__objc_protolist" }) {
            protolist = slice.offset + section.offset
        }
    }
    guard let protolist else { return }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-protolist-\(UUID().uuidString)")
    try data.write(to: url)
    #expect(throws: Never.self) { try MachOPreflight.validate(url: url) }
    data[protolist + 2] ^= 0xff                                       // the target moves by up to 16 MB
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: (any Error).self) { try MachOPreflight.validate(url: url) }
}

/// A protocol at 0x6000 (`__data`), named by `__cstring` at 0x3000, with an
/// instance method list at 0x2000 (`__objc_const`).
private func oneProtocolReader(size: UInt32 = 96, name: UInt64 = 0x3000) -> MachOPreflight.PointerReader {
    var proto = Data()
    for value: UInt64 in [0, name, 0, 0x2000, 0, 0, 0, 0] {
        withUnsafeBytes(of: value.littleEndian) { proto.append(contentsOf: $0) }
    }
    for word: UInt32 in [size, 0] { withUnsafeBytes(of: word.littleEndian) { proto.append(contentsOf: $0) } }
    proto += Data(count: 0x100 - proto.count)
    return MachOPreflight.PointerReader(
        sections: [
            ("__objc_const", 0x2000, 0x100, 0, Data(count: 0x100)),
            ("__cstring", 0x3000, 0x100, 0, nil),
            ("__data", 0x6000, 0x100, 0, proto),
        ],
        encodings: [0: .plain])
}

@Test func walksAProtocolThroughItsPointerFields() throws {
    try MachOPreflight.validateObjCClasses([], protocols: [0x6000], reader: oneProtocolReader())
    // A list slot aimed 8 bytes into the protocol: its "name" is the null
    // protocol list (the Stickies mutant's shape).
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateObjCClasses([], protocols: [0x6008], reader: oneProtocolReader())
    }
    // A name outside the string sections, and a size running past `__data`.
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateObjCClasses([], protocols: [0x6000], reader: oneProtocolReader(name: 0x2000))
    }
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateObjCClasses([], protocols: [0x6000], reader: oneProtocolReader(size: 0x400))
    }
}

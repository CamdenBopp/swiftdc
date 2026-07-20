import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `MachOPreflight` validates the Mach-O container; these cover the first
/// section **contents** it looks inside.
///
/// Corrupting a relative pointer in `__swift5_protos` / `__swift5_proto` /
/// `__swift5_types` killed **every** subcommand with empty stderr. The pointer
/// resolves to an offset outside the file, and the dependency converts it to
/// unsigned before bounds-checking, so it traps (`Negative value is not
/// representable`) or walks off the mapping with `strlen` — neither catchable
/// from swiftdc.
///
/// The rule is one number against another the file declares: `target =
/// pointerOffset + value` must land inside the file. Sign is **not** the test —
/// verified on real binaries, where every entry points backwards into `__TEXT`.

private func table(_ deltas: [Int32]) -> Data {
    var data = Data()
    for delta in deltas {
        withUnsafeBytes(of: delta.littleEndian) { data.append(contentsOf: $0) }
    }
    return data
}

private func rejects(_ deltas: [Int32], sectionOffset: Int, fileSize: Int) -> Bool {
    do {
        try MachOPreflight.validateRelativePointerTable(
            bytes: table(deltas), sectionOffset: sectionOffset, fileSize: fileSize,
            name: "__swift5_types"
        )
        return false
    } catch {
        return true
    }
}

// MARK: - Must reject

@Test func rejectsARelativePointerResolvingPastTheFile() {
    // pointer at 1000, delta +9000 → 10000, past a 5000-byte file.
    #expect(rejects([9_000], sectionOffset: 1_000, fileSize: 5_000))
}

@Test func rejectsARelativePointerResolvingBeforeTheFile() {
    // The observed crash: a negative resolved offset reaches `numericCast` and
    // traps rather than being rejected.
    #expect(rejects([-2_000], sectionOffset: 1_000, fileSize: 5_000))
}

@Test func rejectsABadEntryAmongGoodOnes() {
    // A single corrupt entry is enough; the table is not valid because most of
    // it happens to be.
    #expect(rejects([-100, -200, 9_999_999, -300], sectionOffset: 1_000, fileSize: 5_000))
}

@Test func rejectsTheExtremeInt32Deltas() {
    // The values a byte-level mutation actually produces.
    #expect(rejects([Int32.min], sectionOffset: 1_000, fileSize: 5_000))
    #expect(rejects([Int32.max], sectionOffset: 1_000, fileSize: 5_000))
}

// MARK: - Must accept (the over-rejection guard)

@Test func acceptsNegativeDeltasThatResolveInsideTheFile() {
    // NOT a corner case — every entry in every real fixture is negative, because
    // the tables sit after the descriptors they point at. A validator that
    // rejected negative deltas would refuse every Swift binary in existence.
    #expect(!rejects([-100, -500, -999], sectionOffset: 1_000, fileSize: 5_000))
}

@Test func acceptsAPointerToTheFirstAndLastValidByte() {
    // Boundaries: 0 is in-file, fileSize - 1 is in-file, fileSize is not.
    #expect(!rejects([-1_000], sectionOffset: 1_000, fileSize: 5_000))   // → 0
    #expect(!rejects([3_999], sectionOffset: 1_000, fileSize: 5_000))    // → 4999
    #expect(rejects([4_000], sectionOffset: 1_000, fileSize: 5_000))     // → 5000
}

@Test func acceptsAnEmptyTable() {
    #expect(!rejects([], sectionOffset: 1_000, fileSize: 5_000))
}

@Test func acceptsEveryRealFixtureTableIfPresent() throws {
    // The strongest over-rejection evidence available: real linker output,
    // including a 30 MB+ binary whose tables hold thousands of entries and sit
    // far beyond the 1 MiB header prefix.
    let paths = [
        "Fixtures/Sample/libSample.dylib",
        "Fixtures/Sample/libReconstruction.dylib",
        "Fixtures/Sample/sample.release",
        "Fixtures/Sample/sample.stripped",
        ".build/debug/swiftdc",
    ]
    var checked: [String] = []
    for path in paths where FileManager.default.fileExists(atPath: path) {
        #expect(throws: Never.self) {
            try MachOPreflight.validate(url: URL(fileURLWithPath: path))
        }
        checked.append((path as NSString).lastPathComponent)
    }
    // Named, not counted: if the fixtures stop building this would otherwise
    // pass having validated nothing.
    #expect(
        checked.contains("libSample.dylib") || checked.isEmpty,
        "expected libSample.dylib among validated binaries, got \(checked)"
    )
}

// MARK: - End to end

/// Mutating a real binary's `__swift5_protos` pointer used to kill every
/// subcommand by signal, with empty stderr. Driven as a subprocess because a
/// trap in-process would take the test runner down too.
@Test func theCLISurvivesACorruptRelativePointerTableIfPresent() throws {
    let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
    let fixture = "Fixtures/Sample/libSample.dylib"
    guard FileManager.default.fileExists(atPath: binary.path),
          FileManager.default.fileExists(atPath: fixture)
    else { return }

    // Locate __swift5_protos from the load commands rather than hardcoding an
    // offset, so a rebuilt fixture does not silently mutate the wrong bytes and
    // turn this into a test of nothing.
    let image = try Data(contentsOf: URL(fileURLWithPath: fixture))
    func u32(_ offset: Int) -> UInt32 {
        image[image.startIndex + offset ..< image.startIndex + offset + 4]
            .reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }
    var sectionOffset: Int?
    var cursor = 32
    for _ in 0 ..< Int(u32(16)) {
        let cmd = u32(cursor), size = u32(cursor + 4)
        if cmd == 0x19 {
            let count = Int(u32(cursor + 64))
            for section in 0 ..< count {
                let base = cursor + 72 + section * 80
                let raw = image[image.startIndex + base ..< image.startIndex + base + 16]
                let name = String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                if name == "__swift5_protos" { sectionOffset = Int(u32(base + 48)) }
            }
        }
        cursor += Int(size)
    }
    let target = try #require(sectionOffset, "__swift5_protos not found in the fixture")

    var corrupted = image
    // A delta that resolves far before the file: the SIGTRAP shape.
    withUnsafeBytes(of: Int32(-0x40_0000).littleEndian) { bytes in
        for (index, byte) in bytes.enumerated() {
            corrupted[corrupted.startIndex + target + index] = byte
        }
    }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-relptr-\(ProcessInfo.processInfo.processIdentifier)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("corrupt_protos")
    try corrupted.write(to: url)

    // All eight metadata-reading subcommands died on this input. `disasm` and
    // `xrefs` are included deliberately: llvm-objdump shields them from
    // container corruption but not from metadata corruption.
    for subcommand in [["dump"], ["interface"], ["objc"], ["objc", "--methods"],
                       ["layout"], ["disasm"], ["xrefs", "--unreferenced"], ["analyze"]] {
        let output = Pipe()
        let process = Process()
        process.executableURL = binary
        process.arguments = subcommand + [url.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let label = subcommand.joined(separator: " ")
        #expect(
            process.terminationReason == .exit,
            "\(label): killed by signal \(process.terminationStatus)"
        )
        #expect(
            process.terminationStatus == 1,
            "\(label): exit \(process.terminationStatus), expected 1"
        )
        #expect(stdout.isEmpty, "\(label): emitted \(stdout.count) bytes despite failing")
    }
}

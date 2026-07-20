import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A fat binary's slices are Mach-O headers in their own right. `MachOPreflight`
/// validated each slice's *extent* (offset/size in the file) but not the thin
/// header *inside* the slice — so a slice whose `sizeofcmds` claimed load
/// commands past its own bounds passed preflight and then trapped in MachOKit
/// (`MachOFile.swift:61: Fatal error: 'try!'`) when `fat.machOFiles()` parsed
/// it. The trap is uncatchable, the same class as every other MachOKit malformed
/// input. Confirmed by corrupting a real fat binary's slice header.
///
/// The fix bounds the slice's thin header against the *slice* size, with the
/// same two checks `validateThin` applies to a top-level header.

// MARK: - Slice-header consistency (pure unit)

private func header64(ncmds: UInt32, sizeofcmds: UInt32, magic: UInt32 = 0xfeed_facf) -> Data {
    var data = Data()
    for word: UInt32 in [magic, 0x0100_000c, 0, 2, ncmds, sizeofcmds, 0, 0] {
        withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
    }
    return data
}

private func rejectsSlice(_ header: Data, sliceSize: Int) -> Bool {
    do {
        try MachOPreflight.validateSliceThinHeader(
            header: header, sliceSize: sliceSize, index: 0
        )
        return false
    } catch { return true }
}

@Test func rejectsASliceWhoseLoadCommandsOverrunTheSlice() {
    // The observed crash: sizeofcmds far larger than the slice.
    #expect(rejectsSlice(header64(ncmds: 5, sizeofcmds: 0x00ff_ffff), sliceSize: 48_128))
}

@Test func rejectsASliceCommandCountThatCannotFitItsByteBudget() {
    // Huge ncmds with a small sizeofcmds — malformed even though MachOKit happens
    // to tolerate it by walking `sizeofcmds` and ignoring the excess count.
    #expect(rejectsSlice(header64(ncmds: 0x00ff_ffff, sizeofcmds: 64), sliceSize: 48_128))
}

@Test func rejectsASliceShorterThanItsHeader() {
    #expect(rejectsSlice(header64(ncmds: 0, sizeofcmds: 0), sliceSize: 16))
}

@Test func acceptsAWellFormedSliceHeader() {
    // A real slice: modest load commands that fit comfortably.
    #expect(!rejectsSlice(header64(ncmds: 20, sizeofcmds: 2_400), sliceSize: 48_128))
}

@Test func ignoresASliceThatIsNotAThinMachO() {
    // A non-Mach-O magic (a nested fat, or padding) is not the trap class and is
    // left for MachOKit to decline cleanly. Rejecting it here could refuse a
    // shape MachOKit handles — over-rejection, which is worse than the crash.
    var data = Data()
    withUnsafeBytes(of: UInt32(0xcafe_babe).bigEndian) { data.append(contentsOf: $0) }
    data.append(Data(repeating: 0, count: 60))
    #expect(!rejectsSlice(data, sliceSize: 4_096))
}

@Test func extractsFatSliceExtents() {
    // fat_header (BE): magic, nfat=2, then two fat_arch (cputype, cpusubtype,
    // offset, size, align).
    var data = Data()
    func be(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
    be(0xcafe_babe); be(2)
    be(0x0100_0007); be(0); be(16_384); be(48_128); be(14)   // slice 0
    be(0x0100_000c); be(0); be(65_536); be(88_672); be(14)   // slice 1
    // pad the file out so the extents are in-bounds
    let fileSize = 200_000
    let extents = MachOPreflight.fatSliceExtents(prefix: data, fileSize: fileSize)
    #expect(extents.count == 2)
    #expect(extents.first?.offset == 16_384 && extents.first?.size == 48_128)
    #expect(extents.last?.offset == 65_536 && extents.last?.size == 88_672)
    // A thin binary has no slices.
    #expect(MachOPreflight.fatSliceExtents(prefix: header64(ncmds: 0, sizeofcmds: 0), fileSize: 32).isEmpty)
}

// MARK: - End to end (subprocess)

/// The crash cannot be observed in-process; drive the built CLI. Requires a real
/// fat binary — `/bin/ls` is fat on macOS — and skips cleanly without one.
@Test func theCLISurvivesACorruptFatSliceHeaderIfPresent() throws {
    let cli = URL(fileURLWithPath: ".build/debug/swiftdc")
    let source = "/bin/ls"
    guard FileManager.default.fileExists(atPath: cli.path),
          FileManager.default.fileExists(atPath: source)
    else { return }

    var image = try Data(contentsOf: URL(fileURLWithPath: source))
    func beU32(_ offset: Int) -> UInt32 {
        image[image.startIndex + offset ..< image.startIndex + offset + 4]
            .reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }
    guard beU32(0) == 0xcafe_babe else { return }   // 32-bit fat; skip other shapes
    let nfat = Int(beU32(4))
    guard nfat >= 1 else { return }
    // fat_arch[0].offset is at 8 + 8; slice arches follow.
    let sliceOffset = Int(beU32(8 + 8))
    let arches = (0 ..< nfat).map { i -> String in
        // cputype at 8 + i*20 ; 0x0100000c = arm64, 0x01000007 = x86_64
        switch beU32(8 + i * 20) {
        case 0x0100_000c: return "arm64e"
        case 0x0100_0007: return "x86_64"
        default: return "arm64"
        }
    }
    // Corrupt slice 0's thin header: sizeofcmds (at slice+20, little-endian) huge.
    withUnsafeBytes(of: UInt32(0x00ff_ffff).littleEndian) { bytes in
        for (i, b) in bytes.enumerated() { image[image.startIndex + sliceOffset + 20 + i] = b }
    }

    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-fatslice-\(ProcessInfo.processInfo.processIdentifier)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let corrupt = dir.appendingPathComponent("corrupt_fat")
    try image.write(to: corrupt)

    // Both arch selections must survive — the crash reproduced when the corrupted
    // slice was reached, and `fat.machOFiles()` touches every slice.
    for arch in arches {
        let out = Pipe()
        let process = Process()
        process.executableURL = cli
        process.arguments = ["dump", corrupt.path, "--arch", arch]
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(
            process.terminationReason == .exit,
            "--arch \(arch): killed by signal \(process.terminationStatus)"
        )
        #expect(
            process.terminationStatus == 1,
            "--arch \(arch): exit \(process.terminationStatus), expected 1"
        )
        #expect(stdout.isEmpty, "--arch \(arch): emitted \(stdout.count) bytes despite failing")
    }
}

/// Over-rejection: a real, uncorrupted fat binary must still load. The slice
/// check must reject only inconsistent headers, never a valid multi-arch file.
@Test func realFatBinariesStillLoadIfPresent() throws {
    for path in ["/bin/ls", "/usr/lib/dyld"] where FileManager.default.fileExists(atPath: path) {
        #expect(throws: Never.self) {
            try MachOPreflight.validate(url: URL(fileURLWithPath: path))
        }
    }
}

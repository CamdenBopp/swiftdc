import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

/// MachOKit's own readers, under swiftdc's preflight. `MachOPreflight`
/// refuses a malformed opcode stream or export trie before MachOKit sees
/// it; these open the file with MachOKit directly, as code that skips the
/// preflight would, and require its readers to end instead of trapping,
/// looping or reading past the stream. The fork pinned before 87e16e69 did
/// not bound them (p-x9/MachOKit #358).
private let opcodeImage = "Fixtures/Sample/libEmuImage.opcodes.dylib"

/// `image` with one range of its LC_DYLD_INFO replaced, written to a
/// temporary file. `range` picks the (offset, size) pair by its index in
/// `dyld_info_command`: 0 rebase, 1 bind, 2 weak bind, 3 lazy bind, 4 export.
private func corrupted(range index: Int, with bytes: (Int) -> [UInt8]) throws -> URL? {
    guard FileManager.default.fileExists(atPath: opcodeImage) else { return nil }
    var data = try Data(contentsOf: URL(fileURLWithPath: opcodeImage))
    func u32(_ at: Int) -> Int {
        Int(data.subdata(in: at..<at + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
    }
    let commandCount = u32(16)
    var cursor = 32
    var found: (offset: Int, size: Int)?
    for _ in 0..<commandCount {
        let command = u32(cursor), size = u32(cursor + 4)
        // LC_DYLD_INFO (0x22) or LC_DYLD_INFO_ONLY (0x80000022).
        if command & 0x7fff_ffff == 0x22 {
            found = (u32(cursor + 8 + index * 8), u32(cursor + 12 + index * 8))
        }
        cursor += size
    }
    let target = try #require(found, "no LC_DYLD_INFO in \(opcodeImage)")
    try #require(target.size > 2)
    let replacement = bytes(target.size)
    try #require(replacement.count == target.size)
    data.replaceSubrange(target.offset..<target.offset + target.size, with: replacement)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-hardening-\(index)-\(UUID().uuidString).dylib")
    try data.write(to: url)
    return url
}

/// A ULEB128 that never ends: the opcode, then continuation bytes to the
/// last byte of the stream.
private func unterminatedULEB(after opcode: UInt8) -> (Int) -> [UInt8] {
    { size in [opcode] + Array(repeating: 0xff, count: size - 1) }
}

@Test(.timeLimit(.minutes(1)))
func aBindStreamWhoseULEBRunsOffItsEndIsReadWithoutATrapIfPresent() throws {
    // BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB (0x80).
    guard let url = try corrupted(range: 1, with: unterminatedULEB(after: 0x80)) else { return }
    defer { try? FileManager.default.removeItem(at: url) }
    let file = try MachOFile(url: url)
    let operations = file.bindOperations.map { Array($0) } ?? []
    #expect(operations.count <= 0x30, "read \(operations.count) operations from a 48-byte stream")
}

@Test(.timeLimit(.minutes(1)))
func aRebaseStreamWhoseULEBRunsOffItsEndIsReadWithoutATrapIfPresent() throws {
    // REBASE_OPCODE_ADD_ADDR_ULEB (0x30).
    guard let url = try corrupted(range: 0, with: unterminatedULEB(after: 0x30)) else { return }
    defer { try? FileManager.default.removeItem(at: url) }
    let file = try MachOFile(url: url)
    let operations = file.rebaseOperations.map { Array($0) } ?? []
    #expect(operations.count <= 8, "read \(operations.count) operations from an 8-byte stream")
}

@Test(.timeLimit(.minutes(1)))
func anExportTrieThatPointsBackAtItsRootIsWalkedToAnEndIfPresent() throws {
    // The root: no terminal data, one child labelled "a" at offset 0, the
    // root again. A walk that follows it without a bound never returns.
    guard let url = try corrupted(range: 4, with: { size in
        [0x00, 0x01, 0x61, 0x00, 0x00] + Array(repeating: 0x00, count: size - 5)
    }) else { return }
    defer { try? FileManager.default.removeItem(at: url) }
    let file = try MachOFile(url: url)
    let symbols = Array(file.exportedSymbols)
    #expect(symbols.count < 4096, "\(symbols.count) symbols from a 320-byte trie")
}

/// The same files through swiftdc itself. The export trie is refused by
/// the preflight, as an error. The two opcode streams are not: the
/// preflight checks their ranges and special ordinals, not that each ULEB
/// ends, so those files reach MachOKit's readers through `disasm`, which
/// must come back, with functions or with an error, and never trap.
@Test(.timeLimit(.minutes(2)))
func swiftdcSurvivesEachOfThoseFilesIfPresent() async throws {
    guard let trie = try corrupted(range: 4, with: { size in
        [0x00, 0x01, 0x61, 0x00, 0x00] + Array(repeating: 0x00, count: size - 5)
    }) else { return }
    defer { try? FileManager.default.removeItem(at: trie) }
    #expect(throws: (any Error).self) { _ = try BinaryLoader.load(path: trie.path) }

    for (index, opcode) in [(1, UInt8(0x80)), (0, UInt8(0x30))] {
        guard let url = try corrupted(range: index, with: unterminatedULEB(after: opcode)) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let functions = try? await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: url.path)
        }
        // Reaching this line is the claim. The code sections are intact,
        // so a run that does not refuse the file still finds its functions.
        if let functions { #expect(!functions.isEmpty, "range \(index)") }
    }
}

import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

/// The same Objective-C built with opcode rebases (`LC_DYLD_INFO`, macOS 11
/// target) and with chained fixups (macOS 13). Read only through chained
/// fixups, the opcode build lost every selector reference and CFString:
/// `NSLog(0x4000)`, sends as unresolved calls, and a tail-called send left
/// the function a leaf. Both builds now render the same.
@Test func anOpcodeRebasedImageReadsSelectorsAndStringsIfPresent() async throws {
    let opcode = "Fixtures/Sample/libOpcodeFixups.dylib"
    let chained = "Fixtures/Sample/libOpcodeFixups.chained.dylib"
    guard FileManager.default.fileExists(atPath: opcode), FileManager.default.fileExists(atPath: chained) else { return }
    func render(_ path: String) async throws -> [String: String] {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        return Dictionary(functions.map { ($0.displayName, $0.renderStructured()) }, uniquingKeysWith: { a, _ in a })
    }
    let old = try await render(opcode)
    let new = try await render(chained)
    let report = try #require(old["_report"])
    #expect(report.contains("NSLog(@\"n=%ld\", arg1)"), Comment(rawValue: report))
    #expect(report.contains("[arg0 removeAllObjects]"), Comment(rawValue: report))
    #expect(old["_tailClear"]?.contains("removeAllObjects]") == true, Comment(rawValue: old["_tailClear"] ?? ""))
    for name in ["_report", "_tailClear"] {
        #expect(old[name] == new[name], "\(name) differs:\n\(old[name] ?? "")\n---\n\(new[name] ?? "")")
    }
}

/// The opcode fixture with its rebase or bind stream replaced, padded with
/// DONE to the stream's own size. Nil when the fixture is missing.
private func patchedOpcodeFixture(rebase: [UInt8]? = nil, bind: [UInt8]? = nil) throws -> MachOFile? {
    let path = "Fixtures/Sample/libOpcodeFixups.dylib"
    guard var data = FileManager.default.contents(atPath: path) else { return nil }
    // LC_DYLD_INFO_ONLY: cmd, cmdsize, rebase_off, rebase_size, bind_off, bind_size.
    func word(_ at: Int) -> Int { Int(data[at..<at + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }) }
    var command = 32
    var streams: (rebase: Range<Int>, bind: Range<Int>)?
    for _ in 0..<word(16) {
        if word(command) == 0x8000_0022 {
            streams = (word(command + 8)..<word(command + 8) + word(command + 12),
                       word(command + 16)..<word(command + 16) + word(command + 20))
        }
        command += word(command + 4)
    }
    let (rebaseRange, bindRange) = try #require(streams)
    for (range, ops) in [(rebaseRange, rebase), (bindRange, bind)] {
        guard let ops else { continue }
        try #require(ops.count <= range.count)
        data.replaceSubrange(range, with: ops + [UInt8](repeating: 0, count: range.count - ops.count))
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-opcodes-\(UUID().uuidString).dylib")
    try data.write(to: url)
    guard case .machO(let machO) = try MachOKit.loadFromFile(url: url) else { return nil }
    return machO
}

private func uleb(_ value: UInt64) -> [UInt8] {
    var value = value, out: [UInt8] = []
    repeat {
        let byte = UInt8(value & 0x7f); value >>= 7
        out.append(value == 0 ? byte : byte | 0x80)
    } while value != 0
    return out
}

/// A malformed rebase stream claims nothing and costs no more than its
/// segments have slots. MachOKit's `rebases` built one entry per
/// repetition (`DO_REBASE_ULEB_TIMES 2^28` passed 3 GB) and a segment
/// offset of 2^63 trapped converting to `Int`.
@Test func aMalformedRebaseStreamIsBoundedIfPresent() throws {
    // SET_TYPE pointer, SET_SEGMENT seg 2 offset …, then the repetition.
    let streams: [String: [UInt8]] = [
        "offset 2^63": [0x11, 0x72] + uleb(1 << 63) + [0x51, 0x00],
        "offset Int.max": [0x11, 0x72] + uleb(UInt64(Int.max)) + [0x51, 0x00],
        "offset wraps to -8": [0x11, 0x72, 0x00, 0x20] + uleb(UInt64.max - 7) + [0x51, 0x00],
        "2^28 repetitions": [0x11, 0x72, 0x00, 0x60] + uleb(1 << 28) + [0x00],
        "2^40 repetitions": [0x11, 0x72, 0x00, 0x60] + uleb(1 << 40) + [0x00],
        "2^34 skipping 2^40": [0x11, 0x72, 0x00, 0x80] + uleb(1 << 34) + uleb(1 << 40) + [0x00],
    ]
    for (name, ops) in streams.sorted(by: { $0.key < $1.key }) {
        guard let machO = try patchedOpcodeFixture(rebase: ops) else { return }
        let targets = ChainedRebases.opcodeTargets(in: machO)
        #expect((targets?.count ?? 0) <= 1, "\(name): \(targets?.count ?? 0) targets")
    }
}

/// A malformed bind stream binds nothing and ends. A count of 2^40 grew
/// past 3 GB, and a skip that wraps the cursor in place never ended.
@Test func aMalformedBindStreamIsBoundedIfPresent() throws {
    // SET_DYLIB_ORDINAL 1, SET_SYMBOL "_x", SET_TYPE pointer, SET_SEGMENT 2.
    let prefix: [UInt8] = [0x11, 0x40, 0x5f, 0x78, 0x00, 0x51, 0x72, 0x00]
    let streams: [String: [UInt8]] = [
        "2^40 times": prefix + [0xc0] + uleb(1 << 40) + uleb(0) + [0x00],
        "2^62 times, skip wraps in place": prefix + [0xc0] + uleb(1 << 62) + uleb(UInt64.max - 7) + [0x00],
    ]
    for (name, ops) in streams.sorted(by: { $0.key < $1.key }) {
        guard let machO = try patchedOpcodeFixture(bind: ops) else { return }
        #expect(ObjCMetadataSnapshot.externalBindSlots(in: machO).isEmpty, "\(name)")
    }
}

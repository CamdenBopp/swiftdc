import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The malformed linkedit shapes the synthetic corpus's mutator found to
/// trap, run past the file or overflow the stack inside MachOKit
/// (Tools/synthcorpus/mutate.py), each written into a copy of an opcode or
/// chained-fixup fixture. The preflight declines each by its own cause,
/// before any reader reaches it.
private struct Image {
    var bytes: [UInt8]

    init?(_ path: String) {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        bytes = [UInt8](data)
    }

    func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
    func u32(_ at: Int) -> Int { (0..<4).reduce(0) { $0 | Int(bytes[at + $1]) << (8 * $1) } }
    mutating func put16(_ at: Int, _ value: Int) { for i in 0..<2 { bytes[at + i] = UInt8((value >> (8 * i)) & 0xff) } }
    mutating func put32(_ at: Int, _ value: Int) { for i in 0..<4 { bytes[at + i] = UInt8((value >> (8 * i)) & 0xff) } }

    /// The offset of the first load command `cmd`.
    func command(_ cmd: Int) -> Int? {
        var cursor = 32
        for _ in 0..<u32(16) {
            if u32(cursor) == cmd { return cursor }
            cursor += u32(cursor + 4)
        }
        return nil
    }

    /// What the preflight says of these bytes, or nil when it accepts them.
    func preflight() throws -> String? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-linkedit-\(UUID().uuidString).dylib")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(bytes).write(to: url)
        do {
            try MachOPreflight.validate(url: url)
            return nil
        } catch {
            return "\(error)"
        }
    }
}

private func uleb(_ value: UInt64) -> [UInt8] {
    var value = value, out: [UInt8] = []
    repeat {
        let byte = UInt8(value & 0x7f); value >>= 7
        out.append(value == 0 ? byte : byte | 0x80)
    } while value != 0
    return out
}

private let opcodeFixture = "Fixtures/Sample/libOpcodeFixups.dylib"
private let chainedFixture = "Fixtures/Sample/libOpcodeFixups.chained.dylib"

@Test func bothFixturesPassThePreflightIfPresent() throws {
    for path in [opcodeFixture, chainedFixture] {
        guard let image = Image(path) else { return }
        #expect(try image.preflight() == nil, "\(path)")
    }
}

/// A rebase, bind or lazy stream that runs past the end of the file:
/// MachOKit read it with `try!` and trapped.
@Test func anOpcodeStreamPastTheFileIsDeclinedIfPresent() throws {
    guard let original = Image(opcodeFixture), let info = original.command(0x8000_0022) else { return }
    for (field, name) in [(12, "rebase"), (20, "bind"), (36, "lazy bind")] {
        var image = original
        image.put32(info + field, 0xffff_fff0)
        let message = try #require(try image.preflight(), "\(name)")
        #expect(message.contains("\(name) stream at offset"), Comment(rawValue: message))
    }
}

/// `SET_DYLIB_SPECIAL_IMM` with -4, which dyld does not define:
/// MachOKit stopped with `fatalError`.
@Test func anUnknownSpecialDylibOrdinalIsDeclinedIfPresent() throws {
    guard var image = Image(opcodeFixture), let info = image.command(0x8000_0022) else { return }
    let bind = image.u32(info + 16)
    image.bytes[bind] = 0x3c          // SET_DYLIB_SPECIAL_IMM, immediate 0xc: -4
    let message = try #require(try image.preflight())
    #expect(message.contains("special dylib ordinal -4"), Comment(rawValue: message))
    #expect(MachOPreflight.unknownBindSpecial([0x3f, 0x3e, 0x3d, 0x30, 0x00]) == nil)   // -1, -2, -3, 0
}

/// Function starts whose deltas wrap past 2^64: MachOKit added them
/// unchecked and trapped. A small start then a delta of 2^64 - 8.
@Test func functionStartsThatWrapAreDeclined() {
    #expect(MachOPreflight.functionStartsDefect(uleb(0x10) + uleb(UInt64.max - 7))?.contains("wrap") == true)
    #expect(MachOPreflight.functionStartsDefect(uleb(0x10) + uleb(0x20) + [0, 0, 0]) == nil)
}

/// Symbols with an empty string table: swiftdc's stub scan copied a symbol
/// list that read short, and trapped.
@Test func symbolsWithAnEmptyStringTableAreDeclinedIfPresent() throws {
    guard var image = Image(chainedFixture), let symtab = image.command(0x2) else { return }
    image.put32(symtab + 20, 0)
    let message = try #require(try image.preflight())
    #expect(message.contains("an empty string table"), Comment(rawValue: message))
}

/// A chained-fixup import table past its payload, and an import whose name
/// starts outside the symbol pool: MachOKit read past the file.
@Test func chainedImportsOutsideTheirPayloadAreDeclinedIfPresent() throws {
    guard let original = Image(chainedFixture), let fixups = original.command(0x8000_0034) else { return }
    let header = original.u32(fixups + 8)
    var huge = original
    huge.put32(header + 16, 0x7fff_ffff)
    let count = try #require(try huge.preflight())
    #expect(count.contains("import(s) of 4 bytes"), Comment(rawValue: count))
    try #require(original.u32(header + 16) > 0 && original.u32(header + 20) == 1)
    var named = original
    let first = header + original.u32(header + 8)
    named.put32(first, (original.u32(first) & 0x1ff) | (0x7fffff << 9))
    let name = try #require(try named.preflight())
    #expect(name.contains("symbol pool"), Comment(rawValue: name))
}

/// A multi-start page whose chain list runs past the page-start array:
/// MachOKit indexed it unchecked and trapped.
@Test func aMultiStartPastThePageStartsIsDeclinedIfPresent() throws {
    guard var image = Image(chainedFixture), let fixups = image.command(0x8000_0034) else { return }
    let header = image.u32(fixups + 8)
    let starts = header + image.u32(header + 4)
    var target: Int?
    for segment in 0..<image.u32(starts) {
        let offset = image.u32(starts + 4 + 4 * segment)
        if offset != 0, image.u16(starts + offset + 20) == 1 { target = starts + offset; break }
    }
    let base = try #require(target)
    image.put16(base + 22, 0x8001)
    let message = try #require(try image.preflight())
    #expect(message.contains("continue past the page-start array"), Comment(rawValue: message))
}

/// An export trie with no cycle but 5,000 nodes deep: MachOKit's recursion
/// overflowed the stack.
@Test func aTooDeepExportTrieIsDeclined() {
    var trie: [UInt8] = []
    let depth = 5000
    var offsets: [Int] = []
    // Each node: no terminal, one child edge "a" to the next node. Offsets
    // are fixed width (3-byte ULEB) so they can be filled in afterwards.
    for _ in 0..<depth {
        offsets.append(trie.count)
        trie += [0, 1, 0x61, 0, 0x80, 0x80, 0x00]
    }
    trie += [0, 0]
    for (index, at) in offsets.enumerated() {
        let next = index + 1 < depth ? offsets[index + 1] : trie.count - 2
        trie[at + 4] = UInt8(next & 0x7f) | 0x80
        trie[at + 5] = UInt8((next >> 7) & 0x7f) | 0x80
        trie[at + 6] = UInt8((next >> 14) & 0x7f)
    }
    #expect(MachOPreflight.exportTrieDefect(Data(trie))?.contains("nodes deep") == true)
}

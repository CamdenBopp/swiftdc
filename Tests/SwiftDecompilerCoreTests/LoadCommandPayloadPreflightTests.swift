import Testing
import Foundation
@testable import SwiftDecompilerCore

/// What a load command's payload points at, as opposed to whether its own
/// range is in bounds. A 2026-11-04 fuzz of load commands (`swift Tools/fuzz.swift
/// container`, four fixtures, 12,000 runs) crashed the CLI 31 times, each a
/// flipped byte that left the ranges legal and the contents wrong.

private func words(_ values: [UInt32]) -> Data {
    var data = Data()
    for value in values { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    return data
}

/// A thin 64-bit header of the given file type around `commands`.
private func image(filetype: UInt32 = 6, commands: [Data]) -> Data {
    let body = commands.reduce(Data(), +)
    return words([0xfeed_facf, 0x0100_000c, 0, filetype, UInt32(commands.count), UInt32(body.count), 0, 0]) + body
}

private func withReader<T>(
    _ data: Data, _ body: (MachOPreflight.ImageReader) throws -> T
) throws -> T {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("preflight-\(UUID().uuidString)")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    return try body(MachOPreflight.ImageReader(handle: handle, base: 0, size: data.count))
}

private func validatesFile(_ data: Data) throws -> Bool {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("preflight-\(UUID().uuidString)")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    do { try MachOPreflight.validate(url: url); return true } catch { return false }
}

// MARK: - Symbol strings

/// An image whose `nlist_64`s name `strx` values, then a string table.
private func symbolImage(strx: [UInt32], strings: Data) -> Data {
    let headerSize = 32 + 24
    let symoff = UInt32(headerSize), stroff = symoff + UInt32(strx.count * 16)
    let command = words([0x2, 24, symoff, UInt32(strx.count), stroff, UInt32(strings.count)])
    var data = image(commands: [command])
    for value in strx { data += words([value, 0, 0, 0]) }
    return data + strings
}

/// Why the symbol strings were declined, or nil.
private func symbolStringsFailure(_ data: Data) throws -> String? {
    try withReader(data) { reader in
        do {
            try MachOPreflight.validateSymbolStrings(prefix: data, image: reader, path: "t")
            return nil
        } catch { return "\(error)" }
    }
}

@Test func aSymbolNamedPastItsStringTableIsDeclined() throws {
    #expect(try symbolStringsFailure(symbolImage(strx: [1, 8], strings: Data([0, 0x61, 0, 0, 0, 0, 0, 0])))?.contains("offset 8 of a 8-byte") == true)
}

@Test func aSymbolWhoseStringNeverEndsIsDeclined() throws {
    #expect(try symbolStringsFailure(symbolImage(strx: [1], strings: Data([0, 0x61, 0x62, 0x63])))?.contains("no terminator") == true)
}

@Test func wellFormedSymbolStringsPass() throws {
    #expect(try symbolStringsFailure(symbolImage(strx: [0, 1, 3], strings: Data([0, 0x61, 0, 0x62, 0]))) == nil)
}

// MARK: - Chained fixups header

/// An image with one segment and a fixups payload holding the given header.
private func chainedImage(
    datasize: UInt32 = 64, starts: UInt32 = 32, imports: UInt32 = 40, symbols: UInt32 = 44,
    format: UInt32 = 1, segCount: UInt32 = 1
) -> Data {
    let dataoff = UInt32(32 + 72 + 16)
    let segment = words([0x19, 72]) + Data(repeating: 0, count: 64)
    let command = words([0x8000_0034, 16, dataoff, datasize])
    var data = image(commands: [segment, command])
    data += words([0, starts, imports, symbols, 0, format, 0, 0, segCount, 0])
    return data + Data(repeating: 0, count: 64)
}

/// Why the chained fixups header was declined, or nil.
private func chainedFailure(_ data: Data) throws -> String? {
    try withReader(data) { reader in
        do {
            try MachOPreflight.validateChainedFixupsHeader(prefix: data, image: reader, path: "t")
            return nil
        } catch { return "\(error)" }
    }
}

@Test func aWellFormedChainedFixupsHeaderPasses() throws {
    #expect(try chainedFailure(chainedImage()) == nil)
}

@Test func chainedStartsPastThePayloadAreDeclined() throws {
    #expect(try chainedFailure(chainedImage(starts: 61))?.contains("starts") == true)
}

@Test func chainedImportsPastThePayloadAreDeclined() throws {
    #expect(try chainedFailure(chainedImage(imports: 65))?.contains("imports") == true)
}

@Test func chainedSymbolsPastThePayloadAreDeclined() throws {
    #expect(try chainedFailure(chainedImage(symbols: 65))?.contains("symbols") == true)
}

@Test func anUnknownChainedImportFormatIsDeclined() throws {
    #expect(try chainedFailure(chainedImage(format: 4))?.contains("format") == true)
    #expect(try chainedFailure(chainedImage(format: 0))?.contains("format") == true)
}

@Test func chainedSegmentsPastThePayloadAreDeclined() throws {
    #expect(try chainedFailure(chainedImage(segCount: 8))?.contains("segment(s)") == true)
}

@Test func aChainedPayloadTooShortForItsHeaderIsDeclined() throws {
    #expect(try chainedFailure(chainedImage(datasize: 27))?.contains("too short") == true)
}


import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

private struct PoolSectionRecord {
    let command: Int
    let record: Int
    let segment: String
    let name: String
    let address: UInt64
    let fileOffset: Int
}
private func poolUInt(_ data: Data, _ offset: Int, _ count: Int) -> UInt64 {
    (0..<count).reduce(0) { $0 | (UInt64(data[offset + $1]) << ($1 * 8)) }
}
private func poolWrite(_ value: UInt64, to data: inout Data, at offset: Int, bytes: Int) {
    for index in 0..<bytes { data[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
}
private func poolName(_ data: Data, _ offset: Int) -> String {
    String(decoding: data[offset..<offset + 16].prefix { $0 != 0 }, as: UTF8.self)
}
private func poolSetName(_ name: String, to data: inout Data, at offset: Int) {
    let bytes = Array(name.utf8)
    for index in 0..<16 { data[offset + index] = index < bytes.count ? bytes[index] : 0 }
}
private func poolSections(_ data: Data) -> [PoolSectionRecord] {
    var offset = 32
    var result: [PoolSectionRecord] = []
    for _ in 0..<Int(poolUInt(data, 16, 4)) {
        if poolUInt(data, offset, 4) == 0x19 {
            for index in 0..<Int(poolUInt(data, offset + 64, 4)) {
                let record = offset + 72 + index * 80
                result.append(.init(command: offset, record: record,
                    segment: poolName(data, record + 16), name: poolName(data, record),
                    address: poolUInt(data, record + 32, 8), fileOffset: Int(poolUInt(data, record + 48, 4))))
            }
        }
        offset += Int(poolUInt(data, offset + 4, 4))
    }
    return result
}

/// Deliberately mutate only metadata in a valid authored image. These copies
/// are parsed as data through MachOKit and never executed or loaded by dyld.
@Test func scalarPoolReadProofRejectsMutableRelocatedAndEncodedBytesIfPresent() async throws {
    let path = "Fixtures/Sample/libFPPools.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let original = try Data(contentsOf: URL(fileURLWithPath: path))
    let sections = poolSections(original)
    let literal = try #require(sections.first { $0.segment == "__TEXT" && $0.name == "__const" })
    let pointer = try #require(sections.first { $0.segment == "__DATA_CONST" && $0.name == "__const" })
    let mutable = try #require(sections.first { $0.segment == "__DATA" && $0.name == "__data" })
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("literal-proof-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func check(_ name: String, address: UInt64, bytes: Int = 8, mutate: (inout Data) -> Void) async throws {
        var data = original
        mutate(&data)
        let url = directory.appendingPathComponent(name + ".dylib")
        try data.write(to: url)
        try await withStableDependencies {
            guard case .machO(let image) = try MachOKit.loadFromFile(url: url) else { Issue.record("Not a thin image"); return }
            let resolver = Disassembler.ReferenceResolver(names: [:], stringRanges: [], machO: image, demangleSymbol: { _ in nil })
            #expect(resolver.literalBits(at: address, bytes: bytes) == nil, Comment(rawValue: name))
        }
    }
    try await check("mutable", address: mutable.address, mutate: { _ in })
    try await check("writable-text", address: literal.address) { data in
        poolWrite(7, to: &data, at: literal.command + 60, bytes: 4)
    }
    try await check("section-relocation", address: literal.address) { data in
        poolWrite(1, to: &data, at: literal.record + 60, bytes: 4)
    }
    try await check("zero-fill", address: literal.address) { data in
        poolWrite(1, to: &data, at: literal.record + 64, bytes: 4)
    }
    try await check("unbacked", address: literal.address) { data in
        let vm = poolUInt(data, literal.command + 24, 8)
        poolWrite(literal.address - vm, to: &data, at: literal.command + 48, bytes: 8)
    }
    try await check("overflowed-file-offset", address: literal.address) { data in
        poolWrite(.max, to: &data, at: literal.command + 40, bytes: 8)
    }
    try await check("unrepresentable-file-offset", address: literal.address) { data in
        poolWrite(UInt64(Int.max), to: &data, at: literal.command + 40, bytes: 8)
    }
    func disguisePointerSection(_ data: inout Data) {
        poolSetName("__TEXT", to: &data, at: pointer.command + 8)
        poolSetName("__TEXT", to: &data, at: pointer.record + 16)
        poolWrite(5, to: &data, at: pointer.command + 60, bytes: 4)
    }
    try await check("encoded-rebase", address: pointer.address) { disguisePointerSection(&$0) }
    try await check("inside-rebase", address: pointer.address + 6, bytes: 2) { disguisePointerSection(&$0) }
    try await check("encoded-bind", address: pointer.address + 8) { disguisePointerSection(&$0) }
    try await check("unresolved-bind", address: pointer.address + 8) { data in
        disguisePointerSection(&data)
        let word = poolUInt(data, pointer.fileOffset + 8, 8)
        #expect(word & (1 << 63) != 0) // authored arm64 ptr64 bind, ordinal in low 24 bits
        poolWrite(word | 0xffffff, to: &data, at: pointer.fileOffset + 8, bytes: 8)
    }
}

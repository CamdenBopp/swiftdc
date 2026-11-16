import Testing
import Foundation
import MachOKit
@testable import SwiftDecompilerCore

/// A code section read as a slice of the mapped file holds exactly the bytes
/// the copying read returns, for a thin file and for a slice that starts
/// past the fat header, where the file offset is the slice's own plus its
/// start.
@Test func aMappedSectionMatchesTheCopiedOneIfPresent() throws {
    let thinPath = "Fixtures/Sample/libSample.dylib"
    guard FileManager.default.fileExists(atPath: thinPath) else { return }
    let thin = try Data(contentsOf: URL(fileURLWithPath: thinPath))
    var relabelled = thin
    relabelled.replaceSubrange(8 ..< 12, with: [2, 0, 0, 0])  // arm64e: only the second slice is arm64
    let offsets: [UInt32] = [0x4000, 0x4000 + UInt32((thin.count + 0x3fff) & ~0x3fff)]
    var header = Data()
    func append32(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { header.append(contentsOf: $0) } }
    append32(0xcafe_babe)
    append32(2)
    for (subtype, offset) in zip([UInt32(2), 0], offsets) {
        append32(0x0100_000c); append32(subtype); append32(offset); append32(UInt32(thin.count)); append32(14)
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-mapped-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fatURL = directory.appendingPathComponent("fat.dylib")
    var file = header
    file.append(Data(count: Int(offsets[0]) - header.count))
    file.append(relabelled)
    file.append(Data(count: Int(offsets[1]) - file.count))
    file.append(thin)
    try file.write(to: fatURL)

    let disassembler = Disassembler()
    for (machO, path) in [(try BinaryLoader.load(path: thinPath), thinPath),
                          (try BinaryLoader.load(path: fatURL.path, architecture: "arm64"), fatURL.path)] {
        let mapped = try Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped)
        let sections = disassembler.codeSections(in: machO)
        #expect(!sections.isEmpty)
        for section in sections {
            let size = Int(section.range.upperBound - section.range.lowerBound)
            let slice = try #require(Disassembler.mappedSlice(of: mapped, address: section.range.lowerBound, size: size, in: machO))
            let copied = try #require(disassembler.sectionBytes(address: section.range.lowerBound, size: size, in: machO))
            #expect(Data(slice) == copied, "\(path) \(section.range)")
        }
    }
    #expect(try BinaryLoader.load(path: fatURL.path, architecture: "arm64").headerStartOffset == Int(offsets[1]))
}

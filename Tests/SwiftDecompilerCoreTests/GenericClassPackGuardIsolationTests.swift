import Foundation
import MachOKit
import MachOSwiftSection
import Testing
@testable import SwiftDecompilerCore

@Test func genericClassMetadataGuardRejectsInconsistentDescriptorsIfPresent() throws {
    let path = "Fixtures/Sample/libGenericClassPacks.dylib"
    guard FileManager.default.fileExists(atPath: path) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, "Build \(path) before running this test.")
        return
    }
    let source = try Data(contentsOf: URL(fileURLWithPath: path))
    let original = try BinaryLoader.load(path: path)

    func model(named name: String, in image: MachOFile) throws -> Class {
        let models = UnrecordedTypes.all(in: image).compactMap { type -> Class? in
            guard case .class(let model) = type,
                  (try? model.descriptor.name(in: image)) == name
            else { return nil }
            return model
        }
        try #require(models.count == 1)
        return try #require(models.first)
    }

    let pack = try #require(try model(named: "PackBox", in: original).genericContext)
    let plain = try #require(try model(named: "PlainBox", in: original).genericContext)
    let actualPackHeader = try #require(pack.typePackHeader)
    try #require(actualPackHeader.numPacks == 1)
    try #require(pack.valueHeader == nil && plain.valueHeader == nil)
    try #require(plain.typePackHeader == nil)
    let packParam = try #require(pack.parameters.first { $0.kind == .typePack })
    let ordinaryParam = try #require(plain.parameters.first)
    try #require(packParam.hasKeyArgument && ordinaryParam.hasKeyArgument)
    try #require(ordinaryParam.kind == .type)
    try #require(plain.header.layout.flags.rawValue == 0)
    try #require(plain.header.layout.numKeyArguments == 2)
    try #require(source.indices.contains(packParam.offset))
    try #require(source.indices.contains(ordinaryParam.offset))

    func check(_ name: String, _ data: Data, packHeader: Bool, valueHeader: Bool,
               plainKinds: Bool, allKey: Bool, unknownFlags: UInt16 = 0,
               shortKeyCount: Bool = false) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-generic-index-\(UUID()).dylib")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        // Exercise the consumer's own guard even if a separate parser preflight
        // later rejects one of these intentionally inconsistent descriptors.
        guard case .machO(let image) = try loadFromFile(url: url) else {
            Issue.record("Mutated fixture is not a thin Mach-O image")
            return
        }
        let candidate = try model(named: name, in: image)
        let generic = try #require(candidate.genericContext)
        try #require(generic.parameters.count == 2)
        try #require(generic.currentParameters.count == generic.parameters.count)
        try #require(!candidate.descriptor.hasResilientSuperclass)
        try #require((generic.typePackHeader != nil) == packHeader)
        try #require((generic.valueHeader != nil) == valueHeader)
        try #require(generic.parameters.allSatisfy { $0.kind == .type } == plainKinds)
        try #require(generic.parameters.allSatisfy { $0.hasKeyArgument } == allKey)
        try #require(generic.header.layout.flags.rawValue & 0xFFF8 == unknownFlags)
        let keyWords = Int(generic.header.layout.numKeyArguments)
        if shortKeyCount {
            try #require(keyWords == generic.parameters.count - 1)
        } else {
            try #require(keyWords >= generic.parameters.count)
        }

        let first = Int(candidate.descriptor.nonResilientImmediateMembersOffset) * 8
        #expect(VTableIndex.build(in: image).genericParameter(type: name, offset: first) == nil)
    }

    // Clear only the encoded pack parameter kind. The valid shape trailer
    // survives, so parameter kinds and key flags alone would admit this map.
    var packHeaderOnly = source
    packHeaderOnly[packParam.offset] &= 0xC0
    try check("PackBox", packHeaderOnly, packHeader: true, valueHeader: false, plainKinds: true, allKey: true)

    // Replace the pack trailer with a same-sized value trailer: a 4-byte
    // count followed by two 4-byte Int descriptors. Keep both parameter
    // kinds plain so the value-header premise is the only failed premise.
    var valueHeaderOnly = packHeaderOnly
    let flags = pack.header.offset + 14  // Two relative pointers, then three UInt16 counts.
    let trailer = actualPackHeader.offset
    try #require(flags >= 0 && flags + 1 < source.count)
    try #require(source[flags] & 0b101 == 0b001)
    try #require(trailer >= 0 && trailer + 12 <= source.count)
    valueHeaderOnly[flags] = (source[flags] & 0b1111_1010) | 0b100
    valueHeaderOnly.replaceSubrange(trailer ..< trailer + 12, with: [UInt8(2)] + Array(repeating: 0, count: 11))
    try check("PackBox", valueHeaderOnly, packHeader: false, valueHeader: true, plainKinds: true, allKey: true)

    // An unrecognized parameter kind remains a key argument in the decoded
    // descriptor and must not bypass the check merely because headers are absent.
    var unknownKindOnly = source
    unknownKindOnly[ordinaryParam.offset] = (source[ordinaryParam.offset] & 0xC0) | 3
    try check("PlainBox", unknownKindOnly, packHeader: false, valueHeader: false, plainKinds: false, allKey: true)

    // Retain the existing key-argument check as an independent premise.
    var missingKeyOnly = source
    missingKeyOnly[ordinaryParam.offset] &= 0x7F
    try check("PlainBox", missingKeyOnly, packHeader: false, valueHeader: false, plainKinds: true, allKey: false)

    // The header begins with two relative pointers followed by UInt16 counts
    // and flags. PlainBox has two plain key types and no trailing feature.
    let keyCount = plain.header.offset + 12
    let plainFlags = plain.header.offset + 14
    try #require(keyCount >= 0 && plainFlags + 1 < source.count)
    try #require(Array(source[keyCount ..< plainFlags + 2]) == [2, 0, 0, 0])

    // Exercise an unrecognized flag in the high byte of the UInt16 field.
    var unknownHeaderOnly = source
    unknownHeaderOnly[plainFlags + 1] = 1
    try check("PlainBox", unknownHeaderOnly, packHeader: false, valueHeader: false,
              plainKinds: true, allKey: true, unknownFlags: 0x0100)

    // Keep both key bits set while making the declared key area too short.
    var shortKeyCountOnly = source
    shortKeyCountOnly[keyCount] = 1
    try check("PlainBox", shortKeyCountOnly, packHeader: false, valueHeader: false,
              plainKinds: true, allKey: true, shortKeyCount: true)
}

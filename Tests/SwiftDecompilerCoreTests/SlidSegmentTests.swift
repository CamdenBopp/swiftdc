import Testing
import Foundation
@testable import SwiftDecompilerCore

// Segments that lie at a different offset in memory than in the file
// (`Fixtures/Sample/slidsegments.swift`, `slidsegments_c.c`). Zero fill at
// the end of __DATA moves every later segment's addresses 0x870000 past its
// file bytes. The Mach-O readers underneath resolve fixup chains and
// relative pointers by file offset, so on such a segment they trap or read
// unrelated bytes: the image is declined, by that cause.

private let executable = "Fixtures/Sample/slidsegments"
// No .dylib suffix: the tests that walk every fixture dylib load images
// the preflight declines, and MachOKit traps on this one.
private let cLibrary = "Fixtures/Sample/slidsegments_c"

private func misread(_ path: String) throws -> [String]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let handle = try #require(FileHandle(forReadingAtPath: path))
    defer { try? handle.close() }
    let image = MachOPreflight.ImageReader(handle: handle, base: 0, size: data.count)
    return MachOPreflight.misreadSegments(prefix: data, image: image).map(\.name)
}

/// Every entry point declines the executable with the layout as its cause,
/// as an error exit. Before, every one exited 1 calling it malformed
/// (preflight read `__swift5_fieldmd`'s VM displacements as file
/// displacements), and with that check fixed every one trapped in MachOKit's
/// chained-fixup reader (`try!` past the end of the file).
@Test func everyEntryPointDeclinesSlidSegmentsIfPresent() throws {
    let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
    guard FileManager.default.fileExists(atPath: binary.path),
          FileManager.default.fileExists(atPath: executable) else { return }
    let commands: [[String]] = [
        ["disasm", "--structured"], ["dump"], ["layout"], ["interface"], ["objc"],
        ["xrefs", "--unreferenced"], ["analyze"],
    ]
    for command in commands {
        let out = Pipe(), err = Pipe()
        let process = Process()
        process.executableURL = binary
        process.arguments = command + [executable]
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let drained = Shell.drain(out, err)
        let stdout = String(decoding: drained.out, as: UTF8.self)
        let stderr = String(decoding: drained.err, as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationReason == .exit, "\(command): killed by signal \(process.terminationStatus)\n\(stderr)")
        #expect(process.terminationStatus == 1, "\(command): exit \(process.terminationStatus)\n\(stderr)")
        #expect(stderr.contains("Unsupported Mach-O layout"), "\(command): \(stderr)")
        #expect(stderr.contains("__DATA_DIRTY (VM offset 0x87c000, file offset 0xc000)"), "\(command): \(stderr)")
        #expect(!stderr.contains("Malformed"), "\(command): \(stderr)")
        #expect(stdout.isEmpty, "\(command): \(stdout)")
    }
}

/// A slid segment counts by either cause: fixup chains (__DATA_DIRTY) or a
/// metadata section with only relative pointers in it (__SWIFT_FIELDS).
@Test func slidSegmentsCountByChainsOrMetadataIfPresent() throws {
    guard let names = try misread(executable) else { return }
    #expect(names == ["__DATA_DIRTY", "__SWIFT_FIELDS"])
}

/// In a C library, a slid segment with fixup chains counts, though it holds
/// no metadata; a slid segment of raw bytes that nothing fixes up or reaches
/// by relative pointer (`__FONT_DATA`, as NanoTimeKit has) does not.
@Test func slidSegmentCountsOnlyWithChainsOrMetadataIfPresent() throws {
    guard let names = try misread(cLibrary) else { return }
    #expect(names == ["__DATA_DIRTY"])
}

/// The usual layout keeps one slide, zero fill at the end of __DATA
/// included (`__bss` and `__common` in sample.release): only __LINKEDIT
/// moves, and nothing counts.
@Test func ordinaryLayoutsHaveNoMisreadSegmentsIfPresent() throws {
    for path in [
        "Fixtures/Sample/sample.release", "Fixtures/Sample/libSample.dylib",
        "Fixtures/Sample/libRuntimeIvars.dylib", "Fixtures/Sample/libReconstruction.opt.dylib",
    ] {
        guard let names = try misread(path) else { continue }
        #expect(names.isEmpty, "\(path): \(names)")
    }
}

// MARK: - Relative pointers map through VM addresses

private struct Image {
    let data: Data
    let map: FileBackedRanges
    let sections: [(segment: Int, name: String, addr: UInt64, offset: Int, size: Int)]

    init?(_ path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        data = try Data(contentsOf: URL(fileURLWithPath: path))
        map = FileBackedRanges(segments: try #require(MachOPreflight.segmentTable(prefix: data)))
        sections = try #require(MachOPreflight.sectionTable(prefix: data)).sections
    }

    func section(_ name: String) throws -> (segment: Int, name: String, addr: UInt64, offset: Int, size: Int) {
        try #require(sections.first { $0.name == name }, "\(name)")
    }

    func int32(at offset: Int) throws -> Int64 {
        Int64(Int32(bitPattern: try #require(data.u32(at: offset))))
    }

    /// Empty at an offset outside the file, so a wrong target fails a test
    /// instead of trapping the test process.
    func string(at offset: Int) -> String {
        guard data.indices.contains(offset) else { return "" }
        return String(decoding: data[offset...].prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// `__swift5_fieldmd` sits in __SWIFT_FIELDS, its names in __TEXT: every
/// field name is a negative displacement crossing the 0x870000 gap. Mapped
/// through VM it reads the source's field names. `place + delta` is a
/// negative file offset.
@Test func aFieldNameOutOfASlidSegmentReadsFromTextIfPresent() throws {
    guard let image = try Image(executable) else { return }
    let fields = try image.section("__swift5_fieldmd")
    var names: Set<String> = []
    var cursor = fields.offset
    while cursor < fields.offset + fields.size {
        let count = Int(try #require(image.data.u32(at: cursor + 12)))
        for field in 0..<count {
            let place = cursor + 16 + field * 12 + 8
            let delta = try image.int32(at: place)
            #expect(delta < 0)
            #expect(place + Int(delta) < 0, "the naive offset must be wrong for this test to prove anything")
            guard case .file(let offset, _) = image.map.relativeTarget(fromFileOffset: place, displacement: delta)
            else { Issue.record("field \(field) at \(place) has no file bytes"); continue }
            names.insert(image.string(at: offset))
        }
        cursor += 16 + count * 12
    }
    #expect(names.isSuperset(of: ["first", "second", "w", "h", "name", "count", "label"]), "\(names.sorted())")
}

/// The method lists sit in __TEXT, the selector references in __DATA_DIRTY:
/// a positive displacement into the slid segment, to a slot whose rebase
/// names the selector.
@Test func aSelectorReferenceInASlidSegmentIsFoundIfPresent() throws {
    guard let image = try Image(executable) else { return }
    let lists = try image.section("__objc_methlist")
    let selrefs = try image.section("__objc_selrefs")
    let methname = try image.section("__objc_methname")
    var selectors: Set<String> = []
    var cursor = lists.offset
    while cursor + 8 <= lists.offset + lists.size {
        let header = try #require(image.data.u32(at: cursor))
        if header == 0 { cursor += 4; continue }
        let count = Int(try #require(image.data.u32(at: cursor + 4)))
        for method in 0..<count {
            let place = cursor + 8 + method * 12
            let delta = try image.int32(at: place)
            #expect(delta > 0)
            #expect(place + Int(delta) >= image.data.count, "the naive offset must be wrong for this test to prove anything")
            guard case .file(let slot, _) = image.map.relativeTarget(fromFileOffset: place, displacement: delta)
            else { Issue.record("method \(method) at \(place) has no file bytes"); continue }
            #expect((selrefs.offset ..< selrefs.offset + selrefs.size).contains(slot))
            // DYLD_CHAINED_PTR_64(_OFFSET): the rebase target is the low 36 bits.
            let raw = try #require(image.data.u64(at: slot))
            let target = raw & (1 << 36 - 1)
            let offset = Int(target >= image.map.base ? target - image.map.base : target)
            #expect((methname.offset ..< methname.offset + methname.size).contains(offset))
            selectors.insert(image.string(at: offset))
        }
        cursor += 8 + count * 12
    }
    #expect(selectors.contains("ping:"), "\(selectors.sorted())")
}

/// `Bridged`'s superclass is an indirect symbolic reference (`\x02` + rel32)
/// in __TEXT: the displacement leads to a pointer slot in __DATA_DIRTY,__got,
/// and the slot is the bind. The relative step and the slot both map through
/// VM.
@Test func anIndirectReferenceReachesItsSlotInASlidSegmentIfPresent() throws {
    guard let image = try Image(executable) else { return }
    let typeref = try image.section("__swift5_typeref")
    let got = try image.section("__got")
    var slots = 0
    for marker in typeref.offset ..< typeref.offset + typeref.size - 5 where image.data[marker] == 0x02 {
        let place = marker + 1
        let delta = try image.int32(at: place)
        guard case .file(let slot, let available) = image.map.relativeTarget(fromFileOffset: place, displacement: delta),
              (got.offset ..< got.offset + got.size).contains(slot)
        else { continue }
        #expect(place + Int(delta) >= image.data.count, "the naive offset must be wrong for this test to prove anything")
        #expect(available >= 8)
        // Bit 63 of a chained pointer: a bind, the slot `dyld_info -fixups`
        // lists as _OBJC_CLASS_$_NSObject.
        let raw = try #require(image.data.u64(at: slot))
        #expect(raw >> 63 == 1)
        slots += 1
    }
    #expect(slots >= 1)
}

/// __DATA's vmsize exceeds its filesize by the zero fill. An address in the
/// zero-fill section reads no file bytes, both inside the last file page
/// (only the section's type says so) and past the file bytes (only the
/// segment does). An address no segment maps is unmapped.
@Test func zeroFillHasNoFileBytesIfPresent() throws {
    guard let image = try Image(executable) else { return }
    let segments = try #require(MachOPreflight.segmentTable(prefix: image.data))
    let data = try #require(segments.first { $0.name == "__DATA" })
    let zero = try image.section("__bigzero")
    #expect(data.vmsize > data.filesize)
    #expect(zero.addr < data.vmaddr + data.filesize, "the section starts inside the last file page")
    #expect(image.map.target(at: zero.addr) == .zeroFill)
    #expect(image.map.target(at: data.vmaddr + data.filesize) == .zeroFill)
    #expect(image.map.target(at: data.vmaddr + data.vmsize - 1) == .zeroFill)
    if case .file(let offset, _) = image.map.target(at: zero.addr - 1) {
        #expect(offset == Int(data.fileoff) + Int(zero.addr - 1 - data.vmaddr))
    } else {
        Issue.record("the byte before the zero fill is file-backed")
    }
    let last = try #require(segments.last)
    #expect(image.map.target(at: last.vmaddr + last.vmsize) == .unmapped)

    // A relative pointer into it, from __DATA, says so.
    let place = Int(data.fileoff)
    let displacement = Int64(zero.addr - data.vmaddr)
    #expect(image.map.relativeTarget(fromFileOffset: place, displacement: displacement) == .zeroFill)
    let (offset, reason) = MachOPreflight.relativeFileOffset(UInt32(displacement), at: place, in: image.map)
    #expect(offset == nil)
    #expect(reason.contains("zero fill"), "\(reason)")
}

/// The preflight's record tables on the real image: `__swift5_fieldmd`'s
/// VM displacements resolve through the segments, to names in
/// `__swift5_typeref`. Read as file displacements they lead below the file,
/// which called a valid image malformed.
@Test func recordTablesResolveThroughSegmentsIfPresent() throws {
    guard let image = try Image(executable) else { return }
    let handle = try #require(FileHandle(forReadingAtPath: executable))
    defer { try? handle.close() }
    let reader = MachOPreflight.ImageReader(handle: handle, base: 0, size: image.data.count)
    let names = try MachOPreflight.validateRelativeTables(
        prefix: image.data, image: reader, map: image.map, path: executable
    )
    let typeref = try image.section("__swift5_typeref")
    #expect(names.contains { (typeref.offset ..< typeref.offset + typeref.size).contains($0) })
    #expect(throws: (any Error).self) {
        try MachOPreflight.validateRelativeTables(
            prefix: image.data, image: reader, map: FileBackedRanges(identityOver: image.data.count), path: executable
        )
    }
}

/// A corrupt pointer into zero fill used to pass while its file offset was
/// inside the file, and the dependency then read whatever bytes lay there.
/// The whole-image preflight now refuses it by cause.
@Test func aRecordPointerIntoZeroFillIsRefusedIfPresent() throws {
    let path = "Fixtures/Sample/sample.release"
    guard let image = try Image(path) else { return }
    let fields = try image.section("__swift5_fieldmd")
    let bss = try image.section("__bss")
    var data = image.data
    let displacement = Int32(Int64(bss.addr) - Int64(fields.addr))
    withUnsafeBytes(of: displacement.littleEndian) { data.replaceSubrange(fields.offset ..< fields.offset + 4, with: $0) }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-zerofill-\(UUID().uuidString)")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    do {
        try MachOPreflight.validate(url: url)
        Issue.record("a type name in zero fill passed the preflight")
    } catch {
        #expect("\(error)".contains("zero fill"), "\(error)")
    }
}

/// Two segments at different slides, hand-built: __TEXT at VM = file, then
/// a segment 0x100000 up in memory and straight after __TEXT in the file.
private let slid = FileBackedRanges(segments: [
    .init(name: "__TEXT", vmaddr: 0, vmsize: 0x4000, fileoff: 0, filesize: 0x4000, sections: []),
    .init(name: "__SLID", vmaddr: 0x10_0000, vmsize: 0x4000, fileoff: 0x4000, filesize: 0x4000, sections: []),
])

private func word(_ value: Int64) -> [UInt8] {
    withUnsafeBytes(of: Int32(value).littleEndian) { Array($0) }
}

/// The displacement from `field` bytes into __SLID back to 0x1000 in __TEXT.
private func back(_ field: Int64) -> [UInt8] { word(0x1000 - (0x10_0000 + field)) }

// Each record table read from a slid section, with a negative displacement
// across the gap: the target is 0x1000 in __TEXT. File arithmetic lands at a
// negative offset and rejects it.

@Test func anAssociatedTypeTableMapsAcrossSegments() throws {
    let table = Data(back(0) + back(4) + [0, 0, 0, 0] + [8, 0, 0, 0])
    #expect(try MachOPreflight.validateAssociatedTypeTable(
        bytes: table, sectionOffset: 0x4000, fileSize: 0x8000, map: slid) == [0x1000, 0x1000])
}

@Test func aBuiltinTypeTableMapsAcrossSegments() throws {
    let table = Data(back(0) + [UInt8](repeating: 0, count: 16))
    #expect(try MachOPreflight.validateBuiltinTypeTable(
        bytes: table, sectionOffset: 0x4000, fileSize: 0x8000, map: slid) == [0x1000])
}

@Test func aMultiPayloadEnumTableMapsAcrossSegments() throws {
    let table = Data(back(0) + [0, 0, 1, 0])
    #expect(try MachOPreflight.validateMultiPayloadEnumTable(
        bytes: table, sectionOffset: 0x4000, fileSize: 0x8000, map: slid) == [0x1000])
}

@Test func aFieldDescriptorTableMapsAcrossSegments() throws {
    let table = Data(back(0) + back(4) + [0, 0, 12, 0] + [0, 0, 0, 0])
    #expect(try MachOPreflight.validateFieldDescriptorTable(
        bytes: table, sectionOffset: 0x4000, fileSize: 0x8000, map: slid) == [0x1000, 0x1000])
}

@Test func aFlatRelativeTableMapsAcrossSegments() throws {
    try MachOPreflight.validateRelativePointerTable(
        bytes: Data(back(0)), sectionOffset: 0x4000, fileSize: 0x8000, name: "__swift5_types", map: slid)
}

/// A relative method list in a slid section: the name is a selector
/// reference beside it, and the type encoding and IMP point back to __TEXT.
@Test func aMethodListMapsItsTypesAndImplementationAcrossSegments() throws {
    let list = Data([12, 0, 0, 0x80] + [1, 0, 0, 0] + word(0x100 - 8) + back(12) + back(16))
    try MachOPreflight.validateObjCMethodLists(
        bytes: list, sectionAddress: 0x10_0000, selrefs: (0x10_0100, 8),
        sectionOffset: 0x4000, fileSize: 0x8000, map: slid
    )
}

/// A target past either end of the address space is unmapped, never the
/// segment the arithmetic wraps to.
@Test func aDisplacementPastTheAddressSpaceIsUnmapped() {
    let top: UInt64 = 0xffff_ffff_ffff_0000
    let map = FileBackedRanges(segments: [
        .init(name: "__TEXT", vmaddr: 0, vmsize: 0x1000, fileoff: 0, filesize: 0x1000, sections: []),
        .init(name: "__TOP", vmaddr: top, vmsize: 0xf000, fileoff: 0x1000, filesize: 0xf000, sections: []),
    ])
    #expect(map.relativeTarget(fromFileOffset: 0x10, displacement: -0x2000) == .unmapped)
    #expect(map.relativeTarget(fromFileOffset: 0x1000 + 0xe000, displacement: 0x2100) == .unmapped)
    // The same arithmetic inside the space resolves.
    #expect(map.relativeTarget(fromFileOffset: 0x10, displacement: 0x10) == .file(offset: 0x20, available: 0xfe0))
}

/// Two segments claiming one file byte or one address: which is meant is
/// unknown, so nothing is claimed.
@Test func overlappingSegmentsClaimNothing() {
    let map = FileBackedRanges(segments: [
        .init(name: "A", vmaddr: 0x1000, vmsize: 0x1000, fileoff: 0, filesize: 0x1000, sections: []),
        .init(name: "B", vmaddr: 0x8000, vmsize: 0x1000, fileoff: 0x800, filesize: 0x1000, sections: []),
        .init(name: "C", vmaddr: 0x8800, vmsize: 0x1000, fileoff: 0x4000, filesize: 0x1000, sections: []),
    ])
    #expect(map.address(ofFileOffset: 0x10) == 0x1010)
    #expect(map.address(ofFileOffset: 0x900) == nil)
    #expect(map.target(at: 0x8100) == .file(offset: 0x900, available: 0xf00))
    #expect(map.target(at: 0x8900) == .unmapped)
}

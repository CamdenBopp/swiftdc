import Testing
import Foundation
import MachOKit
import MachOFoundation
import MachOObjCSection
@testable import SwiftDecompilerCore

// Segments that lie at a different offset in memory than in the file
// (`Fixtures/Sample/slidsegments.swift`, `slidsegments_c.c`). Zero fill at
// the end of __DATA moves every later segment's addresses 0x870000 past its
// file bytes. Fixup chains and relative pointers count in memory, so each is
// found through its own segment. The `_flat` twins are the same objects
// linked the same way without the zero fill: what the slide changes in a
// render is addresses and nothing else.

private let executable = "Fixtures/Sample/slidsegments"
private let cLibrary = "Fixtures/Sample/slidsegments_c"
private let flatExecutable = "Fixtures/Sample/slidsegments_flat"
private let flatCLibrary = "Fixtures/Sample/slidsegments_c_flat"
private let strippedExecutable = "Fixtures/Sample/slidsegments_stripped"
private let flatStrippedExecutable = "Fixtures/Sample/slidsegments_flat_stripped"

private func misread(_ data: Data, at path: String) throws -> [String] {
    let handle = try #require(FileHandle(forReadingAtPath: path))
    defer { try? handle.close() }
    let image = MachOPreflight.ImageReader(handle: handle, base: 0, size: data.count)
    return MachOPreflight.misreadSegments(prefix: data, image: image).map(\.name)
}

private func misread(_ path: String) throws -> [String]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    return try misread(try Data(contentsOf: URL(fileURLWithPath: path)), at: path)
}

private let binary = URL(fileURLWithPath: ".build/debug/swiftdc")

private func run(_ executable: URL, _ arguments: [String]) throws -> (stdout: String, stderr: String, process: Process) {
    let out = Pipe(), err = Pipe()
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = out
    process.standardError = err
    try process.run()
    // Both pipes at once: a render larger than either buffer would block.
    let drained = Shell.drain(out, err)
    process.waitUntilExit()
    return (String(decoding: drained.out, as: UTF8.self), String(decoding: drained.err, as: UTF8.self), process)
}

private let views: [[String]] = [
    ["interface"], ["dump"], ["objc"], ["layout"], ["analyze"], ["xrefs", "--unreferenced"],
    ["disasm", "--structured"], ["disasm", "--pseudo"], ["disasm"],
]

/// Every view reads the executable, each with what the source says it holds:
/// names read through relative pointers both ways, a superclass through an
/// indirect reference, a selector through a slid reference. Before, each one
/// declined the image, and before that trapped in MachOKit (`try!` past the
/// end of the file) or called it malformed.
@Test func everyEntryPointReadsSlidSegmentsIfPresent() throws {
    guard FileManager.default.fileExists(atPath: binary.path),
          FileManager.default.fileExists(atPath: executable) else { return }
    let expected: [String: [String]] = [
        "interface": ["var first: Swift.Int", "var second: Swift.String", "class Bridged: __C.NSObject",
                      "class Derived: SlidSegments.Base", "extension SlidSegments.Rect: SlidSegments.Shape"],
        "dump": ["var first: Swift.Int", "func SlidSegments.Base.greet() -> Swift.String"],
        "objc": ["@interface _TtC12SlidSegments4Base : _TtCs12_SwiftObject",
                 "@interface _TtC12SlidSegments7Bridged : NSObject", "- (long long)ping:(long long)arg0;"],
        "layout": ["+0x0    8B  first: Si", "+0x8    16B  second: SS", "+0x20   8B  count: Si"],
        "disasm": ["-[_TtC12SlidSegments7Bridged ping:]", "literal pool symbol address: ___chkstk_darwin"],
    ]
    for view in views {
        let result = try run(binary, view + [executable])
        #expect(result.process.terminationReason == .exit, "\(view): killed by signal \(result.process.terminationStatus)")
        #expect(result.process.terminationStatus == 0, "\(view): \(result.stderr)")
        #expect(result.stderr.isEmpty, "\(view): \(result.stderr)")
        #expect(!result.stdout.isEmpty, "\(view)")
        if view.count == 1 || view[0] != "disasm" {
            for text in expected[view[0]] ?? [] {
                #expect(result.stdout.contains(text), "\(view): no \(text)")
            }
        }
    }
}

/// What differs between two images linked alike is where things are.
private func addressesMasked(_ text: String) -> String {
    var text = text
    for (pattern, replacement) in [
        (#"0x[0-9a-fA-F]+"#, "0xN"), (#"\b(sub|loc)_[0-9a-fA-F]+"#, "L_N"),
        (#"(?m)^(\s*)[0-9a-f]+:"#, "$1ADDR:"), (#"(adrp\s+x\d+, )-?\d+"#, "$1PAGE"),
    ] {
        text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
    return text
}

/// The slid image renders line for line as its flat twin. The twin keeps one
/// slide, so nothing in its reading depends on the mapping: any relative
/// pointer, rebase or bind the slide misleads shows up here as a changed line.
@Test func slidSegmentsRenderAsTheirFlatTwinsIfPresent() throws {
    guard FileManager.default.fileExists(atPath: binary.path) else { return }
    // Stripped, names can only come from metadata, so a pointer the slide
    // misleads loses one instead of being covered by the symbol table.
    for (slid, flat) in [
        (executable, flatExecutable), (cLibrary, flatCLibrary), (strippedExecutable, flatStrippedExecutable),
    ] {
        guard FileManager.default.fileExists(atPath: slid), FileManager.default.fileExists(atPath: flat) else { continue }
        for view in views {
            let a = addressesMasked(try run(binary, view + [slid]).stdout).components(separatedBy: "\n")
            let b = addressesMasked(try run(binary, view + [flat]).stdout).components(separatedBy: "\n")
            #expect(!a.isEmpty && a.count == b.count, "\(slid) \(view): \(a.count) lines against \(b.count)")
            let changed = zip(a, b).filter { $0 != $1 }
            #expect(changed.isEmpty, "\(slid) \(view): \(changed.prefix(5))")
        }
    }
}

/// Every fixup `dyld_info` reports, independently of MachOKit, is found at
/// its slot: a rebase with dyld's target, a bind with dyld's symbol. Chains
/// read at the VM offset find none of the slid segment's slots.
@Test func everyFixupMatchesDyldInfoIfPresent() throws {
    for path in [executable, cLibrary] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let report = try run(URL(fileURLWithPath: "/usr/bin/xcrun"), ["dyld_info", "-fixups", path]).stdout
        let machO = try BinaryLoader.load(path: path)
        let base = try #require(machO.preferredLoadAddress)
        let table = Disassembler.ChainedFixupTable()
        let rebases = table.allRebases(in: machO)
        var seen = 0, slid = 0
        for line in report.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 5, fields[2].hasPrefix("0x"), let address = UInt64(fields[2].dropFirst(2), radix: 16)
            else { continue }
            seen += 1
            if fields[0] == "__DATA_DIRTY" { slid += 1 }
            let slot = try #require(machO.fileOffset(of: address), "\(line)")
            if fields[3] == "rebase", let target = UInt64(fields[4].dropFirst(2), radix: 16) {
                #expect(rebases[slot].map { base &+ $0 } == target, "\(line)")
            } else if fields[3] == "bind" {
                let name = fields[4].split(separator: "/").last.map(String.init)
                #expect(table.symbol(at: slot, in: machO) == name, "\(line)")
            }
        }
        #expect(seen > 0 && slid > 0, "\(path): \(seen) fixups, \(slid) slid")
    }
}

/// A rebase target counts from the load address. In an executable that puts
/// it inside __PAGEZERO, where it used to read as its own file offset: right
/// only while the target keeps __TEXT's slide. Here it lies in __DATA_DIRTY.
@Test func aRuntimeOffsetFindsItsSegmentIfPresent() throws {
    guard FileManager.default.fileExists(atPath: executable) else { return }
    let machO = try BinaryLoader.load(path: executable)
    let dirty = try #require(machO.segments.first { $0.segmentName == "__DATA_DIRTY" })
    let base = try #require(machO.preferredLoadAddress)
    let runtime = UInt64(dirty.virtualMemoryAddress) - base
    #expect(runtime != UInt64(dirty.fileOffset))
    #expect(machO.fileOffset(of: runtime) == UInt64(dirty.fileOffset))
    #expect(machO.fileOffset(of: UInt64(dirty.virtualMemoryAddress)) == UInt64(dirty.fileOffset))
    #expect(machO.imageAddress(ofOffset: dirty.fileOffset) == UInt64(dirty.virtualMemoryAddress))
    #expect(machO.imageOffset(ofAddress: UInt64(dirty.virtualMemoryAddress)) == dirty.fileOffset)
    #expect(machO.address(forOffset: dirty.fileOffset) == UInt64(dirty.virtualMemoryAddress))
}

/// A relative pointer into zero fill leads to no bytes, by every road in:
/// the file holds nothing there, and the offset it would have had belongs to
/// the slid segment stored after __DATA.
@Test func aPointerIntoZeroFillReadsNothingIfPresent() throws {
    guard FileManager.default.fileExists(atPath: executable) else { return }
    let machO = try BinaryLoader.load(path: executable)
    let data = try #require(machO.segments.first { $0.segmentName == "__DATA" })
    let start = UInt64(data.virtualMemoryAddress)
    let past = start + UInt64(data.fileSize) + 0x100
    let delta = Int(past - start)

    #expect(machO.relativeOffset(fromOffset: data.fileOffset, displacement: delta) == nil)
    #expect(machO.relativeAddress(fromOffset: data.fileOffset, displacement: delta) == past)
    #expect(machO.imageOffset(ofAddress: past) == nil)
    #expect(machO.fileOffset(of: past) == nil)

    // Inside the last file page, only the section's type says so.
    let zero = try #require(machO.sections.first { $0.sectionName == "__bigzero" })
    #expect(UInt64(zero.address) < start + UInt64(data.fileSize))
    #expect(machO.relativeOffset(fromOffset: data.fileOffset, displacement: Int(UInt64(zero.address) - start)) == nil)

    let context = machO.context
    let advanced = context.advanceAddress(data.fileOffset, by: delta)
    #expect(throws: (any Error).self) { try context.checkedAddress(advanced) }
    #expect(throws: (any Error).self) { let _: UInt8 = try context.readElement(at: advanced) }
    #expect(throws: (any Error).self) { try context.readString(at: advanced) }
    let resolved = context.addressFromVirtualAddress(past)
    #expect(throws: (any Error).self) { try context.readString(at: resolved) }
    #expect(throws: (any Error).self) {
        try RelativeDirectRawPointer(relativeOffset: Int32(delta)).resolveDirectAddress(at: data.fileOffset, in: context)
    }
    #expect(RelativeDirectRawPointer(relativeOffset: Int32(delta))
        .resolveDirectOffset(from: data.fileOffset, in: context) == nil)
}

/// Out of every segment is the same: a defined nothing, not `offset + delta`.
@Test func aPointerPastEverySegmentReadsNothingIfPresent() throws {
    guard FileManager.default.fileExists(atPath: executable) else { return }
    let machO = try BinaryLoader.load(path: executable)
    let text = try #require(machO.segments.first { $0.segmentName == "__TEXT" })
    #expect(machO.relativeOffset(fromOffset: text.fileOffset, displacement: -0x1000) == nil)
    #expect(machO.relativeOffset(fromOffset: text.fileOffset, displacement: Int.max) == nil)
    #expect(machO.relativeAddress(fromOffset: text.fileOffset, displacement: -0x2_0000_0000) == nil)
    #expect(machO.imageAddress(ofOffset: -1) == nil)
    #expect(machO.imageAddress(ofOffset: 1 << 40) == nil)
}

/// The dependency's map, which reads the parsed image, and the preflight's,
/// which reads the load commands before anything has parsed them, answer alike.
@Test func theTwoSegmentMapsAgreeIfPresent() throws {
    for path in [executable, cLibrary, "Fixtures/Sample/sample.release", "Fixtures/Sample/libSample.dylib"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let preflight = FileBackedRanges(segments: try #require(MachOPreflight.segmentTable(prefix: data)))
        let machO = try BinaryLoader.load(path: path)
        for section in machO.sections {
            for address in [UInt64(section.address), UInt64(section.address) + UInt64(section.size) - 1] {
                let offset: Int?
                if case .file(let found, _) = preflight.target(at: address) { offset = found } else { offset = nil }
                #expect(machO.imageOffset(ofAddress: address) == offset, "\(path) \(section.sectionName)")
                if let offset {
                    #expect(machO.imageAddress(ofOffset: offset) == preflight.address(ofFileOffset: offset))
                }
            }
        }
    }
}

/// A generic class's key witness table: the requirement's descriptor lies in
/// __SWIFT_FIELDS and its subject's name, `x`, in __TEXT. Read at
/// `offset + delta`, the name is not `x` and the table is declined.
@Test func aKeyWitnessTableReadsItsSubjectAcrossSegmentsIfPresent() throws {
    guard FileManager.default.fileExists(atPath: executable) else { return }
    let index = VTableIndex.build(in: try BinaryLoader.load(path: executable))
    let tables = stride(from: 0, to: 0x400, by: 8).compactMap { index.witnessTable(type: "Box", offset: $0) }
    #expect(tables.map(\.parameter) == ["A"])
}

/// Where a name lands, counted from `__text`: the two images' code is the
/// same bytes, and only where it starts differs.
private func fromText(_ address: UInt64, in machO: MachOFile) throws -> UInt64 {
    let text = try #require(machO.sections.first { $0.sectionName == "__text" })
    return address &- UInt64(text.address)
}

/// Metadata names every function the flat twin's does, at the same code. The
/// descriptors lie in __SWIFT_FIELDS and the code in __TEXT, so each accessor
/// and vtable implementation pointer crosses the slide. The disassembly can't
/// show this: a public type's symbols name those functions first.
@Test func metadataNamesTheSameFunctionsAsTheFlatTwinIfPresent() throws {
    guard FileManager.default.fileExists(atPath: executable), FileManager.default.fileExists(atPath: flatExecutable)
    else { return }
    func names(_ path: String) throws -> [String] {
        let machO = try BinaryLoader.load(path: path)
        return try MetadataSymbolizer().functionNames(in: machO).unique
            .map { "\(try fromText($0.key, in: machO)) \($0.value)" }.sorted()
    }
    let slid = try names(executable), flat = try names(flatExecutable)
    #expect(slid.contains { $0.hasSuffix("type metadata accessor for SlidSegments.Pair") }, "\(slid.prefix(6))")
    #expect(slid == flat)
}

/// Each method binds its `self` as in the flat twin, an async method's
/// through its function pointer record, which lies in __SWIFT_FIELDS.
@Test func selfTypesBindAsInTheFlatTwinIfPresent() throws {
    guard FileManager.default.fileExists(atPath: executable), FileManager.default.fileExists(atPath: flatExecutable)
    else { return }
    func bindings(_ path: String) throws -> [String] {
        let machO = try BinaryLoader.load(path: path)
        return try SelfTypeIndex.build(in: machO).all
            .map { "\(try fromText($0.address, in: machO)) \($0.binding.selfTypeName) \($0.binding.kind)" }.sorted()
    }
    let slid = try bindings(executable), flat = try bindings(flatExecutable)
    #expect(!slid.isEmpty)
    #expect(slid == flat)
}

/// The record itself: an async method's slot leads to data, and reading that
/// data at its VM offset rather than its file offset finds no function.
@Test func anAsyncRecordInASlidSegmentLeadsToItsCodeIfPresent() throws {
    guard FileManager.default.fileExists(atPath: executable) else { return }
    let machO = try BinaryLoader.load(path: executable)
    let record = try #require(machO.symbols.first { $0.name.hasSuffix("4BaseC5lateryS2iYaFTu") })
    let segment = try #require(machO.segments.first {
        $0.virtualMemoryAddress <= record.offset && record.offset < $0.virtualMemoryAddress + $0.virtualMemorySize
    })
    #expect(segment.segmentName == "__SWIFT_FIELDS", "the record lies in \(segment.segmentName)")
    let code = MethodImplementation(machO).code(at: UInt64(record.offset), isData: true)
    let function = try #require(machO.symbols.first { $0.name.hasSuffix("4BaseC5lateryS2iYaF") })
    #expect(code == UInt64(function.offset))
}

/// A symbol in zero fill is not filed under the offset it would have had,
/// which names bytes stored after the segment.
@Test func aZeroFillSymbolIsFiledAtNoFileOffsetIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: executable) else { return }
    let machO = try BinaryLoader.load(path: executable)
    let data = try #require(machO.segments.first { $0.segmentName == "__DATA" })
    let tail = try #require(machO.symbols.first { $0.name == "_$s12SlidSegments4TailCMI" })
    let inSegment = tail.offset - data.virtualMemoryAddress
    #expect(inSegment >= 0 && inSegment >= data.fileSize, "the symbol lies past __DATA's file bytes")
    let wouldHaveBeen = data.fileOffset + inSegment
    let found = await withStableDependencies { machO.symbols(offset: wouldHaveBeen) }
    #expect(found == nil)
    // Where it is filed, it keeps its address.
    let filed = try #require(machO.swiftSymbols.first { $0.name == tail.name })
    #expect(machO.address(forOffset: filed.offset) == UInt64(tail.offset))
}

/// An offset from the image under analysis must not trap: a symbol's
/// `n_value` with bit 63 set arrives here as a negative offset.
@Test func aNegativeOffsetHasAnAddressAndDoesNotTrapIfPresent() throws {
    guard FileManager.default.fileExists(atPath: executable) else { return }
    let machO = try BinaryLoader.load(path: executable)
    _ = machO.address(forOffset: -0x1000)
    #expect(machO.imageAddress(ofOffset: -0x1000) == nil)
}

// MARK: - Images the preflight refuses, read as a dependency would read them

/// The preflight stops every image here before a reader sees it. A reader's
/// own guard is what remains if a check ever lets one past, so it is proved
/// on the image directly.
private func unchecked(_ data: Data, named name: String, _ body: (MachOFile) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    guard case .machO(let machO) = try loadFromFile(url: url) else {
        Issue.record("\(name) is not a thin image")
        return
    }
    try body(machO)
}

/// A chain stops where the segment's file bytes stop, whatever `page_count`
/// says: past them lie the bytes of whatever is stored next.
@Test func aChainStopsAtItsSegmentsFileBytesIfPresent() throws {
    guard FileManager.default.fileExists(atPath: executable) else { return }
    var data = try Data(contentsOf: URL(fileURLWithPath: executable))
    let machO = try BinaryLoader.load(path: executable)
    let got = try #require(machO.sections.first { $0.sectionName == "__got" && $0.segmentName == "__DATA_DIRTY" })
    let dirty = try #require(machO.segments.first { $0.segmentName == "__DATA_DIRTY" })
    let slots = stride(from: got.offset, to: got.offset + got.size, by: 8).map { UInt64($0) }
    let table = Disassembler.ChainedFixupTable()
    let bound = try #require(slots.last { table.symbol(at: $0, in: machO) != nil })
    let shortened = UInt64(got.offset - dirty.fileOffset)
    #expect(bound >= UInt64(dirty.fileOffset) + shortened)
    let command = try segmentCommand("__DATA_DIRTY", in: data)
    put(shortened, at: command + 48, in: &data)
    try unchecked(data, named: "short-segment") { machO in
        #expect(Disassembler.ChainedFixupTable().symbol(at: bound, in: machO) == nil)
    }
}

/// A method's types that lead into zero fill read as nothing. Offset 0, what
/// the field used to fall back on, is the Mach-O header, whose magic is no
/// type encoding.
@Test func aMethodTypeIntoZeroFillReadsNothingIfPresent() throws {
    guard FileManager.default.fileExists(atPath: executable) else { return }
    var data = try Data(contentsOf: URL(fileURLWithPath: executable))
    let machO = try BinaryLoader.load(path: executable)
    let list = try #require(machO.sections.first { $0.sectionName == "__objc_methlist" })
    let zero = try #require(machO.sections.first { $0.sectionName == "__bigzero" })
    // { entsize, count } then { name, types, imp }: the first entry's types.
    let field = 8 + 4
    let displacement = Int32(UInt64(zero.address) + 0x100 - (UInt64(list.address) + UInt64(field)))
    withUnsafeBytes(of: displacement.littleEndian) {
        data.replaceSubrange(list.offset + field ..< list.offset + field + 4, with: $0)
    }
    try unchecked(data, named: "method-types") { machO in
        let lists = Array(try #require(machO.objc.methods))
        let first = try #require(lists.first?.methods(in: machO)?.first)
        #expect(first.types.isEmpty, "\(first.types)")
        #expect(!first.name.isEmpty)
    }
}

// MARK: - What stays declined

/// The file offset of the `LC_SEGMENT_64` command for `name`.
private func segmentCommand(_ name: String, in data: Data) throws -> Int {
    var cursor = 32
    for _ in 0 ..< Int(try #require(data.u32(at: 16))) {
        let size = Int(try #require(data.u32(at: cursor + 4)))
        if try #require(data.u32(at: cursor)) == 0x19,
           String(decoding: data[(cursor + 8) ..< (cursor + 24)].prefix { $0 != 0 }, as: UTF8.self) == name {
            return cursor
        }
        cursor += size
    }
    throw BinaryLoadError("no segment \(name)")
}

private func put(_ value: UInt64, at offset: Int, in data: inout Data) {
    withUnsafeBytes(of: value.littleEndian) { data.replaceSubrange(offset ..< offset + 8, with: $0) }
}

private func declined(_ data: Data, named name: String) throws -> (names: [String], message: String) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    var message = ""
    do { try MachOPreflight.validate(url: url) } catch { message = String(describing: error) }
    return (try misread(data, at: url.path), message)
}

/// Chain starts that disagree with their segment's address leave no pages to
/// read: with no fixups, a slot's chain bits would read as a pointer.
@Test func chainStartsElsewhereAreDeclinedIfPresent() throws {
    guard FileManager.default.fileExists(atPath: executable) else { return }
    var data = try Data(contentsOf: URL(fileURLWithPath: executable))
    let fixups = try #require(MachOPreflight.chainedFixups(prefix: data))
    let starts = fixups.dataoff + Int(try #require(data.u32(at: fixups.dataoff + 4)))
    let table = try #require(MachOPreflight.segmentTable(prefix: data))
    let index = try #require(table.firstIndex { $0.name == "__DATA_DIRTY" })
    let info = starts + Int(try #require(data.u32(at: starts + 4 + 4 * index)))
    let field = info + 8
    put(try #require(data.u64(at: field)) + 0x4000, at: field, in: &data)
    let result = try declined(data, named: "chain-elsewhere")
    #expect(result.names == ["__DATA_DIRTY"])
    #expect(result.message.contains("Unsupported Mach-O layout"), "\(result.message)")
    #expect(result.message.contains("__DATA_DIRTY (VM offset 0x"), "\(result.message)")
}

/// A slid segment that shares its file bytes with another has no one address
/// for an offset, so its fixups and metadata cannot be placed.
@Test func aSlidSegmentSharingFileBytesIsDeclinedIfPresent() throws {
    guard FileManager.default.fileExists(atPath: executable) else { return }
    var data = try Data(contentsOf: URL(fileURLWithPath: executable))
    let dirty = try segmentCommand("__DATA_DIRTY", in: data)
    let fields = try segmentCommand("__SWIFT_FIELDS", in: data)
    put(try #require(data.u64(at: dirty + 40)), at: fields + 40, in: &data)
    let result = try declined(data, named: "shared-bytes")
    #expect(result.names.contains("__SWIFT_FIELDS"))
    #expect(result.message.contains("Unsupported Mach-O layout"), "\(result.message)")
}

/// Raw bytes that nothing reaches by file offset do not count, however they
/// lie: `__FONT_DATA` in a C library, moved onto __DATA_DIRTY's bytes.
@Test func aSlidSegmentOfRawBytesDoesNotCountIfPresent() throws {
    guard FileManager.default.fileExists(atPath: cLibrary) else { return }
    var data = try Data(contentsOf: URL(fileURLWithPath: cLibrary))
    let font = try segmentCommand("__FONT_DATA", in: data)
    let dirty = try segmentCommand("__DATA_DIRTY", in: data)
    put(try #require(data.u64(at: dirty + 40)), at: font + 40, in: &data)
    #expect(!(try declined(data, named: "raw-bytes").names.contains("__FONT_DATA")))
}

/// A slid image with nothing wrong declines nothing.
@Test func slidSegmentsAreNotDeclinedIfPresent() throws {
    for path in [executable, cLibrary] {
        guard let names = try misread(path) else { continue }
        #expect(names.isEmpty, "\(path): \(names)")
    }
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

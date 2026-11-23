import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

private let imageBase: UInt64 = 0x100000000
private let parent = imageBase + 0xab8
private let entry = imageBase + 0x94c
private let resume = imageBase + 0xb08
private let descriptorAddress = imageBase + 0x1fd0
private let allocatorStub = imageBase + 0x1f2c
private let allocator = RuntimeFunctionReference(rawSymbol: "_swift_task_alloc",
    libraryName: "/usr/lib/swift/libswift_Concurrency.dylib")

// Independently copied little-endian words from the retained linked O parent.
// The synthetic test depends only on the words and independent address/extent
// expectations, and never reads an ignored fixture path.
private let parentCode: [UInt32] = [
    0xb24403bd, 0xd10083ff, 0xa9017bfd, 0xf90007f6, 0x910043fd, 0xaa0003f4, 0xf9000ac0,
    0xb0000008, 0xb94fd500, 0x94000514, 0xf9000ec0, 0x90000008, 0x912c2108, 0xa9002016,
    0xaa0003f6, 0xaa1403e0, 0xa9417bfd, 0x9243fbbd, 0x910083ff, 0x17ffff92,
]

private func decodeHandoff(_ words: [UInt32]) throws -> [Instruction] {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: parent)
    try #require(decoded.count == words.count)
    return decoded.map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
}

private func handoffEvidence(
    descriptor: UInt64 = descriptorAddress, checkProvider: Bool = true,
    recordTarget: UInt64 = entry, coveredRecord: Bool = true
) -> AsyncDescriptorHandoff.Evidence {
    .init(allocatorAt: { address in
        guard address == allocatorStub else { return nil }
        return checkProvider ? allocator : .init(rawSymbol: allocator.rawSymbol, libraryName: "/tmp/other.dylib")
    }, descriptorAt: { address, _ in
        guard coveredRecord, address == descriptor else { return nil }
        return .init(address: address, entry: recordTarget, requiredContextSize: 32)
    })
}

private func descriptorIndex(
    words: [UInt32] = parentCode, checkProvider: Bool = true,
    recordTarget: UInt64 = entry, coveredRecord: Bool = true
) throws -> AsyncFuncletIndex {
    let instructions = try decodeHandoff(words)
    return AsyncFuncletIndex.build(
        hints: .init(entries: [parent, entry], awaitReturns: [resume], continuations: []),
        functionStarts: [parent, entry, resume],
        instructions: { $0 == parent ? instructions : [] },
        nameOf: { $0 == allocatorStub ? "swift_task_alloc" : nil },
        handoffEvidence: handoffEvidence(checkProvider: checkProvider,
            recordTarget: recordTarget, coveredRecord: coveredRecord)
    )
}

private func proveHandoff(
    _ words: [UInt32], evidence: AsyncDescriptorHandoff.Evidence
) throws -> AsyncDescriptorHandoff? {
    AsyncDescriptorHandoff.prove(try decodeHandoff(words), source: parent, site: resume - 4,
                                 resume: resume, entry: entry, evidence: evidence)
}

@Test func asyncHandoffRejectsImmediateSizeWithoutDescriptorLoad() throws {
    var code = parentCode
    let evidence = handoffEvidence(descriptor: imageBase + 0x1000)
    code[8] = 0xb9400500 // ldr w0,[x8,#4], matched valid descriptor at page start
    try #require(proveHandoff(code, evidence: evidence) != nil)
    code[8] = 0x52800400 // mov w0,#32, same scalar operand but no descriptor load
    #expect(try proveHandoff(code, evidence: evidence) == nil, "isolated size load provenance")
}

@Test func asyncHandoffRejectsFullWidthSizeLoadAtMatchingValidRecord() throws {
    var code = parentCode
    // The checked record is four-byte aligned and its size word is eight-byte
    // aligned. The adjacent high word can be zero, so equal x0 is possible.
    let evidence = handoffEvidence(descriptor: descriptorAddress + 4)
    code[8] = 0xb94fd900 // ldr w0,[x8,#0xfd8]
    try #require(proveHandoff(code, evidence: evidence) != nil)
    code[8] = 0xf947ed00 // ldr x0,[x8,#0xfd8], same address, wrong width
    #expect(try proveHandoff(code, evidence: evidence) == nil, "isolated size load width")
}

@Test func asyncHandoffRejectsWrongParentAtOtherwiseIdenticalHeader() throws {
    var code = parentCode
    code[13] = 0xa9002015 // stp x21,x8,[x0], still writes the same resume to the same result
    let edge = try #require(descriptorIndex(words: code).transfers[parent]?.first)
    #expect(edge.descriptorHandoff == nil, "isolated parent header word")
}

@Test func asyncHandoffRejectsWrongContextRegisterSource() throws {
    var code = parentCode
    code[14] = 0xaa0803f6 // mov x22,x8, same resume scratch instead of allocator x0
    #expect(try proveHandoff(code, evidence: handoffEvidence()) == nil, "isolated x22 identity")
}

@Test func asyncHandoffRejectsRecordTargetThatDiffersFromDirectEntry() throws {
    // The callback returns a record with another valid linker start. The
    // transfer's own destination and its chosen resume stay the same.
    let edge = try #require(descriptorIndex(recordTarget: resume).transfers[parent]?.first)
    #expect(edge.callee == entry)
    #expect(edge.descriptorHandoff == nil, "isolated exact descriptor entry")
}

@Test func optimizedAsyncParentHandoffCarriesDescriptorOperandProvenance() throws {
    let index = try descriptorIndex()
    let handoff = try #require(index.transfers[parent]?.first?.descriptorHandoff)
    #expect(handoff.descriptor.address == descriptorAddress)
    #expect(handoff.descriptor.entry == entry)
    #expect(handoff.descriptor.requiredContextSize == 32)
    #expect(handoff.sizeLoad == imageBase + 0xad8)
    #expect(handoff.allocationCall == imageBase + 0xadc)
    #expect(handoff.allocator == allocator)
}

@Test func aDisplayNameAndGroupedTransferDoNotSubstituteForHandoffProvenance() throws {
    let wrongProvider = try descriptorIndex(checkProvider: false)
    let wrongEntry = try descriptorIndex(recordTarget: resume)
    let missingCoverage = try descriptorIndex(coveredRecord: false)
    var differentLoad = parentCode
    differentLoad[8] = 0xb94fd900 // next word, same base and destination
    let wrongLoad = try descriptorIndex(words: differentLoad)
    for index in [wrongProvider, wrongEntry, missingCoverage, wrongLoad] {
        let edge = try #require(index.transfers[parent]?.first)
        #expect(edge.resume == resume)
        #expect(edge.callee == entry)
        #expect(edge.descriptorHandoff == nil)
    }

    var differentContext = parentCode
    differentContext[14] = 0xaa0803f6 // x22 takes resume scratch rather than allocator result
    let wrongIdentity = try descriptorIndex(words: differentContext)
    #expect(wrongIdentity.transfers[parent]?.contains { $0.descriptorHandoff != nil } != true)
}

@Test func asyncDescriptorRequiresCompleteOwningSegmentFixupAbsence() {
    // Copied layout of the retained O starts directory in segment command
    // order: __PAGEZERO, __TEXT, __DATA_CONST, __DATA, __LINKEDIT.
    let directory: [UInt8] = [5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                               24, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    #expect(AsyncFunctionDescriptor.noStarts(in: directory, segmentCount: 5, ordinal: 1))
    #expect(!AsyncFunctionDescriptor.noStarts(in: directory, segmentCount: 5, ordinal: 2))
    #expect(!AsyncFunctionDescriptor.noStarts(in: Array(directory.dropLast()), segmentCount: 5, ordinal: 1))
    #expect(!AsyncFunctionDescriptor.noStarts(in: directory, segmentCount: 4, ordinal: 1))
    var textHasStarts = directory
    textHasStarts[8] = 24
    #expect(!AsyncFunctionDescriptor.noStarts(in: textHasStarts, segmentCount: 5, ordinal: 1))
}

@Test func publicAwaitResultsReportsOnlyTheOutgoingDescriptorHandoffIfPresent() async throws {
    guard linkedAwaitResultsIsPresent() else { return }
    let image = try BinaryLoader.load(path: linkedAwaitResults)
    func exactSymbol(_ name: String) throws -> UInt64 {
        let symbol = try #require(image.symbols.first { $0.name == name })
        return try #require(Disassembler.sectionAddress(of: symbol))
    }
    let owner = try exactSymbol("_$s12AwaitResults6useIntyySiYaF")
    let callee = try exactSymbol("_$s12AwaitResults9intResultyS2iYaF")
    let descriptor = try exactSymbol("_$s12AwaitResults9intResultyS2iYaFTu")
    let recorder = ProbeRecorder()
    _ = await Probe.recording(recorder) {
        await withStableDependencies { await Disassembler().disassemble(machO: image) }
    }
    let facts = recorder.records.filter { $0.event == .asyncDescriptorHandoff }
    let outgoing = try #require(facts.first { $0.function?.start == owner && $0["entry"] == .address(callee) })
    #expect(outgoing["descriptor"] == .address(descriptor))
    #expect(outgoing["sizeOperand"] == .int(32))
    #expect(outgoing["incomingPrivacy"] == .label("unknown"))
    #expect(!facts.contains { $0["entry"] == .address(owner) })
}

private let linkedAwaitResults = "Fixtures/Sample/libAwaitResults.opt.dylib"

private func linkedAwaitResultsIsPresent() -> Bool {
    guard FileManager.default.fileExists(atPath: linkedAwaitResults) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, "Build \(linkedAwaitResults) before testing.")
        return false
    }
    return true
}

/// The clone is only read as Mach-O data. It is never loaded by dyld.
private func withLinkedHandoffCopy(
    _ mutation: (MachOFile, inout Data) throws -> Void,
    loadEdited: (URL) throws -> MachOFile = { try BinaryLoader.load(path: $0.path) },
    verify: (MachOFile, MachOFile) async throws -> Void
) async throws {
    let original = try BinaryLoader.load(path: linkedAwaitResults)
    var bytes = try Data(contentsOf: URL(fileURLWithPath: linkedAwaitResults))
    try #require(original.headerStartOffset == 0 && !original.isSwapped)
    try mutation(original, &bytes)
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-handoff-\(UUID().uuidString).dylib")
    defer { try? FileManager.default.removeItem(at: scratch) }
    try bytes.write(to: scratch)
    let edited = try loadEdited(scratch)
    try await verify(original, edited)
}

private func linkedHandoffAddress(_ name: String, in image: MachOFile) throws -> UInt64 {
    let symbol = try #require(image.symbols.first { $0.name == name })
    return try #require(Disassembler.sectionAddress(of: symbol))
}

private func linkedDescriptorShape(in image: MachOFile) throws -> (
    address: UInt64, entry: UInt64, bytes: [UInt8], starts: Set<UInt64>, code: [CodeSection]
) {
    let name = "_$s12AwaitResults9intResultyS2iYaF"
    let address = try linkedHandoffAddress(name + "Tu", in: image)
    let entry = try linkedHandoffAddress(name, in: image)
    let starts = Set(Disassembler.linkerFunctionStarts(of: image))
    let code = CodeSection.of(image, functionStarts: starts.sorted())
    let offset = try #require(image.fileOffset(of: address).map(Int.init))
    let file = try Data(contentsOf: image.url)
    try #require(offset >= 0 && offset + 8 <= file.count)
    return (address, entry, Array(file[offset..<(offset + 8)]), starts, code)
}

@Test func linkedDescriptorDeclinesUnknownFixupVersionDespiteReadableRecordIfPresent() async throws {
    guard linkedAwaitResultsIsPresent() else { return }
    try await withLinkedHandoffCopy({ image, bytes in
        let commands = image.loadCommands.compactMap { command -> Int? in
            if case .dyldChainedFixups(let info) = command { return Int(info.layout.dataoff) }
            return nil
        }
        try #require(commands.count == 1)
        let offset = try #require(commands.first)
        try #require(offset >= 0 && offset + 4 <= bytes.count)
        try #require(Array(bytes[offset..<(offset + 4)]) == [0, 0, 0, 0])
        bytes[offset] = 1 // unsupported header version; lengths and directories stay intact
    }, verify: { original, edited in
        let before = try linkedDescriptorShape(in: original)
        let after = try linkedDescriptorShape(in: edited)
        #expect(after.address == before.address)
        #expect(after.entry == before.entry)
        #expect(after.bytes == before.bytes)
        #expect(after.starts == before.starts)
        #expect(after.code == before.code)
        try #require(after.starts.contains(after.entry))
        let signedEntryDelta = after.bytes.prefix(4).enumerated().reduce(UInt32(0)) { bits, byte in
            bits | UInt32(byte.element) << (8 * byte.offset)
        }
        #expect(Int64(after.address) + Int64(Int32(bitPattern: signedEntryDelta)) == Int64(after.entry))
        #expect(Array(after.bytes.suffix(4)) == [32, 0, 0, 0])

        let beforeRanges = try #require(FileBackedRanges(standalone: original))
        let afterRanges = try #require(FileBackedRanges(standalone: edited))
        #expect(beforeRanges.target(at: before.address) == afterRanges.target(at: after.address))
        let baseline = try #require(AsyncFunctionDescriptor.read(at: before.address, in: original,
            ranges: beforeRanges, codeSections: before.code, functionStarts: before.starts, expectedEntry: before.entry))
        #expect(baseline.requiredContextSize == 32)
        #expect(AsyncFunctionDescriptor.read(at: after.address, in: edited,
            ranges: afterRanges, codeSections: after.code, functionStarts: after.starts, expectedEntry: after.entry) == nil,
            "isolated readable descriptor with unsupported fixup version")
    })
}

@Test func linkedDescriptorDeclinesFixupRecordWithConflictingSegmentOffsetIfPresent() async throws {
    guard linkedAwaitResultsIsPresent() else { return }
    try await withLinkedHandoffCopy({ image, bytes in
        func word(at offset: Int) throws -> Int {
            try #require(offset >= 0 && offset <= bytes.count - 4)
            return (0..<4).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
        }
        let commands = image.loadCommands.compactMap { command -> Int? in
            if case .dyldChainedFixups(let info) = command { return Int(info.layout.dataoff) }
            return nil
        }
        try #require(commands.count == 1)
        let header = try #require(commands.first)
        let starts = try header + word(at: header + 4)
        let segments = Array(image.segments64)
        let text = try #require(segments.firstIndex(where: { $0.segmentName == "__TEXT" }))
        let data = try #require(segments.firstIndex(where: { $0.segmentName == "__DATA_CONST" }))
        try #require(try word(at: starts) == segments.count)
        try #require(try word(at: starts + 4 + text * 4) == 0)
        let relative = try word(at: starts + 4 + data * 4)
        try #require(relative >= 4 + segments.count * 4)
        let segmentOffset = starts + relative + 8
        try #require(segmentOffset <= bytes.count - 8)
        let base = try #require(image.preferredLoadAddress)
        let oldOffset = segments[data].layout.vmaddr - base
        let textOffset = segments[text].layout.vmaddr - base
        try #require(oldOffset != textOffset)
        let byteArray = { (number: UInt64) in (0..<8).map { UInt8(truncatingIfNeeded: number >> (8 * $0)) } }
        try #require(Array(bytes[segmentOffset..<(segmentOffset + 8)]) == byteArray(oldOffset))
        bytes.replaceSubrange(segmentOffset..<(segmentOffset + 8), with: byteArray(textOffset))
    }, loadEdited: { scratch in
        // The path API already rejects this contradiction. Open the controlled
        // bytes directly only to test the descriptor reader's own guard.
        let diagnostic: String
        do {
            _ = try BinaryLoader.load(path: scratch.path)
            diagnostic = ""
        } catch let error as BinaryLoadError {
            diagnostic = error.message
        }
        try #require(diagnostic.contains("chain starts disagree with the segment's address"))
        guard case .machO(let image) = try MachOKit.loadFromFile(url: scratch) else {
            throw BinaryLoadError("Expected the edited standalone Mach-O")
        }
        return image
    }, verify: { original, edited in
        let before = try linkedDescriptorShape(in: original)
        let after = try linkedDescriptorShape(in: edited)
        try #require(before.address == after.address && before.entry == after.entry && before.bytes == after.bytes)
        try #require(before.starts == after.starts && before.code == after.code)
        let originalRanges = try #require(FileBackedRanges(standalone: original))
        let editedRanges = try #require(FileBackedRanges(standalone: edited))
        try #require(originalRanges.target(at: before.address) == editedRanges.target(at: after.address))
        try #require(AsyncFunctionDescriptor.read(at: before.address, in: original,
            ranges: originalRanges, codeSections: before.code, functionStarts: before.starts, expectedEntry: before.entry) != nil)
        #expect(AsyncFunctionDescriptor.read(at: after.address, in: edited,
            ranges: editedRanges, codeSections: after.code, functionStarts: after.starts, expectedEntry: after.entry) == nil,
            "non-text directory entry claims the supposedly fixup-free text segment")
    })
}

/// Recover the pointer slot from the original linked machine encodings and
/// check its actual parsed bind, independently of the probe admission.
private func linkedAllocatorReference(in image: MachOFile, call: UInt64) throws -> RuntimeFunctionReference {
    let file = try Data(contentsOf: image.url)
    func word(at address: UInt64) throws -> UInt32 {
        let offset = try #require(image.fileOffset(of: address).map(Int.init))
        try #require(offset >= 0 && offset + 4 <= file.count)
        return file[offset..<(offset + 4)].enumerated().reduce(UInt32(0)) { bits, byte in
            bits | UInt32(byte.element) << (8 * byte.offset)
        }
    }
    let branch = try word(at: call)
    try #require(branch & 0xfc000000 == 0x94000000)
    let delta = Int64(Int32(bitPattern: branch << 6) >> 6) * 4
    let stub = UInt64(Int64(call) + delta)
    let page = try word(at: stub)
    let load = try word(at: stub + 4)
    let jump = try word(at: stub + 8)
    try #require(page & 0x9f00001f == 0x90000010) // adrp x16
    try #require(load & 0xffc003ff == 0xf9400210) // ldr x16,[x16,#offset]
    try #require(jump == 0xd61f0200)              // br x16
    let immediate = ((page >> 5) & 0x7ffff) << 2 | ((page >> 29) & 3)
    let pages = Int64(Int32(bitPattern: immediate << 11) >> 11)
    let slot = UInt64(Int64(stub & ~0xfff) + pages * 4096 + Int64((load >> 10) & 0xfff) * 8)
    let offset = try #require(image.fileOffset(of: slot))
    return try #require(Disassembler.ChainedFixupTable()
        .validatedFunctionReference(at: UInt64(offset), in: image))
}

@Test func linkedSameNameAllocatorFromAnotherProviderDoesNotAdmitHandoffIfPresent() async throws {
    guard linkedAwaitResultsIsPresent() else { return }
    let alternate = "/usr/lib/swift/libswift_Replacement.dylib"
    try await withLinkedHandoffCopy({ _, bytes in
        let old = Data(allocator.libraryName.utf8) + Data([0])
        let replacement = Data(alternate.utf8) + Data([0])
        try #require(old.count == replacement.count)
        let range = try #require(bytes.range(of: old))
        try #require(bytes.range(of: old, in: range.upperBound..<bytes.endIndex) == nil)
        bytes.replaceSubrange(range, with: replacement)
    }, verify: { original, edited in
        let ownerName = "_$s12AwaitResults6useIntyySiYaF"
        let owner = try linkedHandoffAddress(ownerName, in: original)
        #expect(try linkedHandoffAddress(ownerName, in: edited) == owner)
        let (before, after) = (ProbeRecorder(), ProbeRecorder())
        let baseline = await withStableDependencies {
            await Probe.recording(before) { await Disassembler().disassemble(machO: original) }
        }
        let candidate = await withStableDependencies {
            await Probe.recording(after) { await Disassembler().disassemble(machO: edited) }
        }
        let fact = try #require(before.records.first { $0.event == .asyncDescriptorHandoff && $0.function?.start == owner })
        guard case .address(let call)? = fact["allocationCall"] else {
            Issue.record("Missing allocator call address in baseline")
            return
        }
        #expect(try linkedAllocatorReference(in: original, call: call) == allocator)
        #expect(try linkedAllocatorReference(in: edited, call: call) ==
            RuntimeFunctionReference(rawSymbol: allocator.rawSymbol, libraryName: alternate))
        let beforeOwner = try #require(baseline.first { $0.startAddress == owner })
        let afterOwner = try #require(candidate.first { $0.startAddress == owner })
        #expect(beforeOwner.instructions.map(\.address) == afterOwner.instructions.map(\.address))
        #expect(beforeOwner.instructions.map(\.branchTarget) == afterOwner.instructions.map(\.branchTarget))
        #expect(!after.records.contains { $0.event == .asyncDescriptorHandoff && $0.function?.start == owner },
            "isolated actual linked allocator provider")
    })
}

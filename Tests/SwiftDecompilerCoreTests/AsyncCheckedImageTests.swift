import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

private func commands(_ bytes: Data, opcode: UInt32) -> [(offset: Int, size: Int)] {
    var result: [(offset: Int, size: Int)] = []
    var command = 32
    for _ in 0..<(bytes.u32(at: 16) ?? 0) {
        guard let code = bytes.u32(at: command), let size = bytes.u32(at: command + 4), size >= 8,
              size <= bytes.count - command else { return [] }
        if code == opcode { result.append((command, Int(size))) }
        command += Int(size)
    }
    return result
}

private func littleEndian(_ word: UInt64, width: Int) -> [UInt8] {
    (0..<width).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) }
}

private func uleb(_ input: Int) -> [UInt8] {
    var value = input
    var bytes: [UInt8] = []
    repeat {
        let chunk = UInt8(value & 0x7f)
        value >>= 7
        bytes.append(chunk | (value == 0 ? 0 : 0x80))
    } while value != 0
    return bytes
}

@Test func checkedAsyncImageRejectsMalformedEntrypointCommands() {
    let main = littleEndian(0x8000_0028, width: 4) + littleEndian(24, width: 4)
        + littleEndian(256, width: 8) + littleEndian(0, width: 8)
    let dyld = littleEndian(0xe, width: 4) + littleEndian(32, width: 4)
        + littleEndian(12, width: 4) + Array("/usr/lib/dyld".utf8)
        + Array(repeating: UInt8(0), count: 7)
    let platform = [UInt64(0x32), 24, 1, 0x000f_0000, 0x001b_0000, 0]
        .flatMap { littleEndian($0, width: 4) }
    let starts = [UInt64(0x26), 16, 264, 8].flatMap { littleEndian($0, width: 4) }
    func header(_ extra: [[UInt8]] = [], mainCommand: [UInt8] = []) -> Data {
        let commands = [mainCommand.isEmpty ? main : mainCommand, dyld, platform, starts] + extra
        let commandBytes = commands.flatMap { $0 }
        let words = [UInt64(0xfeed_facf), 0x0100_000c, 0, 2, UInt64(commands.count),
                     UInt64(commandBytes.count), 0x80, 0]
        return Data(words.flatMap { littleEndian($0, width: 4) } + commandBytes
            + Array(repeating: UInt8(0), count: 272 - 32 - commandBytes.count))
    }
    #expect(AsyncCheckedImage.checkedEntryOffset(in: header()) == 256)
    #expect(AsyncCheckedImage.checkedEntryOffset(in: header([main])) == nil)
    #expect(AsyncCheckedImage.checkedEntryOffset(in: Data(header().prefix(47))) == nil)
    var misaligned = main
    misaligned[8] = 1 // still in the selected file
    #expect(AsyncCheckedImage.checkedEntryOffset(in: header(mainCommand: misaligned)) == nil)
    let variant = [UInt64(0x37), 16, 264, 8].flatMap { littleEndian($0, width: 4) }
    #expect(AsyncCheckedImage.checkedEntryOffset(in: header([variant])) == nil)
}

@Test func checkedAsyncImageRejectsAThinDylibAsStartupIfPresent() throws {
    let path = "Fixtures/Sample/libAwaitResults.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, "Build the async fixtures.")
        return
    }
    let image = try BinaryLoader.load(path: path)
    #expect(!Disassembler.linkerFunctionStarts(of: image).isEmpty)
    #expect(Disassembler().checkedAsyncImage(in: image) == nil)
}

@Test func checkedAsyncImageFollowsRealStartupOperandsAndReportsIngressFrontiersIfPresent() async throws {
    let path = "Fixtures/Sample/closed-await-hop-oracle"
    guard FileManager.default.fileExists(atPath: path) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, "Build the closed async startup fixture.")
        return
    }
    try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        let extractor = Disassembler()
        let checked = try #require(extractor.checkedAsyncImage(in: image))
        let bytes = try Data(contentsOf: image.url)
        let mainCommand = try #require(commands(bytes, opcode: 0x8000_0028).onlyAsyncFixtureCommand)
        let mainOffset = try #require(bytes.u64(at: mainCommand.offset + 8).flatMap { Int(exactly: $0) })
        let ranges = try #require(FileBackedRanges(standalone: image))
        let section = try #require(image.sections64.first { $0.sectionName == "__text" })
        let independentlyMappedMain = section.layout.addr + UInt64(mainOffset - Int(section.layout.offset))
        #expect(checked.startup.main == independentlyMappedMain)
        #expect(checked.startup.descriptor.requiredContextSize == 48)
        #expect(checked.bodies[checked.startup.descriptor.entry]?.isEmpty == false)
        #expect(checked.startup.create.reference.rawSymbol == "_swift_task_create")
        #expect(checked.startup.create.pointerFileOffset != checked.startup.run.pointerFileOffset)

        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratch) }
        func inspect(_ modified: Data, label: String) throws -> AsyncCheckedImage? {
            let copy = scratch.appendingPathComponent(label)
            try modified.write(to: copy)
            return extractor.checkedAsyncImage(in: try BinaryLoader.load(path: copy.path))
        }

        let detached = try #require(checked.detachedIngress)
        #expect(detached.create.binding.stub == checked.startup.create.stub)
        #expect(detached.create.site != checked.startup.createSite)
        #expect(detached.boxAllocation.binding.reference.rawSymbol == "_swift_allocObject")
        #expect(detached.relativeTails.count == 2)
        let lastRelative = try #require(detached.relativeTails.last)
        #expect(lastRelative.descriptor == detached.closureDescriptor)
        #expect(detached.directTails.count == 4)
        #expect(detached.directTails.first?.function == detached.closureDescriptor.entry)
        #expect(detached.sites[lastRelative.branch]?.successors == [detached.closureDescriptor.entry])
        #expect(detached.sites[detached.create.site]?.unresolvedTransfer == true)

        let physical = try #require(checked.physicalRegion)
        #expect(physical.savedChildOffset == 16)
        #expect(physical.ownerSlot == 24)
        #expect(physical.increment == 2)
        #expect(physical.childAllocationSite == detached.directTails.last?.handoff.allocationCall)
        #expect(physical.childSavedParentResume == detached.directTails.last?.returnEntry)
        let linkedFrameSites = physical.steps.filter { step in
            if case .machine(let effects) = step.step {
                return effects.contains {
                    if case .machineStackWords = $0 { return true }
                    return false
                }
            }
            return false
        }
        #expect(linkedFrameSites.contains { $0.word == 0xa9017bfd })
        #expect(linkedFrameSites.contains { $0.word == 0xf81f83a9 })
        let expectedFold = try #require(Dictionary(grouping: detached.directTails, by: \.returnEntry)
            .first { $0.value.count >= 2 })
        let ownerReturns = try #require(physical.sharedReturns[expectedFold.key])
        let relativeSuppliers = detached.relativeTails.filter { $0.returnEntry == expectedFold.key }
        let expectedTailSites = Set(expectedFold.value.map(\.branch) + relativeSuppliers.map(\.branch))
        let expectedAllocations = Set(expectedFold.value.map { $0.handoff.allocationCall }
            + relativeSuppliers.map { $0.allocation.site })
        #expect(ownerReturns.count == expectedFold.value.count + relativeSuppliers.count)
        #expect(Set(ownerReturns.map(\.tailSite)) == expectedTailSites)
        #expect(Set(ownerReturns.map(\.callerGeneration)).count == ownerReturns.count)
        #expect(Set(ownerReturns.map(\.childGeneration)) == expectedAllocations)
        #expect(!ownerReturns.contains { $0.tailSite == detached.directTails.last?.branch })
        let firstRelative = try #require(detached.relativeTails.first)
        let checkedTail = try #require(physical.steps.first { $0.site == firstRelative.branch })
        if case .machine(let effects) = checkedTail.step {
            #expect(effects.contains {
                if case .requireRelativeTarget(let register, let entry) = $0 {
                    return register == 3 && entry == firstRelative.descriptor.entry
                }
                return false
            })
        } else {
            Issue.record("Expected checked relative-tail operand replay")
        }
        let hop = try #require(physical.requests.first { $0.role == .switchExecutor })
        #expect(physical.steps.first { $0.site == hop.site }?.physicalSuccessors == [hop.binding.stub])
        #expect(physical.steps.first { $0.site == physical.sinkCall }?.physicalSuccessors == [physical.sinkEntry])
        #expect(physical.requests.filter { $0.role == .releaseContext(pointerRegister: 0) }.count == 2)

        let sink = try #require(image.imageOffset(ofAddress: physical.sinkCall))
        let labelWord = try #require(bytes.u32(at: sink - 12))
        try #require(labelWord & 0x1f == 1)
        var differentLabel = bytes
        differentLabel.replaceSubrange((sink - 12)..<(sink - 8),
            with: littleEndian(UInt64(labelWord ^ (1 << 5)), width: 4))
        let labelChanged = try #require(try inspect(differentLabel, label: "new-label"))
        #expect(labelChanged.physicalRegion?.sinkCall == physical.sinkCall)
        #expect(labelChanged.physicalRegion?.increment == physical.increment)

        let ownerStore = try #require(image.imageOffset(ofAddress: physical.childSavedParentResume + 9 * 4))
        try #require(bytes.u32(at: ownerStore) == 0xf9000d20)
        var badSlot = bytes
        badSlot.replaceSubrange(ownerStore..<(ownerStore + 4),
            with: littleEndian(0xf9000920, width: 4)) // str x0,[x9,#16]
        let wrongSlot = try #require(try inspect(badSlot, label: "wrong-owner-slot"))
        #expect(wrongSlot.detachedIngress?.create.site == detached.create.site)
        #expect(wrongSlot.physicalRegion == nil)

        let scheduling = try #require(checked.startupSwitches.values.first {
            $0.continuation == detached.driver
        })
        #expect(checked.frontiers.contains(.importedOperation(scheduling.site)))
        #expect(detached.sites[scheduling.site]?.successors == [scheduling.binding.stub])
        #expect(detached.sites[scheduling.site]?.unresolvedTransfer == true)

        let addOffset = try #require(image.imageOffset(ofAddress: scheduling.materialization + 4))
        let addressAdd = try #require(bytes.u32(at: addOffset))
        try #require(addressAdd & 0xffc003ff == 0x91000000)
        var misalignedSwitch = bytes
        // Toggle bit zero of ADD's displacement. The external branch and
        // strong import remain intact, and the detached body remains in file.
        misalignedSwitch.replaceSubrange(addOffset..<(addOffset + 4),
            with: littleEndian(UInt64(addressAdd ^ (1 << 10)), width: 4))
        let noStart = try #require(try inspect(misalignedSwitch, label: "bad-switch-start"))
        #expect(noStart.startup.descriptor == checked.startup.descriptor)
        #expect(noStart.frontiers.contains(.importedOperation(scheduling.site)))
        #expect(noStart.startupSwitches[scheduling.site] == nil)
        #expect(noStart.bodies[detached.driver] == nil)
        #expect(noStart.detachedIngress == nil)

        let moveOffset = try #require(image.imageOffset(ofAddress: scheduling.materialization + 8))
        try #require(bytes.u32(at: moveOffset) == 0xaa0803e1)
        var clobberedSwitch = bytes
        clobberedSwitch.replaceSubrange(moveOffset..<(moveOffset + 4),
            with: littleEndian(0xaa0803e0, width: 4)) // mov x0,x8
        let clobbered = try #require(try inspect(clobberedSwitch, label: "clobbered-switch-start"))
        #expect(clobbered.frontiers.contains(.importedOperation(scheduling.site)))
        #expect(clobbered.startupSwitches[scheduling.site] == nil)
        #expect(clobbered.bodies[detached.driver] == nil)
        #expect(clobbered.detachedIngress == nil)

        var wrongBox = bytes
        let boxStore = try #require(image.imageOffset(ofAddress: detached.boxStore))
        try #require(bytes.u32(at: boxStore) == 0xa9015408)
        // STP x9,x21,[x0,#16] leaves task creation and descriptor records intact.
        wrongBox.replaceSubrange(boxStore..<(boxStore + 4), with: littleEndian(0xa9015409, width: 4))
        let missingBox = try #require(try inspect(wrongBox, label: "wrong-box-source"))
        #expect(missingBox.startup.descriptor == checked.startup.descriptor)
        #expect(missingBox.detachedIngress == nil)

        var wrongRelative = bytes
        let relativeBranch = try #require(image.imageOffset(ofAddress: lastRelative.branch))
        try #require(bytes.u32(at: relativeBranch) == 0xd61f0020)
        // BR x2 retains an indirect branch and a live x1 descriptor-derived code value.
        wrongRelative.replaceSubrange(relativeBranch..<(relativeBranch + 4),
                                      with: littleEndian(0xd61f0040, width: 4))
        let missingTail = try #require(try inspect(wrongRelative, label: "wrong-relative-target"))
        #expect(missingTail.startup.descriptor == checked.startup.descriptor)
        #expect(missingTail.detachedIngress == nil)

        var wrongRoot = bytes
        let const = try #require(image.sections64.first {
            $0.segmentName == "__TEXT" && $0.sectionName == "__const"
        })
        wrongRoot.replaceSubrange((mainCommand.offset + 8)..<(mainCommand.offset + 16),
                                  with: littleEndian(UInt64(const.layout.offset), width: 8))
        #expect(AsyncCheckedImage.checkedEntryOffset(in: wrongRoot) == Int(const.layout.offset))
        #expect(try inspect(wrongRoot, label: "bad-root") == nil)

        let segments = commands(bytes, opcode: 0x19)
        let dataSegment = try #require(segments.first(where: { command in
            bytes[(command.offset + 8)..<(command.offset + 14)].elementsEqual("__DATA".utf8)
        }))
        var overflowing = bytes
        overflowing.replaceSubrange((dataSegment.offset + 24)..<(dataSegment.offset + 32),
                                    with: littleEndian(UInt64.max - 7, width: 8))
        let overflowCopy = scratch.appendingPathComponent("overflow-segment")
        try overflowing.write(to: overflowCopy)
        #expect(throws: BinaryLoadError.self) { try BinaryLoader.load(path: overflowCopy.path) }
        let rawOverflow = try MachOFile(url: overflowCopy)
        #expect(rawOverflow.header.fileType == .execute)
        #expect(extractor.checkedAsyncImage(in: rawOverflow) == nil)

        var overlapping = bytes
        overlapping.replaceSubrange((dataSegment.offset + 24)..<(dataSegment.offset + 32),
                                    with: littleEndian(ranges.base, width: 8))
        let overlapCopy = scratch.appendingPathComponent("overlap-segment")
        try overlapping.write(to: overlapCopy)
        let rawOverlap = try MachOFile(url: overlapCopy)
        #expect(rawOverlap.segments64.contains { $0.segmentName.hasPrefix("__DATA") &&
            $0.layout.vmaddr == ranges.base })
        #expect(extractor.checkedAsyncImage(in: rawOverlap) == nil)

        var indirect = bytes
        let operation = checked.startup.descriptor.entry
        let operationOffset = try #require(image.imageOffset(ofAddress: operation))
        indirect.replaceSubrange(operationOffset..<(operationOffset + 4),
                                 with: littleEndian(0xd61f0100, width: 4)) // br x8
        let unresolved = try #require(try inspect(indirect, label: "indirect-start"))
        #expect(unresolved.startup.descriptor == checked.startup.descriptor)
        #expect(unresolved.frontiers.contains(.unsupportedControl(operation)))

        let exports = try #require(commands(bytes, opcode: 0x8000_0033).onlyAsyncFixtureCommand)
        let exportOffset = Int(try #require(bytes.u32(at: exports.offset + 8)))
        let exportSize = Int(try #require(bytes.u32(at: exports.offset + 12)))
        let mainRuntimeOffset = Int(independentlyMappedMain - ranges.base)
        let operationRuntimeOffset = Int(operation - ranges.base)
        let mainEncoding = uleb(mainRuntimeOffset)
        let operationEncoding = uleb(operationRuntimeOffset)
        try #require(mainEncoding.count == operationEncoding.count)
        let needle = Data([UInt8(mainEncoding.count + 1), 0] + mainEncoding + [0])
        let exportRange = exportOffset..<(exportOffset + exportSize)
        let leaf = try #require(bytes.range(of: needle, in: exportRange))
        try #require(bytes.range(of: needle, in: leaf.upperBound..<exportRange.upperBound) == nil)
        var exposed = bytes
        exposed.replaceSubrange((leaf.lowerBound + 2)..<(leaf.upperBound - 1), with: operationEncoding)
        let open = try #require(try inspect(exposed, label: "exported-start"))
        #expect(open.startup.descriptor == checked.startup.descriptor)
        #expect(open.frontiers.contains(.exported(operation)))
    }
}

private extension Array {
    var onlyAsyncFixtureCommand: Element? { count == 1 ? first : nil }
}

import MachOKit
import MachOSwiftSection

/// A checked, static record. An allocation or indirect-call consumer must
/// separately prove the descriptor operand, invocation and object lifetime.
struct AsyncFunctionDescriptor: Sendable, Equatable {
    let address: UInt64
    let entry: UInt64
    let requiredContextSize: UInt32

    private static let byteCount = 8

    /// The caller supplies the address reached by a proved descriptor
    /// reference. An arbitrary data address or a demangled name is not such a
    /// reference. This initial reader handles standalone ARM64 and the
    /// read-only __TEXT,__const placement emitted by the observed compiler.
    static func read(
        at referencedAddress: UInt64, in machO: MachOFile, ranges: FileBackedRanges,
        codeSections: [CodeSection], functionStarts: Set<UInt64>, expectedEntry: UInt64? = nil
    ) -> Self? {
        guard Disassembler.decodesCode(of: machO), !machO.isLoadedFromDyldCache,
              referencedAddress.isMultiple(of: 4),
              case let (end, false) = referencedAddress.addingReportingOverflow(UInt64(byteCount)),
              let descriptorSection = machO.sections64.first(where: { section in
                  section.sectionName == "__const" && section.segmentName == "__TEXT"
                      && section.layout.nreloc == 0
                      && covers(referencedAddress, count: byteCount,
                                start: section.layout.addr, size: section.layout.size)
              })
        else { return nil }
        let span = referencedAddress..<end
        guard hasNoTextFixups(in: machO) else { return nil }
        guard machO.segments64.contains(where: { segment in
                  segment.segmentName == "__TEXT" && !segment.initialProtection.contains(.write)
                      && covers(referencedAddress, count: byteCount,
                                start: segment.layout.vmaddr, size: segment.layout.vmsize)
              }),
              !ranges.zeroFill.contains(where: { $0.overlaps(span) }),
              case .file(let offset, let available) = ranges.target(at: referencedAddress),
              available >= byteCount,
              // Require one contiguous file map for all eight bytes.
              (1..<byteCount).allSatisfy({ displacement in
                  guard case .file(let following, _) = ranges.target(at: referencedAddress + UInt64(displacement))
                  else { return false }
                  return following >= offset && following - offset == displacement
              }),
              offset >= 0,
              UInt64(offset) >= UInt64(descriptorSection.layout.offset),
              UInt64(offset) - UInt64(descriptorSection.layout.offset) == referencedAddress - descriptorSection.layout.addr,
              let bytes: [UInt8] = try? machO.readElements(offset: offset, numberOfElements: byteCount)
        else { return nil }
        return decode(bytes, at: referencedAddress, expectedEntry: expectedEntry) { target in
            guard functionStarts.contains(target),
                  let section = CodeSection.containing(target, in: codeSections),
                  section.range.upperBound - target >= 4,
                  case .file(let codeOffset, let available) = ranges.target(at: target), available >= 4,
                  !ranges.zeroFill.contains(where: { $0.overlaps(target..<(target + 4)) }),
                  let codeBytes: [UInt8] = try? machO.readElements(offset: codeOffset, numberOfElements: 4)
            else { return false }
            return codeBytes.count == 4
        }
    }

    /// Arithmetic and encoding independent of file/image boundary discovery.
    static func decode(
        _ bytes: [UInt8], at address: UInt64, expectedEntry: UInt64? = nil,
        provesEntry: (UInt64) -> Bool
    ) -> Self? {
        guard bytes.count == byteCount, address.isMultiple(of: 4),
              !address.addingReportingOverflow(UInt64(byteCount)).overflow else { return nil }
        let displacement = Int32(bitPattern: word(bytes, 0))
        let (entry, overflow) = displacement < 0
            ? address.subtractingReportingOverflow(UInt64(displacement.magnitude))
            : address.addingReportingOverflow(UInt64(displacement.magnitude))
        guard !overflow, displacement != 0, entry.isMultiple(of: 4),
              !(address..<(address + UInt64(byteCount))).contains(entry),
              expectedEntry.map({ $0 == entry }) ?? true,
              provesEntry(entry) else { return nil }
        // The record's size field is a requirement, even when it is zero
        // or does not fit a future role's header/allocator assumptions.
        return Self(address: address, entry: entry, requiredContextSize: word(bytes, 4))
    }

    /// Prove absence of chained pointers in the whole owning segment without
    /// interpreting unsupported pointer formats or accepting a partial walk.
    static func hasNoTextFixups(in machO: MachOFile) -> Bool {
        guard !machO.isLoadedFromDyldCache else { return false }
        let commands = Array(machO.loadCommands)
        guard !commands.contains(where: { command in
            switch command {
            case .dyldInfo, .dyldInfoOnly: return true
            case .dysymtab(let info): return info.layout.nextrel != 0 || info.layout.nlocrel != 0
            default: return false
            }
        }) else { return false }
        let commandsWithFixups = commands.compactMap { command -> (Int, Int)? in
            guard case .dyldChainedFixups(let info) = command else { return nil }
            return (Int(info.layout.dataoff), Int(info.layout.datasize))
        }
        let segments = Array(machO.segments64)
        let textOrdinals = segments.indices.filter { segments[$0].segmentName == "__TEXT" }
        guard commandsWithFixups.count == 1, let (offset, length) = commandsWithFixups.first,
              textOrdinals.count == 1, let text = textOrdinals.first, length >= 28,
              segments.contains(where: { segment in
                  segment.segmentName == "__LINKEDIT"
                      && covers(UInt64(offset), count: length, start: segment.layout.fileoff,
                                size: segment.layout.filesize)
              }),
              let header: [UInt8] = try? machO.readElements(offset: offset, numberOfElements: 28),
              header.count == 28, let start = startsOffset(in: header),
              start <= length, length - start >= 4,
              segments.count <= (length - start - 4) / 4,
              let directory: [UInt8] = try? machO.readElements(offset: offset + start,
                    numberOfElements: 4 + segments.count * 4)
        else { return false }
        guard noStarts(in: directory, segmentCount: segments.count, ordinal: text),
              let imageBase = machO.preferredLoadAddress else { return false }
        let textLayout = segments[text].layout
        guard let textVM = checkedRange(textLayout.vmaddr, size: textLayout.vmsize),
              let textFile = checkedRange(textLayout.fileoff, size: textLayout.filesize)
        else { return false }

        // The starts record also identifies its segment by a VM offset.
        // Reject contradictory ownership before trusting the empty TEXT slot.
        let startsHeaderLength = 22
        let startsLength = length - start
        var occupied: [Range<Int>] = []
        for (ordinal, segment) in segments.enumerated() {
            let location = Int(word(directory, 4 + ordinal * 4))
            if location == 0 { continue }
            guard location >= directory.count, location <= startsLength,
                  startsLength - location >= startsHeaderLength,
                  let prefix: [UInt8] = try? machO.readElements(
                    offset: offset + start + location, numberOfElements: startsHeaderLength),
                  prefix.count == startsHeaderLength
            else { return false }
            let recordSize = Int(word(prefix, 0))
            guard (startsHeaderLength...(startsLength - location)).contains(recordSize) else { return false }
            let record = location..<(location + recordSize)
            guard !occupied.contains(where: { $0.overlaps(record) }) else { return false }
            occupied.append(record)

            let claimedOffset = UInt64(word(prefix, 8)) | (UInt64(word(prefix, 12)) << 32)
            let (claimedVM, overflow) = imageBase.addingReportingOverflow(claimedOffset)
            let layout = segment.layout
            guard !overflow, claimedVM == layout.vmaddr,
                  segments.filter({ $0.layout.vmaddr == claimedVM && $0.layout.vmsize != 0 }).count == 1,
                  let vm = checkedRange(layout.vmaddr, size: layout.vmsize), !vm.overlaps(textVM),
                  let file = checkedRange(layout.fileoff, size: layout.filesize), !file.overlaps(textFile)
            else { return false }
        }
        return true
    }

    static func noStarts(in directory: [UInt8], segmentCount: Int, ordinal: Int) -> Bool {
        guard directory.count >= 4, (directory.count - 4).isMultiple(of: 4),
              segmentCount == (directory.count - 4) / 4,
              (0..<segmentCount).contains(ordinal), Int(word(directory, 0)) == segmentCount
        else { return false }
        return word(directory, 4 + ordinal * 4) == 0
    }

    private static func startsOffset(in header: [UInt8]) -> Int? {
        guard word(header, 0) == 0 else { return nil }
        let offset = Int(word(header, 4))
        return offset >= 28 && offset.isMultiple(of: 4) ? offset : nil
    }

    private static func word(_ bytes: [UInt8], _ i: Int) -> UInt32 {
        UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8
            | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
    }

    private static func checkedRange(_ start: UInt64, size: UInt64) -> Range<UInt64>? {
        let (end, overflow) = start.addingReportingOverflow(size)
        return !overflow && end > start ? start..<end : nil
    }

    private static func covers(_ address: UInt64, count: Int, start: UInt64, size: UInt64) -> Bool {
        address >= start && size >= UInt64(count) && address - start <= size - UInt64(count)
    }
}

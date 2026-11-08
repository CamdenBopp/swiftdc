import Foundation
import MachOKit

/// Which VM addresses of a standalone Mach-O hold bytes in the file.
///
/// MachOKit's `fileOffset(of:)` maps an address as if its whole segment were
/// file-backed. An address in a zero-fill section (`__bss`, `__common`) has no
/// file bytes, and its "offset" can lie past the end of the file: on Prime
/// Video's arm64 slice, `__common` starts 128 KB beyond it. A read there either
/// traps (`try!` in a dependency) or, through `strlen`, faults on whatever page
/// follows the mapping; that depends on the process's memory layout, so it
/// failed in some runs and not others.
struct FileBackedRanges {
    struct Segment {
        let vm: Range<UInt64>
        /// The header-relative file offset of `vm.lowerBound`.
        let fileOffset: UInt64
        /// The VM address where the segment's file bytes end.
        let fileEnd: UInt64
    }

    let base: UInt64
    let segments: [Segment]
    let zeroFill: [Range<UInt64>]

    /// Nil for an image read out of a dyld shared cache, whose file offsets are
    /// cache-relative and are read through the cache instead.
    init?(standalone machO: MachOFile) {
        guard !machO.isLoadedFromDyldCache else { return nil }
        let segments = machO.segments64
        base = UInt64(segments.first { $0.segmentName == "__TEXT" }?.virtualMemoryAddress ?? 0)
        self.segments = segments.map { segment in
            let start = UInt64(segment.virtualMemoryAddress)
            return Segment(
                vm: start ..< start + UInt64(segment.virtualMemorySize),
                fileOffset: UInt64(segment.fileOffset),
                fileEnd: start + UInt64(segment.fileSize)
            )
        }
        zeroFill = machO.sections64.compactMap { section in
            switch section.flags.type {
            case .zerofill?, .gb_zerofill?, .thread_local_zerofill?:
                let start = UInt64(section.address)
                return start ..< start + UInt64(section.size)
            default:
                return nil
            }
        }
    }

    /// The header-relative file offset of `address` and how many file bytes
    /// follow it in its segment, or nil when the address has none.
    func fileBytes(at address: UInt64) -> (offset: Int, available: Int)? {
        guard let segment = segments.first(where: { $0.vm.contains(address) }),
              address < segment.fileEnd,
              !zeroFill.contains(where: { $0.contains(address) })
        else { return nil }
        let delta = address - segment.vm.lowerBound
        return (Int(segment.fileOffset + delta), Int(segment.fileEnd - address))
    }

    func holdsBytes(at address: UInt64, count: Int) -> Bool {
        (fileBytes(at: address)?.available ?? 0) >= count
    }
}

extension MachOFile {
    /// The NUL-terminated string at `address`, scanned only through the bytes
    /// the file holds there and at most `maxLength` of them. Nil when the
    /// address has no file bytes or no terminator is found within them.
    func fileBackedCString(
        at address: UInt64, ranges: FileBackedRanges, maxLength: Int = 4096
    ) -> String? {
        guard let (offset, available) = ranges.fileBytes(at: address) else { return nil }
        let limit = min(available, maxLength)
        // `readElements` is bounds-checked (it throws past the mapping), where
        // `readString(offset:)` runs `strlen` on a raw pointer. Most strings are
        // short, so the window starts small and doubles.
        var window = min(64, limit)
        while window > 0 {
            let bytes: [UInt8]
            do { bytes = try readElements(offset: offset, numberOfElements: window) } catch { return nil }
            if let end = bytes.firstIndex(of: 0) {
                return String(decoding: bytes[..<end], as: UTF8.self)
            }
            guard window < limit else { return nil }
            window = min(window * 2, limit)
        }
        return nil
    }
}

// MARK: - Relative pointers

extension FileBackedRanges {
    /// The ranges of a thin image, from the segment table the preflight
    /// reads out of its load commands.
    init(segments entries: [MachOPreflight.SegmentEntry]) {
        base = entries.first { $0.name == "__TEXT" }?.vmaddr ?? 0
        segments = entries.compactMap { entry in
            let (end, overflow) = entry.vmaddr.addingReportingOverflow(entry.vmsize)
            guard !overflow else { return nil }
            // A filesize past the vmsize maps no more than the vmsize.
            return Segment(
                vm: entry.vmaddr ..< end, fileOffset: entry.fileoff,
                fileEnd: entry.vmaddr + min(entry.filesize, entry.vmsize)
            )
        }
        zeroFill = entries.flatMap(\.zeroFill)
    }

    /// Every byte of a `fileSize`-byte file at the address equal to its
    /// offset: one segment, one slide. What the preflight's table checks
    /// assumed before they mapped through segments, and what their
    /// synthetic tests still describe.
    init(identityOver fileSize: Int) {
        base = 0
        let size = UInt64(max(fileSize, 0))
        segments = [Segment(vm: 0 ..< size, fileOffset: 0, fileEnd: size)]
        zeroFill = []
    }

    /// Where an address lies.
    enum Target: Equatable {
        /// In file bytes: the header-relative file offset holding it, and how
        /// many file bytes follow in its segment.
        case file(offset: Int, available: Int)
        /// In a segment, in memory the loader fills with zeros: a section of
        /// a zero-fill type, or past the segment's file bytes (vmsize >
        /// filesize). No file byte belongs to it.
        case zeroFill
        /// In no segment, or past the end of the address space.
        case unmapped
    }

    func target(at address: UInt64) -> Target {
        let holding = segments.filter { $0.vm.contains(address) }
        // Two segments over one address: which bytes are meant is unknown.
        guard holding.count == 1, let segment = holding.first else { return .unmapped }
        guard address < segment.fileEnd, !zeroFill.contains(where: { $0.contains(address) }) else {
            return .zeroFill
        }
        let (offset, overflow) = segment.fileOffset.addingReportingOverflow(address - segment.vm.lowerBound)
        guard !overflow, let fileOffset = Int(exactly: offset), let available = Int(exactly: segment.fileEnd - address)
        else { return .unmapped }
        return .file(offset: fileOffset, available: available)
    }

    /// The VM address of the byte at header-relative file offset `offset`,
    /// or nil when no segment's file bytes hold it, or more than one does.
    func address(ofFileOffset offset: Int) -> UInt64? {
        guard offset >= 0 else { return nil }
        let offset = UInt64(offset)
        let holding = segments.filter { segment in
            let size = segment.fileEnd - segment.vm.lowerBound
            return offset >= segment.fileOffset && offset - segment.fileOffset < size
        }
        guard holding.count == 1, let segment = holding.first else { return nil }
        return segment.vm.lowerBound + (offset - segment.fileOffset)
    }

    /// Where a relative pointer stored at header-relative file offset
    /// `place` leads. The displacement is in VM space, so the pointer's
    /// address is found first and the target is mapped back through its own
    /// segment: `place + displacement` is the target's file offset only when
    /// both lie in segments with one slide. A target past the address space
    /// is unmapped, never wrapped.
    func relativeTarget(fromFileOffset place: Int, displacement: Int64) -> Target {
        guard let pointer = address(ofFileOffset: place) else { return .unmapped }
        let (address, overflow) = displacement >= 0
            ? pointer.addingReportingOverflow(displacement.magnitude)
            : pointer.subtractingReportingOverflow(displacement.magnitude)
        guard !overflow else { return .unmapped }
        return target(at: address)
    }
}

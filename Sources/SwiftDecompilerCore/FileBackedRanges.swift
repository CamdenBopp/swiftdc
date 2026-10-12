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

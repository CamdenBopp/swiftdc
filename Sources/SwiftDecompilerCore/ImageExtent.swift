import MachOKit

/// The addresses one shared-cache image owns.
///
/// A cache's references resolve across images, which a file's do not: a
/// bound pointer on disk is an import, and in the cache it is an address in
/// the image that exports it. Metadata read through one lands in another
/// image's records, so a reader that lists what an image declares has to ask
/// whether a record it reached is this image's. Nil for a standalone file,
/// where every record the file holds is its own.
///
/// `__LINKEDIT` is shared by every image of a subcache, so it says nothing
/// about ownership.
struct ImageExtent {
    private let ranges: [Range<UInt64>]
    private let regionStart: UInt64

    init?(cacheImage machO: MachOFile) {
        guard let cache = machO.cache else { return nil }
        self.init(
            segments: machO.loadCommands.infos(of: LoadCommand.segment64)
                .filter { $0.segmentName != "__LINKEDIT" }
                .map { UInt64($0.vmaddr) ..< UInt64($0.vmaddr) + UInt64($0.vmsize) },
            regionStart: UInt64(cache.mainCacheHeader.sharedRegionStart))
    }

    init(segments: [Range<UInt64>], regionStart: UInt64) {
        self.ranges = segments
        self.regionStart = regionStart
    }

    func contains(address: UInt64) -> Bool {
        ranges.contains { $0.contains(address) }
    }

    /// `offset` as a cache image's records give it, from the region's start.
    func contains(cacheOffset offset: Int) -> Bool {
        offset >= 0 && contains(address: regionStart + UInt64(offset))
    }
}

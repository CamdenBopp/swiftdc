import MachOKit

/// Rebase targets for a run of pointer slots, read with one walk of the
/// chained-fixup chains instead of one `resolveRebase(at:)` per slot.
///
/// MachOKit's `resolveRebase(at:)` walks the slot's page chain from the page
/// start on every call. Slots packed 8 bytes apart, like `__objc_selrefs`,
/// make that quadratic per page: Keynote's `objc` spent every sampled moment
/// of two 15 s windows inside it, under `ObjCSelectors.selectorTable`.
struct ChainedRebases {
    /// Slot file offset → image-relative runtime offset, for each slot in the
    /// requested range that holds a rebase. A bind or an unfixed slot is absent,
    /// exactly where `resolveRebase(at:)` returns nil.
    let targets: [Int: UInt64]

    /// Nil when the image has no chained fixups: then there is no chain to
    /// walk, and the caller keeps its per-slot path.
    init?(fileOffsets: Range<Int>, in machO: MachOFile) {
        guard let fixups = machO.dyldChainedFixups, let starts = fixups.startsInImage else { return nil }
        var targets: [Int: UInt64] = [:]
        for segment in fixups.startsInSegments(of: starts) {
            for pointer in fixups.pointers(of: segment, in: machO)
            where fileOffsets.contains(pointer.offset) && pointer.fixupInfo.rebase != nil {
                targets[pointer.offset] = pointer.rebaseTargetRuntimeOffset(for: machO)
            }
        }
        self.targets = targets
    }
}

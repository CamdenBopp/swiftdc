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

    /// Nil when the image has neither chained fixups nor rebase opcodes:
    /// then the caller keeps its per-slot path.
    init?(fileOffsets: Range<Int>, in machO: MachOFile) {
        guard let fixups = machO.dyldChainedFixups, let starts = fixups.startsInImage else {
            guard let opcode = Self.opcodeTargets(in: machO) else { return nil }
            targets = opcode.filter { fileOffsets.contains($0.key) }
            return
        }
        var targets: [Int: UInt64] = [:]
        for segment in fixups.startsInSegments(of: starts) {
            for pointer in fixups.pointers(of: segment, in: machO)
            where fileOffsets.contains(pointer.offset) && pointer.fixupInfo.rebase != nil {
                targets[pointer.offset] = pointer.rebaseTargetRuntimeOffset(for: machO)
            }
        }
        self.targets = targets
    }

    /// Every pointer rebase of an image that rebases by opcode
    /// (`LC_DYLD_INFO`, a deployment target below macOS 12 or iOS 15), slot
    /// file offset to image-relative target. Such a slot holds its target's
    /// unslid address on disk, but only a slot the rebase opcodes list is a
    /// pointer: a bound slot holds zero or an addend. Without this, every
    /// selector reference and CFString of such an image went unread, and a
    /// send rendered as an unresolved call. Nil for an image with chained
    /// fixups or no rebase opcodes, and for opcodes naming a segment the
    /// image lacks; a slot past its segment's file bytes or below the image
    /// base is left out.
    static func opcodeTargets(in machO: MachOFile) -> [Int: UInt64]? {
        guard machO.dyldChainedFixups == nil, machO.is64Bit, machO.rebaseOperations != nil else { return nil }
        let segments = Array(machO.segments64)
        let base = machO.address(forOffset: 0)
        var targets: [Int: UInt64] = [:]
        for rebase in machO.rebases where rebase.type == .pointer {
            guard segments.indices.contains(rebase.segmentIndex) else { return nil }
            let segment = segments[rebase.segmentIndex]
            let offset = segment.fileOffset + Int(rebase.segmentOffset)
            guard Int(rebase.segmentOffset) + 8 <= segment.fileSize,
                  let bytes: [UInt8] = try? machO.readElements(offset: offset, numberOfElements: 8), bytes.count == 8
            else { continue }
            let value = bytes.enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << (8 * UInt64($1.offset))) }
            // Each reader validates the target itself (a selector must land
            // in `__objc_methname`, a string in the file's bytes).
            guard value >= base else { continue }
            targets[offset] = value - base
        }
        return targets
    }
}

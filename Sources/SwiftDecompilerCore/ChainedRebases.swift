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
    ///
    /// The opcodes are interpreted here, not through MachOKit's `rebases`,
    /// which builds one entry per repetition with no bound: a malformed
    /// `DO_REBASE_ULEB_TIMES 2^28` grew past 3 GB, and a segment offset of
    /// 2^63 trapped converting to `Int`. A stream that does more work than
    /// its segments have pointer slots is malformed and claims nothing.
    static func opcodeTargets(in machO: MachOFile) -> [Int: UInt64]? {
        guard machO.dyldChainedFixups == nil, machO.is64Bit,
              let operations = machO.rebaseOperations else { return nil }
        let segments = Array(machO.segments64)
        let base = machO.address(forOffset: 0)
        let pointerSize: UInt = 8
        let budget = segments.reduce(1024) { $0 + max($1.fileSize, 0) / 8 }
        var work = 0
        var type: RebaseType = .pointer
        var segmentIndex = 0
        var segmentOffset: UInt = 0
        var targets: [Int: UInt64] = [:]

        /// One rebase at the cursor. False ends the stream: over budget, or
        /// a segment the image lacks.
        func rebase() -> Bool {
            work += 1
            guard work <= budget, segments.indices.contains(segmentIndex) else { return false }
            guard type == .pointer else { return true }
            let segment = segments[segmentIndex]
            let size = UInt(max(segment.fileSize, 0))
            guard segmentOffset < size, size - segmentOffset >= pointerSize else { return true }
            let (offset, overflow) = segment.fileOffset.addingReportingOverflow(Int(segmentOffset))
            guard !overflow, let bytes: [UInt8] = try? machO.readElements(offset: offset, numberOfElements: 8), bytes.count == 8
            else { return true }
            let value = bytes.enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << (8 * UInt64($1.offset))) }
            // Each reader validates the target itself (a selector must land
            // in `__objc_methname`, a string in the file's bytes).
            if value >= base { targets[offset] = value - base }
            return true
        }
        func repeated(_ count: UInt, skip: UInt) -> Bool {
            for _ in 0 ..< count {
                guard rebase() else { return false }
                segmentOffset = segmentOffset &+ pointerSize &+ skip
            }
            return true
        }

        for operation in operations {
            switch operation {
            case .done:
                return targets
            case .set_type_imm(let value):
                type = value
            case .set_segment_and_offset_uleb(let segment, let offset):
                segmentIndex = segment
                segmentOffset = offset
            case .add_addr_uleb(let offset):
                segmentOffset = segmentOffset &+ offset
            case .add_addr_imm_scaled(let scale):
                segmentOffset = segmentOffset &+ scale &* pointerSize
            case .do_rebase_imm_times(let count), .do_rebase_uleb_times(let count):
                guard repeated(count, skip: 0) else { return nil }
            case .do_rebase_add_addr_uleb(let offset):
                guard rebase() else { return nil }
                segmentOffset = segmentOffset &+ pointerSize &+ offset
            case .do_rebase_uleb_times_skipping_uleb(let count, let skip):
                guard repeated(count, skip: skip) else { return nil }
            }
        }
        return targets
    }
}

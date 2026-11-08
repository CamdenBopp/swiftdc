import Testing
import Foundation
import MachOKit
@testable import SwiftDecompilerCore

/// `ChainedRebases` replaces one `resolveRebase(at:)` per slot (a walk of the
/// page chain from its start each time, which made Keynote's selector table
/// quadratic) with one walk of every chain. It must give the same answer for
/// every slot: the rebase target where there is a rebase, and nothing where
/// `resolveRebase` returns nil (a bind, or a slot no fixup touches).
@Test func agreesWithPerSlotRebaseResolutionIfPresent() throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let segments = machO.segments64.filter { $0.segmentName.hasPrefix("__DATA") }
    #expect(!segments.isEmpty)

    let rebases = try #require(ChainedRebases(
        fileOffsets: 0 ..< Int.max, in: machO
    ), "the fixture uses chained fixups")

    var rebased = 0, unrebased = 0
    for segment in segments {
        let start = Int(segment.fileoff)
        for offset in stride(from: start, to: start + Int(segment.filesize), by: 8) {
            let expected = machO.resolveRebase(at: UInt64(offset))
            #expect(rebases.targets[offset] == expected, "slot at file offset 0x\(String(offset, radix: 16))")
            if expected == nil { unrebased += 1 } else { rebased += 1 }
        }
    }
    // Both answers occur, so neither half of the comparison is vacuous.
    #expect(rebased > 20)
    #expect(unrebased > 20)

    // The selector table built on it resolves almost every selector reference.
    // A bind or a non-selector-shaped string may legitimately not resolve.
    let table = ObjCSelectors.selectorTable(in: machO)
    let selrefs = try #require(machO.sections64.first { $0.sectionName == "__objc_selrefs" })
    let slotCount = selrefs.size / 8
    #expect(table.bySelref.count >= slotCount - 2)
    #expect(table.bySelref.count <= slotCount)
}

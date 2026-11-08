import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

/// The chained-fixup table answers exactly what MachOKit's per-lookup
/// `resolveBind(at:)` and `resolveRebase(at:)` do, for every chained pointer
/// (binds and rebases alike) of every fixture image, and nil off any chain.
@Test func chainedFixupTableMatchesMachOKitIfPresent() throws {
    let directory = "Fixtures/Sample"
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    var binds = 0
    var rebases = 0
    var images = 0
    for entry in entries.sorted() where entry.hasSuffix(".dylib") {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(entry)
        guard case .machO(let machO) = try MachOKit.loadFromFile(url: url),
              let fixups = machO.dyldChainedFixups, let starts = fixups.startsInImage
        else { continue }
        images += 1
        let table = Disassembler.ChainedFixupTable()
        var offsets: [UInt64] = []
        for segment in fixups.startsInSegments(of: starts) {
            offsets += fixups.pointers(of: segment, in: machO).map { UInt64($0.offset) }
        }
        for offset in offsets {
            let expected = machO.resolveBind(at: offset).flatMap { fixups.symbolName(for: $0.0.info.nameOffset) }
            #expect(table.symbol(at: offset, in: machO) == expected, "\(entry) @\(offset)")
            if expected != nil { binds += 1 }
            let rebase = machO.resolveRebase(at: offset)
            #expect(table.rebaseTarget(at: offset, in: machO) == rebase, "\(entry) rebase @\(offset)")
            if rebase != nil { rebases += 1 }
        }
        // An offset no chain holds (the header) is no bind.
        #expect(table.symbol(at: 0, in: machO) == nil)
        #expect(table.rebaseTarget(at: 0, in: machO) == nil)
    }
    if images > 0 {
        #expect(binds > 0, "no fixture image has a chained bind to compare")
        #expect(rebases > 0, "no fixture image has a chained rebase to compare")
    }
}

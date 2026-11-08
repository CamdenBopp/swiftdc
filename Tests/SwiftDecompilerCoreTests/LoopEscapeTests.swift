import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The loop-body pass seeds its lap from the converged header, so a fact
/// that only the back edge brings holds on it (`loopescape.c`, -O0).
/// Seeded from the loop's entry alone, `lateEscape` (whose `&i` escapes at
/// the end of the body, so the next lap's `poke()` may write `i`) claimed
/// `i += 1`, and `staleEntryPointer` (whose `p` points at `j` only on the
/// first lap) claimed `j += 100`. Native: 102 and 202, two laps each, where
/// the claims read as five laps.
@Test func aLoopBodyPassSeedsFromTheConvergedHeaderIfPresent() async throws {
    let path = "Fixtures/Sample/libLoopEscape.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    for name in ["_lateEscape", "_staleEntryPointer"] {
        let function = try #require(functions.first { $0.displayName == name })
        let text = function.renderStructured()
        #expect(text.contains("while ("), "\(name): \(text)")
        for claim in ["var i = 0", "i += 1", "j += 100"] {
            #expect(!text.contains(claim), "\(name) claims \(claim):\n\(text)")
        }
    }
}

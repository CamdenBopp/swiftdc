import Testing
import Foundation
import MachOKit
@testable import SwiftDecompilerCore

/// The whole-image path renders **streaming** — one function decoded, analysed,
/// rendered, and released at a time — to bound peak memory (8–10× lower than
/// holding every function's instructions; see the Performance section of the
/// readiness doc). Its output must stay byte-identical to the array path, since
/// both feed the same `disasm --image` command in different memory regimes.
///
/// The host golden hashes prove that on a real cache image, but only where the
/// dyld cache is present. This locks the same invariant **portably** on a built
/// fixture: the streamed blocks, joined, must exactly equal the array path's
/// blocks joined — for every render mode. If a future change makes the two
/// diverge (a different resolver, a mis-cut boundary), this fails on a clean
/// checkout, not only on a machine with the cache.

private let fixture = "Fixtures/Sample/libReconstruction.dylib"

private func loadFixture() -> MachOFile? {
    guard FileManager.default.fileExists(atPath: fixture) else { return nil }
    return try? BinaryLoader.load(path: fixture)
}

/// Compare the streamed join to the array-path join for one render mode.
private func assertStreamMatchesArray(
    _ machO: MachOFile, mode: String, render: @escaping (DisassembledFunction) -> String
) async {
    let array = await withStableDependencies {
        await Disassembler(preset: .default).disassemble(machO: machO)
    }
    let arrayJoined = array.map(render).joined(separator: "\n\n")
    let streamed = await withStableDependencies {
        await Disassembler(preset: .default).disassembleStreamingRender(machO: machO, render: render)
    }
    let streamJoined = streamed.joined(separator: "\n\n")

    #expect(
        streamJoined == arrayJoined,
        """
        [\(mode)] streaming output differs from the array path \
        (\(arrayJoined.count) vs \(streamJoined.count) bytes, \
        \(array.count) vs \(streamed.count) functions). The two paths must be \
        byte-identical — most likely a boundary mis-cut or a resolver difference.
        """
    )
}

@Test func streamingMatchesTheArrayPathForEveryModeIfPresent() async throws {
    guard let machO = loadFixture() else { return }
    await assertStreamMatchesArray(machO, mode: "text") { $0.render() }
    await assertStreamMatchesArray(machO, mode: "structured") { $0.renderStructured() }
    await assertStreamMatchesArray(machO, mode: "pseudo") { $0.renderPseudo() }
    await assertStreamMatchesArray(machO, mode: "cfg") { $0.renderCFG() }
}

@Test func streamingProgressReachesTheTotalIfPresent() async throws {
    guard let machO = loadFixture() else { return }
    // @unchecked because the closure runs synchronously within the awaited call,
    // never concurrently — there is no actual data race.
    final class Box: @unchecked Sendable { var pairs: [(Int, Int)] = [] }
    let box = Box()
    let blocks = await Disassembler(preset: .default).disassembleStreamingRender(
        machO: machO, render: { $0.render() },
        progress: { done, total in box.pairs.append((done, total)) }
    )

    let pairs = box.pairs
    #expect(!pairs.isEmpty, "progress was never reported")
    // Monotonic non-decreasing `done`, a single stable `total`.
    #expect(zip(pairs, pairs.dropFirst()).allSatisfy { $0.0 <= $1.0 }, "done went backwards: \(pairs)")
    #expect(Set(pairs.map(\.1)).count == 1, "total changed mid-run: \(Set(pairs.map(\.1)))")
    // The last report must reach the total (the final position is always sent).
    #expect(pairs.last?.0 == pairs.last?.1, "final progress \(pairs.last!) did not reach the total")
    // The total is an upper bound on produced functions (empty spans are skipped).
    #expect(blocks.count <= (pairs.last?.1 ?? 0), "produced more functions than the reported total")
}

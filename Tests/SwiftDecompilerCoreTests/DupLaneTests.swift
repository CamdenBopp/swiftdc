import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `dup` was modelled as one value in each eight-byte word whatever its
/// lane width, so `dup v0.4s, w0` (clang -O2 filling an `int[8]`, then
/// `stp q0, q0, [sp]`) held w0 in each word, though each word is
/// `w0 | w0 << 32`: `dup_lanes.c`'s `fillInts` read one word back and
/// rendered `sink((r0 & 0xffffffff))`. Only an eight-byte lane
/// (`dup v0.2d, x0`, `fillLongs`) is modelled now.
@Test func aDupIntoNarrowLanesHoldsNoWordIfPresent() async throws {
    let path = "Fixtures/Sample/libDupLanes.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderPseudo()
    }
    let ints = try text("_fillInts")
    #expect(ints.contains("sink()") && !ints.contains("sink((r0"), Comment(rawValue: ints))
    let longs = try text("_fillLongs")
    #expect(longs.contains("sink(r0)"), Comment(rawValue: longs))
}

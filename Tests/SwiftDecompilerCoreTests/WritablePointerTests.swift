import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A call through a writable global function pointer names no callee
/// (`writablepointer.c`, -O2). `countdown` loads `next` from `__DATA,__data`
/// and branches to it; the slot's initial value is a rebase to countdown, but
/// `retarget` can store another function there first, so `next(n - 1)` read
/// as `countdown(n - 1)` named a callee the program need not reach. `hook`
/// is the same with a bind to puts as its initial value. `pinned` is the
/// same C in `__DATA_CONST`, which dyld makes read-only after fixups: its
/// initial value is the only one it can hold, and it stays named.
@Test func aCallThroughAWritablePointerNamesNoCalleeIfPresent() async throws {
    let path = "Fixtures/Sample/libWritablePointer.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path)
    }
    func function(_ name: String) throws -> DisassembledFunction {
        try #require(functions.first { $0.symbol == "_" + name }, "no _\(name) in \(functions.map(\.symbol))")
    }
    func branch(in name: String) throws -> Instruction {
        try #require(function(name).instructions.first { $0.text.hasPrefix("br") })
    }

    // A rebase in a writable section.
    let countdownText = try function("countdown").renderPseudo()
    let countdown = try branch(in: "countdown")
    #expect(countdown.callee == nil && countdown.branchTarget == nil, Comment(rawValue: countdownText))
    #expect(!countdownText.contains("countdown("), Comment(rawValue: countdownText))

    // A bind in a writable section.
    let announceText = try function("announce").renderPseudo()
    let announce = try branch(in: "announce")
    #expect(announce.callee == nil, Comment(rawValue: announceText))
    #expect(announce.indirectJumpTarget == "?", Comment(rawValue: announceText))
    #expect(!announceText.contains("puts"), Comment(rawValue: announceText))

    // A rebase in a segment that is read-only after fixups.
    let viaPinnedText = try function("viaPinned").renderPseudo()
    let viaPinned = try branch(in: "viaPinned")
    #expect(viaPinned.callee == "twice", Comment(rawValue: viaPinnedText))
}

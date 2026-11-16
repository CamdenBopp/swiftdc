import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An in-image callee whose body loads from the caller's outgoing area takes
/// stack arguments beyond its registers: `nine(q, 1, …, 7, 100)` read
/// `nine(?)` (`stackargs.c`). Their count is not proven, so the call ends in
/// `…`; a callee that reads no stack argument does not.
@Test(arguments: ["Fixtures/Sample/libStackArgs.dylib", "Fixtures/Sample/libStackArgs.O0.dylib"])
func aCalleeReadingAStackArgumentEndsInEllipsisIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    let nine = try structured("_callNine")
    #expect(nine.range(of: #"nine\([^)]*…\)"#, options: .regularExpression) != nil, Comment(rawValue: nine))
    let two = try structured("_callTwo")
    #expect(two.contains("two(") && !two.contains("…"), Comment(rawValue: two))
}

/// A callee with a frame reads its stack arguments through x29, after a
/// call or a test, or into a callee-saved register it saved itself; each
/// of its calls ends in `…`. Read only through sp on the straight line to
/// the first call or branch, they rendered as complete
/// (`framed(arg0, 1, 2, 3, 4, 5, 6, 7)` at -O0), and a summary rebuilt
/// after its callees' reads were folded in forgot the read anyway.
@Test(arguments: ["Fixtures/Sample/libStackArgs.dylib", "Fixtures/Sample/libStackArgs.O0.dylib",
                  "Fixtures/Sample/libStackArgs.Oz.dylib"])
func aFramedCalleeReadingAStackArgumentEndsInEllipsisIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    for (caller, callee) in [("_callFramed", "framed"), ("_callTested", "tested"), ("_callKept", "kept"),
                             ("_callPassed", "passed")] {
        let text = try structured(caller)
        #expect(text.range(of: "\\b\(callee)\\([^)]*…\\)", options: .regularExpression) != nil, Comment(rawValue: text))
    }
    let two = try structured("_callFramedTwo")
    #expect(two.contains("framedTwo(") && !two.contains("…"), Comment(rawValue: two))
}

/// A summary that gives up its callee-saved claims keeps its stack read:
/// the read is the body's own, not a preservation claim.
@Test func claimingNothingKeepsAStackRead() throws {
    let engine = try #require(CapstoneEngine())
    // ldr x0, [sp]; ret
    let words: [UInt32] = [0xf94003e0, 0xd65f03c0]
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    let function = DisassembledFunction(symbol: "_reads", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
    let summary = try #require(CalleeRegisterSummary.of(function))
    #expect(summary.readsIncomingStack)
    #expect(summary.claimingNothing().readsIncomingStack)
}

/// A reload of a slot the function stored itself is not a stack argument,
/// even at or above its entry sp: `callthrough_frame_fragment` saves x19 at
/// `[sp]` and restores it, and Go spills its register arguments into the
/// caller's area and reloads them. Counted as reads, its call and every Go
/// call ended in `…`.
@Test func aReloadOfItsOwnStoreIsNoStackArgumentIfPresent() async throws {
    let path = "Fixtures/Sample/libABIFrameOwnership.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let callers = functions.map { $0.renderStructured() }.filter { $0.contains("callthrough_frame_fragment(") && !$0.hasPrefix("_callthrough_frame_fragment") }
    #expect(!callers.isEmpty)
    for text in callers {
        #expect(!text.contains("callthrough_frame_fragment(local_40, arg1, …)"), Comment(rawValue: text))
    }
}

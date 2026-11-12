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

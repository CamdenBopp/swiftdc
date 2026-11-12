import Foundation
import Testing
@testable import SwiftDecompilerCore

/// At -O a loop counter lives in a register, not a stack slot, and the body
/// advances it before the test (`add x19, x19, #3; …; cmp x19, #0x3e5`). Only
/// slots were named, so the loop read `if (x19 <ᵁ 0x3e5) { continue }`, a test
/// on a register nothing in the loop changes (`registerloop.swift`).
@Test(arguments: ["Fixtures/Sample/libRegisterLoop.dylib", "Fixtures/Sample/libRegisterLoop.Osize.dylib"])
func aRegisterLoopCounterIsNamedAndSteppedIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    let up = try structured("RegisterLoop.countUp() -> ()")
    for line in ["var i = -3", "RegisterLoop.sink((i + 3))", "((i + 3) < 997)", "i += 3"] {
        #expect(up.contains(line), Comment(rawValue: up))
    }
    #expect(!up.contains("x19"), Comment(rawValue: up))
    // untilLimit's test reads a closure's result and renders raw, so its
    // counter is neither declared nor read by name.
    let until = try structured("RegisterLoop.untilLimit(() -> Swift.Int) -> ()")
    #expect(!until.contains("var i") && !until.contains("(i)") && !until.contains("i += 1"), Comment(rawValue: until))
    // -O unrolls fromTen into five calls; -Osize keeps the loop.
    guard path.hasSuffix(".Osize.dylib") else { return }
    let down = try structured("RegisterLoop.fromTen() -> ()")
    for line in ["var i = 12", "RegisterLoop.sink((i - 2))", "((i - 2) >ᵁ 2)", "i -= 2"] {
        #expect(down.contains(line), Comment(rawValue: down))
    }
}

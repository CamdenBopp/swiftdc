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
    // The flat view declares the counter before the call that reads it.
    let flat = try #require(functions.first { $0.displayName == "RegisterLoop.countUp() -> ()" }).renderPseudo()
    let declared = try #require(flat.range(of: "var i = -3"), Comment(rawValue: flat))
    let read = try #require(flat.range(of: "RegisterLoop.sink((i + 3))"), Comment(rawValue: flat))
    #expect(declared.lowerBound < read.lowerBound, Comment(rawValue: flat))
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

/// The flat view declares a loop's counters on the instruction that enters
/// the loop, but only where that comes before every block of the loop:
/// declared below the loop, `--pseudo` would read `i` and declare it after.
@Test func aLoopCounterIsDeclaredBeforeItsLoopOnlyInAddressOrder() throws {
    func analysis(_ words: [UInt32]) throws -> FunctionAnalysis {
        let engine = try #require(CapstoneEngine())
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        let function = DisassembledFunction(symbol: "_counter", demangledName: nil, startAddress: 0x1000,
            instructions: decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                            branchTarget: $0.branchTarget, detail: $0.detail)
            }, source: .symbol)
        return ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: [:]))
    }
    // mov x8, #0; L: add x8, x8, #1; cmp x8, #10; b.lt L; ret
    let ahead = try analysis([0xd2800008, 0x91000508, 0xf100291f, 0x54ffffcb, 0xd65f03c0])
    #expect(ahead.loopInitializations[0x100c]?.map(\.name) == ["i"])
    #expect(ahead.loopEntryDeclarations[0x1000]?.map(\.name) == ["i"])
    // b P; L: add x8, x8, #1; cmp x8, #10; b.lt L; ret; P: mov x8, #0; b L
    let below = try analysis([0x14000005, 0x91000508, 0xf100291f, 0x54ffffcb, 0xd65f03c0, 0xd2800008, 0x17fffffb])
    #expect(below.loopInitializations[0x100c]?.map(\.name) == ["i"])
    #expect(below.loopEntryDeclarations.isEmpty)
}

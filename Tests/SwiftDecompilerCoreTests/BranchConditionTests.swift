import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A branch reads the flags of the last instruction that set them. The
/// structurer's text path walked back to the nearest `cmp`/`tst` and stepped
/// over flag setters it does not model, so the condition came from the wrong
/// compare. Reduced from an app audit (`Fixtures/Sample/conditions.swift`):
///
///     touches (-Osize)  cmp x0, x1; ccmp x0, x2, #0, ge; b.ge   rendered `x0 < x1`
///     selThenFloat      cmp x0, #5; fcsel; fcmp d0, d2; b.pl     rendered `(x0 - 5) < 0`
///     setStatus         cmp x0, x21; ccmp x1, x19, #0, eq; b.eq  rendered `self.status != x21`
///
/// Each now declines (`?`): the true condition needs the conditional compare
/// modelled, and a wrong one is worse than none.
@Test func aBranchOnAnUnmodelledFlagSetterDeclinesIfPresent() async throws {
    for level in ["opt", "osize"] {
        let path = "Fixtures/Sample/libConditions.\(level).dylib"
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "Conditions")
        }
        func render(_ name: String) throws -> String {
            try #require(functions.first { $0.displayName.hasPrefix("Conditions.\(name)") }).renderStructured()
        }
        let float = try render("selThenFloat")
        #expect(!float.contains("(x0 - 5)"), "\(level): \(float)")
        let string = try render("Model.setStatus")
        #expect(!string.contains("!= x21"), "\(level): \(string)")
        #expect(!string.contains("!?"), "\(level): a declined condition inverts to itself: \(string)")
        if level == "osize" {
            let range = try render("touches")
            #expect(!range.contains("x0 < x1"), "\(level): \(range)")
        }
    }
}

/// `b.hi`/`b.hs`/`b.lo`/`b.ls` compare unsigned. `(10...20).contains(p[3])`
/// lowers to `sub x8, x8, #10; cmp x8, #10; b.hi`, which rendered `x8 > 0xa`:
/// as a signed test it is false for every p[3] below 10, where the binary
/// takes the branch.
@Test func aCarryConditionRendersUnsignedIfPresent() async throws {
    for level in ["opt", "osize"] {
        let path = "Fixtures/Sample/libConditions.\(level).dylib"
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "Conditions.rng")
        }
        let text = try #require(functions.first).renderStructured()
        #expect(text.contains("x8 >\u{1D41} 0xa") || text.contains("x8 <=\u{1D41} 0xa"), "\(level): \(text)")
        #expect(!text.contains("x8 > 0xa"), "\(level): \(text)")
    }
}

@Test func theCarryConditionsMapToUnsignedOperators() {
    #expect(ControlFlowStructure.inverted("a >\u{1D41} b") == "a <=\u{1D41} b")
    #expect(ControlFlowStructure.inverted("?") == "?")
}

/// The tracer invalidates the flags on every instruction that writes them
/// (Capstone's `updatesFlags`), not on a list: the list missed `ngcs` and
/// `negs`, so `cmp x0, #1; ngcs xzr, x2; cset w0, lt` (a 128-bit compare)
/// returned `x0 < 1`, the low word's comparison. Assembled with
/// `xcrun clang -arch arm64 -c`, decoded at 0x3000:
///
///     f: cmp x0, #1; ngcs xzr, x2; cset w0, lt; ret
///     g: cmp x0, #1; negs x9, x2;  cset w0, lt; ret
@Test func aFlagSetterTheTracerDoesNotModelForgetsTheComparison() throws {
    let words: [UInt32] = [0xf100041f, 0xfa0203ff, 0x1a9fa7e0, 0xd65f03c0,
                           0xf100041f, 0xeb0203e9, 0x1a9fa7e0, 0xd65f03c0]
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x3000)
    try #require(decoded.count == words.count)
    for start in [UInt64(0x3000), 0x3010] {
        let body = decoded.filter { $0.address >= start && $0.address < start + 16 }.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: "f", demangledName: nil, startAddress: start,
                                            instructions: body, source: .symbol)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x2": 1]))
        let ret = try #require(body.last)
        let value = analysis.exitValues[ret.address]
        #expect(value == nil || value == .unknown, "0x\(String(start, radix: 16)): returned \(String(describing: value))")
    }
}

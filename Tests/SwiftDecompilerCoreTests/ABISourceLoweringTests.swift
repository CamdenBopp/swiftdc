import Foundation
import Testing
@testable import SwiftDecompilerCore

// Recovered from the pre-merge stash (d921fc1, improve/source-findings).

private let abiSourceDebug = "Fixtures/Sample/libABISource.dylib"
private let abiSourceOptimized = "Fixtures/Sample/libABISource.opt.dylib"
private let abiSourceResilient = "Fixtures/Sample/libABISource.resilient.dylib"
private let abiSourceOracle = "Fixtures/Sample/abi-source-oracle"
private let abiSourceResilientOracle = "Fixtures/Sample/abi-source-resilient-oracle"

private func abiSourcePseudo(_ filter: String, in path: String) async throws -> String? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: filter)
    }
    return functions.map { $0.renderPseudo() }.joined(separator: "\n")
}

// Concurrent metadata scans crashed in MachOKit's chained-fixup page traversal
// on this host. Keep this fixture's disassemblies serial within the suite.
@Suite(.serialized)
struct ABISourceLoweringTests {
    @Test func nativeABISourceOracleIfPresent() throws {
        guard FileManager.default.fileExists(atPath: abiSourceOracle) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(abiSourceOracle)
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(text.split(whereSeparator: \.isNewline).map(String.init) == [
            "3.5", "13.0", "31.0", "15", "11", "BCDE", "sizes 8 16 40 32 32",
        ])
    }

    @Test func nativeResilientOneWordResultIfPresent() throws {
        guard FileManager.default.fileExists(atPath: abiSourceResilientOracle),
              FileManager.default.fileExists(atPath: abiSourceResilient) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(abiSourceResilientOracle)
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        // First call stores directly through x8; second copies x8 to x10 and
        // stores through the alias. Both execute against the resilient dylib.
        #expect(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == "27\n27\n")
    }

    @Test func resilientOneWordReturnUsesIncomingX8IfPresent() async throws {
        guard let pseudo = try await abiSourcePseudo("abiMakeOne", in: abiSourceResilient) else { return }
        // Native body: `add x9, x0, #17; str x9, [x8]; ret`. The complete
        // resilient result layout is one eight-byte `a` field at offset zero;
        // x0 still holds the seed and is not a return value.
        #expect(pseudo.contains("return ABISource.ABIOneWord(a: (arg0 + 17))"), "Pseudo: \(pseudo)")
        #expect(!pseudo.contains("return arg0"), "Pseudo: \(pseudo)")
    }

    @Test func x8ResultsRenderOnlyWhatTheStoresProveIfPresent() async throws {
        // The stash expected these to decline outright; HEAD's x8 tracking
        // (IndirectResults) proves more, and the native oracle agrees with it.
        // `abiMakeFive` stores four words as two SIMD pairs and one word as an
        // integer: only the integer field is proven.
        if let five = try await abiSourcePseudo("abiMakeFive", in: abiSourceResilient) {
            #expect(five.contains("return ABISource.ABIFiveWords(a: ?, b: ?, c: ?, d: ?, e: (arg0 + 5))"), "Pseudo: \(five)")
        }
        // `mov x10, x8; str x9, [x10]`: the alias is followed. The resilient
        // oracle above executes it and gets 27 for seed 10.
        if let alias = try await abiSourcePseudo("abiMakeAliasedOne", in: abiSourceResilient) {
            #expect(alias.contains("return ABISource.ABIOneWord(a: (arg0 + 17))"), "Pseudo: \(alias)")
        }
        // A SIMD-stored two-word result proves nothing it can render.
        if let two = try await abiSourcePseudo("abiMakeTwo", in: abiSourceResilient) {
            #expect(!two.contains("return "), "Pseudo: \(two)")
        }
        // The nonresilient one-word result is direct (`add x0, x0, #17; ret`),
        // but a nominal type's register class is not proven from its name, so
        // its x0 is not read as the result.
        if let direct = try await abiSourcePseudo("abiMakeOne", in: abiSourceOptimized) {
            #expect(!direct.contains("return "), "Pseudo: \(direct)")
        }
    }

    @Test func nominalFloatingResultDoesNotReuseStaleIntegerResultIfPresent() async throws {
        guard let pseudo = try await abiSourcePseudo("abiOneDoubleFromInt", in: abiSourceOptimized) else { return }
        // Native result: `bl abiAddOne; scvtf d0, x0; fadd d0, d0, #0.5; ret`.
        // x0 still holds abiAddOne's Int and is not the ABIOneDouble result.
        #expect(pseudo.contains("abiOneDoubleFromInt"))
        #expect(pseudo.contains("ABISource.abiAddOne(arg0)"), "Pseudo: \(pseudo)")
        #expect(!pseudo.contains("return ABISource.abiAddOne(arg0)"), "Pseudo: \(pseudo)")
    }

    @Test func valueSelfHFAGetsRegistersAfterFloatingArgumentIfPresent() async throws {
        for path in [abiSourceDebug, abiSourceOptimized] {
            guard let pseudo = try await abiSourcePseudo("ABIVec2.scaled", in: path) else { continue }
            // Native entry: d0=factor, d1=self.x, d2=self.y. At x=2, y=3,
            // factor=5 this expression yields 13; self.x*self.y+factor gives 11.
            #expect(pseudo.contains("ABIVec2.scaled"), "Pseudo: \(pseudo)")
            #expect(pseudo.contains("self.y)"), "Pseudo: \(pseudo)")
            #expect(pseudo.contains("arg0 * self.x") || pseudo.contains("self.x * arg0"), "Pseudo: \(pseudo)")
            #expect(!pseudo.contains("self.x * self.y") && !pseudo.contains("self.y * self.x"), "Pseudo: \(pseudo)")
        }
    }

    @Test func valueSelfHFAGetsRegistersAfterHFAArgumentIfPresent() async throws {
        for path in [abiSourceDebug, abiSourceOptimized] {
            guard let pseudo = try await abiSourcePseudo("ABIVec2.dot", in: path) else { continue }
            // Native entry: d0/d1=other.x/y, d2/d3=self.x/y. The fixture's
            // execution oracle checks dot((2,3), (5,7)) == 31.
            let expected = path == abiSourceDebug
                ? "return ((self.x * arg0.x) + (self.y * arg0.y))"
                : "return ((arg0.x * self.x) + (arg0.y * self.y))"
            #expect(pseudo.contains(expected), "Pseudo: \(pseudo)")
        }
    }

    @Test func unknownNominalResultHasNoAssumedIntegerReturnRegister() {
        let function = DisassembledFunction(
            symbol: "test",
            demangledName: "ABISource.abiOneDoubleFromInt(Swift.Int) -> ABISource.ABIOneDouble",
            startAddress: 0x1000, instructions: [], source: .symbol)
        #expect(Disassembler.swiftReturnRegister(of: function) == nil)
    }

    @Test func indirectResultCallDoesNotInheritTrailingCallerRegisterIfPresent() async throws {
        for path in [abiSourceOptimized, abiSourceResilient] {
            guard let pseudo = try await abiSourcePseudo("abiMaybeFive", in: path) else { continue }
            // Native `abiMaybeFive(seed, yes)` passes only x0=seed to
            // `abiMakeFive(seed)`. x1 still holds `yes`, but is not a formal
            // argument of that call; x8 supplies its result buffer.
            #expect(pseudo.contains("ABISource.abiMakeFive(arg0)"), "Pseudo: \(pseudo)")
            #expect(!pseudo.contains("ABISource.abiMakeFive(arg0, arg1)"), "Pseudo: \(pseudo)")
        }
    }
}

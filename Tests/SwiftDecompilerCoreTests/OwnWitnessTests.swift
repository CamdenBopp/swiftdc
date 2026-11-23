import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `GaugeKit.Tank.level.getter` and its witness for `Gauge.level` share a body
/// because the witness is the function, with nothing to adapt. That is one
/// function described twice. The symbol path read two symbols as a fold and
/// declined, where `MetadataSymbolizer` already read it as one.
private let tank = "GaugeKit.Tank.level.getter : Swift.Int"
private let witness = "protocol witness for GaugeKit.Gauge.level.getter : Swift.Int in conformance GaugeKit.Tank : GaugeKit.Gauge in GaugeKit"

private func behind(_ names: [String: String]) -> String? {
    Disassembler.functionBehindOwnWitnesses(names.keys.sorted()) { names[$0] }
}

@Suite struct OwnWitnessTests {
    @Test func aFunctionAndItsOwnWitnessAreOneFunction() {
        #expect(behind(["_getter": tank, "_getterTW": witness]) == "_getter")
    }

    @Test func aStaticWitnessMatchesAStaticFunction() {
        let function = "static M.T.make() -> M.T"
        let staticWitness = "protocol witness for static M.P.make() -> M.T in conformance M.T : M.P in M"
        #expect(behind(["_a": function, "_aTW": staticWitness]) == "_a")
        #expect(behind(["_a": "M.T.make() -> M.T", "_aTW": staticWitness]) == nil)
    }

    /// `md_ms.ImplS.y()` folded with the witness for `Impl2.x()`: two members.
    @Test func aWitnessForAnotherMemberIsAFold() {
        #expect(behind([
            "_y": "M.ImplS.y() -> Swift.Int",
            "_yTW": "protocol witness for M.Impl2.x() -> Swift.Int in conformance M.ImplS : M.Impl2 in M",
        ]) == nil)
    }

    @Test func aWitnessForAnotherTypeIsAFold() {
        #expect(behind([
            "_a": "M.A2.grow(by: Swift.Int) -> Swift.Int",
            "_aTW": "protocol witness for M.Shape.grow(by: Swift.Int) -> Swift.Int in conformance M.A1 : M.Shape in M",
        ]) == nil)
    }

    @Test func twoFunctionsOrTwoWitnessesAreAFold() {
        #expect(behind(["_a": tank, "_b": "GaugeKit.Other.level.getter : Swift.Int", "_cTW": witness]) == nil)
        #expect(behind(["_aTW": witness, "_bTW": witness + " "]) == nil)
    }

    @Test func aWitnessThatDoesNotDemangleIsAFold() {
        #expect(behind(["_getter": tank, "_getterTW": "_getterTW"]) == nil)
    }

    @Test func theFunctionHeadsItsAddressAndNamesItsCallersIfPresent() async throws {
        let fixture = "Fixtures/Sample/libGaugeKit.dylib"
        guard FileManager.default.fileExists(atPath: fixture) else { return }
        let functions = try await withStableDependencies { try await Disassembler(preset: .default).disassemble(path: fixture) }
        let heading = try #require(functions.first { $0.displayName.hasPrefix("GaugeKit.Tank.level.getter") })
        #expect(heading.source == .symbol)
        #expect(heading.foldedCandidates == nil)
        #expect(!functions.contains { $0.displayName.hasPrefix("protocol witness for GaugeKit.Gauge.level.getter") })
    }
}

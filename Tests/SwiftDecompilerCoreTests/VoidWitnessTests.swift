import Foundation
import Testing
@testable import SwiftDecompilerCore

/// destroy (like storeEnumTagSinglePayload and the enum projections)
/// returns nothing, so x0 after it is not a value: a call reading x0 next
/// takes `?`, never the destroy. initializeWithCopy returns its
/// destination, which does flow on.
@Test func aVoidValueWitnessLeavesNoResultIfPresent() async throws {
    let path = "Fixtures/Sample/libVoidWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String { try #require(functions.first { $0.symbol == name }).renderStructured() }
    let destroyed = try text("_vwVoidThenUse")
    #expect(destroyed.contains("destroy value witness for Swift.Int("), "\(destroyed)")
    #expect(destroyed.contains("vwSink(?)"), "\(destroyed)")
    #expect(try text("_vwCopyThenUse").contains("vwSink(initializeWithCopy value witness for Swift.Int("))
    #expect(DisassembledFunction.isVoidValueWitness("storeEnumTagSinglePayload value witness for A"))
    #expect(!DisassembledFunction.isVoidValueWitness("getEnumTagSinglePayload value witness for A"))
}

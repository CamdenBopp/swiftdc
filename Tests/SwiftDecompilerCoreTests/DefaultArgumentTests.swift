import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `default argument 1 of scale(_:by:)` is a generator with no parameters
/// (the compiler lowers it `define … i64 @"…fA0_"()`), but its name holds
/// scale's parameter list, and x0 and x1 were seeded as its arguments.
/// Found by checking entry seeds against the compiler's lowering
/// (Tools/ghidra-compare/interface_oracle.py: 19 such entries).
@Test func aDefaultArgumentGeneratorHasNoParametersIfPresent() async throws {
    let path = "Fixtures/Sample/libDefaultArgument.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let generator = try #require(functions.first { $0.displayName.hasPrefix("default argument 1 of DefaultArgument.scale") })
    #expect(Disassembler.swiftScalarArgumentRegisters(of: generator) == nil)
    #expect(generator.renderStructured().contains("return 7"), Comment(rawValue: generator.renderStructured()))
    // The function it belongs to keeps its own parameters.
    let scale = try #require(functions.first { $0.displayName.hasPrefix("DefaultArgument.scale(") })
    #expect(Disassembler.swiftScalarArgumentRegisters(of: scale) == ["x0": 0, "x1": 1])
}

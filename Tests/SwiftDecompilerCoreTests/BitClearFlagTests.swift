import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A subset test at -O is `bics xzr, need, have` and a condition on Z. The
/// flags of `bics` were unmodelled, so the condition declined:
/// `have.contains(need)` rendered `return ?`. FlagWidthOracleTests checks
/// the model against native execution; this is what a reader sees.
/// optionsubset.swift states each function's true behaviour.
@Test func subsetTestsRenderTheirBitClearConditionIfPresent() async throws {
    let path = "Fixtures/Sample/libOptionSubset.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let expected = [
        "allows": "return ((arg1.rawValue & ~arg0.rawValue) == 0)",
        "extraBits": "return (((arg0 & ~arg1) == 0) ? 22 : 11)",
        // The 32-bit form tests the word only.
        "covered": "return (((arg0 & 0xffffffff) & ~(arg1 & 0xffffffff)) == 0)",
        "route": "OptionSubset.consume((((arg1.rawValue & ~arg0.rawValue) == 0) ? 2 : 1))",
    ]
    for (name, statement) in expected.sorted(by: { $0.key < $1.key }) {
        let function = try #require(functions.first { $0.displayName.hasPrefix("OptionSubset.\(name)(") })
        // The fixture is only a guard while it still lowers to `bics`.
        #expect(function.instructions.contains { $0.text.hasPrefix("bics") }, "\(name) no longer lowers to bics")
        let text = function.renderStructured()
        #expect(text.contains(statement), "\(name):\n\(text)")
    }
}

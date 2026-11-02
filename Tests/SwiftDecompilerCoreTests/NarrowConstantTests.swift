import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A narrow integer argument or result is its register's low bits at the
/// declared signedness. Read whole, `takeNarrow(-1, -2, -3, …)` rendered
/// `takeNarrow(255, 0xfffe, 0xfffffffd, …)`, wrong values that look right.
@Test func aNarrowIntegerConstantReadsAtItsTypeIfPresent() async throws {
    let path = "Fixtures/Sample/libNarrowConstants.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let call = try #require(functions.first { $0.displayName.hasPrefix("Narrow.callNarrow") }).renderPseudo()
    #expect(call.contains("Narrow.takeNarrow(-1, -2, -3, 250, 0xfde8, 0xee6b2800, true)"), Comment(rawValue: call))
    let result = try #require(functions.first { $0.displayName.hasPrefix("Narrow.minusOne32") }).renderPseudo()
    #expect(result.contains("return -1\n"), Comment(rawValue: result))
}

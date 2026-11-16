import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A stripped executable with no LC_FUNCTION_STARTS decodes pub and its
/// static helpers as one body, and each `bl` lands inside it
/// (`mergedcalls.c`). The target of a `bl` is in the instruction: rendered
/// as `indirect_call(?, …)` it claimed the target was not known. It is a
/// direct call to a known, unnamed address.
@Test func aDirectCallToAnUnnamedAddressIsNotIndirectIfPresent() async throws {
    let path = "Fixtures/Sample/mergedcalls.stripped"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let pseudo = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(!pseudo.contains("indirect_call"), Comment(rawValue: pseudo))
    #expect(pseudo.contains("(recovered_args: ["), Comment(rawValue: pseudo))
    // Every `bl` target in the listing is the name of the call that renders.
    let targets = functions.flatMap(\.instructions).filter { $0.text.hasPrefix("bl\t") }.compactMap(\.branchTarget)
    #expect(!targets.isEmpty)
    for target in targets {
        #expect(pseudo.contains("sub_\(String(target, radix: 16))("), "no call to 0x\(String(target, radix: 16))\n\(pseudo)")
    }
}

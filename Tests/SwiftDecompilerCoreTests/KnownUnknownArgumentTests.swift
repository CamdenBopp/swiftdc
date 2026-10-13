import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func typedThrowContinuationKeepsTheKnownUnknownScalarArgumentIfPresent() async throws {
    let path = "Fixtures/Sample/libTypedThrowsAwait.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    // Compiler source calls onError(error.raw &+ 1000); ARM64 supplies x0
    // even when the context-derived operand is unproved by the tracer.
    let function = try #require(functions.first { function in
        function.displayName.contains("useCode") && function.instructions.contains {
            DisassembledFunction.calleeName(of: $0)?.contains("onError") == true
        }
    })
    let call = try #require(function.instructions.first {
        DisassembledFunction.calleeName(of: $0)?.contains("onError") == true
    })
    #expect(call.callArguments?.count == 1)
    #expect(call.callArguments == ["?"])
    #expect(function.renderStructured().contains("onError(?)"))
    #expect(function.renderPseudo().contains("onError(?)"))
    #expect(!function.renderStructured().contains("onError()"))
}

// Negative layout controls constrain any missing-site completion to supported
// layouts; no signature parser expansion belongs in this correction.
@Test func missingValuesDoNotJustifyUnknownOrAggregateArgumentLayouts() {
    for callee in ["externalUnknown", "M.f<T>(T) -> ()", "M.f((Swift.Int, Swift.Int)) -> ()", "M.f(Swift.Int) async -> ()"] {
        #expect(Disassembler.swiftCallArgumentSlots(callee: callee,
            enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex()) == nil)
    }
}

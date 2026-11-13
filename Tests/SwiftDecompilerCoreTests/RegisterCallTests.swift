import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A call through a register the trace proved holds an in-image function's
/// address is bounded by that function's body, as a direct `bl` is. It was
/// laid out positionally: `mov x0, #3; mov x1, #7; blr x8` to a function
/// reading only x0 rendered `one_arg(3, 7)`, and a `br x16` with x0
/// unknown `one_arg()` (`registercall.s`).
@Test func aRegisterCallToAnInImageFunctionTakesItsBodysArgumentsIfPresent() async throws {
    let path = "Fixtures/Sample/libRegisterCall.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    #expect(try structured("_direct").contains("one_arg(3)"))
    let call = try structured("_reg_call")
    #expect(call.contains("one_arg(3)") && !call.contains("7"), Comment(rawValue: call))
    let tail = try structured("_reg_tail")
    #expect(tail.contains("one_arg(?)"), Comment(rawValue: tail))
}

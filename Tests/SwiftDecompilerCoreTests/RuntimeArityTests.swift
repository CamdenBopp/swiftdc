import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

private let fixture = "Fixtures/Sample/libRuntimeArity.dylib"

/// The listing line of the call in `function` whose note names `callee`.
private func callLine(_ callee: String, in function: DisassembledFunction) -> String? {
    function.render().components(separatedBy: "\n").first { $0.contains("bl\t") && $0.contains(callee) }
}

/// A call inside a body was taken to read every argument register the body
/// had not written, so a callee whose only call is `objc_opt_self` of an
/// address it loads summarized as reading x1-x7, and its callers passed it
/// whatever those held: `runtimearity.swift`'s metadata accessor rendered
/// `args(self, ?, arg0, arg1)`, the initializer's own arguments. A call to a
/// callee of known arity reads only its parameters. Both the array path and
/// the streaming path build the summaries, so both are checked.
@Test func aBodyCallOfKnownArityReadsOnlyItsParametersIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let accessor = "type metadata accessor for RuntimeArity.RuntimeArityOpenEvent"
    let initializer = "-[_TtC12RuntimeArity21RuntimeArityOpenEvent initWithProfileName:trigger:]"
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture)
    }
    let function = try #require(functions.first { $0.displayName == initializer })
    let line = try #require(callLine(accessor, in: function))
    #expect(!line.contains("args("), "\(line)")

    let machO = try BinaryLoader.load(path: fixture)
    let streamed = await withStableDependencies {
        await Disassembler(preset: .default).disassembleStreamingRender(machO: machO) { function in
            function.displayName == initializer ? function.render() : ""
        }
    }.joined()
    let streamedLine = try #require(streamed.components(separatedBy: "\n").first {
        $0.contains("bl\t") && $0.contains(accessor)
    })
    #expect(!streamedLine.contains("args("), "\(streamedLine)")
}

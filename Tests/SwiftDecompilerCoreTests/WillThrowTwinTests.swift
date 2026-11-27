import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The runtime's `swift_willThrow` takes the thrown error in x21 and
/// nothing in x0, so its call renders x21's value as its argument. That
/// was decided by the callee's name. willthrowtwin.c defines a function
/// of that name in the image that reads x0: called with the first
/// argument while x21 held the second, it rendered `swift_willThrow(arg1)`.
/// willthrowtwin.s states each body's true behaviour.
private let willThrowTwinImage = "Fixtures/Sample/libWillThrowTwin.dylib"

/// Every way in: the whole image by path, and the function alone.
private func willThrowTwinFunctions(_ name: String) async throws -> [DisassembledFunction]? {
    guard FileManager.default.fileExists(atPath: willThrowTwinImage) else { return nil }
    let prefix = "WillThrowTwin.\(name)("
    let whole = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: willThrowTwinImage)
    }
    let filtered = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: willThrowTwinImage, functionFilter: name)
    }
    return [try #require(whole.first { $0.displayName.hasPrefix(prefix) }, "\(name)"),
            try #require(filtered.first { $0.displayName.hasPrefix(prefix) }, "\(name) filtered")]
}

/// `plain` has nothing known in x21, `stale` has its second argument
/// there. Both call the twin with their first argument.
@Test(arguments: ["plain", "stale"])
func anInImageTwinOfTheThrowHookTakesWhatItsBodyReadsIfPresent(name: String) async throws {
    guard let functions = try await willThrowTwinFunctions(name) else { return }
    for function in functions {
        let calls = function.instructions.filter {
            $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == "swift_willThrow"
        }
        try #require(calls.count == 1, "\(name)")
        // Nothing binds the call to a library.
        #expect(!DisassembledFunction.hasNamedABIContract(calls[0]), "\(name)")
        for text in [function.renderStructured(), function.renderPseudo()] {
            #expect(text.contains("    swift_willThrow(arg0)\n"), Comment(rawValue: text))
            #expect(!text.contains("swift_willThrow(arg1)"), Comment(rawValue: text))
            #expect(!text.contains("swift_willThrow(?)"), Comment(rawValue: text))
            // The twin's result is still claimed by nothing.
            #expect(text.contains("    return ?\n"), Comment(rawValue: text))
        }
    }
}

/// The controls: the runtime's own hook, reached through its import stub,
/// still renders the error in x21 and not x0. `always` is called with the
/// flag in x0 and the error in x21 (hookpath.s); `plainThrow` with the
/// fresh error box in both (throwselect.swift).
@Test(arguments: [("libHookPath.dylib", "HookPath.always(", "swift_willThrow(arg1)"),
                  ("libThrowSelect.dylib", "ThrowSelect.plainThrow(", "swift_willThrow(r0)")])
func theRuntimesOwnThrowHookStillTakesTheErrorInX21IfPresent(image: String, prefix: String, call: String) async throws {
    let path = "Fixtures/Sample/\(image)"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let function = try #require(functions.first { $0.displayName.hasPrefix(prefix) }, "\(prefix)")
    for text in [function.renderStructured(), function.renderPseudo()] {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains(call), Comment(rawValue: text))
    }
}

/// What the machine does, under the emulator: nothing the pipeline
/// states for the image is false.
@Test func theWillThrowTwinImageStatesNothingFalseIfPresent() async throws {
    guard let sweep = try await sweepAgainstEmulator("libWillThrowTwin.dylib") else { return }
    #expect(sweep.mismatches.isEmpty, "\(sweep.mismatches)")
}

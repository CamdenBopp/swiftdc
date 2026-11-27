import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The runtime's `swift_job_run`, `swift_willThrow` and
/// `swift_willThrowTypedImpl` return nothing, so x0 after a call to one is
/// no result. voidruntimetwin.c defines functions of those names in the
/// image that return a value, and voidruntimetwin.s returns each one's
/// result plus one. The render declines that value; it states no other,
/// and the call stays in view. voidruntimetwin.s gives each function's
/// true behaviour.
private let voidTwinImage = "Fixtures/Sample/libVoidRuntimeTwin.dylib"

/// Every way in: the whole image by path, and the function alone.
private func voidTwinFunctions(_ name: String) async throws -> [DisassembledFunction]? {
    guard FileManager.default.fileExists(atPath: voidTwinImage) else { return nil }
    let prefix = "VoidRuntimeTwin.\(name)("
    let whole = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: voidTwinImage)
    }
    let filtered = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: voidTwinImage, functionFilter: name)
    }
    return [try #require(whole.first { $0.displayName.hasPrefix(prefix) }, "\(name)"),
            try #require(filtered.first { $0.displayName.hasPrefix(prefix) }, "\(name) filtered")]
}

/// Each caller and the twin it calls.
@Test(arguments: [("afterJobRun", "swift_job_run"), ("afterWillThrow", "swift_willThrow"),
                  ("afterTypedImpl", "swift_willThrowTypedImpl")])
func aVoidRuntimeNameTwinsResultIsDeclinedNotStatedIfPresent(caller: String, twin: String) async throws {
    guard let functions = try await voidTwinFunctions(caller) else { return }
    for function in functions {
        // The call reaches this image's function, and nothing binds it
        // to a library.
        let calls = function.instructions.filter {
            $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == twin
        }
        try #require(calls.count == 1, "\(caller)")
        #expect(!DisassembledFunction.hasNamedABIContract(calls[0]), "\(caller)")
        for text in [function.renderStructured(), function.renderPseudo()] {
            let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            // The call that produced the value is in view, before the exit.
            let call = try #require(lines.firstIndex { $0.hasPrefix("\(twin)(") }, Comment(rawValue: text))
            // The value is the twin's result plus one, which nothing
            // proves: not the argument, not a constant.
            let exit = try #require(lines.firstIndex(of: "return ?"), Comment(rawValue: text))
            #expect(call < exit, Comment(rawValue: text))
            #expect(lines.filter { $0.hasPrefix("return") } == ["return ?"], Comment(rawValue: text))
        }
    }
}

/// The control in the same image: the same caller around a function no
/// table names still returns that call's result.
@Test func aCallNoTableNamesStillReturnsItsResultIfPresent() async throws {
    guard let functions = try await voidTwinFunctions("afterPlain") else { return }
    for function in functions {
        for text in [function.renderStructured(), function.renderPseudo()] {
            #expect(text.contains("    return (plain_result(arg0) + 1)\n"), Comment(rawValue: text))
        }
    }
}

/// What the machine does, under the emulator: no return the pipeline
/// states for the image is false. The twins' callers state none.
@Test func theVoidRuntimeTwinImageStatesNothingFalseIfPresent() async throws {
    guard let sweep = try await sweepAgainstEmulator("libVoidRuntimeTwin.dylib") else { return }
    #expect(sweep.mismatches.isEmpty, "\(sweep.mismatches)")
}

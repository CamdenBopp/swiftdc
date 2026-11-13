import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The Swift runtime ships no SDK header, so `SDKCPrototypes` has none of it
/// and 263 of RuntimeFunctions.def's rows took whatever registers were
/// tracked. Each case is a signature the compiler's sources fix.
@Test func runtimeEntryPointsTakeTheirDeclaredSignature() {
    // swift/include/swift/Runtime/Metadata.h: `void (OpaqueValue *, size_t,
    // const Metadata *)`.
    #expect(DisassembledFunction.knownCArity(of: "swift_arrayDestroy") == 3)
    // RuntimeFunctions.def: swift_deallocClassInstance returns nothing, and
    // x0 after one read `let r8 = swift_deallocClassInstance(r7, 32, 7)`.
    #expect(ValueTracer.CallFacts(callee: "swift_deallocClassInstance").cResult == "v")
    // Error.h: a BoxPair comes back in x0 and x1. `x` claims nothing about x0.
    #expect(ValueTracer.CallFacts(callee: "swift_allocError").cResult == nil)
    #expect(DisassembledFunction.knownCArity(of: "swift_allocError") == 4)
    // The MetadataResponse's x0 is the metadata, read as a value.
    #expect(ValueTracer.CallFacts(callee: "swift_getGenericMetadata").cResult == nil)
}

/// Not everything the table's source lists has a fixed register signature.
@Test func runtimeEntryPointsWithoutARegisterSignatureAreLeftOut() {
    // The selector decides.
    #expect(DisassembledFunction.cPrototype(of: "objc_msgSendSuper2") == nil)
    // A context in x22, formals by the async convention.
    #expect(DisassembledFunction.cPrototype(of: "swift_task_switch") == nil)
    #expect(DisassembledFunction.cPrototype(of: "swift_task_future_wait") == nil)
    // A generic Swift function under a C name, unless checked by hand
    // (SwiftIntrinsicSignatures): its result goes through x8.
    #expect(DisassembledFunction.cPrototype(of: "swift_getAtKeyPath")?.parameters.count == 2)
    #expect(ValueTracer.CallFacts(callee: "swift_getAtKeyPath").passedRegisters.contains(.x(8)))
    // RuntimeFunctions.def says one argument; Error.h and the stdlib say five.
    #expect(DisassembledFunction.cPrototype(of: "swift_unexpectedError") == nil)
}

/// An actor's initializer loads the object it passes, so nothing is tracked,
/// and `swift_defaultActor_initialize()` read as a call that takes nothing.
@Test func aRuntimeCallWithNothingTrackedShowsItsParametersIfPresent() async throws {
    let fixture = "Fixtures/Sample/libRethrowCleanup.opt.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: "A2.init")
    }
    let pseudo = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(pseudo.contains("swift_defaultActor_initialize(?)"), "\(pseudo)")
}

/// `swift_bridgeObjectRetain` returns its argument, not a float, so no stale
/// v0 makes a site of the String getter after it. The two words are the
/// getter's whatever was tracked: `String.utf8.getter()` read as no `self`.
@Test func aStringGetterWithNothingTrackedKeepsItsWordsIfPresent() async throws {
    let fixture = "Fixtures/Sample/libStringArity.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: "takeOptString")
    }
    let pseudo = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(pseudo.contains("Swift.String.utf8.getter(?, ?)"), "\(pseudo)")
}

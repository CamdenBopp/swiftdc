import Testing
import Foundation
@testable import SwiftDecompilerCore

/// Soundness regression: a local whose address a call receives may be written
/// by that call. The tracer kept the value stored before the call, so a
/// reload after it rendered the stale value:
///
/// - an NSError out-parameter (`str xzr, [sp]; mov x3, sp; bl …error:`)
///   rendered the failure's error as `_convertNSErrorToError(0)`;
/// - a value mutated in place through `self` in x20 rendered as its
///   original: `Stack.count.getter(Stack.init())` after pushes,
///   `String.append("Optional")` for a string extended to `"Optional {"`.
///
/// A second address calculation does not prove a separate object's extent:
/// the two addresses can name words of one local. Without stronger layout or
/// callee-write evidence both words may be changed. Proven incoming-stack
/// ownership and read-only projection effects still retain their facts.

private func traced(_ words: [UInt32]) -> [UInt64: CallSite]? {
    guard let engine = CapstoneEngine() else { return nil }
    let bytes = words.flatMap { word in (0..<4).map { UInt8((word >> ($0 * 8)) & 0xff) } }
    let instructions = engine.disassemble(Data(bytes), address: 0).map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
    let function = DisassembledFunction(symbol: "_t", demangledName: "t", startAddress: 0,
                                        instructions: instructions, source: .symbol)
    return ValueTracer().callSites(in: function)
}

@Test func anAddressCalculationDoesNotProveTheNextLocalIsSeparate() throws {
    //   sub sp, sp, #0x30
    //   mov x8, #7;  str x8, [sp, #0x20]    B = 7
    //   mov x10, #5; str x10, [sp, #0x10]   A = 5
    //   add x9, sp, #0x20                   an address, not proof B is separate
    //   add x0, sp, #0x10; bl f             f may write A through &A
    //   ldr x2, [sp, #0x20]                 B, possibly changed too
    //   ldr x3, [sp, #0x10]                 A, no longer known to be 5
    //   bl g
    let sites = try #require(traced([
        0xd100c3ff, 0xd28000e8, 0xf90013e8, 0xd28000aa, 0xf9000bea, 0x910083e9, 0x910043e0,
        0x94000006, 0xf94013e2, 0xf9400be3, 0x94000003, 0x9100c3ff, 0xd65f03c0, 0xd65f03c0,
    ]))
    let second = try #require(sites[0x28])
    #expect(second.arguments.count < 3 || second.arguments[2] == .unknown, "\(second.arguments)")
    #expect(second.arguments.count < 4 || second.arguments[3] == .unknown, "\(second.arguments)")
}

@Test func withoutASeparateAddressTheEscapeRunsToTheFrameTop() throws {
    // Removing the extra address calculation leaves the same uncertainty
    // about whether the write reaches B.
    let sites = try #require(traced([
        0xd100c3ff, 0xd28000e8, 0xf90013e8, 0x910043e0, 0x94000006,
        0xf94013e2, 0xf9400be3, 0x94000003, 0x9100c3ff, 0xd65f03c0, 0xd65f03c0,
    ]))
    let second = try #require(sites[0x1c])
    #expect(second.arguments.count < 3 || second.arguments[2] == .unknown, "\(second.arguments)")
}

private func pseudo(_ filter: String, in path: String) async throws -> String? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: filter)
    }
    return functions.map { $0.renderPseudo() }.joined(separator: "\n")
}

@Test func anErrorOutParameterIsReloadedNotTheNilBeforeTheCallIfPresent() async throws {
    guard let text = try await pseudo("listingCount", in: "Fixtures/Sample/libSwiftErrorProbe.dylib") else { return }
    #expect(text.contains("error:local_"), "\(text)")
    #expect(!text.contains("_convertNSErrorToError(0)"), "\(text)")
}

@Test func aValueMutatedInPlaceIsNotItsOriginalIfPresent() async throws {
    guard let text = try await pseudo("sample.run()", in: "Fixtures/Sample/sample.debug") else { return }
    #expect(text.contains("Stack.count.getter"), "\(text)")
    #expect(!text.contains("Stack.count.getter : Swift.Int(sample.Stack.init())"), "\(text)")
}

@Test func whatAnEscapeCannotReachSurvivesIfPresent() async throws {
    // The witness call through an existential container's type and witness
    // words stays resolved across the projection that receives the container.
    if let run = try await pseudo("sample.run()", in: "Fixtures/Sample/sample.release") {
        #expect(run.contains("sample.Shape.describe(self: __swift_project_boxed_opaque_existential_1("), "\(run)")
    }
    // `[super init…]` passes `&objc_super`; the seventh argument, on the
    // incoming stack, is out of its reach.
    if let initializer = try await pseudo("initWithA:b:c:d:e:f:g:", in: "Fixtures/Sample/sample.debug") {
        #expect(initializer.contains("self->_count = arg6"), "\(initializer)")
    }
    // The interpolation builder is mutated in place; the folder still claims
    // its init and the closing `String(stringInterpolation:)`.
    if let describe = try await pseudo("sample.Circle.describe()", in: "Fixtures/Sample/sample.debug") {
        #expect(describe.contains("\"Circle("), "\(describe)")
        #expect(!describe.contains("DefaultStringInterpolation.init("), "\(describe)")
    }
}

@Test func rejectedMergedReturnsKeepTheirCallsIfPresent() async throws {
    for path in ["Fixtures/Sample/libSwiftErrorProbe.dylib", "Fixtures/Sample/libSwiftErrorProbe.stripped.dylib"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "listingCount")
        }
        let function = try #require(functions.first)
        let release = try #require(function.instructions.first {
            DisassembledFunction.calleeName(of: $0) == "swift_errorRelease"
        })
        #expect(!release.resultConsumed)
        #expect(function.renderPseudo().contains("swift_errorRelease("))
        #expect(function.renderStructured().contains("swift_errorRelease("))
    }
}

@Test func typedThrowHelpersKeepUnconsumedAvailabilityChecksIfPresent() async throws {
    for path in ["Fixtures/Sample/libReconstruction.opt.dylib", "Fixtures/Sample/libReconstruction.osize.dylib"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "typedScale")
        }
        let function = try #require(functions.first)
        // At -Osize the check is `bl OUTLINED_FUNCTION_4`, a fragment that
        // tail-calls it, inlined at the site.
        #expect(function.renderPseudo().contains("Swift._stdlib_isOSVersionAtLeastOrVariantVersionAtLeast("))
    }
}

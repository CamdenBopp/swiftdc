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
/// The extent the callee may write is unknown, so it runs to the next local
/// whose address the function takes separately. What it cannot reach must
/// survive: an unrelated address-taken local, incoming stack arguments, and
/// an existential container's words past the payload a projection receives.

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

@Test func anEscapedLocalIsForgottenButASeparateLocalSurvives() throws {
    //   sub sp, sp, #0x30
    //   mov x8, #7;  str x8, [sp, #0x20]    B = 7
    //   mov x10, #5; str x10, [sp, #0x10]   A = 5
    //   add x9, sp, #0x20                   &B: B is its own variable
    //   add x0, sp, #0x10; bl f             f may write A through &A
    //   ldr x2, [sp, #0x20]                 B, still 7
    //   ldr x3, [sp, #0x10]                 A, no longer known to be 5
    //   bl g
    let sites = try #require(traced([
        0xd100c3ff, 0xd28000e8, 0xf90013e8, 0xd28000aa, 0xf9000bea, 0x910083e9, 0x910043e0,
        0x94000006, 0xf94013e2, 0xf9400be3, 0x94000003, 0x9100c3ff, 0xd65f03c0, 0xd65f03c0,
    ]))
    let second = try #require(sites[0x28])
    #expect(second.arguments.count > 2 && second.arguments[2] == .immediate(7), "\(second.arguments)")
    #expect(second.arguments.count < 4 || second.arguments[3] == .unknown, "\(second.arguments)")
}

@Test func withoutASeparateAddressTheEscapeRunsToTheFrameTop() throws {
    // The same, minus `add x9, sp, #0x20`: nothing says B is not part of A,
    // so f may have written it.
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

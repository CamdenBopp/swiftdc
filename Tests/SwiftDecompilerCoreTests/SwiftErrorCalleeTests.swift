import Testing
import Foundation
@testable import SwiftDecompilerCore

/// Soundness regression: Swift's error convention through callees whose name
/// cannot say they throw.
///
/// A caller arms swifterror by loading x21 with its current error (zero, or a
/// saved copy of the error it was handed) right before the call, then tests x21
/// after. The do/catch fix (`e39f64b`) invalidated x21 only when the callee's
/// demangled name said ` throws`, and only in the tracer. An unnamed callee (a
/// stripped local), a metadata label with no signature (`Type.method`), or an
/// accessor (whose demangling never shows `throws`) let the arming value flow
/// through:
///
/// - the tracer read the zero: `if (0 != 0)`, `return 1`, and
///   `swift_errorRelease(0)` in a SwiftData `@objc` thunk;
/// - the structurer's text walk-back crossed the call: a post-call
///   `cbz x21` after `mov x21, x19` rendered `x19 == 0`, in 164 SwiftData
///   functions, even for callees named ` throws`.

private func decoded(
    _ words: [UInt32], at address: UInt64, name: String = "test", annotations: [UInt64: String] = [:]
) -> DisassembledFunction? {
    guard let engine = CapstoneEngine() else { return nil }
    let bytes = words.flatMap { word in (0..<4).map { UInt8((word >> ($0 * 8)) & 0xff) } }
    let instructions = engine.disassemble(Data(bytes), address: address).map {
        Instruction(address: $0.address, text: $0.text, annotation: annotations[$0.address],
                    controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
    }
    return DisassembledFunction(symbol: "_test", demangledName: name, startAddress: address,
                                instructions: instructions, source: .symbol)
}

@Test func structurerDoesNotWalkX21BackAcrossAnUnprovenCall() throws {
    //   mov x19, x21     save the incoming error register
    //   mov x21, x19     re-arm it for the call
    //   bl  <unnamed>
    //   cbz x21, 1f      the callee's error, not x19
    let function = try #require(decoded([
        0xaa1503f3, 0xaa1303f5, 0x9400000e, 0xb4000075,
        0xd2800020, 0xd65f03c0, 0xd2800040, 0xd65f03c0,
    ], at: 0))
    let rendered = function.renderStructured()
    #expect(rendered.contains("if (x21 == 0)"), "\(rendered)")
    #expect(!rendered.contains("x19"), "\(rendered)")
}

@Test func aCallResultKeptInX21StillResolvesAcrossACall() throws {
    //   bl  f; mov w21, w0     f's Bool result, kept in x21
    //   bl  g                  g is not a swifterror call: x21 holds a live value
    //   tbz w21, #0, 2f
    let function = try #require(decoded([
        0x94000008, 0x2a0003f5, 0x94000006, 0x36000075,
        0xd2800020, 0xd65f03c0, 0xd2800040, 0xd65f03c0,
    ], at: 0x20, annotations: [0x20: "M.isReady() -> Swift.Bool"]))
    let rendered = function.renderStructured()
    // The walk reaches `mov w21, w0` past the unnamed g and inlines f.
    #expect(rendered.contains("!M.isReady()"), "\(rendered)")

    // With f unnamed too, the tested register stays `w21`: a bare `w0` would
    // read as x0 at the branch, which is g's result.
    let unnamed = try #require(decoded([
        0x94000008, 0x2a0003f5, 0x94000006, 0x36000075,
        0xd2800020, 0xd65f03c0, 0xd2800040, 0xd65f03c0,
    ], at: 0x20)).renderStructured()
    #expect(unnamed.contains("bit 0 of w21 clear"), "\(unnamed)")
    #expect(!unnamed.contains("w0"), "\(unnamed)")
}

@Test func onlyCLevelSymbolsAndNonThrowingSignaturesProvablyDoNotThrow() {
    for callee in ["memset", "objc_msgSend", "swift_retain",
                   "M.f(Swift.Int) -> Swift.Int",
                   "outlined destroy of M.T", "type metadata accessor for M.T"] {
        #expect(ValueTracer.provablyDoesNotThrow(callee), "\(callee)")
    }
    for callee in ["", "sub_1000", "M.Validator.method", "M.T.p.getter : Swift.Int",
                   "M.f(Swift.Int) throws -> Swift.Int", "M.f() throws(M.E) -> ()"] {
        #expect(!ValueTracer.provablyDoesNotThrow(callee), "\(callee)")
    }
}

// MARK: - The SwiftData shape, compiled

/// `Fixtures/Sample/swifterror.swift` at `-O`: an `@objc` thunk around an
/// internal throwing method, and a do/catch around a private throwing
/// function. Stripped, neither callee's name says it throws.
private let probeLevels = [
    ("stripped", "Fixtures/Sample/libSwiftErrorProbe.stripped.dylib"),
    ("unstripped", "Fixtures/Sample/libSwiftErrorProbe.dylib"),
]

private func probeFunctions(_ filter: String, in path: String) async throws -> [DisassembledFunction]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    return try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: filter)
    }
}

@Test func objcThunkErrorCheckIsNotTheArmingZeroIfPresent() async throws {
    for (label, path) in probeLevels {
        guard let functions = try await probeFunctions("validateAndReturnError", in: path) else { continue }
        #expect(!functions.isEmpty, "\(label): thunk not found")
        for function in functions {
            let structured = function.renderStructured()
            let pseudo = function.renderPseudo()
            for text in [structured, pseudo] {
                #expect(!text.contains("(0 != 0)") && !text.contains("(0 == 0)"), "\(label): \(text)")
                // `cmp x21, #0; cset w0, eq` is `error == nil`, not a constant.
                #expect(!text.contains("return 1"), "\(label): \(text)")
                // The error passed to the bridge and the release is x21's.
                #expect(!text.contains("swift_errorRelease(0)"), "\(label): \(text)")
                #expect(!text.contains("_convertErrorToNSError(0)"), "\(label): \(text)")
            }
        }
    }
}

@Test func doCatchAroundAnUnnamedThrowerReleasesTheRealErrorIfPresent() async throws {
    for (label, path) in probeLevels {
        guard let functions = try await probeFunctions("SwiftErrorProbe.tryHidden", in: path) else { continue }
        #expect(!functions.isEmpty, "\(label): tryHidden not found")
        for function in functions {
            let pseudo = function.renderPseudo()
            #expect(!pseudo.contains("swift_errorRelease(0)"), "\(label): \(pseudo)")
        }
    }
}

// MARK: - Throw exits

/// A throwing function returns its error in x21 and leaves x0 meaningless (or,
/// for a typed error small enough, holding the error's payload). Rendered as a
/// `return`, a throw exit printed x0 as the result: `return 0` for
/// `throw .negative`, `return swift_willThrow(…)`, and at -Onone a typed
/// forwarder's error path `return (typedPick(arg0) & 255)`.

private let reconstructionLevels = [
    ("-Onone", "Fixtures/Sample/libReconstruction.dylib"),
    ("-O", "Fixtures/Sample/libReconstruction.opt.dylib"),
]

private func structured(_ name: String, in path: String) async throws -> String? {
    guard let functions = try await probeFunctions(name, in: path) else { return nil }
    return functions.filter { $0.demangledName?.hasPrefix(name) == true }
        .map { $0.renderStructured() + "\n" + $0.renderPseudo() }.joined(separator: "\n")
}

/// No statement follows a `throw` in its block: a trailing `return` would
/// claim the exit also returns.
private func statementsAfterThrow(_ body: String) -> [String] {
    let lines = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    return zip(lines, lines.dropFirst()).compactMap { line, next in
        line.hasPrefix("throw ") && !next.hasPrefix("}") ? next : nil
    }
}

@Test func typedThrowExitNamesTheErrorCaseIfPresent() async throws {
    for (level, path) in reconstructionLevels {
        guard let body = try await structured("Reconstruction.typedScale(", in: path) else { continue }
        #expect(body.contains("throw Reconstruction.ReconTypedError.negative"), "\(level): \(body)")
        #expect(!body.contains("return 0"), "\(level): \(body)")
        #expect(!body.contains("ReconTypedError.tooBig"), "\(level): \(body)")
        let structuredOnly = body.components(separatedBy: "\n}\n").first ?? body
        #expect(statementsAfterThrow(structuredOnly).isEmpty, "\(level): \(body)")
    }
}

@Test func untypedThrowExitIsNotAReturnIfPresent() async throws {
    for (level, path) in reconstructionLevels {
        guard let body = try await structured("Reconstruction.mightFail(", in: path) else { continue }
        #expect(body.contains("throw ?"), "\(level): \(body)")
        #expect(!body.contains("return swift_willThrow"), "\(level): \(body)")
    }
}

@Test func forwardedTypedErrorIsNotReturnedIfPresent() async throws {
    let (level, path) = reconstructionLevels[0]
    guard let body = try await structured("Reconstruction.typedForward(", in: path) else { return }
    #expect(body.contains("throw ?"), "\(level): \(body)")
    #expect(!body.contains("& 255"), "\(level): \(body)")
}

@Test func aMergedExitIsNotClassifiedAsAThrowIfPresent() async throws {
    // At -O the forwarder merges both exits (`csel x21, x21, x8, eq`), so no
    // `ret` proves an error; it must not print a `throw`.
    let (level, path) = reconstructionLevels[1]
    guard let body = try await structured("Reconstruction.typedForward(", in: path) else { return }
    #expect(!body.isEmpty, "\(level): typedForward not found")
    let throwStatements = body.split(separator: "\n").filter {
        $0.trimmingCharacters(in: .whitespaces).hasPrefix("throw ")
    }
    #expect(throwStatements.isEmpty, "\(level): \(body)")
}

@Test func splitSignatureReportsTheTypedError() {
    #expect(DisassembledFunction.splitSignature("M.f(Swift.Int) throws(M.E) -> Swift.Int")?.thrownType == "M.E")
    #expect(DisassembledFunction.splitSignature("M.f(Swift.Int) async throws(M.E) -> Swift.Int")?.thrownType == "M.E")
    #expect(DisassembledFunction.splitSignature("M.f(Swift.Int) throws -> Swift.Int")?.thrownType == nil)
    #expect(DisassembledFunction.splitSignature("M.f(() throws(M.E) -> ()) -> Swift.Int")?.thrownType == nil)
}


// MARK: - swift_willThrow's operand

/// `swift_willThrow(SWIFT_CONTEXT void *, SWIFT_ERROR_RESULT SwiftError **)`
/// (swift/include/swift/Runtime/Error.h:71) takes the thrown error in x21 and
/// nothing in x0. Rendering x0 showed whatever was last there: 20
/// `swift_willThrow(0)` in SwiftData, and in RegexParser's
/// `parseWithDelimiters` a release that ran between boxing the error and
/// throwing it, `swift_willThrow(swift_errorRelease(?))`. The compiler only
/// orders it that way in the shipping image, so this is host-gated on the
/// dyld cache.
@Test func willThrowShowsTheErrorInX21NotX0IfAvailable() async throws {
    guard let machO = try? BinaryLoader.loadFromDyldCache(
        cachePath: nil, selector: .name("libswift_RegexParser")) else { return }
    let functions = await Disassembler(preset: .default)
        .disassemble(machO: machO, functionFilter: "parseWithDelimiters")
    let text = functions.map { $0.renderPseudo() + "\n" + $0.renderStructured() }.joined(separator: "\n")
    guard text.contains("swift_willThrow(") else { return } // a different OS build
    #expect(!text.contains("swift_willThrow(swift_errorRelease"), "\(text)")
    let expressions = expandingResultBindingsForAssertions(text)
    #expect(expressions.contains("swift_willThrow((extension in _RegexParser):Swift.Error.addingLocation("), "\(text)")
}

/// A lazy protocol witness table accessor is `() -> WitnessTable`
/// (swift/lib/IRGen/GenDecl.cpp:6384), so anything rendered as its argument is
/// a stale register: `…ReconError : Swift.Error in Reconstruction(arg0)`. A
/// *merged* accessor does take the differing constant as a real parameter,
/// and keeps it.
@Test func lazyWitnessTableAccessorTakesNoArgumentsIfPresent() async throws {
    for (level, path) in reconstructionLevels {
        guard let body = try await structured("Reconstruction.mightFail(", in: path) else { continue }
        #expect(body.contains("Swift.Error in Reconstruction()"), "\(level): \(body)")
        #expect(!body.contains("Swift.Error in Reconstruction(arg0)"), "\(level): \(body)")
    }
    #expect(DisassembledFunction.knownCArity(of: "merged lazy protocol witness table accessor for type M.T") == nil)
}

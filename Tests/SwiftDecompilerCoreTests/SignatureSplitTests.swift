import Testing
import Foundation
@testable import SwiftDecompilerCore

/// Soundness regression. Every signature reader (argument registers, argument
/// types, enum/Bool/float parameters, the return register) used to take the
/// *last* ` -> ` and then the *last* `(...)` group as the parameter list. Two
/// real demangled shapes break that:
///
/// - typed throws: `f(Swift.Double, Swift.Int) throws(M.E) -> Swift.Double`
///   read as one `M.E` parameter, so x0 (really the second argument) rendered
///   as `arg0` and the literal `0` as an `M.E` case;
/// - a closure result: `f(Swift.Int) -> (Swift.Double) -> Swift.Double` read
///   the closure's types as the function's, and printed a stale `d0` as
///   `return arg0`.
///
/// The spellings below are the demangler's own output for a compiled probe
/// (`xcrun swift-demangle` on Swift 6.3): `rethrows` and `throws(any Error)`
/// print as plain `throws`.

@Test func splitSignatureDropsEffectsFromTheHead() {
    let cases: [(String, String, String)] = [
        ("eff.f1(Swift.Double) throws(eff.E) -> Swift.Double", "eff.f1(Swift.Double)", "Swift.Double"),
        ("eff.f2(Swift.Int) async throws(eff.E) -> Swift.Int", "eff.f2(Swift.Int)", "Swift.Int"),
        ("eff.f3(Swift.Int, Swift.Int) async throws -> Swift.Int", "eff.f3(Swift.Int, Swift.Int)", "Swift.Int"),
        ("eff.f5(Swift.Int) throws(eff.E) -> ()", "eff.f5(Swift.Int)", "()"),
        ("eff.f6(Swift.Int) async -> ()", "eff.f6(Swift.Int)", "()"),
        ("eff.f9<A where A: Swift.Error>(A) throws(A) -> Swift.Int", "eff.f9<A where A: Swift.Error>(A)", "Swift.Int"),
        ("eff.S.m(Swift.Double) throws(eff.E) -> Swift.Double", "eff.S.m(Swift.Double)", "Swift.Double"),
    ]
    for (name, head, result) in cases {
        let split = DisassembledFunction.splitSignature(name)
        #expect(split?.head == head, "\(name)")
        #expect(split?.result == result, "\(name)")
    }
}

@Test func splitSignatureEndsTheDeclarationAtTheFirstTopLevelArrow() {
    // A closure-typed parameter's arrow is nested, so it is skipped.
    let rethrowing = DisassembledFunction.splitSignature(
        "eff.f4(() throws -> Swift.Int) throws -> Swift.Int")
    #expect(rethrowing?.head == "eff.f4(() throws -> Swift.Int)")
    #expect(rethrowing?.result == "Swift.Int")

    // A closure *result* is the whole tail after the first arrow.
    let maker = DisassembledFunction.splitSignature(
        "eff.f8(Swift.Int) -> (Swift.Int) throws(eff.E) -> Swift.Int")
    #expect(maker?.head == "eff.f8(Swift.Int)")
    #expect(maker?.result == "(Swift.Int) throws(eff.E) -> Swift.Int")

    // A closure's own name: its signature, then ` in <enclosing function>`.
    let closure = DisassembledFunction.splitSignature(
        "closure #1 (Swift.Double) -> Swift.Int in shape.maker(Swift.Int) -> (Swift.Double) -> Swift.Int")
    #expect(closure?.head == "closure #1 (Swift.Double)")
    #expect(closure?.result == "Swift.Int")

    #expect(DisassembledFunction.splitSignature("eff.S.p.getter : Swift.Int") == nil)
}

private let reconstructionLevels = [
    ("-Onone", "Fixtures/Sample/libReconstruction.dylib"),
    ("-O", "Fixtures/Sample/libReconstruction.opt.dylib"),
]

/// The structured render of each function named exactly `name`, per level.
private func structured(_ name: String, in path: String) async throws -> String? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: name)
    }
    return functions.filter { $0.demangledName?.hasPrefix(name) == true }
        .map { $0.renderStructured() }.joined(separator: "\n")
}

@Test func typedThrowsClauseIsNotReadAsTheParameterListIfPresent() async throws {
    for (level, path) in reconstructionLevels {
        guard let body = try await structured("Reconstruction.typedScale(", in: path) else { continue }
        // `n` is the second parameter and lives in x0; the literal is an Int.
        // The defect named the literal as an error case inside the condition
        // (`arg0 >= ReconTypedError.negative`); the thrown case itself is fine.
        let conditions = body.split(separator: "\n").filter { $0.contains("if (") }
        #expect(!conditions.contains { $0.contains("ReconTypedError") }, "\(level): \(body)")
        #expect(!body.contains("arg0 < ") && !body.contains("arg0 >= "), "\(level): \(body)")
        #expect(body.contains("arg1 < 0") || body.contains("arg1 >= 0"), "\(level): \(body)")
        // The success value is recovered from both real parameters.
        #expect(body.contains("+ arg1)"), "\(level): \(body)")
    }
}

@Test func closureResultIsNotReadAsTheReturnTypeIfPresent() async throws {
    for (level, path) in reconstructionLevels {
        guard let body = try await structured("Reconstruction.thresholdGate(", in: path) else { continue }
        #expect(!body.isEmpty, "\(level): thresholdGate not found")
        // A closure is not returned in d0; printing d0 (the seeded `arg0`)
        // fabricated `return arg0`.
        #expect(!body.contains("return arg0"), "\(level): \(body)")
    }
}

// MARK: - Results that do not come back in x0

/// Reading the real result type (not the enclosing function's) exposed closures
/// whose x0 at `ret` is not the result: a closure reabstracted to a generic
/// convention returns through the x8 buffer, and an async function delivers its
/// result through its context. Each rendered a stale call as the return value
/// (`return Dictionary.removeAll(0)`, `return swift_task_dealloc()` in
/// libswiftObservation). The same check also removed older fabrications on
/// ordinary indirect returns, e.g. a 40-byte struct init printing `return arg0`.

private func function(_ name: String, _ texts: [String]) -> DisassembledFunction {
    DisassembledFunction(
        symbol: "_$s1M1fyyF", demangledName: name, startAddress: 0,
        instructions: texts.enumerated().map { Instruction(address: UInt64($0.offset * 4), text: $0.element) },
        source: .symbol
    )
}

@Test func incomingX8IsRecognisedAsTheIndirectResultBuffer() {
    let indirect: [[String]] = [
        ["str\tx0, [x8]", "ret"],                                   // resilient struct init
        ["stp\tx29, x30, [sp, #-0x10]!", "mov\tx19, x8", "bl\t0x100"], // saved across a call
        ["ldr\tx9, [x8, #0x8]", "ret"],
        ["ldr\tx8, [x8, #0x8]", "ret"],                             // read before the write
    ]
    for texts in indirect {
        #expect(Disassembler.readsIncomingIndirectResult(function("M.f() -> M.S", texts)), "\(texts)")
    }
    let scratch: [[String]] = [
        ["mov\tw8, #0x1", "str\tx8, [x0]", "ret"],
        ["adrp\tx8, 0x1000", "ldr\tx8, [x8, #0x10]", "ret"],
        ["bl\t0x100", "mov\tx9, x8", "ret"],                        // x8 after a call is clobbered
        ["add\tx0, x0, #0x1", "ret"],
    ]
    for texts in scratch {
        #expect(!Disassembler.readsIncomingIndirectResult(function("M.f() -> M.S", texts)), "\(texts)")
    }
}

@Test func returnRegisterDeclinesIndirectAndAsyncResults() {
    #expect(Disassembler.swiftReturnRegister(of: function("M.f(Swift.Int) -> Swift.Int", ["ret"])) == .integer)
    #expect(Disassembler.swiftReturnRegister(of: function("M.f(Swift.Int) -> Swift.Int", ["str\tx0, [x8]", "ret"])) == nil)
    #expect(Disassembler.swiftReturnRegister(of: function("M.f(Swift.Int) async -> Swift.Int", ["ret"])) == nil)
    #expect(Disassembler.swiftReturnRegister(of: function(
        "(2) await resume partial function for M.f(Swift.Int) async -> Swift.Int", ["ret"])) == nil)
}

@Test func returnsValueAndThrowsReadTheFunctionsOwnSignature() {
    // A `-> ()` closure inside a `-> Swift.Never` function returns nothing.
    #expect(!DisassembledFunction.signatureReturnsValue(
        displayName: "closure #1 (Swift.UnsafeBufferPointer<Swift.UInt8>) -> () in M.h() -> Swift.Never",
        objcSignature: nil))
    #expect(!DisassembledFunction.signatureReturnsValue(
        displayName: "protocol witness for Swift.Hashable.hash(into: inout Swift.Hasher) -> () in conformance M.S : Swift.Hashable in M",
        objcSignature: nil))
    #expect(DisassembledFunction.signatureReturnsValue(
        displayName: "((Swift.Int) -> Swift.Int) -> Swift.Int", objcSignature: nil))
    // A closure inside a throwing function does not itself throw.
    #expect(DisassembledFunction.splitSignature("closure #1 () -> () in M.f() throws -> Swift.Int")?.isThrowing == false)
    #expect(DisassembledFunction.splitSignature("M.f() throws(M.E) -> Swift.Int")?.isThrowing == true)
    #expect(DisassembledFunction.splitSignature("M.f() async -> Swift.Int")?.isAsync == true)
}

@Test func indirectStructReturnIsNotReadFromX0IfPresent() async throws {
    // `OuterY.Wide` is five Ints (40 bytes), returned through x8; its x0 at
    // `ret` is the first argument, which printed as `return arg0`.
    for (level, path) in reconstructionLevels {
        guard let body = try await structured("Reconstruction.OuterY.Wide.init(", in: path) else { continue }
        #expect(!body.isEmpty, "\(level): Wide.init not found")
        #expect(!body.contains("return arg0"), "\(level): \(body)")
    }
}

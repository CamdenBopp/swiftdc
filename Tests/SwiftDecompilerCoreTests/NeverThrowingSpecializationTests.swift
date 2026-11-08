import Foundation
import Testing
import Demangling
@testable import SwiftDecompilerCore

/// The name the analysis reads for a symbol: its default demangling.
private func printed(_ symbol: String) throws -> String {
    try demangleAsNode(symbol).print(using: .default)
}

private func neverProven(_ symbol: String) throws -> Bool {
    DisassembledFunction.specializationBindsThrownTypeToNever(symbol: symbol, semanticName: try printed(symbol))
}

/// `generic specialization <serialized, (), Swift.Never> of
/// Unicode.Scalar.withUTF8CodeUnits<A, B where B: Error>(…) throws(B) -> A`,
/// from sample.debug.
private let withUTF8Never =
    "$ss7UnicodeO6ScalarV17withUTF8CodeUnitsyxxSRys5UInt8VGq_YKXEq_YKs5ErrorR_r0_lFyt_s5NeverOTgq5"

@Test func aNeverBindingOfTheThrownParameterIsProven() throws {
    #expect(try neverProven(withUTF8Never))
    // The closure inside it throws the parent's B.
    #expect(try neverProven(
        "$ss7UnicodeO6ScalarV17withUTF8CodeUnitsyxxSRys5UInt8VGq_YKXEq_YKs5ErrorR_r0_lFxSPys6UInt64VGq_YKXEfU_yt_s5NeverOTgq5"))
    // Under a function signature specialization (closure propagation, -O).
    #expect(try neverProven(
        "$s16TypedThrowsNever9transformyS2i_S2ixYKXEtxYKs5ErrorRzlFs0C0O_Tg5015$sS2iIgyd_S2is5C11OIegydzr_TRS2iIgyd_Tf1nc_n"))
}

@Test func aThrownParameterNotProvablyBoundToNeverStaysThrowing() throws {
    // B bound to a real error type, and to `any Error`.
    #expect(try !neverProven(
        "$s19TypedThrowsNeverLib9transformyS2i_S2ixYKXEtxYKs5ErrorRzlFAA05ProbeF0O_Tgq5"))
    #expect(try !neverProven("$s19TypedThrowsNeverLib9transformyS2i_S2ixYKXEtxYKs5ErrorRzlFsAC_p_Tgq5"))
    // `Box<Never>.runOwn<ProbeError>(…) throws(A1)`: the substitutions are
    // <Never, ProbeError>, and the thrown A1 is the method's own parameter at
    // depth 1. Its index, 0, names Never only in a list that ignores depth.
    #expect(try !neverProven("$s4Ctx23BoxV6runOwnyS2i_S2iqd__YKXEtqd__YKs5ErrorRd__lFs5NeverO_AA05ProbeE0OTgq5"))
    // `pinned<A, B, C where A == Int, B: Error>(…) throws(B)` with
    // <ProbeError, Never>: A is not canonical, so it has no substitution and
    // B's index, 1, names C's.
    #expect(try !neverProven("$s4Ctx26pinnedyS2i_q0_mS2iq_YKXEtq_YKSiRszs5ErrorR_r1_lFAA05ProbeC0O_s5NeverOTt1gq5"))
    // A name that is not this symbol's demangling proves nothing.
    #expect(!DisassembledFunction.specializationBindsThrownTypeToNever(
        symbol: withUTF8Never, semanticName: "generic specialization <serialized, (), Swift.Never> of f() throws(B) -> A"))
}

/// Hand-mangled from `withUTF8Never`, each breaking exactly one link of the
/// proof that the real compiler output above breaks several of at once.
@Test func eachLinkOfTheNeverProofIsRequired() throws {
    // No `B: Swift.Error` conformance in the function's own signature.
    #expect(try !neverProven(
        "$ss7UnicodeO6ScalarV17withUTF8CodeUnitsyxxSRys5UInt8VGq_YKXEq_YKr0_lFyt_s5NeverOTgq5"))
    // The thrown type is a depth-1 parameter (index 1), not B.
    #expect(try !neverProven(
        "$ss7UnicodeO6ScalarV17withUTF8CodeUnitsyxxSRys5UInt8VGq_YKXEqd_0_YKs5ErrorR_r0_lFyt_s5NeverOTgq5"))
    // Three substitutions for two parameters.
    #expect(try !neverProven(
        "$ss7UnicodeO6ScalarV17withUTF8CodeUnitsyxxSRys5UInt8VGq_YKXEq_YKs5ErrorR_r0_lFyt_s5NeverOSiTgq5"))
    // `pinned` (above) given a third substitution and no dropped argument,
    // so the count matches although `A == Int` leaves A without one.
    #expect(try !neverProven(
        "$s4Ctx26pinnedyS2i_q0_mS2iq_YKXEtq_YKSiRszs5ErrorR_r1_lFAA05ProbeC0O_s5NeverOSiTgq5"))
}

@Test func aRawExitOfANeverSpecializationIsAReturnInBothViews() throws {
    let name = try printed(withUTF8Never)
    let function = DisassembledFunction(symbol: "_" + withUTF8Never, demangledName: name, startAddress: 0x1000,
        instructions: [
            Instruction(address: 0x1000, text: "cbz x0, 0x1008", controlFlow: .conditionalBranch, branchTarget: 0x1008),
            Instruction(address: 0x1004, text: "ret", controlFlow: .return),
            Instruction(address: 0x1008, text: "ret", controlFlow: .return),
        ], source: .symbol, semanticName: name)
    #expect(!function.signatureThrows)
    for text in [function.renderStructured(), function.renderPseudo()] {
        #expect(!text.contains("machine_return()"), Comment(rawValue: text))
        #expect(text.contains("return"), Comment(rawValue: text))
    }
}

@Test func neverBoundSpecializationsReturnAndControlsStayThrowingIfPresent() async throws {
    let path = "Fixtures/Sample/libTypedThrowsNever.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "TypedThrowsNeverLib.transform")
    }
    func specialization(_ binding: String) throws -> DisassembledFunction {
        try #require(functions.first { $0.displayName.hasPrefix("generic specialization <serialized, \(binding)> of ") })
    }
    let never = try specialization("Swift.Never")
    #expect(never.specializationBindsThrownTypeToNever)
    let structured = never.renderStructured()
    // The source returns `body(x) &+ 1`; the error test still reads as one.
    #expect(structured.contains("if (error == nil) {"))
    #expect(structured.contains(" ? + 1)"))
    for text in [structured, never.renderPseudo()] {
        #expect(!text.contains("machine_return()"))
        #expect(!text.contains("throw "))
    }
    for binding in ["TypedThrowsNeverLib.ProbeError", "Swift.Error"] {
        let control = try specialization(binding)
        #expect(!control.specializationBindsThrownTypeToNever)
        #expect(control.signatureThrows)
        #expect(control.renderStructured().contains("machine_return()"))
    }
    #expect(try specialization("TypedThrowsNeverLib.ProbeError").renderStructured().contains("throw ?"))
}

@Test func withUTF8CodeUnitsNeverSpecializationsReturnIfPresent() async throws {
    let path = "Fixtures/Sample/sample.debug"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "withUTF8CodeUnits")
    }
    let specializations = functions.filter { $0.displayName.hasPrefix("generic specialization <serialized, (), Swift.Never> of ") }
    #expect(specializations.count == 2)
    for function in specializations {
        #expect(function.specializationBindsThrownTypeToNever)
        for text in [function.renderStructured(), function.renderPseudo()] {
            #expect(!text.contains("machine_return()"))
            #expect(text.contains("return"))
        }
    }
}

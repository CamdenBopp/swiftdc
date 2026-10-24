import Testing
import Foundation
import Demangling
@testable import SwiftDecompilerCore

/// A generic specialization prints as its unspecialized declaration, and its
/// call was laid out from the printed `(A)`: positionally, from x0. The
/// Double specialization of `bump` takes its argument in d0, so
/// `specializations.swift`'s `useDouble(d, n)` rendered `bump(arg1)`, passing
/// n, and `returnDouble(d)` rendered `bump()`. Laid out from the substituted
/// signature, each passes its Double.
@Test func aSpecializationsArgumentsComeFromItsSubstitutedSignatureIfPresent() async throws {
    let path = "Fixtures/Sample/libSpecializations.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    for name in ["useDouble", "useInt", "returnDouble"] {
        let text = try #require(functions.first { $0.displayName.hasPrefix("Specializations.\(name)(") })
            .renderPseudo()
        #expect(text.contains("Specializations.bump<A where A: Swift.Numeric>(arg0)\n"), "\(name): \(text)")
    }
}

private func printed(_ symbol: String) throws -> String {
    try demangleAsNode(symbol).print(using: .default)
}

@Test func aSpecializedSignatureReplacesEachGenericParameter() throws {
    let bump = "$s15Specializations4bumpyxxSjRzlFSd_Tg5"
    #expect(DisassembledFunction.specializedSignature(symbol: "_" + bump, printedName: try printed(bump))
        == "Specializations.bump(Swift.Double) -> Swift.Double")
    // The tree must print the name the call was given.
    #expect(DisassembledFunction.specializedSignature(
        symbol: bump, printedName: "generic specialization <Swift.Int> of Specializations.bump") == nil)
    // A member type (`A.Element`) needs a conformance to resolve.
    let first = "$s15Specializations10firstCounty7ElementQzSgxSlRzlFSaySiG_Tg5"
    #expect(DisassembledFunction.specializedSignature(symbol: first, printedName: try printed(first)) == nil)
    // A function signature specialization drops and explodes arguments.
    let dead = "$s9CallArity3genyS2i_xtlFSi_Tg5Tf4nd_n"
    #expect(DisassembledFunction.specializedSignature(symbol: dead, printedName: try printed(dead)) == nil)
}

/// An address the linker folded several symbols onto keeps none: the one
/// symbol there may name another specialization of the same body.
@Test func aFoldedSpecializationKeepsNoSymbol() {
    let symbols = Disassembler.ReferenceResolver.specializationSymbols(
        labels: [1: "_one", 2: "_two", 3: "_three"],
        names: [1: "generic specialization <Swift.Int> of f", 2: "generic specialization <Swift.UInt> of f",
                3: "M.plain(Swift.Int) -> ()"],
        folded: [2: ["_two", "_other"]])
    #expect(symbols == [1: "_one"])
}

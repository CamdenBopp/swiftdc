import Foundation
import Testing
@testable import SwiftDecompilerCore

// Recovered from the pre-merge stash (d921fc1, improve/source-findings).

@Test func qualifiedClassLookupRequiresMatchingDescriptor() {
    let index = ClassTypeIndex(
        classNames: ["Ref"],
        qualifiedClassNames: ["ClassIdentityLocal.Ref"]
    )
    #expect(index.isClass("Ref"))
    #expect(index.isClass("ClassIdentityLocal.Ref"))
    #expect(!index.isClass("ClassIdentityExternal.Ref"))
    #expect(index.referenceOptionalInner("Swift.Optional<ClassIdentityLocal.Ref>") == "ClassIdentityLocal.Ref")
    #expect(index.referenceOptionalInner("Swift.Optional<ClassIdentityExternal.Ref>") == nil)
}

/// The external Ref is a two-word struct. A local class also named Ref must
/// not cause its return to be read from x0 as a one-word class reference.
@Test func declinesForeignStructReturnOnLocalClassNameCollisionIfPresent() async throws {
    let fixture = "Fixtures/Sample/libClassIdentityLocal.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }

    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default)
            .disassemble(path: fixture, functionFilter: "makeExternalRef")
    }
    let pseudo = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(pseudo.contains("ClassIdentityLocal.makeExternalRef() -> ClassIdentityExternal.Ref"))
    #expect(!pseudo.contains("return 3"))
}

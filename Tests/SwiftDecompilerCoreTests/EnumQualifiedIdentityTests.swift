import Foundation
import Testing
@testable import SwiftDecompilerCore

// Recovered from the pre-merge stash (d921fc1, improve/source-findings).

@Test func qualifiedNoPayloadLookupsRequireMatchingDescriptor() {
    let index = EnumCaseIndex(
        byName: ["Shade": ["amber", "violet"]],
        byQualifiedName: ["EnumIdentityLocal.Shade": ["amber", "violet"]]
    )
    #expect(index.caseName(ofEnum: "Shade", tag: 0) == "amber")
    #expect(index.caseName(ofEnum: "EnumIdentityLocal.Shade", tag: 0) == "amber")
    #expect(index.caseName(ofEnum: "EnumIdentityExternal.Shade", tag: 0) == nil)
    #expect(!index.isNoPayloadEnum("EnumIdentityExternal.Shade"))
    #expect(!index.tagsFit("EnumIdentityExternal.Shade", unsignedBits: 8))
}

/// An external return type may share a simple name and byte pattern with a
/// locally defined enum. Only the local enum has reflection metadata in this
/// image, so its case names must never be assigned to the external type.
@Test func declinesForeignEnumCaseNameOnSimpleNameCollisionIfPresent() async throws {
    let fixture = "Fixtures/Sample/libEnumIdentityLocal.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }

    func pseudo(_ filter: String) async throws -> String {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default)
                .disassemble(path: fixture, functionFilter: filter)
        }
        return functions.map { $0.renderPseudo() }.joined(separator: "\n")
    }

    let foreignNoPayload = try await pseudo("fromExternalNoPayload")
    let localNoPayload = try await pseudo("fromLocalNoPayload")
    #expect(foreignNoPayload.contains("EnumIdentityExternal.Shade"))
    #expect(!foreignNoPayload.contains("EnumIdentityExternal.Shade.amber"))
    #expect(!foreignNoPayload.contains("EnumIdentityExternal.Shade.violet"))
    #expect(localNoPayload.contains("return EnumIdentityLocal.Shade.amber"))

    let foreignPayload = try await pseudo("fromExternalPayload")
    #expect(foreignPayload.contains("EnumIdentityExternal.Packet"))
    #expect(!foreignPayload.contains("EnumIdentityExternal.Packet.empty"))

    let foreignNested = try await pseudo("fromExternalNested")
    let localNested = try await pseudo("fromLocalNested")
    #expect(foreignNested.contains("EnumIdentityExternal.Box.State"))
    #expect(!foreignNested.contains("EnumIdentityExternal.Box.State.amber"))
    #expect(localNested.contains("return EnumIdentityLocal.Box.State.amber"))
}

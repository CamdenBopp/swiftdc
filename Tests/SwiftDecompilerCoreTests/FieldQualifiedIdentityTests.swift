import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `Calculator.sum(_: FieldIdentityExternal.Vec)` reads the external `Vec`'s
/// `actualFirst`/`actualSecond`. This image also defines its own `Vec` with
/// `wrongFirst`/`wrongSecond` at the same offsets, and a qualified type name
/// fell back to that simple-name map: the render read
/// `arg0.wrongFirst + arg0.wrongSecond`. A qualified name now needs its own
/// descriptor's map. The local `Vec` still names its fields. (Fixtures from
/// the pre-merge stash d921fc1; its loader-path field-map tests are not
/// ported: they need the deferred `buildIncludingLoaderPathDependencies`.)
@Test func aForeignTypeDoesNotBorrowALocalTypesFieldsIfPresent() async throws {
    let fixture = "Fixtures/Sample/libFieldIdentityLocal.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    func pseudo(_ filter: String) async throws -> String {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: filter)
        }
        return functions.map { $0.renderPseudo() }.joined(separator: "\n")
    }
    let foreign = try await pseudo("Calculator.sum")
    #expect(!foreign.contains("wrongFirst") && !foreign.contains("wrongSecond"), "\(foreign)")
    let local = try await pseudo("Calculator.localSum")
    #expect(local.contains("arg0.wrongFirst") && local.contains("arg0.wrongSecond"), "\(local)")
}

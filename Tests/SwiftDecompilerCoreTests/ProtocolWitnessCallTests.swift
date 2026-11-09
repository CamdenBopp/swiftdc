import Foundation
import Testing
@testable import SwiftDecompilerCore

private func structured(_ path: String) async throws -> [String: String] {
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    return Dictionary(functions.map { ($0.displayName, $0.renderStructured()) }, uniquingKeysWith: { a, _ in a })
}

/// A call through word k of a table swift_conformsToProtocol returned is
/// the protocol's requirement k - 1, when the call passes the conforming
/// type's metadata and the table last. A stripped image names it by the
/// descriptor's protocol and the requirement's index and kind; a call that
/// does not pass the table stays unresolved.
@Test func aProtocolWitnessThroughALookedUpTableIsNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libProtocolWitnessArgs.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let text = try await structured(path)
    #expect(text["_pwArea"]?.contains("Demo.Shape requirement 0 (method) witness for arg0(") == true, "\(text["_pwArea"] ?? "")")
    #expect(text["_pwSides"]?.contains("Demo.Shape requirement 1 (getter) witness for arg0(") == true, "\(text["_pwSides"] ?? "")")
    for name in ["_pwNotTheTable", "_pwNotTheType", "_pwUnknownType"] {
        #expect(text[name]?.contains("unresolved call") == true, "\(name)")
        #expect(text[name]?.contains("witness for") == false, "\(name): \(text[name] ?? "")")
    }
}

/// The same through Swift's own lowering of `(object as? Named)?.label`:
/// requirement 0 is the `label` getter and 1 is `rank()`. Only a module
/// built for library evolution emits the method descriptors that name them.
@Test func aCastToAClassBoundProtocolNamesItsWitnessIfPresent() async throws {
    let paths = ["Fixtures/Sample/libProtocolWitness.dylib", "Fixtures/Sample/libProtocolWitness.stripped.dylib",
                 "Fixtures/Sample/libProtocolWitness.resilient.dylib"]
    guard paths.allSatisfy(FileManager.default.fileExists(atPath:)) else { return }
    for path in paths.prefix(2) {
        let all = try await structured(path).values.joined(separator: "\n")
        #expect(all.contains("ProtocolWitness.Named requirement 0 (getter) witness for ?("), "\(path)")
        #expect(all.contains("ProtocolWitness.Named requirement 1 (method) witness for ?("), "\(path)")
    }
    let resilient = try await structured(paths[2]).values.joined(separator: "\n")
    #expect(resilient.contains("ProtocolWitness.Named.label.getter witness for ?("))
    #expect(resilient.contains("ProtocolWitness.Named.rank() witness for ?("))
    // Named for an operation, not an address: still unresolved dispatch.
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: paths[1]) }
    #expect(functions.flatMap(\.instructions).filter(\.facts.isWitnessDispatch).count == 2)
}

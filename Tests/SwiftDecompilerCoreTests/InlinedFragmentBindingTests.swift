import Foundation
import Testing
@testable import SwiftDecompilerCore

/// -Osize outlines the tail of a runtime call into a fragment, and the
/// site that reaches it is rewritten to the call the fragment makes. The
/// rewritten site kept the callee's name but not the proof that the name
/// is bound to the library's function, so it was laid out as an unknown
/// call: `swift_allocObject(…)`, `swift_deallocClassInstance(…)`. The
/// site calls the fragment's own target, and that target's binding is its.
@Test func anInlinedFragmentsCallKeepsItsLibraryBindingIfPresent() async throws {
    let path = "Fixtures/Sample/libReconstruction.osize.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    func function(_ prefix: String) throws -> DisassembledFunction {
        try #require(functions.first { $0.displayName.hasPrefix(prefix) }, "\(prefix)")
    }
    let allocating = try function("Reconstruction.Counter.__allocating_init(value:")
    let deallocating = try function("Reconstruction.Dog.__deallocating_deinit")
    // Both sites are fragments' calls: the test is about nothing else.
    for f in [allocating, deallocating] {
        // Reached by a call in one and by a tail branch in the other.
        #expect(f.instructions.contains { $0.inlinedFragment != nil }, "\(f.displayName) reaches no fragment")
    }
    for text in [allocating.renderStructured(), allocating.renderPseudo()] {
        // Metadata, size and alignment mask: 32 bytes for two Int fields.
        #expect(text.contains("swift_allocObject(?, 32, 7)"), Comment(rawValue: text))
    }
    for text in [deallocating.renderStructured(), deallocating.renderPseudo()] {
        #expect(text.contains("swift_deallocClassInstance(self, 16, 7)"), Comment(rawValue: text))
    }
    // The fact itself, on the rewritten site.
    let site = try #require(allocating.instructions.first {
        $0.inlinedFragment != nil && DisassembledFunction.calleeName(of: $0) == "swift_allocObject"
    })
    #expect(site.facts.namedABIContract)
}

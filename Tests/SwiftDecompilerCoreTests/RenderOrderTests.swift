import Foundation
import Testing
@testable import SwiftDecompilerCore

private let renderOrderFixture = "Fixtures/Sample/libRenderOrder.dylib"

private func renderOrderFunction(_ member: String) async throws -> DisassembledFunction? {
    guard FileManager.default.fileExists(atPath: renderOrderFixture) else { return nil }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: renderOrderFixture) }
    return try #require(functions.first { $0.displayName.contains("RenderOrder.\(member)(") }, "\(member)")
}

/// An unresolved indirect call took a result computed before another call.
/// Its arguments were not counted as uses, so the result was neither bound
/// nor shown where it was computed: `render_effect()` and then
/// `indirect_call(?, recovered_args: [render_helper()])`, the helper read as
/// running second.
@Test func aResultAnIndirectCallTakesIsBoundWhereItIsComputedIfPresent() async throws {
    guard let function = try await renderOrderFunction("indirect") else { return }
    for text in [function.renderPseudo(), function.renderStructured()] {
        let helper = try #require(text.range(of: "let r0 = render_helper()"), "\(text)")
        let effect = try #require(text.range(of: "render_effect()"), "\(text)")
        #expect(helper.lowerBound < effect.lowerBound, "\(text)")
        #expect(text.contains("recovered_args: [r0]"), "\(text)")
        #expect(!text.contains("[render_helper()]"), "\(text)")
    }
}

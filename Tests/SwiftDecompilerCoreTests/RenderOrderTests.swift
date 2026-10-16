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

/// A bound call is the call's statement, so it names `self` as the
/// statement does. Both binding paths dropped it: a result bound because
/// it is used across another call (`boundSelf`) and one bound because its
/// indirect result is read by word (`readWide`).
@Test func aBoundCallNamesItsSelfIfPresent() async throws {
    if let function = try await renderOrderFunction("boundSelf") {
        for text in [function.renderPseudo(), function.renderStructured()] {
            #expect(text.contains("let r0 = RenderOrder.Widget.count.getter(self: arg0)"), "\(text)")
        }
    }
    let path = "Fixtures/Sample/libBoundSelf.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "readWide")
    }
    let function = try #require(functions.first { $0.displayName.contains("BoundSelf.readWide(") })
    for text in [function.renderPseudo(), function.renderStructured()] {
        #expect(text.contains("let r0 = BoundSelf.Holder.make(self: arg0)"), "\(text)")
    }
}

/// A static member of a struct receives a thin metatype, which no register
/// carries; x20 at its call is the caller's scratch. It rendered
/// `Point.origin.getter(self: arg0)`; app code rendered
/// `static Swift.Array._allocateBufferUninitialized(self: 256, 256)`. A class's
/// static member receives its metatype in x20 and keeps its `self`.
@Test func aStaticMemberOfAValueTypeHasNoSelfIfPresent() async throws {
    guard let function = try await renderOrderFunction("staticCall") else { return }
    for text in [function.renderPseudo(), function.renderStructured()] {
        #expect(text.contains("let r0 = static RenderOrder.Point.origin.getter()"), "\(text)")
        #expect(text.contains("static RenderOrder.Widget.shared.getter(self: r0)"), "\(text)")
    }
}

@Test func staticValueTypeMembersAreFoundByTheirOwner() {
    let index = ClassTypeIndex(qualifiedClassNames: ["M.Box"], qualifiedNonClassNames: ["M.Point", "M.Edge.Set", "Swift.String"])
    #expect(DisassembledFunction.isStaticValueTypeMember("static M.Point.origin.getter : Swift.Int", classTypeIndex: index))
    #expect(DisassembledFunction.isStaticValueTypeMember("static M.Edge.Set.all.getter : M.Edge.Set", classTypeIndex: index))
    #expect(DisassembledFunction.isStaticValueTypeMember(
        "static (extension in Foundation):Swift.String._unconditionallyBridgeFromObjectiveC(__C.NSString?) -> Swift.String",
        classTypeIndex: index))
    #expect(DisassembledFunction.isStaticValueTypeMember("static M.Point.make<A>(A) -> M.Point", classTypeIndex: index))
    #expect(!DisassembledFunction.isStaticValueTypeMember("static M.Box.shared.getter : M.Box", classTypeIndex: index))
    #expect(!DisassembledFunction.isStaticValueTypeMember("M.Point.origin.getter : Swift.Int", classTypeIndex: index))
    #expect(!DisassembledFunction.isStaticValueTypeMember("static N.Point.origin.getter : Swift.Int", classTypeIndex: index))
}

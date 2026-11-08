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

/// A call result spelled inside the one expression that uses it is that
/// call: `return RenderOrder.Widget.count.getter()` dropped its `self`.
@Test func aCallSpelledInsideItsUseNamesItsSelfIfPresent() async throws {
    guard let function = try await renderOrderFunction("inlineSelf") else { return }
    for text in [function.renderPseudo(), function.renderStructured()] {
        #expect(text.contains("return RenderOrder.Widget.count.getter(self: arg0)"), "\(text)")
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

/// A static member or an initializer of a struct receives a thin metatype,
/// which no register carries; x20 at its call is the caller's scratch. It
/// rendered `Point.origin.getter(self: arg0)` and `Point.init(self: r0, 7)`;
/// app code rendered `static Swift.Array._allocateBufferUninitialized(self:
/// 256, 256)` and `SwiftUI.EdgeInsets.init(self: static
/// SwiftUI.Edge.Set.vertical.getter(…))`. A class's static member receives
/// its metatype in x20 and keeps its `self`.
@Test func aStaticMemberOfAValueTypeHasNoSelfIfPresent() async throws {
    guard let function = try await renderOrderFunction("staticCall") else { return }
    for text in [function.renderPseudo(), function.renderStructured()] {
        #expect(text.contains("let r0 = static RenderOrder.Point.origin.getter()"), "\(text)")
        #expect(text.contains("static RenderOrder.Widget.shared.getter(self: r0)"), "\(text)")
        #expect(text.contains("RenderOrder.Point.init(7)"), "\(text)")
    }
}

@Test func thinMetatypeMembersAreFoundByTheirOwner() {
    let index = ClassTypeIndex(qualifiedClassNames: ["M.Box", "M.Point.Holder"],
                               qualifiedNonClassNames: ["M.Point", "M.Edge.Set", "Swift.String",
                                                        "(extension in Foundation):Swift.String.Encoding"])
    #expect(DisassembledFunction.receivesThinMetatype("static M.Point.origin.getter : Swift.Int", classTypeIndex: index))
    #expect(DisassembledFunction.receivesThinMetatype("static M.Edge.Set.all.getter : M.Edge.Set", classTypeIndex: index))
    #expect(DisassembledFunction.receivesThinMetatype(
        "static (extension in Foundation):Swift.String._unconditionallyBridgeFromObjectiveC(__C.NSString?) -> Swift.String",
        classTypeIndex: index))
    #expect(DisassembledFunction.receivesThinMetatype("static M.Point.make<A>(A) -> M.Point", classTypeIndex: index))
    #expect(!DisassembledFunction.receivesThinMetatype("static M.Box.shared.getter : M.Box", classTypeIndex: index))
    #expect(!DisassembledFunction.receivesThinMetatype("M.Point.origin.getter : Swift.Int", classTypeIndex: index))
    #expect(!DisassembledFunction.receivesThinMetatype("static N.Point.origin.getter : Swift.Int", classTypeIndex: index))
    // A value type declared in an extension is known by its extension name.
    #expect(DisassembledFunction.receivesThinMetatype(
        "static (extension in Foundation):Swift.String.Encoding.utf8.getter : (extension in Foundation):Swift.String.Encoding",
        classTypeIndex: index))
    // A class nested in a struct: the member is the class's.
    #expect(!DisassembledFunction.receivesThinMetatype("static M.Point.Holder.shared.getter : M.Point.Holder", classTypeIndex: index))
    #expect(!DisassembledFunction.receivesThinMetatype("static M.Point.Holder.make() -> M.Point.Holder", classTypeIndex: index))
    // Initializers: a value type's takes a thin metatype, a class's does not,
    // and neither does a value type's instance method.
    #expect(DisassembledFunction.receivesThinMetatype("M.Point.init(x: Swift.Int) -> M.Point", classTypeIndex: index))
    #expect(DisassembledFunction.receivesThinMetatype("M.Point.init<A>(A) -> M.Point", classTypeIndex: index))
    #expect(!DisassembledFunction.receivesThinMetatype("M.Box.init(x: Swift.Int) -> M.Box", classTypeIndex: index))
    #expect(!DisassembledFunction.receivesThinMetatype("M.Point.Holder.init() -> M.Point.Holder", classTypeIndex: index))
    #expect(!DisassembledFunction.receivesThinMetatype("M.Point.move(by: Swift.Int) -> ()", classTypeIndex: index))
}

/// A compiler helper's convention has no `self`; x20 at its call is the
/// caller's. The listing noted `self=arg0` on a lazy witness table accessor.
@Test func aCompilerHelperHasNoSelfIfPresent() async throws {
    guard let function = try await renderOrderFunction("helperCall") else { return }
    let call = try #require(function.instructions.first { $0.controlFlow == .call })
    #expect(call.annotation?.contains("lazy protocol witness table accessor") == true, "\(call.annotation ?? "")")
    #expect(call.annotation?.contains("self=") == false, "\(call.annotation ?? "")")
    #expect(DisassembledFunction.takesNoSelf("merged outlined copy of M.T"))
    #expect(DisassembledFunction.takesNoSelf("type metadata accessor for M.T"))
    #expect(!DisassembledFunction.takesNoSelf("merged M.T.method() -> ()"))
    #expect(!DisassembledFunction.takesNoSelf("M.T.method() -> ()"))
}

/// `os_log_type_t` is a C typedef the importer made a struct; Swift mangles
/// it as a typealias, so the class index had no evidence it is a value type
/// and its static members kept a scratch `self` (73 Clarc calls).
@Test func aStaticMemberOfAnImportedTypedefStructHasNoSelfIfPresent() async throws {
    guard let function = try await renderOrderFunction("importedLog") else { return }
    let call = try #require(function.instructions.first { $0.controlFlow == .call })
    #expect(call.annotation?.contains("os_log_type_t.info.getter") == true, "\(call.annotation ?? "")")
    #expect(call.annotation?.contains("self=") == false, "\(call.annotation ?? "")")
}

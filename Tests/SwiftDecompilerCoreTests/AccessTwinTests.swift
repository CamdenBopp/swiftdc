import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The runtime's access markers write no field, so a field read before one
/// is the field after it. That was decided by the callee's name. An
/// in-image function that only shares the name has no such contract:
/// with `swift_endAccess` defined in the image and setting `n` to 23,
/// `let old = m.n; twinEnd(m); return m.n &- old` rendered
/// `return (arg0.n - arg0.n)`. accesstwin.swift states each function's
/// true behaviour.
private func views(_ image: String, _ name: String) async throws -> [String]? {
    let path = "Fixtures/Sample/\(image)"
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let function = try #require(functions.first { $0.displayName.hasPrefix("AccessTwin.\(name)(") })
    return [function.renderStructured(), function.renderPseudo()]
}

@Test(arguments: ["libAccessTwin.dylib", "libAccessTwin.onone.dylib"])
func aFieldIsNotCarriedAcrossAnAccessMarkersNameTwinIfPresent(image: String) async throws {
    guard let end = try await views(image, "acrossEnd"),
          let begin = try await views(image, "acrossBegin") else { return }
    for text in end {
        // Two reads of one field, with a writer between: not one value.
        #expect(!text.contains("arg0.n - arg0.n"), Comment(rawValue: text))
        #expect(text.contains("    return ?\n"), Comment(rawValue: text))
    }
    for text in begin {
        // The value consumed is the field before the twin, not the field.
        #expect(text.contains("AccessTwin.consume(?)"), Comment(rawValue: text))
        #expect(!text.contains("AccessTwin.consume(arg0.n)"), Comment(rawValue: text))
        // The read after the twin is the field as it is then.
        #expect(text.contains("    return arg0.n\n"), Comment(rawValue: text))
    }
}

/// The control in the same image: with no call between, the field read is
/// still named where it is consumed.
@Test(arguments: ["libAccessTwin.dylib", "libAccessTwin.onone.dylib"])
func aFieldReadWithNoCallBetweenIsStillNamedIfPresent(image: String) async throws {
    guard let views = try await views(image, "noCall") else { return }
    for text in views { #expect(text.contains("AccessTwin.consume(arg0.n)"), Comment(rawValue: text)) }
}

/// The contract itself: a field-preserving runtime name preserves fields
/// only with its library binding.
@Test func anAccessMarkerPreservesFieldsOnlyWithItsLibraryBinding() {
    for name in ["swift_beginAccess", "swift_endAccess", "objc_retainBlock"] {
        #expect(!ValueTracer.CallFacts(callee: name).writesNoFields, "\(name) by name alone")
        #expect(ValueTracer.CallFacts(callee: name, namedABIContract: true).writesNoFields, "\(name) bound")
    }
    // An ARC entry point is admitted by its own identity contract, as before.
    #expect(!ValueTracer.CallFacts(callee: "swift_retain").writesNoFields)
    #expect(ValueTracer.CallFacts(callee: "swift_retain", arcIdentityContract: true).writesNoFields)
}

/// A call is hidden as runtime bookkeeping by its name. The twin's call
/// was hidden with the rest, so the function that changed the field was
/// not in the render at all: `acrossEnd` read as a lone `return`. A call
/// is hidden only with its library binding; the twin's is shown.
@Test(arguments: ["libAccessTwin.dylib", "libAccessTwin.onone.dylib"])
func anAccessMarkersNameTwinIsNotHiddenAsRuntimeNoiseIfPresent(image: String) async throws {
    guard let end = try await views(image, "acrossEnd"),
          let begin = try await views(image, "acrossBegin") else { return }
    for text in end {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let call = try #require(lines.firstIndex { $0.hasPrefix("swift_endAccess(") }, Comment(rawValue: text))
        // Before the exit whose value it changed.
        #expect(try #require(lines.firstIndex(of: "return ?")) > call, Comment(rawValue: text))
    }
    for text in begin {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let call = try #require(lines.firstIndex { $0.hasPrefix("swift_beginAccess(") }, Comment(rawValue: text))
        #expect(try #require(lines.firstIndex(of: "AccessTwin.consume(?)")) > call, Comment(rawValue: text))
    }
}

/// The control: the runtime's own markers, bound to libswiftCore, stay
/// hidden. `Holder.total` brackets each field read with one
/// (reconstruction.swift, -Osize).
@Test func theRuntimesOwnAccessMarkersStayHiddenIfPresent() async throws {
    let path = "Fixtures/Sample/libReconstruction.osize.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let total = try #require(functions.first { $0.displayName.hasPrefix("Reconstruction.BoxA.Holder.total.getter") })
    #expect(total.instructions.contains { DisassembledFunction.calleeName(of: $0) == "swift_beginAccess" })
    for text in [total.renderStructured(), total.renderPseudo()] {
        #expect(!text.contains("swift_beginAccess"), Comment(rawValue: text))
        #expect(text.contains("return (self.first + self.second)"), Comment(rawValue: text))
    }
}

/// libobjc's register-specific releases have no SDK declaration, so the
/// provider table does not list them. Bound to libobjc they are still its
/// own, and stay hidden (retainregister.swift, built for the simulator).
@Test func aRegisterSpecificReleaseBoundToLibobjcStaysHiddenIfPresent() async throws {
    let path = "Fixtures/Sample/libRetainRegister.sim.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let join = try #require(functions.first { $0.displayName.hasPrefix("RetainRegister.Node.join(") })
    #expect(join.instructions.contains { DisassembledFunction.calleeName(of: $0) == "objc_release_x20" })
    for text in [join.renderStructured(), join.renderPseudo()] {
        #expect(!text.contains("objc_release"), Comment(rawValue: text))
    }
    #expect(RuntimeFunctionReference.isRegisterSpecificObjCRelease("objc_release_x20"))
    #expect(RuntimeFunctionReference.isRegisterSpecificObjCRelease("objc_release_x1"))
    for name in ["objc_release", "objc_release_x", "objc_release_x20_probe", "objc_release_x200", "objc_retain_x20"] {
        #expect(!RuntimeFunctionReference.isRegisterSpecificObjCRelease(name), "\(name)")
    }
}

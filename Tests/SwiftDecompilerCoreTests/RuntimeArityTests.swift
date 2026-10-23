import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

private let fixture = "Fixtures/Sample/libRuntimeArity.dylib"

/// The listing line of the call in `function` whose note names `callee`.
private func callLine(_ callee: String, in function: DisassembledFunction) -> String? {
    function.render().components(separatedBy: "\n").first { $0.contains("bl\t") && $0.contains(callee) }
}

/// A call inside a body was taken to read every argument register the body
/// had not written, so a callee whose only call is `objc_opt_self` of an
/// address it loads summarized as reading x1-x7, and its callers passed it
/// whatever those held: `runtimearity.swift`'s metadata accessor rendered
/// `args(self, ?, arg0, arg1)`, the initializer's own arguments. A call to a
/// callee of known arity reads only its parameters. Both the array path and
/// the streaming path build the summaries, so both are checked.
@Test func aBodyCallOfKnownArityReadsOnlyItsParametersIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let accessor = "type metadata accessor for RuntimeArity.RuntimeArityOpenEvent"
    let initializer = "-[_TtC12RuntimeArity21RuntimeArityOpenEvent initWithProfileName:trigger:]"
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture)
    }
    let function = try #require(functions.first { $0.displayName == initializer })
    let line = try #require(callLine(accessor, in: function))
    #expect(!line.contains("args("), "\(line)")

    let machO = try BinaryLoader.load(path: fixture)
    let streamed = await withStableDependencies {
        await Disassembler(preset: .default).disassembleStreamingRender(machO: machO) { function in
            function.displayName == initializer ? function.render() : ""
        }
    }.joined()
    let streamedLine = try #require(streamed.components(separatedBy: "\n").first {
        $0.contains("bl\t") && $0.contains(accessor)
    })
    #expect(!streamedLine.contains("args("), "\(streamedLine)")
}

/// The arguments a call's listing note gives `callee` in `function`: the
/// `args(…)` list split at top-level commas, or `[]` for a note without one.
private func noteArguments(_ callee: String, in function: DisassembledFunction) -> [[String]] {
    function.instructions.compactMap { insn -> [String]? in
        guard insn.controlFlow == .call || insn.controlFlow == .branch,
              let annotation = insn.annotation, annotation.hasPrefix("→ \(callee)"),
              annotation.dropFirst("→ \(callee)".count).first.map({ $0 == " " }) ?? true
        else { return nil }
        guard let open = annotation.range(of: "  args(") else { return [] }
        var depth = 1
        var index = open.upperBound
        while index < annotation.endIndex, depth > 0 {
            if annotation[index] == "(" { depth += 1 } else if annotation[index] == ")" { depth -= 1 }
            if depth > 0 { index = annotation.index(after: index) }
        }
        let inner = annotation[open.upperBound..<index]
        return inner.isEmpty ? [] : DisassembledFunction.splitTopLevelArguments(inner)
    }
}

/// Swift runtime entry points of fixed arity took whatever registers held a
/// value at the call. `swift_getObjectType(HeapObject *)` read
/// `(self, ?, arg0, arg1)` in an `@objc` initializer and `()` where the
/// object was unknown; `swift_continuation_throwingResumeWithError(task,
/// error)` read a third argument; `swift_task_getMainExecutor(void)` read
/// one; and `swift_checkMetadataState(request, type)` and
/// `swift_getWitnessTable(conformance, type, instantiationArgs)` dropped
/// their unknown last arguments (`runtimearity.swift`; the headers are cited
/// in `knownCArity`).
@Test func aSwiftRuntimeEntryPointTakesItsDeclaredArgumentsIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture)
    }
    func function(_ prefix: String) -> DisassembledFunction? {
        functions.first { $0.displayName.hasPrefix(prefix) }
    }
    let expected: [(function: String, callee: String, arguments: [[String]])] = [
        ("-[_TtC12RuntimeArity22RuntimeArityFinalEvent initWithProfileName:trigger:]",
         "swift_getObjectType", [["self"]]),
        ("RuntimeArity.RuntimeArityFinalEvent.init(", "swift_getObjectType", [["?"]]),
        ("(1) suspend resume partial function for RuntimeArity.resumeFailing(",
         "swift_continuation_throwingResumeWithError", [["r0", "r1"]]),
        ("generic specialization <Swift.Int> of static Swift.MainActor.assumeIsolated",
         "swift_task_getMainExecutor", [[]]),
        ("type metadata completion function for RuntimeArity.RuntimeArityBox",
         "swift_checkMetadataState", [["319", "?"]]),
    ]
    for (name, callee, arguments) in expected {
        guard let found = function(name) else {
            Issue.record("no \(name)")
            continue
        }
        #expect(noteArguments(callee, in: found) == arguments, "\(name) \(callee): \(noteArguments(callee, in: found))")
    }
    let witnessTables = functions.flatMap { noteArguments("swift_getWitnessTable", in: $0) }
    #expect(!witnessTables.isEmpty && witnessTables.allSatisfy { $0.count == 3 && $0.last == "?" },
            "\(witnessTables)")
}

/// The two entries no fixture reaches with a register to spare, pinned to
/// their declarations: `swift_getObjCClassMetadata(const ClassMetadata *)`
/// (Metadata.h:562) and `swift_getOpaqueTypeConformance2(arguments,
/// descriptor, index)` (MetadataLookup.cpp:3237). Terminal and Clarc each
/// rendered one wider than that.
@Test func swiftRuntimeArityEntriesWithoutAFixtureMatchTheirDeclarations() {
    #expect(DisassembledFunction.knownCArity(of: "swift_getObjCClassMetadata") == 1)
    #expect(DisassembledFunction.knownCArity(of: "swift_getOpaqueTypeConformance2") == 3)
}

/// A system library's metadata accessor for a type with no generic
/// parameters takes the request alone, but with no body in the image it took
/// every live register: `runtimearity.swift`'s `sharedActor` rendered
/// `type metadata accessor for Swift.MainActor(0, arg1, arg2)`.
@Test func aSystemNonGenericMetadataAccessorTakesTheRequestAloneIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: "sharedActor")
    }
    let function = try #require(functions.first { $0.displayName.hasPrefix("RuntimeArity.sharedActor(") })
    let text = function.renderPseudo()
    #expect(text.contains("type metadata accessor for Swift.MainActor(0))"), Comment(rawValue: text))
}

/// The generated table against the descriptors it was read from: MainActor,
/// String and URL are not generic; Array and SwiftUI's ModifiedContent are,
/// so their accessors also take generic arguments and are absent.
@Test func theNonGenericAccessorTableLeavesGenericTypesOut() {
    let types = NonGenericMetadataAccessors.types
    #expect(types.count > 10_000)
    #expect(types.contains("Swift.MainActor"))
    #expect(types.contains("Swift.String"))
    #expect(types.contains("Foundation.URL"))
    #expect(!types.contains("Swift.Array"))
    #expect(!types.contains("SwiftUI.ModifiedContent"))
    #expect(DisassembledFunction.knownCArity(of: "type metadata accessor for Swift.MainActor") == 1)
    #expect(DisassembledFunction.knownCArity(of: "type metadata accessor for Swift.Array") == nil)
}

/// Runtime entry points outside the table printed only the operands that
/// were tracked, so a call whose arguments were not tracked read as taking
/// nothing: `runtimearity.swift`'s weak reference rendered
/// `swift_weakLoadStrong()`, `swift_weakAssign(&self.target)` and
/// `swift_weakDestroy()` (GoodLinks had 1,821 `swift_weakLoadStrong()`).
@Test func aWeakReferenceCallShowsEveryArgumentIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture)
    }
    let text = functions.filter { $0.displayName.contains("RuntimeArityWeakBox") }
        .map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(text.contains("swift_weakAssign(&self.target, ?)"), Comment(rawValue: text))
    #expect(text.contains("swift_weakDestroy(?)"), Comment(rawValue: text))
    #expect(!text.contains("swift_weakAssign()") && !text.contains("swift_weakDestroy()")
            && !text.contains("swift_weakAssign(&self.target)\n"), Comment(rawValue: text))
}

/// Every runtime entry added with the weak-reference ones, against its
/// declaration (swift/include/swift/Runtime/HeapObject.h, Enum.h, Error.h,
/// Metadata.h).
@Test func runtimeObjectEntriesMatchTheirDeclarations() {
    let expected: [String: Int] = [
        "swift_setDeallocating": 1, "swift_unownedRetainStrong": 1, "swift_weakLoadStrong": 1,
        "swift_weakDestroy": 1, "swift_unknownObjectWeakDestroy": 1,
        "swift_initStackObject": 2, "swift_initStaticObject": 2, "swift_weakInit": 2, "swift_weakAssign": 2,
        "swift_unknownObjectWeakInit": 2, "swift_unknownObjectWeakAssign": 2, "swift_getEnumCaseMultiPayload": 2,
        "swift_allocObject": 3, "swift_deallocObject": 3, "swift_deallocClassInstance": 3,
        "swift_storeEnumTagMultiPayload": 3, "swift_getErrorValue": 3, "swift_initStructMetadata": 5,
    ]
    for (name, arity) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(DisassembledFunction.knownCArity(of: name) == arity, "\(name)")
    }
}

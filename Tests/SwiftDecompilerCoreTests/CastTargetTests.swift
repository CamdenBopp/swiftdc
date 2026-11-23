import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A cast's target was named from its metadata argument cut at the first
/// `(`, which was meant to drop an accessor's call arguments. It also cut a
/// type that has one: `x is Shelf<(Int, Int)>` rendered
/// `(arg0 as? CastTargets.Shelf<)`. And a generic type's accessor call,
/// whose arguments are the type's parameters, was named by the type alone:
/// `x as? Shelf<T>` rendered `as? CastTargets.Shelf`, a type the program
/// does not have. casttargets.swift states each function's true behaviour.
private func structured(_ path: String) async throws -> [String: String] {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    var texts: [String: String] = [:]
    for function in functions where function.displayName.hasPrefix("CastTargets.") {
        let name = String(function.displayName.dropFirst("CastTargets.".count).prefix { $0 != "(" && $0 != "<" })
        if ["isTupleShelf", "asFunctionShelf", "asIntShelf", "asPlain", "asTuple", "asGenericShelf"].contains(name) {
            texts[name] = function.renderStructured() + "\n---\n" + function.renderPseudo()
        }
    }
    return texts
}

@Test func aCastNamesItsWholeTargetIfPresent() async throws {
    let path = "Fixtures/Sample/libCastTargets.onone.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let texts = try await structured(path)
    let expected = [
        "isTupleShelf": "(arg0 as? CastTargets.Shelf<(Swift.Int, Swift.Int)>)",
        "asFunctionShelf": "(arg0 as? CastTargets.Shelf<(Swift.Int) -> Swift.Int>)",
        "asIntShelf": "(arg0 as? CastTargets.Shelf<Swift.Int>)",
        "asPlain": "(arg0 as? CastTargets.Plain)",
        "asTuple": " as? (Swift.Int, Swift.String)) != nil)",
    ]
    for (name, cast) in expected.sorted(by: { $0.key < $1.key }) {
        let text = try #require(texts[name])
        // Twice: the structured view and the flat one.
        #expect(text.components(separatedBy: cast).count == 3, "\(name):\n\(text)")
    }
    // No view prints a target that stops at an open bracket.
    for (name, text) in texts { #expect(!text.contains("<)"), "\(name):\n\(text)") }
}

@Test func anOptimizedCastNamesItsWholeTargetIfPresent() async throws {
    let path = "Fixtures/Sample/libCastTargets.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let texts = try await structured(path)
    #expect(try #require(texts["isTupleShelf"])
        .contains("return ((arg0 as? CastTargets.Shelf<(Swift.Int, Swift.Int)>) != 0)"))
    #expect(try #require(texts["asTuple"]).contains(" as? (Swift.Int, Swift.String)) != nil)"))
    #expect(try #require(texts["asPlain"]).contains("(arg0 as? CastTargets.Plain)"))
    for (name, text) in texts { #expect(!text.contains("<)"), "\(name):\n\(text)") }
}

/// A target built from the caller's generic parameter is not nameable from
/// the accessor call: the cast stays the runtime call, at both levels.
@Test(arguments: ["libCastTargets.dylib", "libCastTargets.onone.dylib"])
func aCastToAnUninstantiatedGenericTargetStaysRawIfPresent(name: String) async throws {
    let path = "Fixtures/Sample/\(name)"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let text = try #require(try await structured(path)["asGenericShelf"])
    #expect(text.contains("swift_dynamicCast("), Comment(rawValue: text))
    #expect(text.contains("type metadata accessor for CastTargets.Shelf("), Comment(rawValue: text))
    #expect(!text.contains(" as? "), Comment(rawValue: text))
}

@Test func aMetadataArgumentNamesOnlyACompleteType() {
    func name(_ argument: String) -> String? { DisassembledFunction.swiftTypeName(fromMetadata: argument) }
    #expect(name("type metadata for Swift.String") == "Swift.String")
    #expect(name("type metadata for M.Shelf<(Swift.Int, Swift.Int)>") == "M.Shelf<(Swift.Int, Swift.Int)>")
    #expect(name("type metadata for (Swift.Int, Swift.String)") == "(Swift.Int, Swift.String)")
    #expect(name("type metadata for (Swift.Int) -> Swift.Int") == "(Swift.Int) -> Swift.Int")
    // A non-generic accessor: no argument, or its constant request.
    #expect(name("type metadata accessor for M.Plain()") == "M.Plain")
    #expect(name("type metadata accessor for M.Plain(0)") == "M.Plain")
    #expect(name("type metadata accessor for M.Plain(0xff)") == "M.Plain")
    // A name that opens with a group of its own keeps it.
    #expect(name("type metadata accessor for (extension in M):N.Inner()") == "(extension in M):N.Inner")
    // A generic accessor's arguments are the type's parameters.
    #expect(name("type metadata accessor for M.Shelf(0, type metadata for Swift.Int)") == nil)
    #expect(name("type metadata accessor for M.Shelf(?, ?, ?, ?)") == nil)
    // An unproven list or an unknown argument shows nothing about the type.
    #expect(name("type metadata accessor for M.Shelf(…)") == nil)
    #expect(name("type metadata accessor for M.Shelf(?)") == nil)
    #expect(name("type metadata accessor for M.Shelf(arg0)") == nil)
    // An accessor's address, not a call.
    #expect(name("type metadata accessor for M.Shelf") == nil)
    #expect(name("type metadata for ") == nil)
    #expect(name("arg0") == nil)
    #expect(DisassembledFunction.swiftCastIdiom(
        callee: "swift_dynamicCastClass",
        arguments: ["arg0", "type metadata accessor for M.Shelf(…)"]) == nil)
}

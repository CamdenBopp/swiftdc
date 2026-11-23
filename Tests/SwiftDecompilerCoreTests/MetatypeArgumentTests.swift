import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A metatype formal holds type metadata, and metadata was stripped from a
/// call's trailing arguments by its spelling, as the plumbing a generic
/// callee takes after its formals. A metatype in the last position went
/// with it: `describe(Crate<Int>.self)` rendered `describe()` and
/// `trailing(9, String.self)` rendered `trailing(9)`, calls with fewer
/// arguments than they make. metatypeformals.swift states each caller's true
/// behaviour.
private func renders(_ path: String) async throws -> [String: [String]] {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    var views: [String: [String]] = [:]
    for function in functions where function.displayName.hasPrefix("MetatypeFormals.use") {
        let name = String(function.displayName.dropFirst("MetatypeFormals.".count).prefix { $0 != "(" })
        views[name] = [function.renderStructured(), function.renderPseudo()]
    }
    return views
}

@Test func metatypeFormalsStayInTheirCallsIfPresent() async throws {
    let path = "Fixtures/Sample/libMetatypeFormals.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let views = try await renders(path)
    let expected = [
        "useDescribe": ["return MetatypeFormals.describe(MetatypeFormals.Crate<Swift.Int>.self)"],
        // Never trailing, and stripped by no rule: now spelled as the value it is.
        "useLeading": ["return MetatypeFormals.leading(MetatypeFormals.Kind.self, 5)"],
        "useTrailing": ["return MetatypeFormals.trailing(9, Swift.String.self)"],
        // A bound call and a call nested in an expression.
        "useBoth": ["let r0 = MetatypeFormals.trailing(9, Swift.String.self)",
                    "return (MetatypeFormals.describe(Swift.Int.self) + r0)"],
    ]
    for (name, statements) in expected.sorted(by: { $0.key < $1.key }) {
        for text in try #require(views[name]) {
            for statement in statements { #expect(text.contains(statement), "\(name):\n\(text)") }
        }
    }
}

/// -Onone calls the generic functions unspecialized: the metatype formal is
/// followed by the type parameter's metadata, which stays hidden.
@Test func metatypeFormalsStayBesideHiddenGenericMetadataIfPresent() async throws {
    let path = "Fixtures/Sample/libMetatypeFormals.onone.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let views = try await renders(path)
    let expected = [
        "useKeep": "MetatypeFormals.keep<A>(Swift.Int.self)\n",
        // Exactly two arguments: the third word, T's metadata, is plumbing.
        "useSized": "return MetatypeFormals.sized<A>(7, MetatypeFormals.Crate<Swift.Int>.self)\n",
        "useDescribe": "return MetatypeFormals.describe(MetatypeFormals.Crate<Swift.Int>.self)\n",
        "useLeading": "return MetatypeFormals.leading(MetatypeFormals.Kind.self, 5)\n",
        "useTrailing": "return MetatypeFormals.trailing(9, Swift.String.self)\n",
    ]
    for (name, statement) in expected.sorted(by: { $0.key < $1.key }) {
        for text in try #require(views[name]) {
            #expect(text.contains(statement), "\(name):\n\(text)")
            #expect(!text.contains("type metadata"), "\(name) shows plumbing:\n\(text)")
        }
    }
}

/// Only one named type's metadata in a metatype parameter is a source
/// metatype. Everything else keeps its spelling, and the strip its rule.
@Test func onlyAMetatypeParameterTurnsMetadataIntoASourceValue() {
    func source(_ rendered: String, _ type: String) -> String? {
        DisassembledFunction.sourceMetatypeArgument(rendered, parameterType: type)
    }
    #expect(source("type metadata for Swift.Int", "A.Type") == "Swift.Int.self")
    #expect(source("type metadata for Swift.Int", "Any.Type") == "Swift.Int.self")
    #expect(source("type metadata accessor for M.Kind()", "M.Kind.Type") == "M.Kind.self")
    // A spelling with a space binds looser than `.self`.
    #expect(source("type metadata for any M.P", "Any.Type") == "(any M.P).self")
    #expect(source("type metadata for (Swift.Int, Swift.Int)", "Any.Type") == "(Swift.Int, Swift.Int).self")
    // Not a metatype parameter: a pointer that happens to be metadata.
    #expect(source("type metadata for Swift.Int", "Swift.UnsafeRawPointer") == nil)
    #expect(source("type metadata for Swift.Int", "") == nil)
    // A generic accessor takes arguments: its result is not one named type.
    #expect(source("type metadata accessor for M.Crate(0, type metadata for Swift.Int)", "Any.Type") == nil)
    // Not metadata at all.
    #expect(source("arg0", "Any.Type") == nil)
    #expect(source("protocol witness table for Swift.Int : Swift.Hashable in Swift", "Any.Type") == nil)
    #expect(source("type metadata for ", "Any.Type") == nil)
    // The strip still takes metadata by its spelling, and leaves the source value.
    #expect(DisassembledFunction.strippingGenericPlumbing(["7", "Swift.Int.self", "type metadata for Swift.Int"])
        == ["7", "Swift.Int.self"])
}

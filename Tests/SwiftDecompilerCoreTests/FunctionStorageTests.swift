import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An accessor prints as `name.getter : Type`. With a function type, the
/// type's arrow was read as the accessor's own signature:
/// `Panel.combine.setter : (Swift.Int, Swift.Int) -> Swift.Int` was a
/// function of two Ints returning an Int. Its one parameter, the new
/// closure's two words, printed `arg0` and `arg1`, and it ended in a
/// `return ?` for a result a setter does not have. functionstorage.swift
/// states each accessor's true behaviour.
private func accessors(_ path: String) async throws -> [String: [String]] {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    var views: [String: [String]] = [:]
    for function in functions where function.displayName.hasPrefix("FunctionStorage.") {
        let name = function.displayName.dropFirst("FunctionStorage.".count)
        let key = String(name.prefix { $0 != " " && $0 != "(" })
        views[key] = [function.renderStructured(), function.renderPseudo()]
    }
    return views
}

@Test(arguments: ["libFunctionStorage.dylib", "libFunctionStorage.onone.dylib"])
func aFunctionTypedSettersNewValueIsNotItsTypesParametersIfPresent(image: String) async throws {
    let path = "Fixtures/Sample/\(image)"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let views = try await accessors(path)
    for name in ["Panel.combine.setter", "Panel.attempt.setter", "Panel.watched.setter"] {
        for text in try #require(views[name], "\(name)") {
            let property = name.split(separator: ".")[1]
            #expect(text.contains("    self.\(property)"), Comment(rawValue: text))
            #expect(!text.contains("arg"), Comment(rawValue: text))
            #expect(!text.contains("return"), Comment(rawValue: text))
        }
    }
    // The observer's work after the store is still there.
    for text in try #require(views["Panel.watched.setter"]) {
        #expect(text.contains("self.tally += 1") || text.contains("FunctionStorage.Panel.watched.didset()"),
                Comment(rawValue: text))
    }
}

@Test(arguments: ["libFunctionStorage.dylib", "libFunctionStorage.onone.dylib"])
func aFunctionTypedGetterTakesNothingAndReturnsAValueIfPresent(image: String) async throws {
    let path = "Fixtures/Sample/\(image)"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let views = try await accessors(path)
    for name in ["Panel.combine.getter", "Panel.attempt.getter", "Panel.watched.getter"] {
        for text in try #require(views[name], "\(name)") {
            // The closure is two words no rule places yet: unknown, and said so.
            #expect(text.contains("    return ?\n"), Comment(rawValue: text))
            #expect(!text.contains("arg"), Comment(rawValue: text))
        }
    }
}

/// The control: a subscript accessor's printed type is its signature. Its
/// indices are still placed, after self.
@Test func aSubscriptAccessorKeepsItsIndicesIfPresent() async throws {
    let path = "Fixtures/Sample/libFunctionStorage.onone.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    for text in try #require(try await accessors(path)["cell"]) {
        #expect(text.contains("    return FunctionStorage.Grid.subscript.getter(self: ?, arg1, 2)\n"), Comment(rawValue: text))
    }
}

@Test func onlyAFunctionOrASubscriptAccessorHasASignature() {
    func split(_ name: String) -> (head: String, result: String)? {
        DisassembledFunction.splitSignature(name).map { ($0.head, $0.result) }
    }
    // Storage: the arrow is the type's.
    #expect(split("M.Panel.combine.getter : (Swift.Int, Swift.Int) -> Swift.Int") == nil)
    #expect(split("M.Panel.combine.setter : (Swift.Int, Swift.Int) -> Swift.Int") == nil)
    #expect(split("M.Panel.attempt.modify : (Swift.Int) throws -> Swift.Int") == nil)
    #expect(split("variable initialization expression of M.Panel.combine : (Swift.Int) -> Swift.Int") == nil)
    #expect(DisassembledFunction.splitSignature("M.Panel.attempt.getter : (Swift.Int) throws -> Swift.Int")?.isThrowing == nil)
    // A subscript accessor: indices to element.
    let getter = split("M.Grid.subscript.getter : (Swift.Int, Swift.Int) -> Swift.Int")
    #expect(getter?.head == "M.Grid.subscript.getter : (Swift.Int, Swift.Int)" && getter?.result == "Swift.Int")
    #expect(split("M.Grid.subscript.setter : (Swift.Int) -> Swift.Int")?.result == "Swift.Int")
    // A property that only has `subscript` in its path is storage.
    #expect(split("M.subscript.Helper.combine.getter : (Swift.Int) -> Swift.Int") == nil)
    // A function, and a closure inside an accessor, are functions.
    #expect(split("M.f(Swift.Int) -> Swift.Int")?.result == "Swift.Int")
    #expect(split("closure #1 (Swift.Int) -> Swift.Int in M.Panel.combine.getter : (Swift.Int) -> Swift.Int")?.result == "Swift.Int")
    // A local variable's getter is storage too: the arrow after ` in ` is
    // the enclosing function's. It still returns the variable's value,
    // though that function returns nothing.
    let local = "getter of scalar #1 : Swift.Unicode.Scalar in M.T.message(in: Swift.Int) -> ()"
    #expect(split(local) == nil)
    #expect(DisassembledFunction.signatureReturnsValue(displayName: local, objcSignature: nil))
    #expect(!DisassembledFunction.signatureReturnsValue(displayName: "M.T.message(in: Swift.Int) -> ()", objcSignature: nil))
    #expect(DisassembledFunction.isSubscriptAccessorName("M.Grid.subscript.getter : (Swift.Int) -> Swift.Int"))
    #expect(!DisassembledFunction.isSubscriptAccessorName("M.Panel.combine.getter : (Swift.Int) -> Swift.Int"))
    #expect(!DisassembledFunction.isSubscriptAccessorName("M.f(Swift.Int) -> Swift.Int"))
}

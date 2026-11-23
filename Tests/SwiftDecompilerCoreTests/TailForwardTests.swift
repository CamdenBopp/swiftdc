import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A function ending in a branch to a callee that returns its result: the
/// tail-return rule took only callees with a Swift argument list and
/// non-generic callers, so `countLit() { "hello".count }` (`b
/// String.count.getter`) and `dynType<T>(_:)` (`b swift_getDynamicType`)
/// rendered the call with no `return` (`tailforward.swift`, -O).
@Test func aTailBranchToAGetterOrRuntimeEntryReturnsItIfPresent() async throws {
    let path = "Fixtures/Sample/libTailForward.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix(name) }, "no \(name)").renderStructured()
    }
    let count = try structured("TailForward.countLit(")
    #expect(count.contains("return Swift.String.count.getter(\"hello\")"), Comment(rawValue: count))
    let dyn = try structured("TailForward.dynType<")
    #expect(dyn.contains("return swift_getDynamicType("), Comment(rawValue: dyn))
}

/// `AnyObject.Type` is one register (no witness tables follow the
/// metadata), but it was laid out as possibly several: `pick(_:_:_:)`
/// rendered `return ?` and `metaOf`'s `b swift_getObjectType` no return
/// (`anyobjectmeta.swift`, `tailforward.swift`, -O).
@Test func anAnyObjectMetatypeIsOneRegisterIfPresent() async throws {
    let path = "Fixtures/Sample/libAnyObjectMeta.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let pick = try #require(functions.first { $0.displayName.hasPrefix("AnyObjectMeta.pick(") }).renderStructured()
    #expect(pick.contains("return (arg0 ? arg1 : arg2)"), Comment(rawValue: pick))
    let tail = "Fixtures/Sample/libTailForward.dylib"
    guard FileManager.default.fileExists(atPath: tail) else { return }
    let tailFunctions = try await withStableDependencies { try await Disassembler().disassemble(path: tail) }
    let meta = try #require(tailFunctions.first { $0.displayName.hasPrefix("TailForward.metaOf<") }).renderStructured()
    #expect(meta.contains("return swift_getObjectType(arg0)"), Comment(rawValue: meta))
}

/// The eligibility matrix of the C-prototype tail return: a branch to a
/// C-named callee returns its result only when the prototype is that
/// callee's and gives one whole integer register (`tailprototype.swift`).
/// An in-image function that shares a library's name is not the library's
/// function: `viaTwin` read `return strlen()` for a vendored `void strlen`.
@Test func aTailBranchReturnsOnlyAProvenIntegerResultIfPresent() async throws {
    let path = "Fixtures/Sample/libTailPrototype.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("TailPrototype.\(name)(") }, "no \(name)").renderStructured()
    }
    // Imported, `long random(void)`: the one eligible case.
    #expect(try structured("viaRandom").contains("return random()"))
    // In-image twin, void result, float result: each a call, never a return.
    for (name, callee) in [("viaTwin", "strlen("), ("viaVoid", "srandom("), ("viaDouble", "drand48(")] {
        let text = try structured(name)
        #expect(text.contains(callee) && !text.contains("return"), Comment(rawValue: "\(name): \(text)"))
    }
}


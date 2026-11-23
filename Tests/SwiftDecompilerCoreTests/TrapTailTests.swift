import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A tail branch to an unnamed body that writes neither x0 nor v0 is this
/// function's return of what x0 holds: the body is elided and the wrapper
/// reads `return arg0`. That held for a body that can trap or loop first.
/// In a stripped image `wrapNonZero(x) { nonZero(x) }`, whose callee is
/// `precondition(x != 0); return x`, rendered `return arg0`: the
/// precondition was gone, and so was every sign that anything else runs.
/// traptail.swift states each function's true behaviour.
private func wrappers(_ path: String) async throws -> [String: [String]] {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    var views: [String: [String]] = [:]
    for function in functions where function.displayName.hasPrefix("TrapTail.wrap") {
        let name = String(function.displayName.dropFirst("TrapTail.".count).prefix { $0 != "(" })
        views[name] = [function.renderStructured(), function.renderPseudo()]
    }
    return views
}

@Test(arguments: ["wrapNonZero", "wrapAboveThree", "wrapUnlessNine"])
func aTailIntoABodyThatMayNotReturnKeepsItsCallIfPresent(name: String) async throws {
    let path = "Fixtures/Sample/libTrapTail.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    for text in try #require(try await wrappers(path)[name]) {
        // The transfer is there, to the unnamed body, and the wrapper does
        // not claim to return its own argument.
        #expect(text.contains("    sub_"), Comment(rawValue: text))
        #expect(!text.contains("return arg0"), Comment(rawValue: text))
    }
}

/// The control: a body that is a lone `ret` is still its caller's return.
@Test func aTailIntoALoneReturnIsStillTheCallersReturnIfPresent() async throws {
    let path = "Fixtures/Sample/libTrapTail.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    for text in try #require(try await wrappers(path)["wrapSame"]) {
        #expect(text.contains("    return arg0\n"), Comment(rawValue: text))
        #expect(!text.contains("sub_"), Comment(rawValue: text))
    }
}

/// With its symbols the callee has a name and the tail call was always
/// shown: the stripped image must not say less than this.
@Test func aNamedTailIntoATrappingBodyShowsItsCallIfPresent() async throws {
    let path = "Fixtures/Sample/libTrapTail.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let views = try await wrappers(path)
    for text in try #require(views["wrapNonZero"]) {
        #expect(text.contains("    return TrapTail.nonZero(arg0)\n"), Comment(rawValue: text))
    }
    for text in try #require(views["wrapUnlessNine"]) {
        #expect(text.contains("    return TrapTail.unlessNine(arg0)\n"), Comment(rawValue: text))
    }
}

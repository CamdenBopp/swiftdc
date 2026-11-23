import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A throwing function's exit is a throw when x21 holds a proven error: a
/// fresh `swift_allocError` box, or the value `swift_willThrow` was called
/// with. Both helpers were recognized by prefix. A function that copied
/// the null result of `swift_allocErrorLog` to x21 and returned normally
/// rendered `throw ?`, and one that called `swift_willThrowLookalike` with
/// x21 zero rendered `throw 0`. errorlookalike.s states each body's true
/// behaviour.
private func views(_ name: String) async throws -> [String]? {
    let path = "Fixtures/Sample/libErrorLookalike.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let function = try #require(functions.first { $0.displayName.hasPrefix("Lookalike.\(name)(") })
    return [function.renderStructured(), function.renderPseudo()]
}

/// Whether any statement of a render is a throw. The header's `throws` is
/// not one.
private func throwsInBody(_ text: String) -> Bool {
    text.components(separatedBy: "\n").dropFirst()
        .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("throw") }
}

/// A longer spelling, and the exact spelling defined in the image: neither
/// is the runtime's allocator, and what either returns is unknown. The
/// exit is not a throw. It is not a return either: x21 is the callee's
/// result.
@Test(arguments: [("viaAllocLog", "swift_allocErrorLog(arg0)"), ("viaLocalAlloc", "swift_allocError(arg0)")])
func aLookalikeOfTheErrorAllocatorMakesNoThrowIfPresent(name: String, call: String) async throws {
    guard let views = try await views(name) else { return }
    for text in views {
        #expect(text.contains("    \(call)\n"), Comment(rawValue: text))
        #expect(!throwsInBody(text), Comment(rawValue: text))
        #expect(text.contains("    \(DisassembledFunction.unresolvedSwiftExitStatement)\n"), Comment(rawValue: text))
    }
}

/// x21 is zero at the lookalike's call and at the `ret`: a normal return
/// of 6, not a throw of the null the lookalike was "called with".
@Test func aLookalikeOfTheThrowHookMakesNoThrowIfPresent() async throws {
    guard let views = try await views("viaWillThrowLog") else { return }
    for text in views {
        #expect(text.contains("    swift_willThrowLookalike(arg0)\n"), Comment(rawValue: text))
        #expect(!throwsInBody(text), Comment(rawValue: text))
        #expect(text.contains("    return 6\n"), Comment(rawValue: text))
    }
}

/// The control: the runtime's own allocator, bound to libswiftCore, still
/// makes its exit a throw. `fetchOrThrow` leaves through an async return
/// whose error is the box itself, so nothing but the allocator proves it
/// (asyncfns.swift).
@Test(arguments: ["libAsyncFns.dylib", "libAsyncFns.opt.dylib"])
func theRuntimesOwnErrorAllocatorStillMakesAThrowIfPresent(image: String) async throws {
    let path = "Fixtures/Sample/\(image)"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    // The function is several funclets under one title: the throw is in
    // the one that allocates the error.
    let funclets = functions.filter { $0.displayName.contains("AsyncFns.fetchOrThrow(") }.map { $0.renderStructured() }
    let allocating = funclets.filter { $0.contains("swift_allocError(") }
    #expect(allocating.count == 1, "\(funclets)")
    for text in allocating { #expect(throwsInBody(text), Comment(rawValue: text)) }
}

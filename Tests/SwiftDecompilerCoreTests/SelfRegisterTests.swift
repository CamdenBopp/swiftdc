import Foundation
import Testing
@testable import SwiftDecompilerCore

/// x20 carries `self` into a method, is callee-saved across calls, and is
/// kept by a tail call. A tail call to a method of the same receiver,
/// `b C.me`, rendered `return SS.C.me()`, a call with no receiver, though
/// the same call made with `bl` rendered `me(self: self)`
/// (`selfregister.s`, written from the convention's rules).
@Test func aCallOnSelfShowsItsReceiverHoweverItIsMadeIfPresent() async throws {
    let path = "Fixtures/Sample/libSelfRegister.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix(name) }, "no \(name)").renderStructured()
    }
    #expect(try structured("SS.C.me()").contains("return self"))
    // Passed in x20 from another register.
    #expect(try structured("SS.callMe(").contains("return SS.C.me(self: arg0)"))
    // Callee-saved: the second call still has it.
    #expect(try structured("SS.C.twice()").contains("SS.C.me(self: self)\n    SS.C.me(self: self)"))
    // A tail call keeps the caller's x20.
    let tail = try structured("SS.C.tail()")
    #expect(tail.contains("return SS.C.me(self: self)"), Comment(rawValue: tail))
    // A different receiver is moved into x20 first.
    #expect(try structured("SS.C.other(").contains("return SS.C.me(self: arg0)"))
}

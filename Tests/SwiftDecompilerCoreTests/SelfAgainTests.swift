import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A receiver placed in x20 for one call is still there for the next, since
/// x20 is callee-saved: `c.m1() &+ c.m2()` read `Box.m2()` because x20 was
/// read only when written since the last call (`selfagain.swift`, -O, the
/// callees in another module). A callee whose own name proves it a class
/// instance member takes x20 as its self either way.
@Test func aReceiverLeftInX20IsTheNextCallsSelfIfPresent() async throws {
    let path = "Fixtures/Sample/libSelfAgain.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let twice = try #require(functions.first { $0.displayName.hasPrefix("SelfAgain.twice") }).renderStructured()
    #expect(twice.contains("SelfAgainKit.Box.m2(self: arg0)"), Comment(rawValue: twice))
}

/// A caller that parks a call's result in x20 (callee-saved) across the
/// next call writes x20 just before it, but a struct's or enum's method
/// takes its value elsewhere, not in x20: `Pair.sum(self: r0, 1)` and
/// `Mode.code(self: r0)` named m1's result their receiver (`selfagain.swift`).
@Test func aValueTypesMethodTakesNoScalarX20AsSelfIfPresent() async throws {
    let path = "Fixtures/Sample/libSelfAgain.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.filter { $0.displayName.hasPrefix("SelfAgain.with") }.map { $0.renderStructured() }
        .joined(separator: "\n")
    #expect(!text.contains("sum(self: r0"), Comment(rawValue: text))
    #expect(!text.contains("code(self: r0"), Comment(rawValue: text))
}

/// Only a class's instance member takes `self` in x20 whoever wrote it: a
/// struct's or enum's member takes its value elsewhere, and a static member,
/// an allocating initializer or a free function has no instance receiver.
@Test func onlyAClassInstanceMemberTakesX20AsSelf() {
    let index = ClassTypeIndex(qualifiedClassNames: ["M.Box"], qualifiedNonClassNames: ["M.Pair", "M.Mode"])
    #expect(Disassembler.isClassInstanceMember("M.Box.m2() -> Swift.Int", classTypeIndex: index))
    #expect(!Disassembler.isClassInstanceMember("M.Pair.sum(Swift.Int) -> Swift.Int", classTypeIndex: index))
    #expect(!Disassembler.isClassInstanceMember("M.Mode.code() -> Swift.Int", classTypeIndex: index))
    #expect(!Disassembler.isClassInstanceMember("static M.Box.make() -> Swift.Int", classTypeIndex: index))
    #expect(!Disassembler.isClassInstanceMember("M.Box.__allocating_init() -> M.Box", classTypeIndex: index))
    #expect(!Disassembler.isClassInstanceMember("M.free() -> Swift.Int", classTypeIndex: index))
    #expect(!Disassembler.isClassInstanceMember("M.Box.method", classTypeIndex: index))
}

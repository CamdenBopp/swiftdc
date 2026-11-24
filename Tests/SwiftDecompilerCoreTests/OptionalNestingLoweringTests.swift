import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An Optional result is direct when its payload is, with no bound on the
/// nesting or on the pieces a tag adds. That holds only because of what the
/// lowering admits: no admitted payload is four registers with no spare
/// bit pattern, the one shape whose Optional needs a fifth piece and goes
/// through x8. The compiler is the oracle here. A maker whose result type
/// the lowering calls direct must not read the x8 it was entered with, and
/// optionalnesting.swift holds every admitted payload family, nested, next
/// to the Optionals that do cross the boundary.
private struct Maker {
    let name: String
    /// Whether the lowering must call the result type direct.
    let claimed: Bool
    /// Whether the compiled body returns through the caller's buffer.
    let throughX8: Bool
    /// The -O body is `mov x0, xN; ret`, which the linker folds onto an
    /// accessor of `Four` with the same code: its address then has no one
    /// name, and only the -Onone body is checked.
    var foldedWhenOptimized = false
}

private let makers: [Maker] = [
    Maker(name: "makeInt", claimed: true, throughX8: false),
    Maker(name: "makeUInt64", claimed: true, throughX8: false),
    Maker(name: "makeBool", claimed: true, throughX8: false),
    Maker(name: "makeDouble", claimed: true, throughX8: false),
    Maker(name: "makeFloat", claimed: true, throughX8: false),
    Maker(name: "makeRawPointer", claimed: true, throughX8: false),
    Maker(name: "makeObject", claimed: true, throughX8: false),
    Maker(name: "makeArray", claimed: true, throughX8: false),
    Maker(name: "makeMetatype", claimed: true, throughX8: false, foldedWhenOptimized: true),
    Maker(name: "makeKeyPath", claimed: true, throughX8: false),
    Maker(name: "makeUnmanaged", claimed: true, throughX8: false, foldedWhenOptimized: true),
    Maker(name: "makeString", claimed: true, throughX8: false),
    Maker(name: "makeCharacter", claimed: true, throughX8: false),
    Maker(name: "makeScalar", claimed: true, throughX8: false),
    Maker(name: "makeStaticString", claimed: true, throughX8: false),
    // Two words and a tag byte: the widest growth an Optional causes.
    Maker(name: "makeBuffer", claimed: true, throughX8: false),
    // Four words and no tag: the widest payload that stays in registers.
    Maker(name: "makeSubstring", claimed: true, throughX8: false),
    // Four words with no spare pattern, then a tag byte: five pieces.
    Maker(name: "makeFourOptional", claimed: false, throughX8: true),
    Maker(name: "makeBufferPairOptional", claimed: false, throughX8: true),
]

private func checkMakers(in path: String, optimized: Bool) async throws {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let index = ClassTypeIndex()
    let listed = makers.filter { !(optimized && $0.foldedWhenOptimized) }
    for maker in listed {
        let function = try #require(
            functions.first { $0.displayName.hasPrefix("OptionalNesting.\(maker.name)(") },
            Comment(rawValue: "\(path): \(maker.name)"))
        let type = try #require(
            Disassembler.swiftReturnTypeName(ofDemangled: function.displayName),
            Comment(rawValue: function.displayName))
        let use = Disassembler.indirectResultUse(of: function)
        #expect(Disassembler.isKnownDirectReturnType(type, classTypeIndex: index) == maker.claimed,
                Comment(rawValue: "\(path): \(function.displayName)"))
        #expect((use == .reads) == maker.throughX8,
                Comment(rawValue: "\(path): \(function.displayName) is \(use)"))
    }
    // The rule itself, over every function of the module and not only the
    // listed ones: a direct claim and a body that reads its incoming x8
    // never meet.
    var claims = 0
    for function in functions where function.displayName.hasPrefix("OptionalNesting.") {
        guard let type = Disassembler.swiftReturnTypeName(ofDemangled: function.displayName),
              Disassembler.isKnownDirectReturnType(type, classTypeIndex: index)
        else { continue }
        claims += 1
        #expect(Disassembler.indirectResultUse(of: function) != .reads,
                Comment(rawValue: "\(path): \(function.displayName)"))
    }
    #expect(claims >= listed.filter(\.claimed).count, Comment(rawValue: path))
}

@Test func nestedOptionalResultsCalledDirectNeverReturnThroughX8IfPresent() async throws {
    let path = "Fixtures/Sample/libOptionalNesting.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    try await checkMakers(in: path, optimized: true)
}

/// -Onone spills and reloads every piece, and still writes a direct result
/// to registers only.
@Test func nestedOptionalResultsCalledDirectNeverReturnThroughX8UnoptimizedIfPresent() async throws {
    let path = "Fixtures/Sample/libOptionalNesting.onone.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    try await checkMakers(in: path, optimized: false)
}

/// Four words with no tag are direct by themselves: the tag byte is what
/// sends `Four?` through x8, not the payload's size.
@Test func fourWordsWithoutATagStayInRegistersIfPresent() async throws {
    for path in ["Fixtures/Sample/libOptionalNesting.dylib", "Fixtures/Sample/libOptionalNesting.onone.dylib"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: path)
        }
        let four = try #require(functions.first { $0.displayName.hasPrefix("OptionalNesting.makeFour(") })
        #expect(Disassembler.indirectResultUse(of: four) != .reads, Comment(rawValue: path))
    }
}

/// The claims themselves, by type name. Nesting keeps a claim its payload
/// earned and gives none to a payload that has none: a struct, a tuple or
/// a generic parameter stays unknown at every depth.
@Test func nestedOptionalsKeepTheirPayloadsLowering() {
    let index = ClassTypeIndex()
    func nested(_ type: String, _ depth: Int) -> String {
        (0..<depth).reduce(type) { wrapped, _ in "Swift.Optional<\(wrapped)>" }
    }
    let direct = [
        "Swift.Int", "Swift.UInt64", "Swift.Bool", "Swift.Double", "Swift.Float", "Swift.UnsafeRawPointer",
        "Swift.AnyObject", "Swift.Array<Swift.Int>", "Any.Type", "Swift.AnyKeyPath",
        "Swift.Unmanaged<Swift.AnyObject>", "Swift.String", "Swift.Character", "Swift.Unicode.Scalar",
        "Swift.StaticString", "Swift.UnsafeBufferPointer<Swift.UInt8>", "Swift.Substring", "() -> Swift.Int",
    ]
    let unknown = [
        "OptionalNesting.Four", "A",
        "(Swift.UnsafeBufferPointer<Swift.UInt8>, Swift.UnsafeBufferPointer<Swift.UInt8>)",
    ]
    for depth in 1...3 {
        for type in direct {
            #expect(Disassembler.isKnownDirectReturnType(nested(type, depth), classTypeIndex: index),
                    "\(nested(type, depth))")
        }
        for type in unknown {
            #expect(!Disassembler.isKnownDirectReturnType(nested(type, depth), classTypeIndex: index),
                    "\(nested(type, depth))")
        }
    }
    // A pointer or reference Optional is one register only at the first
    // level; the next one is direct without being called one register.
    #expect(SwiftLowering.of("Swift.Optional<Swift.UnsafeRawPointer>") == .oneInteger)
    #expect(SwiftLowering.of("Swift.Optional<Swift.Optional<Swift.UnsafeRawPointer>>") == .direct)
}

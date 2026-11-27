import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An existential metatype is its metadata pointer and one witness table
/// for each protocol of the composition that has one, and a result of five
/// words is returned through x8. The name gives the members and not which
/// of them have tables, so the lowering calls a metatype direct only while
/// one word and a table for every member still fit in four. The compiler is
/// the oracle: a maker whose result type the lowering calls direct must not
/// read the x8 it was entered with.
private struct Maker {
    let name: String
    /// Whether the lowering must call the result type direct.
    let claimed: Bool
    /// Whether the compiled body returns through the caller's buffer.
    let throughX8: Bool
}

private let module = "ExistentialMetatypes"

private let makers: [Maker] = [
    Maker(name: "makeOne", claimed: true, throughX8: false),
    Maker(name: "makeTwo", claimed: true, throughX8: false),
    // Four words: the widest metatype that stays in registers.
    Maker(name: "makeThree", claimed: true, throughX8: false),
    Maker(name: "makeFour", claimed: false, throughX8: true),
    Maker(name: "makeFive", claimed: false, throughX8: true),
    // Four members, of which `Swift.Sendable` and `Swift.AnyObject` are
    // known by name to have no table.
    Maker(name: "makeThreeSendable", claimed: true, throughX8: false),
    Maker(name: "makeThreeObject", claimed: true, throughX8: false),
    // The same two members beside four tables take none of them away.
    Maker(name: "makeFourSendable", claimed: false, throughX8: true),
    Maker(name: "makeFourObject", claimed: false, throughX8: true),
    // Four words in registers, and not claimed: nothing in the name says
    // that the @objc member has no table.
    Maker(name: "makeThreeObjC", claimed: false, throughX8: false),
    Maker(name: "makeConcrete", claimed: true, throughX8: false),
]

private func checkMakers(in path: String) async throws {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let index = ClassTypeIndex()
    for maker in makers {
        let function = try #require(
            functions.first { $0.displayName.hasPrefix("\(module).\(maker.name)(") },
            Comment(rawValue: "\(path): \(maker.name)"))
        let type = try #require(
            Disassembler.swiftReturnTypeName(ofDemangled: function.displayName),
            Comment(rawValue: function.displayName))
        // Every result here is a metatype, so the claim under test is the
        // metatype's and no other rule's.
        #expect(type.hasSuffix(".Type") || type.hasSuffix(".Type>"), Comment(rawValue: function.displayName))
        let use = Disassembler.indirectResultUse(of: function)
        #expect(Disassembler.isKnownDirectReturnType(type, classTypeIndex: index) == maker.claimed,
                Comment(rawValue: "\(path): \(function.displayName)"))
        #expect((use == .reads) == maker.throughX8,
                Comment(rawValue: "\(path): \(function.displayName) is \(use)"))
    }
    // The rule itself, over every function of the module: a direct claim
    // and a body that reads its incoming x8 never meet.
    var claims = 0
    for function in functions where function.displayName.hasPrefix("\(module).") {
        guard let type = Disassembler.swiftReturnTypeName(ofDemangled: function.displayName),
              Disassembler.isKnownDirectReturnType(type, classTypeIndex: index)
        else { continue }
        claims += 1
        #expect(Disassembler.indirectResultUse(of: function) != .reads,
                Comment(rawValue: "\(path): \(function.displayName)"))
    }
    #expect(claims >= makers.filter(\.claimed).count, Comment(rawValue: path))
}

@Test func existentialMetatypeResultsCalledDirectNeverReturnThroughX8IfPresent() async throws {
    let path = "Fixtures/Sample/libExistentialMetatypes.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    try await checkMakers(in: path)
}

/// -Onone spills and reloads every word, and still sends only the
/// five-word metatypes through x8.
@Test func existentialMetatypeResultsCalledDirectNeverReturnThroughX8UnoptimizedIfPresent() async throws {
    let path = "Fixtures/Sample/libExistentialMetatypes.onone.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    try await checkMakers(in: path)
}

/// The claims by type name, as the demangler spells them: the composition
/// is not parenthesized and the suffix sits on its last member.
@Test func metatypeIsDirectOnlyWhileEveryMemberCouldHaveATable() {
    let index = ClassTypeIndex()
    func direct(_ type: String) -> Bool { Disassembler.isKnownDirectReturnType(type, classTypeIndex: index) }
    let fits = [
        // One word: a concrete, generic-parameter or `Any` metatype.
        "M.S.Type", "A.Type", "Any.Type", "Swift.AnyObject.Type", "Swift.Int.Type",
        // Two to four words.
        "M.P1.Type", "M.P1 & M.P2.Type", "M.P1 & M.P2 & M.P3.Type",
        "M.C & M.P1 & M.P2.Type",
        // Four members, one of them without a table by name.
        "M.P1 & M.P2 & M.P3 & Swift.AnyObject.Type",
        "M.P1 & M.P2 & M.P3 & Swift.Sendable.Type",
        "M.P1 & M.P2 & M.P3 & Swift.Sendable & Swift.AnyObject.Type",
        // A metatype of a metatype has the same words and the same members.
        "M.P1 & M.P2 & M.P3 & Swift.AnyObject.Type.Type",
        // A constrained existential's requirements are not members.
        "any M.P1 & M.P2<Self.T == Swift.Int>.Type",
        // A composition inside a generic argument is not this metatype's:
        // the metatype of a concrete generic type is one word or none.
        "M.G<M.P1 & M.P2 & M.P3 & M.P4 & M.P5>.Type",
        "Swift.Array<M.P1 & M.P2 & M.P3 & M.P4>.Type",
        // An arrow's `>` inside the argument closes nothing.
        "M.G<(M.P1) -> M.P1 & M.P2 & M.P3 & M.P4 & M.P5>.Type",
        // The metatype of an existential type itself is one word.
        "(M.P1 & M.P2 & M.P3 & M.P4 & M.P5).Protocol",
        "(M.P1 & M.P2 & M.P3 & M.P4 & M.P5).Protocol.Type",
        // A function returning a five-word metatype is still two words.
        "() -> M.P1 & M.P2 & M.P3 & M.P4.Type",
    ]
    let doesNotFit = [
        "M.P1 & M.P2 & M.P3 & M.P4.Type",
        "M.P1 & M.P2 & M.P3 & M.P4 & M.P5.Type",
        // A metatype of a metatype has the same words.
        "M.P1 & M.P2 & M.P3 & M.P4.Type.Type",
        // The table-less names beside four other members.
        "M.P1 & M.P2 & M.P3 & M.P4 & Swift.AnyObject.Type",
        "M.P1 & M.P2 & M.P3 & M.P4 & Swift.Sendable.Type",
        // A superclass, an @objc protocol or another module's marker has
        // no table, and its name does not say so.
        "M.C & M.P1 & M.P2 & M.P3.Type",
        "M.P1 & M.P2 & M.P3 & M.Sendable.Type",
        "any M.P1 & M.P2 & M.P3 & M.P4<Self.T == Swift.Int>.Type",
    ]
    for type in fits {
        #expect(direct(type), "\(type)")
        #expect(direct("Swift.Optional<\(type)>"), "Optional of \(type)")
    }
    for type in doesNotFit {
        #expect(!direct(type), "\(type)")
        #expect(!direct("Swift.Optional<\(type)>"), "Optional of \(type)")
        #expect(!direct("Swift.Optional<Swift.Optional<\(type)>>"), "nested Optional of \(type)")
    }
    // The one-register claims are untouched.
    #expect(SwiftLowering.of("Any.Type") == .oneInteger)
    #expect(SwiftLowering.of("Swift.AnyObject.Type") == .oneInteger)
    #expect(SwiftLowering.of("M.P1 & M.P2.Type") == .direct)
    #expect(SwiftLowering.of("M.P1 & M.P2 & M.P3 & M.P4.Type") == .unknown)
}

private func clientLines(_ name: String, in path: String, structured: Bool) async throws -> [String] {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let function = try #require(
        functions.first { $0.displayName.hasPrefix("ExistentialMetatypesClient.\(name)(") },
        Comment(rawValue: "\(path): \(name)"))
    let text = structured ? function.renderStructured() : function.renderPseudo()
    return text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
}

private let clientImages = [
    "Fixtures/Sample/libExistentialMetatypesClient.dylib",
    "Fixtures/Sample/libExistentialMetatypesClient.onone.dylib",
]

/// In another image a maker is a stub: only its name says how it returns.
/// A caller of a five- or six-word maker reads the result from the buffer
/// it passed in x8, so its return is neither the call's x0 nor what the
/// buffer held before the call. `staleFour` stores 7 in the buffer first
/// and returns a metadata pointer.
@Test(arguments: [true, false])
func aCallersBufferForAFiveWordMetatypeIsNotReadAsItsOldContentsIfPresent(structured: Bool) async throws {
    for path in clientImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for (caller, call) in [
            ("firstWordOfFour", "ExistentialMetatypes.makeFour(arg0)"),
            ("firstWordOfFive", "ExistentialMetatypes.makeFive(arg0)"),
            ("staleFour", "ExistentialMetatypes.makeFour(arg0)"),
        ] {
            let lines = try await clientLines(caller, in: path, structured: structured)
            #expect(lines.contains(call), "\(path) \(caller): \(lines)")
            #expect(lines.filter { $0.hasPrefix("return") } == ["return ?"], "\(path) \(caller): \(lines)")
        }
    }
}

/// The control: a slot the caller did not pass keeps its value across a
/// call to a maker that returns in registers. `staleThree` returns 9.
@Test(arguments: [true, false])
func aCallersOwnSlotSurvivesACallToAFourWordMetatypeMakerIfPresent(structured: Bool) async throws {
    for path in clientImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let lines = try await clientLines("staleThree", in: path, structured: structured)
        #expect(lines.contains("ExistentialMetatypes.makeThree(arg0)"), "\(path): \(lines)")
        #expect(lines.filter { $0.hasPrefix("return") } == ["return 9"], "\(path): \(lines)")
    }
}

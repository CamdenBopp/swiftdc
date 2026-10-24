import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A rendered literal must spell its bytes. A small Swift string's bytes and
/// a C string were printed between quotes as they were, so the four
/// characters c, backslash, n, d rendered `"c\nd"`, a newline, and `a"b`
/// rendered `"a"b"`, which does not parse; -Onone interpolations escaped
/// their already-escaped pieces again (`"say \\\"hi\\\" …"`). Every case is
/// in `literal_escapes.swift` (-O and -Onone) or `literal_escapes.m` (-O2).
private func pseudo(_ path: String) async throws -> [String: String]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    var byName: [String: String] = [:]
    for function in functions {
        byName[function.displayName] = function.renderPseudo()
    }
    return byName
}

private func body(_ functions: [String: String], _ prefix: String) throws -> String {
    let name = try #require(functions.keys.sorted().first { $0.hasPrefix(prefix) }, "no \(prefix)")
    return functions[name] ?? ""
}

@Test func optimizedSwiftLiteralsSpellTheirBytesIfPresent() async throws {
    guard let functions = try await pseudo("Fixtures/Sample/libLiteralEscapes.dylib") else { return }
    // A String slot's small string.
    let quote = try body(functions, "LiteralEscapes.smallQuote(")
    #expect(quote.contains(#"LiteralEscapes.take("a\"b")"#), "\(quote)")
    let backslash = try body(functions, "LiteralEscapes.smallBackslash(")
    #expect(backslash.contains(#"LiteralEscapes.take("c\\nd")"#), "\(backslash)")
    // A large literal, escaped before this change too.
    let large = try body(functions, "LiteralEscapes.largeBackslash(")
    #expect(large.contains(#"LiteralEscapes.take("a long literal with a \\n backslash")"#), "\(large)")
    // A small string read positionally: `String.append` has no layout.
    let appended = try body(functions, "LiteralEscapes.interpolated(")
    #expect(appended.contains(#"" and a \\n slash")"#), "\(appended)")
}

@Test func unoptimizedSwiftLiteralsSpellTheirBytesOnceIfPresent() async throws {
    guard let functions = try await pseudo("Fixtures/Sample/libLiteralEscapes.Onone.dylib") else { return }
    // The C string handed to the literal initializer.
    let backslash = try body(functions, "LiteralEscapes.smallBackslash(")
    #expect(backslash.contains(#"Swift.String.init("c\\nd", 4, 1)"#), "\(backslash)")
    // The interpolation keeps each piece as it rendered.
    let interpolated = try body(functions, "LiteralEscapes.interpolated(")
    #expect(interpolated.contains(#""say \"hi\" \(local_"#), "\(interpolated)")
    #expect(interpolated.contains(#") and a \\n slash""#), "\(interpolated)")
    // So does the literal folded out of its initializer.
    let stored = try body(functions, "LiteralEscapes.storeBackslash(")
    #expect(stored.contains(#"    "c\\nd"\#n"#), "\(stored)")
}

@Test func cAndObjectiveCLiteralsSpellTheirBytesIfPresent() async throws {
    guard let functions = try await pseudo("Fixtures/Sample/libObjCLiteralEscapes.dylib") else { return }
    for (name, call) in [
        ("_cQuote", #"puts("q\"r")"#),
        ("_cBackslash", #"puts("a\\nb")"#),
        ("_cBoth", #"puts("\\\"")"#),
        ("_objcBackslash", #"NSLog(@"x\\y")"#),
    ] {
        let text = try body(functions, name)
        #expect(text.contains(call), "\(name): \(text)")
    }
}

/// The C-string text both readers share, the dyld cache's included: printable
/// ASCII only, escaped, and cut after 48 characters.
@Test func aCStringRendersPrintableEscapedAndCut() {
    #expect(Disassembler.ReferenceResolver.printableLiteralText(#"a\b"c"#) == #"a\\b\"c"#)
    let long = #"\"# + String(repeating: "x", count: 49)
    #expect(Disassembler.ReferenceResolver.printableLiteralText(long) == #"\\"# + String(repeating: "x", count: 47) + "…")
    #expect(Disassembler.ReferenceResolver.printableLiteralText("") == nil)
    #expect(Disassembler.ReferenceResolver.printableLiteralText("a\nb") == nil)
}

/// The folds find a call's arguments by scanning its text, and toggled at
/// every `"`, so a literal with one escaped quote (`"q\""`) never closed:
/// -Onone kept `Swift.String.init("q\"", 2, 1)` for `sink = "q\""`, and the
/// whole `DefaultStringInterpolation` sequence for `"q\"\(x)"`.
@Test func aLiteralWithAnEscapedQuoteStillFoldsIfPresent() async throws {
    guard let functions = try await pseudo("Fixtures/Sample/libLiteralEscapes.Onone.dylib") else { return }
    let stored = try body(functions, "LiteralEscapes.storeQuote(")
    #expect(stored.contains(#"    "q\""\#n"#) && !stored.contains("String.init"), "\(stored)")
    let interpolated = try body(functions, "LiteralEscapes.interpolatedQuote(")
    #expect(interpolated.contains(#""q\"\(local_"#) && !interpolated.contains("appendLiteral"), "\(interpolated)")
}

/// -Onone builds a literal from its bytes' address and count. Named as a C
/// string, the address showed only printable ASCII, cut after 48
/// characters: a piece with a control character or a non-ASCII byte showed
/// an address, after which the interpolation fold printed the tail alone
/// (`"\(local_40) done"`), and a long literal printed cut, which the folds
/// took for the string. Read as exactly its count, each is whole.
@Test func anOnoneLiteralIsReadAsItsByteCountIfPresent() async throws {
    guard let functions = try await pseudo("Fixtures/Sample/libLiteralEscapes.Onone.dylib") else { return }
    for (name, literal) in [
        ("bell", #""\u{7}ring \(local_40) done""#),
        ("middleBell", #""x=\(local_48) \u{7} y=\(local_50)""#),
        ("accented", #""café \(local_40)""#),
        ("longStore", #""a literal that is longer than forty-eight characters, by a few""#),
        ("longInterp", #""a literal that is longer than forty-eight characters: \(local_40)""#),
    ] {
        let text = try body(functions, "LiteralEscapes.\(name)(")
        #expect(text.contains("    \(literal)\n") && !text.contains("DefaultStringInterpolation"), "\(name): \(text)")
    }
}

/// Only Swift's literal initializer reads its pointer as a counted
/// literal: a C call with the same (address, count, 1) shape keeps the
/// address of a C string it cannot print.
@Test func onlyTheLiteralInitializerReadsACountedLiteralIfPresent() async throws {
    guard let functions = try await pseudo("Fixtures/Sample/libObjCLiteralEscapes.dylib") else { return }
    let text = try body(functions, "_cCountLike")
    #expect(text.contains("countLike(0x") && !text.contains(#"\u{7}"#), "\(text)")
}

/// An interpolation fold was tried at every statement, so after a piece it
/// could not read it was retried from the next append, folded the tail
/// alone and consumed the closing `String(stringInterpolation:)`, which then
/// read as the whole string. A run folds only from its start.
@Test func anInterpolationRunFoldsOnlyFromItsStart() {
    let run = [
        "Swift.DefaultStringInterpolation.init(11, 1)",
        "Swift.DefaultStringInterpolation.appendLiteral(Swift.String.init(?, 6, 1))",
        "Swift.DefaultStringInterpolation.appendInterpolation<A where A: Swift.CustomStringConvertible>(local_40)",
        "Swift.DefaultStringInterpolation.appendLiteral(Swift.String.init(\" done\", 5, 1))",
        "Swift.String.init()",
    ]
    #expect(DisassembledFunction.foldSwiftIdioms(run) == run)
    // Read whole, the same run folds.
    var readable = run
    readable[1] = "Swift.DefaultStringInterpolation.appendLiteral(Swift.String.init(\"ring \", 5, 1))"
    #expect(DisassembledFunction.foldSwiftIdioms(readable) == [#""ring \(local_40) done""#])
}

/// A literal's bytes must agree with the `isASCII` flag its initializer
/// passes; no compiler output disagrees, so this has no fixture.
@Test func aLiteralsBytesMustAgreeWithItsASCIIFlag() {
    #expect(Disassembler.ReferenceResolver.bytes(Array("ring".utf8), agreeWithASCIIFlag: true))
    #expect(Disassembler.ReferenceResolver.bytes(Array("café".utf8), agreeWithASCIIFlag: false))
    #expect(!Disassembler.ReferenceResolver.bytes(Array("café".utf8), agreeWithASCIIFlag: true))
    #expect(!Disassembler.ReferenceResolver.bytes(Array("ring".utf8), agreeWithASCIIFlag: false))
}

import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A Swift literal of 16 bytes or more is the pair (count and flags,
/// `(address − 32) | 1<<63`). Naming the object word's address quoted the C
/// string the linker put 32 bytes before the literal:
/// `LargeStrings.show(0xd000000000000021, ("Seventeen bytes!!" | 0x8000000000000000))`
/// for `show("A literal laid out 32 bytes later")`, and the compare in
/// `matches` named the wrong literal too. An app audit found 0 of 151 such
/// sites rendering the true text.
@Test func aLargeStringLiteralRendersItsOwnTextIfPresent() async throws {
    let path = "Fixtures/Sample/libLargeStrings.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "LargeStrings")
    }
    func render(_ prefix: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix(prefix) }).renderStructured()
    }
    let labels = try render("LargeStrings.labels")
    #expect(labels.contains("LargeStrings.show(\"Seventeen bytes!!\")"), Comment(rawValue: labels))
    #expect(labels.contains("LargeStrings.show(\"A literal laid out 32 bytes later\")"), Comment(rawValue: labels))
    let matches = try render("LargeStrings.matches")
    #expect(matches.contains("\"A literal laid out 32 bytes later\""), Comment(rawValue: matches))
    #expect(!matches.contains("Seventeen"), Comment(rawValue: matches))
}

@Test func largeLiteralsPreserveUTF8ControlsAndPoolingIfPresent() async throws {
    let path = "Fixtures/Sample/libLargeStrings.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "LargeStrings")
    }
    let labels = try #require(functions.first { $0.displayName.hasPrefix("LargeStrings.unicodeLabels(") })
    for text in [labels.renderPseudo(), labels.renderStructured()] {
        for literal in ["Été 🌧️ 東京 — naïve", "e\u{301}e\u{301}e\u{301}e\u{301}e\u{301}e\u{301}",
                        "long\\0embedded\\n\\\"quote\\\"\\\\tail", "a pooled prefix — shared Unicode suffix 🌧️", "shared Unicode suffix 🌧️"] {
            #expect(text.contains("LargeStrings.show(\"\(literal)\")"), Comment(rawValue: text))
        }
    }
    let pooled = try #require(functions.first { $0.displayName.hasPrefix("LargeStrings.pooledUnicode(") }).renderStructured()
    #expect(pooled.contains("LargeStrings.show(\"shared Unicode suffix 🌧️\")"), Comment(rawValue: pooled))
}

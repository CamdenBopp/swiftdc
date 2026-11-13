import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A `__cfstring` entry's characters were read as a C string, so a UTF-16
/// literal stopped at its first zero byte (`@"héllo"` rendered `@"h"`), an
/// ASCII one holding a NUL lost what follows it (`@"a\0b"` rendered
/// `@"a"`), and `@"日本"` and `@""` stayed raw addresses. The entry's flags
/// and length decide now (`cfstrings.m`, -O2).
@Test func aConstantStringIsReadByItsFlagsAndLengthIfPresent() async throws {
    let path = "Fixtures/Sample/libCFStrings.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    #expect(try structured("_plain").contains("NSLog(@\"plain ascii\")"))
    #expect(try structured("_accent").contains("NSLog(@\"héllo\")"))
    #expect(try structured("_kanji").contains("NSLog(@\"日本\")"))
    #expect(try structured("_nul").contains("NSLog(@\"a\\0b\")"))
    #expect(try structured("_empty").contains("NSLog(@\"\")"))
}

/// An entry whose length disagrees with its bytes (length 2 over "abcd")
/// proves neither reading, so it stays its address; read as a C string it
/// rendered `@"abcd"` (`cfstrings_short.s`).
@Test func aConstantStringWhoseLengthDisagreesDeclinesIfPresent() async throws {
    let path = "Fixtures/Sample/libCFStringsShort.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let short = try #require(functions.first { $0.displayName == "_short" }).renderStructured()
    #expect(!short.contains("@\""), Comment(rawValue: short))
}


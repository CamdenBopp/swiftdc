import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `localfirst.s`: the first function's symbol is stripped. objdump opens
/// the listing with `<path>:`, which read as a label, so the unfiltered
/// listing titled the first function with the file's path (`disasm
/// /usr/bin/true` printed `/usr/bin/true:` over its only function).
@Test func theListingNeverNamesAFunctionAfterTheFileIfPresent() async throws {
    let path = "Fixtures/Sample/libLocalFirst.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler(preset: .default).disassemble(path: path) }
    let first = try #require(functions.first)
    #expect(first.symbol.hasPrefix("sub_"), "\(first.symbol)")
    #expect(!functions.contains { $0.symbol.contains("/") || $0.symbol.contains("libLocalFirst") })
    #expect(functions.map(\.symbol).contains("_entry"))
}

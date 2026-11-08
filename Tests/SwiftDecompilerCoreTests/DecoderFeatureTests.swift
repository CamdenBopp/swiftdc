import Testing
import Foundation
@testable import SwiftDecompilerCore

/// llvm-objdump given no CPU or features decodes a plain arm64 slice as
/// ARMv8.0, so the LSE and RCpc atomics clang emits by default printed as
/// `.long` data in the unfiltered listing, while Capstone, which decodes
/// every feature, gave the analysis the instruction. `atomics.c` (-O2):
/// `.long 0xf8e80000` was `ldaddal x8, x0, [x0]`.
@Test func anUnfilteredListingDecodesEveryArchitectureExtensionIfPresent() async throws {
    let path = "Fixtures/Sample/libAtomics.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let mnemonics = functions.flatMap(\.instructions).map { String($0.text.prefix { !$0.isWhitespace }) }
    #expect(!mnemonics.contains(".long"))
    #expect(mnemonics.contains("ldaddal"))
    #expect(mnemonics.contains("casal"))
    #expect(mnemonics.contains("ldapr"))
}

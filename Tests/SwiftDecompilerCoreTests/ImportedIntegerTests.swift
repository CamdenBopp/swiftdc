import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An imported C enum or option set passes as its raw integer, which the
/// image proves by binding the type's value witness table to the builtin
/// integer's (`_$sBi64_WV`). Unseeded, `describe(_: ComparisonResult)`,
/// which returns its argument, read `return ?` (`importedenum.swift`).
@Test func anImportedIntegerParameterIsSeededIfPresent() async throws {
    let path = "Fixtures/Sample/libImportedEnum.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func pseudo(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("ImportedEnum.\(name)(") }).renderStructured()
    }
    let describe = try pseudo("describe"), raw = try pseudo("rawOptions")
    #expect(describe.contains("return arg0") && describe.contains("(arg0 + 1) >=ᵁ 3"), Comment(rawValue: describe))
    #expect(raw.contains("return arg0"), Comment(rawValue: raw))
    let machO = try BinaryLoader.load(path: path)
    #expect(EnumCaseIndex.importedIntegerBits(in: machO) == ["__C.NSComparisonResult": 64, "__C.NSStringCompareOptions": 64])
}

@Test func onlyABuiltinIntegerWitnessTableNamesAWidth() {
    #expect(EnumCaseIndex.builtinIntegerWidth(ofWitnessTable: "_$sBi64_WV") == 64)
    #expect(EnumCaseIndex.builtinIntegerWidth(ofWitnessTable: "_$sBi32_WV") == 32)
    #expect(EnumCaseIndex.builtinIntegerWidth(ofWitnessTable: "_$sBi128_WV") == nil)
    #expect(EnumCaseIndex.builtinIntegerWidth(ofWitnessTable: "_$sBo_WV") == nil)
    #expect(EnumCaseIndex.builtinIntegerWidth(ofWitnessTable: "_$sSiWV") == nil)
}

import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `scvtf` reads its operand as signed. On an argument typed `UInt`,
/// `scvtf d0, x0; ret` rendered `return Double(arg0)`, which reads as the
/// unsigned conversion: wrong for every value with the top bit set
/// (`signedfloat.swift`). A signed argument still renders plain.
@Test func aSignedConversionOfAnUnsignedArgumentKeepsItsBitPatternIfPresent() async throws {
    let path = "Fixtures/Sample/libSignedFloat.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix(name) }, "no \(name)").renderStructured()
    }
    let si = try structured("SignedFloat.si(")
    #expect(si.contains("return Double(Int(bitPattern: arg0))"), Comment(rawValue: si))
    let widen = try structured("SignedFloat.widen(")
    #expect(widen.contains("Double(arg0)") && !widen.contains("bitPattern"), Comment(rawValue: widen))
}

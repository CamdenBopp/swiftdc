import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A small struct of scalars is passed one register per field. The set of
/// integer field types that lowering accepted held `Int`, `UInt`, `Bool`
/// and the 8-, 16- and 32-bit integers, but not `Int64` or `UInt64`, which
/// are one i64 each as `Int` is. A struct with one such field declined
/// whole: `wideCombine(_ w: Wide, _ k: UInt64) { w.a &- k &* w.b }`
/// rendered `return ?`, and so did every `OptionSet` with a `UInt64` raw
/// value. int64fields.swift states each function's true behaviour.
private func structured(_ path: String, _ name: String) async throws -> String {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let function = try #require(functions.first { $0.displayName.hasPrefix("Int64Fields.\(name)(") })
    return function.renderStructured()
}

@Test func int64AndUInt64StructFieldsAreReadFromRegistersIfPresent() async throws {
    let path = "Fixtures/Sample/libInt64Fields.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let expected = [
        "wideCombine": "return (arg0.a - (arg1 * arg0.b))",
        "signedLess": "return (arg0.a < arg0.b)",
        // The Double between rides in d0 and does not shift the integers.
        "mixedSum": "return (arg0.raw + (arg1 * arg0.n))",
        "flagsUnion": "return (arg1.rawValue | arg0.rawValue)",
        // self exploded, then the formal.
        "Wide.mix": "return ((self.b ^ self.a) + arg0)",
        // The control never depended on the new entries.
        "wordsCombine": "return (arg0.a + (arg1 * arg0.b))",
    ]
    for (name, statement) in expected.sorted(by: { $0.key < $1.key }) {
        let text = try await structured(path, name)
        #expect(text.contains(statement), "\(name):\n\(text)")
    }
}

/// -Onone spills each field register to the frame before reading it: the
/// same seeds, a different lowering.
@Test func int64AndUInt64StructFieldsAreReadFromRegistersUnoptimizedIfPresent() async throws {
    let path = "Fixtures/Sample/libInt64Fields.onone.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let expected = [
        "wideCombine": "return (arg0.a - (arg0.b * arg1))",
        "signedLess": "return (arg0.a < arg0.b)",
        "mixedSum": "return ((arg1 * arg0.n) + arg0.raw)",
        "flagsUnion": "return (arg0.rawValue | arg1.rawValue)",
        "Wide.mix": "return ((self.a ^ self.b) + arg0)",
    ]
    for (name, statement) in expected.sorted(by: { $0.key < $1.key }) {
        let text = try await structured(path, name)
        #expect(text.contains(statement), "\(name):\n\(text)")
    }
}

/// The lowering question itself, per type: one general register per 64-bit
/// field, and the Double in its own bank.
@Test func int64AndUInt64FieldsLowerToOneGeneralRegisterEachIfPresent() throws {
    let path = "Fixtures/Sample/libInt64Fields.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let maps = try FieldMapBuilder.build(in: try BinaryLoader.load(path: path))
    func banks(_ type: String) throws -> [Bool]? {
        try #require(maps["Int64Fields.\(type)"]).mixedScalarFieldBanksInRegisters?.map(\.isFloat)
    }
    #expect(try banks("Wide") == [false, false])
    #expect(try banks("Signed") == [false, false])
    #expect(try banks("Mixed") == [false, false, true])
    #expect(try banks("Flags") == [false])
    #expect(try banks("Words") == [false, false])
}

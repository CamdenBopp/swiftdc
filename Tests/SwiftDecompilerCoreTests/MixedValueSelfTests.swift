import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A value struct of scalars from both banks passes each field in the next
/// register of its own bank, after the formals (`mixedself.swift`, -O):
/// `Gauge { level: Int, scale: Double, limit: Int32 }` arrives as x0, d0,
/// w1. Only all-Int and all-float structs were seeded, so `scaled()`
/// rendered `return ?` and an x20 seed claimed a self the method never
/// reads. Fields sharing an 8-byte unit merge into one register and a
/// fifth field goes by address, so those still decline.
@Test func aMixedBankValueSelfIsReadFromItsRegistersIfPresent() async throws {
    let path = "Fixtures/Sample/libMixedSelf.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix(name) }, "no \(name)").renderStructured()
    }
    let scaled = try structured("MixedSelf.Gauge.scaled(")
    #expect(scaled.contains("return ((self.scale * Double(self.level)) + Double("), Comment(rawValue: scaled))
    #expect(scaled.contains("self.limit"), Comment(rawValue: scaled))
    let scaledBy = try structured("MixedSelf.Gauge.scaledBy(")
    #expect(scaledBy.contains("((self.scale - arg1) * Double((self.level - arg0)))"), Comment(rawValue: scaledBy))
    let narrow = try structured("MixedSelf.Narrow.sum(")
    #expect(narrow.contains("self.tag") && narrow.contains("- self.count)"), Comment(rawValue: narrow))
    // A struct parameter, likewise, before the parameters after it:
    // `withGauge(_ g: Gauge, _ k: Int)` has k in x2.
    let with = try structured("MixedSelf.withGauge(")
    #expect(with.contains("return (arg0.scale * Double((arg1 + arg0.level)))"), Comment(rawValue: with))
    // Two Int32 fields share x0; five fields go through x20.
    #expect(try structured("MixedSelf.Packed.diff(").contains("return ?"))
    #expect(try structured("MixedSelf.Wide.sum(").contains("return ?"))

}

/// A class's fields start after its header (0x10) and its instance goes in
/// x20, never as its fields. Taken for a mixed-bank struct, `Gauge.raw`
/// (a class getter) lost its receiver at every call site: `Gauge.raw.getter()`
/// for `Gauge.raw.getter(self: self)` (`auditsemantics.swift`, -O).
@Test func aClassIsNotTakenForAMixedBankStructIfPresent() async throws {
    let path = "Fixtures/Sample/libAuditSemantics.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let value = try #require(functions.first { $0.displayName.hasPrefix("AuditSemantics.Counter.value.getter") })
        .renderStructured()
    #expect(value.contains("AuditSemantics.Gauge.raw.getter(self: self)"), Comment(rawValue: value))
}


import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A struct too large for registers is passed by address in one integer
/// register, and that address is the parameter. It was counted but never
/// seeded, so `callWide(_ value: Wide, _ k: Int) { value.sum(k) }` (`mov
/// x20, x0; mov x0, x1; bl Wide.sum`) dropped the receiver:
/// `Wide.sum(arg1)` (`imported_receiver.swift`, -O).
@Test func aStructPassedByAddressIsItsParameterIfPresent() async throws {
    let path = "Fixtures/Sample/libImportedReceiver.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let call = try #require(functions.first { $0.displayName.hasPrefix("ImportedSelf.callWide(") }).renderStructured()
    #expect(call.contains("return ImportedSelf.Wide.sum(self: arg0, arg1)"), Comment(rawValue: call))
}

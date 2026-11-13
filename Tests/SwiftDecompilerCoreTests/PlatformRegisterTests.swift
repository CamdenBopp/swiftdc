import Foundation
import Testing
@testable import SwiftDecompilerCore

/// x18 is the platform register: nothing promises it survives a call.
/// `mov x18, #7; bl ext; mov x0, x18; ret` rendered `return 7`
/// (`platformregister.s`). With no call between, its value still reads.
@Test func thePlatformRegisterDoesNotSurviveACallIfPresent() async throws {
    let path = "Fixtures/Sample/libPlatformRegister.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix(name) }, "no \(name)").renderStructured()
    }
    let across = try structured("PlatformRegister.x18Across")
    #expect(across.contains("return ?") && !across.contains("return 7"), Comment(rawValue: across))
    let local = try structured("PlatformRegister.x18Local")
    #expect(local.contains("return ((arg0 << 1) + 1)"), Comment(rawValue: local))
}

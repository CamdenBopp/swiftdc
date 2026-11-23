import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A call whose result only decides a branch is inlined into the condition
/// and dropped from the statements. When both arms render nothing (each
/// only sets the result of a function with none proven), the `if` is
/// dropped, and `probeLevel` rendered `{ return }` with its `sysctl` gone
/// (`consumed_call.c`). The call stands where it ran; an `if` that keeps a
/// body keeps the call in its condition, once.
@Test func aCallDecidingAnEmptyBranchStillRendersIfPresent() async throws {
    let path = "Fixtures/Sample/libConsumedCall.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    let level = try structured("_probeLevel")
    #expect(level.components(separatedBy: "sysctl(arg0, 2, 0, 0, 0, 0)").count == 2, Comment(rawValue: level))
    let warn = try structured("_probeOrWarn")
    #expect(warn.components(separatedBy: "sysctl(").count == 2, Comment(rawValue: warn))
    #expect(warn.contains("if (!sysctl("), Comment(rawValue: warn))
}

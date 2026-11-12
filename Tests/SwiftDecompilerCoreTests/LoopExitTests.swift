import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An exit from an inner loop that leaves the outer loop too
/// (`loopexit.swift`, -O). The inner loop's exit is where the structurer
/// stops, so the text after the inner loop is the rest of the outer loop's
/// body, and a `break` ran it: `stopAll` read `if (ext(?) == 6) { break }`
/// into `sink(-i)` and the outer test, where the code returns. Such an exit
/// is spelled out: the tail it reaches, or a goto to the code after both.
@Test func anExitLeavingTwoLoopsIsNotABreakIfPresent() async throws {
    let path = "Fixtures/Sample/libLoopExit.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func exitLine(_ name: String) throws -> String {
        let text = try #require(functions.first { $0.displayName.hasPrefix(name) }, "no \(name)").renderStructured()
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let test = try #require(lines.firstIndex { $0.hasPrefix("if (LoopExit.ext(?) == 6)") }, Comment(rawValue: text))
        return lines[test + 1]
    }
    #expect(try exitLine("LoopExit.stopAll") == "return")
    #expect(try exitLine("LoopExit.leaveBoth") == "return")
    let outer = try exitLine("LoopExit.breakOuter")
    #expect(outer.hasPrefix("goto loc_"), Comment(rawValue: outer))
    let text = try #require(functions.first { $0.displayName.hasPrefix("LoopExit.breakOuter") }).renderStructured()
    let label = String(outer.dropFirst("goto ".count)) + ":"
    let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    let at = try #require(lines.firstIndex(of: label), Comment(rawValue: text))
    #expect(lines[at + 1] == "LoopExit.sink(100)", Comment(rawValue: text))
}

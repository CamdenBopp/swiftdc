import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `swift_willThrow` is called with an error about to be thrown, so the
/// value it was called with, found in x21 at an exit, makes that exit a
/// throw. The values were collected over the whole function. On a path
/// that never ran the hook, the same value in x21 proved nothing, and was
/// still read as thrown: with `x21 = arg1` on both arms of a branch and
/// the hook on one, both arms rendered `throw arg1`. hookpath.s states
/// each body's true behaviour.
private func lines(_ name: String, structured: Bool) async throws -> [String]? {
    let path = "Fixtures/Sample/libHookPath.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let function = try #require(functions.first { $0.displayName.hasPrefix("HookPath.\(name)(") })
    let text = structured ? function.renderStructured() : function.renderPseudo()
    return text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
}

private let unresolved = DisassembledFunction.unresolvedSwiftExitStatement

/// Two exits: the arm with the hook throws its value, the arm without it
/// is neither a throw nor a return.
@Test func aHookOnOneArmDoesNotMakeTheOtherArmAThrowIfPresent() async throws {
    guard let lines = try await lines("either", structured: true) else { return }
    let hook = try #require(lines.firstIndex(of: "swift_willThrow(arg1)"), "\(lines)")
    #expect(lines[hook + 1] == "throw arg1", "\(lines)")
    #expect(lines.filter { $0.hasPrefix("throw") }.count == 1, "\(lines)")
    #expect(lines.filter { $0 == unresolved }.count == 1, "\(lines)")
    // The unresolved exit is the other arm's: before the hook's arm here.
    #expect(try #require(lines.firstIndex(of: unresolved)) < hook, "\(lines)")
}

/// One shared `ret`: the path through the hook ends in a throw, and the
/// path around it reaches an exit that stays unresolved.
@Test func aHookOnOnePathIntoASharedExitThrowsOnThatPathOnlyIfPresent() async throws {
    guard let lines = try await lines("merged", structured: true) else { return }
    let hook = try #require(lines.firstIndex(of: "swift_willThrow(arg1)"), "\(lines)")
    #expect(lines[hook + 1].hasPrefix("throw"), "\(lines)")
    #expect(lines.filter { $0.hasPrefix("throw") }.count == 1, "\(lines)")
    #expect(lines.last { !$0.isEmpty && $0 != "}" } == unresolved, "\(lines)")
}

/// The control: a hook every path runs still makes the exit a throw of
/// its value, in both views.
@Test(arguments: [true, false])
func aHookEveryPathRunsStillMakesAThrowIfPresent(structured: Bool) async throws {
    guard let lines = try await lines("always", structured: structured) else { return }
    #expect(lines.contains("swift_willThrow(arg1)"), "\(lines)")
    #expect(lines.contains("throw arg1"), "\(lines)")
    #expect(!lines.contains(unresolved), "\(lines)")
}

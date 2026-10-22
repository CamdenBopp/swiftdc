import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A runtime entry point of known C arity keeps its arity when none of its
/// operands is tracked (`untracked_args.c`). With nothing to record, no call
/// site existed, and the call rendered as one that takes nothing:
/// `memmove()` at -O2, `free()` at -O0.
@Test(arguments: ["Fixtures/Sample/libUntrackedArgs.dylib", "Fixtures/Sample/libUntrackedArgs.opt.dylib"])
func untrackedOperandsKeepTheCalleesKnownArityIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let expected: [String: String] = [
        "_moveJob": path.hasSuffix(".opt.dylib") ? "memmove(?, ?, ?)" : "__memmove_chk(?, ?, ?, -1)",
        "_freeJob": "free(?)",
    ]
    for (name, call) in expected.sorted(by: { $0.key < $1.key }) {
        guard let function = functions.first(where: { $0.displayName == name }) else {
            Issue.record("no \(name) in \(path)")
            continue
        }
        for (view, text) in [("pseudo", function.renderPseudo()), ("structured", function.renderStructured())] {
            let lines = text.components(separatedBy: "\n").dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            #expect(lines.first == call, "\(path) \(name) \(view):\n\(text)")
        }
    }
}

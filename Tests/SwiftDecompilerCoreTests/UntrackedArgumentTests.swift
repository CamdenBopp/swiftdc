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
        // bzero and malloc had no known arity: `bzero()`, `malloc()`.
        "_clearJob": path.hasSuffix(".opt.dylib") ? "bzero(?, ?)" : "__memset_chk(?, 0, ?, -1)",
        "_growJob": "malloc(?)",
        "_findJob": "memchr(?, ?, ?)",
        "_sizeJob": "malloc_size(?)",
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

/// Each entry the known-arity table gained for a call the apps printed
/// with nothing tracked as taking nothing, checked against its header.
@Test func theKnownArityTableTakesEachHeadersParameters() {
    let expected: [String: Int] = [
        "malloc": 1, "objc_enumerationMutation": 1, "CFRelease": 1,
        "bzero": 2, "dispatch_async": 2, "dispatch_sync": 2, "swift_getKeyPath": 2, "swift_slowAlloc": 2,
        "swift_once": 3, "swift_slowDealloc": 3,
        "malloc_size": 1, "_Block_release": 1, "objc_destroyWeak": 1,
        "os_unfair_lock_unlock": 1, "swift_dynamicCastClass": 2, "swift_conformsToProtocol": 2,
        "swift_task_isCurrentExecutor": 2, "sqlite3_column_type": 2, "sqlite3_column_int64": 2,
        "objc_getAssociatedObject": 2, "dispatch_once": 2, "memchr": 3,
        "swift_getAssociatedTypeWitness": 5, "swift_task_create": 5, "swift_task_reportUnexpectedExecutor": 6,
    ]
    for (callee, arity) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(DisassembledFunction.knownCArity(of: callee) == arity, "\(callee)")
    }
}

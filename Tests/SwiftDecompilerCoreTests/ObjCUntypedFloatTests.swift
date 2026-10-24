import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An Objective-C send with no signature lays its explicit arguments out
/// as integers from x2 (`objc_untyped_float.m`). A double travels in d0, so
/// `[o put:1.5 at:7]` rendered `put:7 at:?`, the 7 read as the double. A
/// write to v0–v7 left for the send (in its block, after the previous call,
/// not stored to memory) disproves the integer layout, and the arguments
/// decline. A register stored after its write was a copy temporary (a
/// double copied through d0), not an argument.
@Test(arguments: ["Fixtures/Sample/libObjCUntypedFloat.dylib", "Fixtures/Sample/libObjCUntypedFloat.opt.dylib"])
func anUntypedSendPassingAFloatDeclinesItsArgumentsIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    var expected: [String: String] = [
        "_putValue": "[? put:? at:?]",
        "_putLoaded": "[? put:? at:?]",
        "_takeInts": "[? take:3 and:4]",
        // A double computed in a branch before the send's block, or before
        // an intervening call, is not left for the send.
        "_takeAfterBranch": "[? take:3 and:4]",
        "_takeAfterCall": "[? take:3 and:4]",
        // A double copied through d0 just before the send is a temporary.
        "_copyThenTake": "[? take:3 and:4]",
        // The 128-bit zeroing of the enumeration state is no float.
        "_countAll": "[? countByEnumeratingWithState:local_",
    ]
    // A method's own double, in d0 from its entry at -O2 or reloaded there
    // at -O0, may be the send's; its long may not.
    let optimized = path.hasSuffix(".opt.dylib")
    expected["-[Relay relay:to:]"] = optimized ? "[arg1 put:? at:?]" : "[? put:? at:?]"
    expected["-[Relay relayCount:to:]"] = optimized ? "[arg1 take:arg0 and:4]" : "[? take:? and:4]"
    // A call since the entry has clobbered the double.
    expected["-[Relay relayAfterCall:to:]"] = optimized ? "[arg1 take:3 and:4]" : "[? take:3 and:4]"
    // -O0 reloads the double parameter into d0; -O2 passes it untouched,
    // and a C function has no signature to say d0 holds an argument (OPEN).
    if !path.hasSuffix(".opt.dylib") { expected["_putPassed"] = "[? put:? at:?]" }
    for (name, send) in expected.sorted(by: { $0.key < $1.key }) {
        guard let function = functions.first(where: { $0.displayName == name }) else {
            Issue.record("no \(name) in \(path)")
            continue
        }
        let lines = function.renderPseudo().components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains { $0.hasPrefix(send) }, "\(path) \(name):\n\(lines.joined(separator: "\n"))")
    }
}

import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An Objective-C send with no signature lays its explicit arguments out
/// as integers from x2 (`objc_untyped_float.m`). A double travels in d0, so
/// `[o put:1.5 at:7]` rendered `put:7 at:?`, the 7 read as the double. A
/// write to v0–v7 left for the send (in its block, after the previous call,
/// not stored to memory) disproves the integer layout, and the arguments
/// decline. A register stored after its write was a copy temporary (a
/// double copied through d0), not an argument. A call before the send
/// writes v0 with its result, if it has one: a callee no signature or body
/// proves leaves nothing there declines the send too.
@Test(arguments: ["Fixtures/Sample/libObjCUntypedFloat.dylib", "Fixtures/Sample/libObjCUntypedFloat.opt.dylib"])
func anUntypedSendPassingAFloatDeclinesItsArgumentsIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    var expected: [String: String] = [
        "_putValue": "[? put:? at:?]",
        "_putLoaded": "[? put:? at:?]",
        // A call's double result in d0: an indirect call proves nothing.
        "_putCall": "[? put:? at:?]",
        // A callee whose body writes no v register leaves nothing there.
        "_takeAfterIntCall": "[? take:3 and:4]",
        "_takeInts": "[? take:3 and:4]",
        // A double computed in a branch before the send's block is not
        // left for the send.
        "_takeAfterBranch": "[? take:3 and:4]",
        // `useDouble`'s body ends `fcvtzs d0, d0; str d0, [x8]`: it leaves
        // a value in d0, which a callee returning a double does the same
        // way, so the send after the call declines.
        "_takeAfterCall": "[? take:? and:?]",
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
    // The call to `useDouble` since the entry clobbered the double, and
    // leaves d0 written, so the send declines as `takeAfterCall`'s does.
    expected["-[Relay relayAfterCall:to:]"] = optimized ? "[arg1 take:? and:?]" : "[? take:? and:?]"
    // -O0 reloads the double parameter into d0; -O2 passes it untouched.
    // A C function has no signature to say how many floats it was passed,
    // so v0-v7 untouched from its entry may hold one, and `putPassed` sets
    // up x2 but not x3, the gap a float argument leaves: the integer layout
    // declines. It read `put:7 at:?` at -O2. `takeInts` sets up both of its
    // registers, so a float in d0 would make one of those writes dead, and
    // it keeps `take:3 and:4`.
    expected["_putPassed"] = "[? put:? at:?]"
    // At -O2 the C functions keep `o` from their entry, and a signatureless
    // body that reads it proves it is their first parameter.
    if optimized {
        expected["_putLoaded"] = "[arg0 put:? at:?]"
        for name in ["_takeAfterBranch", "_copyThenTake"] { expected[name] = "[arg0 take:3 and:4]" }
        expected["_takeAfterCall"] = "[arg0 take:? and:?]"
        expected["_putCall"] = "[arg0 put:? at:?]"
        expected["_takeAfterIntCall"] = "[arg0 take:3 and:4]"
    }
    for (name, send) in expected.sorted(by: { $0.key < $1.key }) {
        guard let function = functions.first(where: { $0.displayName == name }) else {
            Issue.record("no \(name) in \(path)")
            continue
        }
        let lines = function.renderPseudo().components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains { $0.hasPrefix(send) }, "\(path) \(name):\n\(lines.joined(separator: "\n"))")
    }
}

/// An Objective-C method's return is read from the register its encoding
/// says: `-(double)scaled:` from v0, and a struct returned in d0-d3 or
/// through x8 from none. Read from x0 whatever the encoding, each read
/// `return self` (`objcreturns.m`, ABI review item 4).
@Test func anObjCReturnIsReadWhereItsEncodingPutsItIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCReturns.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }).renderStructured()
    }
    #expect(try text("-[Rets scaled:]").contains("return (arg0 * self->_scale)"))
    for name in ["-[Rets big]", "-[Rets rect:]"] {
        let body = try text(name)
        #expect(body.contains("return ?") && !body.contains("return self"), Comment(rawValue: body))
    }
    #expect(try text("-[Rets count]").contains("return self->_n"))
    // A double constant returned in d0 is its value, not its bit pattern.
    let outgoing = "Fixtures/Sample/libObjCOutgoing.dylib"
    if FileManager.default.fileExists(atPath: outgoing) {
        let probe = try await withStableDependencies { try await Disassembler().disassemble(path: outgoing) }
        let float = try #require(probe.first { $0.displayName == "-[SDOutgoingProbe floatResult]" }).renderStructured()
        #expect(float.contains("return 2.5\n"), Comment(rawValue: float))
    }
}

/// A struct of floats comes back in v0-v3, so a method returning a CGRect
/// that tail-calls a C function declared to return one forwards it whole:
/// `-[SDLanes scaledFrame]` is `return CGRectInset(…)` (`objc_struct_lanes.m`).
@Test func aFloatStructReturnForwardedByATailCallIsThatCallIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCStructLanes.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.displayName == "-[SDLanes scaledFrame]" }).renderStructured()
    #expect(text.contains("return CGRectInset(?, [self scale], 0.5)"), Comment(rawValue: text))
}

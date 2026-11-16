import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A local function, a `defer` body included, takes its captures after
/// its formals, so a call to one is laid out by what its body reads, as a
/// closure's is. By its printed list, `$defer #1 ()` took whatever x0
/// held: `$defer #1 (r0)`, the result of the call before it, and with one
/// capture `$defer #1 (arg0, r0)` (`localfunction.swift`, -Onone).
@Test func aLocalFunctionCallTakesWhatItsBodyReadsIfPresent() async throws {
    let path = "Fixtures/Sample/libLocalFunction.Onone.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("LF.\(name)(") }, "no \(name)").renderStructured()
    }
    // No formal and no capture: no argument.
    let plain = try structured("deferred")
    #expect(plain.contains("$defer #1 ()\n"), Comment(rawValue: plain))
    // One capture: exactly it.
    let capturing = try structured("deferredCapture")
    #expect(capturing.contains("$defer #1 (arg0)\n"), Comment(rawValue: capturing))
    // A formal and two captures, in that order.
    let outer = try structured("outer")
    #expect(outer.contains("mix #1 (arg2, arg0, arg1)") && outer.contains("mix #1 ((arg2 + 1), arg0, arg1)"),
            Comment(rawValue: outer))
}

@Test func aLocalFunctionIsNamedByItsDiscriminator() {
    for name in ["closure #1 (Swift.Int) -> Swift.Int in M.f() -> ()",
                 "implicit closure #2 () -> Swift.Bool in M.f() -> ()",
                 "mix #1 (Swift.Int) -> Swift.Int in M.outer(Swift.Int) -> Swift.Int",
                 "$defer #1 () -> () in M.f(Swift.Int) -> Swift.Int",
                 "helper #12 <A>(A) -> () in M.f() -> ()",
                 // An async-let child: the attribute follows the discriminator.
                 "implicit closure #1 @Sendable () async -> Swift.Int in M.f() async -> Swift.Int"] {
        #expect(DisassembledFunction.isLocalFunctionName(name), "\(name)")
    }
    for name in ["M.f(Swift.Int) -> Swift.Int", "sub_1000", "memcpy",
                 "M.T.subscript.getter : (Swift.Int) -> Swift.Int",
                 // The discriminator is the enclosing function's, not the callee's.
                 "M.T.g(Swift.Int) -> Swift.Int in conformance #1 (x)",
                 "generic specialization <Swift.Int> of M.f<A>(A) -> ()",
                 "mix # (Swift.Int) -> Swift.Int", "#1 (Swift.Int) -> Swift.Int",
                 // A thunk or merged function naming one has its own convention.
                 "partial apply forwarder for closure #1 (Swift.Int) -> Swift.Int in M.f() -> ()",
                 "merged closure #3 (Swift.Int) -> Swift.Bool in M.f() -> ()",
                 "M.T.closure #1 (Swift.Int) -> ()"] {
        #expect(!DisassembledFunction.isLocalFunctionName(name), "\(name)")
    }
}

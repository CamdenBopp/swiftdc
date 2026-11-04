import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `objcvreturns.m`, built at both levels: -O2 and -O0 lower these exits
/// differently, so a fix proven at one is not proven at the other.
private let objcReturnBankFixtures = [
    "Fixtures/Sample/libObjCVReturns.dylib",
    "Fixtures/Sample/libObjCVReturnsO0.dylib",
]

/// A method whose result is not in x0 leaves x0 holding whatever the last
/// call left there. Read as the result, that call counted as consumed and
/// printed nowhere: `-[VRets a4]` is `bl sinkL; fmov d0, #2.5; ret` and read
/// `return 2.5` alone. So did a tail branch, whose x0 is the callee's
/// argument at most. `-keep` is the x0 control.
@Test func anObjCMethodKeepsItsLastCallWhenTheResultIsNotInX0IfPresent() async throws {
    let lastCalls = [
        ("-[VRets a4]", "sinkL(1)"), ("-[VRets a1]", "sinkL(2)"), ("-[VRets v2:]", "sinkD("),
        ("-[VRets a5]", "sinkL(3)"), ("-[VRets rect]", "sinkL(4)"), ("-[VRets size]", "sinkL(5)"),
        ("-[VRets big]", "sinkL(6)"), ("-[VRets tailD]", "sinkL(7)"), ("-[VRets tailL]", "sinkL(8)"),
        ("-[VRets keep]", "sinkL(9)"),
    ]
    for path in objcReturnBankFixtures {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        func text(_ name: String) throws -> String {
            try #require(functions.first { $0.displayName == name }).renderStructured()
        }
        for (name, call) in lastCalls {
            let body = try text(name)
            #expect(body.contains(call), "\(path) \(name):\n\(body)")
        }
        // The result itself still reads where its encoding puts it.
        #expect(try text("-[VRets a4]").contains("return 2.5\n"), "\(path)")
        #expect(try text("-[VRets keep]").contains("return 3\n"), "\(path)")
        #expect(try text("-[VRets rect]").contains("return ?"), "\(path)")
    }
}

/// How many times `text` appears in `body`.
private func occurrences(of text: String, in body: String) -> Int {
    body.components(separatedBy: text).count - 1
}

/// `-[VRets d]` is one `bl`, then `fadd d0, d0, d0`. The use counter read x0
/// while the return read v0, so it saw no use and the return spelled the send
/// out at both: `return ([super d] + [super d])`, two sends for one.
@Test func aSendUsedTwiceInAFloatReturnIsSentOnceIfPresent() async throws {
    for path in objcReturnBankFixtures {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        func text(_ name: String) throws -> String {
            try #require(functions.first { $0.displayName == name }).renderStructured()
        }
        for (name, send) in [("-[VRets d]", "[super d]"), ("-[VRets f]", "[super f]"), ("-[VRets sum:]", "[self d]")] {
            let body = try text(name)
            #expect(occurrences(of: send, in: body) == 1, "\(path) \(name):\n\(body)")
        }
    }
    let path = objcReturnBankFixtures[0]
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let body = try #require(functions.first { $0.displayName == "-[VRets d]" }).renderStructured()
    #expect(body.contains("let r0 = [super d]") && body.contains("return (r0 + r0)"), Comment(rawValue: body))
}

/// The argument path of the same rule: `-[VRets argTwice]` is one `bl`, then
/// `fadd d0, d0, d0` into sinkD. It binds the send and adds the name.
@Test func aSendUsedTwiceAsAnArgumentIsSentOnceIfPresent() async throws {
    for path in objcReturnBankFixtures {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let body = try #require(functions.first { $0.displayName == "-[VRets argTwice]" }).renderStructured()
        #expect(occurrences(of: "[super d]", in: body) == 1, "\(path):\n\(body)")
        #expect(body.contains("sinkD((r0 + r0))"), "\(path):\n\(body)")
    }
}

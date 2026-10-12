import Testing
import Foundation
@testable import SwiftDecompilerCore

/// AAPCS64 does not preserve NZCV across a call, so a condition read after a
/// `bl` cannot come from a compare before it. The tracer kept the tracked
/// flags through the call, so `cmp; bl f; cset` produced the pre-call
/// comparison's result. Compiled code never reads flags across a call;
/// hand-written or obfuscated code can. (sleuthre's changelog records the
/// same fix in its own tracker.)
@Test func aCallInvalidatesTheTrackedFlags() throws {
    let engine = try #require(CapstoneEngine())
    func decode(_ bytes: [UInt8]) -> [Instruction] {
        engine.disassemble(Data(bytes), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, annotation: nil,
                        controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
        }
    }
    let move: [UInt8] = [0xe9, 0x00, 0x80, 0xd2]     // mov  x9, #7
    let compare: [UInt8] = [0x3f, 0x15, 0x00, 0xf1]  // cmp  x9, #5
    let call: [UInt8] = [0x02, 0x00, 0x00, 0x94]     // bl   +8
    let set: [UInt8] = [0xe0, 0x17, 0x9f, 0x1a]      // cset w0, eq

    // Without a call the compare is read: 7 == 5 folds to 0.
    let direct = decode(move + compare + set)
    #expect(direct.map { $0.text.split(separator: "\t").first.map(String.init) } == ["mov", "cmp", "cset"])
    #expect(ValueTracer().finalState(of: direct)["x0"] == .immediate(0))

    // Across a call the flags are the callee's: nothing is known.
    let across = decode(move + compare + call + set)
    #expect(across.map { $0.text.split(separator: "\t").first.map(String.init) } == ["mov", "cmp", "bl", "cset"])
    let x0 = ValueTracer().finalState(of: across)["x0"]
    #expect(x0 == nil || x0 == .unknown, "cset after a call read the pre-call compare: \(String(describing: x0))")
}

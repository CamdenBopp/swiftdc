import Foundation
import Testing
@testable import SwiftDecompilerCore

struct FrameFactLostPointerIntegrationTests {
    @Test func onlyAFramePointerLostAtAMustJoinEscapes() throws {
        // An unseeded CBZ chooses which private local's address is stored in
        // a third slot. x10 is overwritten before the join, so only the slot
        // loses a pointer. No outgoing stack argument starts at sp, and the
        // later unknown call receives only zero. The conservative lost-slot
        // escape policy must decline the different-pointer case, while the
        // agreed-pointer control keeps7. These synthetic bodies are not run
        // natively; the CLT assembler/LLVM oracle verifies their words.
        let words: [UInt32] = [
            0xd10103ff, 0xd28000e9, 0xf90007e9, 0xf9000be9,
            0xb40000a0, 0x910023ea, 0xf9000fea, 0xd280000a,
            0x14000004, 0x910043ea, 0xf9000fea, 0xd280000a,
            0xd2800000, 0x940007f3, 0xf94007e0, 0x910103ff, 0xd65f03c0,
        ]
        let engine = try #require(CapstoneEngine())
        func trace(_ words: [UInt32]) throws -> FunctionAnalysis {
            let bytes = words.flatMap { word in
                (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) }
            }
            let decoded = engine.disassemble(Data(bytes), address: 0x1000)
            try #require(decoded.count == words.count)
            let calls = decoded.filter { $0.controlFlow == .call }
            try #require(calls.count == 1 && calls[0].branchTarget == 0x3000)
            let body = decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                            branchTarget: $0.branchTarget, detail: $0.detail,
                            callee: .kept($0.controlFlow == .call ? "shared_frame_write_helper" : nil))
            }
            let function = DisassembledFunction(symbol: "_frame_slot_loss", demangledName: nil,
                startAddress: 0x1000, instructions: body, source: .address)
            let analysis = ValueTracer().analyze(function)
            let call = try #require(analysis.callSites[0x1034])
            #expect(call.arguments == [.immediate(0)])
            #expect(call.stackArguments.isEmpty)
            return analysis
        }
        let lost = try trace(words)
        #expect((lost.exitValues[0x1040] ?? .unknown) == .unknown)
        var agreed = words
        agreed[9] = 0x910023ea // both arms keep &local8 in the holder slot
        #expect(try trace(agreed).exitValues[0x1040] == .immediate(7))
    }
}

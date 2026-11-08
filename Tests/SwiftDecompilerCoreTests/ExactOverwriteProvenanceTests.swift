import Foundation
import Testing
@testable import SwiftDecompilerCore

struct ExactOverwriteProvenanceTests {
    @Test func replacingPointerBytesDoesNotBecomeUnknownPointerLoss() throws {
        // A at sp+8 holds B's pointer, then an exact zero store overwrites A.
        // Unknown invalidation leaves the pointer bytes in memory and must
        // escape B; this exact overwrite removes those bytes and must not.
        let words: [UInt32] = [
            0xd10103ff, 0x910043ec, 0xf90007ec, 0xd28000e9, 0xf9000be9,
            0xf90007ff, 0xaa1f03e0, 0x940007f9,
            0x910043eb, 0xf9400160, 0x910103ff, 0xd65f03c0,
        ]
        let bytes = words.flatMap { word in
            (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) }
        }
        let engine = try #require(CapstoneEngine())
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        let body = decoded.map { instruction in
            Instruction(address: instruction.address, text: instruction.text, controlFlow: instruction.controlFlow,
                branchTarget: instruction.branchTarget, detail: instruction.detail,
                callee: .kept(instruction.controlFlow == .call ? "frame_mutating_helper" : nil))
        }
        let function = DisassembledFunction(symbol: "_exact_pointer_replacement", demangledName: nil,
            startAddress: 0x1000, instructions: body, source: .address)
        let analysis = ValueTracer().analyze(function, entry: nil)
        let call = try #require(analysis.callSites[0x101c])
        #expect(call.arguments == [.immediate(0)])
        #expect(call.stackArguments.isEmpty)
        #expect(analysis.exitValues[0x102c] == .immediate(7))
    }
}

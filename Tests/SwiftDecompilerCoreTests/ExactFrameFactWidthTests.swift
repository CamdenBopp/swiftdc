import Foundation
import Testing
@testable import SwiftDecompilerCore

struct ExactFrameFactWidthTests {
    @Test func exactTracerFactsKeepTheirOwnByteWidthsAtTouchingWrites() throws {
        // Each byte write starts exactly after the old1/2/4-byte fact. An
        // assumed8-byte fact would lose7. There are no calls or escapes.
        let cases: [(store: UInt32, nextByte: UInt32, load: UInt32)] = [
            (0x390043e9, 0x390047e2, 0x394043e0), // strb16; strb17; ldrb16
            (0x790023e9, 0x39004be2, 0x794023e0), // strh16; strb18; ldrh16
            (0xb90013e9, 0x390053e2, 0xb94013e0), // str w16; strb20; ldr w16
        ]
        for item in cases {
            let words: [UInt32] = [0xd10083ff, 0xd28000e9, item.store, item.nextByte,
                                   item.load, 0x910083ff, 0xd65f03c0]
            let bytes = words.flatMap { word in
                (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) }
            }
            let engine = try #require(CapstoneEngine())
            let body = engine.disassemble(Data(bytes), address: 0x1000)
            try #require(body.count == words.count)
            try #require(!body.contains { $0.controlFlow == .call })
            let instructions = body.map { item in
                Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
                            branchTarget: item.branchTarget, detail: item.detail)
            }
            let function = DisassembledFunction(symbol: "_exact_fact_width", demangledName: nil,
                startAddress: 0x1000, instructions: instructions, source: .address)
            let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x2": 0]))
            #expect(analysis.exitValues[0x1018] == .immediate(7))
        }
    }
}

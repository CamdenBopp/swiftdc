import Foundation
import Testing
@testable import SwiftDecompilerCore

struct FrameRegisterCoordinateControlTests {
    @Test func pairLaneAndFrameDisplacementUseTheSameCoordinates() throws {
        // The second STP lane stays at first+8. Reversing all frame additions
        // cannot cancel out between this store and the later displaced load.
        let words: [UInt32] = [
            0xd10083ff, 0xd28000eb, 0xd280016c, 0xa900b3eb, 0x910023e9,
            0xaa0903ea, 0xf9400540, 0x910083ff, 0xd65f03c0,
        ]
        let engine = try #require(CapstoneEngine())
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) } }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        let function = DisassembledFunction(symbol: "_register_pair_coordinate_control", demangledName: nil,
            startAddress: 0x1000, instructions: decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
            }, source: .address)
        #expect(ValueTracer().analyze(function).exitValues[0x1020] == .immediate(11))
    }
}

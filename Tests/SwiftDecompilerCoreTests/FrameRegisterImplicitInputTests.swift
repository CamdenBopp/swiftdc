import Foundation
import Testing
@testable import SwiftDecompilerCore

struct FrameRegisterImplicitInputTests {
    @Test func memoryBaseMayReadsKeepTheLegacyDurableEscape() throws {
        // STTR's base is a readRegisterKeys input but is not a stand-alone
        // register operand. Legacy unsupported-store handling makes its frame
        // reach durable before this body creates a new save. This pins that
        // conservative policy; these decoded bodies are not native executions.
        let words: [UInt32] = [
            0xd10083ff, 0xf9000ffe, 0x910043e9, 0xf800093f, 0xf90007f3,
            0xaa1f03f3, 0xaa1f03e9, 0xaa1f03e0, 0x940007f8, 0xf94007f3,
            0xf9400ffe, 0x910083ff, 0xd65f03c0,
        ]
        let engine = try #require(CapstoneEngine())
        func exits(_ body: [UInt32], checkInputs: Bool) throws -> [UInt64: [String: Preservation.Value]] {
            let bytes = body.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) } }
            let decoded = engine.disassemble(Data(bytes), address: 0x1000)
            try #require(decoded.count == body.count)
            if checkInputs {
                let detail = try #require(decoded[3].detail)
                try #require(detail.readRegisterKeys.contains("x9"))
                try #require(!detail.operands.contains { $0.operand.register?.key == "x9" })
            }
            let instructions = decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
            }
            let function = DisassembledFunction(symbol: "_legacy_memory_base_input", demangledName: nil,
                startAddress: 0x1000, instructions: instructions, source: .address)
            return try #require(Preservation.exitValues(blocks: function.basicBlocks(), entry: 0x1000,
                addresses: Set(instructions.map(\.address)), callInputs: { _ in [] }, clobbersMayAliasStack: false))
        }
        let escaped = try exits(words, checkInputs: true)
        #expect(escaped[0x1030]?["x19"] == nil)
        #expect(escaped[0x1030]?["x23"] == .entry("x23"))
        var control = words
        control[3] = 0xd503201f // NOP instead of the unsupported store
        #expect(try exits(control, checkInputs: false)[0x1030]?["x19"] == .entry("x19"))
    }
}

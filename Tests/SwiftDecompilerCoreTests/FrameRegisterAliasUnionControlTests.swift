import Foundation
import Testing
@testable import SwiftDecompilerCore

/// Preserve the legacy unknown-call policy, not a native wrong-value claim.
/// The authored helper writes x19's unchanged value to the selected save;
/// native execution would be ABI-safe, but is not assumed by this test.
struct FrameRegisterAliasUnionControlTests {
    @Test func aRightOnlySavedSlotAliasSurvivesPreservationJoin() throws {
        let words: [UInt32] = [
            0xd10083ff, 0xf9000ffe, 0xf90007f3, 0xaa1f03e1, 0xb4000040,
            0x910023e1, 0x940007fa, 0xf94007f3, 0xf9400ffe, 0x910083ff, 0xd65f03c0,
        ]
        let helperWords: [UInt32] = [0xb4000041, 0xf9000033, 0xd65f03c0]
        let engine = try #require(CapstoneEngine())
        func decode(_ body: [UInt32], at address: UInt64) throws -> [Instruction] {
            let bytes = body.flatMap { word in
                (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) }
            }
            let decoded = engine.disassemble(Data(bytes), address: address)
            try #require(decoded.count == body.count)
            return decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
            }
        }
        let helper = try decode(helperWords, at: 0x3000)
        try #require(helper[0].controlFlow == .conditionalBranch && helper[0].branchTarget == 0x3008)
        try #require(helper[2].controlFlow == .return)

        func exits(_ body: [UInt32], reversed: Bool) throws -> [UInt64: [String: Preservation.Value]] {
            let instructions = try decode(body, at: 0x1000)
            try #require(instructions[4].branchTarget == 0x1018)
            try #require(instructions[6].controlFlow == .call && instructions[6].branchTarget == 0x3000)
            let function = DisassembledFunction(symbol: "_frame_register_alias_union_control", demangledName: nil,
                startAddress: 0x1000, instructions: instructions, source: .address)
            let blocks = function.basicBlocks().map { block in
                BasicBlock(startAddress: block.startAddress, instructions: block.instructions,
                    successors: reversed ? Array(block.successors.reversed()) : block.successors,
                    switchCases: block.switchCases)
            }
            // Only the caller belongs to this analysis. The helper is an
            // unknown ABI-conforming call with x1 as its selected frame input.
            return try #require(Preservation.exitValues(blocks: blocks, entry: 0x1000,
                addresses: Set(instructions.map(\.address)), callInputs: { _ in ["x1"] },
                clobbersMayAliasStack: false))
        }
        for reversed in [false, true] {
            let joined = try exits(words, reversed: reversed)
            #expect(joined[0x1028]?["x19"] == nil)
            #expect(joined[0x1028]?["x23"] == .entry("x23"))
            #expect(joined[0x1028]?["v11"] == .entry("v11"))
            var neitherAliases = words
            neitherAliases[5] = 0xaa1f03e1 // MOV x1,xzr instead of ADD x1,sp,#8
            let control = try exits(neitherAliases, reversed: reversed)
            #expect(control[0x1028]?["x19"] == .entry("x19"))
            #expect(control[0x1028]?["x23"] == .entry("x23"))
            #expect(control[0x1028]?["v11"] == .entry("v11"))
        }
    }
}

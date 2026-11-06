import Foundation
import Testing
@testable import SwiftDecompilerCore

/// Consumer controls for the existing MAY-self slot semantics. The words are
/// kept beside an independently assembled/LLVM-decoded scratch oracle.
struct MayFrameSlotControlTests {
    private static func body(_ words: [UInt32]) throws -> DisassembledFunction {
        let engine = try #require(CapstoneEngine())
        let bytes = words.flatMap { word in
            (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) }
        }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        let instructions = decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        return DisassembledFunction(symbol: "_may_frame_slot_control", demangledName: nil,
            startAddress: 0x1000, instructions: instructions, source: .address)
    }

    private static func flow(
        _ words: [UInt32], reversed: Bool = false, restores: [String: Int64] = [:]
    ) throws -> Preservation.SelfRegisterFlow {
        let function = try body(words)
        let blocks = function.basicBlocks().map { block in
            var result = BasicBlock(startAddress: block.startAddress, instructions: block.instructions,
                successors: reversed ? Array(block.successors.reversed()) : block.successors)
            result.switchCases = block.switchCases
            return result
        }
        return try #require(Preservation.selfRegisterFlow(
            blocks: blocks, entry: function.startAddress,
            addresses: Set(function.instructions.map(\.address)),
            callEffect: { _ in CalleeEffect(restores: restores) },
            callInputs: { _ in [] }, forwards: { _ in false }))
    }

    @Test func aSlotPresentOnEitherPredecessorSurvivesBothTraversalOrders() throws {
        // sub sp,sp,#32; cbz x0,clear; str x20,[sp,#8]; b join
        // clear: str xzr,[sp,#8]; join: mov x20,xzr; ldr x0,[sp,#8]
        // add sp,sp,#32; ret
        let words: [UInt32] = [0xd10083ff, 0xb4000060, 0xf90007f4, 0x14000002,
            0xf90007ff, 0xaa1f03f4, 0xf94007e0, 0x910083ff, 0xd65f03c0]
        for reversed in [false, true] {
            #expect(try Self.flow(words, reversed: reversed).reads)
            var clear = words
            clear[2] = 0xf90007ff
            #expect(try !Self.flow(clear, reversed: reversed).reads)
        }
    }

    @Test func anExactWordOverwriteEndsPresenceButAPartialOverwriteKeepsIt() throws {
        // Spill x20, end its register membership, overwrite the slot, reload.
        for (overwrite, expected): (UInt32, Bool) in [(0xf90007ff, false), (0x390023ff, true)] {
            let words: [UInt32] = [0xd10083ff, 0xf90007f4, 0xaa1f03f4, overwrite,
                0xf94007e0, 0x910083ff, 0xd65f03c0]
            #expect(try Self.flow(words).reads == expected)
        }
    }

    @Test func aPairOverwriteEndsBothSlotsAndAPairSpillInstallsBoth() throws {
        // stp x20,x20,[sp,#8]; mov x20,xzr; [stp xzr,xzr,[sp,#8]]
        // ldp x0,x1,[sp,#8]; add sp,sp,#32; ret
        let clear: [UInt32] = [0xd10083ff, 0xa900d3f4, 0xaa1f03f4, 0xa900ffff,
            0xa94087e0, 0x910083ff, 0xd65f03c0]
        #expect(try !Self.flow(clear).reads)
        var spill = clear
        spill.remove(at: 3)
        #expect(try Self.flow(spill).reads)
    }

    @Test func partialLoadsReadTheSlotButItsUpperBoundaryDoesNot() throws {
        for (load, expected): (UInt32, Bool) in [
            (0xb9400fe0, true), // ldr w0,[sp,#12]
            (0x39403fe0, true), // ldrb w0,[sp,#15]
            (0xb94013e0, false), // ldr w0,[sp,#16]
            (0xf94007e0, true), // ldr x0,[sp,#8]
        ] {
            let words: [UInt32] = [0xd10083ff, 0xf90007f4, 0xaa1f03f4, load,
                0x910083ff, 0xd65f03c0]
            #expect(try Self.flow(words).reads == expected)
        }
    }

    @Test func aCalleeReloadUsesMayPresenceAtItsActualByteExtent() throws {
        let words: [UInt32] = [0xd10083ff, 0xf90007f4, 0xaa1f03f4,
            0x94000400, 0x910083ff, 0xd65f03c0]
        for (offset, expected): (Int64, Bool) in [(8, true), (12, true), (16, false)] {
            #expect(try Self.flow(words, restores: ["x0": offset]).reads == expected)
        }
    }
}

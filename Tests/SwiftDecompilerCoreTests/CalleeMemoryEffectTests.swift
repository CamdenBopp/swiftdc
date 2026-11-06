import Foundation
import Testing
@testable import SwiftDecompilerCore

struct CalleeMemoryEffectTests {
    private static func body(_ words: [UInt32]) throws -> DisassembledFunction {
        let engine = try #require(CapstoneEngine())
        let bytes = words.flatMap { word in
            (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) }
        }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        return DisassembledFunction(symbol: "_callee_memory_control", demangledName: nil,
            startAddress: 0x1000, instructions: decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
            }, source: .address)
    }

    @Test func aCompleteLiteralStoreKeepsItsWidthValueAndOrigin() throws {
        // mov x9,#11; str x9,[x0]; ret
        let summary = CalleeMemoryEffect.discover(in: try Self.body([0xd2800169, 0xf9000009, 0xd65f03c0]))
        let x0 = PhysReg(kind: .gpr, number: 0, widthBits: 64)
        let x9 = PhysReg(kind: .gpr, number: 9, widthBits: 64)
        #expect(summary == .literalStores([.init(base: x0, offset: 0, bytes: 8, value: 11, source: x9)], inputs: [x0]))
        let plan = try #require(summary.framePlan { $0 == x0 ? -32 : nil })
        #expect(plan.stores == [.init(start: -32, bytes: 8, value: 11, source: x9)])
        let effect = plan.writeEffect(arithmetic: .wrapping)
        #expect(effect.mayInvalidate(.init(start: -32, bytes: 8)))
        #expect(!effect.mayInvalidate(.init(start: -24, bytes: 8)))
    }

    @Test func pairAndInteriorStoresKeepTheirActualByteExtents() throws {
        // mov x9,#11; mov x10,#13; stp x9,x10,[x0,#8]
        // add x11,x0,#16; sturb w9,[x11,#-1]; ret
        let summary = CalleeMemoryEffect.discover(in: try Self.body([
            0xd2800169, 0xd28001aa, 0xa900a809, 0x9100400b, 0x381ff169, 0xd65f03c0,
        ]))
        let plan = try #require(summary.framePlan { $0.key == "x0" ? -48 : nil })
        #expect(plan.stores.map(\.start) == [-40, -32, -33])
        #expect(plan.stores.map(\.bytes) == [8, 8, 1])
        #expect(plan.stores.map(\.value) == [11, 13, 11])
        // The first store starts at root+8: reject overflowing start arithmetic.
        #expect(summary.framePlan { _ in .max } == nil)
    }

    @Test func anUnsupportedOperationDeclinesTheWholeBody() throws {
        for words: [UInt32] in [
            [0xd2800169, 0xf940000a, 0xf9000009, 0xd65f03c0], // load
            [0xd2800169, 0x94000400, 0xf9000009, 0xd65f03c0], // call
            [0xd2800169, 0x14000002, 0xf9000009, 0xd65f03c0], // branch
            [0xf9000001, 0xd65f03c0], // incoming data might be a pointer
            [0xd10083ff, 0xd2800169, 0xf9000009, 0xd65f03c0], // unbalanced sp
            [0xd65f03c0, 0xd2800169, 0xd65f03c0], // early return
            [0xd280017e, 0xd65f03c0], // changed LR makes RET another transfer
        ] {
            #expect(CalleeMemoryEffect.discover(in: try Self.body(words)) == .unknown)
        }
        let function = try Self.body([0xd2800169, 0xf9000009, 0xd65f03c0])
        let missing = function.instructions.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow, branchTarget: $0.branchTarget)
        }
        let incomplete = DisassembledFunction(symbol: "_missing_detail", demangledName: nil,
            startAddress: 0x1000, instructions: missing, source: .address)
        #expect(CalleeMemoryEffect.discover(in: incomplete) == .unknown)
        let gap = DisassembledFunction(symbol: "_decode_gap", demangledName: nil,
            startAddress: 0x1000, instructions: [function.instructions[0], function.instructions[2]], source: .address)
        #expect(CalleeMemoryEffect.discover(in: gap) == .unknown)
    }

    @Test func frameResolutionIsTransactionalAndChecksBothEnds() throws {
        // mov x9,#11; str x9,[x0]; str x9,[x1]; ret
        let summary = CalleeMemoryEffect.discover(in: try Self.body([
            0xd2800169, 0xf9000009, 0xf9000029, 0xd65f03c0,
        ]))
        #expect(summary.framePlan { $0.key == "x0" ? -32 : nil } == nil)
        #expect(summary.framePlan { $0.key == "x0" ? .max - 3 : -16 } == nil)
        let complete = try #require(summary.framePlan { $0.key == "x0" ? -32 : -16 })
        #expect(complete.stores.map(\.start) == [-32, -16])
        let noMemory = CalleeMemoryEffect.discover(in: try Self.body([0xd65f03c0]))
        #expect(noMemory != .unknown)
        #expect(try #require(noMemory.framePlan { _ in nil }).stores.isEmpty)
        #expect(CalleeMemoryEffect.unknown.framePlan { _ in -32 } == nil)
        // BL's link value differs from pre-call x30. A caller's frame alias
        // there must never become the address of this callee's store.
        let link = CalleeMemoryEffect.discover(in: try Self.body([0xd2800169, 0xf90003c9, 0xd65f03c0]))
        #expect(link.framePlan { _ in -32 } == nil)
    }
}

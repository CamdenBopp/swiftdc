import Foundation
import Testing
@testable import SwiftDecompilerCore

private func asyncPointerAnalysis(_ words: [UInt32], callee: Bool = false) throws -> FunctionAnalysis {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    #expect(decoded.count == words.count)
    let function = DisassembledFunction(symbol: "pointer", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map { Instruction(address: $0.address, text: $0.text,
            controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail) }, source: .address)
    return ValueTracer().analyze(function, entry: .asyncFunclet(base: nil,
        seededRegisters: ["x22": callee ? .asyncCalleeContext : .asyncContext]))
}

@Test func asyncTruncatedContextLoadDoesNotInventReturn() throws {
    // ldr w9, [x22, #8]; br x9 — the upper pointer bits were not loaded.
    let narrow = try asyncPointerAnalysis([0xb9400ac9, 0xd61f0120])
    #expect(narrow.indirectControlFlowTargets[0x1004] != .asyncResumeParent)
    let wide = try asyncPointerAnalysis([0xf94006c9, 0xd61f0120])
    #expect(wide.indirectControlFlowTargets[0x1004] == .asyncResumeParent)
    // ldr w9, [x22]; ldr x9, [x9,#8]; br x9 — truncated parent context.
    let parent = try asyncPointerAnalysis([0xb94002c9, 0xf9400529, 0xd61f0120], callee: true)
    #expect(parent.indirectControlFlowTargets[0x1008] != .asyncResumeParent)
    let fullParent = try asyncPointerAnalysis([0xf94002c9, 0xf9400529, 0xd61f0120], callee: true)
    #expect(fullParent.indirectControlFlowTargets[0x1008] == .asyncResumeParent)
}

@Test func asyncFloatingLoadsDoNotCarryContextPointerIdentity() throws {
    // ldr d0,[x22,#8]; ret and ldp d0,d1,[x22,#8]; ret.
    for load: UInt32 in [0xfd4006c0, 0x6d4086c0] {
        let own = try asyncPointerAnalysis([load, 0xd65f03c0])
        #expect(own.exitFloatValues[0x1004] != .asyncResumeParent)
    }
    // ldr d0,[x22]; ret and ldp d0,d1,[x22]; ret at an await-return entry.
    for load: UInt32 in [0xfd4002c0, 0x6d4006c0] {
        let parent = try asyncPointerAnalysis([load, 0xd65f03c0], callee: true)
        #expect(parent.exitFloatValues[0x1004] != .asyncContext)
    }
}

@Test func asyncTruncatedContextCopyDoesNotInventReturn() throws {
    // mov w9,w22; ldr x9,[x9,#8]; br x9.
    let narrow = try asyncPointerAnalysis([0x2a1603e9, 0xf9400529, 0xd61f0120])
    #expect(narrow.indirectControlFlowTargets[0x1008] != .asyncResumeParent)
    // mov x9,x22 preserves the pointer and remains a valid control.
    let wide = try asyncPointerAnalysis([0xaa1603e9, 0xf9400529, 0xd61f0120])
    #expect(wide.indirectControlFlowTargets[0x1008] == .asyncResumeParent)
}

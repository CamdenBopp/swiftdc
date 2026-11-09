import Foundation
import Testing
@testable import SwiftDecompilerCore

private let tailBranches: [UInt32] = [0xb4008000, 0xb5008000, 0x36008000, 0x37008000, 0x54008000]

private func tailBody(_ words: [UInt32], at start: UInt64 = 0x1000) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: start)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "_conditionalTail", demangledName: nil,
        startAddress: start, instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
}

private func tailExits(_ body: DisassembledFunction, effect: CalleeEffect) throws -> [UInt64: [String: Preservation.Value]] {
    try #require(Preservation.exitValues(blocks: body.basicBlocks(), entry: body.startAddress,
        addresses: Set(body.instructions.map(\.address)), exitEffect: { insn in insn.controlFlow == .conditionalBranch ? effect : CalleeEffect() }, clobbersMayAliasStack: false))
}

@Test func conditionalTailTargetsEnterTheEffectAndOutgoingGraphs() throws {
    for branch in tailBranches {
        let body = try tailBody([branch, 0xd65f03c0])
        try #require(body.instructions[0].branchTarget == 0x2000)
        for key in ["x19", "v8"] {
            let summary = try #require(CalleeRegisterSummary.of(body,
                calleeEffects: { _ in CalleeEffect(clobbers: [key]) }))
            #expect(summary.callees == [0x2000])
            #expect(summary.outgoingCalls.map(\.target) == [0x2000])
            #expect(summary.clobberedCalleeSaved == [key])
            #expect(summary.definitelyClobbered == [key])
            #expect(summary.mayWriteFloatResult)
            #expect(summary.effect.clobbers.isDisjoint(with: ["x23", "v11"]))
        }
    }
}

@Test func conditionalTailEffectsLeaveTheFallthroughStateIntact() throws {
    for branch in tailBranches {
        let body = try tailBody([branch, 0xd65f03c0])
        for key in ["x19", "v8", "x21"] {
            let exits = try tailExits(body, effect: CalleeEffect(clobbers: [key]))
            #expect(Set(exits.keys) == [0x1000, 0x1004])
            #expect(exits[0x1000]?[key] == nil)
            #expect(exits[0x1004]?[key] == .entry(key))
            #expect(exits[0x1000]?["x23"] == .entry("x23"))
            #expect(exits[0x1004]?["v11"] == .entry("v11"))
        }
    }
}

@Test func conditionalTailX21EntryProofKeepsBothOutcomesSeparate() throws {
    let body = try tailBody([0xb4008000, 0xd65f03c0])
    let exits = try #require(Preservation.entryValuesAtExits(blocks: body.basicBlocks(), entry: 0x1000,
        addresses: Set(body.instructions.map(\.address)), exitEffect: { insn in insn.controlFlow == .conditionalBranch ? CalleeEffect(clobbers: ["x21"]) : CalleeEffect() }))
    #expect(exits[0x1000]?.contains("x21") == false)
    #expect(exits[0x1004]?.contains("x21") == true)
    // A fallthrough overwrite is not the incoming no-error value either.
    let overwrite = try tailBody([0xb4008000, 0xd2800035, 0xd65f03c0])
    let changed = try #require(Preservation.entryValuesAtExits(blocks: overwrite.basicBlocks(), entry: 0x1000,
        addresses: Set(overwrite.instructions.map(\.address)), exitEffect: { insn in insn.controlFlow == .conditionalBranch ? CalleeEffect(clobbers: ["x21"]) : CalleeEffect() }))
    #expect(changed[0x1000]?.contains("x21") == false)
    #expect(changed[0x1008]?.contains("x21") == false)
}

@Test func aConditionalReloadMustAgreeWithItsFallthroughExit() throws {
    for (key, load): (String, UInt32) in [("x19", 0xf94003f3), ("v8", 0xfd4003e8)] {
        let effect = CalleeEffect(restores: [key: 0])
        let one = try tailBody([0xb4008000, 0xd65f03c0])
        let partial = try #require(CalleeRegisterSummary.of(one, calleeEffects: { _ in effect }))
        #expect(partial.restoredFrom[key] == nil)
        let exits = try tailExits(one, effect: effect)
        #expect(exits[0x1000]?[key] == .incoming(0))
        #expect(exits[0x1004]?[key] == .entry(key))
        let both = try tailBody([0xb4008000, load, 0xd65f03c0])
        let restored = try #require(CalleeRegisterSummary.of(both, calleeEffects: { _ in effect }))
        #expect(restored.restoredFrom[key] == 0)
        #expect(restored.effect.restores[key] == 0)
        #expect(!restored.effect.clobbers.contains(key))
        #expect(restored.clobberedCalleeSaved.isDisjoint(with: ["x23", "v11"]))
    }
}

@Test func conditionalTailsCloseReadsSelfFrameContextAndFieldEffects() throws {
    let middle = try tailBody([0xb4008000, 0xd65f03c0])
    // ldr x9,[x3/x29/x22/x20]; str x9,[x3]; ret.
    let leaf = try tailBody([0xf9400069, 0xf94003a9, 0xf94002c9, 0xf9400289, 0xf9000069, 0xd65f03c0], at: 0x2000)
    let initial = try #require(CalleeRegisterSummary.of(middle, isFunction: { $0 == 0x2000 }))
    let target = try #require(CalleeRegisterSummary.of(leaf))
    var summaries = [UInt64(0x1000): initial, UInt64(0x2000): target]
    CalleeRegisterSummary.closeOverReads(&summaries)
    CalleeRegisterSummary.closeOverFieldWrites(&summaries, name: { _ in nil })
    let closed = try #require(summaries[0x1000])
    #expect(closed.argumentReads == [0, 3])
    #expect(closed.readsFramePointer)
    #expect(closed.readsContextRegister)
    #expect(closed.readsSelfRegister)
    #expect(!closed.writesNoFields)
    #expect(closed.mayWriteFloatResult)
    let rebuilt = try #require(CalleeRegisterSummary.recomputingPreservation(middle,
        retainingReadsFrom: closed, calleeEffects: { _ in target.effect }, isFunction: { $0 == 0x2000 }))
    #expect(rebuilt.argumentReads == closed.argumentReads)
    #expect(rebuilt.readsFramePointer == closed.readsFramePointer)
    #expect(rebuilt.readsContextRegister == closed.readsContextRegister)
    #expect(rebuilt.readsSelfRegister == closed.readsSelfRegister)
}

@Test func conditionalTargetsRespectKnownAndUnknownInputPolicies() throws {
    let body = try tailBody([0xb4008000, 0xd65f03c0])
    let known = try #require(CalleeRegisterSummary.of(body, calleeArity: { _ in 3 }))
    #expect(known.argumentReads == [0, 1, 2])
    #expect(known.pendingReads.isEmpty)
    #expect(known.provenFloatArgumentReads.isEmpty)
    let unknown = try #require(CalleeRegisterSummary.of(body))
    #expect(unknown.argumentReads == RegisterSet(0...7))
    #expect(unknown.provenFloatArgumentReads.isEmpty)
}

@Test func aConditionalTailCanConsumeACopyOfIncomingSelf() throws {
    // mov x23,x20; mov x20,#0; cbz x0,0x2000; ret.
    let body = try tailBody([0xaa1403f7, 0xd2800014, 0xb4007fc0, 0xd65f03c0])
    let summary = try #require(CalleeRegisterSummary.of(body, isFunction: { $0 == 0x2000 }))
    #expect(summary.readsSelfRegister)
}

@Test func conditionalEffectsClosePreciselyAcrossTheCallGraph() throws {
    for (key, write): (String, UInt32) in [("x19", 0xd2800033), ("v8", 0x1e6e1008)] {
        let middle = try tailBody([0xb4008000, 0xd65f03c0])
        let leaf = try tailBody([write, 0xd65f03c0], at: 0x2000)
        var summaries = [UInt64(0x1000): try #require(CalleeRegisterSummary.of(middle, isFunction: { $0 == 0x2000 })),
                         UInt64(0x2000): try #require(CalleeRegisterSummary.of(leaf))]
        CalleeRegisterSummary.closeOverReads(&summaries)
        let reads = try #require(summaries[0x1000])
        CalleeRegisterSummary.closeOverCalls(&summaries) { start, effects, readFacts in
            CalleeRegisterSummary.recomputingPreservation(start == 0x1000 ? middle : leaf,
                retainingReadsFrom: readFacts, calleeEffects: effects, isFunction: { $0 == 0x2000 })
        }
        let result = try #require(summaries[0x1000])
        #expect(result.effect.clobbers.contains(key))
        #expect(result.clobberedCalleeSaved.isDisjoint(with: ["x23", "v11"]))
        #expect(result.effect.clobbers.isDisjoint(with: ["x23", "v11"]))
        #expect(result.argumentReads == reads.argumentReads)
        #expect(result.readsSelfRegister == reads.readsSelfRegister)
    }
}

@Test func internalConditionsAndResolvedSwitchesStayInTheCFG() throws {
    for branch: UInt32 in [0xb4000000, 0xb4000020, 0x54000000] {
        let body = try tailBody([branch, 0xd65f03c0])
        let summary = try #require(CalleeRegisterSummary.of(body))
        #expect(summary.callees.isEmpty)
        #expect(summary.outgoingCalls.isEmpty)
        #expect(summary.clobberedCalleeSaved.isEmpty)
    }
    let body = try tailBody([0xd61f0020, 0xd65f03c0]) // br x1, resolved as a switch
    let blocks = [BasicBlock(startAddress: 0x1000, instructions: [body.instructions[0]], successors: [0x1004], switchCases: [0x1004]),
                  BasicBlock(startAddress: 0x1004, instructions: [body.instructions[1]], successors: [])]
    var queries = 0
    let exits = try #require(Preservation.exitValues(blocks: blocks, entry: 0x1000,
        addresses: [0x1000, 0x1004], exitEffect: { insn in queries += 1; return insn.controlFlow == .branch ? CalleeEffect(clobbers: ["x19"]) : CalleeEffect() }))
    #expect(queries == 1) // RET's default hook is queried; the switch is not.
    #expect(Set(exits.keys) == [0x1004])
    #expect(exits[0x1004]?["x19"] == .entry("x19"))
}

/// `closeOverFieldWrites` reads a body's calls only when it stores only to
/// its stack, and each distinct call alone: a summary keeps them for such a
/// body only, each once.
@Test func outgoingCallsAreKeptOnlyWhereFieldWritesReadThem() throws {
    // bl 0x2000; bl 0x2000; ret: stack-only, one distinct call.
    let twice = try #require(CalleeRegisterSummary.of(try tailBody([0x94000400, 0x940003ff, 0xd65f03c0])))
    #expect(twice.storesOnlyToStack)
    #expect(twice.outgoingCalls.map(\.target) == [0x2000])
    // str x0, [x1]; bl 0x2000; ret: a store through x1, so no call is read.
    let storing = try #require(CalleeRegisterSummary.of(try tailBody([0xf9000020, 0x940003ff, 0xd65f03c0])))
    #expect(!storing.storesOnlyToStack)
    #expect(storing.outgoingCalls.isEmpty)
}

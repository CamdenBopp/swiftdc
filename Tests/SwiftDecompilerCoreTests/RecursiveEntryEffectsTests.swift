import Foundation
import Testing
@testable import SwiftDecompilerCore

// Instruction words for the authored recursive-only fixture. Independent
// assembly comparisons are recorded with the proof artifacts.
private struct RecursiveWords: Sendable {
    let root: String
    let temporary: String
    let words: [UInt32]
}

private let oneHop: [RecursiveWords] = [
    RecursiveWords(root: "x19", temporary: "x20", words: [
        0xb4000100, 0xa9bf7bfd, 0xaa1303f4, 0xd1000400, 0x97fffffc,
        0xaa1403f3, 0xa8c17bfd, 0xd65f03c0, 0xd2800034, 0xd65f03c0]),
    RecursiveWords(root: "v8", temporary: "v9", words: [
        0xb4000100, 0xa9bf7bfd, 0x1e604109, 0xd1000400, 0x97fffffc,
        0x1e604128, 0xa8c17bfd, 0xd65f03c0, 0x1e6e1009, 0xd65f03c0]),
]

private let twoHop: [RecursiveWords] = [
    RecursiveWords(root: "x19", temporary: "x22", words: [
        0xb4000140, 0xa9bf7bfd, 0xaa1403f6, 0xaa1303f4, 0xd1000400,
        0x97fffffb, 0xaa1403f3, 0xaa1603f4, 0xa8c17bfd, 0xd65f03c0,
        0xd2800036, 0xd65f03c0]),
    RecursiveWords(root: "v8", temporary: "v10", words: [
        0xb4000140, 0xa9bf7bfd, 0x1e60412a, 0x1e604109, 0xd1000400,
        0x97fffffb, 0x1e604128, 0x1e604149, 0xa8c17bfd, 0xd65f03c0,
        0x1e6e100a, 0xd65f03c0]),
]

private let stackProtected: [RecursiveWords] = [
    RecursiveWords(root: "x19", temporary: "x20", words: [
        0xb4000140, 0xa9be7bfd, 0xf9000bf3, 0xaa1303f4, 0xd1000400,
        0x97fffffb, 0xaa1403f3, 0xf9400bf3, 0xa8c27bfd, 0xd65f03c0,
        0xd2800034, 0xd65f03c0]),
    RecursiveWords(root: "v8", temporary: "v9", words: [
        0xb4000140, 0xa9be7bfd, 0xfd000be8, 0x1e604109, 0xd1000400,
        0x97fffffb, 0x1e604128, 0xfd400be8, 0xa8c27bfd, 0xd65f03c0,
        0x1e6e1009, 0xd65f03c0]),
]

private func recursiveBody(_ words: [UInt32]) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "_recursiveEntry", demangledName: nil,
        startAddress: 0x1000, instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
}

private func expectSameClosedReads(_ actual: CalleeRegisterSummary, _ expected: CalleeRegisterSummary) {
    #expect(actual.argumentReads == expected.argumentReads)
    #expect(actual.provenArgumentReads == expected.provenArgumentReads)
    #expect(actual.provenFloatArgumentReads == expected.provenFloatArgumentReads)
    #expect(actual.floatArgumentWidths == expected.floatArgumentWidths)
    #expect(actual.mayWriteFloatResult == expected.mayWriteFloatResult)
    #expect(actual.pendingReads == expected.pendingReads)
    #expect(actual.readsFramePointer == expected.readsFramePointer)
    #expect(actual.readsContextRegister == expected.readsContextRegister)
    #expect(actual.readsSelfRegister == expected.readsSelfRegister)
}

private func closeRecursive(_ body: DisassembledFunction, callbacks: inout Int) throws -> CalleeRegisterSummary {
    let initial = try #require(CalleeRegisterSummary.of(body, isFunction: { $0 == body.startAddress }))
    var summaries = [body.startAddress: initial]
    CalleeRegisterSummary.closeOverReads(&summaries)
    let closedReads = try #require(summaries[body.startAddress])
    CalleeRegisterSummary.closeOverCalls(&summaries) { start, effects, readFacts, reusePreservation in
        callbacks += 1
        #expect(start == body.startAddress)
        expectSameClosedReads(readFacts, closedReads)
        return CalleeRegisterSummary.recomputingPreservation(body,
            retainingReadsFrom: readFacts, reusingPreservation: reusePreservation, calleeEffects: effects,
            isFunction: { $0 == body.startAddress })
    }
    let result = try #require(summaries[body.startAddress])
    expectSameClosedReads(result, closedReads)
    return result
}

@Test func selfEntryCallsEnterTheEffectDependencyGraph() throws {
    for test in oneHop {
        let body = try recursiveBody(test.words)
        let summary = try #require(CalleeRegisterSummary.of(body))
        #expect(summary.callees == [body.startAddress])
        #expect(summary.definitelyClobbered.contains(test.temporary))
        #expect(!summary.clobberedCalleeSaved.contains(test.root))
    }
}

@Test func selfEntryCallsReplayTheirKnownEffects() throws {
    for test in oneHop {
        let body = try recursiveBody(test.words)
        let summary = try #require(CalleeRegisterSummary.of(body, calleeEffects: { target in
            target == body.startAddress ? CalleeEffect(clobbers: [test.temporary]) : CalleeEffect()
        }))
        #expect(summary.clobberedCalleeSaved.contains(test.root))
        #expect(summary.effect.clobbers.contains(test.root))
    }
}

@Test func recursiveEffectsCloseWithoutRebuildingReadFacts() throws {
    for test in oneHop {
        let body = try recursiveBody(test.words)
        var callbacks = 0
        let summary = try closeRecursive(body, callbacks: &callbacks)
        #expect(callbacks > 0)
        #expect(summary.effect.clobbers.contains(test.root))
        #expect(summary.clobberedCalleeSaved.isDisjoint(with: ["x23", "v11"]))
        #expect(summary.effect.clobbers.isDisjoint(with: ["x23", "v11"]))
    }
}

@Test func recursiveEffectsRescheduleTheirOwnDependentTemporary() throws {
    for test in twoHop {
        let body = try recursiveBody(test.words)
        let initial = try #require(CalleeRegisterSummary.of(body))
        #expect(initial.definitelyClobbered.contains(test.temporary))
        #expect(!initial.definitelyClobbered.contains(test.root))
        var callbacks = 0
        let summary = try closeRecursive(body, callbacks: &callbacks)
        #expect(callbacks >= 2)
        #expect(summary.effect.clobbers.contains(test.root))
        #expect(summary.clobberedCalleeSaved.isDisjoint(with: ["x23", "v11"]))
        #expect(summary.effect.clobbers.isDisjoint(with: ["x23", "v11"]))
    }
}

@Test func recursiveStackReloadsKeepTheEntryRoot() throws {
    for test in stackProtected {
        let body = try recursiveBody(test.words)
        var callbacks = 0
        let summary = try closeRecursive(body, callbacks: &callbacks)
        #expect(callbacks > 0)
        #expect(!summary.clobberedCalleeSaved.contains(test.root))
        #expect(!summary.effect.clobbers.contains(test.root))
        #expect(summary.restoredFrom[test.root] == nil)
    }
}

@Test func entryBranchesRemainCFGEdges() throws {
    for branch: UInt32 in [0x14000000, 0x54000000] { // B and B.EQ to 0x1000
        let body = try recursiveBody([branch, 0xd65f03c0])
        try #require(body.instructions[0].branchTarget == body.startAddress)
        var effectQueries = 0
        let summary = try #require(CalleeRegisterSummary.of(body, calleeEffects: { _ in
            effectQueries += 1
            return CalleeEffect(clobbers: ["x19", "v8"])
        }))
        #expect(summary.callees.isEmpty)
        #expect(summary.outgoingCalls.isEmpty)
        #expect(effectQueries == 0)
    }
}

@Test func unfinishedRecursiveEffectsInvalidateTheWholeNineteenRegisterBank() throws {
    let bank = Set((19...29).map { "x\($0)" } + (8...15).map { "v\($0)" })
    for test in oneHop {
        let body = try recursiveBody(test.words)
        let initial = try #require(CalleeRegisterSummary.of(body))
        var capped = [body.startAddress: initial]
        CalleeRegisterSummary.closeOverCalls(&capped, cap: 0) { _, _, _, _ in
            Issue.record("A zero-cap closure must decline before recomputation")
            return nil
        }
        #expect(capped[body.startAddress]?.clobberedCalleeSaved == bank)
        #expect(capped[body.startAddress]?.effect.clobbers == bank)
        var failed = [body.startAddress: initial]
        CalleeRegisterSummary.closeOverCalls(&failed) { _, _, _, _ in nil }
        #expect(failed[body.startAddress]?.clobberedCalleeSaved == bank)
        #expect(failed[body.startAddress]?.effect.clobbers == bank)
    }
}

import Foundation
import Testing
@testable import SwiftDecompilerCore

private func escapeBody(_ words: [UInt32], at address: UInt64, allocation: Bool = false) throws -> [Instruction] {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: address)
    #expect(decoded.count == words.count)
    return decoded.map { Instruction(address: $0.address, text: $0.text,
        annotation: allocation && $0.controlFlow == .call ? "swift_task_alloc" : nil,
        controlFlow: $0.controlFlow, branchTarget: allocation && $0.controlFlow == .call ? nil : $0.branchTarget,
        detail: $0.detail) }
}

private func provenSlots(resume words: [UInt32], missingResume: Bool = false) throws -> [Int: AbstractValue] {
    // Store7 before an own-context continuation handoff. Raw alias
    // bodies challenge the MAY detector; this is not a complete native ABI fixture.
    // Compiler-style own-context continuation handoff, an analysis seam.
    let entryBody = try escapeBody([
        0xd28000e8, 0xf9000ac8, 0x10007fc0, 0x14000bfd,
    ], at: 0x1000)
    let resumeBody = try escapeBody(words, at: 0x2000)
    let raw: [UInt64: DisassembledFunction] = [
        0x1000: .init(symbol: "entry", demangledName: "M.entry() async -> Swift.Int", startAddress: 0x1000,
                      instructions: entryBody, source: .address),
        0x2000: .init(symbol: "resume", demangledName: nil, startAddress: 0x2000,
                      instructions: resumeBody, source: .address),
    ]
    let index = AsyncFuncletIndex.build(hints: .init(entries: [0x1000], awaitReturns: [], continuations: [0x2000]),
        functionStarts: Set(raw.keys), instructions: { raw[$0]?.instructions ?? [] },
        nameOf: { $0 == 0x4000 ? "swift_task_switch" : raw[$0]?.displayName })
    try #require(index.chains[0x1000] == [0x1000, 0x2000])
    let functions = raw.mapValues { function in
        index.info(for: function.startAddress, parentName: { raw[$0]?.displayName })
            .map(function.attachingAsyncFunclet) ?? function
    }
    return Disassembler().asyncChainSlots(index: index, function: { missingResume && $0 == 0x2000 ? nil : functions[$0] },
        enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex())[0x2000] ?? [:]
}

@Test func aContextAliasClobberedOnAnotherBranchStillEscapes() throws {
    // ldr x19,[x22]; cbz x0,escape; mov x19,xzr; b done;
    // escape: add x0,x19,#16; bl mutate; ldr x0,[x19,#16]; done: ret.
    // The escape path never executes the overwrite. A callee that adds 11 to
    // *x0 changes the slot to 18, so the chain cannot prove its old value 7.
    let slots = try provenSlots(resume: [
        0xf94002d3, 0xb4000060, 0xaa1f03f3, 0x14000004,
        0x91004260, 0x94001000, 0xf9400a60, 0xd65f03c0,
    ])
    #expect(slots[16] == nil)
}

@Test func aContextAliasFromEitherPredecessorStillEscapesAtTheJoin() throws {
    // One predecessor reloads x19 from [x22]; the other overwrites it.
    // At the join it MAY be a context, enough to invalidate a constant proof.
    let slots = try provenSlots(resume: [
        0xb4000060, 0xf94002d3, 0x14000002, 0xaa1f03f3,
        0x91004260, 0x94001000, 0xd65f03c0,
    ])
    #expect(slots[16] == nil)
}

@Test func aContextSlotWithoutAnEscapeRemainsProven() throws {
    let slots = try provenSlots(resume: [0xf9400ac0, 0xf94006c1, 0xd61f0020])
    #expect(slots[16] == .immediate(7))
}

@Test func aContextAliasReachingAnEarlierBlockThroughABackEdgeStillEscapes() throws {
    // The alias is established after the escape in address order. A loop back
    // to the earlier block brings it to that address computation at runtime.
    let slots = try provenSlots(resume: [
        0xb40000a0, 0x91004260, 0x94001000, 0xf9400a60, 0xd65f03c0,
        0xf94002d3, 0xd2800020, 0x17fffff9,
    ])
    #expect(slots[16] == nil)
}

@Test func anIncompleteContextEscapeAnalysisProvesNoSlots() throws {
    let body = try escapeBody(Array(repeating: 0xd65f03c0, count: 20), at: 0x1000)
    let function = DisassembledFunction(symbol: "bounded", demangledName: nil,
        startAddress: 0x1000, instructions: body, source: .address)
    let recorder = ProbeRecorder()
    let offset = Probe.recording(recorder) {
        AsyncContextEscapes(iterationsPerBlock: 0).lowestOffset(in: function)
    }
    #expect(offset == Int.min)
    #expect(recorder.count(of: .contextEscapeCap) == 1)
}

@Test func anUnresolvedContextControlFlowProvesNoSlots() throws {
    let body = try escapeBody([0xd61f0120], at: 0x1000) // br x9: unknown local successors
    let function = DisassembledFunction(symbol: "unknown", demangledName: nil,
        startAddress: 0x1000, instructions: body, source: .address)
    #expect(AsyncContextEscapes().lowestOffset(in: function) == Int.min)
    // A separately proved async handoff/return is terminal, not a CFG gap.
    #expect(AsyncContextEscapes().lowestOffset(in: function, terminalBranches: [0x1000]) == nil)
}

@Test func aPairedContextReloadStillEscapes() throws {
    // ldp x19,x8,[x22]; add x0,x19,#16; bl mutate; ret.
    #expect(try provenSlots(resume: [0xa94022d3, 0x91004260, 0x94001000, 0xd65f03c0])[16] == nil)
}

@Test func aContextAddressingWritebackCannotLeaveAConstantProof() throws {
    // ldr x19,[x22],#16 advances a context base the alias set cannot represent.
    #expect(try provenSlots(resume: [0xf84106d3, 0x91004260, 0x94001000, 0xd65f03c0])[16] == nil)
}

@Test func anUndecodedFuncletCannotLeaveAChainWideProof() throws {
    #expect(try provenSlots(resume: [0xd65f03c0], missingResume: true)[16] == nil)
}

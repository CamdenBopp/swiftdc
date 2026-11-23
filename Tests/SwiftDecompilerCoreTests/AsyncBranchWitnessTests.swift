import Foundation
import Testing
@testable import SwiftDecompilerCore

private func branchWitnessFunction(_ words: [UInt32], missingDetailAt: UInt64? = nil) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    return DisassembledFunction(
        symbol: "resume", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.address == missingDetailAt ? nil : $0.detail)
        },
        source: .address
    )
}

private let ownerEntry = MethodEntryConvention.asyncFunclet(
    base: nil, seededRegisters: ["x0": .awaitResult(1), "x22": .asyncContext]
)
private let ownerBranch: UInt64 = 0x102c
private let nop: UInt32 = 0xd503201f

private func ownerDiamond(
    argument: UInt32 = 0xaa1f03e0, reload: UInt32 = 0xf94007f6, changeContext: UInt32 = nop,
    missingDetailAt: UInt64? = nil
) throws -> DisassembledFunction {
    let function = try branchWitnessFunction([
        0xd10043ff, // sub sp, sp, #16
        0xf90007f6, // str x22, [sp, #8]; [sp] is not an outgoing argument
        0xaa0003f3, // mov x19, x0
        0xb4000061, // cbz x1, join
        argument,  // x0 is zero, the owner, or the address of its spill
        0x94000bfb, // bl 0x4000; unknown callee
        reload,    // join: ldr x22, [sp, #8] unless the slot escaped
        0xf9000ed3, // str x19, [x22, #0x18]
        changeContext,
        0x910043ff, // add sp, sp, #16
        0x10007ec0, // adr x0, 0x2000
        0x14000ff5, // b 0x5000
    ], missingDetailAt: missingDetailAt)
    let cfg = function.controlFlowGraph
    let join = try #require(cfg.block(startingAt: 0x1018))
    try #require(cfg.blocks[join].predecessorIDs.count == 2)
    try #require(function.instructions.last?.branchTarget == 0x5000)
    return function
}

@Test(arguments: [false, true])
func asyncBranchWitnessRetainsOwnerEscapeAcrossJoin(capture: Bool) throws {
    // Both paths still have the saved x22 at the join. Only the call's x0
    // gives the chosen path durable MAY reach to the owner.
    let function = try ownerDiamond(argument: capture ? 0xf94007e0 : 0xaa1f03e0)
    var tracer = ValueTracer()
    tracer.asyncWitnessBranches = [ownerBranch, 0x101c, 0x5000]
    let witnesses = tracer.analyze(function, entry: ownerEntry).asyncBranchWitnesses
    #expect(Set(witnesses.keys) == [ownerBranch])
    let witness = try #require(witnesses[ownerBranch])
    #expect(witness.x22 == .ownerBase)
    #expect(witness.continuationAddress == 0x2000)
    #expect(witness.ownerSlots[0x18] == .awaitResult(1))
    #expect(witness.localCapture == (capture ? [.owner] : []))
}

@Test func asyncBranchWitnessRetainsOwnerEscapeThroughSpillStorage() throws {
    // add x0, sp, #8 passes the private slot's address. The unknown call may
    // read its pointer and overwrite it, so leave x22 in its original register.
    let function = try ownerDiamond(argument: 0x910023e0, reload: nop)
    var tracer = ValueTracer()
    tracer.asyncWitnessBranches = [ownerBranch]
    let witness = try #require(tracer.analyze(function, entry: ownerEntry).asyncBranchWitnesses[ownerBranch])
    #expect(witness.x22 == .ownerBase)
    #expect(witness.ownerSlots[0x18] == .awaitResult(1))
    #expect(witness.localCapture == [.owner])
}

@Test(arguments: [UInt32(0xaa1f03f6), 0x910022d6, 0x2a1603f6])
func asyncBranchWitnessRequiresExactOwnerBase(changeContext: UInt32) throws {
    // mov x22, xzr; add x22, x22, #8; mov w22, w22
    let function = try ownerDiamond(changeContext: changeContext)
    var tracer = ValueTracer()
    tracer.asyncWitnessBranches = [ownerBranch]
    let witness = try #require(tracer.analyze(function, entry: ownerEntry).asyncBranchWitnesses[ownerBranch])
    #expect(witness.x22 == .unproven)
    #expect(witness.ownerSlots[0x18] == .awaitResult(1))
}

@Test(arguments: [false, true])
func asyncBranchWitnessDistinguishesChildIdentityAndCapture(capture: Bool) throws {
    let function = try branchWitnessFunction([
        capture ? 0xaa1603e0 : 0xaa1f03e0, // pass child or zero in x0
        0x94000bff, // bl 0x4000
        0xd2840000, // mov x0, #0x2000; an integer is not an address fact
        0x14000ffd, // b 0x5000
    ])
    var tracer = ValueTracer()
    tracer.asyncWitnessBranches = [0x100c]
    let entry = MethodEntryConvention.asyncFunclet(base: nil, seededRegisters: ["x22": .asyncCalleeContext])
    let witness = try #require(tracer.analyze(function, entry: entry).asyncBranchWitnesses[0x100c])
    #expect(witness.x22 == .childBase)
    #expect(witness.continuationAddress == nil)
    #expect(witness.localCapture == (capture ? [.child] : []))
}

@Test func asyncBranchWitnessRequiresOptInAndConvergence() throws {
    let function = try ownerDiamond()
    var tracer = ValueTracer()
    #expect(tracer.analyze(function, entry: ownerEntry).asyncBranchWitnesses.isEmpty)
    tracer.asyncWitnessBranches = [ownerBranch]
    tracer.stateFactBudget = 0
    #expect(tracer.analyze(function, entry: ownerEntry).asyncBranchWitnesses.isEmpty)
}

@Test func asyncBranchWitnessReplayLeavesProbeRecordsUnchanged() throws {
    let function = try ownerDiamond(argument: 0xf94007e0)
    let baseline = ProbeRecorder()
    let ordinary = Probe.recording(baseline) {
        ValueTracer().analyze(function, entry: ownerEntry, cfg: FunctionCFG(function))
    }
    var tracer = ValueTracer()
    tracer.asyncWitnessBranches = [ownerBranch]
    let observed = ProbeRecorder()
    let withWitness = Probe.recording(observed) {
        tracer.analyze(function, entry: ownerEntry, cfg: FunctionCFG(function))
    }

    #expect(ordinary.asyncBranchWitnesses.isEmpty)
    #expect(withWitness.asyncBranchWitnesses[ownerBranch]?.localCapture == [.owner])
    try #require(baseline.count(of: .cfgGraphBuilt) == 1)
    try #require(baseline.count(of: .cfgGraphUsed) > 0)
    #expect(observed.records == baseline.records)
}

@Test func asyncBranchWitnessDeclinesAtTheIterationCap() throws {
    // More distinct blocks than the fixed allowance with iterationsPerBlock=0.
    let words = Array(repeating: UInt32(0xb4000021), count: 20) + [0x14000040]
    let function = try branchWitnessFunction(words)
    var tracer = ValueTracer()
    tracer.asyncWitnessBranches = [0x1050]
    try #require(tracer.analyze(function, entry: ownerEntry).asyncBranchWitnesses[0x1050] != nil)
    tracer.iterationsPerBlock = 0
    #expect(tracer.analyze(function, entry: ownerEntry).asyncBranchWitnesses.isEmpty)
}

@Test(arguments: [UInt64(0x1014), 0x102c])
func asyncBranchWitnessDeclinesAfterMissingDetail(address: UInt64) throws {
    // The first address is in a predecessor that could capture the owner.
    // The other is the branch itself, outside the replayed prefix.
    let function = try ownerDiamond(argument: 0xf94007e0, missingDetailAt: address)
    var tracer = ValueTracer()
    tracer.asyncWitnessBranches = [ownerBranch]
    #expect(tracer.analyze(function, entry: ownerEntry).asyncBranchWitnesses.isEmpty)
}

@Test func asyncBranchWitnessObservesTheRawMeetBeforeSelectEnrichment() throws {
    let function = try branchWitnessFunction([
        0xb4000061, // cbz x1, 0x100c
        0xd2800028, // mov x8, #1
        0x14000002, // b 0x1010
        0xd2800048, // mov x8, #2
        0xf9000ac8, // str x8, [x22, #16]
        0x10007f60, // adr x0, 0x2000
        0x14000ffa, // b 0x5000
    ])
    let branch: UInt64 = 0x1018
    let entry = MethodEntryConvention.asyncFunclet(base: .swiftFunction(scalarArguments: ["x1": 0]),
        seededRegisters: ["x22": .asyncContext])
    var tracer = ValueTracer()
    tracer.asyncWitnessBranches = [branch]
    tracer.asyncSlotFactBranches = [branch]
    let analysis = tracer.analyze(function, entry: entry)
    let witness = try #require(analysis.asyncBranchWitnesses[branch])
    #expect(witness.x22 == .ownerBase)
    #expect(witness.ownerSlots[16] == nil)
    guard case .select? = analysis.asyncSlotFactsAtBranches[branch]?[16] else {
        Issue.record("Expected the render pass to reconstruct the select")
        return
    }
}

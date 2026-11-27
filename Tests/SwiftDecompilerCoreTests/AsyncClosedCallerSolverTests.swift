import Foundation
import Testing
@testable import SwiftDecompilerCore

private typealias Solver = AsyncClosedCallerSolver

private func awaitIdentity(
    site: UInt64 = 0x101c, task: UInt64 = 1,
    carrier: Solver.AwaitIdentity.Carrier = .normalIntegerX0
) -> Solver.AwaitIdentity {
    .init(callEdge: .init(source: 0x1000, branch: site),
          taskGeneration: task, ownerGeneration: 0x1000, returnEntry: 0x2000, carrier: carrier)
}

private func closedCallerRegion(
    alternate: [Solver.Effect] = [], release: Int = 9, scalarOffset: Int = 16,
    hopTarget: UInt64 = 0x3000, executorWord: UInt64 = 0, queuedBytes: Range<Int> = 16..<24,
    edgeSite: UInt64 = 0x200c, extraAllocation: [Solver.Effect] = [],
    graphIncludesOrphan: Bool = false, alternateFirst: Bool = false,
    leftAwait: Solver.AwaitIdentity = awaitIdentity(), rightAwait: Solver.AwaitIdentity = awaitIdentity(),
    executorWord2: UInt64 = 0, inlineBytes: Range<Int> = 16..<24,
    postStore: [Solver.Effect] = []
) -> Solver.ModelRegion {
    // O and C allocation sites are synthetic lifetime identities. Save C in O,
    // execute an alternate arm, then recover O from C and C from O.
    var graph: [UInt64: Solver.Block] = [
        0x1000: .init(effects: [
            .allocate(site: 0x1000, extent: 32, result: 20),
            .allocate(site: 0x1020, extent: 24, result: 22),
            .storeWord(address: 22, source: 20),
            .offset(base: 20, by: 24, result: 8),
            .storeWord(address: 8, source: 22),
            .forget(20), .forget(8),
        ] + extraAllocation, exit: .successors(alternateFirst ? [0x1100, 0x1200] : [0x1200, 0x1100])),
        0x1100: .init(effects: [.returnedScalar(leftAwait, result: 0)], exit: .successors([0x2000])),
        0x1200: .init(effects: alternate + [.returnedScalar(rightAwait, result: 0)], exit: .successors([0x2000])),
        0x2000: .init(effects: [
            .loadWord(address: 22, result: 20),
            .offset(base: 20, by: 24, result: 8),
            .loadWord(address: 8, result: 9),
            .offset(base: 20, by: scalarOffset, result: 7),
            .storeWord(address: 7, source: 0),
        ] + postStore + [
            .release(release),
            .copy(from: 20, to: 22),
            .continuation(hopTarget, result: 0),
            .immediate(executorWord, result: 1), .immediate(executorWord2, result: 2),
        ], exit: .hop(.init(edge: .init(source: 0x2000, branch: edgeSite), resume: 0x3000,
            inlinePreserved: .init(allocation: 0x1000, bytes: inlineBytes),
            queuedPreserved: .init(allocation: 0x1000, bytes: queuedBytes)))),
    ]
    if graphIncludesOrphan {
        graph[0x1300] = .init(effects: [], exit: .successors([0x2000]))
    }
    return .init(entry: 0x1000, taskGeneration: 1, blocks: graph)
}

@Test func closedAsyncCallerJoinsAliasesAndCarriesOneAwaitedWord() throws {
    let solved = try #require(Solver.solve(closedCallerRegion()))
    #expect(solved.resume == 0x3000)
    #expect(solved.words == [16: awaitIdentity()])
}

@Test func closedAsyncCallerDoesNotClearPublishedReachWhenChildIsReleased() {
    #expect(Solver.solve(closedCallerRegion(alternate: [.publish])) == nil)
    #expect(Solver.solve(closedCallerRegion(alternate: [.publish], alternateFirst: true)) == nil)
}

@Test func closedAsyncCallerDropsSavedChildAfterOverlappingByteWriteOnOnePath() {
    #expect(Solver.solve(closedCallerRegion(alternate: [
        .loadWord(address: 22, result: 8),
        .offset(base: 8, by: 31, result: 8),
        .clobber(address: 8, byteCount: 1),
    ])) == nil)
    #expect(Solver.solve(closedCallerRegion(alternate: [
        .loadWord(address: 22, result: 8),
        .offset(base: 8, by: 23, result: 8),
        .clobber(address: 8, byteCount: 1),
    ]))?.words[16] == awaitIdentity())
}

@Test func closedAsyncCallerChecksOwnerBoundsAndReleaseTop() {
    #expect(Solver.solve(closedCallerRegion(scalarOffset: 32)) == nil)
    #expect(Solver.solve(closedCallerRegion(release: 20)) == nil)
    #expect(Solver.solve(closedCallerRegion(extraAllocation: [
        .allocate(site: 0x1030, extent: 16, result: 10),
    ])) == nil)
}

@Test func closedAsyncCallerRequiresExactGenericSwitchAndBothPreservationPaths() {
    #expect(Solver.solve(closedCallerRegion(hopTarget: 0x3004)) == nil)
    #expect(Solver.solve(closedCallerRegion(executorWord: 1)) == nil)
    #expect(Solver.solve(closedCallerRegion(queuedBytes: 16..<23)) == nil)
    #expect(Solver.solve(closedCallerRegion(executorWord2: 1)) == nil)
    #expect(Solver.solve(closedCallerRegion(inlineBytes: 16..<23)) == nil)
    #expect(Solver.solve(closedCallerRegion(graphIncludesOrphan: true)) == nil)
}

@Test func closedAsyncCallerRejectsDistinctOriginsAndNonResultCarriers() {
    #expect(Solver.solve(closedCallerRegion(rightAwait: awaitIdentity(site: 0x1020))) == nil)
    #expect(Solver.solve(closedCallerRegion(leftAwait: awaitIdentity(site: 0x1020))) == nil)
    let otherTask = awaitIdentity(task: 2)
    #expect(Solver.solve(closedCallerRegion(leftAwait: otherTask, rightAwait: otherTask)) == nil)
    let error = awaitIdentity(carrier: .typedErrorX0)
    #expect(Solver.solve(closedCallerRegion(leftAwait: error, rightAwait: error)) == nil)
}

@Test func closedAsyncCallerRejectsPartialScalarClobberAndConflictingSeed() {
    #expect(Solver.solve(closedCallerRegion(postStore: [
        .offset(base: 20, by: 23, result: 8), .clobber(address: 8, byteCount: 1),
    ])) == nil)
    let scoped = [16: AbstractValue.awaitResult(1)]
    #expect(Disassembler.mergeAsyncScalarSlots([16: .immediate(9), 24: .immediate(6)], with: scoped)
        == [24: .immediate(6)])
    #expect(Disassembler.mergeAsyncScalarSlots(scoped, with: scoped) == scoped)
}

@Test func closedAsyncCallerSolverSeedsTheOrdinaryResumeTracer() throws {
    let engine = try #require(CapstoneEngine())
    let names: [UInt64: String] = [
        0x1000: "M.entry() async -> Swift.Int",
        0x4000: "swift_task_alloc", 0x5000: "M.awaited() async -> Swift.Int",
        0x6000: "swift_task_switch", 0x7000: "M.sink(Swift.Int) -> ()",
    ]
    // Separate machine instructions exercise grouping, destination slot load,
    // ADD, and x0 at the real call. The graph above describes synthetic
    // admitted effects and intentionally cannot admit these bytes on its own.
    let bodies: [UInt64: [UInt32]] = [
        0x1000: [0x94000c00, 0xaa0003e8, 0xaa1603e9, 0x10007fb1,
                 0xd503211f, 0xa9004509, 0xaa0803f6, 0x14000ff9],
        0x2000: [0x10008000, 0xd2800001, 0xd2800002, 0x14000ffd],
        0x3000: [0xf9400ac0, 0x91000800, 0x94000ffe, 0xd65f03c0],
    ]
    var raw: [UInt64: DisassembledFunction] = [:]
    for (address, words) in bodies {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: address)
        try #require(decoded.count == words.count)
        raw[address] = .init(symbol: "synthetic", demangledName: names[address], startAddress: address,
            instructions: decoded.map {
                Instruction(address: $0.address, text: $0.text,
                    annotation: $0.branchTarget.flatMap { names[$0] },
                    controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
            }, source: .address)
    }
    let index = AsyncFuncletIndex.build(
        hints: .init(entries: [0x1000], awaitReturns: [0x2000], continuations: [0x3000]),
        functionStarts: Set(bodies.keys).union(names.keys),
        instructions: { raw[$0]?.instructions ?? [] }, nameOf: { names[$0] })
    try #require(index.transfers[0x2000]?.first?.resume == 0x3000)
    try #require(index.funclets[0x2000]?.ordinal == 1)
    let functions = raw.mapValues { function in
        index.info(for: function.startAddress, parentName: { names[$0] })
            .map(function.attachingAsyncFunclet) ?? function
    }
    let engineOwner = Disassembler()
    let unqualified = engineOwner.asyncChainSlots(index: index, function: { functions[$0] },
        enumCaseIndex: .init(), classTypeIndex: .init())
    #expect(unqualified[0x3000] == nil)
    let offSite = try #require(Solver.solve(closedCallerRegion(edgeSite: 0x2008)))
    #expect(Disassembler.asyncScalarWords(offSite, index: index) == nil)
    let model = try #require(Solver.solve(closedCallerRegion()))
    let admitted = try #require(Disassembler.asyncScalarWords(model, index: index))
    #expect(admitted == [16: .awaitResult(1)])
    let resume = try #require(functions[0x3000])
    let convention = try #require(Disassembler.asyncConvention(for: resume, base: nil, index: index))
    let analysis = ValueTracer(asyncContextSlots: admitted).analyze(resume, entry: convention)
    #expect(analysis.callSites[0x3008]?.arguments.first
        == .binary(.add, .awaitResult(1), .immediate(2)))
}

@Test func closedAsyncCallerDerivesNormalReturnFromLiveHeaderAndActualArithmetic() {
    func solve(
        loadedReturn: UInt64 = 0x2000, savedReturn: UInt64 = 0x2000,
        producer: UInt64 = 0x1410, expectedProducer: UInt64 = 0x1410, installedOwner: Int = 20,
        resultRegister: Int = 0
    ) -> Solver.Solution? {
        let identity = awaitIdentity()
        let entry: [Solver.Effect] = [
            .allocate(site: 0x1000, extent: 32, result: 20),
            .allocate(site: 0x1020, extent: 32, result: 22),
            .storeWord(address: 22, source: installedOwner),
            .offset(base: 22, by: 8, result: 8),
            .continuation(savedReturn, result: 1),
            .storeWord(address: 8, source: 1),
            .continuation(loadedReturn, result: 1),
            .integerInput(origin: 0x1404, result: 2),
            .wrappingScalarAdd(site: producer, source: 2, displacement: 1, result: resultRegister),
            .normalIntegerReturn(.init(identity: identity, childGeneration: 0x1020,
                continuationRegister: 1, producerSite: expectedProducer)),
        ]
        let resume: [Solver.Effect] = [
            .offset(base: 20, by: 24, result: 9),
            .storeWord(address: 9, source: 0),
            .copy(from: 22, to: 0), .release(0),
            .copy(from: 20, to: 22),
            .continuation(0x3000, result: 0),
            .immediate(0, result: 1), .immediate(0, result: 2),
        ]
        let sameSlot = Solver.ByteRange(allocation: 0x1000, bytes: 24..<32)
        return Solver.solve(.init(entry: 0x1000, taskGeneration: 1, blocks: [
            0x1000: .init(effects: entry, exit: .successors([0x2000])),
            0x2000: .init(effects: resume, exit: .hop(.init(
                edge: .init(source: 0x2000, branch: 0x200c), resume: 0x3000,
                inlinePreserved: sameSlot, queuedPreserved: sameSlot))),
        ]))
    }

    #expect(solve()?.words[24] == awaitIdentity())
    #expect(solve(loadedReturn: 0x2004) == nil)
    #expect(solve(savedReturn: 0x2004) == nil)
    #expect(solve(installedOwner: 22) == nil)
    #expect(solve(expectedProducer: 0x1414) == nil)
    #expect(solve(resultRegister: 3) == nil)
}

@Test func asyncPhysicalLifterRequiresRealWidthAndSuccession() throws {
    let pc: UInt64 = 0x9000
    func hasEffect(_ word: UInt32) -> Bool {
        AsyncPhysicalInstructionLifter.lift(word, at: pc, flow: .sequential, successors: [pc + 4]) != nil
    }
    #expect(hasEffect(0xf90007f6)) // str x22,[sp,#8]
    #expect(hasEffect(0xa9017bfd)) // stp x29,x30,[sp,#16]
    #expect(hasEffect(0xf81f83a9)) // stur x9,[x29,#-8]
    #expect(hasEffect(0x72ad6dc1)) // movk w1,#0x6b6e,lsl#16
    #expect(!hasEffect(0xb90007f6)) // str w22: no full-width alias claim
    #expect(!hasEffect(0xf90002d6)) // context write cannot become a native spill
    #expect(AsyncPhysicalInstructionLifter.lift(0xf90007f6, at: pc, flow: .sequential,
                                                successors: [pc + 8]) == nil)
    #expect(AsyncPhysicalInstructionLifter.lift(0x14000002, at: pc, flow: .branch,
                                                successors: [pc + 8]) != nil)
    #expect(AsyncPhysicalInstructionLifter.lift(0x14000002, at: pc, flow: .branch,
                                                successors: [pc + 4]) == nil)
}

@Test func asyncPhysicalLifterTracksNativeSpillLifetimeWithoutTreatingItAsAsyncMemory() {
    func simulate(store: UInt32 = 0xf90007f4, reload: UInt32 = 0xf94007f4,
                  insert: [UInt32] = []) -> Solver.Solution? {
        let raw: [UInt32] = [0xd10043ff, store] + insert + [reload, 0x910043ff]
        let effects = raw.enumerated().compactMap { index, word in
            let pc = UInt64(0x1800 + index * 4)
            return AsyncPhysicalInstructionLifter.lift(word, at: pc, flow: .sequential, successors: [pc + 4])
        }
        guard effects.count == raw.count else { return nil }
        let region = closedCallerRegion(postStore: effects.flatMap { $0 })
        return Solver.solve(region)
    }
    #expect(simulate()?.words[16] == awaitIdentity())
    #expect(simulate(store: 0xf9000bf4) == nil) // [sp,#16] lies beyond the owned frame
    #expect(simulate(reload: 0xf94003f4) == nil) // missing exact x20 reload
    #expect(simulate(insert: [0x910043ff, 0xd10043ff]) == nil) // stale native slot after pop/reallocate
}

@Test func asyncRelativeDescriptorRequiresSignedMatchingOperandAndActualRequestedRegister() {
    let record = AsyncFunctionDescriptor(address: 0x5000, entry: 0x4100, requiredContextSize: 32)
    let other = AsyncFunctionDescriptor(address: 0x5010, entry: 0x4300, requiredContextSize: 32)
    func solve(page: UInt64 = 0x5000, signExtend: Bool = true,
               offsetRecord: AsyncFunctionDescriptor? = nil, requested: UInt64 = 32) -> Solver.Solution? {
        var ops: [Solver.Effect] = [
            .immediate(page, result: 13),
            .materializeLocalDescriptor(expected: record, base: 13, delta: 0, result: 13),
            .descriptorPair(expected: record, base: 13, relative: 14, size: 0),
        ]
        if let offsetRecord {
            ops += [.immediate(offsetRecord.address, result: 15),
                .materializeLocalDescriptor(expected: offsetRecord, base: 15, delta: 0, result: 15),
                .descriptorPair(expected: offsetRecord, base: 15, relative: 14, size: 0)]
        }
        if signExtend { ops.append(.signExtendDescriptorOffset(register: 14)) }
        ops += [.resolveDescriptorTarget(descriptor: 13, displacement: 14, result: 16),
                .requireRelativeTarget(register: 16, entry: record.entry),
                .requireImmediate(value: requested, register: 0)]
        return Solver.solve(closedCallerRegion(postStore: ops))
    }
    #expect(solve()?.words[16] == awaitIdentity())
    #expect(solve(page: 0x5010) == nil)
    #expect(solve(signExtend: false) == nil)
    #expect(solve(offsetRecord: other) == nil)
    #expect(solve(requested: 31) == nil)

    // Claimed requirement still equals 32, but actual machine x0 was changed.
    #expect(Solver.solve(closedCallerRegion(postStore: [
        .immediate(31, result: 0), .requireImmediate(value: 32, register: 0),
    ])) == nil)
    #expect(Solver.solve(closedCallerRegion(postStore: [
        .forget(0), .requireImmediate(value: 32, register: 0),
    ])) == nil)
}

@Test func asyncNativeSpillCannotKeepAReleasedAllocationAlias() {
    let word = Solver.ByteRange(allocation: 0x1000, bytes: 24..<32)
    let spill = Solver.MachineStackWords(base: 31, offset: 0, registers: [9], load: false, update: .none)
    let reload = Solver.MachineStackWords(base: 31, offset: 0, registers: [9], load: true, update: .none)
    let effects: [Solver.Effect] = [
        .allocate(site: 0x1000, extent: 32, result: 22),
        .allocate(site: 0x1020, extent: 32, result: 9),
        .adjustMachineStack(by: -16), .machineStackWords(spill),
        .release(9), .machineStackWords(reload),
        .offset(base: 22, by: 16, result: 8),
        // An unknown word is conservatively erased. A stale known pointer
        // would reject here because its allocation generation has retired.
        .storeWord(address: 8, source: 9), .adjustMachineStack(by: 16),
        .returnedScalar(awaitIdentity(), result: 0),
        .offset(base: 22, by: 24, result: 8), .storeWord(address: 8, source: 0),
        .continuation(0x3000, result: 0), .immediate(0, result: 1), .immediate(0, result: 2),
    ]
    let model = Solver.ModelRegion(entry: 0x2000, taskGeneration: 1, blocks: [
        0x2000: .init(effects: effects, exit: .hop(.init(edge: .init(source: 0x2000, branch: 0x200c),
            resume: 0x3000, inlinePreserved: word, queuedPreserved: word))),
    ])
    #expect(Solver.solve(model)?.words[24] == awaitIdentity())
}

@Test func asyncPoppedFrameCoordinateCannotBeReusedAfterReallocation() {
    func solve(reallocate: Bool) -> Solver.Solution? {
        var ops: [Solver.Effect] = [
            .adjustMachineStack(by: -16), .formMachineFrame(offset: 0), .copy(from: 29, to: 12),
        ]
        if reallocate { ops += [.adjustMachineStack(by: 16), .adjustMachineStack(by: -16)] }
        ops += [.copy(from: 12, to: 29), .machineStackWords(.init(base: 29, offset: 0,
            registers: [20], load: false, update: .none)), .adjustMachineStack(by: 16)]
        return Solver.solve(closedCallerRegion(postStore: ops))
    }
    #expect(solve(reallocate: false)?.words[16] == awaitIdentity())
    #expect(solve(reallocate: true) == nil)
}

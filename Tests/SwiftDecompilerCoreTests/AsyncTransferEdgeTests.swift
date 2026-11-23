import Foundation
import Testing
@testable import SwiftDecompilerCore

private let transferEntry: UInt64 = 0x10000

private func transferIndex(_ words: [UInt32], awaitReturns: [UInt64] = [], continuations: [UInt64] = [],
                           names: [UInt64: String]) throws -> AsyncFuncletIndex {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: transferEntry)
    try #require(decoded.count == words.count)
    let instructions = decoded.map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
    return AsyncFuncletIndex.build(
        hints: .init(entries: [transferEntry], awaitReturns: awaitReturns, continuations: continuations),
        functionStarts: Set([transferEntry] + awaitReturns + continuations + Array(names.keys)),
        instructions: { $0 == transferEntry ? instructions : [] },
        nameOf: { names[$0] }
    )
}

@Test func asyncTransferEdgesRetainBothExecutorHopDestinations() throws {
    let site = transferEntry + 28
    let resumes = [transferEntry + 32, transferEntry + 36]
    // Each arm signs a different resume address in x16, then a shared tail
    // moves x16 to x0 and branches to swift_task_switch.
    let index = try transferIndex([
        0xb4000094, 0x100000f0, 0xdac123f0, 0x14000003,
        0x100000b0, 0xdac123f0, 0xaa1003e0, 0x14000003,
    ], continuations: resumes, names: [transferEntry + 40: "swift_task_switch"])

    #expect(index.transfers[transferEntry]?.sorted { $0.resume < $1.resume } == resumes.map {
        .init(source: transferEntry, site: site, resume: $0, kind: .executorHop,
              callee: nil, calleeName: nil, resumeKind: .continuation)
    })
    #expect(index.suspensions.count == 1)
}

@Test func asyncTransferEdgesRetainBothAwaitDestinationsAtAnUnlabelledTail() throws {
    let site = transferEntry + 48
    let resumes = [transferEntry + 52, transferEntry + 56]
    // Each arm writes its own resume pointer to the allocated child context.
    // Both arms pass that context in x22 through the same tail call.
    let index = try transferIndex([
        0x9400000f, 0xaa0003e8, 0xaa1603e9, 0x360000b8,
        0x10000131, 0xd503211f, 0xa9004509, 0x14000004,
        0x100000d1, 0xd503211f, 0xa9004509, 0xaa0803f6, 0x14000004,
    ], awaitReturns: resumes, names: [
        transferEntry + 60: "swift_task_alloc", transferEntry + 64: "m.g() async -> Swift.Int",
    ])

    #expect(index.transfers[transferEntry]?.sorted { $0.resume < $1.resume } == resumes.map {
        .init(source: transferEntry, site: site, resume: $0, kind: .awaitCall,
              callee: transferEntry + 64, calleeName: "m.g() async -> Swift.Int", resumeKind: .awaitReturn)
    })
    #expect(index.suspensions[site] == nil)
}

@Test func asyncTransferEdgesDistinguishContinuationInitFromTheSuspension() throws {
    let resume = transferEntry + 32
    // The child context lives at x22 + 16. The init call takes ownership
    // information from its header, but the next branch actually suspends.
    let index = try transferIndex([
        0xaa1603f4, 0x910042d6, 0x100000d0, 0xf9000e90,
        0xaa1603e0, 0x52800021, 0x94000003, 0x14000003,
    ], awaitReturns: [resume], names: [
        transferEntry + 36: "swift_continuation_init", transferEntry + 40: "swift_continuation_await",
    ])

    #expect(index.transfers[transferEntry] == [
        .init(source: transferEntry, site: transferEntry + 24, resume: resume,
              kind: .ownershipOnly, callee: nil, calleeName: nil, resumeKind: .awaitReturn),
    ])
    #expect(index.suspensions.isEmpty)
}

@Test func asyncTransferEdgesRetainTheRuntimeWaitBinding() throws {
    let resume = transferEntry + 20
    let runtimeWait = "swift_taskGroup_wait_next_throwing"
    // The wait takes its resume address in x2 and a result buffer in x3.
    let index = try transferIndex([
        0x100000b0, 0xdac123f0, 0xaa1003e2, 0x910042c3, 0x14000002,
    ], continuations: [resume], names: [transferEntry + 24: runtimeWait])

    #expect(index.transfers[transferEntry] == [
        .init(source: transferEntry, site: transferEntry + 16, resume: resume,
              kind: .runtimeWait(runtimeWait), callee: transferEntry + 24, calleeName: runtimeWait,
              resumeKind: .continuation),
    ])
    #expect(index.transfers[transferEntry]?.first?.runtimeWait == runtimeWait)
}

@Test func asyncTransferEdgesKeepDistinctCalleesThatResumeIntoTheSameFunclet() throws {
    let resume = transferEntry + 0x30
    let first = transferEntry + 0x44, second = transferEntry + 0x48
    let firstName = "m.f() async -> Swift.Int", secondName = "m.g() async -> Swift.Double"
    // Two arms each allocate a child context, store the same resume pointer,
    // and tail-call different async functions.
    let words: [UInt32] = [
        0xb40000c1, 0x9400000f, 0x10000149, 0xf9000409, 0xaa0003f6, 0x1400000c,
        0x9400000a, 0x100000a9, 0xf9000409, 0xaa0003f6, 0x14000008,
    ]
    let names = [transferEntry + 0x40: "swift_task_alloc", first: firstName, second: secondName]
    let index = try transferIndex(words, awaitReturns: [resume], names: names)
    #expect(index.transfers[transferEntry]?.sorted { $0.site < $1.site } == [
        .init(source: transferEntry, site: transferEntry + 20, resume: resume, kind: .awaitCall,
              callee: first, calleeName: firstName, resumeKind: .awaitReturn),
        .init(source: transferEntry, site: transferEntry + 40, resume: resume, kind: .awaitCall,
              callee: second, calleeName: secondName, resumeKind: .awaitReturn),
    ])
    #expect(index.suspension(into: resume) == nil)
}

@Test func asyncTransferEdgesKeepAConflictingHintAsAnUnknownABI() throws {
    let resume = transferEntry + 8
    // A hop to an address declared as an await return contradicts the
    // declared ABI. The discovered control edge still matters to consumers.
    let index = try transferIndex([0x10000040, 0x14000002], awaitReturns: [resume],
                                  names: [transferEntry + 12: "swift_task_switch"])
    #expect(index.transfers[transferEntry] == [
        .init(source: transferEntry, site: transferEntry + 4, resume: resume, kind: .executorHop,
              callee: nil, calleeName: nil, resumeKind: .unknown),
    ])
}

@Test func asyncTransferEdgesRetainBothOwnersAndTheirSharedDescendant() throws {
    let first: UInt64 = 0x1000, second: UInt64 = 0x2000
    let shared: UInt64 = 0x3000, taskSwitch: UInt64 = 0x4000, descendant: UInt64 = 0x5000
    // Each pair is `adr x0, continuation; b swift_task_switch`. The two
    // entries resume the same funclet, which in turn resumes its descendant.
    let index = try executorTransferIndex(entries: [first, second], continuations: [shared, descendant],
                                         taskSwitch: taskSwitch, words: [
        first: [0x10010000, 0x14000bff],
        second: [0x10008000, 0x140007ff],
        shared: [0x10010000, 0x140003ff],
    ])

    for (source, resume) in [(first, shared), (second, shared), (shared, descendant)] {
        #expect(index.transfers[source] == [
            .init(source: source, site: source + 4, resume: resume, kind: .executorHop,
                  callee: nil, calleeName: nil, resumeKind: .continuation),
        ])
    }
    for resume in [shared, descendant] {
        #expect(index.funclets[resume]?.sharedBy == [first, second])
    }
    #expect(index.suspensions.isEmpty)
}

@Test func asyncTransferEdgesKeepTheBackEdgeIntoAnAlreadyVisitedResume() throws {
    let entry: UInt64 = 0x1000, first: UInt64 = 0x2000, second: UInt64 = 0x3000, taskSwitch: UInt64 = 0x4000
    // Entry -> first -> second -> first. Both incoming handoffs to first
    // remain available despite its lack of a unique predecessor.
    let index = try executorTransferIndex(entries: [entry], continuations: [first, second],
                                         taskSwitch: taskSwitch, words: [
        entry: [0x10008000, 0x14000bff],
        first: [0x10008000, 0x140007ff],
        second: [0x10ff8000, 0x140003ff],
    ])
    #expect(index.chains[entry] == [entry, first, second])
    #expect(index.funclets[first]?.predecessor == nil)
    #expect(index.transfers[entry]?.map(\.resume) == [first])
    #expect(index.transfers[first]?.map(\.resume) == [second])
    #expect(index.transfers[second]?.map(\.resume) == [first])
}

private func executorTransferIndex(entries: [UInt64], continuations: [UInt64], taskSwitch: UInt64,
                                   words: [UInt64: [UInt32]]) throws -> AsyncFuncletIndex {
    let engine = try #require(CapstoneEngine())
    var bodies: [UInt64: [Instruction]] = [:]
    for (source, body) in words {
        let bytes = body.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: source)
        try #require(decoded.count == body.count)
        bodies[source] = decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
    }
    return AsyncFuncletIndex.build(
        hints: .init(entries: entries, continuations: continuations),
        functionStarts: Set(entries + continuations + [taskSwitch]),
        instructions: { bodies[$0] ?? [] },
        nameOf: { $0 == taskSwitch ? "swift_task_switch" : nil }
    )
}

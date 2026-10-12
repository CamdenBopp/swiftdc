import Foundation
import Testing
@testable import SwiftDecompilerCore

private func asyncBody(at start: UInt64, resume: UInt64, stored: Bool = true, callee: UInt64 = 0x4000,
                       allocated: Bool = true, outgoingContext: Bool = true) throws -> [Instruction] {
    var words: [UInt32] = allocated ? [0x94000000] : [] // annotated task_alloc
    let adrPC = start + UInt64(words.count * 4)
    let delta = UInt32(truncatingIfNeeded: resume &- adrPC) & 0x1fffff
    words.append(0x10000009 | ((delta & 3) << 29) | ((delta >> 2) << 5))
    if stored { words.append(0xf9000409) } // str x9, [x0, #8]
    if outgoingContext { words.append(0xaa0003f6) } // mov x22, x0
    let branchPC = start + UInt64(words.count * 4)
    words.append(0x14000000 | (UInt32(truncatingIfNeeded: (callee &- branchPC) >> 2) & 0x3ffffff))
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let engine = try #require(CapstoneEngine())
    let decoded = engine.disassemble(Data(bytes), address: start)
    #expect(decoded.count == words.count)
    return decoded.map { Instruction(address: $0.address, text: $0.text,
        annotation: $0.controlFlow == .call ? "swift_task_alloc" : nil,
        controlFlow: $0.controlFlow, branchTarget: $0.controlFlow == .call ? nil : $0.branchTarget, detail: $0.detail) }
}

@Test func asyncUnusedResumeAddressIsNotOwnershipEvidence() throws {
    let body = try asyncBody(at: 0x1000, resume: 0x3000, stored: false)
    let index = AsyncFuncletIndex.build(
        hints: .init(entries: [0x1000], awaitReturns: [0x3000]),
        functionStarts: [0x1000, 0x3000], instructions: { $0 == 0x1000 ? body : [] }, nameOf: { _ in nil })
    #expect(index.funclets[0x3000]?.parent == nil)
    #expect(index.suspensions.isEmpty)
}

@Test func asyncConflictingParentsDeclineOwnershipAndResult() throws {
    let first = try asyncBody(at: 0x1000, resume: 0x3000)
    let second = try asyncBody(at: 0x2000, resume: 0x3000, callee: 0x5000)
    let index = AsyncFuncletIndex.build(
        hints: .init(entries: [0x1000, 0x2000], awaitReturns: [0x3000]),
        functionStarts: [0x1000, 0x2000, 0x3000], instructions: { $0 == 0x1000 ? first : ($0 == 0x2000 ? second : []) },
        nameOf: { $0 == 0x4000 ? "m.f() async -> Swift.Int" : "m.g() async -> Swift.Double" })
    #expect(index.funclets[0x3000]?.parent == nil)
    #expect(index.suspension(into: 0x3000) == nil)
    #expect(Disassembler.awaitedResultRegister(into: 0x3000, index: index) == nil)
    // Declined because two chains own it, which reads differently from a
    // funclet no chain reaches.
    #expect(index.info(for: 0x3000, parentName: { _ in nil })?.sharedBy == [0x1000, 0x2000])
}

@Test func asyncUniqueStoredResumeStillRecovers() throws {
    let body = try asyncBody(at: 0x1000, resume: 0x3000)
    let index = AsyncFuncletIndex.build(
        hints: .init(entries: [0x1000], awaitReturns: [0x3000]),
        functionStarts: [0x1000, 0x3000], instructions: { $0 == 0x1000 ? body : [] },
        nameOf: { _ in "m.f() async -> Swift.Int" })
    #expect(index.funclets[0x3000]?.parent == 0x1000)
    #expect(Disassembler.awaitedResultRegister(into: 0x3000, index: index) == "x0")
}

/// Two sites of one function resuming into one funclet is a loop
/// (libswift_Concurrency's `AsyncCompactMapSequence.Iterator.next()` re-awaits
/// into resume #1 from resume #4): the owner is proven, but no single
/// predecessor or awaited callee is, so neither is reported.
@Test func asyncMultipleSitesInOneParentDeclineResult() throws {
    let first = try asyncBody(at: 0x1000, resume: 0x3000)
    let second = try asyncBody(at: 0x1020, resume: 0x3000, callee: 0x5000)
    let index = AsyncFuncletIndex.build(
        hints: .init(entries: [0x1000], awaitReturns: [0x3000]),
        functionStarts: [0x1000, 0x3000], instructions: { $0 == 0x1000 ? first + second : [] },
        nameOf: { $0 == 0x4000 ? "m.f() async -> Swift.Int" : "m.g() async -> Swift.Double" })
    #expect(index.funclets[0x3000]?.parent == 0x1000)
    #expect(index.funclets[0x3000]?.predecessor == nil)
    #expect(index.suspension(into: 0x3000) == nil)
    #expect(Disassembler.awaitedResultRegister(into: 0x3000, index: index) == nil)
}

@Test func asyncArbitraryMemoryStoreIsNotContextHandoff() throws {
    let body = try asyncBody(at: 0x1000, resume: 0x3000, allocated: false)
    let index = AsyncFuncletIndex.build(
        hints: .init(entries: [0x1000], awaitReturns: [0x3000]),
        functionStarts: [0x1000, 0x3000], instructions: { $0 == 0x1000 ? body : [] }, nameOf: { _ in nil })
    #expect(index.funclets[0x3000]?.parent == nil)
    #expect(index.suspensions.isEmpty)
}

@Test func asyncStoredContextMustBePassedInX22() throws {
    let body = try asyncBody(at: 0x1000, resume: 0x3000, outgoingContext: false)
    let index = AsyncFuncletIndex.build(
        hints: .init(entries: [0x1000], awaitReturns: [0x3000]),
        functionStarts: [0x1000, 0x3000], instructions: { $0 == 0x1000 ? body : [] }, nameOf: { _ in nil })
    #expect(index.funclets[0x3000]?.parent == nil)
    #expect(index.suspensions.isEmpty)
}

@Test func asyncHintsMustNameDeclaredFunctionBoundaries() throws {
    var decoded: [UInt64] = []
    let index = AsyncFuncletIndex.build(
        hints: .init(entries: [0x1001, 0x2000], awaitReturns: [0x3002]),
        functionStarts: [0x1000, 0x3000], instructions: { decoded.append($0); return [] }, nameOf: { _ in nil })
    #expect(decoded.isEmpty)
    #expect(index.isEmpty)
}

@Test func asyncAwaitedResultRequiresKnownScalarABI() throws {
    let body = try asyncBody(at: 0x1000, resume: 0x3000)
    for type in ["Example.BigStruct", "Example.UnknownClass", "(Swift.Int) -> Swift.Int"] {
        let index = AsyncFuncletIndex.build(
            hints: .init(entries: [0x1000], awaitReturns: [0x3000]),
            functionStarts: [0x1000, 0x3000], instructions: { $0 == 0x1000 ? body : [] },
            nameOf: { _ in "m.f() async -> \(type)" })
        #expect(index.funclets[0x3000]?.parent == 0x1000)
        #expect(Disassembler.awaitedResultRegister(into: 0x3000, index: index) == nil)
    }
}

@Test func asyncNarrowStoreAndCopyAreNotResumeHandoffs() throws {
    // A real allocated context and outgoing x22 make the width check decisive.
    // The final wide-store variant is the positive control.
    for (middle, recovers): ([UInt32], Bool) in [
        ([0xb9000809], false), // str w9,[x0,#8]
        ([0x2a0903ea, 0xf900040a], false), // mov w10,w9; str x10,[x0,#8]
        ([0xf9000409], true), // str x9,[x0,#8]
    ] {
        let words: [UInt32] = [0x94000000, 0x1000ffe9] + middle + [0xaa0003f6, 0x14000bfc]
        let engine = try #require(CapstoneEngine())
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let body = engine.disassemble(Data(bytes), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text,
                        annotation: $0.controlFlow == .call ? "swift_task_alloc" : nil,
                        controlFlow: $0.controlFlow,
                        branchTarget: $0.controlFlow == .call ? nil : $0.branchTarget, detail: $0.detail)
        }
        #expect(body.count == words.count)
        let index = AsyncFuncletIndex.build(hints: .init(entries: [0x1000], awaitReturns: [0x3000]),
            functionStarts: [0x1000, 0x3000], instructions: { $0 == 0x1000 ? body : [] }, nameOf: { _ in nil })
        #expect((index.funclets[0x3000]?.parent != nil) == recovers)
        #expect(index.suspensions.isEmpty == !recovers)
    }
}

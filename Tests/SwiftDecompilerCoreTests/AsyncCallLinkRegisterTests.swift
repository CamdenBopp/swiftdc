import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An ordinary call replaces LR before its callee executes. A value loaded
/// into LR earlier cannot become a resume pointer or context after the call.
private func asyncLinkRegisterIndex(domain: Int, indirect: Bool, preserved: Bool,
                                    hints: Bool) throws -> AsyncFuncletIndex {
    var words: [UInt32] = []
    let register: UInt32 = preserved ? 19 : 30
    func emit(_ word: UInt32) { words.append(word) }
    func branch(_ target: UInt64, link: Bool) {
        let pc = UInt64(0x1000 + words.count * 4)
        emit((link ? 0x94000000 : 0x14000000)
            | (UInt32(truncatingIfNeeded: (Int64(target) - Int64(pc)) >> 2) & 0x03ffffff))
    }
    func adr(_ reg: UInt32, _ target: UInt64) {
        let delta = target - UInt64(0x1000 + words.count * 4)
        emit(0x10000000 | reg | UInt32(delta & 3) << 29 | UInt32(delta >> 2) << 5)
    }
    func move(_ dst: UInt32, _ src: UInt32) { emit(0xaa0003e0 | src << 16 | dst) }
    branch(0x4000, link: true) // fresh child context in x0
    move(20, 0)               // callee-saved allocation alias
    switch domain {
    case 0: adr(register, 0x2000)
    case 1: emit(0xb0000000 | register) // adrp register, 0x2000
    default: move(register, 0)
    }
    move(0, 31) // the opaque call is not passed the context
    if indirect {
        adr(9, 0x6000)
        emit(0xd63f0120) // blr x9
    } else {
        branch(0x6000, link: true)
    }
    if domain == 2 {
        move(1, register)
        adr(8, 0x2000)
    } else {
        if domain == 0 { move(8, register) }
        else { emit(0x91000008 | register << 5) } // add x8, register, #0
        move(1, 20)
    }
    emit(0xa9002036) // stp x22, x8, [x1]
    move(22, 1)
    branch(0x5000, link: false)
    let engine = try #require(CapstoneEngine())
    var decoded: [UInt64: [Instruction]] = [:]
    for (start, body) in [UInt64(0x1000): words, 0x2000: [0xd65f03c0],
                          0x4000: [0xd65f03c0], 0x5000: [0xd65f03c0], 0x6000: [0xd65f03c0]] {
        decoded[start] = engine.disassemble(body.withUnsafeBytes { Data($0) }, address: start).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        try #require(decoded[start]?.count == body.count)
    }
    return AsyncFuncletIndex.build(
        hints: hints ? .init(entries: [0x1000], awaitReturns: [0x2000], continuations: []) : nil,
        functionStarts: Set(decoded.keys), instructions: { decoded[$0] ?? [] }, nameOf: {
            switch $0 {
            case 0x4000: "swift_task_alloc"
            case 0x5000: "Own.worker() async -> Swift.Int64"
            default: nil
            }
        })
}

@Test func asyncCallsForgetPriorLinkRegisterAddressesPagesAndContexts() throws {
    for hints in [true, false] {
        for indirect in [true, false] {
            for domain in 0...2 {
                let index = try asyncLinkRegisterIndex(domain: domain, indirect: indirect,
                                                       preserved: false, hints: hints)
                #expect(index.chains[0x1000] != [0x1000, 0x2000],
                        "domain=\(domain), indirect=\(indirect), hints=\(hints)")
                #expect(index.suspensions.isEmpty)
            }
        }
    }
}

@Test func asyncCallsKeepCalleeSavedAddressesPagesAndContexts() throws {
    for hints in [true, false] {
        for indirect in [true, false] {
            for domain in 0...2 {
                let index = try asyncLinkRegisterIndex(domain: domain, indirect: indirect,
                                                       preserved: true, hints: hints)
                #expect(index.chains[0x1000] == [0x1000, 0x2000],
                        "domain=\(domain), indirect=\(indirect), hints=\(hints)")
                #expect(index.suspensions.count == 1)
            }
        }
    }
}

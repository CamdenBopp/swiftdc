import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A native stack base plus (child - stack + 8) addresses the child's saved
/// resume pointer. The base's provenance alone cannot classify that store.
private func indexedFrameIndex(base: Int, width: Int, index: Int?, load: Bool = false,
                               hints: Bool) throws -> AsyncFuncletIndex {
    func branch(_ from: UInt64, _ to: UInt64, link: Bool) -> UInt32 {
        (link ? 0x94000000 : 0x14000000)
            | (UInt32(truncatingIfNeeded: (Int64(to) - Int64(from)) >> 2) & 0x03ffffff)
    }
    let entry: UInt64 = 0x1000, resume: UInt64 = 0x2008
    let adrPC: UInt64 = 0x100c, delta = resume - adrPC
    let adr = UInt32(0x10000000) | 8 | UInt32(delta & 3) << 29 | UInt32(delta >> 2) << 5
    var words: [UInt32] = [
        0xd10083ff, 0x910043fd, // sub sp,sp,#32; add x29,sp,#16
        branch(0x1008, 0x4000, link: true),
        adr, 0xa9002016, 0xaa0003f6, // header then child context in x22
    ]
    if base == 31 { words += [0x910003ea] } // mov x10,sp
    let subtractor = base == 31 ? 10 : 29
    words += [0xcb0002c9 | UInt32(subtractor << 16), 0x91002129]
    let memory: UInt32
    if let index {
        let opcode: UInt32 = load ? 0xf8606800 : (width == 8 ? 0x38206800 : 0xf8206800)
        memory = opcode | UInt32(index << 16) | UInt32(base << 5) | 31
    } else {
        try #require(!load)
        let opcode: UInt32 = width == 8 ? 0x39002000 : 0xf9000400
        memory = opcode | UInt32(base << 5) | 31
    }
    words += [memory]
    words += [branch(entry + UInt64(words.count * 4), 0x5000, link: false)]
    let bodies: [UInt64: [UInt32]] = [entry: words, resume: [0xd65f03c0],
                                    0x4000: [0xd65f03c0], 0x5000: [0xd65f03c0]]
    let engine = try #require(CapstoneEngine())
    var decoded: [UInt64: [Instruction]] = [:]
    for (address, code) in bodies {
        decoded[address] = engine.disassemble(code.withUnsafeBytes { Data($0) }, address: address).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        try #require(decoded[address]?.count == code.count)
    }
    return AsyncFuncletIndex.build(
        hints: hints ? .init(entries: [entry], awaitReturns: [resume], continuations: []) : nil,
        functionStarts: Set(bodies.keys), instructions: { decoded[$0] ?? [] },
        nameOf: { address in
            switch address {
            case 0x4000: "swift_task_alloc"
            case 0x5000: "Own.worker() async -> Swift.Int64"
            default: nil
            }
        })
}

@Test func asyncIndexedNativeFrameWritesCannotPreserveResumeOwnership() throws {
    for hints in [true, false] {
        for base in [29, 31] {
            for width in [8, 64] {
                let index = try indexedFrameIndex(base: base, width: width, index: 9, hints: hints)
                #expect(index.funclets[0x2008]?.parent == nil)
                #expect(index.suspension(into: 0x2008) == nil)
            }
        }
    }
}

@Test func asyncDirectAndZeroIndexedFrameStoresKeepResumeOwnership() throws {
    for hints in [true, false] {
        for base in [29, 31] {
            for width in [8, 64] {
                for register: Int? in [nil, 31] {
                    // A literal zero register stays zero under shifts and
                    // extensions; it adds no unknown offset to the frame.
                    let index = try indexedFrameIndex(base: base, width: width, index: register, hints: hints)
                    #expect(index.chains[0x1000] == [0x1000, 0x2008])
                    let suspension = try #require(index.suspension(into: 0x2008))
                    #expect(suspension.suspension.callee == 0x5000)
                }
            }
        }
    }
}

@Test func asyncIndexedNativeFrameLoadsKeepResumeOwnership() throws {
    for hints in [true, false] {
        for base in [29, 31] {
            let index = try indexedFrameIndex(base: base, width: 64, index: 9, load: true, hints: hints)
            #expect(index.chains[0x1000] == [0x1000, 0x2008])
            #expect(index.suspension(into: 0x2008)?.suspension.callee == 0x5000)
        }
    }
}

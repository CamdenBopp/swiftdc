import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The child context has a known identity before any header stores. Register
/// spelling cannot turn that pointer into a hardware stack address. These
/// machine-word reductions compare x19 and x29 on the same inline header and
/// store path; they do not claim a particular compiler emits this alias.
private func frameAliasIndex(alias: Int?, store: UInt32, hints: Bool, headerBase: Int = 0,
                             betweenHeaderAndStore: [UInt32] = [], beforeAllocation: [UInt32] = [],
                             aliasSource: Int = 0, outlinedHeader: Bool = false,
                             beforeHeader: [UInt32] = []) throws -> AsyncFuncletIndex {
    func branch(_ from: UInt64, _ to: UInt64, link: Bool) -> UInt32 {
        (link ? 0x94000000 : 0x14000000)
            | (UInt32(truncatingIfNeeded: (Int64(to) - Int64(from)) >> 2) & 0x03ffffff)
    }
    let adrPC = UInt64(0x1008 + beforeAllocation.count * 4)
    let delta = UInt64(0x2000) - adrPC
    let adr = UInt32(0x10000000) | 8 | UInt32(delta & 3) << 29 | UInt32(delta >> 2) << 5
    var entry: [UInt32] = beforeAllocation + [
        branch(0x1000 + UInt64(beforeAllocation.count * 4), 0x4000, link: true),
        alias.map { 0xaa0003e0 | UInt32(aliasSource << 16) | UInt32($0) } ?? 0xd503201f,
        adr,
    ]
    entry += beforeHeader
    if outlinedHeader {
        entry += [branch(0x1000 + UInt64(entry.count * 4), 0x3000, link: true)]
    } else {
        entry += [0xa9002016 | UInt32(headerBase << 5), 0xaa0003f6]
    }
    entry += betweenHeaderAndStore
    entry += [store]
    entry += [branch(0x1000 + UInt64(entry.count * 4), 0x5000, link: false)]
    var bodies: [UInt64: [UInt32]] = [0x1000: entry, 0x2000: [0xd65f03c0],
                                    0x4000: [0xd65f03c0], 0x5000: [0xd65f03c0]]
    if outlinedHeader {
        bodies[0x3000] = [0xa9002016 | UInt32(headerBase << 5),
                          0xaa0003f6 | UInt32(headerBase << 16), 0xd65f03c0]
    }
    let engine = try #require(CapstoneEngine())
    var decoded: [UInt64: [Instruction]] = [:]
    for (address, words) in bodies {
        decoded[address] = engine.disassemble(words.withUnsafeBytes { Data($0) }, address: address).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        try #require(decoded[address]?.count == words.count)
    }
    return AsyncFuncletIndex.build(
        hints: hints ? .init(entries: [0x1000], awaitReturns: [0x2000], continuations: []) : nil,
        functionStarts: Set(bodies.keys), instructions: { decoded[$0] ?? [] },
        nameOf: { address in
            switch address {
            case 0x4000: "swift_task_alloc"
            case 0x5000: "Own.worker() async -> Swift.Int64"
            default: nil
            }
        })
}

private func frameDiamondFunction(ambiguous: Bool = false, looping: Bool = false,
                                  backToEntry: Bool = false) throws -> DisassembledFunction {
    func branch(_ from: UInt64, _ to: UInt64, link: Bool) -> UInt32 {
        (link ? 0x94000000 : 0x14000000)
            | (UInt32(truncatingIfNeeded: (Int64(to) - Int64(from)) >> 2) & 0x03ffffff)
    }
    let delta: UInt64 = 0x2008 - 0x102c
    let adr = UInt32(0x10000000) | 8 | UInt32(delta & 3) << 29 | UInt32(delta >> 2) << 5
    // Two diamonds put the suspension beyond a predecessor merge in every
    // bounded straight-line window. x29 is unchanged on all safe paths.
    let words: [UInt32] = [
        0xd10083ff, 0x910043fd, 0xb4000061,
        ambiguous ? 0xaa1303fd : 0xd503201f,
        branch(0x1010, looping ? 0x1008 : 0x1018, link: false),
        0xd503201f, 0xb4000062, 0xd503201f,
        branch(0x1020, 0x1028, link: false), 0xd503201f,
        branch(0x1028, 0x4000, link: true), adr,
        0xa9002016, 0xaa0003f6, 0xf9000bbf,
        branch(0x103c, backToEntry ? 0x1000 : 0x5000, link: false),
    ]
    let engine = try #require(CapstoneEngine())
    let decoded = engine.disassemble(words.withUnsafeBytes { Data($0) }, address: 0x1000).map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "Own.frameBranches", demangledName: nil, startAddress: 0x1000,
                                instructions: decoded, source: .address)
}

@Test func asyncKnownFrameRegisterContextStoresInvalidateResumeOwnership() throws {
    for hints in [true, false] {
        for register in [19, 29] {
            // Wide, paired, narrow and SIMD writes all overlap ResumeParent.
            // A narrow store of the alias itself also verifies
            // that its provenance is captured before default register kills.
            for (name, instruction, source): (String, UInt32, Int?) in [
                ("str64", 0xf9000400, 31),
                ("stur64", 0xf8008000, 31),
                ("stp64", 0xa9007c00, 31),
                ("str32", 0xb9000800, 31),
                ("str16", 0x79001000, 31),
                ("str8", 0x39002000, 31),
                ("str8-alias-source", 0x39002000, nil),
                ("str128", 0x3d800000, 0),
            ] {
                let word = instruction | UInt32(register << 5) | UInt32(source ?? register)
                let index = try frameAliasIndex(alias: register, store: word, hints: hints)
                let context = Comment(rawValue: "\(name) x\(register), hints=\(hints)")
                #expect(index.funclets[0x2000]?.parent == nil, context)
                #expect(index.suspension(into: 0x2000) == nil, context)
            }
        }
    }
}

@Test func asyncKnownFrameRegisterContextDisjointStoresKeepResumeOwnership() throws {
    for hints in [true, false] {
        for register in [19, 29] {
            for headerBase in [0, register] {
                for word: UInt32 in [0xd503201f, 0xf9000800 | UInt32(register << 5) | 31] {
                    let index = try frameAliasIndex(alias: register, store: word, hints: hints, headerBase: headerBase)
                    #expect(index.chains[0x1000] == [0x1000, 0x2000])
                    let site = try #require(index.suspension(into: 0x2000))
                    #expect(site.address == 0x1018 && site.suspension.callee == 0x5000)
                }
            }
        }
    }
}

@Test func asyncHardwareFrameStoresKeepResumeOwnership() throws {
    for hints in [true, false] {
        // Without a known async-context alias, x29 and sp keep the ordinary
        // hardware-frame contract; writing the caller stack is not a write
        // into the independently allocated child context.
        for base in [29, 31] {
            let index = try frameAliasIndex(alias: nil, store: 0xf9000400 | UInt32(base << 5) | 31, hints: hints)
            #expect(index.chains[0x1000] == [0x1000, 0x2000])
            #expect(index.suspension(into: 0x2000)?.address == 0x1018)
        }
    }
}

@Test func asyncLostContextFactsNeverBecomeHardwareFrameProofs() throws {
    for hints in [true, false] {
        for register in [19, 29] {
            let base = UInt32(register << 5)
            let registerBits = UInt32(register)
            for between in [
                [UInt32(0x8b1f0000) | base | registerBits], // add xN,xN,xzr: identity
                [UInt32(0xca1f0000) | base | registerBits], // eor xN,xN,xzr: identity
                // A disjoint narrow store loses the register-only context fact.
                // Re-establish ResumeParent through live x22 before zeroing it.
                [UInt32(0x39004000) | base | registerBits, 0xf90006c8],
            ] {
                let index = try frameAliasIndex(alias: register, store: 0xf9000400 | base | 31,
                                               hints: hints, betweenHeaderAndStore: between)
                #expect(index.funclets[0x2000]?.parent == nil)
                #expect(index.suspension(into: 0x2000) == nil)
            }
        }
    }
}

@Test func asyncProvedHardwareFrameRestorationsKeepResumeOwnership() throws {
    for hints in [true, false] {
        for restoration: [UInt32] in [
            [0x910003fd],                         // mov x29,sp
            [0x910043fd],                         // add x29,sp,#16
            [0x910003f3, 0xaa1303fd],             // mov x19,sp; mov x29,x19
            [0x910043f3, 0xaa1303fd],             // add x19,sp,#16; mov x29,x19
            [0x910043f3, 0xd1002273, 0xaa1303fd], // subtract a constant from that frame alias
        ] {
            for store: UInt32 in [0xf90007bf, 0xa9bf7fbf, 0x390023bf, 0x381fffbf] {
                // The pre-indexed store changes x29 after addressing native
                // stack memory; classification must use its incoming proof.
                let index = try frameAliasIndex(alias: 29, store: store, hints: hints,
                                               betweenHeaderAndStore: restoration)
                #expect(index.chains[0x1000] == [0x1000, 0x2000])
                let site = try #require(index.suspension(into: 0x2000))
                #expect(site.address == 0x1018 + UInt64(restoration.count * 4))
            }
        }
        for outlined in [true, false] {
            let index = try frameAliasIndex(alias: 29, store: 0xf90007bf, hints: hints,
                                           beforeAllocation: [0x910003f3], aliasSource: 19, outlinedHeader: outlined)
            #expect(index.chains[0x1000] == [0x1000, 0x2000])
        }
    }
}

@Test func asyncUnprovedFrameRestorationsCannotHidePossibleContextWrites() throws {
    for hints in [true, false] {
        for restoration: [UInt32] in [
            [0xaa1303fd],                         // x19 has no proved stack provenance
            [0x110003fd],                         // mov w29,wsp truncates a 64-bit stack address
            [0x910003f3, 0xa9404fe0, 0xaa1303fd], // LDP replaces its second destination x19
        ] {
            let index = try frameAliasIndex(alias: 29, store: 0xf90007bf, hints: hints,
                                           betweenHeaderAndStore: restoration)
            #expect(index.funclets[0x2000]?.parent == nil)
            #expect(index.suspension(into: 0x2000) == nil)
        }
        // The allocator replaces x0 and BL replaces LR. Their old native
        // stack aliases cannot prove that a later x29 store addresses a frame.
        for source in [0, 30] {
            let index = try frameAliasIndex(alias: 29, store: 0xf90007bf, hints: hints,
                                           beforeAllocation: [0x910003e0 | UInt32(source)], aliasSource: source)
            #expect(index.funclets[0x2000]?.parent == nil)
            #expect(index.suspension(into: 0x2000) == nil)
        }
        for (beforeAllocation, beforeHeader, after): ([UInt32], [UInt32], [UInt32]) in [
            ([0x910003f6], [], [0xaa1603fd]), // header helper replaces x22's old stack pointer
            ([], [0x910003fe], [0xaa1e03fd]), // its BL replaces LR's old stack pointer
        ] {
            let index = try frameAliasIndex(alias: 29, store: 0xf90007bf, hints: hints,
                                           betweenHeaderAndStore: after, beforeAllocation: beforeAllocation,
                                           outlinedHeader: true, beforeHeader: beforeHeader)
            #expect(index.funclets[0x2000]?.parent == nil)
            #expect(index.suspension(into: 0x2000) == nil)
        }
    }
}

@Test func asyncFrameProvenanceCrossesCFGJoinsWithoutAssumingAmbiguousArms() throws {
    for hints in [true, false] {
        for ambiguous in [false, true] {
            let function = try frameDiamondFunction(ambiguous: ambiguous)
            let index = AsyncFuncletIndex.build(
                hints: hints ? .init(entries: [0x1000], awaitReturns: [0x2008], continuations: []) : nil,
                functionStarts: [0x1000, 0x2008, 0x4000, 0x5000],
                instructions: { $0 == 0x1000 ? function.instructions : [] },
                nameOf: { $0 == 0x4000 ? "swift_task_alloc" : ($0 == 0x5000 ? "Own.worker() async -> Swift.Int64" : nil) })
            if ambiguous {
                #expect(index.funclets[0x2008]?.parent == nil)
                #expect(index.suspension(into: 0x2008) == nil)
            } else {
                #expect(index.chains[0x1000] == [0x1000, 0x2008])
                let site = try #require(index.suspension(into: 0x2008))
                #expect(site.address == 0x103c)
            }
        }
    }
}

@Test func asyncHardwareFrameFactsMeetBackedgesAndDeclineAnIncompleteSolve() throws {
    for ambiguous in [false, true] {
        for looping in [false, true] {
            let function = try frameDiamondFunction(ambiguous: ambiguous, looping: looping)
            let blocks = AsyncFuncletIndex.trapGuardedRuns(function.basicBlocks())
            let inputs = AsyncHardwareFrames.inputs(in: blocks, entry: 0x1000, isHeaderHelper: { _ in false })
            #expect(inputs[0x1028]?.contains("x29") == !ambiguous)
            // A capped solve must discard even the already-proven entry fact.
            let capped = AsyncHardwareFrames.inputs(in: blocks, entry: 0x1000, maximumVisits: 1,
                                                   isHeaderHelper: { _ in false })
            #expect(capped.isEmpty)
        }
    }
    let entryLoop = try frameDiamondFunction(ambiguous: true, backToEntry: true)
    let inputs = AsyncHardwareFrames.inputs(in: AsyncFuncletIndex.trapGuardedRuns(entryLoop.basicBlocks()),
                                            entry: 0x1000, isHeaderHelper: { _ in false })
    #expect(inputs[0x1000]?.contains("x29") == false)
    let safe = try frameDiamondFunction()
    let blocks = AsyncFuncletIndex.trapGuardedRuns(safe.basicBlocks())
        + [BasicBlock(startAddress: 0x1100, instructions: [], successors: [0x1028])]
    let reachable = AsyncHardwareFrames.inputs(in: blocks, entry: 0x1000, isHeaderHelper: { _ in false })
    #expect(reachable[0x1028]?.contains("x29") == true)
    #expect(reachable[0x1100] == nil)
    var unknown: Set<String> = ["x19", "x29"]
    AsyncHardwareFrames.advance(&unknown, by: Instruction(address: 0x1000, text: "opaque", detail: nil),
                                isHeaderHelper: { _ in false })
    #expect(unknown.isEmpty)
}

@Test func asyncProvedHeaderFrameEffectsPreserveArgumentsAndReplaceLR() throws {
    for hints in [true, false] {
        for source in [1, 30] {
            let index = try frameAliasIndex(alias: 29, store: 0xf90007bf, hints: hints,
                                           betweenHeaderAndStore: [0xaa0003fd | UInt32(source << 16)],
                                           outlinedHeader: true, beforeHeader: [0x910003e1, 0x910003fe])
            // This complete helper preserves the native-stack pointer in x1;
            // BL replaces the same pointer in LR. x1 also forces the precise
            // helper transfer rather than the ordinary ABI call fallback.
            if source == 1 {
                #expect(index.chains[0x1000] == [0x1000, 0x2000])
                #expect(index.suspension(into: 0x2000) != nil)
            } else {
                #expect(index.funclets[0x2000]?.parent == nil)
                #expect(index.suspension(into: 0x2000) == nil)
            }
        }
    }
}

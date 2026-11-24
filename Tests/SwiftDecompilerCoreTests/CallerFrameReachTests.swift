import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A caller's frame slot was taken to survive any call that was passed no
/// address of it. A callee that stores above the sp it was entered with
/// writes that frame anyway. The emulator found two renders this made
/// false: `if (1)` on a slot the callee had rewritten, and
/// `return // x0 = 7` after a 64-byte `st4` across the caller's frame.
private func body(_ words: [UInt32]) throws -> [Instruction] {
    let engine = try #require(CapstoneEngine())
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let decoded = engine.disassemble(bytes, address: 0x1000)
    try #require(decoded.count == words.count)
    return decoded.map { Instruction(address: $0.address, text: $0.text,
        controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail) }
}

@Test(arguments: [
    // sub sp, #32; str x30, [sp, #16]; mov x9, #7; str x9, [sp, #96]; …
    ("a store above the frame", 72, [], [0xd10083ff, 0xf9000bfe, 0xd28000e9, 0xf90033e9, 0xf9400bfe, 0x910083ff, 0xd65f03c0]),
    // sub sp, #80; add x2, sp, #144; …
    ("an address above the frame", 0, [64], [0xd10143ff, 0x910243e2, 0x910143ff, 0xd65f03c0]),
    // sub sp, #16; add x0, sp, #8; st4 {v0.2d…v3.2d}, [x0]; …
    ("a wide store through an address inside the frame", 56, [], [0xd10043ff, 0x910023e0, 0x4c000c00, 0x910043ff, 0xd65f03c0]),
    // stp x29, x30, [sp, #-16]!; mov x29, sp; add x8, x29, #16; …
    ("an address above the frame record", 0, [0], [0xa9bf7bfd, 0x910003fd, 0x910043a8, 0xa8c17bfd, 0xd65f03c0]),
    // …; str x9, [x29, #16]; …
    ("a store above the frame record", 8, [], [0xa9bf7bfd, 0x910003fd, 0xf9000ba9, 0xa8c17bfd, 0xd65f03c0]),
    // sub sp, #32; add x8, sp, #8; mov x9, x8; add x10, x9, #24; …
    ("a copied address advanced to the entry sp", 0, [0], [0xd10083ff, 0x910023e8, 0xaa0803e9, 0x9100612a, 0x910083ff, 0xd65f03c0]),
    // sub sp, #64; add x0, sp, #0; stp q0, q1, [x0, #48]; …
    ("a pair of vectors ending above the frame", 16, [], [0xd10103ff, 0x910003e0, 0xad018400, 0x910103ff, 0xd65f03c0]),
    // sub sp, #64; add x1, sp, #8; cbz x0, 1f; add x1, sp, #56; 1: str x2, [x1, #8]; …
    ("the higher of two addresses that meet", 8, [], [0xd10103ff, 0x910023e1, 0xb4000040, 0x9100e3e1, 0xf9000422, 0x910103ff, 0xd65f03c0]),
    // sub sp, #64; cbz x0, 1f; add sp, sp, #48; 1: str x1, [sp, #24]; ret
    ("the shallower of two depths that meet", 16, [], [0xd10103ff, 0xb4000040, 0x9100c3ff, 0xf9000fe1, 0xd65f03c0]),
    // sub sp, #48; stp x29, x30, [sp, #32]; add x29, sp, #32; mov sp, x9; str x1, [sp, #40]; ret
    ("sp from a register, bounded only by the frame record", 32, [], [0xd100c3ff, 0xa9027bfd, 0x910083fd, 0x9100013f, 0xf90017e1, 0xd65f03c0]),
    // mov sp, x9; str x1, [sp]; ret
    ("sp from a register with no frame record", CallerFrameReach.unbounded, [], [0x9100013f, 0xf90003e1, 0xd65f03c0]),
    // sub sp, #32; br x8; str x1, [sp, #40]; add sp, #32; ret
    ("a store above the frame that only a register branch reaches", 16, [], [0xd10083ff, 0xd61f0100, 0xf90017e1, 0x910083ff, 0xd65f03c0]),
] as [(String, Int64, [Int64], [UInt32])])
func aBodyThatAddressesItsCallersFrameIsSeen(what: String, bytes: Int64, points: [Int64], words: [UInt32]) throws {
    let scan = CallerFrameReach.scan(try body(words))
    #expect(scan.own == bytes, Comment(rawValue: what))
    #expect(scan.points.sorted() == points, Comment(rawValue: what))
}

@Test(arguments: [
    // A frame record, a local's address stored through, a slot below x29,
    // and a load of a stack argument above it.
    ("an ordinary frame", [0xd100c3ff, 0xa9027bfd, 0x910083fd, 0x910023e0, 0xf9000001, 0xf81f83a2, 0xf9400ba3,
                           0xa9427bfd, 0x9100c3ff, 0xd65f03c0]),
    // stp x29, x30, [sp, #-16]!; mov x29, sp; sub sp, sp, x0; mov x1, sp; str x2, [sp]; mov sp, x29; …
    ("a dynamic allocation", [0xa9bf7bfd, 0x910003fd, 0xcb2063ff, 0x910003e1, 0xf90003e2, 0x910003bf, 0xa8c17bfd, 0xd65f03c0]),
    // sub sp, #32; cbz x0, 1f; add x1, sp, #16; str x2, [x1, #8]; 1: add sp, #32; ret
    ("a store on one path, inside the frame", [0xd10083ff, 0xb4000060, 0x910043e1, 0xf9000422, 0x910083ff, 0xd65f03c0]),
    // cmp sp, x0; mov x0, #0; ret
    ("a compare of sp", [0xeb2063ff, 0xd2800000, 0xd65f03c0]),
    // sub sp, #64; add x0, sp, #0; stp q0, q1, [x0, #32]; …
    ("a pair of vectors ending at the frame's top", [0xd10103ff, 0x910003e0, 0xad010400, 0x910103ff, 0xd65f03c0]),
    // sub sp, #32; str x30, [sp, #24]; add x0, sp, #8; bl …; str x1, [x0, #32]; …
    ("a store through a call's result", [0xd10083ff, 0xf9000ffe, 0x910023e0, 0x97fffffd, 0xf9001001, 0xf9400ffe, 0x910083ff, 0xd65f03c0]),
    // sub sp, #32; br x8; str x1, [sp, #16]; add sp, #32; ret
    ("a store inside the frame that only a register branch reaches", [0xd10083ff, 0xd61f0100, 0xf9000be1, 0x910083ff, 0xd65f03c0]),
    // sub sp, #32; str x1, [sp], #16; add sp, #16; ret
    ("a post-index store at sp", [0xd10083ff, 0xf80107e1, 0x910043ff, 0xd65f03c0]),
] as [(String, [UInt32])])
func aBodyThatStaysInItsFrameIsNotFlagged(what: String, words: [UInt32]) throws {
    let scan = CallerFrameReach.scan(try body(words))
    #expect(scan.own == 0 && scan.points.isEmpty, Comment(rawValue: what))
}

/// A callee's reach starts at its own entry sp, which is down this body's
/// frame by the depth of sp at the call. What is left above this body's
/// entry sp is the callee's reach less that depth, through any number of
/// calls. With no bound on the depth, or on the callee's reach, it is all.
@Test func theReachClosesOverCallsLessTheDepthAtEach() {
    func summary(own: Int64 = 0, points: [Int64] = [], calls: [(UInt64, Int64)] = []) -> CalleeRegisterSummary {
        var summary = CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [])
        summary.callerFrameReach = own
        summary.frameReachPoints = points
        summary.frameReachCalls = calls.map { CalleeRegisterSummary.FrameReachCall(target: $0.0, depth: $0.1) }
        return summary
    }
    var summaries: [UInt64: CalleeRegisterSummary] = [
        0x100: summary(calls: [(0x200, 32)]),          // 24 - 32: nothing left
        0x200: summary(calls: [(0x300, 16)]),          // 40 - 16
        0x300: summary(own: 40),
        0x400: summary(calls: [(0x500, 0)]),           // a callee that stays in its frame
        0x500: summary(),
        0x600: summary(calls: [(0x300, -1)]),          // no bound on the depth
        0x700: summary(calls: [(0x800, 64)]),          // no bound on the callee
        0x800: summary(own: CallerFrameReach.unbounded),
        0x900: summary(own: 8, calls: [(0x300, 16), (0x500, 0)]),   // the larger of its own and a callee's
        0xa00: summary(calls: [(0x300, 0)]),           // a tail branch at the entry sp
        0xb00: summary(points: [8, 48]),
        0xc00: summary(points: [0], calls: [(0xb00, 16)]),    // 8 is this body's own slot; 48 is 32 up
        0xd00: summary(calls: [(0xc00, 32)]),                 // 0 and 32 are its own; 32 - 32 is the entry sp
        0xe00: summary(calls: [(0xb00, -1)]),                 // no bound on the depth
    ]
    CalleeRegisterSummary.closeOverCallerFrameReach(&summaries)
    let all = CallerFrameReach.unbounded
    #expect(summaries.mapValues(\.callerFrameReach) == [
        0x100: 0, 0x200: 24, 0x300: 40, 0x400: 0, 0x500: 0, 0x600: all, 0x700: all, 0x800: all, 0x900: 24, 0xa00: 40,
        0xb00: 0, 0xc00: 0, 0xd00: 0, 0xe00: all,
    ])
    #expect(summaries.mapValues(\.frameReachPoints).filter { !$0.value.isEmpty } == [
        0xb00: [8, 48], 0xc00: [0, 32], 0xd00: [0],
    ])
}

/// A scan records each call out with the depth of sp at it, and the least
/// depth where one callee is called twice. A branch inside the body is no
/// call.
@Test func aScanRecordsTheDepthAtEachCall() throws {
    // sub sp, #48; cbz x0, 1f; bl 0x1044; 1: add sp, #16; bl 0x1044; add sp, #32; b 0x1094
    let scan = CallerFrameReach.scan(try body([
        0xd100c3ff, 0xb4000040, 0x9400000f, 0x910043ff, 0x9400000d, 0x910083ff, 0x1400001f,
    ]))
    #expect(scan.own == 0)
    #expect(scan.calls == [0x1044: .some(32), 0x1094: .some(0)])
}

/// A summary that gives up its other claims still says what its body
/// was seen to do to the caller's frame.
@Test func aSummaryClaimingNothingKeepsTheReach() {
    var summary = CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [])
    summary.callerFrameReach = 24
    summary.frameReachCalls = [CalleeRegisterSummary.FrameReachCall(target: 0x100, depth: 8)]
    summary.frameReachPoints = [16]
    let kept = summary.claimingNothing()
    #expect(kept.callerFrameReach == 24)
    #expect(kept.frameReachPoints == [16])
    #expect(kept.frameReachCalls == summary.frameReachCalls)
}

private func function(_ symbol: String, in image: String) async throws -> DisassembledFunction? {
    let path = "Fixtures/Sample/\(image)"
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    return try #require(functions.first { $0.symbol == symbol })
}

/// `entry_pointer_copy_body` makes `sp + 144` in an 80-byte frame and has
/// its helper store 99 there: the probe's `[sp, #64]`. The probe compares
/// that slot with 99 and takes the equal path. It rendered `if (1)`. The
/// slot escapes as one whose address was passed: the slot below it keeps
/// what the probe stored.
@Test(arguments: ["libCallerFrameAlias.dylib", "libCallerFrameAlias.opt.dylib", "libCallerFrameAlias.size.dylib"])
func aSlotACalleeReachedIsNotAConstantIfPresent(image: String) async throws {
    guard let probe = try await function("_entry_pointer_copy_probe", in: image) else { return }
    let conditions = probe.instructions.filter { $0.controlFlow == .conditionalBranch }.map(\.facts.condition)
    try #require(conditions.count == 4)
    // The second branch tests the slot the callee made an address of. The
    // third tests the slot below it, which no address above it reaches.
    #expect(!["0", "1"].contains(conditions[1] ?? ""), Comment(rawValue: probe.render()))
    #expect(conditions[2] == "0", Comment(rawValue: probe.render()))
}

/// The fragment's `st4` writes 64 bytes from 8 below its entry sp, over
/// the caller's slot that held 7. The machine returns 0x4444444444444444.
@Test func aSlotUnderAWideStoreIsNotTheResultIfPresent() async throws {
    guard let caller = try await function("_async_memory_st4", in: "libAsyncMemoryEffects.dylib") else { return }
    let ret = try #require(caller.instructions.last { $0.controlFlow == .return })
    #expect(ret.facts.exit != .unprovenResult("7"), Comment(rawValue: caller.render()))
    #expect(!caller.renderStructured().contains("x0 = 7"))
}

/// framereach.s: each probe stores 3 in a slot, calls, and returns the
/// slot. The direct callee stores 99 there from its entry sp, the wrapper's
/// callee from 16 bytes further down, and the control stays in its frame.
/// Every way in reaches the same answer: the whole image, a filter, the
/// streamed image and one function at a time.
@Test func aSlotIsKeptOnlyAcrossACalleeThatStaysInItsFrameIfPresent() async throws {
    let path = "Fixtures/Sample/libFrameReach.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    let listing = try await withStableDependencies { try await Disassembler(preset: .default).disassemble(path: path) }
    let filtered = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "_probe")
    }
    let streamed = await withStableDependencies {
        await Disassembler(preset: .default).disassembleStreaming(machO: image, transform: { $0 })
    }
    let each = await withStableDependencies {
        await Disassembler(preset: .default).analyzeEachFunction(at: Set(listing.map(\.startAddress)), in: image, transform: { $0 })
    }
    for (way, functions) in [("listing", listing), ("filtered", filtered), ("streamed", streamed), ("each", Array(each.values))] {
        for (symbol, kept) in [("_frame_reach_direct_probe", false), ("_frame_reach_through_probe", false),
                               ("_frame_reach_forward_probe", false), ("_frame_reach_clobber_probe", false),
                               ("_frame_reach_indexed_probe", false),
                               ("_frame_reach_control_probe", true)] {
            let probe = try #require(functions.first { $0.symbol == symbol }, "\(way): \(symbol)")
            let ret = try #require(probe.instructions.last { $0.controlFlow == .return })
            #expect((ret.facts.exit == .unprovenResult("3")) == kept, "\(way): \(probe.render())")
        }
    }
}

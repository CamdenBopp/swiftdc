import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The resume-pointer handoffs the async index proves, one shape each, as
/// optimized arm64e code lowers them. The context-slot rule recovered from the
/// pre-merge stash (only a resume stored into the ResumeParent of the context
/// passed in x22 counts) dropped all 610 resume links of the system
/// `libswift_Concurrency.dylib`. Each shape here is one reason it did, and HEAD
/// before the stash rule recovered most of them only by trusting any store,
/// with the suspension recorded at the arm's internal `b`.
///
/// The words are `Tests/…/AsyncHandoffShapeTests.s` below, assembled with
/// `xcrun clang -arch arm64e -c` and read back with `llvm-objdump -d`; they
/// decode at 0x10000.
///
///     s1: bl alloc; mov x8, x0; add x9, x0, #8; adr x16, r; mov x17, x9;
///         movk x17, #0xd707, lsl #48; pacia x16, x17; str x16, [x0, #8];
///         ldrb w4, [x22, #0x38]; str x1, [x29, #0x10]; mov x22, x8; autibsp;
///         eor x16, x30, x30, lsl #1; tbz x16, #62, 1f; brk #0xc471; 1: b callee
///     s2: cbz x20, 1f; adr x16, r1; paciza x16; b 2f; 1: adr x16, r2;
///         paciza x16; 2: mov x0, x16; b swift_task_switch
///     s3: bl alloc; mov x8, x0; mov x9, x22; tbz w24, #0, 1f; adr x17, ra;
///         pacia1716; stp x9, x17, [x8]; b 2f; 1: adr x17, rb; pacia1716;
///         stp x9, x17, [x8]; 2: mov x22, x8; b callee
///     s5: mov x20, x22; add x22, x22, #0x10; adr x16, r; str x16, [x20, #0x18];
///         mov x0, x22; mov w1, #1; bl swift_continuation_init;
///         b swift_continuation_await
///     s6: adr x16, r; paciza x16; mov x2, x16; add x3, x22, #0x10;
///         b swift_taskGroup_wait_next_throwing
///     s7: ldr x20, [x22, #0x40]; adr x16, r; str x16, [x20, #8];
///         str x1, [x29, #0x18]; mov x22, x20; b callee
///     s8: as s7, with `str xzr, [x9, #8]` for the frame store
///     s9: adr x16, r; str x16, [x22, #8]; b callee
///    s10: bl alloc; 1: adr x16, r; str x16, [x0, #8]; mov x22, x0; b 1b
///    s11: as s2, with `autibsp; eor x16, x30, x30, lsl #1; tbz x16, #62, 3f;
///         brk #0xc471; 3:` between the join's `mov x0, x16` and its `b`
private let shapeWords: [UInt32] = [
    0x94000011, 0xaa0003e8, 0x91002009, 0x100001b0, 0xaa0903f1, 0xf2fae0f1,
    0xdac10230, 0xf9000410, 0x3940e2c4, 0xf9000ba1, 0xaa0803f6, 0xd50323ff,
    0xca1e07d0, 0xb6f00050, 0xd4388e20, 0x14000003, 0xd65f03c0, 0xd65f03c0,
    0xd65f03c0, 0xb4000094, 0x100000f0, 0xdac123f0, 0x14000003, 0x100000b0,
    0xdac123f0, 0xaa1003e0, 0x14000003, 0xd65f03c0, 0xd65f03c0, 0xd65f03c0,
    0x9400000f, 0xaa0003e8, 0xaa1603e9, 0x360000b8, 0x10000131, 0xd503211f,
    0xa9004509, 0x14000004, 0x100000d1, 0xd503211f, 0xa9004509, 0xaa0803f6,
    0x14000004, 0xd65f03c0, 0xd65f03c0, 0xd65f03c0, 0xd65f03c0, 0xaa1603f4,
    0x910042d6, 0x100000d0, 0xf9000e90, 0xaa1603e0, 0x52800021, 0x94000003,
    0x14000003, 0xd65f03c0, 0xd65f03c0, 0xd65f03c0, 0x100000b0, 0xdac123f0,
    0xaa1003e2, 0x910042c3, 0x14000002, 0xd65f03c0, 0xd65f03c0, 0xf94022d4,
    0x100000b0, 0xf9000690, 0xf9000fa1, 0xaa1403f6, 0x14000002, 0xd65f03c0,
    0xd65f03c0, 0xf94022d4, 0x100000b0, 0xf9000690, 0xf900053f, 0xaa1403f6,
    0x14000002, 0xd65f03c0, 0xd65f03c0, 0x10000070, 0xf90006d0, 0x14000002,
    0xd65f03c0, 0xd65f03c0, 0x94000006, 0x10000090, 0xf9000410, 0xaa0003f6,
    0x17fffffd, 0xd65f03c0, 0xd65f03c0, 0xb4000094, 0x10000170, 0xdac123f0,
    0x14000003, 0x10000130, 0xdac123f0, 0xaa1003e0, 0xd50323ff, 0xca1e07d0,
    0xb6f00050, 0xd4388e20, 0x14000003, 0xd65f03c0, 0xd65f03c0, 0xd65f03c0,
]

private enum Shape {
    static let base: UInt64 = 0x10000
    static let s1 = base + 0x0, s1Resume = base + 0x40, s1Alloc = base + 0x44, s1Callee = base + 0x48
    static let s2 = base + 0x4c, s2R1 = base + 0x6c, s2R2 = base + 0x70, s2Switch = base + 0x74
    static let s3 = base + 0x78, s3Ra = base + 0xac, s3Rb = base + 0xb0, s3Alloc = base + 0xb4
    static let s3Callee = base + 0xb8
    static let s5 = base + 0xbc, s5Resume = base + 0xdc, s5Init = base + 0xe0, s5Await = base + 0xe4
    static let s6 = base + 0xe8, s6Resume = base + 0xfc, s6Wait = base + 0x100
    static let s7 = base + 0x104, s7Resume = base + 0x11c, s7Callee = base + 0x120
    static let s8 = base + 0x124, s8Resume = base + 0x13c, s8Callee = base + 0x140
    static let s9 = base + 0x144, s9Resume = base + 0x150, s9Callee = base + 0x154
    static let s10 = base + 0x158, s10Resume = base + 0x16c, s10Alloc = base + 0x170
    static let s11 = base + 0x174, s11R1 = base + 0x1a4, s11R2 = base + 0x1a8, s11Switch = base + 0x1ac

    static let names: [UInt64: String] = [
        s1Alloc: "swift_task_alloc", s1Callee: "m.f() async -> Swift.Int",
        s2Switch: "swift_task_switch",
        s3Alloc: "swift_task_alloc", s3Callee: "m.g() async -> Swift.Int",
        s5Init: "swift_continuation_init", s5Await: "swift_continuation_await",
        s6Wait: "swift_taskGroup_wait_next_throwing",
        s7Callee: "m.h() async -> Swift.Int", s8Callee: "m.h() async -> Swift.Int",
        s9Callee: "m.h() async -> Swift.Int", s10Alloc: "swift_task_alloc",
        s11Switch: "swift_task_switch",
    ]
    static let starts: [UInt64] = [
        s1, s1Resume, s1Alloc, s1Callee, s2, s2R1, s2R2, s2Switch, s3, s3Ra, s3Rb, s3Alloc, s3Callee,
        s5, s5Resume, s5Init, s5Await, s6, s6Resume, s6Wait, s7, s7Resume, s7Callee,
        s8, s8Resume, s8Callee, s9, s9Resume, s9Callee, s10, s10Resume, s10Alloc,
        s11, s11R1, s11R2, s11Switch,
    ]

    static func index(entries: [UInt64], awaitReturns: [UInt64] = [], continuations: [UInt64] = []) throws
        -> AsyncFuncletIndex
    {
        let engine = try #require(CapstoneEngine())
        let bytes = shapeWords.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: base)
        #expect(decoded.count == shapeWords.count)
        let all = decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let sortedStarts = starts.sorted()
        return AsyncFuncletIndex.build(
            hints: .init(entries: entries, awaitReturns: awaitReturns, continuations: continuations),
            functionStarts: Set(starts),
            instructions: { start in
                let end = sortedStarts.first { $0 > start } ?? UInt64.max
                return all.filter { $0.address >= start && $0.address < end }
            },
            nameOf: { names[$0] })
    }
}

/// arm64e signs the resume pointer in place (`pacia x16, x17`) before storing
/// it; the tail call sits behind the return-address check (`tbz; brk`); a byte
/// load and a frame store between the store and the call write no context.
@Test func asyncSignedResumeBehindReturnAddressCheckIsHandedOver() throws {
    let index = try Shape.index(entries: [Shape.s1], awaitReturns: [Shape.s1Resume])
    #expect(index.funclets[Shape.s1Resume]?.parent == Shape.s1)
    #expect(index.funclets[Shape.s1Resume]?.predecessor == Shape.s1)
    let site = try #require(index.suspension(into: Shape.s1Resume))
    #expect(site.address == Shape.s1Resume - 4)
    #expect(site.suspension.callee == Shape.s1Callee)
    #expect(Disassembler.awaitedResultRegister(into: Shape.s1Resume, index: index) == "x0")
}

/// Each arm of a diamond builds a different resume pointer; the join hands
/// x16 to `swift_task_switch`. Both are continuations of the entry, and the
/// arm's `b` to the join is not a suspension.
@Test func asyncHopAfterDiamondResumesIntoEitherArm() throws {
    let index = try Shape.index(entries: [Shape.s2], continuations: [Shape.s2R1, Shape.s2R2])
    for resume in [Shape.s2R1, Shape.s2R2] {
        #expect(index.funclets[resume]?.parent == Shape.s2)
        #expect(index.funclets[resume]?.kind == .continuation)
    }
    #expect(index.suspensions[Shape.s2R1 - 4]?.isExecutorHop == true)
    #expect(index.suspensions[Shape.s2 + 0xc] == nil, "the arm's internal `b` is not a suspension")
}

/// The context is allocated before the fork; each arm stores its own resume
/// (`pacia1716` signs x17 in place) and both leave through one tail call.
/// Ownership holds, but the shared call is no one await: no record, no result.
@Test func asyncSharedTailCallOwnsBothArmsButRecordsNoAwait() throws {
    let index = try Shape.index(entries: [Shape.s3], awaitReturns: [Shape.s3Ra, Shape.s3Rb])
    for resume in [Shape.s3Ra, Shape.s3Rb] {
        #expect(index.funclets[resume]?.parent == Shape.s3)
        #expect(index.funclets[resume]?.kind == .awaitReturn)
        #expect(index.suspension(into: resume) == nil)
        #expect(Disassembler.awaitedResultRegister(into: resume, index: index) == nil)
    }
    #expect(index.suspensions[Shape.s3Ra - 4] == nil)
}

/// `withUnsafeContinuation`: the continuation context lives inside the own
/// context, its ResumeParent is written through an alias, and the handoff is
/// `swift_continuation_init`. The await is elsewhere, so no record here.
@Test func asyncContinuationInitHandsOverTheContextResumeParent() throws {
    let index = try Shape.index(entries: [Shape.s5], awaitReturns: [Shape.s5Resume])
    #expect(index.funclets[Shape.s5Resume]?.parent == Shape.s5)
    #expect(index.suspension(into: Shape.s5Resume) == nil)
}

/// `swift_taskGroup_wait_next_throwing` takes the resume function in x2 and
/// resumes in the caller's own context.
@Test func asyncRuntimeWaitHandsOverItsResumeArgument() throws {
    let index = try Shape.index(entries: [Shape.s6], continuations: [Shape.s6Resume])
    #expect(index.funclets[Shape.s6Resume]?.parent == Shape.s6)
    #expect(index.funclets[Shape.s6Resume]?.kind == .continuation)
    let info = index.info(for: Shape.s6Resume, parentName: { _ in nil })
    #expect(info?.resumedBy == "swift_taskGroup_wait_next_throwing")
}

/// A pointer loaded from a slot is not proven a context: storing a resume at
/// its +8 and passing it in x22 declines, as the stash's
/// `asyncArbitraryMemoryStoreIsNotContextHandoff` requires. No real shape in
/// libswift_Concurrency needs more: its saved contexts are allocated on the
/// same path (`AsyncStream._Storage.next()`'s x20 is `swift_task_alloc`'s).
@Test func asyncLoadedPointerIsNotAProvenContext() throws {
    for (entry, resume) in [(Shape.s7, Shape.s7Resume), (Shape.s8, Shape.s8Resume)] {
        let index = try Shape.index(entries: [entry], awaitReturns: [resume])
        #expect(index.funclets[resume]?.parent == nil)
    }
}

/// The own context's ResumeParent is where this function returns, not a
/// callee's continuation.
@Test func asyncOwnResumeParentIsNotAHandoff() throws {
    let index = try Shape.index(entries: [Shape.s9], awaitReturns: [Shape.s9Resume])
    #expect(index.funclets[Shape.s9Resume]?.parent == nil)
}

/// A path ends at a loop back-edge with the resume already in the context x22
/// holds. The `b` stays inside the function, so it suspends nothing.
@Test func asyncInternalBranchIsNotASuspension() throws {
    let index = try Shape.index(entries: [Shape.s10], awaitReturns: [Shape.s10Resume])
    #expect(index.funclets[Shape.s10Resume]?.parent == nil)
    #expect(index.suspensions.isEmpty)
}

/// The diamond again, with the return-address check between the join and its
/// hop, as libswift_Concurrency's `AsyncCompactMapSequence.Iterator.next()`
/// resume #1 has it. The join has two ways in, so only folding the check away
/// lets the arm's path reach the `b`; without it 255 of that dylib's resume
/// funclets were orphaned.
@Test func asyncHopAfterDiamondCrossesTheReturnAddressCheck() throws {
    let index = try Shape.index(entries: [Shape.s11], continuations: [Shape.s11R1, Shape.s11R2])
    for resume in [Shape.s11R1, Shape.s11R2] {
        #expect(index.funclets[resume]?.parent == Shape.s11)
        #expect(index.funclets[resume]?.kind == .continuation)
    }
    #expect(index.suspensions[Shape.s11R1 - 4]?.isExecutorHop == true)
}

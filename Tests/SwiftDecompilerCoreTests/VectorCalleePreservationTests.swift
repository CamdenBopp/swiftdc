import Ccapstone
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif
@testable import SwiftDecompilerCore

private func vectorPreservationBody(_ words: [UInt32], at address: UInt64 = 0x1000) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: address)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "_vectorPreservation", demangledName: nil,
        startAddress: address, instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
}

private func vectorPreservationSummary(_ name: String) throws -> CalleeRegisterSummary {
    let words = try #require(vectorPreservationShapes[name])
    return try #require(CalleeRegisterSummary.of(try vectorPreservationBody(words)))
}

@Test func vectorCalleeSummariesDetectLowLaneClobbersAtEveryWidth() throws {
    // Independently assembled FMOV Dn,#1, FMOV Sn,#1, MOVI Vn.2D,#0.
    for register in 8...15 {
        for opcode: UInt32 in [0x1e6e1000, 0x1e2e1000, 0x6f00e400] {
            let function = try vectorPreservationBody([opcode | UInt32(register), 0xd65f03c0])
            let summary = try #require(CalleeRegisterSummary.of(function))
            #expect(summary.clobberedCalleeSaved == ["v\(register)"])
            #expect(summary.definitelyClobbered == ["v\(register)"])
        }
    }
}

@Test func vectorCalleeSummariesDeclineUnmodeledOverlappingRegisters() throws {
    let all = Set((8...15).map { "v\($0)" })
    // clang -march=armv8-a+sve: MOV Z8.D,#0 and LDR Z8,[SP]. Z8
    // overlaps V8, but PhysReg deliberately does not map SVE/SME registers.
    // The preservation analysis must conservatively forget the whole bank,
    // including a load that otherwise takes the modeled load fast path.
    for opcode: UInt32 in [0x25f8c008, 0x858043e8] {
        let callee = try vectorPreservationBody([opcode, 0xd65f03c0], at: 0x2000)
        #expect(callee.instructions.first?.detail?.operands.first?.operand.register?.kind == .other)
        let summary = try #require(CalleeRegisterSummary.of(callee))
        #expect(summary.clobberedCalleeSaved == all)
        #expect(summary.definitelyClobbered == all)
        let wrapper = try vectorPreservationBody([0x94000400, 0xd65f03c0])
        #expect(try #require(CalleeRegisterSummary.of(wrapper, calleeEffects: { _ in summary.effect }))
            .clobberedCalleeSaved == all)
    }
    // A saved low lane copied into d0 is also lost when an overlapping Z0
    // write occurs. Copying it back cannot establish preservation of d8.
    let copied = try vectorPreservationBody([0x1e604100, 0x25f8c000, 0x1e604008, 0xd65f03c0])
    #expect(try #require(CalleeRegisterSummary.of(copied)).clobberedCalleeSaved == all)
}

@Test func vectorCalleeUpperLaneInsertsKeepLowWordsAndFrameAliases() throws {
    // Independently assembled INS/MOV D[1], FMOV D[1], S[2]/S[3], H[4], B[8].
    for opcode: UInt32 in [0x4e181d28, 0x9eaf0128, 0x4e141d28, 0x4e1c1d28, 0x4e121d28, 0x4e111d28] {
        let function = try vectorPreservationBody([opcode, 0xd65f03c0])
        #expect(try #require(CalleeRegisterSummary.of(function)).clobberedCalleeSaved.isEmpty)
    }
    for opcode: UInt32 in [0x4e081d28, 0x4e0c1d28] { // D[0] and S[1] touch the low word.
        #expect(try #require(CalleeRegisterSummary.of(try vectorPreservationBody([opcode, 0xd65f03c0])))
            .clobberedCalleeSaved == ["v8"])
    }
    // Missing arrangements or indices outside the real register cannot
    // establish an upper-only write, even when the opcode text says INS.
    let decoded = try vectorPreservationBody([0x4e181d28, 0xd65f03c0])
    let original = try #require(decoded.instructions[0].detail)
    for (index, layout) in [(1, AARCH64LAYOUT_INVALID), (-1, AARCH64LAYOUT_VL_D), (2, AARCH64LAYOUT_VL_D)] {
        var operands = original.operands
        operands[0].vectorIndex = index
        operands[0].vectorArrangement = layout
        let detail = StructuredInsn(id: original.id, conditionCode: original.conditionCode,
            updatesFlags: false, writeback: false, postIndex: false, operands: operands)
        let function = DisassembledFunction(symbol: "_invalidLane", demangledName: nil,
            startAddress: decoded.startAddress,
            instructions: [Instruction(address: 0x1000, text: "mov v8.d[1],x9", detail: detail), decoded.instructions[1]],
            source: .symbol)
        #expect(try #require(CalleeRegisterSummary.of(function)).clobberedCalleeSaved == ["v8"])
    }
    // d8's low value survives in d0 despite a change to v0.d[1].
    let copy = try vectorPreservationBody([0x1e604100, 0x4e181d20, 0x1e604008, 0xd65f03c0])
    #expect(try #require(CalleeRegisterSummary.of(copy)).clobberedCalleeSaved.isEmpty)
    for insert: UInt32 in [0x4e181c08, 0x9eaf0008] { // mov/fmov v8.d[1],x0
        let alias = try vectorPreservationBody([
            0xf81f0ff3, 0xaa0103f3, 0x910003e0, insert, 0xaa1f03e0,
            0x94000400, 0xf84107f3, 0xd65f03c0,
        ])
        let summary = try #require(CalleeRegisterSummary.of(alias))
        #expect(summary.clobberedCalleeSaved.contains("x19"))
        #expect(!summary.clobberedCalleeSaved.contains("v8"))
        // The low pointer reaches a local below the save, while the high
        // pointer reaches the save itself. Neither may hide the other.
        let twoPointers = try vectorPreservationBody([
            0xf81f0ff3, 0xaa0103f3, 0xd10043e0, 0x9e670008,
            0x910003e0, insert, 0xaa1f03e0, 0x94000400, 0xf84107f3, 0xd65f03c0,
        ])
        #expect(try #require(CalleeRegisterSummary.of(twoPointers)).clobberedCalleeSaved.contains("x19"))
    }
    // Preserve the already-proved frame MAY-alias behavior too.
    do {
        // A frame address passed to an unknown in-image fragment through d0
        // remains an alias. Losing it at FMOV would falsely prove x19's save intact.
        for unmodeledWrite: [UInt32] in [[], [0x25f8c008]] {
            // MOV Z8.D,#0 leaves D0 intact. Forgetting vector values must not
            // also forget that D0 can carry this escaped frame address.
            let function = try vectorPreservationBody([
                0xf81f0ff3, 0xaa0103f3, 0x910003e0, 0x9e670000, 0xaa1f03e0,
            ] + unmodeledWrite + [0x94000400, 0xf84107f3, 0xd65f03c0])
            // str x19; mov x19,x1; mov x0,sp; fmov d0,x0; clear x0; [SVE]; call; reload; ret
            #expect(try #require(CalleeRegisterSummary.of(function)).clobberedCalleeSaved.contains("x19"))
        }
    }
}

@Test func vectorCalleeSummariesProveFullWidthSavesAndRejectPartialRestores() throws {
    for name in ["saveD8", "saveQ8", "saveDPair", "saveQPair", "upperOnlyOverwrite", "wideCopy"] {
        #expect(try vectorPreservationSummary(name).clobberedCalleeSaved.isEmpty, Comment(rawValue: name))
    }
    for name in ["partialSave", "overlapSave", "lowOverwrite"] {
        #expect(try vectorPreservationSummary(name).clobberedCalleeSaved == ["v8"], Comment(rawValue: name))
    }
    #expect(try vectorPreservationSummary("swapReload").clobberedCalleeSaved == ["v8", "v9"])
}

@Test func vectorPreservationCopiesRespectTheCalleeSavedBank() throws {
    #expect(try vectorPreservationSummary("callerSavedCopy").clobberedCalleeSaved == ["v8"])
    #expect(try vectorPreservationSummary("wideCopyCall").clobberedCalleeSaved == ["v8"])
    // d9 survives the call and restores d8, but d9 itself is not restored.
    #expect(try vectorPreservationSummary("calleeSavedCopy").clobberedCalleeSaved == ["v9"])
    for temporary in Array(0...7) + Array(16...31) {
        // fmov dTmp,d8; call; fmov d8,dTmp. Every caller-saved vector must
        // lose the saved low-lane provenance, not just the return register.
        let function = try vectorPreservationBody([
            0x1e604100 | UInt32(temporary), 0x94000400,
            0x1e604008 | UInt32(temporary << 5), 0xd65f03c0,
        ])
        #expect(try #require(CalleeRegisterSummary.of(function)).clobberedCalleeSaved == ["v8"])
    }
}

@Test func vectorCalleeReloadEffectsUseLowLanesAndCorrectPairOffsets() throws {
    let single = try vectorPreservationSummary("reloadCaller")
    #expect(single.restoredFrom == ["v8": 16])
    let pair = try vectorPreservationSummary("reloadCallerPair")
    #expect(pair.restoredFrom == ["v8": 16, "v9": 32])
    let epilogue = try #require(CalleeRegisterSummary.of(try vectorPreservationBody(
        [0xfc4107e8, 0xd65f03c0], at: 0x2000))) // ldr d8,[sp],#16; ret
    // str d8,[sp,#-16]!; fmov d8,#1; b 0x2000
    let caller = try vectorPreservationBody([0xfc1f0fe8, 0x1e6e1008, 0x140003fe])
    let restored = try #require(CalleeRegisterSummary.of(caller, calleeEffects: { _ in epilogue.effect }))
    #expect(restored.clobberedCalleeSaved.isEmpty)
}

@Test func vectorCalleeClobbersCloseOverNestedCalls() throws {
    let caller = try vectorPreservationBody([0x94000400, 0xd65f03c0])
    let leaf = try vectorPreservationBody([0x1e6e1008, 0xd65f03c0], at: 0x2000)
    let functions = [caller.startAddress: caller, leaf.startAddress: leaf]
    var summaries = try functions.mapValues { try #require(CalleeRegisterSummary.of($0)) }
    CalleeRegisterSummary.closeOverCalls(&summaries) { address, effect, _, _ in
        functions[address].flatMap { CalleeRegisterSummary.of($0, calleeEffects: effect) }
    }
    #expect(summaries[0x1000]?.clobberedCalleeSaved == ["v8"])
    #expect(summaries[0x1000]?.definitelyClobbered == ["v8"])
}

@Test func vectorSavedButUnrestoredClobbersStillPropagate() throws {
    for store: UInt32 in [0xbc1f0fe8, 0xfc1f0fe8] { // str s8 / str d8,[sp,#-16]!
        let caller = try vectorPreservationBody([0x94000400, 0xd65f03c0])
        let leaf = try vectorPreservationBody([store, 0x1e6e1008, 0x910043ff, 0xd65f03c0], at: 0x2000)
        let functions = [caller.startAddress: caller, leaf.startAddress: leaf]
        var summaries = try functions.mapValues { try #require(CalleeRegisterSummary.of($0)) }
        CalleeRegisterSummary.closeOverCalls(&summaries) { address, effect, _, _ in
            functions[address].flatMap { CalleeRegisterSummary.of($0, calleeEffects: effect) }
        }
        #expect(summaries[0x2000]?.definitelyClobbered.contains("v8") == true)
        #expect(summaries[0x1000]?.clobberedCalleeSaved.contains("v8") == true)
    }
}


@Test func compilerOutlinedVectorThunksAndEpiloguesHaveRealEffects() throws {
    // clang 21's default -Oz lowering of outlinedvectors.c emits each move
    // followed by an external tail branch. Relocate that branch out of this
    // synthetic body; the MOV and epilogue words are compiler-generated.
    for register in [8, 9, 10] {
        let thunk = try vectorPreservationBody([0x4ea01c00 | UInt32(register), 0x14000400])
        #expect(try #require(CalleeRegisterSummary.of(thunk)).definitelyClobbered == ["v\(register)"])
    }
    let epilogue = try vectorPreservationBody([0x6d4123e9, 0x6cc32beb, 0xd65f03c0])
    #expect(try #require(CalleeRegisterSummary.of(epilogue)).restoredFrom
            == ["v9": 16, "v8": 24, "v11": 0, "v10": 8])
}

@Test func aVectorClobberingFragmentCannotReturnTheCallersStaleLowLane() throws {
    let callee = try #require(CalleeRegisterSummary.of(try vectorPreservationBody(
        [0x1e6e1008, 0xd65f03c0], at: 0x2000)))
    // fmov d8,#2; bl 0x2000; fmov d0,d8; ret
    let caller = try vectorPreservationBody([0x1e601008, 0x940003ff, 0x1e604100, 0xd65f03c0])
    let blind = ValueTracer().analyze(caller, entry: nil)
    #expect(blind.exitFloatValues[0x100c] == .immediate(Double(2).bitPattern))
    var tracer = ValueTracer()
    tracer.calleeClobbers[0x2000] = callee.clobberedCalleeSaved
    #expect(tracer.analyze(caller, entry: nil).exitFloatValues[0x100c] == nil)
}

// clang arm64-apple-macosx15.0 machine encodings for D/Q saves, narrow and
// overlapping writes, register copies, and outlined epilogue reloads.
private let vectorPreservationShapes: [String: [UInt32]] = [
    "clobberS9": [0x1e2e1009, 0xd65f03c0],
    "clobberQ15": [0x6f00e40f, 0xd65f03c0],
    "saveD8": [0xfc1f0fe8, 0x1e6e1008, 0xfc4107e8, 0xd65f03c0],
    "saveQ8": [0x3c9f0fe8, 0x1e6e1008, 0x3cc107e8, 0xd65f03c0],
    "saveDPair": [0x6dbf27e8, 0x1e6e1008, 0x1e6e1009, 0x6cc127e8, 0xd65f03c0],
    "saveQPair": [0xadbf27e8, 0x1e6e1008, 0x1e6e1009, 0xacc127e8, 0xd65f03c0],
    "partialSave": [0xbc1f0fe8, 0x1e6e1008, 0xbc4107e8, 0xd65f03c0],
    "overlapSave": [0xfc1f0fe8, 0x39001fe0, 0x1e6e1008, 0xfc4107e8, 0xd65f03c0],
    "callerSavedCopy": [0x1e604100, 0x94000400, 0x1e604008, 0xd65f03c0],
    "calleeSavedCopy": [0x1e604109, 0x94000400, 0x1e604128, 0xd65f03c0],
    "wideCopy": [0x4ea81d00, 0x6f00e408, 0x4ea01c08, 0xd65f03c0],
    "wideCopyCall": [0x4ea81d00, 0x94000400, 0x4ea01c08, 0xd65f03c0],
    "swapReload": [0x6dbf27e8, 0x6cc123e9, 0xd65f03c0],
    "upperOnlyOverwrite": [0x3c9f0fe8, 0xf90007e0, 0x3cc107e8, 0xd65f03c0],
    "lowOverwrite": [0x3c9f0fe8, 0xf90003e0, 0x3cc107e8, 0xd65f03c0],
    "reloadCaller": [0xfd400be8, 0xd65f03c0],
    "reloadCallerPair": [0xad40a7e8, 0xd65f03c0],
]

@Test func vectorRestoresComposeAcrossMultipleTailTransfers() throws {
    let caller = try vectorPreservationBody([0xfc1f0fe8, 0x940003ff, 0x910043ff, 0xd65f03c0])
    let overwrite = try vectorPreservationBody([0x1e6e1008, 0x140007ff], at: 0x2000)
    let relay = try vectorPreservationBody([0x14000400], at: 0x4000)
    let reload = try vectorPreservationBody([0xfd4003e8, 0xd65f03c0], at: 0x5000)
    let functions = Dictionary(uniqueKeysWithValues: [caller, overwrite, relay, reload].map { ($0.startAddress, $0) })
    var summaries = try functions.mapValues { try #require(CalleeRegisterSummary.of($0)) }
    #expect(summaries[0x2000]?.definitelyClobbered == ["v8"])
    CalleeRegisterSummary.closeOverCalls(&summaries) { address, effects, _, _ in
        functions[address].flatMap { CalleeRegisterSummary.of($0, calleeEffects: effects) }
    }
    #expect(summaries[0x4000]?.restoredFrom == ["v8": 0])
    #expect(summaries[0x2000]?.restoredFrom == ["v8": 0])
    #expect(summaries[0x1000]?.clobberedCalleeSaved.isEmpty == true)
}

@Test func unfinishedVectorClosuresInvalidateTheWholePreservedBank() {
    let all = Set((19...29).map { "x\($0)" } + (8...15).map { "v\($0)" })
    let graph: [UInt64: CalleeRegisterSummary] = [
        0x10: CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: ["v8"], definitelyClobbered: ["v8"]),
        0x20: CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [], callees: [0x10]),
        0x30: CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [], callees: [0x20]),
        0x40: CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [], callees: [0x30]),
    ]
    func rebuild(_ address: UInt64, _ effects: (UInt64) -> CalleeEffect) -> CalleeRegisterSummary {
        let callees = graph[address]?.callees ?? []
        let clobbers = callees.reduce(into: Set<String>()) { $0.formUnion(effects($1).clobbers) }
        return CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: clobbers,
            definitelyClobbered: clobbers, callees: callees)
    }
    var capped = graph
    CalleeRegisterSummary.closeOverCalls(&capped, cap: 1) { address, effects, _, _ in rebuild(address, effects) }
    #expect(capped[0x30]?.clobberedCalleeSaved == all)
    #expect(capped[0x40]?.definitelyClobbered == all)
    var failed = graph
    CalleeRegisterSummary.closeOverCalls(&failed) { address, effects, _, _ in
        address == 0x20 ? nil : rebuild(address, effects)
    }
    #expect(failed[0x20]?.clobberedCalleeSaved == all)
    #expect(failed[0x40]?.definitelyClobbered == all)
}

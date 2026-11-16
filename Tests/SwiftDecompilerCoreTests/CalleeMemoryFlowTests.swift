import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The helper and caller words have a separate assembler/LLVM oracle. These
/// controls exercise consumers, including the full unknown-effect fallback.
struct CalleeMemoryFlowTests {
    private static func body(_ words: [UInt32], at address: UInt64 = 0x1000) throws -> DisassembledFunction {
        let engine = try #require(CapstoneEngine())
        let bytes = words.flatMap { word in
            (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) }
        }
        let decoded = engine.disassemble(Data(bytes), address: address)
        try #require(decoded.count == words.count)
        return DisassembledFunction(symbol: "_callee_memory_flow", demangledName: nil,
            startAddress: address, instructions: decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
            }, source: .address)
    }

    private static func effect(_ store: UInt32 = 0xf9000009) throws -> CalleeMemoryEffect {
        CalleeMemoryEffect.discover(in: try body([0xd2800169, store, 0xd65f03c0], at: 0x2000))
    }

    @Test func theTracerAppliesKnownWritesAndKeepsDisjointWords() throws {
        // sub sp,sp,#32; mov x9,#7; str x9,[sp,#8/16]; add x0,sp,#8
        // bl 0x2000; ldr x0,[sp,#8/16]; add sp,sp,#32; ret
        for (store, load, expected): (UInt32, UInt32, UInt64) in [
            (0xf90007e9, 0xf94007e0, 11), (0xf9000be9, 0xf9400be0, 7),
        ] {
            let caller = try Self.body([0xd10083ff, 0xd28000e9, store, 0x910023e0,
                0x940003fc, load, 0x910083ff, 0xd65f03c0])
            var tracer = ValueTracer()
            tracer.calleeMemoryEffects[0x2000] = try Self.effect()
            #expect(tracer.analyze(caller).exitValues[0x101c] == .immediate(expected))
            #expect((ValueTracer().analyze(caller).exitValues[0x101c] ?? .unknown) == .unknown)
            // One unplaced input invalidates the entire plan, rather than
            // applying the first store and overlooking the unknown second.
            tracer.calleeMemoryEffects[0x2000] = CalleeMemoryEffect.discover(in: try Self.body([
                0xd2800169, 0xf9000009, 0xf9000029, 0xd65f03c0,
            ], at: 0x2000))
            #expect((tracer.analyze(caller).exitValues[0x101c] ?? .unknown) == .unknown)
        }
    }

    @Test func aNonstandardInputRemainsEscapedForALaterUnknownCall() throws {
        // x19 is outside the default argument register set. The proven body
        // uses it, so its frame origin must still feed the durable escape.
        // sub sp,sp,#32; mov x9,#7; str x9,[sp,#16]; add x19,sp,#8
        // bl 0x2000; mov x0,xzr; bl 0x3000; ldr x0,[sp,#16]; add sp,sp,#32; ret
        let words: [UInt32] = [0xd10083ff, 0xd28000e9, 0xf9000be9, 0x910023f3,
            0x940003fc, 0xaa1f03e0, 0x940007fa, 0xf9400be0, 0x910083ff, 0xd65f03c0]
        var tracer = ValueTracer()
        tracer.calleeMemoryEffects[0x2000] = try Self.effect(0xf9000269) // str x9,[x19]
        #expect((tracer.analyze(try Self.body(words)).exitValues[0x1024] ?? .unknown) == .unknown)
        var noLaterCall = words
        noLaterCall[6] = 0xaa1f03e0
        #expect(tracer.analyze(try Self.body(noLaterCall)).exitValues[0x1024] == .immediate(7))
    }

    @Test func preservationInvalidatesOnlyWrittenSavesAndChecksIncomingMemory() throws {
        let initial = Preservation.State(registers: ["sp": .stack(-64), "x0": .stack(-56)],
            slots: [-56: .entry("x19"), -48: .entry("x20"), -8: .entry("x29")],
            stackAliases: ["sp", "x0"])
        var known = initial
        let effect = CalleeEffect(memoryEffect: try Self.effect())
        #expect(Preservation.applyCall(effect, inputs: ["x0"], to: &known, clobbersMayAliasStack: false) != nil)
        #expect(known.load(at: -56) == .unknown)
        #expect(known.load(at: -48) == .entry("x20"))
        #expect(known.load(at: -8) == .entry("x29"))
        #expect(known.incomingIntact)
        var unknown = initial
        Preservation.applyCall(CalleeEffect(), inputs: ["x0"], to: &unknown, clobbersMayAliasStack: false)
        #expect(unknown.load(at: -48) == .unknown)
        #expect(unknown.load(at: -8) == .unknown)
        #expect(!unknown.incomingIntact)
        var positive = initial
        positive.setRegister("x0", to: .stack(0))
        Preservation.applyCall(effect, inputs: ["x0"], to: &positive, clobbersMayAliasStack: false)
        #expect(!positive.incomingIntact)
        // Checked preservation overlap cannot retain a malformed word whose
        // end overflows, even when the known write itself has a valid extent.
        var overflow = Preservation.State(registers: ["sp": .stack(-64), "x0": .stack(-56)],
            slots: [.max - 3: .entry("x19")])
        Preservation.applyCall(effect, inputs: ["x0"], to: &overflow, clobbersMayAliasStack: false)
        #expect(overflow.slots[.max - 3] == nil)
    }

    @Test func selfReadsDistinguishWholePartialAndUnknownCalleeWrites() throws {
        // Spill self and end its register membership. The helper can write
        // the slot but cannot read it. Reloading after a byte store still
        // carries MAY-self; a complete word replacement ends that presence.
        for (store, load, expected): (UInt32, UInt32, Bool) in [
            (0xf9000009, 0xf94007e0, false), // full word, then reload
            (0x39000009, 0xf94007e0, true),  // byte, then reload
            (0x39000009, 0xaa1f03e0, false), // byte, no reload
        ] {
            let caller = try Self.body([0xd10083ff, 0xf90007f4, 0xaa1f03f4, 0x910023e0,
                0x940003fc, load, 0x910083ff, 0xd65f03c0])
            func flow(_ effect: CalleeMemoryEffect) throws -> Preservation.SelfRegisterFlow {
                try #require(Preservation.selfRegisterFlow(blocks: caller.basicBlocks(), entry: caller.startAddress,
                    addresses: Set(caller.instructions.map(\.address)),
                    callEffect: { _ in CalleeEffect(memoryEffect: effect) },
                    callInputs: { _ in ["x0"] }, forwards: { _ in false }))
            }
            #expect(try flow(Self.effect(store)).reads == expected)
            #expect(try flow(.unknown).reads)
        }
    }

    @Test func immutableBodyMemoryFactsSurviveEachSummaryRebuilder() throws {
        let helper = try Self.body([0xd2800169, 0xf9000009, 0xd65f03c0], at: 0x2000)
        let summary = try #require(CalleeRegisterSummary.of(helper))
        let memory = try Self.effect()
        #expect(summary.memoryEffect == memory)
        #expect(summary.effect.memoryEffect == memory)
        let rebuilt = try #require(CalleeRegisterSummary.recomputingPreservation(helper,
            retainingReadsFrom: summary, calleeEffects: { _ in CalleeEffect() }))
        #expect(rebuilt.memoryEffect == memory)
        var pending = summary
        pending.pendingReads = [.init(target: 0x3000, unwritten: 0xff)]
        var summaries: [UInt64: CalleeRegisterSummary] = [0x2000: pending,
            0x3000: .init(argumentReads: [7], clobberedCalleeSaved: ["x19"], definitelyClobbered: ["x19"])]
        CalleeRegisterSummary.closeOverReads(&summaries)
        #expect(summaries[0x2000]?.argumentReads.contains(7) == true)
        #expect(summaries[0x2000]?.memoryEffect == memory)
        // Force the independent clobber rebuilder. Its synthetic replacement
        // lacks the immutable fact, which must be retained from the old body.
        summaries[0x2000]?.callees = [0x3000]
        CalleeRegisterSummary.closeOverCalls(&summaries) { _, _, _, _ in
            CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: ["x19"], definitelyClobbered: ["x19"])
        }
        #expect(summaries[0x2000]?.clobberedCalleeSaved == ["x19"])
        #expect(summaries[0x2000]?.memoryEffect == memory)
        CalleeRegisterSummary.closeOverCalls(&summaries, cap: 0) { _, _, _, _ in nil }
        #expect(summaries[0x2000]?.memoryEffect == memory)
    }

    @Test func productionSummaryRefinementUsesBodyMemoryBeforeClosingReads() throws {
        let caller = try Self.body([0xd10083ff, 0xf90007f4, 0xaa1f03f4, 0x910023e0,
            0x940003fc, 0xf94007e0, 0x910083ff, 0xd65f03c0])
        let helper = try Self.body([0xd2800169, 0xf9000009, 0xd65f03c0], at: 0x2000)
        let initial = try #require(CalleeRegisterSummary.of(caller, isFunction: { $0 == 0x2000 }))
        #expect(initial.readsSelfRegister)
        var summaries: [UInt64: CalleeRegisterSummary] = [
            0x1000: initial, 0x2000: try #require(CalleeRegisterSummary.of(helper)),
        ]
        var rebuilt: [UInt64] = []
        CalleeRegisterSummary.refineMemory(&summaries) { start, effects in
            rebuilt.append(start)
            return CalleeRegisterSummary.of(caller, calleeEffects: effects, isFunction: { $0 == 0x2000 })
        }
        #expect(rebuilt == [0x1000])
        CalleeRegisterSummary.closeOverReads(&summaries)
        #expect(summaries[0x1000]?.readsSelfRegister == false)
    }
}

import Foundation
import Testing
@testable import SwiftDecompilerCore

struct DurableFrameReachTests {
    private static func body(_ words: [UInt32]) throws -> DisassembledFunction {
        let engine = try #require(CapstoneEngine())
        let bytes = words.flatMap { word in
            (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) }
        }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        let instructions = decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail,
                        callee: .kept($0.controlFlow == .call ? "frame_mutating_helper" : nil))
        }
        return DisassembledFunction(symbol: "_durable_reach_core", demangledName: nil,
            startAddress: 0x1000, instructions: instructions, source: .address)
    }

    @Test func preparedCarrierQueriesKeepPoliciesAndRawTermsDistinct() {
        var dynamicOnly = TraceFrameReach()
        dynamicOnly[.dynamic(-32)] = .unknown
        let evidence = TraceLayoutEvidence(sortedAddressTaken: [-24, -8])
        #expect(dynamicOnly.logicalCount == 1)
        #expect(dynamicOnly.effect(using: evidence, arithmetic: .wrapping).isEmpty)
        var trace = TraceFrameReach()
        trace[.point(-32)] = .immediate(7)
        var right = TraceFrameReach()
        right[.point(-32)] = .unknown
        right[.below(.min)] = .immediate(1)
        trace.formUnion(right)
        #expect(trace[.point(-32)] == .unknown) // payload right-bias, not truthiness
        #expect(trace.logicalCount == 2)
        let effect = trace.effect(using: evidence, arithmetic: .wrapping)
        #expect(effect.mayInvalidate(.init(start: -32, bytes: 8)))
        #expect(!effect.mayInvalidate(.init(start: -24, bytes: 8)))
        var raw = TraceFrameReach()
        raw[.below(.min)] = .unknown
        #expect(!raw.effect(using: evidence, arithmetic: .wrapping).isEmpty) // no interval normalization
        var frozen = FrozenFrameReach()
        frozen[.range(.init(floor: -16, bound: -8))] = ReachPresence()
        let checked = frozen.effect(using: NoFrameQueryEvidence(), arithmetic: .checked)
        let wrapped = frozen.effect(using: NoFrameQueryEvidence(), arithmetic: .wrapping)
        let overflow = FrameMemoryExtent(start: .max - 3, bytes: 8)
        #expect(checked.mayInvalidate(overflow))
        #expect(!wrapped.mayInvalidate(overflow))
        let caller = frozen.effect(using: NoFrameQueryEvidence(), arithmetic: .checked, includingCallerOwned: true)
        #expect(caller.mayInvalidate(.init(start: -4, bytes: 8)))
        #expect(!wrapped.mayInvalidate(.init(start: -4, bytes: 8)))
        #expect(frozen.logicalCount == 1) // query addition never becomes an escape
    }

    @Test func aJoinedEscapeReachesALaterPreservationCallWithoutNewInputs() {
        let clear = Preservation.State(registers: ["sp": .stack(-64)],
            slots: [-48: .incoming(64), -8: .entry("x29")])
        var escaped = clear
        escaped.setRegister("x0", to: .stack(-56))
        escaped.markEscape(["x0"])
        // Escape arose on the RIGHT input. A lost-union mutant cannot pass
        // merely by copying the left input's already-escaped range.
        var joined = clear.merged(with: escaped)
        Preservation.applyCall(CalleeEffect(), inputs: [], to: &joined, clobbersMayAliasStack: false)
        #expect(joined.load(at: -48) == .unknown)
        #expect(joined.load(at: -8) == .entry("x29"))
        var control = clear
        Preservation.applyCall(CalleeEffect(), inputs: [], to: &control, clobbersMayAliasStack: false)
        #expect(control.load(at: -48) == .incoming(64))
        #expect(control.load(at: -8) == .entry("x29"))
    }

    @Test func aBranchEscapeSurvivesTracerJoinAndALaterCall() throws {
        // The first call can retain sp+8, but no value is stored there yet.
        // After the join, store7 and call again with no new frame input.
        // x0 was clobbered by the first call, so no dropped frame register
        // can independently recreate the marker missing from a bad MAY union.
        let words: [UInt32] = [
            0xd10083ff, 0xb4000081, 0x910023e0, 0x940007fd, 0x14000002,
            0xaa1f03e0, 0xd28000e9, 0xf90007e9, 0xaa1f03e0, 0x940007f7,
            0xf94007e0, 0x910083ff, 0xd65f03c0,
        ]
        let function = try Self.body(words)
        let result = ValueTracer().analyze(function, entry: nil)
        #expect(result.exitValues[0x1030] == nil)
        let lastCall = try #require(result.callSites[0x1024])
        #expect(lastCall.arguments == [.immediate(0)])
        #expect(lastCall.stackArguments.isEmpty)
        var noEscape = words
        noEscape[2] = 0xaa1f03e0 // first call receives0 instead of sp+8
        let control = ValueTracer().analyze(try Self.body(noEscape), entry: nil)
        #expect(control.exitValues[0x1030] == .immediate(7))
    }

    @Test func finiteReachFeedsTheActualSelfRegisterReadConsumer() throws {
        // The byte overwrite destroys the must save of x20 but leaves the
        // remaining bytes as MAY self. x29's save bounds a finite escape.
        // sp+8 reaches it; sp+16 touches its upper end and must not read it.
        for (pointer, expected): (UInt32, Bool) in [(0x910023e0, true), (0x910043e0, false)] {
            let function = try Self.body([
                0xd10083ff, 0xf9000ffd, 0xf90007f4, 0xaa1f03f4, 0x390023ff,
                pointer, 0x940007fa, 0x910083ff, 0xd65f03c0,
            ])
            let flow = try #require(Preservation.selfRegisterFlow(
                blocks: function.basicBlocks(), entry: function.startAddress,
                addresses: Set(function.instructions.map(\.address)),
                callEffect: { _ in CalleeEffect() }, callInputs: { _ in ["x0"] }, forwards: { _ in false }))
            #expect(flow.reads == expected)
        }
    }

    @Test func anEarlierJoinedEscapeFeedsALaterSelfReadWithoutAnEarlyRead() throws {
        // No MAY-self slot exists at the first call, so it cannot set reads.
        // Self is spilled only after the branch join; the frozen escape must
        // survive until the second call. A register contains self at the first
        // call, but its explicit input set excludes x20.
        for (pointer, expected): (UInt32, Bool) in [(0x910023e0, true), (0x910043e0, false)] {
            let function = try Self.body([
                0xd10083ff, 0xf9000ffd, 0xb4000081, pointer, 0x940007fc,
                0x14000002, 0xaa1f03e0, 0xf90007f4, 0xaa1f03f4, 0x390023ff,
                0xaa1f03e0, 0x940007f5, 0x910083ff, 0xd65f03c0,
            ])
            let blocks = function.basicBlocks()
            for reversed in [false, true] {
                let traversal: [BasicBlock] = reversed ? blocks.map { block in
                    var reordered = BasicBlock(startAddress: block.startAddress, instructions: block.instructions,
                        successors: Array(block.successors.reversed()))
                    reordered.switchCases = block.switchCases
                    return reordered
                } : blocks
                let flow = try #require(Preservation.selfRegisterFlow(
                    blocks: traversal, entry: function.startAddress,
                    addresses: Set(function.instructions.map(\.address)),
                    callEffect: { _ in CalleeEffect() },
                    callInputs: { $0.address == 0x1010 ? ["x0"] : [] }, forwards: { _ in false }))
                #expect(flow.reads == expected, Comment(rawValue: "reversed=\(reversed)"))
            }
        }
    }
}
